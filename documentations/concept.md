# Mess Manager

## Product Concept & System Blueprint

**Version:** 1.0
**Platform:** Responsive web application
**Primary stack:** Next.js/React + Supabase + Vercel
**Development:** GitHub Codespaces
**Primary currency:** BDT (৳)
**Primary operating model:** One mess can have multiple members, but only the current manager can modify operational data.

---

## 1. Product Vision

Mess Manager is a centralized financial and meal-management system for shared residential messes.

Its purpose is to eliminate manual calculation of:

* daily meals
* meal rates
* total food expenditure
* individual food costs
* shared expenses
* expenses shared by selected members
* deposits/payments
* credits and outstanding balances
* guests and guest meals
* joining/leaving adjustments
* monthly settlement
* manager transition
* historical records

The system should convert raw inputs into a reliable monthly settlement automatically.

The intended experience is:

> **Manager enters facts → system performs calculations → members view their balances.**

The member should not need to calculate anything manually.

---

# 2. Core Design Principle

The application should distinguish between:

### Facts

Things the manager records:

* who is a member
* which days a member ate
* how many meals they ate
* how much an item cost
* who an expense applies to
* how much someone paid
* whether a meal belongs to a guest
* whether an adjustment was made

### Derived values

Things the system calculates:

* total meals
* food expenditure
* meal rate
* member food cost
* member share of common expenses
* total payable amount
* total paid
* credit/debit balance
* settlement summary
* average meal consumption
* expense statistics

The manager should never have to manually type derived values.

---

# 3. Fundamental Accounting Model

Every monthly settlement should conceptually follow:

**Food Cost**

= Total food/grocery expenditure associated with meals

**Meal Rate**

= Total food cost ÷ Total chargeable meals

**Individual Meal Cost**

= Member chargeable meals × Meal rate

**Shared Cost**

= Member's applicable share of a shared expense

**Adjustments**

= Credits − Debits

**Total Charge**

= Individual meal cost + shared costs + applicable charges − credits

**Net Settlement**

= Total charge − amount already paid

Therefore:

* positive result → member owes the mess
* negative result → mess owes member
* zero → settled

The exact implementation should use integer/decimal-safe monetary arithmetic rather than JavaScript floating-point arithmetic.

---

# 4. The Most Important Entity: Mess Month

The system should not treat a mess as one endlessly changing dataset.

Instead:

**Mess**
→ contains multiple **Mess Periods**

Example:

Mess: `Sunrise Mess`

Periods:

* August 2026
* September 2026
* October 2026

Each period has its own:

* manager
* membership snapshot
* meal records
* expenses
* shared expenses
* payments
* adjustments
* settlement status

This is essential for historical integrity.

Changing the September manager must not rewrite August's manager.

Removing a member from September must not remove their August records.

---

# 5. Mess Lifecycle

A mess should have approximately this lifecycle:

### Stage 1 — Mess creation

A user creates a mess.

They become the initial manager.

The system generates a join code.

### Stage 2 — Member onboarding

A person signs in.

They enter the mess join code.

Their request becomes:

**Pending**

The current manager sees the request.

### Stage 3 — Manager approval

Manager can:

* approve
* reject

Only approved members become active members of the mess period.

### Stage 4 — Monthly operation

Manager records:

* meals
* expenses
* payments
* adjustments
* member status changes

Members can view information but cannot modify operational records.

### Stage 5 — Period closing

Manager reviews the generated settlement.

Once satisfied, manager closes the period.

### Stage 6 — Historical archive

Closed period becomes immutable to ordinary operational editing.

The next month's period can then be created.

---

# 6. Roles

The minimum role model should be:

## Member

Can:

* sign in
* view the mess they belong to
* view current month
* view their own meal history
* view their own expenses/shared-cost allocation
* view their own payments
* view their current balance
* view previous monthly settlements
* see basic member information
* request to join a mess
* leave/request removal according to the configured workflow

Cannot:

* edit meals
* edit expenses
* edit payments
* edit members
* approve members
* change manager
* change meal rate
* create shared costs
* close a month
* reopen a closed month

---

## Manager

Can:

* manage the current mess period
* approve/reject join requests
* manage members
* enter meals
* correct meals
* add expenses
* define expense sharing
* record payments
* create adjustments
* manage guest meals
* initiate a new month
* assign the next manager
* close a month
* view all member balances
* view financial summaries
* view audit history

---

# 7. Manager Rotation

Manager is not a permanent role.

The system should support:

**Manager for September → Manager for October → Manager for November**

A manager assignment belongs to a specific mess period.

Recommended model:

```text
Mess
 ├── September 2026
 │    └── Manager: A
 │
 ├── October 2026
 │    └── Manager: B
 │
 └── November 2026
      └── Manager: C
```

This is much safer than storing:

```text
mess.manager_id
```

as the sole source of truth.

The mess may optionally have a current manager pointer for convenience, but the authoritative manager should belong to the period.

---

# 8. Membership Snapshot

Membership should also be period-specific.

Example:

### September

A
B
C
D

### October

A
B
D
E

C leaving the mess should not alter September.

This means a member can have:

* joined date
* left date
* membership status
* active period membership
* historical period membership

The settlement must always use the membership snapshot relevant to that period.

---

# 9. Joining a Mess

The system should support a human-readable join code such as:

`M7K4P9`

Recommended properties:

* short
* case-insensitive
* easy to type
* random
* revocable
* regeneratable
* never used as the sole authorization mechanism

Flow:

```text
User
 ↓
Enter Join Code
 ↓
System finds Mess
 ↓
System checks eligibility
 ↓
Create Join Request
 ↓
Manager reviews
 ↓
Approve / Reject
 ↓
Approved → Member
```

A join code should not automatically grant membership.

The manager's approval is authoritative.

---

# 10. Join Request Edge Cases

The system must handle:

### Wrong code

Show:

> Invalid or expired join code.

### Code regenerated

Old code immediately stops working.

### Already a member

Do not create another membership.

### Existing pending request

Prevent duplicate requests.

### Rejected user tries again

Allow according to a configurable rule, but retain the previous request in history.

### User already belongs to another mess

Decide whether the product allows multiple messes.

Recommended V1:

**One active mess per user.**

This greatly simplifies accounting and UI.

The database can still be designed so multi-mess support could be added later.

### Member was removed previously

Their old historical records must remain.

If they rejoin later, that should create a new membership period rather than resurrecting historical membership.

---

# 11. Meal Recording Model

Meals should not be stored merely as:

```text
user → total meals
```

The underlying data should be date-based.

Conceptually:

```text
Date
Member
Breakfast
Lunch
Dinner
Extra
Guest
```

This allows:

* corrections
* daily history
* guest tracking
* partial meals
* statistics
* audits

The UI can still provide fast monthly entry.

---

# 12. Meal Types

V1 should support configurable meal types.

Default:

* Breakfast
* Lunch
* Dinner

Potential future support:

* Evening snack
* Special meal
* Custom meal

Each meal record should contain a quantity.

Examples:

```text
Lunch = 1
Dinner = 1
```

or

```text
Lunch = 0.5
```

if the mess permits half meals.

However, fractional meals should be a **mess configuration**, not assumed universally.

---

# 13. Meal Rules

The system should allow a manager to configure:

### Allowed meal quantity

Examples:

* integers only
* 0.5 increments
* arbitrary decimal quantity

### Meal counting

Option A:

Every meal record counts equally.

Option B:

Meal types have weights.

For example:

```text
Breakfast = 0.75
Lunch     = 1.00
Dinner    = 1.00
```

Then:

```text
chargeable meals
=
quantity × meal weight
```

This should be optional.

Default V1:

**All standard meals have weight 1.0.**

---

# 14. Guest Meal System

Guest meals must be handled separately.

Example:

Member A has:

```text
20 personal meals
3 guest meals
```

The manager may configure whether guest meals:

* are charged at the normal meal rate
* include an additional guest surcharge
* are assigned to the host member
* appear separately in settlement

Recommended V1:

Guest meals are charged to the hosting member.

Example:

```text
Meal Rate = ৳58

Member meals = 40
Guest meals = 3

Chargeable meals = 43
```

