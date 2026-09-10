# Document 12 — Supabase RPC & Database Function Specification

**Product:** Mess Manager
**Document:** Supabase RPC & Database Function Specification
**Version:** 1.0
**Status:** Implementation Specification
**Depends on:** Documents 1–11, especially Schema v2, RLS/Authorization Specification, Calculation Engine & Accounting Specification, Audit/Data Integrity Specification

---

# 1. Purpose

This document defines the PostgreSQL functions exposed through Supabase RPC.

The purpose is to ensure that important business operations are executed as controlled transactions rather than as a collection of independent client-side CRUD requests.

The RPC layer is responsible for:

* authorization
* validation
* cross-table integrity
* transaction boundaries
* concurrency control
* idempotency where required
* audit creation
* state transitions
* accounting calculations
* settlement finalization

The frontend should call these functions rather than attempting to reproduce business rules locally.

---

# 2. RPC Design Philosophy

The API exposed through Supabase should be **command-oriented** for important mutations.

Instead of:

```text
UPDATE expenses ...
UPDATE expense_allocations ...
UPDATE payments ...
```

the application should use:

```text
create_expense(...)
```

or:

```text
update_expense(...)
```

The function becomes the single authority for the operation.

This prevents the frontend from deciding which rows need to change and in what order.

---

# 3. Function Security Model

Every user-facing RPC must determine the caller using the authenticated Supabase context.

Conceptually:

```sql
auth.uid()
```

must be treated as the caller identity.

The client must never provide a trusted argument such as:

```text
actor_user_id
```

for authorization purposes.

If an audit event needs an actor:

```text
actor_user_id = auth.uid()
```

must be determined by the function.

---

# 4. Function Security Levels

Functions fall into three categories.

## Level A — Read-only calculations

Examples:

```text
calculate_period_summary
calculate_member_statement
run_period_integrity_check
```

These may use controlled `SECURITY INVOKER` functions where RLS is sufficient.

---

## Level B — Normal authenticated mutations

Examples:

```text
save_meal_entries
record_payment
create_expense
create_adjustment
```

These must enforce authorization and open-period conditions.

---

## Level C — High-impact privileged transitions

Examples:

```text
approve_join_request
transfer_manager
close_period
reopen_period
finalize_settlement
```

These should generally be implemented as controlled security-definer functions with explicit authorization checks and a tightly controlled `search_path`.

---

# 5. Security-Definer Requirements

Every `SECURITY DEFINER` function must:

* explicitly set its `search_path`
* schema-qualify referenced objects
* validate `auth.uid()`
* explicitly check authorization
* avoid trusting caller-supplied ownership fields
* minimize dynamic SQL
* avoid exposing privileged database functionality indirectly

Example pattern:

```sql
CREATE OR REPLACE FUNCTION private.example(...)
RETURNS ...
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
...
$$;
```

The exact trusted schema arrangement must match the final migration.

---

# 6. Common Function Rules

All mutation functions must:

1. validate the authenticated user
2. validate referenced records
3. validate mess/period relationships
4. validate membership/manager authority
5. validate period status
6. perform the complete operation transactionally
7. create required audit events
8. return a deterministic result
9. fail rather than create an ambiguous state

---

# 7. Standard Error Categories

The application should translate database errors into stable application-level error codes.

Recommended categories:

```text
UNAUTHENTICATED
FORBIDDEN
NOT_FOUND
INVALID_INPUT
PERIOD_CLOSED
PERIOD_NOT_OPEN
INVALID_STATE
CONFLICT
DUPLICATE_OPERATION
INTEGRITY_FAILURE
RECONCILIATION_FAILURE
CLOSURE_BLOCKED
IDEMPOTENCY_CONFLICT
```

The frontend should not depend on PostgreSQL constraint names as its primary error protocol.

---

# 8. Idempotency Contract

Retry-sensitive mutation functions should accept:

```text
p_request_id UUID
```

or an equivalent unique operation identifier.

Examples:

```text
create_expense
record_payment
create_adjustment
approve_join_request
close_period
reopen_period
transfer_manager
```

The function must detect whether the request was already processed.

If the same request ID is submitted again with identical operation semantics, the function should return the existing result rather than execute it twice.

If the same request ID is reused for a materially different request, return:

```text
IDEMPOTENCY_CONFLICT
```

---

# 9. Mess Creation

## Function

```text
create_mess(...)
```

## Purpose

Creates a new mess and initializes the creator as its initial authorized manager/member according to the product onboarding workflow.

## Inputs

Recommended:

```text
p_name TEXT
p_request_id UUID
```

## Rules

* caller must be authenticated
* mess name must be valid
* mess record is created
* creator's profile must exist
* initial membership must be established
* initial join/access state must be valid
* initial manager assignment must be established for the first period or onboarding state according to the selected workflow
* join code generation must use secure server-side randomness

