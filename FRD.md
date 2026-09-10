# Mess Manager

## Functional Requirements Document (FRD)

**Document version:** 1.0
**Product version:** V1
**Based on:** Mess Manager PRD v1.0
**Backend:** Supabase PostgreSQL + Supabase Auth
**Frontend:** Responsive web application
**Deployment:** Vercel
**Development:** GitHub Codespaces

---

# 1. Purpose

This document defines the functional behavior of Mess Manager at implementation level.

The PRD states **what the product should accomplish**.

This FRD specifies:

* how each workflow behaves
* what fields are required
* who can perform each action
* what states exist
* how data moves through the system
* what validations occur
* what calculations are triggered
* what happens in edge cases
* what operations are forbidden

The subsequent database schema, RLS policies, server actions/database functions, and UI implementation should conform to this document.

---

# 2. Functional Architecture

At a high level:

```text
User
 │
 ▼
Authentication
 │
 ▼
Application
 │
 ├── Mess
 ├── Membership
 ├── Period
 ├── Meals
 ├── Expenses
 ├── Allocations
 ├── Payments
 ├── Adjustments
 └── Settlement
          │
          ▼
     Calculation Layer
          │
          ▼
       Dashboard
          │
          ▼
      Audit Layer
```

The frontend is responsible for:

* interaction
* data-entry UI
* local form validation
* presentation

Supabase/PostgreSQL is responsible for:

* persistence
* authorization
* relational integrity
* authoritative calculations
* protected state transitions
* auditability

---

# 3. Terminology

## 3.1 Mess

A residential group managed by the application.

---

## 3.2 Period

A defined accounting interval, normally one calendar month.

Example:

```text
2026-09-01 → 2026-09-30
```

---

## 3.3 Member

A user who has approved membership in a mess.

---

## 3.4 Period Member

A user's membership within one specific accounting period.

This distinction is required for historical accounting.

---

## 3.5 Manager

The user authorized to administer one accounting period.

---

## 3.6 Meal

A chargeable consumption event associated with a member and date.

---

## 3.7 Guest Meal

A meal consumed by a non-member but financially assigned to a host member.

---

## 3.8 Expense

A financial expenditure incurred by the mess.

---

## 3.9 Allocation

The portion of an expense assigned to one participant.

---

## 3.10 Payment

Money paid into the mess by a member.

---

## 3.11 Adjustment

A manual financial credit or debit applied by the manager.

---

## 3.12 Settlement

The final calculated financial position of a member for a period.

---

# 4. User Roles

The application shall recognize at least:

```text
UNAUTHENTICATED
AUTHENTICATED USER
MEMBER
MANAGER
```

A user may be:

* authenticated but not a mess member
* an active member
* a historical member
* current manager for a period

Role is contextual.

A user can be a manager in one period and an ordinary member in another.

---

# 5. Authentication Functional Requirements

## FR-AUTH-001 — Registration

The system shall provide account creation using Supabase Auth.

### Input

* email
* password

### Optional profile

* display name

### On success

1. Auth identity is created.
2. Application profile is created/available.
3. User is authenticated.
4. User enters the application shell.

### Validation

Email must be valid.

Password validation shall follow the configured authentication policy.

---

# 6. Login

## FR-AUTH-002

Authenticated credentials shall permit access to the application.

On successful authentication:

```text
Login
 ↓
Determine memberships
 ↓
Determine available messes
 ↓
Determine current period
 ↓
Open appropriate dashboard
```

A user with no mess membership should be taken to onboarding rather than seeing an empty accounting dashboard.

---

# 7. Logout

## FR-AUTH-003

The user can log out.

The frontend must clear application state after logout.

Protected queries must no longer be executable using the previous application session.

---

# 8. Password Recovery

## FR-AUTH-004

The user may request password recovery.

The application must not reveal whether an arbitrary email belongs to a registered user through error-message differences.

---

# 9. Profile

## FR-PROFILE-001

The user may view and edit non-security-sensitive profile information such as:

* display name
* avatar, if implemented

The user must not edit:

* internal user ID
* authentication metadata
* account ownership information

---

# 10. Mess Creation

## FR-MESS-001

An authenticated user may create a mess.

### Required

* mess name

### Optional initial configuration

* currency
* timezone
* meal types
* fractional meal setting
* guest meal rule
* meal weighting

V1 should default to:

```text
Currency: BDT
Timezone: Asia/Dhaka
Meal types: Breakfast, Lunch, Dinner
Meal weight: 1
Fractional meals: Disabled
Guest meals: Enabled
```

---

# 11. Mess Creation Transaction

Mess creation shall behave as one logical transaction.

Conceptually:

```text
Create mess
 ↓
Create creator membership
 ↓
Create initial period if selected
 ↓
Assign creator as manager
 ↓
Generate join code
```

A failure in a required step must not leave a half-created mess.

---

# 12. Mess Join Code

