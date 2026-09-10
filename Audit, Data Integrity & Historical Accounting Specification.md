# Document 11 — Audit, Data Integrity & Historical Accounting Specification

**Product:** Mess Manager
**Document:** Audit, Data Integrity & Historical Accounting Specification
**Version:** 1.0
**Status:** Implementation Specification
**Depends on:** PRD, FRD, NFR/Technical Requirements, UI/UX Specification, Data Model & ERD, Supabase Schema, RLS Specification, Calculation Engine & Accounting Specification

---

## 1. Purpose

This document defines how Mess Manager preserves trustworthy financial and membership history over time.

The system is not merely a CRUD application. It is an accounting-oriented system in which a later change must not silently rewrite the meaning of an earlier period.

The primary objectives are:

1. Every important mutation must be attributable.
2. Historical periods must remain reproducible.
3. Corrections must happen at the correct source record.
4. Destructive deletion of accounting history must be avoided.
5. Closed periods must be protected.
6. Concurrent operations must not create inconsistent balances.
7. Settlement results must remain auditable.
8. Current membership or manager changes must not retroactively alter historical calculations.
9. The database must enforce critical invariants even when the normal frontend is bypassed.

---

# 2. Core Integrity Principles

## 2.1 Database authority

The database is the authoritative source for:

* membership state
* manager assignment
* meal records
* guest meals
* expenses
* expense allocations
* payments
* adjustments
* opening balances
* period status
* settlement snapshots
* audit history

The frontend must never be treated as a trusted accounting authority.

A malicious or buggy client must not be able to create an invalid accounting state simply by calling the Supabase API directly.

---

## 2.2 Historical periods are immutable by default

A period that is `CLOSED` is considered finalized.

Normal application operations must not modify:

* meals
* guest meals
* expenses
* expense allocations
* payments
* adjustments
* opening balances
* period membership
* manager assignment
* meal weights
* settlement snapshots

for that period.

The only normal exception is an explicit **reopen-period** operation performed by an authorized manager.

Reopening must itself produce an audit event.

---

## 2.3 Corrections are source corrections

The system should not encourage users to manually overwrite calculated values.

For example:

Incorrect:

> Change Rafsan's food cost from 2,450 BDT to 2,300 BDT.

Correct:

> Correct the meal entry or expense that caused the food cost.

Likewise:

Incorrect:

> Manually change the settlement balance.

Correct:

> Correct the underlying payment, expense, meal, adjustment, or opening balance.

This guarantees that the final result can always be reconstructed.

---

## 2.4 Financial records are never casually deleted

Accounting-related records should normally use one of these mechanisms:

* correction through an update
* voiding
* replacement/correction record
* explicit reversal

A record should not disappear from the historical database merely because it was entered incorrectly.

---

# 3. Audit Model

## 3.1 Audit event definition

An audit event records a meaningful state-changing action.

Every audit event should answer:

> Who changed what, when, in which mess and period, and why?

At minimum an audit event should contain:

* event ID
* mess ID, where applicable
* period ID, where applicable
* actor user ID
* event timestamp
* action
* entity type
* entity ID
* before-state, where applicable
* after-state, where applicable
* reason/comment, where applicable
* request/idempotency identifier, where applicable
* metadata sufficient to understand the operation

The existing `audit_events` table is therefore treated as an append-only historical record.

---

# 4. Audit Event Types

The implementation should use controlled action values rather than arbitrary free-form strings.

Recommended actions include:

### Authentication/account actions

* `PROFILE_CREATED`
* `PROFILE_UPDATED`
* `ACCOUNT_DEACTIVATED`

### Mess actions

* `MESS_CREATED`
* `MESS_UPDATED`
* `MESS_ARCHIVED`

### Join actions

* `JOIN_CODE_CREATED`
* `JOIN_CODE_REGENERATED`
* `JOIN_REQUEST_CREATED`
* `JOIN_REQUEST_APPROVED`
* `JOIN_REQUEST_REJECTED`

### Membership actions

* `MEMBER_ADDED`
* `MEMBER_ENDED`
* `MEMBER_REMOVED`
* `MEMBER_REACTIVATED`

### Manager actions

* `MANAGER_ASSIGNED`
* `MANAGER_TRANSFERRED`
* `MANAGER_REMOVED`

### Period actions

* `PERIOD_CREATED`
* `PERIOD_OPENED`
* `PERIOD_CLOSED`
* `PERIOD_REOPENED`

### Meal actions

* `MEAL_CREATED`
* `MEAL_UPDATED`
* `MEAL_VOIDED`
* `GUEST_MEAL_CREATED`
* `GUEST_MEAL_UPDATED`
* `GUEST_MEAL_VOIDED`
* `MEAL_TYPE_CREATED`
* `MEAL_TYPE_UPDATED`
* `MEAL_TYPE_RETIRED`

### Expense actions

* `EXPENSE_CREATED`
* `EXPENSE_UPDATED`
* `EXPENSE_VOIDED`
* `EXPENSE_ALLOCATION_CREATED`
* `EXPENSE_ALLOCATION_UPDATED`
* `EXPENSE_ALLOCATION_VOIDED`

### Payment actions

* `PAYMENT_CREATED`
* `PAYMENT_UPDATED`
* `PAYMENT_VOIDED`

