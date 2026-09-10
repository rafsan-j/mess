# Mess Manager — Supabase RPC & API Contract V1

## 1. Purpose

This document defines the application-facing contract between the Mess Manager frontend and the Supabase PostgreSQL backend.

The frontend must not implement accounting rules independently. It submits validated user intent to controlled database functions, and the database performs authorization, validation, mutation, and accounting calculations atomically.

The architectural rule is:

> **Frontend requests an operation → RPC validates authorization and state → database performs the mutation → database records the audit event → RPC returns the authoritative result.**

Direct client-side mutation of high-risk accounting tables is prohibited.

---

# 2. API Architecture

The application uses three categories of database interfaces.

## 2.1 Read interfaces

Used for retrieving data.

Examples:

* current period
* members
* meals
* expenses
* payments
* statements
* settlement
* history
* audit records

Read interfaces may be implemented through RLS-protected tables/views or dedicated read functions.

---

## 2.2 Mutation RPCs

Used for operations that modify application state.

Examples:

* create mess
* request membership
* approve member
* create period
* assign manager
* save meals
* create expense
* record payment
* create adjustment
* close period
* reopen period

These functions are the authoritative mutation boundary.

---

## 2.3 Calculation/reporting RPCs

Used to calculate financial results.

Examples:

* period summary
* member statement
* settlement preview
* reconciliation

Calculation functions must use the same canonical accounting engine used during period closure.

---

# 3. General RPC Rules

Every public RPC must:

1. Require an authenticated Supabase user where authentication is applicable.
2. Determine the caller from `auth.uid()`.
3. Never trust a client-supplied `user_id` for authorization.
4. Verify mess/period membership server-side.
5. Verify manager status server-side.
6. Verify period state server-side.
7. Validate all dates against the owning period.
8. Validate all referenced records belong to the same mess/period.
9. Perform the complete mutation inside one database transaction.
10. Create the corresponding audit event.
11. Return authoritative database-generated values.
12. Reject unauthorized operations rather than silently ignoring them.
13. Never expose service-role credentials.
14. Use fixed `search_path` for security-definer functions.
15. Use explicit exception codes/messages suitable for frontend handling.

---

# 4. Standard Error Categories

RPCs should use consistent PostgreSQL exception categories.

Recommended application error codes:

| Code                    | Meaning                                                |
| ----------------------- | ------------------------------------------------------ |
| `AUTH_REQUIRED`         | No authenticated user                                  |
| `FORBIDDEN`             | User lacks permission                                  |
| `NOT_MEMBER`            | User is not a member of the relevant mess/period       |
| `NOT_MANAGER`           | User is not the current manager                        |
| `NOT_FOUND`             | Requested record does not exist or is inaccessible     |
| `INVALID_STATE`         | Operation is incompatible with current state           |
| `PERIOD_CLOSED`         | Closed period cannot be modified                       |
| `INVALID_DATE`          | Date lies outside the period                           |
| `INVALID_AMOUNT`        | Amount is invalid                                      |
| `INVALID_REFERENCE`     | Referenced object belongs to another mess/period       |
| `DUPLICATE`             | Operation conflicts with an existing unique record     |
| `RECONCILIATION_FAILED` | Accounting totals do not reconcile                     |
| `IDEMPOTENCY_CONFLICT`  | Same request identifier was reused with different data |
| `VALIDATION_ERROR`      | General input validation failure                       |

The frontend should display human-readable messages while logging the machine-readable error code.

---

# 5. Authentication Boundary

Supabase Auth owns identity.

Application tables reference:

```text
auth.users.id
```

The application profile is stored in:

```text
public.profiles
```

The backend must never accept arbitrary identity claims such as:

```text
is_manager = true
role = manager
user_id = <another user's ID>
```

as authoritative.

Manager status comes from:

```text
manager_assignments
```

within a specific period.

---

# 6. Mess Lifecycle RPCs

## 6.1 `create_mess`

Creates a new mess and establishes the authenticated user as its initial manager.

### Input

```text
p_name text
p_description text nullable
```

### Preconditions

* authenticated user exists
* name is non-empty
* user is not required to belong to another mess

### Behavior

Creates:

1. `messes`
2. initial `mess_join_codes`
3. initial membership/period state as defined by onboarding workflow

The creator becomes the initial manager when the first period is created.

### Returns

```text
mess_id
mess_name
join_code
```

---

# 7. Join Workflow

## 7.1 `request_to_join_mess`

### Input

```text
p_join_code text
```

### Behavior

1. Resolve active join code.
2. Resolve associated mess.
3. Verify caller is not already an active member.
4. Verify caller does not already have a pending request.
5. Create pending join request.
6. Create audit event.

### Returns

```text
join_request_id
mess_id
status
created_at
```

---

## 7.2 `approve_join_request`

Manager-only.

### Input

```text
p_join_request_id uuid
```

### Validation

* caller is current manager of the relevant period/mess
* request exists
* request is `PENDING`
* requester is not already active
* current period is not closed if membership modification would affect accounting

### Behavior

1. Approve request.
2. Create the appropriate period membership.
3. Record audit event.

Historical periods must not be retroactively changed.

### Returns

```text
join_request_id
member_user_id
period_member_id
status
```

---

## 7.3 `reject_join_request`

Manager-only.

### Input

```text
p_join_request_id uuid
```

### Returns

```text
join_request_id
status = REJECTED
```

---

# 8. Period Lifecycle

## 8.1 `create_period`

Manager-only.

### Input

```text
p_mess_id uuid
p_start_date date
p_end_date date
p_name text nullable
```

### Validation

* caller has authority over the mess
* start date <= end date
* no overlapping period
* no conflicting OPEN period
* all required configuration is valid

### Behavior

Creates:

* period
* period membership snapshot
* manager assignment
* meal types/configuration

Membership is copied into the new period as historical configuration.

### Returns

```text
period_id
status
start_date
end_date
```

---

# 9. Manager Assignment

## 9.1 `assign_manager`

Manager-only or authorized period administration.

### Input

```text
p_period_id uuid
p_period_member_id uuid
```

### Validation

The target user must:

* belong to the same period
* have active membership

### Behavior

Creates manager assignment.

There must be exactly one current manager for an OPEN period.

---

## 9.2 `transfer_manager`

### Input

```text
p_period_id uuid
p_new_manager_period_member_id uuid
```

### Transaction

The operation must atomically:

1. End the current manager assignment.
2. Validate the new manager.
3. Create the new manager assignment.
4. Record audit events.

There must never be an observable intermediate state with two current managers.

### Returns

```text
previous_manager_period_member_id
new_manager_period_member_id
effective_at
```

---

# 10. Meal Entry API

## 10.1 `save_meal_entries`

Manager-only.

This is the primary meal-grid mutation RPC.

### Input

```text
p_period_id uuid

p_entries jsonb
```

Example conceptual payload:

```json
[
  {
    "period_member_id": "...",
    "meal_date": "2026-09-10",
    "meal_type_id": "...",
    "quantity": 1
  },
  {
    "period_member_id": "...",
    "meal_date": "2026-09-10",
    "meal_type_id": "...",
    "quantity": 0
  }
]
```

### Validation

For every entry:

* period exists
* caller is manager
* period is editable
* member belongs to period
* meal type belongs to period
* date lies within period
* quantity >= 0
* quantity satisfies configured precision/range

### Behavior

Uses upsert semantics for the logical meal key.

The database recalculates affected financial results dynamically.

### Returns

```text
saved_count
updated_count
deleted_count
period_id
```

---

# 11. Guest Meal API

## 11.1 `create_guest_meal`

Manager-only.

### Input

```text
p_period_id uuid
p_meal_date date
p_meal_type_id uuid
p_guest_name text nullable
p_quantity numeric
p_weight numeric
p_note text nullable
```

### Validation

Guest meals must:

* belong to the period
* use a valid period meal type
* have a valid date
* have positive quantity/weight where applicable

### Returns

```text
guest_meal_id
meal_date
quantity
weight
```

---

# 12. Expense API

## 12.1 `create_expense`

Manager-only.

### Input

```text
p_period_id uuid
p_expense_date date
p_category_id uuid
p_description text
p_amount numeric
p_accounting_type expense_accounting_type
p_paid_by_period_member_id uuid nullable
p_allocation_method allocation_method
p_allocations jsonb nullable
p_note text nullable
```

