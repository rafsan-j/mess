# Mess Manager

## Product Requirements Document (PRD)

**Document version:** 1.0
**Product version:** V1
**Platform:** Responsive web application
**Primary deployment:** Vercel
**Backend / Auth / Database:** Supabase
**Development environment:** GitHub Codespaces
**Primary currency:** BDT (৳)
**Document status:** Product baseline

---

# 1. Executive Summary

Mess Manager is a web application designed to manage the financial and operational accounting of a shared residential mess.

The product replaces manual calculations and spreadsheets with an automated system for:

* member management
* manager management
* mess joining and approval
* daily meal tracking
* guest meals
* grocery/food expenses
* non-food shared expenses
* selected-member cost sharing
* payments
* credits/debits
* monthly settlement
* historical records
* auditability

The system is intentionally designed around a fundamental separation:

> **Managers enter operational facts. The system performs the accounting.**

Members are primarily consumers of information. They can view their records and balances but cannot modify mess data.

The application's most important product requirement is that **historical accounting must remain stable even when the current membership, manager, or configuration changes.**

---

# 2. Product Problem

Shared messes commonly depend on some combination of:

* paper meal charts
* calculators
* notebooks
* spreadsheets
* Messenger/WhatsApp messages
* manually maintained expense lists

This creates recurring problems:

1. Meal counts are difficult to maintain accurately.
2. Expenses can be forgotten or duplicated.
3. Shared expenses are difficult to divide correctly.
4. Members may have different meal counts.
5. One member may pay an expense on behalf of others.
6. Mid-month joining/leaving complicates calculations.
7. Previous month balances can be forgotten.
8. Manager changes can create confusion.
9. Historical records can be overwritten.
10. Small rounding errors can accumulate.
11. Members often cannot independently understand how their final amount was calculated.
12. The manager ends up doing repetitive arithmetic that software should handle.

Mess Manager is intended to make these problems largely disappear.

---

# 3. Product Goal

## Primary goal

Make monthly mess accounting **automatic, transparent, auditable, and difficult to calculate incorrectly**.

A manager should be able to operate a month by recording source data and then receive a complete settlement automatically.

---

# 4. Product Objectives

### O1 — Automate calculations

The system should calculate:

* total meals
* meal rate
* food cost
* shared costs
* adjustments
* payment totals
* member balances
* month-end settlements

without requiring manual arithmetic.

### O2 — Reduce manager workload

The manager should primarily enter:

* meals
* expenses
* payment records
* membership changes

rather than calculate totals.

### O3 — Make settlement transparent

Every final amount should be explainable through a breakdown.

### O4 — Preserve historical integrity

A change in October must never silently modify September.

### O5 — Enforce permissions

Only the manager should be able to modify operational mess data.

### O6 — Make the system usable on a phone

The application should be fully functional on mobile devices because meal entry and expense entry will often happen away from a laptop.

### O7 — Provide an extensible architecture

V1 should be focused, but the data model should not prevent future capabilities such as inventory, multiple managers, notifications, exports, or multiple messes.

---

# 5. Product Principles

## P1 — Facts over manual calculations

Users enter facts.

The system derives numbers.

---

## P2 — Database-enforced authorization

The frontend should never be the only security boundary.

Hiding an "Edit" button is insufficient.

The underlying database operations must enforce permissions.

---

## P3 — Historical periods are independent

Every month/period has its own accounting context.

Changing:

* membership
* manager
* settings
* current data

must not rewrite closed historical months.

---

## P4 — Every financial number must be explainable

A user seeing:

> ৳3,842.50

should be able to understand how that number was produced.

---

## P5 — Corrections must be traceable

Correcting an error should not destroy the history that an error existed.

---

## P6 — Fail safely

When information is incomplete or mathematically impossible, the system should display the problem rather than invent a value.

Example:

> Cannot calculate meal rate because there are no chargeable meals.

---

# 6. Target Users

## 6.1 Mess Manager

The manager is responsible for maintaining the mess's operational data.

Typical responsibilities:

* member approval
* meal tracking
* expense entry
* shared-cost assignment
* payment entry
* corrections
* monthly review
* settlement
* manager handover

The manager is the primary power user.

---