## Transaction

All initial mess/access state must be created atomically.

## Audit

Create:

```text
MESS_CREATED
```

and any associated membership/manager events.

---

# 10. Join Code Creation

## Function

```text
create_join_code(...)
```

## Purpose

Generate a valid join code for a mess.

## Authorization

Mess manager/admin authority as defined by the product.

## Rules

* existing active code should be revoked/expired as required
* new code must be cryptographically unpredictable
* code uniqueness must be enforced
* code must not expose internal IDs

## Audit

```text
JOIN_CODE_CREATED
```

---

# 11. Join Code Regeneration

## Function

```text
regenerate_join_code(...)
```

## Purpose

Invalidate the previous active code and create a new code.

## Transaction

```text
revoke old code
      ↓
generate new code
      ↓
activate new code
      ↓
audit
      ↓
commit
```

There must never be an ambiguity about which code is currently active.

---

# 12. Request to Join Mess

## Function

```text
request_to_join_mess(...)
```

## Inputs

```text
p_join_code TEXT
p_request_id UUID
```

## Rules

* caller must be authenticated
* join code must be valid and active
* caller must not already be a member
* caller must not already have a pending request
* caller must not be blocked from the mess
* request must be created in `PENDING` state

## Audit

```text
JOIN_REQUEST_CREATED
```

---

# 13. Approve Join Request

## Function

```text
approve_join_request(...)
```

## Inputs

```text
p_request_id UUID
p_request_idempotency UUID
```

## Authorization

Caller must have manager authority for the relevant mess/current period according to the membership workflow.

## Validation

Verify:

* request exists
* request belongs to caller's authorized mess
* request is still pending
* requesting user is not already an active member
* current period state is valid

## Operation

Atomically:

```text
lock join request
       ↓
verify pending
       ↓
approve request
       ↓
create/update membership
       ↓
audit
       ↓
commit
```

A second concurrent approval must fail safely.

---

# 14. Reject Join Request

## Function

```text
reject_join_request(...)
```

## Inputs

```text
p_request_id UUID
p_reason TEXT
p_request_idempotency UUID
```

## Rules

* manager authority required
* request must be pending
* reason may be required based on product policy
* request becomes rejected
* request remains historically visible

## Audit

```text
JOIN_REQUEST_REJECTED
```

---

# 15. Create Period

## Function

```text
create_period(...)
```

## Inputs

Conceptually:

```text
p_mess_id UUID
p_start_date DATE
p_end_date DATE
p_request_id UUID
```

## Authorization

Existing authorized manager.

## Rules

* caller must belong to mess
* caller must have authority to create the period
* start date must precede end date
* date range must not overlap an existing period
* there must not be another active/open period where prohibited
* manager must be assigned
* period configuration must be initialized

The exclusion constraint remains the final structural protection against overlapping dates.

---

# 16. Open Period

## Function

```text
open_period(...)
```

This may be combined with `create_period()` where the workflow is simple.

If separated, opening verifies all prerequisites before changing:

```text
DRAFT → OPEN
```

---

# 17. Assign Manager

## Function

```text
assign_manager(...)
```

## Inputs

```text
p_period_id UUID
p_period_member_id UUID
p_request_id UUID
```

## Rules

The target user must:

* belong to the relevant period
* be active
* belong to the relevant mess

Only authorized existing manager/admin authority may perform the assignment.

The database must ensure there is no conflicting current manager.

---

# 18. Transfer Manager

## Function

```text
transfer_manager(...)
```

## Inputs

```text
p_period_id UUID
p_new_manager_member_id UUID
p_reason TEXT
p_request_id UUID
```

## Authorization

Current manager or higher authority defined by the product.

## Transaction

```text
lock period
     ↓
verify current manager
     ↓
verify target active member
     ↓
end current manager assignment
     ↓
create new manager assignment
     ↓
audit transfer
     ↓
commit
```

## Audit

At minimum:

```text
MANAGER_TRANSFERRED
```

with previous and new manager identifiers.

---

# 19. End Membership

## Function

```text
end_period_membership(...)
```

## Rules

The function must not rewrite historical periods.

Ending membership affects the selected period only.

It must verify that ending membership does not create an impossible state.

For example, removing the current manager without assigning a replacement should be rejected unless the period is being explicitly closed or transferred according to the business workflow.

---

# 20. Save Meal Entries

## Function

```text
save_meal_entries(...)
```

This is one of the most important high-frequency functions.

## Purpose

Create or update meal entries for one or more members/dates/meal types.

## Recommended Input

A JSONB array or typed composite structure containing entries such as:

```json
[
  {
    "period_member_id": "...",
    "meal_date": "2026-09-10",
    "meal_type_id": "...",
    "quantity": 1
  }
]
```