The guest does not need a user account.

---

# 15. Meal Rate Calculation

The application should calculate meal rate automatically.

Example:

```text
Total food expense = ৳23,400
Total chargeable meals = 400

Meal rate = ৳58.50
```

Important:

The UI should distinguish:

### Exact internal rate

`58.500000...`

from

### Display rate

`৳58.50`

The database calculation must retain sufficient precision.

---

# 16. Zero-Meal Edge Case

Suppose:

```text
Food expenses = ৳10,000
Meals = 0
```

Meal rate cannot be calculated.

The application must **not divide by zero**.

Instead:

> Meal rate unavailable because no chargeable meals have been recorded.

The manager should be prevented from closing the period until the issue is resolved or explicitly handled.

---

# 17. Expense Classification

Not every expense belongs to meals.

Expenses should have categories.

Suggested V1 categories:

* Groceries
* Food
* Cooking gas
* Electricity
* Water
* Internet
* Cleaning
* Maintenance
* Rent
* Household supplies
* Other

The critical distinction is:

### Meal-related expense

Contributes to food/meal cost.

### Shared non-meal expense

Does not affect meal rate.

This distinction prevents a major accounting error.

---

# 18. Shared Costs

Shared costs are expenses that are divided among selected members.

Example:

Internet:

```text
Total = ৳1,000
Participants = A, B, C, D
```

Each gets:

```text
৳250
```

But another expense could be:

```text
Water bill = ৳800
Participants = A, B, C
```

Each gets:

```text
৳266.666...
```

The application must resolve rounding consistently.

---

# 19. Shared Cost Allocation Methods

The system should support at least:

### Equal split

```text
total / participant_count
```

### Weighted split

Example:

```text
A = 2 shares
B = 1 share
C = 1 share
```

### Fixed individual amounts

Example:

```text
A = ৳300
B = ৳250
C = ৳450
```

The total assigned amount must equal the expense amount.

The system should reject an allocation that does not reconcile unless the manager explicitly uses an adjustment mechanism.

---

# 20. Rounding Rule

Financial calculations must use deterministic rounding.

Recommended:

* monetary values stored in decimal/numeric
* calculations done server-side/database-side
* display to 2 decimal places
* final settlement rounded according to a documented rule

For example:

```text
Individual exact share:
৳266.666666...

Displayed:
৳266.67
```

But the system must avoid independently rounding each intermediate value and then accidentally creating a ৳0.01/৳0.02 mismatch.

A final settlement should reconcile exactly.

---

# 21. Shared Cost Allocation Example

Expense:

```text
৳100
```

Three members:

```text
A
B
C
```

Exact:

```text
33.333333...
```

Displayed settlement could become:

```text
A = 33.34
B = 33.33
C = 33.33
```

The extra paisa is assigned deterministically.

For example:

> residual paisa goes to the first participant by stable member ordering.

The allocation algorithm must never depend on random array order.

---

# 22. Expense Paid By vs Expense Charged To

These are different concepts.

Suppose:

A pays ৳1,000 for internet.

But A, B, C and D share the expense.

The record must contain:

```text
Expense amount = ৳1,000
Paid by = A

Allocation:
A = ৳250
B = ৳250
C = ৳250
D = ৳250
```

A's settlement therefore receives a ৳1,000 payment/credit and a ৳250 expense charge.

Net effect:

A effectively advances ৳750 on behalf of the others.

This distinction is fundamental.

---

# 23. Payment Tracking

Members may pay the mess during the month.

Example:

```text
Required = ৳4,700
Paid = ৳3,000
Balance = ৳1,700
```

The system should support multiple payments.

```text
15 Sep → ৳2,000
22 Sep → ৳1,000
28 Sep → ৳1,700
```

Total:

```text
৳4,700
```

No manual running-balance calculation should be necessary.

---

# 24. Overpayment

Suppose:

```text
Required = ৳4,500
Paid = ৳5,000
```

Then:

```text
Credit = ৳500
```

The system should display:

> You have ৳500 credit.

Do not represent this as a negative "amount due" without explanation.

The UI should distinguish:

* Amount due
* Credit
* Settled

---