## 6.2 Mess Member

A member uses the product primarily to:

* monitor meals
* understand charges
* see shared expenses
* see payments
* see current balance
* inspect historical settlements

The member does not operate the accounting system.

---

## 6.3 Prospective Member

An authenticated user who wants to join a mess.

They can submit a join request using the mess's join code.

They do not become a member until approved.

---

# 7. V1 Product Scope

The V1 product includes the following major domains:

### Identity

* registration
* login
* logout
* password reset
* authenticated sessions
* user profile

### Mess management

* create mess
* mess profile/settings
* join code
* regenerate join code
* mess status

### Membership

* join requests
* approval/rejection
* active members
* membership history
* member removal/deactivation

### Management

* current manager
* manager handover
* manager assignment by accounting period

### Meals

* daily meal records
* meal types
* quantities
* guest meals
* monthly meal summary
* corrections

### Expenses

* expense creation
* expense categories
* food vs non-food classification
* payer
* notes
* date
* selected participants

### Cost sharing

* equal split
* weighted split
* fixed allocation
* allocation validation

### Payments

* payment entry
* payment history
* total paid
* settlement impact

### Adjustments

* credit
* debit
* reason
* audit history

### Settlement

* meal rate
* personal food cost
* shared costs
* adjustments
* payments
* amount due
* credit
* final statement

### Period management

* open period
* close period
* historical period view
* controlled reopening

### Audit

* management actions
* financial edits
* membership changes
* period lifecycle actions

---

# 8. Out of Scope for V1

The following are deliberately excluded:

* online banking integration
* payment gateway
* automated bank reconciliation
* grocery inventory management
* receipt OCR
* AI-based categorization
* WhatsApp integration
* native mobile applications
* push notifications
* multi-currency accounting
* advanced tax functionality
* supplier management
* automated grocery ordering
* subscription billing
* organization-level administration

These features may be evaluated after V1.

---

# 9. Core User Journey

The primary lifecycle is:

```text
Create account
      ↓
Create mess
      ↓
Initial manager assigned
      ↓
Share join code
      ↓
Users submit join requests
      ↓
Manager approves members
      ↓
Create/open monthly period
      ↓
Record meals
      ↓
Record expenses
      ↓
Record shared allocations
      ↓
Record payments
      ↓
System calculates settlement
      ↓
Manager reviews
      ↓
Manager closes period
      ↓
Next period created
      ↓
New manager assigned
```

---

# 10. Authentication Requirements

## AUTH-01 — User registration

A new user must be able to create an account.

Required information:

* email
* password

Optional profile information may include:

* display name
* profile image

The application must not duplicate authentication credentials in its own custom authentication tables.

---

## AUTH-02 — Login

Authenticated users must be able to sign in securely.

---

## AUTH-03 — Logout

Users must be able to explicitly end their session.

---

## AUTH-04 — Password reset

Users must be able to request password recovery through the authentication system.

---

## AUTH-05 — Authenticated application boundary

Mess data must not be accessible through ordinary application screens to unauthenticated users.

---

# 11. Mess Creation Requirements

## MESS-01

An authenticated user can create a mess.

Required:

* mess name
* default configuration

Upon creation:

* the creator becomes the initial manager
* a join code is generated
* an initial accounting period may be created

---

## MESS-02 — Unique mess identity

Every mess must have a unique internal identifier.

Human-readable names do not need to be globally unique.

Two messes may both be called:

> Sunrise Mess

---

## MESS-03 — Join code

Each active mess should have a join code.

The code should:

* be randomly generated
* be easy to type
* not expose internal database IDs
* be revocable
* be regeneratable

---

## MESS-04 — Join code regeneration

The manager can regenerate the code.

When regenerated:

> The previous code immediately becomes invalid.

Existing members remain members.

Only future join requests are affected.

---

# 12. Join Request Requirements

## JOIN-01

Authenticated users can enter a mess join code.

---

## JOIN-02

The system validates the code before creating a request.

---

## JOIN-03

Valid code:

```text
Join request → Pending
```

---

## JOIN-04

A pending request must be visible to the current manager.

---

## JOIN-05

Manager can:

* approve
* reject

---

## JOIN-06