### Adjustment actions

* `ADJUSTMENT_CREATED`
* `ADJUSTMENT_UPDATED`
* `ADJUSTMENT_VOIDED`

### Opening-balance actions

* `OPENING_BALANCE_CREATED`
* `OPENING_BALANCE_UPDATED`
* `OPENING_BALANCE_VOIDED`

### Settlement actions

* `SETTLEMENT_CALCULATED`
* `SETTLEMENT_FINALIZED`
* `SETTLEMENT_SUPERSEDED`

### Administrative actions

* `PERIOD_INTEGRITY_CHECK_FAILED`
* `PERIOD_INTEGRITY_CHECK_PASSED`
* `RECONCILIATION_FAILED`
* `RECONCILIATION_PASSED`

---

# 5. Audit Event Immutability

Audit events must be append-only.

Once an audit event exists:

* it cannot be edited
* it cannot be deleted through normal application access
* users cannot alter its actor
* users cannot alter its timestamp
* users cannot alter its before/after state

The database should deny ordinary `UPDATE` and `DELETE` operations on audit events.

Administrative database-level intervention may still exist for disaster recovery, but such operations are outside normal application functionality.

---

# 6. Audit Trigger Strategy

Audit logging should use a hybrid architecture.

## 6.1 Database triggers for direct record mutations

For high-value records, database triggers should automatically create audit events.

Examples:

* meals
* expenses
* payments
* adjustments
* membership
* manager assignments
* period status
* settlement snapshots

This prevents a future code path from accidentally bypassing audit logging.

---

## 6.2 RPC-level audit events for business operations

Some operations represent a business action rather than a simple row mutation.

Examples:

* approving a join request
* transferring manager
* closing a period
* reopening a period
* calculating and finalizing settlement
* regenerating a join code

These should produce explicit audit events inside the same database transaction as the operation.

---

# 7. Transaction Requirement

A state-changing accounting operation and its corresponding audit event should be committed atomically.

For example:

```text
Create expense
    ↓
Validate expense
    ↓
Create allocation data
    ↓
Update required derived state
    ↓
Create audit event
    ↓
COMMIT
```

The application must not reach a state where:

```text
Expense exists
BUT
audit event does not exist
```

for operations where auditing is mandatory.

The same principle applies to corrections and voids.

---

# 8. Before-State and After-State

For important mutable entities, an audit event should retain enough information to determine the changed state.

For example, if an expense changes:

```text
Before:
amount = 1000
category = INTERNET
paid_by = Member A
```

and becomes:

```text
After:
amount = 1200
category = INTERNET
paid_by = Member A
```

the audit event should record both states.

For sensitive or unnecessarily large fields, the system may store a structured subset plus a hash/fingerprint rather than duplicating the entire row.

The implementation must choose consistently rather than arbitrarily mixing formats.

---

# 9. Financial Mutation Policy

## 9.1 Meals

A meal may be updated while its period remains open.

For example:

```text
Dinner = 1
```

may be corrected to:

```text
Dinner = 0
```

The system must then recalculate affected settlement values.

For material corrections, the audit event must capture:

* actor
* period
* member
* date
* meal type
* previous quantity
* new quantity
* timestamp

A meal should not be physically deleted merely because the manager entered the wrong quantity.

Where possible, a quantity of zero or a void state should preserve historical evidence of the correction.

---

# 10. Guest Meal Corrections

Guest meals must follow the same principles.

A guest meal correction must identify:

* host member
* date
* guest meal type
* previous quantity
* new quantity or void state
* reason where required

Guest meals must never silently alter the host's historical record.

---

# 11. Expense Correction Policy

Expenses are particularly sensitive because they can affect:

* total meal cost
* meal rate
* shared cost
* payer expense advance
* member balances
* period settlement

Therefore an expense mutation must be validated as a complete accounting operation.

Changing:

```text
amount
```

may affect allocations.

Changing:

```text
accounting_type
```

may move the expense between:

* meal cost
* shared non-meal cost
* other non-meal cost

Changing:

```text
paid_by_period_member_id
```

may change the expense advance of a member.

Therefore such changes must not be implemented as arbitrary client-side column updates.

They should be executed through a controlled RPC.

---

# 12. Expense Allocation Integrity

For a non-voided expense:

```text
SUM(active allocations) = expense amount
```

must always hold.

For example:

```text
Expense = 1,000
A = 250
B = 250
C = 250
D = 250
```

is valid.

But:

```text
Expense = 1,000
A = 250
B = 250
C = 250
D = 249
```

is invalid.

Likewise:

```text
A = 1000
B = 1000
```

against a 1,000 BDT expense is invalid.

The database or trusted RPC layer must reject such states.

---

# 13. Expense Advance Integrity

If a valid expense has:

```text
paid_by_period_member_id = A
```

the system treats that vendor payment as an **expense advance by A**.

This must not be confused with:

```text
payment by A into the mess
```

These are different accounting events.

Example:

```text
Internet bill = 1,000
A pays vendor
A/B/C/D share equally
```

Accounting result:

```text
A shared cost       +250
A expense advance  -1000
A net effect        -750

B net effect        +250
C net effect        +250
D net effect        +250
```

The total is zero.

A separate 1,000 BDT member payment must not be automatically generated.

