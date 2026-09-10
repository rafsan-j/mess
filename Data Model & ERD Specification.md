# Mess Manager

## Data Model & ERD Specification

**Document version:** 1.0
**Product version:** V1
**Related documents:** PRD v1.0, FRD v1.0, NFR/Technical Requirements v1.0, UI/UX Profile v1.0, Page-by-Page UI/UX Specification v1.0
**Database:** PostgreSQL via Supabase
**Authentication authority:** Supabase Auth
**Primary identifier strategy:** UUID
**Primary currency:** BDT
**Default timezone:** Asia/Dhaka

---

# 1. Purpose

This document defines the authoritative relational model for Mess Manager.

It establishes:

* entities
* relationships
* cardinality
* ownership
* lifecycle
* field semantics
* historical preservation
* integrity constraints
* indexing strategy
* derived vs stored data
* settlement snapshots
* audit structures

The later Supabase SQL schema must implement this model.

---

# 2. Core Modeling Principle

The database must distinguish between:

### Current state

What is true now.

and:

### Historical state

What was true during a previous accounting period.

This leads to the fundamental rule:

> **Mess-wide identity is long-lived; operational and accounting context is period-specific.**

---

# 3. High-Level Entity Model

```text id="7z7y48"
                         ┌────────────────┐
                         │  auth.users    │
                         └───────┬────────┘
                                 │
                                 │ 1:1
                                 ▼
                         ┌────────────────┐
                         │    profiles    │
                         └───────┬────────┘
                                 │
                                 │
                                 ▼
                         ┌────────────────┐
                         │     messes     │
                         └───────┬────────┘
                                 │
                  ┌──────────────┼─────────────────┐
                  │              │                 │
                  ▼              ▼                 ▼
          join codes       mess settings     periods
                                                     │
                         ┌───────────────────────────┼──────────────────────┐
                         │                           │                      │
                         ▼                           ▼                      ▼
                  period members              managers              settlements
                         │
              ┌──────────┼──────────┬────────────┬──────────────┐
              │          │          │            │              │
              ▼          ▼          ▼            ▼              ▼
            meals     expenses    payments   adjustments      balances
                           │
                           ▼
                      allocations

All major entities
        │
        ▼
    audit events
```

---

# 4. Supabase Authentication Boundary

Supabase Auth owns authentication identity.

The application should not recreate:

* password
* password hash
* authentication credential
* authentication session

inside its own tables.

Application data references the authenticated user through their Supabase Auth UUID.

Conceptually:

```text id="8gmbxp"
auth.users.id
      │
      ▼
profiles.id
```

The application's profile identifier should normally correspond to the authenticated user's UUID.

---

# 5. Entity Inventory

The V1 logical model contains the following major entities:

```text id="lgf9f0"
1. profiles
2. messes
3. mess_join_codes
4. mess_join_requests
5. periods
6. period_members
7. manager_assignments
8. meal_types
9. meals
10. expenses
11. expense_allocations
12. payments
13. adjustments
14. opening_balances
15. settlement_snapshots
16. settlement_member_snapshots
17. audit_events
```

Some implementation details may combine or split entities, but this logical separation is the preferred baseline.

---

# 6. `profiles`

## Purpose

Stores application-level user information associated with a Supabase Auth user.

## Relationship

```text id="9in0ke"
auth.users 1 ─── 1 profiles
```

## Key fields

```text id="puw3ce"
id UUID PK
display_name TEXT
avatar_url TEXT NULL
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

## Rules

* `id` must reference the authenticated user identity.
* profile must not contain password credentials.
* display name should be plain text.

---

# 7. Why `profiles` Is Separate

Do not overload `auth.users` with application-specific mess information.

The user:

```text id="4q6t71"
Rafsan
```

is a global identity.

Their membership in:

```text id="o3y2x2"
Sunrise Mess
```

is a separate relational fact.

---

# 8. `messes`

## Purpose

Represents a residential mess.

## Key fields

```text id="x0hy96"
id UUID PK
name TEXT
status mess_status
timezone TEXT
currency_code TEXT
created_by UUID
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

## Suggested status

```text id="3c5w0d"
ACTIVE
ARCHIVED
```

---

# 9. Mess Ownership

`created_by` records the user who originally created the mess.

This does **not** mean the user remains the manager forever.

The authoritative management relationship is period-specific.

---

# 10. Mess Archiving

A mess should normally be archived rather than hard-deleted once meaningful historical data exists.

A mess may remain in the database for years after becoming inactive.

---

# 11. `mess_join_codes`

## Purpose

Stores the active and historical invitation codes associated with a mess.

## Key fields

```text id="z2px9l"
id UUID PK
mess_id UUID FK
code TEXT
is_active BOOLEAN
created_at TIMESTAMPTZ
revoked_at TIMESTAMPTZ NULL
created_by UUID
```

## Important distinction

The current code can be identified by:

```text is_active = true
```

but history remains available.

---

# 12. Join Code Integrity

There should be at most one active join code per mess.

Conceptually:

```text id="xjflq2"
mess
 ├── old code   revoked
 ├── old code   revoked
 └── current    active
```

Regenerating a code does not overwrite history.

---

# 13. Join Code Storage

The human-facing code should not be the primary key.

The code record uses a UUID.

A uniqueness constraint should prevent duplicate active codes.

---

# 14. `mess_join_requests`

## Purpose

Records attempts to join a mess.

## Key fields

```text id="w6sdwk"
id UUID PK
mess_id UUID FK
user_id UUID FK
requested_at TIMESTAMPTZ
status join_request_status
reviewed_at TIMESTAMPTZ NULL
reviewed_by UUID NULL
rejection_reason TEXT NULL
```

## Status

```text id="f6plp7"
PENDING
APPROVED
REJECTED
```

---

# 15. Join Request History

A rejected request remains stored.

This means:

```text id="f2j8m2"
User → Request 1 → REJECTED
User → Request 2 → PENDING
```

is valid.

---

# 16. Pending Request Uniqueness

At most one pending request should exist for:

```text id="em8v4s"
same user
same mess
```

This requires a partial unique index.

---

# 17. Approved Request Relationship

Approval does not itself serve as the permanent membership record.

Instead:

```text id="r3m1f5"
join request
      ↓
approval
      ↓
period membership
```