Approval creates/activates the user's membership for the appropriate period.

---

## JOIN-07

Rejecting a request must not automatically delete its history.

---

## JOIN-08

Duplicate pending requests for the same user and mess must be prevented.

---

## JOIN-09

A member should not be able to submit a second membership request for the same mess while already active.

---

## JOIN-10

If a user was previously removed and later wants to return, the system should create a new membership episode rather than modify the old historical one.

---

# 13. Membership Requirements

## MEMBER-01

Manager can view all current members.

---

## MEMBER-02

Manager can view membership status.

Possible statuses include:

* pending
* active
* inactive
* removed

---

## MEMBER-03

Membership must have effective dates.

This is required for mid-month joins/leaves.

---

## MEMBER-04

Removing a member must not delete historical financial or meal records.

---

## MEMBER-05

A member's historical records must remain accessible according to the period's permissions.

---

## MEMBER-06

The application must prevent duplicate active memberships for the same user and period.

---

## MEMBER-07

A former member can remain visible in historical periods but not in the current active-member list.

---

# 14. Manager Requirements

## MANAGER-01

Each active accounting period must have exactly one authoritative manager.

---

## MANAGER-02

The manager role must be associated with a period rather than treated solely as a permanent mess attribute.

---

## MANAGER-03

The current manager can nominate/assign the next manager.

---

## MANAGER-04

Manager transfer must be an explicit operation.

---

## MANAGER-05

When management changes:

```text
Old manager → ordinary member
New manager → manager
```

unless the old manager has separately been removed.

---

## MANAGER-06

Historical manager assignments must remain visible in historical records.

---

## MANAGER-07

There must never be two simultaneously active managers for the same period unless a future version explicitly introduces co-management.

---

# 15. Accounting Period Requirements

## PERIOD-01

A mess must have accounting periods.

Recommended implementation:

```text
September 2026
October 2026
November 2026
```

---

## PERIOD-02

Every period has:

* start date
* end date
* status
* manager
* membership context

---

## PERIOD-03

Only one active/open operating period should normally exist for a mess.

---

## PERIOD-04

A closed period becomes read-only for ordinary operations.

---

## PERIOD-05

Closing a period requires validation.

---

## PERIOD-06

Reopening a period must be an explicit privileged action.

---

## PERIOD-07

Reopening requires a reason.

---

## PERIOD-08

All period lifecycle changes must be audited.

---

# 16. Meal Requirements

## MEAL-01

Manager can record meals by date.

---

## MEAL-02

The system should support default meal types:

* breakfast
* lunch
* dinner

---

## MEAL-03

Each meal record should have:

* member
* date
* meal type
* quantity

---

## MEAL-04

The system should optionally support configurable meal weights.

Default:

```text
Breakfast = 1
Lunch = 1
Dinner = 1
```

---

## MEAL-05

The system should support fractional meals only when enabled by mess configuration.

---

## MEAL-06

The manager should have a grid-based interface for rapid meal entry.

---

## MEAL-07

The manager should be able to edit previously entered meals.

---

## MEAL-08

Meal edits must be auditable.

---

## MEAL-09

The system should provide monthly totals by member.

---

## MEAL-10

The system should provide daily totals for manager review.

---

# 17. Guest Meal Requirements

## GUEST-01

A guest meal can be recorded against a hosting member.

---

## GUEST-02

Guests do not require user accounts.

---

## GUEST-03

Guest meals should remain distinguishable from the member's own meals.

---

## GUEST-04

Guest meals must be included in chargeable meal calculations according to mess configuration.

---

## GUEST-05

The guest charge should be attributable to the hosting member.

---

# 18. Food Expense Requirements

## EXP-01

Manager can create an expense.

Minimum fields:

* date
* amount
* description
* category
* payer
* period

---

## EXP-02

Each expense must be classified as either:

### Meal-related

or

### Non-meal/shared

---

## EXP-03

Only meal-related expenses contribute to meal-rate calculation.

---

## EXP-04

Non-food shared costs must never accidentally increase the meal rate.

---

## EXP-05

Manager can edit an expense while the period is open.

---

## EXP-06

Expense edits must be auditable.

---

# 19. Expense Categories

V1 should provide default categories:

* groceries
* food
* cooking gas
* electricity
* water
* internet
* cleaning
* maintenance
* rent
* household supplies
* other

The architecture should allow additional categories later.

---

# 20. Shared Expense Requirements

## SHARE-01

A non-meal expense can be shared among selected members.

---

## SHARE-02

Manager chooses participants.

Example:

```text
A
B
C
D
```

---

## SHARE-03

A selected participant must have valid membership in the relevant period.

---

## SHARE-04

V1 must support equal splitting.

---

## SHARE-05

V1 should support weighted splitting.

Example:

```text
A = 2 shares
B = 1 share
C = 1 share
```

---

## SHARE-06

V1 should support fixed individual allocations.

---

## SHARE-07

Allocation total must reconcile with the source expense amount.

---

## SHARE-08

The system must explicitly handle monetary residuals created by rounding.

---

## SHARE-09

Allocation changes must be auditable.

---

# 21. "Paid By" Requirement

## PAYBY-01

An expense must identify the person who actually paid.

This person may differ from the people who bear the cost.

---

## PAYBY-02

The payer's financial statement must reflect their payment/advance appropriately.

Example:

```text
Expense = ৳1,000
Paid by A
Shared among A/B/C/D

A's expense share = ৳250
A's payment = ৳1,000
```

The system must not treat A as owing the entire ৳1,000.

---

# 22. Payment Requirements

## PAYMENT-01

Manager can record a payment made by a member.

---

## PAYMENT-02

A member may make multiple payments in a period.

---

## PAYMENT-03

Each payment must have:

* member
* amount
* date
* period
* optional note

---

## PAYMENT-04

Payment totals are calculated automatically.

---

## PAYMENT-05

A payment cannot silently alter the original expense records.

Payments are separate ledger events.

---

# 23. Adjustment Requirements

## ADJ-01

Manager can create a credit or debit adjustment.

---

## ADJ-02

Every adjustment must have:

* member
* amount
* type
* reason
* date
* period

---

## ADJ-03

Adjustments must appear separately in the member statement.

---

## ADJ-04

An adjustment cannot silently overwrite another transaction.

---

# 24. Calculation Requirements

## CALC-01 — Total meal quantity

System automatically calculates the member's total chargeable meals.

---

## CALC-02 — Total meal units

If weighted meals are enabled:

```text
meal units = quantity × meal weight
```

---

## CALC-03 — Total food expenditure

```text
total food expenditure
=
sum of all meal-related expenses
```

for the relevant period.

---

## CALC-04 — Meal rate

```text
meal rate
=
food expenditure
÷ chargeable meal units
```

---

## CALC-05 — Member food cost

```text
member food cost
=
member chargeable meal units
× meal rate
```

---

## CALC-06 — Shared cost

```text
member shared cost
=
sum of the member's expense allocations
```

---

## CALC-07 — Adjustments

```text
net adjustment
=
credits − debits
```

---

## CALC-08 — Total charge

Conceptually:

```text
total charge
=
food cost
+
shared costs
+
debits
−
credits
```

---

## CALC-09 — Net balance

```text
net balance
=
total charge
−
payments
−
applicable carried credits
```

The exact ledger model will be formally specified in the Calculation Engine Specification.

---

# 25. Zero-Meal Handling

## CALC-10

The system must never divide by zero.

If:

```text
food expenditure > 0
chargeable meals = 0
```

the meal rate should be unavailable.

The manager must be notified.

---

# 26. Zero-Food-Cost Handling

If:

```text
food expenditure = 0
chargeable meals > 0
```

meal rate should be:

```text
৳0.00
```

rather than undefined.

This is mathematically valid and materially different from the zero-meal case.

---

# 27. Overpayment Requirements

## BAL-01

If a member pays more than their final charge, the system must identify a credit.

Example:

```text
Charge = ৳4,500
Paid = ৳5,000

Credit = ৳500
```

---

# 28. Underpayment Requirements

If:

```text
Charge = ৳4,500
Paid = ৳3,000
```

system displays:

```text
Due = ৳1,500
```

---

# 29. Settled State

If:

```text
charge = payment
```

member is shown as:

> Settled

not:

> Due ৳0

The UI should have an explicit semantic state.