## Validation

Every row must satisfy:

* caller has manager authority
* period is open
* member belongs to period
* meal type belongs to period
* meal date is within period
* quantity is valid
* duplicate logical meal entry cannot be created

## Transaction

The entire submitted batch should be atomic unless the UI explicitly uses a documented partial-save model.

Recommended V1 behavior:

> Entire batch succeeds or entire batch fails.

## Audit

Each changed logical meal should be auditable, with bulk operation metadata where applicable.

---

# 21. Guest Meal Creation

## Function

```text
create_guest_meal(...)
```

## Inputs

```text
p_period_id UUID
p_host_period_member_id UUID
p_meal_date DATE
p_meal_type_id UUID
p_quantity NUMERIC
p_reason TEXT
p_request_id UUID
```

## Validation

* manager authority required
* period open
* host belongs to period
* meal type belongs to period
* date lies within period
* quantity valid

Guest meal must be clearly distinguishable from the host's own meal.

---

# 22. Guest Meal Update

## Function

```text
update_guest_meal(...)
```

Corrections must preserve audit history.

Changing quantity must produce an audit event.

---

# 23. Void Guest Meal

## Function

```text
void_guest_meal(...)
```

The record remains historically traceable but is excluded from calculation.

---

# 24. Create Expense

## Function

```text
create_expense(...)
```

## Inputs

Conceptually:

```text
p_period_id
p_expense_date
p_category_id
p_description
p_amount
p_accounting_type
p_paid_by_period_member_id
p_allocation_method
p_allocations
p_request_id
```

The exact typed representation may use UUIDs and JSONB for allocation details.

---

# 25. Expense Creation Validation

The function must validate:

### Basic

* period exists
* period is open
* caller is manager
* amount > 0
* accounting type is valid
* date is within period

### Category

* category exists
* category is compatible with accounting type where category rules require it

### Payer

If:

```text
paid_by_period_member_id IS NOT NULL
```

the payer must belong to the same period and be eligible.

### Allocation

If the expense requires member allocation:

* all allocation members belong to period
* no duplicate active member allocations
* allocation method is valid
* values are valid
* total allocation reconciles exactly

---

# 26. Expense Allocation Modes

## NONE

Used only where the accounting model does not require member allocation.

## EQUAL

Function calculates exact allocations.

## WEIGHTED

Function uses supplied weights and calculates exact allocations.

## FIXED

Function validates explicitly supplied amounts.

The client should not be trusted to calculate final monetary allocation values.

The server must recalculate or validate the result.

---

# 27. Largest-Remainder Allocation

For equal/weighted allocations:

1. calculate exact proportional values
2. round according to the monetary precision
3. calculate residual
4. allocate residual deterministically
5. verify final sum equals expense amount

Tie-breaking must be stable.

Recommended tie-breaker:

```text
period_member_id
```

or another immutable deterministic member ordering.

The selected rule must remain fixed within a calculation version.

---

# 28. Expense Update

## Function

```text
update_expense(...)
```

This must be a controlled full business operation.

It must account for changes to:

* amount
* category
* accounting type
* date
* payer
* allocation method
* allocation members
* allocation weights
* fixed allocations

The function must recalculate or replace dependent allocation state consistently.

---

# 29. Expense Void

## Function

```text
void_expense(...)
```

## Inputs

```text
p_expense_id UUID
p_reason TEXT
p_request_id UUID
```

## Rules

* manager authority required
* period must be open
* expense must not already be voided
* void reason should be required
* allocations must become inactive/void according to the schema model
* settlement must exclude the expense

The expense itself remains historically visible.

---

# 30. Record Payment

## Function

```text
record_payment(...)
```

## Inputs

```text
p_period_id
p_period_member_id
p_payment_date
p_amount
p_description
p_request_id
```

## Important distinction

This records:

> Member paid money into the mess.

It does not represent:

> Member paid a vendor for a mess expense.

Vendor payments are represented through `paid_by_period_member_id` and expense advances.

---

# 31. Payment Validation

* period open
* manager authority
* member belongs to period
* amount > 0
* date within period
* idempotency key valid

Payment must be recorded exactly once for a given request ID.

---

# 32. Update Payment

## Function

```text
update_payment(...)
```

Changes must be audited.

If a payment is no longer valid, voiding is preferable to deletion.

---

# 33. Void Payment

## Function

```text
void_payment(...)
```

The payment remains in history but no longer contributes to settlement.

Required:

```text
void_reason
```

---

# 34. Create Adjustment

## Function

```text
create_adjustment(...)
```

## Inputs

```text
p_period_id
p_period_member_id
p_adjustment_type
p_amount
p_reason
p_request_id
```

## Rules