# 25. Carry-Forward

A credit or unpaid amount may optionally carry into the next period.

Recommended:

At month close, produce:

```text
Closing balance
```

Then the next month may begin with:

```text
Opening balance
```

Example:

September:

```text
Final payable = ৳4,800
Paid = ৳5,000

Closing credit = ৳200
```

October:

```text
Opening credit = ৳200
```

This should be an explicit ledger entry rather than silently changing October's expenses.

---

# 26. Adjustments

Managers may need to correct exceptional situations.

Examples:

* previous overcharge
* damaged item reimbursement
* refund
* personal purchase
* compensation
* rounding correction
* disciplinary/fine-related charge if the mess chooses to use such a feature

Adjustment types should include:

```text
Credit
Debit
```

Every adjustment requires:

* amount
* affected member
* reason
* date
* manager
* optional note

An adjustment should never simply overwrite a previous calculation.

---

# 27. Immutable Accounting Principle

After a transaction has been entered, corrections should preferably create an audit trail.

Example:

Original expense:

```text
৳850
```

Correction:

```text
Original = ৳850
Correct = ৳800
```

The system should preserve the fact that a correction occurred.

The manager can correct the operational record through the UI, but the system should retain an audit event such as:

```text
Expense edited
Old amount: ৳850
New amount: ৳800
Changed by: Manager
Reason: duplicate item
```

---

# 28. Closed Month

A closed period should be treated as an accounting snapshot.

After closure:

### Members

Read-only.

### Previous manager

Read-only.

### Current manager

Read-only by default.

No normal edits should be allowed.

If reopening is required, make it an explicit high-risk operation.

Recommended V1:

> Only the current manager may reopen a recently closed period, and reopening requires a reason.

All reopening actions must be audited.

A stronger future version could require a second authorization mechanism.

---

# 29. Month-End Workflow

The ideal manager workflow:

```text
Daily
 ↓
Record meals
 ↓
Record expenses
 ↓
Record payments

During month
 ↓
Review totals
 ↓
Correct discrepancies

Month end
 ↓
Review members
 ↓
Review meal totals
 ↓
Review expenses
 ↓
Review shared allocations
 ↓
Review payments
 ↓
Review balances
 ↓
Confirm settlement
 ↓
Close month
 ↓
Create next period
 ↓
Assign next manager
```

---

# 30. Automatic Validation

Before a period can be closed, the application should run checks.

Examples:

### Membership validation

* Is there a manager?
* Are there duplicate active memberships?
* Are all required members valid?

### Meal validation

* Are meal quantities valid?
* Are any records outside the period?
* Are there zero chargeable meals?

### Expense validation

* Does every expense have a category?
* Does every shared expense reconcile?
* Are all participants members of the period?

### Payment validation

* Does every payment belong to a valid member?
* Is the amount positive?
* Does the payment date belong to the period unless explicitly marked otherwise?

### Settlement validation

* Do all allocations reconcile?
* Does every member have a determinable balance?
* Does the ledger balance?

The close button should show any blocking issues before allowing closure.

---

# 31. Data Integrity Rules

The application should enforce these at the database level whenever practical.

Examples:

### Amounts

Must be:

```text
>= 0
```

### Expense allocation

Total allocation must equal expense amount.

### Member-dependent records

A meal/payment/allocation must reference a valid period membership.

### Manager

At most one active manager for a period.

### Join request

Prevent duplicate pending requests.

### Period

Cannot have overlapping date ranges for the same mess.

### Closed period

Operational transactions cannot be altered through ordinary client calls.

---

# 32. Audit Log

An audit log should be considered a core feature, not an optional future enhancement.

Record events such as:

* mess created
* join request created
* member approved
* member rejected
* member removed
* manager assigned
* manager changed
* meal created
* meal edited
* expense created
* expense edited
* allocation changed
* payment added
* payment edited
* adjustment created
* period opened
* period closed
* period reopened
* join code regenerated

Audit records should include:

```text
actor
event
entity
entity_id
timestamp
old data where appropriate
new data where appropriate
reason where appropriate
```

Members should not be able to manipulate the audit log.

---

# 33. Dashboard