## FR-MESS-002

The system shall generate a random join code.

Recommended characteristics:

```text
6–8 characters
uppercase alphanumeric
human-readable
```

Characters that are easily confused, such as:

```text
O / 0
I / 1
```

should preferably be excluded.

---

# 13. Join Code Validation

## FR-MESS-003

When a user submits a join code:

1. Normalize input.
2. Find active code.
3. Check mess availability.
4. Check whether user already belongs.
5. Check whether pending request already exists.
6. Create request if valid.

The system must not expose confidential mess data during code lookup.

---

# 14. Join Request State Machine

```text
NONE
 │
 ▼
PENDING
 ├──────► APPROVED
 │
 └──────► REJECTED
```

Possible future:

```text
PENDING → CANCELLED
```

but this is not required for V1.

---

# 15. Join Request — Member Side

User submits:

```text
Join Code
```

System responds:

### Success

> Join request submitted.

### Already member

> You are already a member of this mess.

### Already pending

> Your request is already awaiting approval.

### Rejected previously

The UI may allow a new request, but the old request remains historical.

### Invalid code

> Invalid join code.

---

# 16. Join Request — Manager Side

Manager sees pending requests containing:

* requester name
* requester identifier/display information
* request date
* status

Actions:

```text
Approve
Reject
```

---

# 17. Approval Transaction

When manager approves:

1. Verify manager authority.
2. Verify period/membership context.
3. Verify request is still pending.
4. Create/activate period membership.
5. Mark request approved.
6. Record audit event.

All steps must happen transactionally.

---

# 18. Race Condition: Double Approval

If two manager sessions attempt to approve the same request simultaneously:

Only one operation should succeed.

The second must safely fail or recognize the request as already processed.

The database must be authoritative here.

---

# 19. Rejection

Manager rejects a pending request.

The request becomes:

```text
REJECTED
```

No active membership is created.

The historical request remains stored.

---

# 20. Membership Lifecycle

Recommended state model:

```text
PENDING
   ↓
ACTIVE
   ↓
ENDED
```

A separate:

```text
REMOVED
```

state may be useful where removal is administrative rather than voluntary departure.

The implementation must distinguish historical membership from current activity.

---

# 21. Mid-Month Joining

Suppose:

```text
Period:
Sep 1–Sep 30

Member joins:
Sep 15
```

The user's period membership should have an effective start:

```text
Sep 15
```

The system must not automatically assign September 1–14 as member days.

Existing meals from before membership must not be assignable through normal UI workflows unless explicitly handled by an administrative correction mechanism.

---

# 22. Mid-Month Leaving

Suppose:

```text
Member leaves:
Sep 22
```

Normal meal-entry screens should prevent meals after the effective departure date.

Historical meals before departure remain unchanged.

---

# 23. Rejoining

If a former member rejoins:

```text
old membership
   ↓
ended

new membership
   ↓
active
```

The application must not modify the dates of the old membership to incorporate the new stay.

---

# 24. Manager Assignment

Each active period must have one manager.

Manager assignment requires:

* target user
* target period
* effective date or period assignment
* actor
* timestamp

The assignment must be audited.

---

# 25. Manager Handover

The recommended V1 manager-handover workflow:

```text
Current Manager
 ↓
Choose active member
 ↓
Review selected person
 ↓
Confirm transfer
 ↓
New manager assigned
 ↓
Old manager loses manager permissions
```

The outgoing manager remains a member unless separately removed.

---

# 26. Manager Self-Removal

A manager must not be able to simply remove themselves as the sole manager.

The system should require:

```text
Assign replacement
OR
explicit administrative recovery
```

This prevents an ownerless period.

---

# 27. Manager Handover Race Condition

Two manager sessions must not simultaneously appoint different managers.

Manager assignment must use a transactional/database constraint.

---

# 28. Accounting Period Creation

## FR-PERIOD-001

A new period can be created for a mess.

Typical:

```text
September 2026
```

followed by:

```text
October 2026
```

The system should prevent overlapping active periods.

---

# 29. Period State Machine

```text
DRAFT
 ↓
OPEN
 ↓
CLOSING
 ↓
CLOSED
```

Optional:

```text
CLOSED
 ↓
REOPENED
 ↓
OPEN
```

The `CLOSING` stage may be implemented internally even if not visible as a UI state.

---

# 30. Period Date Rules

For a monthly period:

* start date must precede end date
* period dates must not overlap another period for the same mess
* transaction dates must normally fall inside the period

---

# 31. Period Configuration Snapshot

At period creation, relevant configuration should be copied/snapshotted where required for accounting.

This may include:

* meal types
* meal weights
* guest rules
* rounding rules
* other accounting settings

The purpose is to prevent later configuration changes from altering historical calculation semantics.

---

# 32. Daily Meal Entry

## FR-MEAL-001

Manager opens a day.

Example:

```text
10 September 2026
```

System loads all eligible period members.