### Validation

* amount > 0
* category belongs to mess
* payer belongs to period
* expense date lies inside period
* accounting type is valid
* allocation method matches accounting type
* fixed allocations sum exactly to expense amount
* weighted allocations have valid weights
* equal allocation has at least one eligible member

### Important

`paid_by_period_member_id` represents the member who advanced money to the vendor.

It is **not** equivalent to a payment into the mess.

### Returns

```text
expense_id
amount
allocation_method
allocated_total
expense_advance
```

---

# 13. Shared Expense Update

## 13.1 `update_shared_expense`

Manager-only.

### Input

```text
p_expense_id uuid
p_description text nullable
p_amount numeric
p_allocation_method allocation_method
p_allocations jsonb nullable
p_paid_by_period_member_id uuid nullable
```

### Rules

Only editable expenses may be changed.

The operation must preserve accounting integrity.

If an expense has already influenced a closed settlement, the period cannot be modified.

Material changes must be represented in the audit history.

---

# 14. Expense Void

## 14.1 `void_expense`

Manager-only.

### Input

```text
p_expense_id uuid
p_reason text
```

### Behavior

The original expense record remains preserved.

It becomes void/non-effective rather than being physically deleted.

All dependent calculations exclude the voided expense.

### Returns

```text
expense_id
voided_at
void_reason
```

---

# 15. Payment API

## 15.1 `record_payment`

Manager-only.

### Input

```text
p_period_id uuid
p_period_member_id uuid
p_payment_date date
p_amount numeric
p_method text nullable
p_reference text nullable
p_note text nullable
p_idempotency_key text
```

### Validation

* payer/member belongs to period
* date lies inside period
* amount > 0
* period editable
* idempotency key is valid

### Behavior

Creates a payment into the mess account.

A payment reduces the member's outstanding balance.

It does **not** affect:

* meal rate
* food expense total
* meal units

---

# 16. Payment Void

## 16.1 `void_payment`

Manager-only.

### Input

```text
p_payment_id uuid
p_reason text
```

The original payment remains preserved and becomes void.

The accounting engine automatically removes its financial effect.

---

# 17. Adjustment API

## 17.1 `create_adjustment`

Manager-only.

### Input

```text
p_period_id uuid
p_period_member_id uuid
p_type adjustment_type
p_amount numeric
p_reason text
```

### Rules

Amount must be positive.

A:

```text
CREDIT
```

reduces what the member owes.

A:

```text
DEBIT
```

increases what the member owes.

### Returns

```text
adjustment_id
type
amount
```

---

## 17.2 `void_adjustment`

Manager-only.

### Input

```text
p_adjustment_id uuid
p_reason text
```

Original record is retained.

---

# 18. Opening Balance API

## 18.1 `create_opening_balance`

Manager-only.

### Input

```text
p_period_id uuid
p_period_member_id uuid
p_direction balance_direction
p_amount numeric
p_source_period_id uuid nullable
p_note text nullable
```

### Rules

A source period, when supplied, must belong to the same mess.

Opening balance effect:

```text
DUE     -> positive
CREDIT  -> negative
```

Opening balances must never be silently inherited from the current membership state.

---

# 19. Period Summary

## 19.1 `calculate_period_summary`

Authenticated read.

### Input

```text
p_period_id uuid
```

### Output

Conceptual structure:

```json
{
  "period_id": "...",
  "meal_units": 123.5,
  "meal_cost": 18500.00,
  "meal_rate": 149.79757085,
  "shared_cost": 4200.00,
  "payments": 16000.00,
  "expense_advances": 18500.00,
  "adjustments": {
    "credits": 500.00,
    "debits": 200.00
  },
  "opening_balance_effect": 0.00,
  "final_member_balance_total": 0.00,
  "reconciliation": {
    "passed": true,
    "difference": 0.00
  },
  "blockers": [],
  "warnings": []
}
```

The actual database type may be a composite result or JSONB depending on implementation preference.

---

# 20. Member Statement

## 20.1 `calculate_member_statement`

### Input

```text
p_period_id uuid
p_period_member_id uuid nullable
```

For an ordinary member, the backend must ignore attempts to request another member's private statement.