The manager dashboard should answer:

> "How is the mess doing right now?"

Suggested cards:

### Current meal rate

`৳58.50`

### Total food expense

`৳23,400`

### Total meals

`400`

### Other shared costs

`৳6,850`

### Money collected

`৳21,000`

### Outstanding

`৳4,250`

### Members

`7 active`

Then:

* today's meals
* recent expenses
* pending join requests
* members owing money
* members with credit
* month completion status

---

# 34. Member Dashboard

Members should see a simpler dashboard.

Example:

```text
September 2026

Your Meals
42

Meal Rate
৳58.50

Food Cost
৳2,457.00

Shared Costs
৳650.00

Adjustments
-৳100.00

Total
৳3,007.00

Paid
৳2,500.00

Due
৳507.00
```

The member should not see management controls.

---

# 35. Monthly Settlement Statement

Every member should have a generated settlement breakdown.

Example:

```text
September 2026

Meals
Breakfast      10
Lunch          18
Dinner         14
Guest           2
------------------
Total          44

Food cost
44 × ৳58.50 = ৳2,574.00

Shared expenses
Internet          ৳200
Water             ৳150
Cleaning          ৳100

Adjustments
Credit           -৳50

Total payable
৳2,974.00

Payments
৳2,500.00

Outstanding
৳474.00
```

This is much more useful than simply showing:

> "You owe ৳474."

---

# 36. Reporting

Manager should have:

### Monthly overview

* total food expenses
* total meals
* meal rate
* total shared expenses
* total payments
* outstanding amount
* credits

### Member report

For each member:

* meals
* food cost
* shared cost
* adjustments
* paid
* balance

### Expense report

* category
* total
* payer
* sharing method

### Historical report

Month-by-month:

```text
Aug
Sep
Oct
Nov
```

with meal rate and total expenditure.

---

# 37. Search and Filtering

Manager should be able to filter:

* date
* member
* expense category
* payer
* payment status
* transaction type

This becomes increasingly important as the month gets longer.

---

# 38. Manager Productivity Features

The manager should not be forced to enter every meal individually.

Provide fast-entry interfaces.

Example:

### Daily meal grid

| Member | Breakfast | Lunch | Dinner |
| ------ | --------: | ----: | -----: |
| A      |         1 |     1 |      1 |
| B      |         0 |     1 |      1 |
| C      |         1 |     1 |      0 |

The manager can edit an entire day's grid.

Another useful action:

> Copy yesterday's meal pattern.

This should create new records but never modify yesterday's records.

---

# 39. Bulk Operations

Useful manager operations:

* copy previous day
* copy previous week's pattern
* mark all members as 1 meal
* clear day
* bulk add payment
* bulk member selection for shared expense

Bulk actions must still respect validation and audit rules.

---

# 40. Important Edge Cases

The system should explicitly handle:

### Member joins mid-month

Their meal records begin from their actual membership start date.

### Member leaves mid-month

They retain records up to their departure date.

### Member rejoins

Creates a new membership episode.

### Manager changes mid-month

Allowed if necessary, but historical records remain in the same period.

Manager assignment history must be preserved.

### Manager leaves

A replacement manager must be assigned before management access disappears.

### Manager account becomes inaccessible

Another authorized manager may need to be assigned through a controlled recovery process.

This is a product-level concern and should be designed before launch.

---

# 41. Manager Handover

A manager transfer should be an explicit workflow.

Example:

```text
Current Manager
 ↓
Select new manager
 ↓
Select effective date/period
 ↓
Review permissions
 ↓
Confirm
 ↓
New manager becomes manager
 ↓
Old manager becomes member
```

The previous manager should not remain a manager accidentally.

A manager should generally remain a member unless explicitly removed.

---

# 42. Join Code Security

The join code is an invitation mechanism, not a password.

Recommended properties:

* random generation
* limited length
* case-insensitive input
* revocable
* regeneratable
* rate-limited join attempts
* no user-data leakage from invalid attempts
* never expose sensitive mess information before authentication/approval

Potential future enhancement:

```text
Join code
+
expiration
```

---

# 43. Member Visibility

Because members cannot edit anything, the UI should be read-oriented.