Default grid:

| Member | Breakfast | Lunch | Dinner |
| ------ | --------: | ----: | -----: |
| A      |         0 |     0 |      0 |
| B      |         0 |     0 |      0 |
| C      |         0 |     0 |      0 |

---

# 33. Meal Entry

Manager can set a quantity for each member and meal type.

Default acceptable values:

```text
0
1
```

if fractional meals are disabled.

If enabled:

```text
0
0.5
1
1.5
...
```

according to configured increment.

---

# 34. Meal Validation

The system shall reject:

* negative quantity
* non-numeric quantity
* unsupported fractional quantity
* meal belonging to another period
* inactive member on that date

---

# 35. Guest Meal Entry

Manager can mark a meal as guest consumption.

Minimum data:

* host member
* date
* meal type
* quantity

Guest identity is optional unless the product later introduces guest records.

---

# 36. Meal Edit

Manager may change an existing meal while the period is open.

Every change must:

* preserve record identity where possible
* update calculations
* generate an audit event

---

# 37. Bulk Meal Actions

The UI should support:

### Set value

Apply a quantity to selected members.

### Copy previous day

Copies meal pattern only; it does not reference or alter the previous day.

### Clear day

Sets/removes the relevant records according to the data model.

### Quick-fill

Populate common patterns.

All such operations must obey the same validation rules as individual entry.

---

# 38. Meal Date Edge Cases

The system must handle:

### Future date

Manager may optionally be prevented from entering future meals.

Recommended V1:

Allow future dates within the open period because some messes record planned patterns.

### Outside current period

Reject.

### Before member joined

Reject.

### After member left

Reject.

### Closed period

Reject modification.

---

# 39. Food Expense Creation

## FR-EXP-001

Manager can create an expense.

Required:

* expense date
* amount
* description
* category
* expense classification
* payer

---

# 40. Expense Classification

Every expense shall identify whether it contributes to meal cost.

Recommended values:

```text
MEAL_RELATED
SHARED_NON_MEAL
OTHER_NON_MEAL
```

The exact enum structure may later be normalized into category + accounting treatment.

---

# 41. Expense Amount

Must be:

```text
> 0
```

unless a separate zero-value correction record is intentionally supported.

Normal zero-value expenses should not be accepted.

---

# 42. Payer

The payer should normally be:

* an active period member

A future version could support external payers.

V1 should not require external payers.

---

# 43. Expense Allocation

If expense is shared:

```text
Expense
 ↓
Participants
 ↓
Allocation method
 ↓
Individual allocation records
```

---

# 44. Equal Allocation

Given:

```text
Amount = X
Members = N
```

Each member's unrounded share is:

```text
X / N
```

Rounding is handled by the canonical allocation engine.

---

# 45. Weighted Allocation

Each participant receives a weight.

Example:

```text
A = 2
B = 1
C = 1
```

Total weight:

```text
4
```

A receives:

```text
Expense × 2/4
```

B/C each receive:

```text
Expense × 1/4
```

Weights must be:

```text
> 0
```

---

# 46. Fixed Allocation

Manager enters an exact amount for each participant.

The system must enforce:

```text
sum(allocation amounts) = expense amount
```

within the exact accounting precision.

If mismatch exists:

> Allocations do not equal expense amount.

Save must be blocked unless the manager corrects the allocations.

---

# 47. Participant Eligibility

A participant must be eligible for the expense's period/date according to membership rules.

A member who has left before the expense date should not be selectable under normal workflow.

---

# 48. Expense Shared by Selected Members

The system must not assume every expense applies to every member.

Example:

```text
Internet
Participants:
A
B
C
```

Members D/E receive no allocation.

---

# 49. Meal-Related Expense Rules

Meal-related expenses contribute to:

```text
Total Food Cost
```

Only records designated as meal-related should enter the meal-rate numerator.

Examples:

### Include

* rice
* vegetables
* meat
* eggs
* cooking ingredients

### Normally exclude

* internet
* rent
* electricity
* cleaning
* maintenance

The exact classification is determined by the configured category/accounting treatment.

---

# 50. Expense Corrections

When manager edits:

```text
Amount
Date
Category
Payer
Classification
Description
```

the system must recalculate affected settlements.

An audit record must record the change.

---

# 51. Payment Entry

## FR-PAY-001

Manager can record a member payment.

Required:

* member
* amount
* date

Optional:

* payment method
* note
* reference

V1 may omit payment method.

---

# 52. Payment Validation

Payment must:

* be positive
* belong to a valid member
* belong to the relevant accounting context
* have a valid date

A payment cannot be assigned to an inactive/non-member under normal UI workflow.

---

# 53. Multiple Payments

A member may have unlimited payment records within practical system limits.

Example:

```text
Sep 05   ৳1,000
Sep 12   ৳2,000
Sep 21   ৳1,500
```

The system sums them automatically.

---

# 54. Payment Editing