This allows historical membership to be independent from invitation workflow.

---

# 18. `periods`

## Purpose

Represents one accounting interval.

## Key fields

```text id="7f0i9l"
id UUID PK
mess_id UUID FK
name TEXT
start_date DATE
end_date DATE
status period_status
created_at TIMESTAMPTZ
opened_at TIMESTAMPTZ NULL
closed_at TIMESTAMPTZ NULL
reopened_at TIMESTAMPTZ NULL
```

---

# 19. Period Status

Suggested:

```text id="5v3qkr"
DRAFT
OPEN
CLOSED
```

`CLOSING` may be implemented internally rather than persisted.

`REOPENED` should not necessarily be a persistent status; reopening can transition:

```text CLOSED → OPEN
```

while retaining reopening history in audit events.

---

# 20. Period Date Constraints

Must satisfy:

```text id="70q5vw"
start_date <= end_date
```

For a given mess, periods must not overlap.

---

# 21. Why Periods Are First-Class

Without a period entity, queries tend to become:

```text WHERE month = 9
AND year = 2026
```

throughout the entire application.

That becomes fragile.

With periods:

```text expense.period_id
meal.period_id
payment.period_id
```

all accounting context is explicit.

---

# 22. Period Ownership

Every period belongs to exactly one mess.

```text id="u35lf3"
mess 1 ─── N periods
```

---

# 23. Active Period Constraint

Normally a mess should have at most one operationally open period.

This is a business invariant to enforce through database logic/constraints.

---

# 24. Period Configuration Snapshot

Accounting settings needed to interpret a period should be associated with that period rather than relying exclusively on current mess settings.

This is essential for historical stability.

---

# 25. `period_members`

## Purpose

Represents a user's membership in a particular accounting period.

This is one of the most important entities in the entire database.

## Key fields

```text id="7oj1u4"
id UUID PK
period_id UUID FK
user_id UUID FK
membership_status period_membership_status
start_date DATE
end_date DATE NULL
joined_from_request_id UUID NULL
created_at TIMESTAMPTZ
ended_at TIMESTAMPTZ NULL
```

---

# 26. Period Membership Status

Suggested:

```text id="l5s9r7"
ACTIVE
ENDED
REMOVED
```

---

# 27. Membership Date Rules

For period membership:

```text period.start_date <= member.start_date <= period.end_date
```

and, when `end_date` exists:

```text member.start_date <= member.end_date <= period.end_date
```

unless a controlled exceptional workflow is later introduced.

---

# 28. Membership Uniqueness

A user should normally have at most one active period membership per period.

Recommended uniqueness rule:

```text id="5lsn7n"
(period_id, user_id)
```

rather than allowing duplicates.

Historical rejoining within the same period should not be silently represented as duplicate memberships; it requires an explicit business decision.

V1 recommendation:

> A user may have only one period membership record per period.

---

# 29. Why Membership Is Period-Specific

Consider:

```text id="v8j6y6"
September:
A active

October:
A left
B joined
```

The database should represent:

```text id="5b64z1"
September period_member(A)

October period_member(B)
```

rather than modifying one global membership row.

---

# 30. Membership and Historical Meals

A meal should reference the appropriate period/member context.

This makes it impossible for ordinary data entry to accidentally assign September meals to an October membership context.

---

# 31. Manager Assignment

## `manager_assignments`

Purpose:

Record who is the manager for a specific period.

## Key fields

```text id="51xkbr"
id UUID PK
period_id UUID FK
user_id UUID FK
assigned_at TIMESTAMPTZ
assigned_by UUID
ended_at TIMESTAMPTZ NULL
```

---

# 32. Manager Assignment Cardinality

Conceptually:

```text id="d7j7ti"
period
  └── manager assignment history
```

There can be multiple historical assignments, but only one current assignment.

Example:

```text id="x0z2ij"
A → manager
A → ended
B → manager
```

---

# 33. Active Manager Constraint

At most one manager may have:

```text ended_at IS NULL
```

for a period.

This should be database-enforced.

---

# 34. Manager Must Be a Period Member

The assigned manager should correspond to a valid member of that period.

A manager cannot be:

* unrelated user
* rejected applicant
* ended member

under ordinary workflow.

---

# 35. Manager Transfer

Manager transfer creates a new assignment and closes the previous assignment.

Do not update the old assignment's user ID.

That would destroy history.

---

# 36. `meal_types`

## Purpose

Defines the configured meal types relevant to a mess/period.

Potential implementation:

```text id="yg61t4"
id UUID PK
mess_id UUID FK
name TEXT
code TEXT
weight NUMERIC
is_active BOOLEAN
sort_order INTEGER
```

However, because historical periods require stable configuration, the implementation should snapshot relevant meal type configuration for each period.

There are two viable designs:

### Design A

Mess-level meal types + copied period configuration.

### Design B

Period-level meal types directly.

**Recommended V1: Design B for accounting-sensitive state.**

---

# 37. Recommended `period_meal_types`

Rather than relying exclusively on current mess settings:

```text id="5la8mm"
period_meal_types
```

can contain:

```text id
period_id
name
code
weight
is_active
sort_order
```

This prevents future setting changes from affecting old periods.

---

# 38. Meal Type Examples

```text id="u9ke03"
BREAKFAST
LUNCH
DINNER
```

Potential future:

```text id="tq8g5l"
SNACK
SPECIAL
```

---

# 39. `meals`

## Purpose

Records member meal consumption.

## Key fields

```text id="v8nq6h"
id UUID PK
period_id UUID FK
period_member_id UUID FK
meal_type_id UUID FK
meal_date DATE
quantity NUMERIC
is_guest BOOLEAN
guest_host_period_member_id UUID NULL
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
created_by UUID
updated_by UUID
```

---

# 40. Meal Record Semantics

A normal member meal:

```text id="jxxz81"
period_member_id = member A
is_guest = false
```

A guest meal:

```text id="bl23xv"
is_guest = true
guest_host_period_member_id = A
```

The exact schema may instead separate guest meals into their own table; see later design discussion.

---

# 41. Recommended Guest Modeling

For V1, guest meals can remain in the same `meals` table because both are consumption events.

This reduces unnecessary duplication.

Distinction is:

```text id="fwukq3"
is_guest
+
host member
```

---