* manager authority
* period open
* member belongs to period
* amount > 0
* type is CREDIT or DEBIT
* reason is mandatory

---

# 35. Void Adjustment

## Function

```text
void_adjustment(...)
```

The adjustment remains visible for history but is removed from active settlement calculation.

---

# 36. Create Opening Balance

## Function

```text
create_opening_balance(...)
```

## Rules

* manager authority
* target member belongs to period
* amount > 0
* direction must be DUE or CREDIT
* opening balance cannot be duplicated where schema semantics permit only one active opening balance

The function must record the source/reason where appropriate.

---

# 37. Update Opening Balance

## Function

```text
update_opening_balance(...)
```

Because opening balance directly affects final settlement, changes must:

* require period open
* be audited
* recalculate settlement
* prevent arbitrary changes after finalization unless the period has been reopened

---

# 38. Calculation Function — Period Summary

## Function

```text
calculate_period_summary(...)
```

## Inputs

```text
p_period_id UUID
```

## Purpose

Calculate current live accounting state.

## Output Concept

```json
{
  "periodId": "...",
  "mealUnits": 100,
  "mealCost": 10000,
  "mealRate": 100,
  "sharedCost": 2000,
  "payments": 3000,
  "expenseAdvances": 11000,
  "adjustments": {
    "credits": 500,
    "debits": 200
  },
  "reconciliation": {
    "passed": true
  },
  "blockers": [],
  "warnings": []
}
```

The actual return type should preferably be a stable PostgreSQL composite/JSON structure.

---

# 39. Member Statement Calculation

## Function

```text
calculate_member_statement(...)
```

## Inputs

```text
p_period_id UUID
p_period_member_id UUID
```

## Output

The canonical result:

```text
meal_units
food_cost
shared_cost
credit_adjustments
debit_adjustments
opening_effect
payments
expense_advances
total_charges
total_credits
final_balance
balance_status
```

---

# 40. Canonical Balance Equation

The function must implement:

```text
Final Balance
=
Opening Effect
+ Food Cost
+ Shared Cost
+ Debit Adjustments
- Credit Adjustments
- Payments
- Expense Advances
```

It must not use a second competing formula elsewhere in the backend.

---

# 41. Expense Advance Calculation

Expense advances must be calculated from valid, non-voided expenses where:

```text
paid_by_period_member_id = target member
```

The advance is:

```text
sum(valid expense amounts paid by member)
```

subject to the defined expense semantics.

Expense advances must not be included in:

```text
meal_rate
```

and must not be counted as:

```text
member payments
```

---

# 42. Meal Cost Calculation

Meal-related expenses are those whose accounting type is:

```text
MEAL_COST
```

The function calculates:

```text
meal_units
meal_cost
meal_rate
```

before member food costs.

---

# 43. Zero-Meal Handling

If:

```text
meal_units = 0
```

then:

```text
meal_rate = NULL
```

when meal expense exists.

Closure must be blocked if:

```text
meal_cost > 0
AND
meal_units = 0
```

If:

```text
meal_cost = 0
AND
meal_units > 0
```

then:

```text
meal_rate = 0
```

is valid.

---

# 44. Food-Cost Allocation Function

For each period member:

```text
food_cost
=
member_meal_units
÷ total_meal_units
× total_meal_cost
```

The implementation must reconcile the member totals exactly with total meal cost.

The final residual method must be deterministic.

---

# 45. Shared-Cost Calculation

For every active shared expense:

```text
sum(member allocations)
=
expense amount
```

The calculation function must not independently reinterpret allocations using a conflicting rule.

Stored allocations become the authoritative allocation result once validated.

---

# 46. Integrity Check Function

## Function

```text
run_period_integrity_check(...)
```

## Purpose

Perform a complete consistency test.

## Checks

At minimum:

* period dates
* manager count
* membership consistency
* meal references
* meal type references
* guest meal references
* expense references
* payer references
* allocation references
* allocation reconciliation
* food-cost reconciliation
* settlement equation
* snapshot consistency
* forbidden closed-period mutations where detectable

## Output

```json
{
  "passed": true,
  "blockers": [],
  "warnings": [],
  "reconciliation": {
    "foodCost": true,
    "allocations": true,
    "balances": true
  }
}
```

---

# 47. Close Period

## Function

```text
close_period(...)
```

This is the most important RPC in the backend.

## Inputs

```text
p_period_id UUID
p_reason TEXT
p_request_id UUID
```

---

# 48. Close-Period Authorization

The caller must:

* be authenticated
* be authorized manager for the specific period
* have an active relationship to the period as required by the authorization model

Current mess manager status alone is insufficient.

---

# 49. Close-Period Transaction

Conceptual sequence:

```text
BEGIN
   ↓
lock period
   ↓
verify period = OPEN
   ↓
run integrity check
   ↓
run closure blocker checks
   ↓
calculate complete settlement
   ↓
verify reconciliation
   ↓
create settlement snapshot
   ↓
create member settlement snapshots
   ↓
mark snapshot FINAL
   ↓
mark period CLOSED
   ↓
write audit events
   ↓
COMMIT
```

If any stage fails:

```text
ROLLBACK
```

No half-closed state is permitted.

---

# 50. Final Snapshot Rules

The close function must create a new snapshot version.

Example:

```text
Version 1
Status = FINAL
```

After a reopen:

```text
Version 1
Status = SUPERSEDED

Version 2
Status = FINAL
```

The implementation must never destroy Version 1 merely because Version 2 exists.

---

# 51. Reopen Period

## Function

```text
reopen_period(...)
```

## Inputs

```text
p_period_id UUID
p_reason TEXT
p_request_id UUID
```

## Authorization

Only the appropriate manager authority may reopen according to product policy.

The function must not allow an ordinary member to invoke reopen.

---

# 52. Reopen Transaction

Conceptually:

```text
BEGIN
   ↓
lock period
   ↓
verify CLOSED
   ↓
verify authorization
   ↓
preserve existing final snapshot
   ↓
mark period OPEN
   ↓
audit reopen
   ↓
COMMIT
```

The existing snapshot remains immutable.

---

# 53. Settlement Finalization

Where separate from `close_period`, use:

```text
finalize_settlement(...)
```

It must:

* calculate
* validate
* reconcile
* write snapshot
* version snapshot
* mark final

A period must not be considered closed merely because some calculation was executed.

---

# 54. Settlement Snapshot Creation

## Function

```text
create_settlement_snapshot(...)
```

This may be internal/private rather than frontend-callable.

Recommended architecture:

```text
close_period()
     ↓
private.create_settlement_snapshot()
```

This prevents the client from manufacturing its own final snapshot.

---

# 55. Settlement Snapshot Authority

For a closed period:

```text
FINAL settlement snapshot
```

is the authoritative historical settlement result.

For an open period:

```text
live calculation
```

is authoritative.

The UI must not mix the two models without clearly distinguishing them.

---

# 56. Historical Statement Function

## Function

```text
get_historical_member_statement(...)
```

For a closed period, this should prefer finalized snapshot data.

It may additionally return source-detail references for authorized users.

---

# 57. Audit Retrieval Function

## Function

```text
get_period_audit_events(...)
```

This should normally be a controlled read function/view rather than unrestricted access to the raw audit table.

Authorization must verify:

* user belongs to the relevant mess
* manager authority where necessary
* historical access rules

Ordinary members should not automatically receive the entire mess audit log.

---

# 58. Pagination

Audit/event retrieval should be paginated.

Do not return thousands of records by default.

Recommended parameters:

```text
p_limit INTEGER
p_cursor TIMESTAMPTZ/UUID
```

or another deterministic cursor strategy.

Offset-only pagination should not be relied upon for large audit histories.

---

# 59. Reporting Functions

The RPC layer may expose read-only reporting helpers such as:

```text
get_dashboard_summary(...)
get_period_financial_summary(...)
get_member_statement(...)
get_member_history(...)
get_recent_expenses(...)
get_recent_payments(...)
```

These must remain read-only.

---

# 60. Read Functions vs Tables

The frontend should not reconstruct complex accounting queries from raw tables when a trusted reporting function/view exists.

For example:

Preferred:

```text
get_member_statement(period_id, member_id)
```

rather than:

```text
fetch meals
fetch expenses
fetch allocations
fetch payments
fetch adjustments
fetch opening balance
calculate everything in JavaScript
```

This avoids duplicated business logic.

---

# 61. Frontend Calculation Policy

The frontend may perform:

* presentation formatting
* optimistic UI hints
* temporary input totals
* form previews

The frontend must not be the authoritative source for:

* meal rate
* food cost
* shared allocation final values
* expense advances
* final balance
* settlement finalization

---

# 62. RPC Return Shape

Mutation functions should return enough information for the frontend to update itself without unnecessary repeated queries.

Example:

```json
{
  "success": true,
  "operation": "record_payment",
  "record_id": "...",
  "period_id": "...",
  "member_id": "...",
  "amount": 2000
}
```

For more complex operations:

```json
{
  "success": true,
  "operation": "close_period",
  "period_id": "...",
  "snapshot_id": "...",
  "snapshot_version": 2,
  "status": "CLOSED"
}
```

Exact return structures should be standardized during implementation.

---

# 63. No Ambiguous Null Semantics

RPC responses should distinguish:

```text
not applicable
```

from:

```text
zero
```

Example:

```text
meal_rate = null
```