---

# 14. Payment Correction Policy

A member payment into the mess must be independently traceable.

Example:

```text
A pays 2,000 BDT to mess
```

This creates:

```text
payment.amount = 2000
payment.member = A
```

If the amount was entered incorrectly:

```text
2,000 → 2,500
```

the correction must be audited.

If the payment never actually happened, it should normally be voided rather than deleted.

A voided payment no longer contributes to settlement but remains visible in the audit/history record.

---

# 15. Adjustment Policy

Adjustments are intended for legitimate accounting corrections that cannot reasonably be represented by modifying an underlying event.

Examples:

* previous-period carry-forward correction
* manually agreed small reconciliation difference
* special charge
* special credit

Every adjustment must contain:

* member
* amount
* credit/debit direction
* reason
* actor
* accounting period
* timestamp

An adjustment should never be used as a general-purpose mechanism for hiding an incorrect meal or expense.

Preferred hierarchy:

```text
Correct source record
        ↓
Use explicit adjustment when source correction is inappropriate
```

---

# 16. Opening Balance Integrity

Opening balances represent an amount brought into the period.

Example:

```text
Opening balance = 500 DUE
```

means the member starts the period owing 500 BDT.

Example:

```text
Opening balance = 500 CREDIT
```

means the mess/member account begins with a 500 BDT credit.

Opening balances must be tied to the target period and member.

They must not automatically change because the previous period is later reopened.

If the previous period changes after the new period has been created, the opening balance remains the explicitly recorded opening state unless a manager deliberately corrects it.

---

# 17. Membership History

Membership is period-specific.

A member's current status must never rewrite the historical membership snapshot of an earlier period.

Example:

### August

```text
A = ACTIVE
B = ACTIVE
C = ACTIVE
```

### September

```text
A = ACTIVE
B = ENDED
C = ACTIVE
D = ACTIVE
```

Changing B's September membership must not alter August.

This is one of the reasons `period_members` exists separately from generic mess membership.

---

# 18. Manager Rotation

The manager role is period-specific.

Example:

```text
August manager = A
September manager = B
October manager = C
```

These assignments must remain historical facts.

Changing the current manager must not grant that user the authority to alter previously closed periods merely because they are the current manager.

Authorization must check:

```text
Does this user have manager authority for THIS period?
```

not:

```text
Is this user currently the mess manager?
```

---

# 19. Manager Transfer

Manager transfer must be atomic.

A transfer must not result in:

```text
two managers
```

or:

```text
zero managers
```

for a period that requires a manager.

The operation should execute conceptually as:

```text
Lock period
    ↓
Verify current manager
    ↓
Verify new manager is an active period member
    ↓
End old manager assignment
    ↓
Create new manager assignment
    ↓
Audit transfer
    ↓
Commit
```

The database should enforce the final consistency.

---

# 20. Join Request Integrity

A user may have at most one pending request for the same mess.

Therefore:

```text
User A → Mess X → PENDING
```

cannot coexist with another:

```text
User A → Mess X → PENDING
```

A rejected request may later be submitted again.

An approved request results in appropriate period membership according to the current/open-period workflow.

Approval must be performed transactionally.

The system must not create membership while leaving the join request in an apparently pending or contradictory state.

---

# 21. Period State Machine

The period state machine is:

```text
DRAFT
  ↓
OPEN
  ↓
CLOSED
```

Reopening is:

```text
CLOSED
  ↓
OPEN
```

A normal period should not transition backwards arbitrarily.

Invalid transitions include:

```text
CLOSED → DRAFT
OPEN → DRAFT
CLOSED → DRAFT
```

unless a highly privileged administrative recovery operation exists outside the normal application.

---

# 22. Period Opening

A period may become `OPEN` only when required prerequisites have been satisfied.

Depending on implementation, this may include:

* valid date range
* manager assigned
* required meal types defined
* valid period configuration
* membership state initialized

The exact prerequisites should be enforced by the period creation/open RPC.

---

# 23. Period Closing

Closing is a high-impact accounting operation.

The close operation should:

1. Lock the period against concurrent accounting mutation.
2. Validate all required integrity constraints.
3. Calculate the complete settlement.
4. Run reconciliation.
5. Create a final settlement snapshot.
6. Mark the snapshot as final.
7. Mark the period `CLOSED`.
8. Write audit events.
9. Commit atomically.

If any blocker exists, closing must fail.

---

# 24. Closure Blockers

Examples of blocking conditions include:

### Accounting blockers

* meal-related expense exists but total chargeable meal units are zero
* active expense allocations do not reconcile
* fixed allocation total does not equal expense amount
* invalid member references
* invalid expense payer
* settlement reconciliation failure
* duplicate accounting records violating uniqueness constraints

### Period blockers

* no manager assigned
* invalid date range
* inconsistent membership state
* more than one current manager
* invalid meal type state

### Settlement blockers

* final balance does not equal charges minus credits
* member balances do not reconcile to expected total
* settlement snapshot cannot be generated consistently

A blocker must be clearly surfaced to the manager.

---

# 25. Closure Warnings

Warnings differ from blockers.

A warning does not necessarily prevent closing.

Examples:

* unusually high meal count
* unusually high expense compared with prior period
* member has no recorded payment despite a positive amount due
* a member has unusually many guest meals
* period contains a large manual adjustment

Warnings should be logged and shown to the manager before final closure where appropriate.

---

# 26. Reopening a Closed Period

Reopening is exceptional.

A manager must explicitly initiate it.

The system should require a reason such as:

> Corrected electricity expense entered incorrectly.

The operation must:

1. verify authority
2. lock the period
3. ensure no conflicting operation is active
4. preserve the previous final settlement snapshot
5. mark the period `OPEN`
6. record the reason
7. create audit events
8. allow corrections
9. require a new settlement finalization before the period can become closed again

The old settlement snapshot must not simply be overwritten.

---

# 27. Settlement Versioning

Every finalized settlement must have a version.

Example:

```text
Version 1 → finalized
Period reopened
Version 2 → finalized
```

Version 1 remains historically available.

Version 2 becomes the current authoritative final snapshot.

The system should maintain a relationship such as:

```text
supersedes_snapshot_id
```

so users can determine which snapshot replaced which earlier snapshot.

---

# 28. Settlement Snapshot Contents

A final settlement snapshot must contain enough information to explain the result without depending entirely on mutable live records.

At minimum, member settlement snapshots should retain:

* period
* member
* meal units
* food cost
* shared cost
* credit adjustments
* debit adjustments
* opening balance
* opening balance direction/effect
* payments
* expense advances
* total charges
* total credits
* final balance
* balance status

Period-level snapshot data should retain:

* total meal units
* total meal cost
* meal rate
* total shared cost
* total adjustments
* total payments
* total expense advances
* reconciliation totals
* calculation version
* generated timestamp
* finalization timestamp
* snapshot version

---

# 29. Why Snapshots Are Necessary

The live database can change during an open period.

A final settlement snapshot provides a historical statement of:

> What the system concluded when this period was finalized.

This is particularly important when:

* a closed period is viewed months later
* calculation algorithms are improved
* database views change
* a period is reopened and finalized again
* historical debugging is required

---

# 30. Calculation Version

Settlement snapshots must include a `calculation_version`.

Example:

```text
calculation_version = 1
```

Later:

```text
calculation_version = 2
```

A new algorithm must not silently reinterpret old finalized snapshots.

Historical snapshots remain tied to the calculation version under which they were generated.

---

# 31. Calculation Determinism

Given identical valid accounting inputs and identical calculation-version rules, the settlement engine should produce identical outputs.

This is particularly important for residual allocation.

For example:

```text
100 ÷ 3
```

cannot produce arbitrary cent differences depending on execution order.

The system should use a deterministic residual method such as largest remainder with stable tie-breaking.

---

# 32. Money Integrity

All accounting amounts must use exact numeric arithmetic.

The system must not use binary floating-point values for authoritative financial amounts.

Preferred PostgreSQL representation:

```sql
NUMERIC(14,2)
```

or a sufficiently precise numeric type defined consistently throughout the schema.

Rules:

* no hidden floating-point conversion
* no JavaScript `Number` as the accounting authority
* no rounding at arbitrary intermediate stages
* explicit final rounding policy
* deterministic residual allocation

---

# 33. Meal Rate Integrity

Meal rate is calculated as:

```text
meal_rate =
    total meal-related expense
    --------------------------
       total chargeable meal units
```

When:

```text
total meal units = 0
```

meal rate is unavailable.

It must not become:

```text
NaN
```

or:

```text
Infinity
```

or silently become:

```text
0
```

when meal-related expense exists.

If:

```text
meal units = 0
food expense > 0
```

period closure should be blocked.

If:

```text
meal units > 0
food expense = 0
```

meal rate is legitimately:

```text
0
```

---

# 34. Reconciliation Invariants

The following invariants must always hold for valid finalized data.

## 34.1 Food-cost reconciliation

```text
SUM(member food cost)
=
TOTAL MEAL_COST expenses
```

---

## 34.2 Expense allocation reconciliation

For each active allocated expense:

```text
SUM(member allocations)
=
expense.amount
```

---

## 34.3 Settlement reconciliation

For every member:

```text
final_balance
=
opening_effect
+ food_cost
+ shared_cost
+ debit_adjustments
- credit_adjustments
- payments
- expense_advances
```

---

## 34.4 Balance classification

```text
final_balance > 0
    → DUE

final_balance = 0
    → SETTLED

final_balance < 0
    → CREDIT
```

---

## 34.5 Period-level reconciliation

For a correctly balanced mess period:

```text
SUM(member final balances)
```

must equal the net amount that remains economically attributable to the mess after all recorded contributions and vendor advances.

The exact period-level reconciliation expression must be implemented consistently with the ledger model and tested independently.

---

# 35. Concurrency Control

The system must account for multiple managers/devices potentially operating simultaneously.

Examples:

```text
Manager laptop
+
Manager phone
```

both submitting expenses.

Or:

```text
Device A → close period
Device B → edit expense
```

at approximately the same time.

The database must prevent race conditions from producing invalid finalized data.

---

# 36. Closing Concurrency

Closing a period should acquire an appropriate database lock.

Once closing begins:

```text
OPEN
   ↓
LOCKED FOR FINALIZATION
   ↓
validate
   ↓
calculate
   ↓
snapshot
   ↓
CLOSED
```