Manager can correct a payment while the period is open.

The edit must be audited.

---

# 55. Adjustment Entry

## FR-ADJ-001

Manager may create:

```text
CREDIT
DEBIT
```

Required:

* member
* amount
* date
* reason

---

# 56. Adjustment Examples

### Credit

Previous overcharge:

```text
৳100 credit
```

### Debit

Damage reimbursement:

```text
৳300 debit
```

The UI must make clear that adjustments are exceptional manual entries.

---

# 57. Calculation Engine

The application must have one canonical calculation pathway.

Different pages must not implement separate versions of:

```text
meal rate
member cost
balance
```

The canonical calculation layer should accept a period context and derive the required figures consistently.

---

# 58. Calculation Inputs

For each period:

```text
Period configuration
+
Period members
+
Meal records
+
Guest meals
+
Meal-related expenses
+
Non-meal expenses
+
Expense allocations
+
Payments
+
Adjustments
+
Opening balances/carry-forward
```

---

# 59. Meal Units

For each meal record:

```text
meal_units =
quantity × meal_weight
```

If all weights equal 1:

```text
meal_units = quantity
```

---

# 60. Total Chargeable Meals

```text
period_meal_units =
SUM(all chargeable meal units)
```

Guest meals are included according to the configured guest policy.

---

# 61. Meal Rate

If:

```text
period_meal_units > 0
```

then:

```text
meal_rate =
total_meal_related_expense
/
period_meal_units
```

---

# 62. Zero Meal Rule

If:

```text
period_meal_units = 0
```

then meal rate is undefined.

System state:

```text
MEAL_RATE_UNAVAILABLE
```

The system must not output infinity, NaN, or arbitrary zero.

---

# 63. Zero Food Expense

If:

```text
total_meal_related_expense = 0
period_meal_units > 0
```

then:

```text
meal_rate = 0
```

---

# 64. Member Food Cost

```text
member_meal_cost =
member_meal_units × meal_rate
```

The exact calculation precision is greater than the display precision.

---

# 65. Shared Cost

For member M:

```text
member_shared_cost =
SUM(M's expense allocations)
```

Only allocations belonging to the relevant period contribute.

---

# 66. Adjustment

```text
net_adjustment =
credit_total − debit_total
```

---

# 67. Total Obligation

Conceptually:

```text
total_obligation =
member_meal_cost
+
member_shared_cost
+
debit_total
−
credit_total
```

---

# 68. Payments

```text
total_paid =
SUM(valid member payments)
```

---

# 69. Closing Balance

Conceptually:

```text
closing_balance =
total_obligation
−
total_paid
```

Interpretation:

```text
> 0  → amount due
= 0  → settled
< 0  → credit
```

---

# 70. Opening Balance

If carry-forward is enabled:

```text
opening_balance
```

is incorporated into the period ledger.

A cleaner accounting model is:

```text
closing_balance =
opening_balance
+
current_period_charges
−
current_period_credits
−
payments
```

The exact direction/sign convention will be finalized in the Calculation Engine Specification.

The UI must never expose ambiguous positive/negative terminology.

---

# 71. Settlement Presentation

The system should translate raw accounting into semantic states.

### Positive

```text
Amount due
৳1,250
```

### Zero

```text
Settled
```

### Negative

```text
Credit
৳350
```

---

# 72. Settlement Breakdown

Each member's statement should provide:

```text
Period
Meals
Meal rate
Food cost
Shared costs
Adjustments
Opening balance
Payments
Final balance
```

Each number should be traceable to underlying records.

---

# 73. Mess-Level Reconciliation

The system shall produce period-level totals.

Important checks include:

```text
Total meal-related expense
=
sum of meal-cost funding
```

and:

```text
Shared expense allocation totals
=
source shared expense totals
```

and:

```text
member-level financial balances
```

must reconcile against the configured accounting model.

---

# 74. Rounding

The accounting engine should retain exact decimal precision until the appropriate settlement stage.

Example:

```text
100 / 3
=
33.333333...
```

Display:

```text
33.33
```

But final allocation must reconcile exactly:

```text
33.34 + 33.33 + 33.33 = 100.00
```

---

# 75. Residual Allocation

Any unavoidable smallest-unit residual must be assigned deterministically.

The system must not depend on:

* UI ordering
* JavaScript object ordering
* random ordering

A stable participant ordering should be used.

The exact algorithm will be finalized in Document 10.

---

# 76. Calculation Rebuild

When any of the following changes:

* meal
* guest meal
* meal-related expense
* expense classification
* shared allocation
* adjustment
* payment
* opening balance

affected settlement values must update.

The system should derive them dynamically or through a controlled recalculation mechanism.

---

# 77. Manager Dashboard

The manager dashboard shall contain:

## Header

* mess name
* current period
* manager identity

## Summary

* meal rate
* total meals
* meal-related expenses
* shared expenses
* collected payments
* outstanding amount
* credit amount