when calculation is undefined due to zero meal units.

This is not equivalent to:

```text
meal_rate = 0
```

---

# 64. Bulk Meal Entry Optimization

Meal entry is likely the highest-frequency manager operation.

The function should support batch writes rather than forcing one RPC call per meal.

Preferred:

```text
save_meal_entries([...many entries...])
```

rather than:

```text
save_meal()
save_meal()
save_meal()
...
```

This reduces latency and simplifies transaction handling.

---

# 65. Bulk Expense Allocation

An expense creation request may carry allocation details in one payload.

For example:

```json
{
  "allocation_method": "EQUAL",
  "members": ["A", "B", "C", "D"]
}
```

The server calculates actual allocation values.

For weighted:

```json
{
  "allocation_method": "WEIGHTED",
  "members": [
    {"member_id": "A", "weight": 2},
    {"member_id": "B", "weight": 1}
  ]
}
```

The server calculates the resulting money values.

---

# 66. Fixed Allocation Validation

For fixed allocation:

```json
{
  "allocation_method": "FIXED",
  "allocations": [
    {"member_id": "A", "amount": 400},
    {"member_id": "B", "amount": 600}
  ]
}
```

The server must verify:

```text
400 + 600 = expense amount
```

A mismatch must reject the transaction.

---

# 67. Period Lock Helper

A private helper should centralize open-period validation.

Conceptually:

```text
assert_period_open(period_id)
```

It must:

* locate period
* verify status
* return failure if not OPEN

All accounting mutation functions should use equivalent centralized logic.

---

# 68. Manager Authorization Helper

Use a private helper conceptually equivalent to:

```text
assert_period_manager(period_id, auth.uid())
```

It should verify:

* caller authenticated
* period exists
* caller has current manager assignment for that period

This avoids slightly different manager checks across functions.

---

# 69. Period Membership Helper

Use:

```text
assert_period_member(period_id, period_member_id)
```

to verify:

* member belongs to selected period
* membership is valid for the operation
* member/mess relationship matches period

---

# 70. Same-Period Validation

Every function accepting multiple period-scoped IDs must verify they refer to the same period.

Examples:

```text
expense + payer
expense + allocation
meal + member
guest meal + host
payment + member
adjustment + member
opening balance + member
```

No client-supplied UUID combination should be assumed valid.

---

# 71. Cross-Mess Protection

Every operation must prevent combinations such as:

```text
Mess A period
+
Mess B member
```

Even if both records are otherwise valid.

This must be enforced by relational validation, not just frontend filtering.

---

# 72. Self-Approval Protection

The join approval function must not accidentally allow a user to approve their own request.

Where product rules forbid it:

```text
request.requested_by = auth.uid()
```

must result in:

```text
FORBIDDEN
```

unless the product explicitly defines self-service approval for a special workflow.

---

# 73. Manager Removal Protection

The system must prevent a manager from leaving a period in an invalid state.

Example:

```text
one current manager
↓
manager removed
↓
zero managers
```

If replacement is required, the operation must assign the replacement atomically.

---

# 74. Transaction Boundary Rule

One logical business command should correspond to one database transaction.

For example:

```text
create_expense()
```

must not be implemented as:

```text
INSERT expense
COMMIT

INSERT allocations
COMMIT

INSERT audit
COMMIT
```

because a failure between operations creates partial state.

Instead:

```text
BEGIN
INSERT expense
INSERT allocations
INSERT audit
COMMIT
```

---

# 75. Trigger vs RPC Responsibilities

Triggers should enforce universal invariants.

RPCs should implement business workflows.

### Trigger examples

* `updated_at`
* audit capture
* immutable audit events
* closed-period mutation guard where appropriate
* row-level structural integrity

### RPC examples

* approve request
* transfer manager
* create expense with allocations
* close period
* reopen period
* calculate/finalize settlement

Complex business workflows should not be hidden in unrelated triggers.

---

# 76. Avoid Trigger Recursion

Audit triggers must not recursively audit the audit table itself.

Likewise, triggers must not create mutation loops such as:

```text
expense update
→ audit insert
→ expense update
→ audit insert
→ ...
```

Audit tables and functions should be explicitly excluded from unrelated generic triggers.

---

# 77. Privilege Grants

After creating RPCs:

* authenticated users should receive `EXECUTE` only for functions intended for them
* internal/private functions should not be exposed to `authenticated`
* sensitive functions should not be callable anonymously
* service-role access should not be used as a substitute for authorization

Function grants should be part of the migration.

---

# 78. Function Search Path Hardening

For security-definer functions, do not rely on default search-path resolution.

Prefer fully qualified references such as:

```sql
public.periods
private.assert_period_manager(...)
```

This protects against object-shadowing issues.

---

# 79. SQL Injection Protection