Another accounting mutation attempting to alter the same period during finalization should fail or wait according to the implemented transaction strategy.

---

# 37. Reopening Concurrency

Reopening must similarly be serialized.

The system must prevent:

```text
Manager A → reopen
Manager B → reopen
```

from producing multiple contradictory period transitions.

Likewise, two concurrent manager transfers must not create two active managers.

---

# 38. Optimistic Concurrency

Where practical, frequently edited entities may contain:

```text
updated_at
```

and/or a version field.

A write can then verify:

```text
record version still equals the version the user originally loaded
```

before applying an update.

If another user changed the record, the operation can be rejected instead of silently overwriting the newer state.

This is particularly useful for:

* expenses
* payments
* member records
* settings
* meal grids where conflicts are possible

---

# 39. Idempotency

Operations that may be retried because of unreliable network conditions should support idempotency where appropriate.

Example:

The manager presses:

> Record payment

The request reaches the server.

The response is lost.

The client retries.

The system must not create two payments.

An idempotency key/request ID should therefore be associated with important command-style operations.

Examples:

* create expense
* record payment
* create adjustment
* close period
* reopen period
* transfer manager
* approve join request

The implementation should enforce uniqueness where appropriate.

---

# 40. Retry Safety

A failed network response does not necessarily mean the transaction failed.

Therefore the client must not blindly assume:

```text
No response = no database change
```

Instead:

1. generate a request ID
2. submit operation
3. if response is lost, retry with the same request ID
4. database returns the original result or prevents duplication

---

# 41. Delete Policy

## 41.1 Profiles

A profile may be deactivated, but historical accounting references should remain intact.

---

## 41.2 Members

Membership records should not be physically deleted if they are referenced by historical accounting.

---

## 41.3 Meals

Do not physically delete accounting meals in normal operation.

Use correction or void semantics.

---

## 41.4 Expenses

Do not hard-delete financial expenses.

Use:

```text
void
```

and retain the historical record.

---

## 41.5 Payments

Do not hard-delete financial payments.

Use:

```text
void
```

with audit information.

---

## 41.6 Adjustments

Do not hard-delete accounting adjustments.

Use void/reversal semantics.

---

## 41.7 Audit Events

Never delete through normal application access.

---

# 42. Soft-Delete / Void Semantics

A voided accounting record should contain enough information to explain:

* that it existed
* that it was intentionally invalidated
* who invalidated it
* when it was invalidated
* why it was invalidated

Typical fields may include:

```text
voided_at
voided_by
void_reason
```

The calculation engine must exclude voided accounting records.

---

# 43. Closed-Period Protection

Every accounting mutation must ultimately validate:

```text
period.status = OPEN
```

A frontend route being hidden is not sufficient protection.

Likewise:

```text
period_id = user's current period
```

is not sufficient authorization.

The database/RPC must verify the period and actor together.

---

# 44. Historical Configuration

Any configuration that materially changes accounting must be period-specific.

Examples:

* meal types
* meal weights
* relevant allocation settings
* membership
* manager assignment

Changing the configuration for September must not silently change August.

Therefore the calculation engine must always use configuration belonging to the relevant period.

---

# 45. Period Membership Snapshot

When a period is opened, its membership should be represented explicitly through `period_members`.

The system must calculate the historical settlement against the period membership, not against the mess's current member list.

Example:

```text
August:
A B C

September:
A C D

October:
A D E
```

Viewing August years later must still show:

```text
A B C
```

not:

```text
A D E
```

---

# 46. Former Members

A former member must retain access to historical information they are authorized to see, subject to privacy rules.

For example, a member who leaves after August should still be able to see their August statement.

However, they must not gain access to:

* another member's private settlement detail
* current manager controls
* current-period editing
* another mess

merely because they were once a member.

---

# 47. Former Managers

A former manager retains no manager privilege merely because they previously managed a period.

Authorization must evaluate the relevant period.

A former manager may be allowed to view historical information according to membership rights, but cannot modify a closed period unless the authorization model explicitly permits a controlled reopen.

---

# 48. Audit Visibility

Audit logs are more sensitive than normal application records.

Recommended access:

### Manager

May view audit events relevant to their authorized mess/period.

### Ordinary member

Normally should not receive unrestricted audit-log access.

They may see user-facing history of their own accounting changes where product UX requires it.

### Database/service administrators

May have broader operational access.

The product must avoid exposing sensitive internal metadata unnecessarily.

---

# 49. Privacy of Audit Data

Audit events should not unnecessarily store:

* authentication tokens
* passwords
* access tokens
* service-role credentials
* sensitive secrets

The audit log should contain accounting/business metadata, not security credentials.

---

# 50. Audit Actor Identity

Every application-generated audit event should identify its actor.

For normal user actions:

```text
actor_user_id = authenticated user
```

For trusted system actions:

```text
actor_user_id = NULL
```

with an explicit system actor designation such as:

```text
actor_type = SYSTEM
```

The implementation should distinguish:

```text
USER
SYSTEM
ADMIN
```

rather than making NULL ambiguous.

---

# 51. Timestamp Policy

Audit timestamps should be generated by the database/server, not trusted from the browser.

Use:

```text
TIMESTAMPTZ
```

for event timestamps.