## Alerts

* pending join requests
* calculation warnings
* missing manager
* incomplete allocation
* period readiness issues

## Quick actions

* Record meals
* Add expense
* Add payment
* Review members
* Review settlement

---

# 78. Member Dashboard

The member dashboard shall prioritize:

* current period
* meals
* current estimated cost
* shared expenses
* paid
* due/credit

The interface should make the member's position understandable without exposing management functionality.

---

# 79. Expense List

Manager expense list must support:

* date
* description
* amount
* category
* payer
* classification
* shared/not shared

Filters:

* date range
* category
* payer
* classification

---

# 80. Meal Calendar/Grid

Manager can navigate dates.

Recommended behavior:

```text
Previous day
Current day
Next day
Calendar picker
```

Daily grid should prioritize rapid editing.

---

# 81. Payment List

Manager can view:

* payment date
* member
* amount
* note

Sort:

* newest
* oldest
* highest amount

---

# 82. Member List

Manager sees:

* name
* membership status
* join date
* leave date
* manager status
* current balance

Member-level financial values should be appropriate for manager visibility.

---

# 83. Member Detail

Manager member detail should contain:

### Profile

* display name
* membership dates

### Current period

* meals
* food cost
* shared costs
* adjustments
* paid
* balance

### History

* previous settlements

---

# 84. Member View

A member viewing themselves sees detailed information.

The member should not see manager-only actions.

---

# 85. Period Closure Review

Before closure, manager enters:

```text
Review Settlement
```

The system displays:

### Operational summary

* member count
* meal count
* expenses
* payments

### Financial summary

* meal rate
* shared costs
* total outstanding
* total credits

### Validation

* unresolved issues
* warnings
* blockers

---

# 86. Closure Blockers

Examples:

```text
No manager
Invalid allocations
Zero meals with food expense
Invalid transaction
Unresolved data inconsistency
```

The system must not allow closure when a blocking condition exists.

Warnings that are explicitly non-blocking may be displayed separately.

---

# 87. Closure Confirmation

Manager must explicitly confirm:

> I have reviewed this period's settlement and want to close it.

The application should require deliberate confirmation rather than closing via accidental click.

---

# 88. Period Closure Transaction

Closure should:

1. Validate all blockers.
2. calculate final settlement.
3. persist the closing state/snapshot.
4. mark period closed.
5. create audit event.

The operation must be transactional.

---

# 89. Closed Period Behavior

Closed period:

### Read

Allowed.

### Create meal

Forbidden.

### Edit meal

Forbidden.

### Create expense

Forbidden.

### Edit expense

Forbidden.

### Add payment

Normally forbidden.

### Add adjustment

Forbidden.

### Change membership historical data

Forbidden through ordinary operations.

---

# 90. Reopening

If supported:

```text
Closed
 ↓
Reopen
 ↓
Reason required
 ↓
Audit event
 ↓
Open
```

The system should clearly indicate that reopening may alter the previously finalized settlement.

---

# 91. Reopening Permissions

Only the authorized current manager or designated administrative authority should be able to reopen.

The authorization must be enforced by the database layer.

---

# 92. Historical Period Selection

User may choose:

```text
August 2026
September 2026
October 2026
```

For old periods:

* member sees allowed historical statement
* manager can see historical operational/accounting records
* editing remains blocked if closed

---

# 93. Audit Requirements

The audit subsystem must capture, at minimum:

### Identity events

* sign-up if application-level audit is needed
* profile changes of significance

### Membership events

* join request
* approval
* rejection
* member removal
* membership changes

### Management events

* manager assignment
* manager transfer

### Financial events

* meal creation
* meal modification
* expense creation
* expense modification
* allocation modification
* payment creation/modification
* adjustment creation/modification

### Period events

* open
* close
* reopen

---

# 94. Audit Record Format

Conceptually:

```text
actor_user_id
event_type
entity_type
entity_id
timestamp
old_values
new_values
reason
```

Not every event requires every field.

---

# 95. Audit Immutability

Normal users, including managers, must not be able to edit or delete audit events through application functionality.

---

# 96. Error Handling Framework

Errors fall into:

### Validation error

User input is invalid.

Example:

> Amount must be greater than zero.

### Authorization error

User lacks permission.

Example:

> You do not have permission to edit this expense.

### State error

Operation is invalid because of current state.

Example:

> This period is already closed.

### Conflict error

Another transaction changed the state.

Example:

> This join request has already been processed.

### System error

Unexpected server/database failure.

User sees a safe message.

Technical details are logged separately.

---

# 97. Offline Behavior

V1 should **not claim full offline synchronization**.

Critical manager accounting operations require a confirmed server response.

If a network interruption occurs during data entry:

* do not assume the operation succeeded
* clearly indicate uncertain save state
* allow retry
* avoid creating accidental duplicate records

---

# 98. Duplicate Submission Protection