# 42. Meal Unique Constraint

For ordinary meal records, the system should normally allow at most one aggregate record for:

```text id="7j3u1s"
period_member
+
date
+
meal_type
+
guest/non-guest context
```

If the system later supports individual guest identities, the model can be expanded.

---

# 43. Meal Quantity

`quantity` must be:

```text > 0
```

for stored consumption records.

The absence of a record can represent zero, avoiding unnecessary zero rows.

---

# 44. Zero Meal Representation

Recommended:

```text id="9evl04"
No row = 0 meals
```

rather than creating:

```text breakfast = 0
lunch = 0
dinner = 0
```

for every member/date.

However, the UI can display zero.

This reduces database volume.

---

# 45. Meal Weight

Effective meal units:

```text id="6dhjvf"
quantity × period_meal_type.weight
```

Weight belongs to the period configuration.

---

# 46. Fractional Meal Validation

The database should validate quantity according to the configured period rule.

For example:

If fractional meals are disabled:

```text quantity must be integer
```

If enabled:

```text quantity can use configured increment
```

The precise mechanism may use constraints/functions rather than a simple static CHECK.

---

# 47. Expense Entity

## `expenses`

Purpose:

Records actual financial expenditures.

## Key fields

```text id="5o8n8f"
id UUID PK
period_id UUID FK
expense_date DATE
description TEXT
amount NUMERIC
category_code TEXT / FK
accounting_type expense_accounting_type
paid_by_period_member_id UUID
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
created_by UUID
updated_by UUID
voided_at TIMESTAMPTZ NULL
void_reason TEXT NULL
```

---

# 48. Expense Accounting Type

Recommended logical treatment:

```text id="7zlu84"
MEAL_COST
SHARED_NON_MEAL
OTHER_NON_MEAL
```

The final implementation may normalize this into a category table plus treatment field.

---

# 49. Meal-Cost Expense

Examples:

* rice
* vegetables
* meat
* oil
* spices
* eggs

These contribute to total meal-related expense.

---

# 50. Shared Non-Meal Expense

Examples:

* internet
* water
* cleaning
* household supplies

These can be allocated among selected members.

They do not affect meal rate.

---

# 51. Rent and Fixed Costs

Rent can be a non-meal expense.

Whether it is:

* shared
* separately allocated
* excluded from settlement

depends on mess configuration/business rules.

V1 should require the manager to explicitly specify accounting treatment rather than infer it solely from category.

---

# 52. Expense Payer

The payer is represented separately from allocations.

This is crucial.

Example:

```text id="c4ewz6"
expense:
৳1,000

paid_by:
A
```

does not mean:

```text A owes ৳1,000
```

---

# 53. Expense Description

Plain text.

No rich HTML.

Length should have a sensible maximum, such as 200–500 characters.

Exact limit will be finalized in validation specifications.

---

# 54. Expense Category

Two possible architectures:

### Enum

Simple but less extensible.

### Category table

More flexible.

Recommended:

```text id="y0r2ei"
expense_categories
```

containing:

```text id
code
name
default_accounting_type
is_active
sort_order
```

This makes future custom categories possible.

---

# 55. `expense_allocations`

## Purpose

Represents who bears an expense and by how much.

## Key fields

```text id="9kgyo6"
id UUID PK
expense_id UUID FK
period_member_id UUID FK
allocation_amount NUMERIC
allocation_weight NUMERIC NULL
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

---

# 56. Allocation Relationship

```text id="v0m6lr"
expense
  ├── allocation → member A
  ├── allocation → member B
  └── allocation → member C
```

---

# 57. Allocation Method

The parent expense should contain something such as:

```text id="a2hw1t"
allocation_method
```

Values:

```text id="eh1fge"
NONE
EQUAL
WEIGHTED
FIXED
```

---

# 58. Equal Allocation

The allocation records store the final exact allocations.

The UI calculates the preview, but the database persists authoritative values.

---

# 59. Weighted Allocation

Allocation records can retain the weights used for calculation.

Example:

```text id="8pyx7u"
A weight = 2
B weight = 1
C weight = 1
```

This is useful for historical explainability.

---

# 60. Fixed Allocation

Each allocation directly stores the assigned amount.

Example:

```text id="smu3uq"
A = 300
B = 250
C = 450
```

---

# 61. Allocation Total Integrity

The allocation set must reconcile with the source expense:

```text id="l9fjyg"
SUM(allocation_amount)
=
expense.amount
```

This is one of the most important database invariants.

Because a normal CHECK constraint cannot easily enforce cross-row aggregate equality, this should be enforced through a controlled transaction/function.

---

# 62. Allocation Participant Eligibility

Every allocation's member must belong to the same period as the expense.

This relationship should be structurally enforced where possible.

---

# 63. Allocation Uniqueness

One expense should not have duplicate allocation rows for the same period member.

Recommended:

```text id="r4q6dz"
UNIQUE(expense_id, period_member_id)
```

---

# 64. `payments`

## Purpose

Represents money paid by a member into the mess.

## Fields

```text id="j5vp0m"
id UUID PK
period_id UUID FK
period_member_id UUID FK
payment_date DATE
amount NUMERIC
note TEXT NULL
created_at TIMESTAMPTZ
created_by UUID
updated_at TIMESTAMPTZ
updated_by UUID
```

Optional future field:

```text payment_method
```

---

# 65. Payment Semantics

A payment is a financial contribution/payment event.

It is not an expense.

---

# 66. Payment Amount

Must be:

```text > 0
```

Normal negative payments are not allowed.

Refunds should be represented as explicit credits/adjustments or a future refund mechanism.

---

# 67. Payment History

Payments should not be merged into one running balance field.

Example:

```text id="76kz5m"
5 Sep  ৳1,000
10 Sep ৳1,500
20 Sep ৳1,500
```

Each remains independently auditable.

---

# 68. `adjustments`

## Purpose

Represents exceptional manual credits/debits.

## Fields

```text id="un1muj"
id UUID PK
period_id UUID FK
period_member_id UUID FK
adjustment_type adjustment_type
amount NUMERIC
adjustment_date DATE
reason TEXT
created_at TIMESTAMPTZ
created_by UUID
updated_at TIMESTAMPTZ
updated_by UUID
```

---

# 69. Adjustment Type

```text id="vdwf5q"
CREDIT
DEBIT
```

The amount itself remains positive.

This is cleaner than mixing negative numbers throughout the data model.

---

# 70. Adjustment Examples

Credit:

```text id="8xr0eb"
Previous overcharge
৳100
```

Debit:

```text id="82imw1"
Broken household item
৳300
```

---

# 71. `opening_balances`

## Purpose

Represents a carried balance entering a period.

## Fields

```text id="6mygrq"
id UUID PK
period_id UUID FK
period_member_id UUID FK
amount NUMERIC
balance_direction balance_direction
source_period_id UUID NULL
created_at TIMESTAMPTZ
created_by UUID
```

---

# 72. Opening Balance Direction

Use structured semantics:

```text id="u3uy4u"
CREDIT
DUE
```

rather than relying on negative/positive signs alone.

---

# 73. Why Opening Balance Is Separate

A September credit should not be silently inserted into October's expenses.

Instead:

```text id="sp9o11"
September closing balance
         ↓