This avoids users spoofing historical timestamps.

Accounting dates such as meal dates may remain:

```text
DATE
```

because a meal belongs to a calendar date.

Both concepts must remain distinct:

```text
accounting_date
```

versus:

```text
created_at
```

---

# 52. Event Ordering

Multiple actions may occur within milliseconds.

`created_at` alone should therefore not be treated as a perfect total ordering.

Audit events should have:

* unique event ID
* server timestamp
* deterministic ordering mechanism where required

PostgreSQL-generated UUIDs provide identity but not necessarily chronological order.

For precise audit sequence, the implementation may additionally use a database-generated sequence number within the relevant scope.

---

# 53. Cross-Table Integrity

Some business rules cannot be enforced using ordinary single-row `CHECK` constraints.

Examples:

```text
expense.period_id must match
expense.payer.period_id
```

or:

```text
allocation.member must belong to
allocation.expense.period
```

or:

```text
manager_assignment.user must be an
active member of the same period
```

These relationships must therefore be enforced through:

* foreign keys where possible
* composite foreign keys where useful
* triggers
* security-definer functions
* controlled RPCs

They must not be left solely to frontend validation.

---

# 54. Composite Foreign Keys

Where practical, the schema should use composite foreign keys to make cross-period mismatches structurally impossible.

For example:

```text
(period_id, period_member_id)
```

may be validated against the appropriate period-membership structure.

This is preferable to discovering the problem only after data has already been inserted.

---

# 55. Trigger-Based Validation

Triggers should be used where constraints depend on multiple rows or business state.

Examples:

* allocation must belong to same period as expense
* payer must be active member of relevant period
* assignment must match period
* mutation forbidden after closure
* settlement snapshot consistency
* audit event creation

Triggers must remain small and deterministic.

Complex accounting calculations belong in dedicated functions rather than giant trigger bodies.

---

# 56. Controlled RPC Architecture

High-risk operations should be implemented as PostgreSQL functions/RPCs rather than exposing unrestricted direct CRUD.

Recommended commands include:

```text
create_mess()
request_to_join_mess()
approve_join_request()
reject_join_request()

create_period()
open_period()
assign_manager()
transfer_manager()

save_meal_entries()
create_guest_meal()
update_guest_meal()
void_guest_meal()

create_expense()
update_expense()
void_expense()

record_payment()
update_payment()
void_payment()

create_adjustment()
void_adjustment()

create_opening_balance()
update_opening_balance()
void_opening_balance()

calculate_period_summary()
calculate_member_statement()

close_period()
reopen_period()
```

The final RPC set may be consolidated during implementation, but all high-impact transitions must remain transaction-controlled.

---

# 57. Security-Definer Function Requirements

Where a security-definer function is used:

* `search_path` must be explicitly controlled
* object names should be schema-qualified
* caller identity must be obtained from the authenticated context
* the function must perform its own authorization checks
* the function must not blindly trust IDs supplied by the client
* dynamic SQL should be minimized

Security-definer functions are privileged code and must therefore be treated as security boundaries.

---

# 58. Service Role Restrictions

The Supabase service-role key bypasses RLS.

Therefore:

* it must never be sent to the browser
* it must never be stored in client-exposed environment variables
* it must never be embedded in frontend JavaScript
* it should be used only in trusted server-side contexts where necessary

Normal user actions should ideally operate through normal authenticated database authorization or controlled RPCs.

---

# 59. Reconciliation Engine

The system should expose an internal reconciliation function capable of checking:

### Meal reconciliation

```text
member meal units
vs
period total meal units
```

### Food-cost reconciliation

```text
member food costs
vs
meal-related expenses
```

### Expense reconciliation

```text
allocation totals
vs
expense totals
```

### Settlement reconciliation

```text
member balances
vs
calculated accounting equation
```

### Snapshot reconciliation

```text
snapshot totals
vs
source records
```

If any mismatch exists, the period should be marked as internally inconsistent and the issue should be surfaced before finalization.

---

# 60. Corruption Detection

The system should be capable of detecting impossible states such as:

```text
expense.amount = 1000
allocation.sum = 997
```

or:

```text
closed period
+
active mutation
```

or:

```text
two current managers
```

or:

```text
settlement snapshot
+
inconsistent member totals
```

These checks should be available both:

* during normal operations
* as an administrative diagnostic tool

---

# 61. Integrity Failure Handling

When a critical integrity condition fails:

The system must not silently repair financial data.

Instead:

1. reject the operation
2. preserve the current valid state if possible
3. write an appropriate audit/diagnostic event
4. expose a meaningful error
5. identify the affected period/entity

Automatic destructive repair is prohibited.

---

# 62. Recovery Philosophy

Recovery must preserve evidence.

Suppose an expense becomes corrupted due to a future software defect.

The correct response is not:

> delete the expense

but:

> identify affected records → quarantine/stop affected operation → determine correct state → apply a controlled correction → preserve audit trail.

This makes future investigation possible.

---

# 63. Historical Reproducibility Requirement

For any finalized period, the system should be able to answer:

> Why is this member's final balance this amount?

The answer should be reconstructable from:

* period membership
* meals
* guest meals
* meal configuration
* meal-related expenses
* shared expenses
* allocations
* adjustments
* opening balance
* payments
* expense advances
* settlement snapshot
* audit history