A manager may request statements for all members.

### Output

```text
meal_units
food_cost
shared_cost
credit_adjustments
debit_adjustments
opening_balance_effect
payments
expense_advances
total_charges
total_credits
final_balance
balance_status
```

---

# 21. Canonical Balance Formula

For every member:

```text
opening_balance_effect
+ food_cost
+ shared_cost
+ debit_adjustments
- credit_adjustments
- payments
- expense_advances
= final_balance
```

Where:

```text
final_balance > 0
    => DUE

final_balance = 0
    => SETTLED

final_balance < 0
    => CREDIT
```

The frontend must never recreate this formula as an alternative source of truth.

---

# 22. Settlement Preview

## 22.1 `calculate_settlement_preview`

### Input

```text
p_period_id uuid
```

### Output

Must contain:

* total meal units
* meal-related expenses
* meal rate
* shared expenses
* allocation totals
* payments
* expense advances
* adjustments
* opening balances
* member balances
* reconciliation status
* blockers
* warnings

The result must be deterministic for the same underlying database state.

---

# 23. Period Close

## 23.1 `close_period`

Manager-only.

### Input

```text
p_period_id uuid
p_confirmation_token text
```

The confirmation token is not a security credential. It is a UX-level acknowledgement generated by the application workflow.

### Pre-close validation

The database must verify:

1. caller is current manager
2. period is OPEN
3. period has valid membership
4. manager assignment is valid
5. all accounting dates are valid
6. all expenses have valid allocations
7. fixed allocations reconcile
8. weighted allocations have valid weights
9. meal-related expenses reconcile
10. meal rate is computable where required
11. no blocking accounting errors exist
12. member balance totals reconcile
13. snapshot can be generated successfully

### Behavior

Inside one transaction:

1. calculate final settlement
2. create immutable settlement snapshot
3. create member settlement snapshots
4. mark period CLOSED
5. record audit event

### Returns

```text
period_id
settlement_snapshot_id
calculation_version
closed_at
reconciliation_passed
```

---

# 24. Reopen Period

## 24.1 `reopen_period`

Manager-only/high-risk operation.

### Input

```text
p_period_id uuid
p_reason text
```

### Validation

* period is CLOSED
* caller has appropriate manager/admin authority
* reason is non-empty

### Behavior

1. Preserve previous final settlement snapshot.
2. Mark it superseded when a new settlement becomes authoritative.
3. Reopen the period.
4. Record audit event.
5. Require explicit re-close before a new final snapshot becomes authoritative.

Old snapshots remain historically available.

---

# 25. Historical Settlement Retrieval

## 25.1 `get_settlement_history`

### Input

```text
p_period_id uuid
```

Returns all settlement snapshot versions in chronological order.

Example:

```text
Version 1 — FINAL — closed Aug 31
Version 2 — SUPERSEDED — reopened Sep 2
Version 3 — FINAL — reclosed Sep 3
```

Only the current final snapshot is authoritative for the period's latest closed state.

Historical versions remain immutable.

---

# 26. Audit API

## 26.1 `get_audit_events`

Manager-authorized.

### Input

```text
p_period_id uuid
p_limit integer
p_offset integer
```

Returns:

```text
event_id
actor_user_id
event_type
entity_type
entity_id
occurred_at
metadata
```

Audit data must not expose unnecessary private information.

---

# 27. Read Interfaces

The frontend may use RLS-protected reads for low-risk data.

Examples:

```text
profiles
periods
period_members
period_meal_types
meals
guest_meals
expenses
expense_allocations
payments
adjustments
```

However, financial summaries should preferably come from canonical reporting functions/views rather than duplicated frontend calculations.

---

# 28. Recommended Reporting Views

The backend should expose views such as:

```text
current_period_manager
active_period_members
period_financial_summary
period_member_summary
current_settlement
```

All exposed views must be reviewed for:

* RLS behavior
* `security_invoker`
* cross-mess leakage
* former-member access
* closed-period history

---

# 29. Idempotency

All operations vulnerable to duplicate submission should support idempotency.

At minimum:

```text
record_payment
create_expense
create_adjustment
close_period
```

should have an idempotency strategy.

Recommended approach:

```text
idempotency_key
+
authenticated_user
+
operation_type
```

must uniquely identify a request.

A retry with the same key and identical payload returns the original result.

A retry with the same key but different payload fails with:

```text
IDEMPOTENCY_CONFLICT
```

This protects against:

* double taps
* mobile retries
* browser retries
* network timeout followed by retry
* duplicate form submissions

---

# 30. Concurrency

The database must protect operations against concurrent managers or duplicate requests.

Important operations requiring row locking or equivalent transactional protection:

```text
approve_join_request
transfer_manager
create_period
save_meal_entries
create/update/void expense
record/void payment
close_period
reopen_period
```

Period lifecycle operations must lock the relevant period row before changing its state.

---

# 31. Transaction Requirements

A mutation RPC must either:

```text
COMMIT
```

all of its intended changes,

or:

```text
ROLLBACK
```

everything.

For example, `close_period` must never produce:

```text
period = CLOSED
snapshot = missing
audit event = missing
```

Likewise, `transfer_manager` must never leave:

```text
old manager = ended
new manager = missing
```

as a committed intermediate state.

---

# 32. Accounting Calculation Pipeline

The canonical calculation engine should follow this sequence:

```text
1. Identify period
        ↓
2. Load historical period configuration
        ↓
3. Load active/non-voided meals
        ↓
4. Calculate chargeable meal units
        ↓
5. Load non-voided meal-related expenses
        ↓
6. Calculate meal rate
        ↓
7. Calculate member food costs
        ↓
8. Load shared expenses
        ↓
9. Calculate allocations
        ↓
10. Load adjustments
        ↓
11. Load opening balances
        ↓
12. Load member payments
        ↓
13. Calculate expense advances
        ↓
14. Calculate final member balances
        ↓
15. Reconcile totals
        ↓
16. Return result
```

The same engine must power:

```text
dashboard
statement
settlement preview
period close
settlement snapshot
```

---

# 33. Exact-Reconciliation Requirement

The calculation engine must guarantee:

```text
SUM(member food costs)
=
total meal-related expense
```

and:

```text
SUM(expense allocations)
=
expense amount
```

and:

```text
SUM(member final balances)
=
0
```

for a fully self-contained period where opening balances are internally balanced.

If an invariant fails, the operation must fail or expose a blocking reconciliation error.

The system must never silently hide a one-cent/paisa residual.

---

# 34. Rounding

Money calculations must use PostgreSQL:

```text
numeric
```

rather than floating-point types.

Where proportional allocation produces fractions smaller than the currency precision, the system uses deterministic residual allocation.

Recommended algorithm:

```text
1. Calculate exact proportional values.
2. Round each value to currency precision.
3. Calculate residual.
4. Distribute residual deterministically.
5. Verify final total exactly equals source amount.
```

Tie-breaking must be stable, such as:

```text
period_member_id
```

or another immutable ordering key.

---

# 35. Expense Advance Treatment

The calculation engine must distinguish:

### Vendor advance

```text
member pays vendor directly
```

from:

### Mess payment

```text
member pays money into mess
```

Example:

```text
Internet expense = 1000
4 members
A pays vendor
```

Allocation:

```text
A +250
B +250
C +250
D +250
```

Expense advance:

```text
A -1000
```

Net:

```text
A -750
B +250
C +250
D +250
```

Total:

```text
0
```

If A subsequently pays 750 into the mess, that is a separate payment and must be recorded separately.

---

# 36. Closed Period Behavior

Once:

```text
period.status = CLOSED
```

ordinary mutation RPCs must reject operations.

Examples:

```text
save_meal_entries       -> PERIOD_CLOSED
create_expense          -> PERIOD_CLOSED
update_shared_expense   -> PERIOD_CLOSED
record_payment          -> PERIOD_CLOSED
create_adjustment       -> PERIOD_CLOSED
```

The only lifecycle exception is the explicit:

```text
reopen_period
```

operation.

---

# 37. Frontend Data Contract

The frontend should treat RPC responses as authoritative.

For example:

```text
Meal Entry
    ↓
save_meal_entries()
    ↓
database
    ↓
authoritative saved result
    ↓
frontend refreshes summary
```

The frontend should not assume that:

```text
HTTP success
```

means:

```text
accounting result unchanged
```

because a mutation can affect meal rate, allocations, balances, and settlement.

---

# 38. Suggested Frontend Service Layer

The application should have a dedicated service layer such as:

```text
lib/
  supabase/
    client.ts
    server.ts

  api/
    mess.ts
    members.ts
    periods.ts
    meals.ts
    expenses.ts
    payments.ts
    adjustments.ts
    settlement.ts
    audit.ts
```

React components should not contain raw accounting logic.

Example conceptual flow:

```text
MealsPage
    ↓
meal service
    ↓
supabase.rpc('save_meal_entries')
    ↓
database
    ↓
result
    ↓
invalidate/refetch period summary
```

---

# 39. Security Requirements for RPCs

Every security-definer RPC must:

```sql
SECURITY DEFINER
SET search_path = public, private, pg_temp
```

or use an equally restrictive fixed search path appropriate to the final schema.

Functions must not rely on:

```sql
search_path
```

being trustworthy.

Sensitive helper functions should live in the private schema where practical.

---

# 40. RPC Exposure

Only intended application functions should be executable by the authenticated role.

The final migration should explicitly manage:

```sql
GRANT EXECUTE
REVOKE EXECUTE
```

rather than relying on PostgreSQL defaults.

High-risk internal helper functions should not be publicly executable.

---

# 41. API Surface Summary

## Authentication

Handled by:

```text
Supabase Auth
```

## Mess

```text
create_mess
request_to_join_mess
approve_join_request
reject_join_request
```

## Membership

```text
approve_join_request
transfer_manager
```

## Periods

```text
create_period
close_period
reopen_period
```

## Meals

```text
save_meal_entries
create_guest_meal
```

## Expenses

```text
create_expense
update_shared_expense
void_expense
```

## Payments

```text
record_payment
void_payment
```

## Adjustments

```text
create_adjustment
void_adjustment
create_opening_balance
```

## Reporting

```text
calculate_period_summary
calculate_member_statement
calculate_settlement_preview
get_settlement_history
```

## Audit

```text
get_audit_events
```

---

# 42. Functions That Should Remain Internal

Not every database function is part of the public application API.

Internal functions may include:

```text
private.is_current_manager(...)
private.is_period_member(...)
private.validate_period_date(...)
private.calculate_meal_units(...)
private.calculate_meal_rate(...)
private.allocate_equal(...)
private.allocate_weighted(...)
private.allocate_fixed(...)
private.calculate_member_balance(...)
private.create_audit_event(...)
private.validate_period_editable(...)
private.assert_same_mess(...)
private.assert_same_period(...)
```

These functions exist to prevent duplication and centralize security/accounting rules.

---

# 43. Implementation Rule

The database should contain one canonical implementation of every accounting rule.

Do not implement:

```text
meal rate calculation
allocation rounding
member balance calculation
settlement reconciliation
```

independently in:

* React
* TypeScript
* SQL views
* RPCs

with subtly different formulas.

Instead:

```text
canonical SQL calculation functions
             ↓
 ┌───────────┼───────────┐
 ↓           ↓           ↓
Dashboard  Statement  Settlement
                         ↓
                     Close Period
                         ↓
                   Final Snapshot
```

---

# 44. Final Contract Principle

The API contract follows one fundamental rule:

> **The client requests facts to be recorded; the database determines what those facts mean financially.**

The frontend therefore remains replaceable.

A future mobile app, desktop application, or alternative frontend can use the same RPC layer without changing the accounting model.

---

# 45. Implementation Order

The backend implementation should now proceed in this order:

```text
01. Base Schema V2
        ↓
02. Helper Authorization Functions
        ↓
03. RLS Policies
        ↓
04. Accounting Calculation Functions
        ↓
05. Mutation RPCs
        ↓
06. Reporting Functions / Views
        ↓
07. Settlement Lifecycle RPCs
        ↓
08. Audit Functions / Triggers
        ↓
09. Seed Dataset
        ↓
10. Automated Database Tests
        ↓
11. Frontend Service Layer
        ↓
12. Frontend Pages
        ↓
13. End-to-End Testing
```

The **database remains the source of truth throughout the entire stack**.