Members can inspect:

* their own financial information
* their own meal history
* their own payment history
* the mess's current month summary
* possibly other members' names/status

But financial privacy should be configurable.

Recommended V1:

Members can see:

```text
member names
meal counts
mess-level totals
```

but not necessarily other members' detailed balances.

Manager can see everything.

---

# 44. Privacy Boundary

A strong default model:

### Member

```text
Own detailed financial records
+
Own meal records
+
Mess-level aggregate information
```

### Manager

```text
All member financial records
+
All operational records
```

The database must enforce this rather than merely hiding UI buttons.

---

# 45. Database Architecture Philosophy

The browser should never be trusted to determine:

```text
"is this user the manager?"
```

The database should enforce it.

Likewise:

```text
"Can this user update this expense?"
```

must be answered by database authorization.

Supabase's RLS model is well suited to this. Policies can use the authenticated user's identity through `auth.uid()`, and the policy layer can restrict rows and operations directly at the database level.

---

# 46. Recommended High-Level Database Structure

Conceptually:

```text
auth.users
     │
     ▼
profiles
     │
     ├──────────────┐
     ▼              ▼
mess_memberships   messes
                      │
                      ▼
                 mess_periods
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
       meals       expenses    payments
                      │
                      ▼
               expense_allocations

mess_periods
     │
     ├── period_members
     ├── manager_assignment
     ├── adjustments
     ├── settlements
     └── audit_logs
```

The exact schema will be specified later.

---

# 47. Calculation Architecture

Critical calculation logic should not exist only in React/JavaScript.

Recommended architecture:

```text
Raw records
     ↓
PostgreSQL functions/views
     ↓
Canonical calculations
     ↓
Frontend display
```

The frontend can calculate temporarily for previews, but the authoritative result should come from the database/server.

For example:

```text
calculate_period_summary(period_id)
calculate_member_statement(period_id, member_id)
calculate_shared_allocation(expense_id)
```

This prevents different screens from producing different answers.

---

# 48. Materialized vs Live Calculations

V1 should prefer live/database-derived calculations rather than permanently storing every calculated number.

Store:

```text
meal records
expense records
allocations
payments
adjustments
```

Calculate:

```text
meal rate
food cost per member
shared cost total
balance
```

The exception is a **closed settlement snapshot**, where retaining the finalized result is useful for historical integrity.

---

# 49. Settlement Snapshot

When a period closes, the application should preserve:

* final meal rate
* final meals
* final food cost
* final shared costs
* final adjustments
* final payments
* final member balances

This provides an accounting snapshot.

Even if formulas change in a later app version, old closed months should remain historically consistent.

---

# 50. Recommended V1 Scope

The first production version should include:

### Authentication

* sign up
* login
* logout
* email verification
* password reset

Supabase Auth supports email/password authentication and provides the authenticated identity used by the database authorization layer.

### Mess

* create mess
* mess settings
* join code
* regenerate code
* join requests
* approve/reject members

### Membership

* member list
* active/inactive status
* joining date
* leaving date
* manager assignment

### Meals

* daily meal grid
* breakfast/lunch/dinner
* guest meals
* bulk entry
* corrections

### Expenses

* expenses
* categories
* payer
* meal/non-meal classification
* shared allocations

### Payments

* record payments
* payment history
* balances

### Adjustments

* credit/debit
* reasons
* history

### Settlement

* automatic meal rate
* member cost
* shared cost
* payment deduction
* due/credit calculation
* monthly statement
* close month

### Security

* Supabase RLS
* manager-only mutation policies
* member read restrictions
* audit logs

---

# 51. Features Deliberately Excluded From V1

To prevent the first release from becoming unnecessarily complex:

* online payment gateway
* bank integration
* OCR receipt scanning
* AI expense categorization
* WhatsApp integration
* push notifications
* multi-currency
* complex tax accounting
* restaurant inventory management
* automatic grocery purchasing
* advanced forecasting
* subscription billing

These can come later.

---

# 52. V2 Possibilities

After V1 is stable:

### Inventory

Track:

```text
Rice
Oil
Eggs
Vegetables
Meat
```