A number without an explainable chain of source records is considered an integrity failure.

---

# 64. Member Statement Explainability

A member statement should be decomposable into:

```text
Opening balance
+
Food cost
+
Shared costs
+
Debit adjustments
-
Credit adjustments
-
Payments
-
Expense advances
=
Final balance
```

The interface may summarize these values, but the database model must retain the underlying source data.

---

# 65. No Manual Final-Balance Editing

There must be no normal UI or API operation equivalent to:

```text
set_member_balance(1500)
```

A final balance is calculated.

If the number is wrong, the source cause must be corrected.

The only legitimate exception is an explicit adjustment or opening balance, each of which is independently recorded.

---

# 66. No Manual Meal-Rate Editing

Likewise, there must be no normal operation equivalent to:

```text
set_meal_rate(72.50)
```

Meal rate is derived.

The manager changes:

* meals
* meal weights
* meal-related expenses

and the system recalculates the rate.

---

# 67. Data Retention

For the initial product, accounting data should be retained for the lifetime of the mess record unless the user explicitly performs an allowed account/data deletion operation.

Because financial history depends on historical identities, deleting a profile must not automatically destroy referenced accounting history.

Retention behavior must therefore distinguish:

```text
account identity
```

from:

```text
historical accounting reference
```

---

# 68. Account Deactivation and Historical References

If a user account is deactivated:

Historical records may still contain the user's immutable internal ID.

The user-facing system may display an anonymized/deactivated identity where appropriate.

The accounting relationship must not be broken merely because the user no longer actively uses the application.

---

# 69. Anonymization

If future regulatory/product requirements require personal-data anonymization, the implementation must ensure that:

* accounting records remain internally consistent
* foreign-key references remain valid
* historical calculations remain reproducible
* audit evidence is not arbitrarily destroyed

Anonymization must therefore be designed separately from ordinary account deletion.

---

# 70. Archival

An entire mess may eventually be archived.

Archiving should mean:

```text
no normal new activity
```

not:

```text
delete all historical data
```

Archived messes remain available for historical viewing according to authorization rules.

---

# 71. Error Messages

Integrity errors should identify the problem without exposing internal implementation details.

Good:

> This expense cannot be closed because its allocations do not total 1,000 BDT.

Poor:

> PostgreSQL constraint fk_expense_allocations_472 failed.

Internal technical errors may be logged separately.

---

# 72. Required Database Protections

The final implementation must use an appropriate combination of:

* foreign keys
* unique constraints
* partial unique indexes
* exclusion constraints
* check constraints
* triggers
* transaction locks
* RLS
* grants
* security-definer RPCs
* immutable audit storage

No single mechanism is sufficient by itself.

---

# 73. Required Test Categories

The backend test suite must include:

## Authorization tests

Verify:

* member cannot mutate meals
* member cannot create expenses
* member cannot approve themselves
* former manager cannot edit a period without authority
* another mess's records cannot be accessed
* arbitrary IDs cannot bypass RLS

---

## Accounting tests

Verify:

* meal rate
* weighted meals
* guest meals
* equal allocation
* weighted allocation
* fixed allocation
* largest-remainder reconciliation
* payments
* expense advances
* adjustments
* opening balances
* final balance classification

---

## Integrity tests

Verify:

* allocation sum mismatch rejected
* cross-period allocation rejected
* cross-period payer rejected
* duplicate active manager rejected
* overlapping periods rejected
* duplicate pending join request rejected
* closed-period mutation rejected

---

## Audit tests

Verify:

* required operations produce audit events
* audit actor is correct
* before/after values are correct
* audit records cannot be edited
* audit records cannot be deleted through normal user access

---

## Concurrency tests

Verify:

* simultaneous payment submissions
* simultaneous expense creation
* simultaneous manager transfer
* simultaneous period close
* simultaneous reopen
* retry with same idempotency key

---

# 74. Golden Historical Scenario

The implementation should preserve a complete test scenario such as:

### Period

```text
September 2026
```

### Members

```text
A
B
C
D
```

### Meals

```text
A = 50 units
B = 30 units
C = 20 units
D = 0 units
```

### Food expense

```text
10,000 BDT
```

### Shared expense

```text
Internet = 1,000 BDT
Equal among A/B/C/D
```

### Payer

```text
A paid the food expense
A paid the internet expense
```

The calculation must produce:

```text
Food:
A = 5,000
B = 3,000
C = 2,000
D = 0

Internet:
A = 250
B = 250
C = 250
D = 250

Expense advances:
A = 11,000
```

Therefore:

```text
A = 5,250 - 11,000 = -5,750
B = 3,250
C = 2,250
D = 250
```

Total:

```text
-5,750 + 3,250 + 2,250 + 250 = 0
```

The historical snapshot must retain this result after the period is closed.

---

# 75. Correction Scenario

Suppose the manager discovers that:

```text
B's meal units were entered as 30
```

but should have been:

```text
35
```

The manager corrects the meal record.

The system must:

1. update/correct the meal
2. recalculate food costs
3. recalculate affected balances
4. recalculate settlement if period is open
5. record audit event
6. preserve the correction history

No manual food-cost editing is necessary.

---

# 76. Reopen Scenario