The application should be safe against:

* double-clicking Save
* browser retry
* network retry
* duplicate API request

For important transactional actions, use:

* database uniqueness constraints
* idempotency where appropriate
* transactional operations

---

# 99. Concurrency

The application must assume multiple browser sessions may be open.

Example:

```text
Manager's phone
+
Manager's laptop
```

Both may edit data.

Database constraints are authoritative.

The UI should refresh/revalidate after mutations where necessary.

---

# 100. Permission Matrix

| Function             | Member |         Manager |
| -------------------- | -----: | --------------: |
| View own dashboard   |    Yes |             Yes |
| View own meals       |    Yes |             Yes |
| View own statement   |    Yes |             Yes |
| View all balances    |     No |             Yes |
| Record meals         |     No |             Yes |
| Edit meals           |     No |             Yes |
| Add expense          |     No |             Yes |
| Edit expense         |     No |             Yes |
| Allocate expense     |     No |             Yes |
| Record payment       |     No |             Yes |
| Add adjustment       |     No |             Yes |
| Approve join request |     No |             Yes |
| Reject join request  |     No |             Yes |
| Manage members       |     No |             Yes |
| Assign manager       |     No |             Yes |
| Close period         |     No |             Yes |
| Reopen period        |     No | Yes, controlled |
| View audit log       |     No |             Yes |

"Yes" assumes authorization within the user's active mess/period context.

---

# 101. Authorization Context

Every protected operation should answer:

```text
Who is this user?
Which mess?
Which period?
What membership do they have?
Are they the authorized manager?
Is the period open?
```

No single frontend boolean should be trusted for these decisions.

---

# 102. Database-Level Security Requirements

Critical operations must ultimately be protected by:

* Supabase RLS
* PostgreSQL constraints
* database functions where appropriate
* transaction boundaries

The client must not be able to circumvent these by calling Supabase directly with manipulated IDs.

---

# 103. Manager-Only Mutation Rule

The following should normally be manager-only writes:

```text
meals
expenses
allocations
payments
adjustments
membership approvals
membership administration
manager assignments
period state transitions
```

The exact exceptions will be documented in the RLS specification.

---

# 104. Member Read Restrictions

A member may read:

* their own detailed financial records
* their own meals
* their own payments
* their own allocations
* their own statement
* permitted mess aggregate information

A member must not obtain unauthorized private data by changing a URL parameter or database ID.

---

# 105. URL/ID Tampering

Example:

```text
/member/ABC
```

A member changing:

```text
ABC → XYZ
```

must not expose another member's private statement.

The database must reject the underlying query where unauthorized.

---

# 106. Manager Scope Tampering

Likewise, a manager from Mess A changing:

```text
period_id
```

to a period belonging to Mess B must receive no unauthorized access.

Authorization must derive from relational ownership/membership, not from the UI's selected mess.

---

# 107. Mess Deletion

V1 should avoid casual mess deletion.

Recommended:

```text
Active
Archived
```

A mess should preferably be archived rather than hard-deleted when historical financial records exist.

---

# 108. User Departure

When a member leaves:

* current membership becomes inactive/ended
* historical records remain
* historical statements remain
* previous allocations remain
* payments remain

---

# 109. Manager Departure

If current manager wants to leave:

1. system detects they are manager
2. system requires transfer
3. replacement manager is selected
4. transfer is completed
5. old manager becomes ordinary member or leaves separately

---

# 110. Expense Allocation Integrity

For every shared expense:

```text
sum(allocation amounts)
=
expense amount
```

The database should prevent invalid final allocation state.

---

# 111. Expense Payer Integrity

Payer must be distinct from beneficiary conceptually.

Example:

```text
Paid by A
Allocated to A/B/C
```

must be representable without duplication.

---

# 112. Payment vs Expense Distinction

A payment is not an expense.

This distinction must remain explicit.

Example:

```text
A pays grocery shop:
Expense = ৳2,000

A later pays mess:
Payment = ৳3,000
```

These affect the accounting differently.

---

# 113. Guest Accounting

Default guest behavior:

```text
Guest meal
 ↓
chargeable meal
 ↓
host member receives resulting food cost
```

Guest consumption must not create a phantom member account.

---

# 114. Meal-Rate Circularity

The system must avoid circular calculation.

Correct:

```text
Food expenses
÷
Total chargeable meals
=
Meal rate

Meal rate
×
member meals
=
member food cost
```

Member costs must not themselves be included in the meal-rate numerator.

---

# 115. Expense Payer Circularity

An expense paid by a member is not automatically a reduction in that member's food cost.

Instead:

```text
Expense allocation
+
Payer/payment treatment
```

must be calculated independently.

---

# 116. Shared Cost Participant Changes

Changing participants affects member allocations.

For an open period:

* recalculate allocations
* recalculate balances
* record audit event

For a closed period:

* reject normal change

---

# 117. Payment Date Changes