---

# 30. Monthly Settlement Requirements

## SETTLE-01

The system must generate a settlement statement per member.

---

## SETTLE-02

The statement must show:

* meal count
* meal rate
* food cost
* shared costs
* adjustments
* payments
* final due/credit

---

## SETTLE-03

Manager must be able to inspect every member's statement before closing.

---

## SETTLE-04

The system should produce a mess-wide reconciliation summary.

---

## SETTLE-05

Total member-level allocations should reconcile to the mess-level accounting totals.

---

# 31. Period Closing Requirements

Before closing, system must validate:

### Membership

* manager exists
* membership data is consistent

### Meals

* invalid records absent
* no impossible quantities

### Expenses

* valid dates
* valid categories
* valid payer
* shared allocations reconcile

### Payments

* valid member
* valid amount

### Settlement

* calculations complete
* accounting reconciles
* no unresolved blocking errors

---

# 32. Closing Confirmation

The manager should see a summary before closure.

Example:

```text
September 2026

Members           7
Meals             438
Food expense      ৳24,880
Meal rate         ৳56.80
Shared expenses   ৳6,450
Payments          ৳26,100

Outstanding       ৳4,230
Credits           ৳850

[Review settlement]
[Close month]
```

Closing must require deliberate confirmation.

---

# 33. Historical Data Requirements

## HIST-01

Closed period data remains viewable.

---

## HIST-02

Historical manager information remains available.

---

## HIST-03

Historical membership remains available.

---

## HIST-04

Historical calculations must not depend exclusively on current configuration.

---

## HIST-05

A future change in meal configuration must not rewrite closed-month settlement results.

---

# 34. Audit Requirements

## AUDIT-01

All privileged data changes must produce audit events.

---

## AUDIT-02

Audit events must contain:

* actor
* action
* entity type
* entity ID
* timestamp

---

## AUDIT-03

Financial edits should retain old/new values when practical.

---

## AUDIT-04

Audit records cannot be edited by normal users.

---

## AUDIT-05

Audit history should be accessible to the manager.

---

# 35. Member Permissions

Members may:

### View

* current mess
* current period
* own meals
* own charges
* own shared costs
* own payments
* own balance
* historical statements
* permitted mess-wide summaries

### Not modify

* meals
* expenses
* allocations
* payments
* adjustments
* membership
* manager assignments
* settings
* join requests of others
* accounting periods

The database must enforce these restrictions.

---

# 36. Manager Permissions

Managers may:

* approve members
* reject members
* deactivate members
* record meals
* edit meals
* create expenses
* edit expenses
* allocate shared costs
* record payments
* create adjustments
* change relevant settings
* assign the next manager
* close the period
* reopen the period under defined rules
* inspect all settlement information
* view audit history

---

# 37. Privacy Requirements

Members should not automatically receive access to every other member's financial details.

Recommended default:

### Member sees

* their own detailed financial information
* their own meal history
* mess-level aggregate information
* public/current member list where appropriate

### Manager sees

* all member financial information

This boundary should be explicitly reflected in both UI and RLS.

---

# 38. Dashboard Requirements

## Manager dashboard

The manager dashboard should expose:

### Current period

* meal rate
* total meals
* food expenditure
* shared expenditure
* money collected
* total outstanding
* credits
* active member count

### Action queue

* pending join requests
* incomplete data
* settlement warnings
* unresolved validation errors

### Quick actions

* record today's meals
* add expense
* record payment
* review members

---

## Member dashboard

The member dashboard should prioritize:

* current meal count
* current estimated cost
* current shared cost
* total paid
* amount due/credit

and provide access to their breakdown.

---

# 39. Mobile Requirements

The application must be mobile-first.

Critical workflows must be usable with one hand or minimal scrolling:

* today's meals
* payment entry
* expense entry
* member approval
* balance viewing

The most frequently used manager operation should not require opening large desktop-style tables.

---

# 40. Responsive Requirements

The system should support:

### Mobile

Approximately:

```text
320px+
```

### Tablet

Approximately:

```text
768px+
```

### Desktop

Approximately:

```text
1024px+
```

The interface should adapt rather than merely scale down.

---

# 41. Empty States

The product must not display confusing blank screens.