October opening balance
```

This makes carry-forward explicit.

---

# 74. Opening Balance Source

Where applicable:

```text source_period_id
```

should reference the prior period.

This provides traceability.

---

# 75. Opening Balance Integrity

An automatically carried opening balance should correspond to a prior finalized closing balance.

Manual opening balances, if supported, must carry a reason and audit event.

---

# 76. Settlement Architecture

A settlement should have two layers.

## Period-level settlement

```text id="q4l9x2"
settlement_snapshots
```

## Member-level settlement

```text id="3q6w6p"
settlement_member_snapshots
```

---

# 77. `settlement_snapshots`

## Purpose

Stores the finalized accounting state when a period is closed.

## Fields

```text id="44twv7"
id UUID PK
period_id UUID FK
status settlement_status
meal_units_total NUMERIC
meal_cost_total NUMERIC
meal_rate NUMERIC NULL
shared_cost_total NUMERIC
payment_total NUMERIC
adjustment_total NUMERIC
closing_balance_total NUMERIC
generated_at TIMESTAMPTZ
finalized_at TIMESTAMPTZ NULL
calculation_version TEXT
```

---

# 78. Calculation Version

`calculation_version` is extremely useful.

Example:

```text id="clycqe"
v1.0
```

If the calculation algorithm changes in future software versions, the historical snapshot identifies which calculation rules generated the result.

---

# 79. Why Snapshot?

Suppose V2 changes:

```text id="zpfqxt"
rounding algorithm
```

The September 2026 final statement should not silently change from:

```text ৳100.00
```

to:

```text ৳99.99
```

merely because the software was updated.

Snapshots protect historical accounting.

---

# 80. `settlement_member_snapshots`

## Purpose

Stores the final member-level result.

## Fields

```text id="x96xui"
id UUID PK
settlement_snapshot_id UUID FK
period_member_id UUID FK
meal_units NUMERIC
food_cost NUMERIC
shared_cost NUMERIC
credit_adjustments NUMERIC
debit_adjustments NUMERIC
opening_balance NUMERIC
payments NUMERIC
total_obligation NUMERIC
final_balance NUMERIC
balance_status settlement_balance_status
generated_at TIMESTAMPTZ
```

---

# 81. Member Settlement Status

```text id="71egc9"
DUE
CREDIT
SETTLED
```

---

# 82. Snapshot Immutability

Once a settlement snapshot is finalized:

Normal application operations must not modify it.

If a period is reopened, a new recalculated snapshot can be generated after the revised close.

The previous finalized state should remain auditable.

---

# 83. Reopened Period Strategy

Recommended model:

```text id="5qgzk4"
Settlement V1
     ↓
Period reopened
     ↓
New calculations
     ↓
Settlement V2
```

The audit/history system records the transition.

This is more robust than overwriting one historical snapshot.

---

# 84. Settlement Versioning

A `version` or sequence number can be added:

```text id="1t6c6v"
snapshot #1
snapshot #2
snapshot #3
```

Only the latest finalized snapshot is current for that period, while previous snapshots remain historical/auditable.

---

# 85. Audit Model

## `audit_events`

Purpose:

Record important actions and changes.

## Fields

```text id="y2r6c8"
id UUID PK
mess_id UUID FK NULL
period_id UUID FK NULL
actor_user_id UUID FK
event_type TEXT / ENUM
entity_type TEXT
entity_id UUID
old_data JSONB NULL
new_data JSONB NULL
reason TEXT NULL
created_at TIMESTAMPTZ
```

---

# 86. Audit Entity Scope

Audit can reference:

* mess
* period
* membership
* manager assignment
* meal
* expense
* allocation
* payment
* adjustment
* settlement

---

# 87. Audit Actor

Every privileged mutation should identify the authenticated user who initiated it.

---

# 88. Audit Event Examples

```text id="ln55o8"
MEMBER_APPROVED
MANAGER_ASSIGNED
MEAL_CREATED
MEAL_UPDATED
EXPENSE_CREATED
EXPENSE_UPDATED
ALLOCATION_UPDATED
PAYMENT_CREATED
PAYMENT_UPDATED
ADJUSTMENT_CREATED
PERIOD_CLOSED
PERIOD_REOPENED
JOIN_CODE_REGENERATED
MEMBER_ENDED
```

---

# 89. Audit Old/New Data

For editable financial records, retaining relevant before/after values is strongly recommended.

Example:

```text id="z0b4w4"
old:
{ amount: 850 }

new:
{ amount: 800 }
```

---

# 90. Audit Data Size

Do not blindly store entire giant database rows in JSONB for every event.

Store the relevant changed fields.

This keeps audit history useful and manageable.

---

# 91. Relationships Summary

```text id="e9zfe0"
profiles
   │
   ├──< mess_join_requests >── messes
   │
   └──< period_members >────── periods
                                 │
                                 ├──< manager_assignments
                                 ├──< period_meal_types
                                 ├──< meals
                                 ├──< expenses
                                 │        │
                                 │        └──< expense_allocations
                                 │
                                 ├──< payments
                                 ├──< adjustments
                                 ├──< opening_balances
                                 └──< settlement_snapshots
                                            │
                                            └──< settlement_member_snapshots