RPCs should prefer typed parameters and ordinary SQL.

Dynamic SQL should be avoided unless genuinely necessary.

Where dynamic SQL is unavoidable:

* values must be parameterized
* identifiers must be safely quoted
* caller input must never be concatenated directly into executable SQL

---

# 80. Performance Requirements

RPCs should minimize unnecessary round trips.

For common operations:

### Meals

Batch writes.

### Expense

Create expense + allocations in one transaction.

### Payment

Single transaction.

### Settlement

One calculation transaction rather than hundreds of client queries.

### Close

One controlled database transaction.

---

# 81. Large-Period Calculation

A period may eventually contain many meal records.

The calculation engine must operate set-wise using SQL where practical.

Avoid row-by-row procedural loops for large collections unless required.

Prefer:

```text
SUM()
GROUP BY
JOIN
CTE
window functions
```

where they provide correct deterministic behavior.

---

# 82. Calculation Performance Rule

Calculation correctness has priority over micro-optimization.

Do not denormalize financial totals into mutable columns merely to make the dashboard faster unless there is a measured need.

Initially, trusted views/functions should be preferred.

If caching is introduced later, the cache must never become an independent accounting source of truth.

---

# 83. Settlement Snapshot as Performance Boundary

Finalized snapshots naturally provide an efficient historical read path.

For closed periods:

```text
snapshot → statement
```

can be much faster than recalculating the entire period on every historical page load.

The source records remain necessary for audit and explanation.

---

# 84. Recalculation After Mutation

For an open period, accounting summaries should be recalculated after relevant mutations.

Relevant mutations include:

* meal
* guest meal
* meal expense
* shared expense
* payment
* expense advance
* adjustment
* opening balance

The system need not physically update every member's balance column if the balance is derived.

A trusted summary query/function is sufficient.

---

# 85. No Derived-Balance Storage in V1

Unless performance testing proves otherwise, V1 should avoid a mutable:

```text
member.current_balance
```

column as an accounting source.

Instead:

```text
source records
+
calculation function
→
balance
```

For closed periods:

```text
final snapshot
→
balance
```

This reduces synchronization bugs.

---

# 86. Correction Workflow

A typical correction should be:

```text
Open period
   ↓
Manager identifies incorrect source
   ↓
RPC validates correction
   ↓
Source record updated/voided
   ↓
Dependent allocations corrected if necessary
   ↓
Audit created
   ↓
Live calculation changes
```

There should be no separate "rebuild balances manually" operation.

---

# 87. Expense Payer Change Workflow

Changing:

```text
paid_by_period_member_id
```

must recalculate expense advance responsibility.

Example:

```text
Before:
A paid 1000

After:
B paid 1000
```

The resulting expense allocation may remain unchanged, but:

```text
A expense advance: -1000 → 0
B expense advance: 0 → -1000
```

This is a material accounting mutation and must be audited.

---

# 88. Accounting-Type Change Workflow

Changing:

```text
MEAL_COST
```

to:

```text
SHARED_NON_MEAL
```

can materially change the entire period.

Therefore the server must:

* validate new allocation requirements
* update allocation state
* exclude/include expense in appropriate calculation
* recalculate meal rate
* recalculate member balances
* audit the change

---

# 89. Allocation-Method Change Workflow

Changing:

```text
EQUAL
```

to:

```text
WEIGHTED
```

must not leave stale allocation rows.

The operation must atomically replace or update allocations and ensure:

```text
allocation sum = expense amount
```

---

# 90. Closed-Period Mutation Rejection

Every relevant mutation must reject:

```text
period.status = CLOSED
```

with a stable application error such as:

```text
PERIOD_CLOSED
```

The only ordinary exceptions are explicit:

```text
reopen_period
```

and approved administrative recovery operations.

---

# 91. Reopen Does Not Rewrite History

Reopening a period must not mutate the old final snapshot.

Instead:

```text
Snapshot 1
    ↓
superseded

Source records corrected
    ↓
Snapshot 2
    ↓
final
```

---

# 92. Audit and RPC Atomicity

For a command such as:

```text
record_payment()
```

the transaction must contain:

```text
payment insert
+
audit event
```

For:

```text
transfer_manager()
```

the transaction must contain:

```text
old assignment update
+
new assignment insert
+
audit
```

For:

```text
close_period()
```

the transaction must contain:

```text
validation
+
calculation
+
snapshot
+
period status change
+
audit
```

---

# 93. RPC Testing Matrix

Every function must receive:

### Happy-path test

Valid authenticated manager request succeeds.

### Authentication test

Anonymous request fails.

### Authorization test

Member attempting manager operation fails.

### Cross-mess test

IDs from unrelated mess fail.

### Cross-period test

IDs from unrelated periods fail.

### Closed-period test