Examples:

### No expenses

> No expenses recorded for this period.

### No meals

> No meals recorded yet.

### No join requests

> No pending member requests.

### No payments

> No payments recorded.

Each useful empty state may provide a manager action.

---

# 42. Error Handling

Errors must be understandable.

Bad:

> Error 409

Better:

> This member is already active in this period.

Bad:

> Null constraint violation

Better:

> Please select who paid for this expense.

System errors should be logged internally while exposing a safe user-facing message.

---

# 43. Financial Precision

Financial calculations must avoid binary floating-point errors.

The product requirement is:

> Monetary operations must use exact decimal arithmetic at the accounting layer.

Displayed values should normally use two decimal places.

---

# 44. Rounding Requirements

The application must use deterministic rounding.

A shared allocation must reconcile exactly with the original amount.

Example:

```text
Total = ৳100
Three participants

Final:
33.34
33.33
33.33

Total:
100.00
```

The chosen residual-allocation rule must be deterministic and documented.

---

# 45. Notifications

Push notifications are outside V1.

However, the architecture should not make future notifications impossible.

Future candidates:

* join request received
* join request approved
* payment reminder
* month closing reminder
* manager handover

---

# 46. Search Requirements

Manager should be able to search/filter:

* member
* expense
* payment
* date
* expense category
* transaction status

Search is especially important for historical records.

---

# 47. Sorting Requirements

Tables containing transactions should support useful sorting such as:

* newest
* oldest
* highest amount
* lowest amount
* member
* category

---

# 48. Data Export

Not required for V1 core operation.

Future support should include:

* CSV
* Excel
* PDF settlement

The database model should not prevent export functionality.

---

# 49. Security Requirements

The application must enforce:

### Authentication

Only authenticated users may access private mess data.

### Authorization

Database policies determine whether users can read/write specific records.

### Manager-only mutation

Operational mutations must be restricted to authorized managers.

### Historical protection

Closed periods cannot be modified through normal client operations.

### Join-code protection

Invalid or revoked codes cannot create memberships.

### Audit protection

Audit data cannot be manipulated by ordinary users.

---

# 50. Performance Goals

The V1 application should feel responsive for normal student mess sizes.

Target operating assumption:

```text
5–30 members per mess
1 active period
hundreds to several thousand transactions
```

The architecture should remain comfortable at larger sizes.

Primary performance priorities:

1. dashboard load
2. daily meal entry
3. monthly statement calculation
4. expense entry
5. member list

---

# 51. Reliability Requirements

The system should prioritize correctness over aggressive optimization.

A slower but correct settlement is preferable to a fast but incorrect settlement.

The system must not silently lose:

* meal entries
* expenses
* payments
* memberships
* settlements

---

# 52. Data Retention

User data and mess records are expected to persist indefinitely unless the product later introduces explicit deletion policies.

Deleting a user must not casually destroy financial history.

This is particularly important because accounting records may reference users who are no longer active.

The detailed deletion/anonymization strategy will be specified in the Non-Functional Requirements document.

---

# 53. Account Deletion Consideration

User account deletion presents a significant edge case.

Example:

```text
User A
 ↓
recorded 8 months of meals/payments
 ↓
deletes account
```

Historical settlements must remain mathematically understandable.

Therefore V1 should separate:

* authentication identity
* persistent profile identity
* historical financial references

A future account deletion flow may anonymize personal details while retaining non-identifying financial history.

---

# 54. Product-Level Edge Case Matrix

The product must account for:

| Situation                                | Required behavior                             |
| ---------------------------------------- | --------------------------------------------- |
| User enters invalid join code            | Reject                                        |
| Join code regenerated                    | Old code invalid                              |
| Duplicate join request                   | Prevent                                       |
| User already member                      | Prevent duplicate membership                  |
| User leaves mid-month                    | Preserve previous records                     |
| User rejoins later                       | New membership episode                        |
| Manager changes                          | Preserve manager history                      |
| Manager leaves                           | Require replacement                           |
| Expense payer differs from beneficiaries | Track separately                              |
| Shared expense doesn't reconcile         | Block save/close                              |
| Zero meals                               | No division                                   |
| Zero food expense                        | Meal rate = 0                                 |
| Member overpays                          | Credit                                        |
| Member underpays                         | Due                                           |
| Member pays exact amount                 | Settled                                       |
| Expense edited                           | Audit change                                  |
| Closed period edited                     | Block                                         |
| Period reopened                          | Require reason + audit                        |
| Invalid meal quantity                    | Reject                                        |
| Expense dated outside period             | Reject or explicit exception flow             |
| Shared expense participant inactive      | Reject                                        |
| No active manager                        | Block operational management                  |
| Manager tries to remove themselves       | Controlled handover required                  |
| Duplicate active manager                 | Database constraint                           |
| Two simultaneous active periods          | Prevent                                       |
| Rounding residual                        | Deterministically allocate                    |
| Former member views history              | Historical access allowed according to policy |
| Authenticated non-member accesses mess   | Deny                                          |
| Member tries manager mutation            | Deny at DB layer                              |

---

# 55. High-Priority User Stories

## Epic A — Authentication

### US-A01

As a user, I want to create an account so that I can use Mess Manager.

### US-A02

As a user, I want to log in so that I can access my mess.

### US-A03

As a user, I want to recover my password so that I don't lose access.

---

# 56. Epic B — Mess Creation

### US-B01

As a user, I want to create a mess so that I can manage my shared residence.

### US-B02

As a manager, I want a join code so that I can invite other residents.

### US-B03

As a manager, I want to regenerate the join code so that an accidentally exposed code can be invalidated.

---

# 57. Epic C — Membership

### US-C01

As a prospective member, I want to request access using a join code.

### US-C02

As a manager, I want to approve members.

### US-C03

As a manager, I want to reject unauthorized requests.

### US-C04

As a manager, I want to see member history.

### US-C05

As a manager, I want to remove a member without destroying their historical accounting.

---

# 58. Epic D — Meals

### US-D01

As a manager, I want to quickly record today's meals.

### US-D02

As a manager, I want to correct a meal entry.

### US-D03

As a manager, I want guest meals to be attributable to a host.

### US-D04

As a member, I want to see my meal history.

### US-D05

As a manager, I want the system to calculate meal totals automatically.

---

# 59. Epic E — Expenses

### US-E01

As a manager, I want to record food purchases.

### US-E02

As a manager, I want to record non-food shared expenses.

### US-E03

As a manager, I want to specify who paid.

### US-E04

As a manager, I want to choose which members share an expense.

### US-E05

As a manager, I want the application to calculate each member's share.

---

# 60. Epic F — Payments

### US-F01

As a manager, I want to record a member's payment.

### US-F02

As a manager, I want to record multiple payments from the same member.

### US-F03

As a member, I want to know how much I have paid.

---

# 61. Epic G — Settlement

### US-G01

As a manager, I want the meal rate calculated automatically.

### US-G02

As a manager, I want every member's final balance calculated automatically.

### US-G03

As a member, I want to understand how my final amount was calculated.

### US-G04

As a manager, I want to review settlement before closing the month.

---

# 62. Epic H — Manager Handover

### US-H01

As a manager, I want to designate the next manager.

### US-H02

As the incoming manager, I want the current period's operational responsibilities.

### US-H03

As the outgoing manager, I want my previous records to remain historical.

---

# 63. Epic I — Auditability

### US-I01

As a manager, I want to know who changed an important record.

### US-I02

As a manager, I want corrections to remain traceable.

### US-I03

As a member, I should not be able to alter accounting history.

---

# 64. Priority Classification

## P0 — Must exist for usable V1

* authentication
* mess creation
* join code
* join request
* manager approval
* membership
* manager assignment
* periods
* meal recording
* food expenses
* shared expenses
* payments
* automatic calculations
* balances
* settlement statement
* period closure
* RLS authorization
* audit logging

---

## P1 — Strongly recommended for V1

* guest meals
* weighted shared expenses
* fixed allocations
* adjustments
* bulk meal entry
* historical period browsing
* reopening workflow
* detailed settlement review
* search/filter
* dashboard warnings
* manager handover interface

---

## P2 — Post-V1

* receipt attachments
* exports
* notifications
* inventory
* analytics
* multiple managers
* multiple messes per account
* native mobile application