### Grocery ledger

Track purchases and inventory consumption.

### Notifications

* pending join request
* payment reminder
* month closing reminder

### Analytics

* monthly meal-rate trend
* expense trends
* member consumption patterns

### Export

* PDF settlement
* CSV
* Excel

### Receipt storage

Attach expense receipts.

### Multiple managers

Potentially:

* primary manager
* assistant manager
* accountant

### Multiple messes

Allow one account to belong to multiple messes.

---

# 53. Product Success Criterion

The application succeeds if a manager can run an entire month without manually calculating the final settlement in a calculator or spreadsheet.

The ideal operation is:

```text
Enter data
      ↓
Review automatically generated numbers
      ↓
Fix exceptions
      ↓
Close month
      ↓
Everyone receives a clear settlement
```

The manager should spend time entering and verifying facts—not doing arithmetic.

---

# 54. Core Product Rule

The most important rule of the entire system is:

> **Never silently change historical financial data because a current membership, manager, configuration, or formula changed.**

Every historical period needs its own context.

---

# 55. Initial Architecture Decision

Recommended technical model:

```text
Frontend
Next.js + React
        │
        ▼
Supabase Client
        │
        ├── Supabase Auth
        │
        └── Supabase Postgres
                │
                ├── RLS
                ├── Functions
                ├── Triggers
                ├── Views
                └── Audit system

Deployment
Vercel

Development
GitHub Codespaces
```

Supabase's current architecture supports Auth integrated with Postgres/RLS, while database functions and triggers can be used for server-side data logic.

---

# 56. Planned Specification Set

The complete project documentation should be produced in this order:

**Document 1 — Product Concept & System Blueprint**
Defines the product, accounting model, lifecycle, roles, edge cases, and architecture principles.

**Document 2 — PRD (Product Requirements Document)**
Defines user problems, goals, personas, product scope, user journeys, functional capabilities, priorities, acceptance criteria, and release strategy.

**Document 3 — FRD (Functional Requirements Document)**
Defines every system behavior in implementation-level detail: inputs, outputs, validations, workflows, permissions, calculations, state transitions, and error handling.

**Document 4 — Non-Functional & Technical Requirements Specification**
Defines security, performance, reliability, accessibility, responsiveness, privacy, auditability, browser support, maintainability, backup/recovery assumptions, and deployment requirements.

**Document 5 — Information Architecture & UI/UX Profile**
Defines design language, navigation, interaction patterns, responsive behavior, manager/member experiences, component system, states, forms, tables, dashboards, dialogs, empty states, errors, and accessibility.

**Document 6 — Page-by-Page UI/UX Specification**
Defines every page, section, component, action, state, permission, API/data requirement, and mobile/desktop layout.

**Document 7 — Data Model / ERD Specification**
Defines every entity, relationship, field, enum, constraint, index, derived value, and lifecycle.

**Document 8 — Supabase PostgreSQL Schema**
The actual SQL migration/schema code.

**Document 9 — Supabase RLS & Authorization Specification**
Defines member/manager policies table by table, including security-definer functions where required.

**Document 10 — Calculation Engine Specification**
Defines the exact mathematical formulas, rounding behavior, allocation algorithms, carry-forward rules, zero-meal behavior, and settlement reconciliation.

**Document 11 — Audit & Data Integrity Specification**
Defines immutable history, corrections, audit events, closed-period behavior, and recovery workflows.

**Document 12 — API / Server Action Specification**
Defines the frontend-to-Supabase interaction model and which operations must occur through database functions or server-side code.

**Document 13 — Validation & Error-State Specification**
Defines user-facing and system-level validation for every major input and workflow.

**Document 14 — Test Plan**
Defines unit, integration, RLS/security, calculation, workflow, regression, mobile, and end-to-end test cases—including pathological financial cases.

**Document 15 — Deployment & Environment Specification**
Defines GitHub Codespaces setup, environment variables, Supabase configuration, Vercel deployment, migrations, production safeguards, and development/production separation.

**Document 16 — Implementation Roadmap**
Breaks the entire system into development phases that can actually be implemented in Codespaces without trying to build everything simultaneously.