Mutation fails.

### Duplicate/retry test

Same idempotency key does not duplicate the operation.

### Concurrency test

Concurrent requests cannot break invariants.

### Audit test

Required audit events are produced.

---

# 94. Golden RPC Tests

At minimum, test this sequence end-to-end:

```text
create mess
    ↓
create/open period
    ↓
add/approve members
    ↓
assign manager
    ↓
create meal types
    ↓
save meals
    ↓
create food expense
    ↓
create shared expense
    ↓
record vendor payer
    ↓
record member payment
    ↓
create adjustment
    ↓
calculate statement
    ↓
run integrity check
    ↓
close period
    ↓
read final snapshot
```

Then:

```text
reopen
    ↓
correct source record
    ↓
recalculate
    ↓
close again
    ↓
verify snapshot version 2
    ↓
verify snapshot version 1 still exists
```

---

# 95. Recommended Internal Function Layer

A clean implementation should have private helpers roughly corresponding to:

```text
private.current_actor()
private.assert_authenticated()
private.assert_mess_member()
private.assert_period_manager()
private.assert_period_open()
private.assert_period_member()
private.assert_same_period()
private.assert_same_mess()
private.generate_join_code()
private.allocate_equal()
private.allocate_weighted()
private.validate_fixed_allocations()
private.calculate_food_costs()
private.calculate_shared_costs()
private.calculate_member_balance()
private.run_period_integrity_check()
private.create_audit_event()
private.get_or_create_idempotency_result()
private.lock_period()
```

These are implementation concepts, not necessarily all public RPCs.

---

# 96. Public RPC Surface — Recommended V1

The frontend-facing mutation API should remain relatively small:

```text
create_mess
create_join_code
regenerate_join_code

request_to_join_mess
approve_join_request
reject_join_request

create_period
open_period
assign_manager
transfer_manager
end_period_membership

save_meal_entries
create_guest_meal
update_guest_meal
void_guest_meal

create_expense
update_expense
void_expense

record_payment
update_payment
void_payment

create_adjustment
void_adjustment

create_opening_balance
update_opening_balance
void_opening_balance

close_period
reopen_period
```

Read/calculation surface:

```text
calculate_period_summary
calculate_member_statement
run_period_integrity_check
get_historical_member_statement
get_period_audit_events
```

The exact final names may be normalized before migration.

---

# 97. Functions That Should Remain Internal

The following should generally not be directly callable by ordinary clients:

```text
create_settlement_snapshot
allocate_equal
allocate_weighted
calculate_food_costs
calculate_member_balance
assert_period_manager
assert_period_open
create_audit_event
lock_period
```

These should exist behind trusted public commands where possible.

---

# 98. Final RPC Architecture

The intended flow is:

```text
Frontend
   │
   ▼
Supabase RPC
   │
   ├── Authenticate caller
   ├── Authorize operation
   ├── Validate identifiers
   ├── Validate period state
   ├── Validate business rules
   ├── Lock required records
   ├── Perform mutation
   ├── Recalculate/reconcile
   ├── Write audit event
   └── Commit
          │
          ▼
      PostgreSQL
```

The frontend should receive the final trusted result rather than independently determining what happened.

---

# 99. Implementation Standard

The final RPC migration must satisfy all of the following:

```text
[ ] No client-supplied actor identity is trusted
[ ] Authorization is checked inside the function
[ ] Cross-period IDs are validated
[ ] Cross-mess IDs are validated
[ ] Closed periods are protected
[ ] Financial mutations are transactional
[ ] Audit events are atomic with mutations
[ ] Retry-sensitive operations support idempotency
[ ] Expense allocations reconcile exactly
[ ] Expense advances are correctly calculated
[ ] Payments remain distinct from expense advances
[ ] Meal rate is never manually stored as authoritative input
[ ] Final balances are derived
[ ] Settlement snapshots are versioned
[ ] Reopen preserves previous snapshots
[ ] Concurrency is controlled
[ ] Privileged functions are hardened
[ ] Function grants are restricted
[ ] Error categories are stable
[ ] Tests cover negative cases
```

---

# 100. Final Decision

The backend command model is now defined.

The authoritative pattern is:

```text
UI action
   ↓
Public RPC
   ↓
Authorization
   ↓
Validation
   ↓
Transaction
   ↓
Mutation
   ↓
Calculation / reconciliation
   ↓
Audit
   ↓
Trusted result
```

The database remains the accounting authority.

The next implementation layer should therefore convert this specification into the actual **Supabase Function/RPC Migration**, including:

* private authorization helpers
* public RPC functions
* exact SQL parameters and return types
* security-definer configuration
* grants
* idempotency handling
* calculation functions
* period locking
* settlement finalization
* audit integration
* error codes
* database-level tests