```

---

# 92. Complete ERD — Logical Form

```text id="g3r0j3"
AUTH.USERS
    │
    └──── 1:1 ──── PROFILES
                        │
                        │
                        ├───────────────< MESS_JOIN_REQUESTS >───────────────┐
                        │                                                      │
                        │                                                      ▼
                        │                                                   MESSES
                        │                                                      │
                        │                                                      ├──< MESS_JOIN_CODES
                        │                                                      │
                        │                                                      └──< PERIODS
                        │                                                           │
                        │                                                           ├──< PERIOD_MEMBERS >── PROFILES
                        │                                                           │       │
                        │                                                           │       ├──< MEALS
                        │                                                           │       ├──< PAYMENTS
                        │                                                           │       ├──< ADJUSTMENTS
                        │                                                           │       └──< OPENING_BALANCES
                        │                                                           │
                        │                                                           ├──< MANAGER_ASSIGNMENTS >── PROFILES
                        │                                                           │
                        │                                                           ├──< PERIOD_MEAL_TYPES
                        │                                                           │
                        │                                                           ├──< EXPENSES
                        │                                                           │       │
                        │                                                           │       └──< EXPENSE_ALLOCATIONS
                        │                                                           │
                        │                                                           └──< SETTLEMENT_SNAPSHOTS
                        │                                                                    │
                        │                                                                    └──< SETTLEMENT_MEMBER_SNAPSHOTS
                        │
                        └───────────────────────────────────────────────────────────────< AUDIT_EVENTS
```

---

# 93. Why `period_members` Is Central

Most protected operations can follow:

```text id="xk4eon"
user
 ↓
period_member
 ↓
period
 ↓
mess
```

This is powerful because authorization can then answer:

> Is this authenticated user a member of this period?

and:

> Is this period member the manager?

through relational data.

---

# 94. Why Meals Reference `period_member_id`

Rather than:

```text meal.user_id
```

use:

```text meal.period_member_id
```

This binds the meal directly to the accounting context.

---

# 95. Why Expenses Reference `paid_by_period_member_id`

This prevents an expense from being paid by an unrelated user and clearly ties the payer to the relevant period membership.

---

# 96. Why Allocations Reference `period_member_id`

The beneficiary must belong to the same period context.

This makes cross-period allocation errors much harder.

---

# 97. Why Payments Reference Period Membership

A payment should belong to a member in the accounting context in which it is recorded.

---

# 98. Why Adjustments Reference Period Membership

Adjustments affect a member's settlement in a specific period.

Therefore:

```text period_member_id
```

is appropriate.

---

# 99. Why Manager Is Not Just a Column on `messes`

A global field:

```text id="hi3o2s"
messes.manager_id
```

would make historical manager data difficult.

If the manager changes:

```text A → B
```

the system could lose the fact that A managed September while B managed October.

Period-specific assignment solves this.

---

# 100. Why Membership Is Not Just on `messes`

A global:

```text id="memx0q"
mess_members
```

table without period context would make historical settlement difficult when people join/leave.

Period membership solves that.

---

# 101. Current Membership vs Historical Membership

The database should not infer history from current status.

Example:

Current:

```text A = inactive
```

does not tell us whether A:

* belonged in August
* belonged in September
* never belonged
* left in September

Period-specific membership does.

---

# 102. Current Period

A mess may have a convenient reference to its current period:

```text current_period_id
```

but this should be treated as a convenience pointer.

The period table remains the authoritative historical structure.

---

# 103. Current Manager

Likewise, the mess may cache a current manager for UI convenience.

However, manager assignment records remain authoritative.

---

# 104. Derived vs Stored Data

## Store

* meals
* expenses
* expense allocations
* payments
* adjustments
* opening balances
* membership
* manager assignment
* period configuration

## Derive

* total meals
* meal rate
* member food cost
* shared cost total
* total charge
* current balance

## Snapshot

* finalized settlement totals

---

# 105. Why Not Store Every Balance Directly?

A field such as:

```text id="t86swe"
members.current_balance
```

creates synchronization problems.

Suppose a payment is edited.

Now many balance columns may need manual updates.

It is safer to derive the balance from the underlying accounting facts.

---

# 106. Why Snapshot Final Balances?

Once a month is finalized, preserving the exact final result is useful.

This gives:

```text live calculations
+
finalized accounting snapshot
```

rather than forcing historical statements to depend exclusively on current runtime formulas.

---

# 107. Calculation Inputs by Period

For a given period:

```text id="2bj1e3"
period
 ├── configuration
 ├── members
 ├── meals
 ├── expenses
 │    └── allocations
 ├── payments
 ├── adjustments
 └── opening balances
```

These become the calculation engine's inputs.

---

# 108. Transaction Ownership

Every operational record should be traceable to:

```text id="0j9p2x"
mess
period
```

directly or indirectly.

This makes RLS policies and audit queries substantially easier.

---

# 109. Foreign Key Strategy

Recommended:

### Restrict

for historical entities that must not disappear.

### Set null

for optional actor/reference fields where appropriate.

### Cascade

only for genuinely subordinate data where deleting the parent is itself safe.

Avoid broad cascades on financial records.

---

# 110. Important Cascade Warning

Do not allow:

```text id="u4i8k4"
delete user
 ↓
delete all meals
 ↓
delete all payments
 ↓
delete all settlements
```

This would destroy accounting history.

Historical references must be protected.

---

# 111. User Deletion Implications

Because Supabase Auth user deletion can interact with foreign keys, the eventual schema must carefully choose whether profile/member references:

* prevent deletion
* become anonymized
* use a durable historical identity layer

The safest V1 architecture is to avoid automatic cascades from user deletion into financial records.

---

# 112. Suggested Historical Identity Approach

A profile row can remain as a historical application identity even if authentication access is later removed.

Potential future state:

```text id="7x0s6i"
profile.status = DEACTIVATED
```

while historical financial records remain.

---

# 113. Mess Join Code Relationship

A mess can have many historical codes:

```text id="9f71o2"
mess
 ├── code 1 revoked
 ├── code 2 revoked
 └── code 3 active
```

This is superior to simply overwriting `messes.join_code`.

---

# 114. Joining a Mess and Period Creation

A new approved member should not necessarily create a new period automatically.

Membership approval should map to the appropriate open period according to the current workflow.

---

# 115. New Period Membership

When creating a new period:

```text id="e2v5dr"
Previous period active members
        ↓