Editing payment date can affect period assignment.

If manager changes:

```textSep 30 → Oct 1
```

the application must validate whether the payment belongs to the same period.

Cross-period movement should be treated as an accounting-sensitive operation.

---

# 118. Transaction Date Integrity

The same principle applies to:

* meals
* expenses
* payments
* adjustments

Dates determine period context unless explicitly overridden by a future cross-period workflow.

---

# 119. Non-Monthly Periods

Although V1 focuses on monthly operation, the database should use generic periods rather than hardcoding:

```textmonth_number
```

This leaves room for:

* custom billing periods
* semester periods
* irregular settlement periods

---

# 120. Manager Dashboard Calculation Refresh

After a manager mutation:

```textSave
 ↓
Server transaction
 ↓
Revalidate affected calculation
 ↓
UI refresh
```

The user should see updated values without manually recalculating.

---

# 121. Optimistic UI

Optimistic updates may be used for low-risk interface responsiveness, but the final state must be reconciled with the server/database response.

For financial data:

> Server-confirmed value is authoritative.

---

# 122. Critical Transactional Operations

The following should preferably be handled atomically:

* approve member
* manager transfer
* create shared expense + allocations
* close period
* reopen period

---

# 123. Create Expense Workflow

```text
Open Add Expense
 ↓
Enter details
 ↓
Select classification
 ↓
Select payer
 ↓
Select sharing method
 ↓
Select participants
 ↓
Preview allocations
 ↓
Validate
 ↓
Save
 ↓
Recalculate
 ↓
Show updated balance
```

---

# 124. Add Payment Workflow

```text
Open Add Payment
 ↓
Select member
 ↓
Enter amount
 ↓
Enter date
 ↓
Optional note
 ↓
Save
 ↓
Update balance
 ↓
Show confirmation
```

---

# 125. Meal Entry Workflow

```text
Select date
 ↓
Load eligible members
 ↓
Enter quantities
 ↓
Validate
 ↓
Save changes
 ↓
Recalculate
 ↓
Update totals
```

---

# 126. Close Month Workflow

```text
Open settlement review
 ↓
Run validation
 ↓
Show blockers/warnings
 ↓
Resolve blockers
 ↓
Review statements
 ↓
Confirm
 ↓
Calculate final values
 ↓
Persist snapshot
 ↓
Lock period
 ↓
Audit
```

---

# 127. New Month Workflow

Recommended:

```text
Previous period
 ↓
Create next period
 ↓
Determine continuing members
 ↓
Determine join requests/new members
 ↓
Assign manager
 ↓
Create period configuration snapshot
 ↓
Open period
```

Previous period's data must not simply be duplicated indiscriminately.

---

# 128. Continuing Members

At the next period, active members from the previous period may be carried forward.

The system should create new period membership records rather than extending the old period membership into the new period.

---

# 129. New Members in New Period

A previously pending or newly invited user may become active in the new period according to the manager approval workflow.

---

# 130. Previous Balance Carry-Forward

If enabled, the previous closing balance becomes the new period's opening balance.

This must be stored as an explicit accounting fact.

The system should not recalculate August every time September is viewed.

---

# 131. Historical Settlement Stability

For a closed period:

Changing:

* today's meal configuration
* current member list
* current join code
* current manager
* future period settings

must not alter the final closed statement.

---

# 132. Validation Severity

Validation results should be categorized:

### BLOCKER

Prevents save or close.

### WARNING

Does not prevent save but requires awareness.

### INFO

Useful contextual information.

Example:

```text
BLOCKER:
Shared allocations total ৳990 but expense is ৳1,000.

WARNING:
There are no meal records for 3 days.

INFO:
Current meal rate is based on 438 meals.
```

---

# 133. Calculation Warnings

Useful warnings:

* no meals recorded
* meal rate unusually high/low compared with recent periods
* expense allocations incomplete
* member has no meals
* unusually large expense
* large outstanding balance

These should be advisory, not arbitrary blockers unless product rules require otherwise.

---

# 134. Member With Zero Meals

A member can legitimately have:

```text
0 meals
```

and still have:

* shared costs
* adjustments
* payments
* opening balance

The system must not automatically exclude such a member from settlement.

---

# 135. Member With Meals But No Payments

Normal case.

Settlement simply shows outstanding amount.

---

# 136. Member With Payments But No Current Charges

Possible due to:

* advance payment
* opening balance
* future-month contribution

The accounting model must explicitly define whether such payment creates a credit.

V1 should represent it as credit rather than discard it.

---

# 137. Negative/Zero Financial Values

Raw transaction amounts should generally not be negative.

Sign should be represented structurally:

```text
transaction_type = CREDIT / DEBIT
```

rather than using negative numbers everywhere.

This reduces ambiguity.

---

# 138. Money Input UX

The frontend should accept user-friendly forms such as:

```text
100
100.5
100.50
```

and normalize them.