---

# 65. Acceptance Criteria — Core Product

The V1 product should be considered functionally successful only when all of the following are true:

### AC-01

A user can register and authenticate.

### AC-02

A user can create a mess.

### AC-03

A manager can generate and share a join code.

### AC-04

Another authenticated user can submit a join request.

### AC-05

Manager approval is required before membership becomes active.

### AC-06

Members cannot perform manager-only writes, even by bypassing the UI.

### AC-07

Manager can record meals.

### AC-08

Manager can record food expenses.

### AC-09

Manager can record shared expenses among selected members.

### AC-10

The system calculates the meal rate automatically.

### AC-11

The system calculates member-level financial obligations automatically.

### AC-12

Payments reduce the outstanding balance.

### AC-13

Overpayments become credits.

### AC-14

Expenses can distinguish payer from beneficiaries.

### AC-15

Rounding differences reconcile exactly.

### AC-16

A closed month cannot be casually modified.

### AC-17

Historical records remain intact after manager/member changes.

### AC-18

The manager can review a complete settlement before closing.

### AC-19

Every critical modification is auditable.

### AC-20

The same accounting data produces the same settlement regardless of which screen displays it.

---

# 66. Definition of Done for V1

V1 is not "done" merely because pages exist.

It is done when:

1. The authentication system works.
2. The database model supports the complete accounting lifecycle.
3. RLS prevents unauthorized operations.
4. Manager workflows work end-to-end.
5. Member workflows work end-to-end.
6. Calculations pass deterministic test cases.
7. Financial rounding reconciles.
8. Historical periods remain stable.
9. Audit records are generated.
10. Closing/reopening rules are enforced.
11. Mobile UI supports core manager operations.
12. Production deployment works.
13. Database migrations can be applied reproducibly.
14. Failure states are handled clearly.
15. The test suite covers critical calculations and authorization boundaries.

---

# 67. Product Risks

## R1 — Accounting formula complexity

Small formula mistakes could affect every member.

**Mitigation:** centralize calculation logic and build extensive calculation tests.

---

## R2 — Authorization mistakes

A member accidentally being able to modify an expense would be a severe security flaw.

**Mitigation:** database-level RLS plus authorization tests.

---

## R3 — Historical data mutation

Changing current membership could accidentally alter previous months.

**Mitigation:** period-specific membership and settlement snapshots.

---

## R4 — Rounding mismatch

Multiple rounding steps can cause balances not to reconcile.

**Mitigation:** exact numeric arithmetic and deterministic residual allocation.

---

## R5 — Manager loss

A manager could disappear from the system without transferring control.

**Mitigation:** controlled manager handover and recovery design.

---

## R6 — Overengineering

Trying to include inventory, notifications, analytics, and payments immediately could slow development.

**Mitigation:** maintain strict V1 scope.

---

# 68. Product Metrics

The most meaningful V1 success metrics are operational rather than vanity metrics.

### Calculation automation

Percentage of final settlement values generated automatically.

Target:

> Essentially 100%.

### Manual calculation reduction

A normal month should require little or no external calculation.

### Correction rate

How often managers need to correct entries.

This helps identify UX problems.

### Settlement reconciliation

Target:

> 100% of closed periods reconcile.

### Unauthorized mutation attempts

Target:

> 0 successful unauthorized writes.

### Manager completion time

Measure how long it takes a manager to:

```text
Open period
→
enter data
→
review
→
close
```

---

# 69. Future Product Direction

The longer-term product can evolve into a broader **shared-living financial operating system**.

Possible future modules:

```text
Mess Accounting
      │
      ├── Meals
      ├── Expenses
      ├── Payments
      ├── Settlement
      │
      ├── Inventory
      ├── Grocery Planning
      ├── Receipts
      ├── Notifications
      ├── Analytics
      └── Shared Household Services
```

However, these should only be introduced after the accounting core is trustworthy.

---

# 70. Product North Star

The product should ultimately make this possible:

> A group of students can operate an entire month of shared living expenses with one manager entering the necessary facts, while the system automatically performs, explains, validates, reconciles, and preserves the accounting.

That is the core product.

Anything that does not substantially improve that workflow should be considered secondary.