review
        ↓
new period_members
```

Do not merely update their old period membership rows.

---

# 116. Ended Members

An ended member remains linked to:

* old period
* old meals
* old expenses
* old payments
* old statements

but is not eligible for future operations.

---

# 117. Expense Date and Period

An expense's date should normally be within:

```text period.start_date
to
period.end_date
```

The same applies to:

* meals
* payments
* adjustments

unless a controlled exception exists.

---

# 118. Cross-Period Payments

The model should not casually support a payment dated October inside September.

Instead, the operation should target an explicit period.

If the product later allows payments for prior/future obligations, that should be modeled as a deliberate cross-period ledger mechanism.

---

# 119. Guest Meals and Period Membership

Guest meals do not require their own period membership.

They are attributed to:

```text host period member
```

---

# 120. Guest Meal Eligibility

The host must be active/eligible for the meal date.

---

# 121. Meal Type History

Suppose current configuration changes:

```text Dinner weight:
1 → 1.2
```

Historical periods must retain their original weight.

Therefore period meal types should be immutable after period closure.

---

# 122. Period Configuration Changes

Configuration changes in an open period may be allowed.

After closure:

* historical configuration is frozen.

Changes to future periods do not affect previous periods.

---

# 123. Expense Category History

If a category is renamed later:

```text Internet → Connectivity
```

historical statements should ideally retain the historically recorded category identity/name or snapshot display value.

Do not make historical reports depend exclusively on mutable current category names.

---

# 124. Recommended Category Strategy

Category records may contain:

```text id
code
name
```

and transaction records can reference the category.

For finalized snapshots, the displayed category name may also be captured where historical presentation stability matters.

---

# 125. Audit Scope

Audit records should be associated with both:

```text mess_id
period_id
```

where applicable.

This makes manager queries efficient.

---

# 126. Audit Event Actor

If an actor later becomes inactive:

The audit still retains their user/profile identity.

---

# 127. Unique Constraints Summary

Important uniqueness/integrity rules include:

```text id="3rg4tx"
profiles.id = auth.users.id

one active join code per mess

one pending join request per user + mess

one period membership per user + period

one current manager per period

one meal aggregate per period_member + date + meal_type + guest context

one allocation per expense + period_member

no overlapping periods for same mess

one finalized current settlement version per period
```

---

# 128. Check Constraints Summary

Likely checks:

```text id="y49bc2"
period.start_date <= period.end_date

expense.amount > 0

payment.amount > 0

adjustment.amount > 0

meal.quantity > 0

allocation.amount >= 0

weight > 0 where used

fixed allocation totals reconcile through transactional validation
```

---

# 129. Index Strategy

Likely indexes:

### Periods

```text id="4of2y4"
mess_id
status
start_date
```

### Period members

```text id="crs4xq"
period_id
user_id
membership_status
```

### Meals

```text id="6cw7sq"
period_id
period_member_id
meal_date
meal_type_id
```

### Expenses

```text id="6u5uj7"
period_id
expense_date
category
paid_by_period_member_id
```

### Allocations

```text id="8ze3jw"
expense_id
period_member_id
```

### Payments

```text id="9fie2q"
period_id
period_member_id
payment_date
```

### Adjustments

```text id="fj8l1l"
period_id
period_member_id
adjustment_date
```

### Audit

```text id="a8j5j3"
mess_id
period_id
entity_type
entity_id
created_at
actor_user_id
```

---

# 130. Indexing Principle

Do not index every column.

Indexes should correspond to:

* common filters
* joins
* RLS checks
* chronological lists
* settlement aggregation

---

# 131. RLS-Friendly Schema

The model intentionally allows RLS to frequently determine:

```text id="zmx5k5"
Does auth.uid()
belong to this period?
```

by joining through:

```text period_members
→ periods
→ messes
```

---

# 132. Manager Authorization Path

Conceptually:

```text id="kwl02k"
auth.uid()
   ↓
period_members
   ↓
manager_assignments
   ↓
period
```

This can be turned into reusable authorization functions.

---

# 133. Member Read Path

For personal data:

```text id="l6ul4x"
auth.uid()
 ↓
period_members
 ↓
meals / payments / allocations / adjustments
```

This makes member-specific RLS relatively straightforward.

---

# 134. Cross-Mess Isolation

Every accounting record ultimately belongs to one period, and every period belongs to one mess.

Therefore:

```text id="23abm4"
record
 ↓
period
 ↓
mess
```

forms the isolation chain.

---

# 135. Avoiding Direct `mess_id` Duplication

Some tables may technically derive mess ownership through period.

For example:

```text meal → period_member → period → mess
```

It may be tempting to store `mess_id` redundantly.

V1 should avoid unnecessary duplicate ownership columns unless performance/RLS analysis shows a strong reason.

This reduces inconsistency risk.

---

# 136. When Redundant `mess_id` Is Useful

Audit events are a reasonable place for direct `mess_id`, because audit queries frequently filter by mess.

Similarly, some denormalized reporting structures could later use redundant mess IDs.

The core transaction tables should remain relationally coherent.

---

# 137. Settlement Snapshot Relationships

A settlement snapshot belongs to exactly one period.

A member settlement belongs to exactly one settlement snapshot and one period member.

Therefore:

```text id="9v1rso"
settlement_member_snapshot.period_member_id
```

must correspond to the snapshot's period.

---

# 138. Historical Snapshot Integrity

A member cannot accidentally appear in a settlement snapshot for a different period.

This should be enforced through transaction-level validation and appropriate relational constraints.

---

# 139. Settlement Reconciliation

Period snapshot should contain enough data to verify:

```text id="n1mcqk"
sum(member.food_cost)
+
sum(member.shared_cost)
+
adjustments
+
opening balances
−
payments
```

against the final balances according to the final accounting formula.

---

# 140. Why Store `calculation_version`

Because accounting software evolves.

Future changes could affect:

* rounding
* guest rules
* allocation rules
* carry-forward
* weighted meals

A version number makes historical results interpretable.

---

# 141. Schema Does Not Own All Calculations

The database schema defines the facts and snapshots.

The calculation engine defines formulas.

The RLS layer defines authorization.

The audit layer defines accountability.

These concerns should remain separated.

---

# 142. Recommended Separation

```text id="x5hsri"
Schema
 ↓