Suppose the period was closed with settlement version 1.

Later:

```text
Electricity expense should be 1,500
```

instead of:

```text
1,200
```

Process:

```text
Version 1 finalized
        ↓
Manager reopens period
        ↓
Audit: PERIOD_REOPENED
        ↓
Expense corrected
        ↓
Settlement recalculated
        ↓
Version 2 finalized
```

Version 1 remains available as historical evidence.

Version 2 becomes current final settlement.

---

# 77. Data Integrity Hierarchy

When designing backend logic, use this order of authority:

```text
Database constraints
        ↓
Database/RPC validation
        ↓
RLS authorization
        ↓
Application business logic
        ↓
Frontend validation
        ↓
UI presentation
```

Frontend validation is the weakest layer and must never be the only protection.

---

# 78. Source-of-Truth Hierarchy

For an open period:

```text
Source records
    ↓
Calculation engine
    ↓
Live summary
```

For a closed period:

```text
Source records
    ↓
Finalized calculation
    ↓
Settlement snapshot
    ↓
Historical display
```

A closed-period UI should use the finalized snapshot for authoritative settlement display while retaining links back to source records and audit history where authorized.

---

# 79. Versioning Policy

The following should be versioned independently where useful:

* database schema version
* calculation version
* settlement snapshot version
* application version

Example:

```text
Schema migration: 14
Calculation version: 2
Settlement snapshot: Version 3
```

This makes historical investigation much easier.

---

# 80. Migration Safety

Schema changes must be delivered as version-controlled migrations.

A migration must not:

* silently destroy accounting records
* remove historical foreign keys without a migration plan
* alter finalized snapshots without explicit justification
* change calculation semantics without a calculation-version decision

Before production deployment, migrations should be tested against representative historical data.

---

# 81. Future-Proofing Without Overengineering

The architecture should leave room for:

* multiple messes per user
* richer notification systems
* exports
* receipts
* inventory
* analytics
* recurring expenses
* multiple managers
* more advanced accounting

However, the V1 system should not introduce unnecessary abstraction merely to anticipate every possible future feature.

The primary objective remains:

> Correct mess accounting with trustworthy history.

---

# 82. Final Integrity Checklist

Before considering the backend production-ready, verify:

### Identity

* authenticated users have stable profiles
* user identity cannot be spoofed

### Mess

* mess ownership/authority is validated
* join codes are controlled
* join requests are unique and auditable

### Membership

* membership is period-specific
* historical membership is preserved

### Manager

* manager is period-specific
* manager transfer is atomic
* multiple simultaneous managers are impossible

### Period

* periods cannot overlap
* open/closed state transitions are controlled
* closed periods are protected

### Meals

* meals are attributable
* meal weights are period-specific
* meal corrections are audited

### Expenses

* accounting type is explicit
* allocations reconcile
* vendor payer is explicit
* expense advances are separate from member payments
* voids preserve evidence

### Payments

* payments are attributable
* duplicate retries are prevented
* voids preserve evidence

### Adjustments

* direction is explicit
* reason is captured
* adjustments are audited

### Settlement

* calculations are deterministic
* food costs reconcile
* balances reconcile
* final snapshots are versioned
* calculation version is recorded

### Audit

* important mutations are logged
* audit events are immutable
* actor and timestamp are trustworthy

### Security

* RLS is enforced
* grants are restricted
* privileged functions are controlled
* service-role credentials remain server-side

### Reliability

* concurrency is handled
* idempotency exists for retry-sensitive commands
* critical operations are transactional

---

# 83. Implementation Decision Summary

The definitive backend model is therefore:

```text
Supabase Auth
      │
      ▼
Profiles
      │
      ▼
Mess
      │
      ├── Join Codes
      ├── Join Requests
      │
      ▼
Mess Period
      │
      ├── Period Members
      ├── Manager Assignment
      ├── Meal Types
      │
      ├── Meals
      ├── Guest Meals
      │
      ├── Expenses
      │      └── Expense Allocations
      │
      ├── Payments
      ├── Adjustments
      ├── Opening Balances
      │
      ▼
Calculation Engine
      │
      ├── Food Cost
      ├── Shared Cost
      ├── Expense Advances
      ├── Payments
      └── Final Balance
      │
      ▼
Settlement Snapshot
      │
      └── Versioned Final History

All critical mutations
        │
        ▼
Immutable Audit Events
```

The central accounting identity remains:

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

The central historical rule remains:

```text
Current state must never silently rewrite historical accounting.
```

And the central implementation rule remains:

```text
If the frontend disappears,
the database must still protect the accounting system.
```

---

# 84. Outcome

After this specification, the backend requirements are sufficiently defined to move into implementation artifacts.

The remaining implementation layers should now be treated as:

1. **Authoritative PostgreSQL schema**
2. **RLS policies and grants**
3. **Security/authorization helper functions**
4. **Accounting/calculation RPC functions**
5. **Period close/reopen/settlement functions**
6. **Audit triggers and business-operation audit events**
7. **Reporting/statement views**
8. **Database test suite**
9. **Seed/demo data**
10. **Application API/service layer**

The Schema v2 supplied previously should therefore be regarded as the structural baseline, while the above rules become mandatory constraints on the final migration/RPC implementation.