It must reject invalid strings such as:

```text
abc
10..5
-100
```

where negative values are not permitted.

---

# 139. Unsaved Changes

For meal grids and multi-field forms:

If the user attempts navigation with unsaved changes, the UI should warn.

---

# 140. Form Recovery

Where practical, temporary form state may survive accidental navigation.

However, unsaved financial entries must never be presented as saved transactions.

---

# 141. Loading States

Every asynchronous operation must have explicit UI states:

```text
Idle
Loading
Success
Error
```

For mutations:

```text
Saving...
```

must prevent accidental duplicate submission.

---

# 142. Empty State Requirements

Empty states must explain:

* what is missing
* whether it is expected
* what the user can do next

Example:

> No meals recorded for this date.

Manager action:

> Record meals

---

# 143. Mobile Meal Grid

A desktop table may not fit comfortably on mobile.

Recommended mobile interaction:

```text
Member card
 ├── Breakfast
 ├── Lunch
 └── Dinner
```

while desktop uses a grid.

The underlying data model remains identical.

---

# 144. Desktop Meal Grid

Desktop may use:

```text
Rows = members
Columns = meal types
```

with sticky:

* member column
* date controls
* save state

---

# 145. Financial Summary Display

Financial numbers should always include clear labels.

Avoid:

```text
৳4,500
৳3,000
৳1,500
```

Prefer:

```text
Total charge     ৳4,500
Paid             ৳3,000
Amount due       ৳1,500
```

---

# 146. Member Transparency

Member statement must expose enough information to understand:

```text
Why do I owe this amount?
```

rather than only showing the final number.

---

# 147. Manager Transparency

Manager settlement review must expose:

```text
Who owes what?
Why?
What underlying records caused it?
```

---

# 148. Audit Accessibility

Manager should be able to inspect audit history for relevant records.

Example:

```text
Expense edited
10 Sep 2026 14:32
Old amount: ৳850
New amount: ৳800
Reason: Duplicate item
```

---

# 149. System Invariants

The system must continuously preserve these invariants:

### INV-01

Every period has at most one active manager.

### INV-02

Every approved period member has valid mess membership context.

### INV-03

A shared expense allocation set reconciles with its expense.

### INV-04

Closed periods cannot undergo ordinary mutations.

### INV-05

A user cannot access another mess's private records.

### INV-06

A member cannot perform manager-only writes.

### INV-07

Historical data is not deleted merely because membership ended.

### INV-08

Meal rate never divides by zero.

### INV-09

Financial records use exact accounting precision.

### INV-10

Audit records cannot be modified by normal application actors.

---

# 150. Functional Definition of V1 Completion

The system is functionally complete when this exact scenario works:

```text
1. User A registers.
2. User A creates Mess X.
3. User A becomes manager.
4. System generates join code.
5. Users B, C, D register.
6. B/C/D request membership.
7. A approves them.
8. September period opens.
9. Manager records daily meals.
10. Manager records groceries.
11. Groceries contribute to meal cost.
12. Manager records internet expense.
13. Internet is shared among B/C/D.
14. A pays the internet bill.
15. Manager records A's payment/expense relationship.
16. Members make multiple payments.
17. Manager makes one adjustment.
18. System calculates every member's settlement.
19. Manager reviews reconciliation.
20. Manager closes September.
21. September becomes read-only.
22. October is created.
23. A assigns B as October manager.
24. A loses October manager permissions.
25. September history remains unchanged.
26. October starts with the correct membership/manager context.
```

That end-to-end flow is the minimum meaningful proof that the product architecture works.

---

# 151. FRD-to-Later-Document Dependencies

This FRD establishes requirements that must now be translated into:

### Document 4

Non-functional and technical requirements.

### Document 5

Information architecture and UI/UX profile.

### Document 6

Detailed page-by-page UX specification.

### Document 7

Entity relationship/data model.

### Document 8

Supabase SQL schema.

### Document 9

Supabase RLS and authorization.

### Document 10

Exact accounting/calculation engine.

### Document 11

Audit/data-integrity design.

### Document 12

API/server action specification.

### Document 13

Validation/error-state matrix.

### Document 14

Test plan.

### Document 15

Deployment/environment specification.

### Document 16

Implementation roadmap.

---

# 152. Critical Architectural Decision

The following separation should be treated as non-negotiable for V1:

```text
                ┌─────────────────────┐
                │   USER INPUT FACTS  │
                └──────────┬──────────┘
                           ↓
                ┌─────────────────────┐
                │ POSTGRES / SUPABASE │
                │   AUTH + RLS + DB   │
                └──────────┬──────────┘
                           ↓
                ┌─────────────────────┐
                │ CALCULATION ENGINE  │
                └──────────┬──────────┘
                           ↓
                ┌─────────────────────┐
                │     SETTLEMENT      │
                └─────────────────────┘
```

The browser should never be the authoritative accounting ledger.

---