Stores facts

Functions/views
 ↓
Derive calculations

RLS
 ↓
Controls access

Audit
 ↓
Records privileged actions

Snapshots
 ↓
Preserve final accounting
```

---

# 143. Future Inventory Compatibility

If inventory is added later:

```text grocery purchases
```

can continue feeding the expense layer without changing the fundamental settlement model.

---

# 144. Future Multiple-Mess Compatibility

If V2 allows one user to belong to multiple messes:

The existing:

```text period_members
```

model already supports it because membership is mess/period-contextual rather than globally tied to one mess.

The application layer can later support:

```text user → mess A
user → mess B
```

without redesigning the entire accounting model.

---

# 145. Future Multiple Managers

The current model deliberately permits assignment history.

A future co-manager model could expand:

```text one active manager
```

to:

```text multiple management roles
```

without replacing the historical assignment concept.

---

# 146. Future Inventory of Roles

A future role table could support:

```text MANAGER
ACCOUNTANT
ASSISTANT_MANAGER
MEMBER
```

The V1 model can remain simpler.

---

# 147. Recommendation: Do Not Build a Generic RBAC System in V1

The only meaningful application role initially is:

```text manager
vs
member
```

A huge permission matrix would add unnecessary complexity.

Use period manager assignment plus member context.

---

# 148. Recommendation: Avoid a Generic Ledger Table in Initial Schema

It is tempting to create:

```text transactions
```

containing everything.

However, meals, expenses, payments, and adjustments have different structures.

For V1, specialized tables are easier to validate.

A higher-level derived accounting view can unify them conceptually later.

---

# 149. Optional Future `ledger_entries`

A future accounting engine could introduce:

```text ledger_entries
```

generated from operational facts.

This can become useful if the application evolves toward formal double-entry accounting.

It is not necessary for initial V1.

---

# 150. Recommended V1 Accounting Model

Use:

```text id="1xe4vc"
Operational facts
+
allocation facts
+
payment facts
+
adjustment facts
+
opening balance
+
finalized snapshots
```

rather than a full accounting ledger engine.

---

# 151. Data Lifecycle

```text id="q7d6pw"
User registers
     ↓
Profile created
     ↓
Mess created/joined
     ↓
Period membership created
     ↓
Operational records accumulate
     ↓
Settlement calculated
     ↓
Snapshot finalized
     ↓
Period closed
     ↓
Historical records retained
```

---

# 152. Record Lifecycle — Expense

```text id="7t4c5e"
CREATE
  ↓
OPEN/EDITABLE
  ↓
UPDATED (optional)
  ↓
PERIOD CLOSED
  ↓
READ-ONLY
```

If reopened:

```text id="r41n9j"
CLOSED
  ↓
REOPEN
  ↓
EDITABLE
  ↓
FINALIZE NEW SNAPSHOT
```

---

# 153. Record Lifecycle — Meal

```text id="x96pd3"
CREATE
  ↓
UPDATE
  ↓
PERIOD CLOSED
  ↓
READ-ONLY
```

---

# 154. Record Lifecycle — Payment

```text id="r7u9j8"
CREATE
  ↓
UPDATE if open
  ↓
CLOSED
```

---

# 155. Record Lifecycle — Member

```text id="qz46ks"
PENDING
 ↓
ACTIVE
 ↓
ENDED / REMOVED
```

Historical relationship remains.

---

# 156. Record Lifecycle — Period

```text id="x1v2vc"
DRAFT
 ↓
OPEN
 ↓
CLOSED
```

Potential:

```text id="7ko99n"
CLOSED
 ↓
OPEN
 ↓
CLOSED
```

with audit/version history.

---

# 157. Soft Deletion Recommendation

For:

* expenses
* payments
* adjustments

prefer controlled correction/void mechanisms where possible rather than hard deletion.

Meals may be corrected/deleted within an open period because they are operational records, but all important changes remain auditable.

---

# 158. Expense Voiding

A future/optional mechanism:

```text id="l6v4c8"
voided_at
void_reason
```

allows an erroneous expense to remain historically visible without contributing to active calculations.

The calculation engine must explicitly exclude voided records.

---

# 159. Payment Voiding

Similarly, a mistaken payment can be voided rather than physically deleted.

This is safer for accounting history.

---

# 160. Meal Correction

Meals generally need a simpler edit mechanism.

The audit system records the old/new value.

---

# 161. Audit vs Soft Delete

These are separate concepts.

### Soft deletion/void

Controls whether a record participates in current accounting.

### Audit

Records what happened.

Both can be useful.

---

# 162. Date-Based Partitioning

V1 does not need PostgreSQL table partitioning.

Expected mess sizes are small enough that ordinary indexed tables should be sufficient.

---

# 163. UUID Strategy

Recommended:

```text id="4e8dy6"
gen_random_uuid()
```

or equivalent PostgreSQL-supported UUID generation.

All major entities should use UUID primary keys.

---

# 164. Public IDs

The application may expose UUIDs in URLs.

This is acceptable when combined with RLS.

UUIDs are not a substitute for authorization.

---

# 165. Human-Readable Codes

Only the join code should intentionally be optimized for human typing.

---

# 166. Timestamp Strategy

Use `TIMESTAMPTZ` for:

* created_at
* updated_at
* approved_at
* closed_at
* audit timestamps

Use `DATE` for:

* meal date
* expense date
* payment date
* adjustment date
* period dates

---

# 167. Why DATE Matters

Meals happen on a local calendar date.

Using a timestamp for meal day can introduce UTC/local conversion bugs.

The actual creation timestamp can still be stored separately.

---

# 168. Created vs Effective Date

A record can have:

```text id="n3y0n8"
meal_date = 10 Sep
created_at = 11 Sep
```

because a manager may enter yesterday's meal later.

This distinction must be preserved.

---

# 169. Updated Timestamp

All editable operational records should include an update timestamp.

This can support:

* optimistic concurrency
* audit
* UI freshness

---

# 170. Updated By

For privileged editable records, retain:

```text id="j8at8o"
updated_by
```

where feasible.

---

# 171. Created By

Similarly:

```text id="w1t4x3"
created_by
```

identifies the actor who originally entered the record.

---

# 172. System-Generated Records

Settlement snapshots and automatic opening balances may use an explicit system actor representation or a nullable `created_by` with event provenance.

The exact choice will be resolved in the audit specification.

---

# 173. Database Constraints vs Functions

Use simple constraints for local rules:

```text amount > 0
start <= end
```

Use database functions/transactions for cross-row business rules:

```text allocation total = expense total
one active manager
close period only when valid
```

---

# 174. Views

The database may expose views such as:

```text id="t8fzq0"
current_period_summary
member_current_balance
period_expense_summary
period_member_statement
```

These are derived read models.

They should not become alternate sources of truth.

---

# 175. Calculation Views

A member statement view may combine:

```text id="wtf4y5"
meal aggregates
+
expense allocation aggregates
+
payment aggregates
+
adjustment aggregates
+
opening balance
```

This can significantly simplify frontend queries.

---

# 176. Security of Views

Views must be designed carefully with Supabase/RLS semantics.

Do not assume a view automatically provides the same authorization guarantees as querying protected base tables.

The exact security model will be specified in the RLS document.

---

# 177. Database Functions

Likely critical functions:

```text id="8v0e3r"
approve_join_request()
transfer_manager()
create_shared_expense()
calculate_period_summary()
calculate_member_statement()
close_period()
reopen_period()
create_next_period()
```

These will be specified later.

---

# 178. Stored Procedures vs Frontend Transactions

Complex workflows should live in trusted backend/database functions rather than requiring many sequential browser requests.

This reduces partial-state risk.

---

# 179. Example — Approve Join Request

The logical transaction:

```text id="u8oz7b"
verify manager
 ↓
verify request pending
 ↓
verify target period
 ↓
create period member
 ↓
mark request approved
 ↓
audit
```

should be atomic.

---

# 180. Example — Shared Expense

```text id="6icp9r"
verify manager
 ↓
create expense
 ↓
calculate/validate allocations
 ↓
insert allocations
 ↓
verify total
 ↓
audit
```

should be atomic.

---

# 181. Example — Close Period

```text id="9cr0i6"
verify manager
 ↓
verify period open
 ↓
run validation
 ↓
calculate final settlement
 ↓
create snapshot
 ↓
mark period closed
 ↓
audit
```

should be atomic.

---

# 182. Schema Design Goal

The schema should make invalid states:

> difficult or impossible to represent.

not merely:

> detectable after they happen.

---

# 183. Invalid State Example

Bad schema:

```text id="lmnw55"
expense.amount = 1000
allocation total = 900
```

with no protection.

Desired:

```text id="t5p7hn"
database transaction rejects final save
```

---

# 184. Invalid State Example — Manager

Bad:

```text id="ifc6i2"
period
 manager A
 manager B
```

Desired:

```text id="x9r0ka"
only one active manager assignment
```

---

# 185. Invalid State Example — Period

Bad:

```text id="b4jv7a"
September:
Sep 1–30

Another period:
Sep 20–Oct 20
```

Desired:

> Overlapping period rejected.

---

# 186. Invalid State Example — Membership

Bad:

```text id="t4uq6u"
same member
two active rows
same period
```

Desired:

> Duplicate membership rejected.

---

# 187. Invalid State Example — Historical Mutation

Bad:

```text id="8ky5ba"
closed period
+
new expense
```

Desired:

> Database rejects mutation.

---

# 188. ERD Design Principle — Historical Context First

Whenever a question involves:

> "What was true in September?"

the database should answer from period-specific records.

It should not reconstruct history by looking at today's state.

---

# 189. ERD Design Principle — Explicit Relationships

Avoid implicit concepts such as:

```text current_manager
```

being the only representation of management.

Prefer:

```text manager_assignments
```

---

# 190. ERD Design Principle — Financial Facts Are Atomic

A meal is a meal record.

An expense is an expense record.

A payment is a payment record.

An allocation is an allocation record.

Do not store a pre-combined monthly number as the only source of truth.

---

# 191. ERD Design Principle — Derived Values Are Disposable

If:

```text member balance
```

can be recomputed from underlying facts, do not make an ordinary mutable balance column the primary truth.

---

# 192. ERD Design Principle — Finalized Values Are Snapshotted

A closed-period settlement is different from a live calculation.

The final state should be retained.

---

# 193. Recommended Core Tables

The minimum production schema should therefore contain approximately:

```text id="l4t0tj"
profiles
messes
mess_join_codes
mess_join_requests

periods
period_members
manager_assignments
period_meal_types

meals

expense_categories
expenses
expense_allocations

payments
adjustments
opening_balances

settlement_snapshots
settlement_member_snapshots

audit_events
```

---

# 194. Optional Tables Deferred From V1

Potential future tables:

```text id="0g3m3p"
mess_settings_history
guest_profiles
payment_methods
receipts
inventory_items
inventory_transactions
notifications
ledger_entries
role_permissions
```

They are not required to implement the V1 product correctly.

---

# 195. Final Logical Model

The complete accounting chain is:

```text id="0ieytp"
USER
 │
 ▼
PROFILE
 │
 ▼
MESS
 │
 ▼
PERIOD
 │
 ▼
PERIOD MEMBER
 │
 ├─────────────► MEALS
 │
 ├─────────────► PAYMENTS
 │
 ├─────────────► ADJUSTMENTS
 │
 └─────────────► OPENING BALANCE
                   

PERIOD
 │
 ├─────────────► EXPENSE
 │                  │
 │                  └────► ALLOCATIONS
 │
 ├─────────────► MANAGER ASSIGNMENT
 │
 ├─────────────► MEAL TYPE CONFIGURATION
 │
 └─────────────► SETTLEMENT SNAPSHOT
                       │
                       └────► MEMBER SNAPSHOT
```

This is the relational foundation the application should be built on.

---

# 196. Handoff to SQL Schema

The next document will convert this logical model into actual PostgreSQL/Supabase implementation.

That document must specify:

* exact table definitions
* UUID generation
* enums
* numeric precision
* timestamps
* foreign keys
* check constraints
* unique constraints
* partial indexes
* general indexes
* update triggers
* database helper functions
* initial seed data
* migration structure

The subsequent RLS document will then define precisely who can `SELECT`, `INSERT`, `UPDATE`, and `DELETE` against each table.
