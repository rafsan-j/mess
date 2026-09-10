# Mess Manager

## Page-by-Page UI/UX Specification

**Document version:** 1.0
**Product version:** V1
**Based on:** PRD v1.0, FRD v1.0, Non-Functional & Technical Requirements v1.0, UI/UX Profile v1.0
**Platform:** Responsive web application
**Primary viewport:** Mobile
**Secondary:** Tablet and desktop

---

# 1. Purpose

This document translates the Mess Manager information architecture into concrete application screens.

For each route it defines:

* purpose
* users
* access requirements
* page structure
* components
* actions
* data requirements
* form fields
* loading states
* empty states
* error states
* mobile behavior
* desktop behavior
* navigation behavior

The document is intended to become the direct UI/UX blueprint for implementation.

---

# 2. Route Architecture

The recommended V1 route structure is:

```text id="5l4w1p"
/                         → redirect/router entry

/auth
  /login
  /register
  /forgot-password
  /reset-password

/onboarding
  /welcome
  /create-mess
  /join-mess
  /join-request

/app
  /dashboard
  /meals
  /expenses
  /payments
  /members
  /settlement
  /history
  /settings

/app/members/[memberId]
  → member detail

/app/expenses/[expenseId]
  → expense detail

/app/payments/[paymentId]
  → payment detail

/app/periods/[periodId]
  → period detail/history

/app/periods/[periodId]/settlement
  → historical/final settlement

/app/settings/account
  → account settings

/app/settings/mess
  → mess settings

/app/settings/accounting
  → accounting settings

/app/settings/management
  → manager controls
```

The exact routing convention may differ during implementation, but the functional destinations should remain equivalent.

---

# 3. Route Access Model

```text id="12ln7y"
Public
├── Login
├── Register
├── Forgot Password
└── Reset Password

Authenticated
├── Onboarding
├── Join Mess
└── Pending Join Request

Member
├── Dashboard
├── Meals
├── Statement
├── History
└── Mess

Manager
├── Dashboard
├── Meals
├── Expenses
├── Payments
├── Members
├── Settlement
├── History
└── Settings
```

Unauthorized routes must redirect or return a safe access-denied state.

---

# 4. Global Application Shell

## Route

```text id="0y8kr1"
/app/*
```

## Desktop

```text id="k2q9t9"
┌────────────────────────────────────────────────────┐
│ Mess Name       September 2026          Profile    │
├───────────────┬────────────────────────────────────┤
│ Dashboard     │                                    │
│ Meals         │                                    │
│ Expenses      │             PAGE CONTENT            │
│ Payments      │                                    │
│ Members       │                                    │
│ Settlement    │                                    │
│ History       │                                    │
│ Settings      │                                    │
└───────────────┴────────────────────────────────────┘
```

## Mobile

```text id="8u8y9j"
┌────────────────────────────┐
│ Mess              Profile  │
├────────────────────────────┤
│                            │
│        PAGE CONTENT        │
│                            │
├────────────────────────────┤
│ Home  Meals  Money  More   │
└────────────────────────────┘
```

## Global header

Must expose:

* mess name
* current period
* user identity/profile
* manager/request indicator where applicable

## Global period selector

Every accounting page should be contextually associated with a period.

---

# 5. `/auth/login`

## Purpose

Authenticate an existing user.

## Access

Unauthenticated users only.

## Structure

```text id="3d0r9d"
Logo
Welcome back

Email
Password

[Log in]

Forgot password?

────────

Don't have an account?
Create account
```

## Inputs

### Email

Required.

### Password

Required.

## Actions

### Log in

Authenticate.

### Forgot password

Navigate to password reset request.

### Create account

Navigate to registration.

## Validation

Email:

* required
* valid format

Password:

* required

## Loading

Button changes to:

> Logging in…

Prevent duplicate submission.

## Errors

Invalid credentials:

> Email or password is incorrect.

Do not reveal which credential was wrong.

Network failure:

> Couldn't connect. Check your connection and try again.

## Success

Route according to state:

```text id="ax6q5j"
No mess
→ onboarding

Has pending join
→ pending request

Has active mess
→ dashboard
```

---

# 6. `/auth/register`

## Purpose

Create a new application account.

## Inputs

* email
* password
* confirm password
* display name

## Validation

Email:

* required
* valid

Password:

* required
* authentication policy compliant

Confirm:

* must match password

Display name:

* required
* reasonable length
* plain text

## Actions

```text id="kr8zfu"
[Create account]
```

## Errors

Duplicate account:

> An account may already exist with this email.

Authentication-specific messaging should avoid unnecessary account enumeration.

## Success

Depending on auth configuration:

```text id="9m9qj1"
verification required
or
authenticated → onboarding
```

---

# 7. `/auth/forgot-password`

## Purpose

Request password reset.

## UI

```text id="a3t6t8"
Forgot password?

Enter your email.

[Send reset link]

Back to login
```

## Security

Response should not clearly reveal whether an account exists.

---

# 8. `/auth/reset-password`

## Purpose

Set a new password from a valid recovery session.

## Fields

* new password
* confirm password

## Actions

```text id="2b8qwl"
[Update password]
```

After success:

> Password updated.

Then navigate to login or application.

---

# 9. `/onboarding/welcome`

## Purpose

First authenticated landing page for a user without a mess.

## Structure

```text id="o6yd8o"
Welcome

What would you like to do?

[Create a mess]

[Join an existing mess]
```

Keep this page extremely simple.

---

# 10. `/onboarding/create-mess`

## Purpose

Create a new mess.

## Fields

### Mess name

Required.

Example:

> Sunrise Mess

### Optional settings

V1 may initially keep these under later settings rather than adding complexity here.

## Primary action

> Create mess

## Result

Creation transaction:

```text id="2a4m99"
Mess
+
membership
+
manager
+
join code
+
initial period
```

## Success screen

```text id="gz3hbe"
Your mess is ready.

Join code:
M7K4P9

[Copy code]

[Go to dashboard]
```

---

# 11. `/onboarding/join-mess`

## Purpose

Join an existing mess via code.

## UI

```text id="2x8j0k"
Join a mess

Enter the join code

[ M7K4P9 ]

[Request to join]
```

## Validation

* code required
* normalized
* valid active code
* no duplicate membership
* no duplicate pending request

## Error

> Invalid join code.

or:

> You already have an active membership in this mess.

---

# 12. `/onboarding/join-request`

## Purpose

Show pending request state.

## UI

```text id="30qj03"
Join request submitted

Mess:
Sunrise Mess

Status:
Awaiting manager approval

Requested:
10 September 2026

You can leave this page and return later.
```

No manager controls.

---

# 13. `/app/dashboard` — Manager

## Purpose

Primary operational command center.

## Header

```text id="bzi3ew"
September 2026
Manager
```

## Primary metrics

```text id="h9ogt1"
Meal Rate
৳58.50

Meals
438

Food Expense
৳24,880

Outstanding
৳4,230
```

## Secondary metrics

```text id="3x9rfq"
Shared Costs
৳6,450

Payments
৳26,100

Credits
৳850

Members
7
```

## Alerts

Examples:

```text id="4aeuee"
3 pending join requests
2 validation issues
```

## Quick actions

* Record meals
* Add expense
* Record payment
* Review settlement

## Recent activity

Show recent:

* expenses
* payments
* membership events

## Data sources

Requires:

* current period
* period summary
* alerts
* recent transactions
* membership summary

---

# 14. `/app/dashboard` — Member

Same route, role-dependent content.

## Primary card

```text id="a47m77"
Current balance

Amount due
৳507.00
```

or:

```text id="g8d7p3"
Credit
৳200.00
```

or:

```text id="7q6v2n"
Settled
```

## Supporting values

* meals
* meal rate
* food cost
* shared costs
* paid

## Explanation

For an open period:

> Your current balance can change as records are added or corrected.

## Actions

* View meals
* View statement
* View payment history

No manager-only actions.

---

# 15. `/app/meals`

## Purpose

Daily meal recording and review.

## Manager view

### Header

```text id="hr1b9x"
Meals
September 2026
```

### Date navigation

```text id="0d0h2a"
←
10 Sep 2026
Today
→
```

### Daily summary

```text id="5pr6mp"
Total meal units
28
```

### Meal grid

Desktop:

| Member | Breakfast | Lunch | Dinner |
| ------ | --------: | ----: | -----: |
| A      |         1 |     1 |      1 |
| B      |         0 |     1 |      1 |
| C      |         1 |     1 |      0 |

Mobile:

```text id="2vof1f"
A
Breakfast [1]
Lunch     [1]
Dinner    [1]

B
Breakfast [0]
Lunch     [1]
Dinner    [1]
```

### Actions

* Save changes
* Copy previous day
* Clear day
* Guest meals

---

# 16. Meal Grid Detail

Each editable cell should support:

* valid quantity
* keyboard navigation
* touch entry

If fractional meals enabled:

```text id="0y0h5m"
0
0.5
1
1.5
...
```

If disabled:

```text id="5d2j3w"
0
1
2
...
```

---

# 17. Meal Page — Member

Members can view their own meal history.

## Structure

```text id="k9bwgl"
My Meals
September 2026

Total
42 meals

Daily history
10 Sep   B 1 | L 1 | D 1
09 Sep   B 0 | L 1 | D 1
...
```

No editing controls.

---

# 18. Guest Meal Interface

Accessible from the manager meal page.

## UI

```text id="1x15g7"
Guest meals

Host
[A ▼]

Date
10 Sep

Meal
Lunch

Quantity
[1]

[Add guest meal]
```

Guest meals should be visually distinct from regular member meals.

---

# 19. Meal Page States

### Loading

Show table/card skeleton.

### No active members

> No active members are available for meal entry.

### Closed period

Banner:

> This period is closed. Meals are read-only.

### Invalid date

> This date does not belong to this period.

### Save success

> Meals saved.

### Save failure

> Meal changes could not be saved.

---

# 20. `/app/expenses`

## Purpose

View and manage expenses.

## Manager page

### Header

```text id="q87g7y"
Expenses
September 2026
```

### Summary

```text id="w2jrr5"
Meal-related
৳24,880

Shared non-meal
৳6,450
```

### Search/filter

* search description
* category
* payer
* classification
* date

### Expense list

Desktop:

| Date   | Description | Category | Paid by | Amount |
| ------ | ----------- | -------- | ------- | -----: |
| 10 Sep | Groceries   | Food     | A       | ৳1,850 |
| 08 Sep | Internet    | Internet | B       | ৳1,000 |

Mobile:

```text id="6qiyx8"
Groceries
10 Sep
Food · Paid by A
৳1,850
```

### Primary action

> Add expense

---

# 21. `/app/expenses/new`

## Purpose

Create an expense.

## Step 1 — Basic information

Fields:

* description
* amount
* date
* category
* classification
* paid by

## Step 2 — Sharing

Question:

> Is this cost shared among selected members?

Options:

```text id="p1guvn"
No
Yes
```

For a normal meal-related grocery expense, sharing configuration may be unnecessary because meal consumption drives its allocation.

---

# 22. Expense — Shared Workflow

If Yes:

### Participants

Multi-select.

### Allocation method

```text id="uw9v94"
Equal split
Weighted split
Fixed amounts
```

### Allocation preview

```text id="5vdybw"
A     ৳250
B     ৳250
C     ৳250
D     ৳250

Total ৳1,000
Difference ৳0
```

Save only when valid.

---

# 23. Expense — Fixed Allocation UX

Example:

```text id="t75z0w"
A   [300]
B   [250]
C   [450]

Allocated
৳1,000

Expense
৳1,000

Difference
৳0
```

If mismatch:

```text id="pz3fqq"
Allocated ৳980
Expense   ৳1,000

Difference ৳20

Allocation must equal the expense amount.
```

---

# 24. `/app/expenses/[expenseId]`

## Purpose

View one expense in detail.

## Structure

```text id="ettdoy"
Internet
10 September 2026

৳1,000

Category
Internet

Paid by
A

Shared among
A, B, C, D

Allocation

A   ৳250
B   ৳250
C   ৳250
D   ৳250
```

## Manager actions

* Edit
* Delete/void if supported
* View history

The exact deletion mechanism should follow the final audit/data-integrity specification.

---

# 25. Expense Edit

Reuse the creation form with current values populated.

If period is closed:

> This expense belongs to a closed period and cannot be edited.

---

# 26. `/app/payments`

## Purpose

Track money paid by members.

## Manager view

### Summary

```text id="r8e7my"
Collected
৳26,100
```

### List

```text id="m6rd2r"
A
10 Sep
৳2,000

B
09 Sep
৳1,500

C
08 Sep
৳3,000
```

### Primary action

> Record payment

---

# 27. `/app/payments/new`

## Fields

### Member

Required.

### Amount

Required.

### Date

Required.

### Note

Optional.

## Optional future field

Payment method.

Not necessary for V1.

## Save

> Record payment

---

# 28. Payment Detail

## Route

```text id="3q35xu"
/app/payments/[paymentId]
```

Show:

* member
* date
* amount
* note
* recorded by
* timestamp
* audit/history

Manager can edit while period is open.

---

# 29. Member Payments View

Members can see only their own payment records.

Example:

```text id="i7a2ls"
My Payments

10 Sep
৳2,000

02 Sep
৳1,500

Total paid
৳3,500
```

---

# 30. `/app/members`

## Purpose

Member management.

## Header

```text id="3sc7kq"
Members
7 active
```

### Pending requests

Prominent top section if requests exist.

### Active members

```text id="e4g17w"
A          Manager
B          Active
C          Active
D          Active
```

### Historical/former members

Optional collapsed section.

---

# 31. Member Management

Manager actions:

* approve request
* reject request
* view member
* remove/end membership
* assign manager where allowed

Member sees:

> Members

but no administrative actions.

---

# 32. Join Request Card

```text id="n6vlr3"
New request

John Doe
Requested 10 Sep 2026

[Approve] [Reject]
```

Approve should execute a protected transaction.

---

# 33. Remove Member Flow

Manager selects:

> Remove member

Confirmation:

```text id="s4ytp5"
Remove John from the current period?

Their existing meals, expenses, and payments will remain in historical records.

[Cancel]
[Remove]
```

The system should collect an effective end date where necessary.

---

# 34. `/app/members/[memberId]`

## Purpose

Manager's detailed view of one member.

## Header

```text id="l08xrv"
John Doe
Active
```

## Membership

* joined
* status
* end date if applicable

## Financial summary

```text id="e7m1ja"
Meals          42
Food cost      ৳2,457
Shared costs   ৳650
Adjustments    -৳50
Paid           ৳2,500
Balance        ৳557 due
```

## Tabs/sections

```text id="9ftgqj"
Overview
Meals
Payments
Statement
History
```

---

# 35. Member Detail — Privacy

A manager can see the member's full relevant financial data.

Another ordinary member must not be able to access this route's private data merely by changing the URL.

---

# 36. `/app/settlement`

## Purpose

Current-period settlement review.

This is a manager-critical screen.

## Header

```text id="y1m8ax"
Settlement
September 2026
Estimated
```

## Period summary

```text id="e7q0rd"
Meals              438
Meal rate          ৳58.50
Food expense       ৳24,880
Shared expenses    ৳6,450
Payments           ৳26,100
```

---

# 37. Settlement Validation Section

Before the member table:

```text id="4g8v5e"
Settlement status

✓ Meal calculations
✓ Expense allocations
✓ Payments
⚠ 1 warning
```

Blockers should appear first.

---

# 38. Settlement Member Table

Desktop:

| Member | Meals |   Food | Shared | Adjustments |   Paid |    Balance |
| ------ | ----: | -----: | -----: | ----------: | -----: | ---------: |
| A      |    44 | ৳2,574 |   ৳450 |        -৳50 | ৳3,000 | Credit ৳26 |
| B      |    39 | ৳2,281 |   ৳620 |           — | ৳2,000 |   Due ৳901 |

Mobile:

```text id="41l8sn"
A

44 meals
Food       ৳2,574
Shared     ৳450
Adjustment -৳50
Paid       ৳3,000

Credit
৳26
```

---

# 39. Settlement Member Detail

Tap a member.

Show full statement:

```text id="2p7ew9"
Meals
44 × ৳58.50
৳2,574

Shared costs
Internet       ৳200
Water          ৳150
Cleaning       ৳100
               ─────
               ৳450

Adjustments
Credit         -৳50

Current charge
৳2,974

Paid
৳3,000

Credit
৳26
```

---

# 40. Settlement Calculation Explanation

Use collapsible "How calculated?" sections.

Example:

```text id="pwk7lz"
Meal rate

Meal-related expenses:
৳24,880

Chargeable meal units:
425

৳24,880 ÷ 425
= ৳58.541176...

Displayed meal rate:
৳58.54
```

The exact intermediate presentation should reflect the eventual calculation engine's precision rules.

---

# 41. Settlement Blockers

Example:

```text id="6mwqg8"
Cannot close period

1 issue

Internet allocation:
৳980 allocated
৳1,000 expense

Difference:
৳20

[Review expense]
```

---

# 42. Settlement Warnings

Example:

```text id="h3fg0k"
Warning

No meals were recorded for
12 September.

This does not necessarily prevent closing.
```

Warnings are separate from blockers.

---

# 43. Close Period Action

At bottom/sticky area:

```text id="gkjy1f"
[Close period]
```

Disabled when blockers exist.

---

# 44. Close Period Confirmation

Full confirmation dialog/sheet:

```text id="fplp6c"
Close September 2026?

This will finalize the period and disable
ordinary edits.

Members:
7

Meals:
438

Meal rate:
৳58.50

Outstanding:
৳4,230

Credits:
৳850

[Cancel]
[Close period]
```

---

# 45. `/app/settlement` — Member

Members see their own statement rather than the management table.

Header:

> September 2026

Status:

> Current / Estimated

Breakdown:

* meals
* food cost
* shared costs
* adjustments
* paid
* current balance

---

# 46. `/app/history`

## Purpose

Browse historical accounting periods.

## Manager view

```text id="8v87ks"
History

September 2026
Closed
৳4,230 outstanding

August 2026
Closed
৳850 credits

July 2026
Closed
Settled
```

## Member view

Show only periods where the user has relevant historical membership/access.

---

# 47. History Filters

Optional:

* year
* status

Avoid excessive filtering in V1.

---

# 48. `/app/periods/[periodId]`

## Purpose

Historical period overview.

## Header

```text id="fbx08u"
September 2026
Closed
```

## Information

* manager
* members
* total meals
* food expense
* meal rate
* shared expenses
* payments
* closing status

## Actions

For closed period:

> View settlement

No normal edit action.

---

# 49. `/app/periods/[periodId]/settlement`

## Purpose

View a finalized historical settlement.

## Header

```text id="tx2w2x"
September 2026
Final settlement
Closed 30 Sep 2026
```

## Member

If member:

show their statement.

If manager:

allow selecting any historical member.

---

# 50. Historical Settlement Read-Only State

Show visible banner:

> This period is closed. Its settlement is read-only.

---

# 51. Historical Settlement Snapshot

The UI should use the finalized snapshot where applicable rather than recomputing historical numbers against current settings.

---

# 52. `/app/settings`

## Purpose

Settings landing page.

## Sections

```text id="6vp70m"
Mess
Accounting
Management
Account
```

Manager sees all applicable sections.

Member may see:

```text id="f9cx8m"
Account
Mess information
```

without management controls.

---

# 53. `/app/settings/mess`

## Purpose

Mess identity and invitation settings.

## Fields

### Mess name

Editable by manager.

### Join code

Display:

```text id="8x5qby"
M7K4P9
```

Actions:

* copy
* regenerate

---

# 54. Regenerate Join Code

Confirmation:

```text id="l8t8nw"
Regenerate join code?

The current code will stop working immediately.

[Cancel]
[Regenerate]
```

Success:

> New join code generated.

---

# 55. `/app/settings/accounting`

## Purpose

Accounting configuration.

## Settings

### Meal types

Default:

* Breakfast
* Lunch
* Dinner

### Meal weight

Per meal type.

### Fractional meals

Toggle:

> Allow fractional meal quantities

### Guest meals

Enable/disable.

### Guest charging rule

V1 recommendation:

> Guest meals are charged to the host member at the configured meal rate.

Additional rules may be added later.

---

# 56. Accounting Setting Change Warning

Some configuration changes can affect current/future calculations.

Before changing:

```text id="a4b4wf"
Changing meal weights may change current-period calculations.

Continue?
```

If the period is closed, settings affecting that historical period should not be editable as historical context.

---

# 57. `/app/settings/management`

## Purpose

Manager-specific administration.

## Current manager

```text id="4ojk1y"
Current manager
A
```

## Transfer

Button:

> Transfer management

---

# 58. Manager Transfer Flow

### Step 1

Choose active member.

### Step 2

Review:

```text id="q8h3vl"
Current manager:
A

New manager:
B

Period:
October 2026
```

### Step 3

Confirmation.

> B will become the manager for this period. A will remain a member.

### Step 4

Success.

> Management transferred.

---

# 59. `/app/settings/account`

## Purpose

User account settings.

## Sections

### Profile

* display name
* avatar if supported

### Security

* password reset/change

### Session

* logout

No mess accounting controls.

---

# 60. Period Creation UI

The PRD/FRD require a new period workflow. This may appear as an action from:

```text id="e9mbx8"
History
or
Dashboard
```

Recommended UI:

```text id="rgxuj6"
Start October 2026

Previous period:
September 2026

Continuing members:
7

Manager:
B

[Review]
[Create period]
```

---

# 61. New Period Review

Show:

### Continuing members

* A
* B
* C
* D

### Former members

* E

### New members

* F

### Manager

* B

### Configuration

* meal types
* weights
* guest rules

The manager confirms before opening.

---

# 62. Period Creation Success

```text id="l0tegc"
October 2026 is ready.

Manager:
B

Members:
7

[Open dashboard]
```

---

# 63. Period Reopen UI

Historical period manager action:

```text id="jqp3jr"
[Reopen period]
```

Requires reason.

Form:

```text id="r8s6tw"
Why are you reopening this period?

[________________________]

[Cancel]
[Reopen]
```

---

# 64. Reopen Confirmation

Show:

> Reopening may change the finalized settlement.

After reopen:

* period becomes editable according to authorization
* audit event generated
* previous snapshot retained according to audit strategy

---

# 65. `/app` — Access Failure

If authenticated user has no permission:

```text id="k90u5v"
Access unavailable

You don't have permission to view this page.

[Go to dashboard]
```

Do not expose database or policy details.

---

# 66. `/app` — No Mess State

Authenticated user without an active mess:

```text id="em28b5"
You don't have a mess yet.

[Create a mess]
[Join a mess]
```

---

# 67. `/app` — Pending Membership State

If user's only relationship is pending:

```text id="ds4qbj"
Your membership request is pending.

Mess:
Sunrise Mess

Requested:
10 Sep 2026

Waiting for manager approval.
```

---

# 68. Global Not-Found State

For missing entity:

```text id="7zvq5k"
This record could not be found.

It may have been removed or you may not have access to it.

[Back]
```

Do not reveal whether a protected record exists.

---

# 69. Global Error Page

For unexpected application failures:

```text id="r7shmd"
Something went wrong.

The application couldn't complete this request.

[Try again]
```

Technical details remain in internal logs.

---

# 70. Mobile Bottom Navigation

Recommended manager navigation:

```text id="6kgtnw"
Home
Meals
Money
More
```

Money opens:

```text id="9h43h8"
Expenses
Payments
Settlement
```

More opens:

```text id="y9t3ve"
Members
History
Settings
```

---

# 71. Mobile Member Navigation

```text id="m5p7d8"
Home
Meals
Statement
More
```

More:

* History
* Mess
* Account

---

# 72. Desktop Sidebar

Manager:

```text id="1l8thk"
Dashboard
Meals
Expenses
Payments
Members
Settlement
History

──────────
Settings
```

Member:

```text id="4lmcgk"
Home
My Meals
My Statement
History

──────────
Mess
Account
```

---

# 73. Floating/Sticky Primary Actions

On mobile, relevant pages may use a sticky action:

Meals:

> Save changes

Expenses:

> Add expense

Payments:

> Record payment

Settlement:

> Close period

The sticky action must not cover content.

---

# 74. Form Validation Placement

Errors should appear:

1. next to the field
2. optionally summarized at the top if multiple fields fail

Example:

```text id="n30cwh"
Amount
[________]

Amount must be greater than zero.
```

---

# 75. Form Submission Error

For server-side failures:

```text id="mt2rsm"
Couldn't save this expense.

Your changes were not confirmed as saved.
```

Avoid pretending that a timeout definitively means the record was not created.

---

# 76. Multi-Step Form Navigation

Complex expense/shared-cost entry may use:

```text id="oo3f1m"
Basic
→
Sharing
→
Review
```

The user's entered state should persist between steps.

---

# 77. Review Step

Before committing a complex financial transaction, show an exact summary.

Example:

```text id="uhy2wf"
Review expense

Internet
৳1,000

Paid by
A

Participants
A, B, C, D

Equal split

A  ৳250
B  ৳250
C  ৳250
D  ৳250
```

---

# 78. Cancel Behavior

When cancelling a new transaction:

If no meaningful input:

> Return immediately.

If input exists:

> Discard this expense?

---

# 79. Success Navigation

After creating an expense:

Recommended:

> Return to expense list with the new transaction visible.

After recording payment:

> Stay on payment list unless the manager explicitly entered from a member page.

After meal save:

> Remain on current date.

This minimizes repeated navigation.

---

# 80. Context Preservation

The application should preserve:

* selected period
* selected date
* filters
* search state

where this improves workflow.

---

# 81. Manager Dashboard Deep Links

Cards should be actionable.

Example:

```text id="k4me2d"
Pending requests: 3
→ Members
```

```text id="22a4rp"
Settlement issue: 1
→ Settlement
```

---

# 82. Dashboard Data Freshness

After manager mutations:

* dashboard summaries should update
* stale values should not remain visible indefinitely
* server-confirmed values should become authoritative

---

# 83. Mobile Modal Strategy

For:

* simple confirmations → modal/bottom sheet
* complex forms → full-screen page/sheet
* large tables → dedicated page
* settlement detail → page or full-screen sheet

---

# 84. Desktop Modal Strategy

Desktop can use centered dialogs for:

* confirmation
* quick payment
* quick member approval

Complex workflows should still have sufficient space.

---

# 85. Transaction Detail Drawer

On desktop, expense/payment detail may use a right-side drawer.

On mobile, use a full-page detail view or full-screen sheet.

---

# 86. Member Detail Responsive Behavior

Desktop:

```text id="l0xg2v"
Profile | Financial Summary
-------------------------
Tabs
```

Mobile:

```text id="9tc2xf"
Profile
Summary
Meals
Payments
Statement
```

as vertically navigable sections.

---

# 87. Settlement Responsive Behavior

Desktop:

Dense table.

Tablet:

Potentially horizontally scrollable table plus sticky member column.

Mobile:

Stacked member cards.

Do not reduce font size excessively to preserve a desktop table.

---

# 88. Meal Grid Responsive Behavior

Desktop:

Spreadsheet-like grid.

Mobile:

Member-centered cards/rows.

Touch controls must remain sufficiently large.

---

# 89. Date Picker

Date picker should:

* highlight current date
* show period boundaries
* prevent invalid dates
* respect timezone policy

---

# 90. Closed Date Behavior

If date belongs to a closed period:

```text id="0v8a6p"
Read-only
```

Editing controls disabled.

---

# 91. Period Boundary UI

When navigating past the first/last date:

The interface should either disable navigation or prompt to move to the adjacent period rather than creating ambiguity.

---

# 92. Member Effective Dates

Member profile should show:

```text id="12l1oy"
Joined:
15 Sep 2026

Ended:
22 Sep 2026
```

when applicable.

---

# 93. Meal Entry Eligibility

On a given date, the member list should contain only eligible members unless manager explicitly chooses a historical/admin mode.

This prevents accidental records outside membership periods.

---

# 94. Expense Participant Eligibility

The participant selector should default to currently eligible members.

If historical date requires different membership, the backend remains authoritative.

---

# 95. Payment Member Eligibility

The manager should normally choose active/current or historically eligible members according to the transaction date.

---

# 96. Adjustments UI

Although not a top-level navigation item in V1, adjustments may be accessible from:

```text id="hs3oy1"
Settlement
→ Member
→ Add adjustment
```

Fields:

* type
* amount
* date
* reason

---

# 97. Adjustment Detail

Show:

```text id="k7e8j6"
Credit
৳100

Reason:
Previous overcharge

Date:
10 Sep 2026
```

---

# 98. Manager-Only Adjustment Access

Members can view adjustments affecting their own statement but cannot create/edit them.

---

# 99. Member Statement Route

Recommended conceptual route:

```text id="5v7pe9"
/app/statement
```

or:

```text id="vl3e91"
/app/settlement
```

depending on implementation.

For UX purposes, it must provide one obvious destination:

> My Statement

---

# 100. Member Statement Page

Structure:

```text id="j9gk3r"
September 2026
Current balance

Amount due
৳507

Breakdown
Meals
42

Food cost
৳2,457

Shared costs
৳650

Adjustments
-৳100

Paid
৳2,500
```

---

# 101. Member Historical Statement

For closed period:

```text id="e8d6vh"
September 2026
Final

Settled
```

The same breakdown remains available.

---

# 102. "How was this calculated?"

Each derived section may expose an expandable detail.

Example:

```text id="7s5qgf"
Food cost
৳2,457
[How calculated]
```

Expands to:

```text id="v6xv3p"
42 meal units
×
৳58.50
=
৳2,457
```

---

# 103. Mess Information Page

Member-accessible page:

```text id="6d3yq4"
Mess
Sunrise Mess

Current manager
A

Active members
7
```

Do not expose:

* join code to ordinary members unless intended
* private balances
* audit information

---

# 104. Manager Mess Information

Manager can additionally see:

* join code
* member management link
* accounting settings
* current period
* manager assignment

---

# 105. Join Code Copy Feedback

After copy:

> Join code copied.

Do not alter the code.

---

# 106. Clipboard Failure

If clipboard access fails:

> Couldn't copy automatically. Please copy the code manually.

---

# 107. Reauthentication Consideration

Highly sensitive account operations may require fresh authentication depending on security configuration.

Examples:

* changing password
* destructive account action

This is optional for V1 but should remain architecturally possible.

---

# 108. Account Logout

Profile menu:

```text id="6jvcn0"
Account
Settings
Log out
```

Logout must not require a confirmation under normal circumstances unless there is an explicit reason.

---

# 109. Manager Status Persistence

The application shell should show manager status consistently enough that the user understands why they have administrative access.

---

# 110. Member Role Persistence

Member should never see a manager dashboard momentarily while role data is loading.

The application should use a role-aware loading boundary.

---

# 111. Role Loading State

Instead of rendering manager controls first and hiding them later:

```text id="eq2cve"
Load authenticated user
 ↓
Resolve mess/period/role
 ↓
Render permitted shell
```

---

# 112. Permission Failure After Navigation

If role changes while the user has the app open:

Example:

```text id="p9r1h7"
Manager transfer occurs in another session.
```

A later manager-only operation must be rejected by the backend.

The UI should refresh/reconcile role state and remove privileged controls.

---

# 113. Closed Period During Active Session

If another session closes the period:

The current manager UI must not continue assuming it is editable.

A subsequent mutation must be rejected, and UI should transition to read-only.

---

# 114. Stale Form Handling

If a manager opened an expense while it was editable and another session closes the period:

The Save operation must fail safely.

Message:

> This period was closed before the change could be saved.

Do not overwrite closed data.

---

# 115. Error Recovery After Concurrency Conflict

Where a conflict occurs:

```text id="7x9f0x"
This record was changed elsewhere.

[Reload]
```

The system should not blindly overwrite the latest server state.

---

# 116. Global Toast System

Standard categories:

### Success

> Expense added.

### Warning

> This period contains unresolved issues.

### Error

> Couldn't save payment.

### Informational

> September is now closed.

---

# 117. Skeleton Loading

Use contextual skeletons matching final layout.

Do not animate excessively.

---

# 118. Error Boundaries

Each major application section should be capable of showing a localized error state rather than crashing the entire application.

---

# 119. Page-Level Authorization

Every protected route should verify access server-side or through trusted database authorization.

Frontend route guards improve UX but do not replace RLS.

---

# 120. Query Loading Boundaries

Each page should separately handle:

* auth loading
* page data loading
* mutation loading

so one slow operation does not freeze unrelated UI.

---

# 121. Form Data Persistence

During multi-step creation:

Data persists while navigating within the same form.

Leaving the workflow triggers an unsaved warning if data was entered.

---

# 122. Accessibility Requirements for Each Page

Every page must provide:

* semantic headings
* labeled controls
* keyboard access
* visible focus
* screen-reader-friendly status
* accessible error messages

---

# 123. Page Heading Structure

Each page should have exactly one primary H1-style page heading.

Example:

```text id="6u4q68"
Expenses
September 2026
```

Secondary content uses lower levels.

---

# 124. Breadcrumbs

Desktop may use breadcrumbs on deeper pages:

```text id="t2h2y4"
Members / John Doe
```

Mobile can omit breadcrumbs when back navigation is obvious.

---

# 125. Back Navigation

Detail pages should provide an obvious back action.

Example:

> ← Expenses

---

# 126. Page Persistence on Refresh

Refreshing a page should preserve:

* authentication
* valid mess/period context
* saved database data

URL should encode enough route state for direct navigation where appropriate.

---

# 127. Browser Back Behavior

Forms should behave predictably.

Do not trap normal browser history unnecessarily.

---

# 128. Deep Link Behavior

Authenticated users opening:

```text id="2kg6ex"
/app/settlement
```

should arrive directly at the settlement page after access verification.

---

# 129. Invalid Period ID

If period does not exist or is inaccessible:

Use generic not-found/access-denied behavior without exposing database details.

---

# 130. Manager Dashboard → Settlement Flow

Typical:

```text id="1u1u29"
Dashboard
 ↓
Settlement warning
 ↓
Settlement
 ↓
Fix issue
 ↓
Return to settlement
 ↓
Close period
```

Relevant route/state should be preserved.

---

# 131. Dashboard → Meal Entry Flow

Typical:

```text id="mcs0f4"
Dashboard
 ↓
Record today's meals
 ↓
Meals page
 ↓
Save
 ↓
Dashboard totals refresh
```

---

# 132. Dashboard → Expense Flow

Typical:

```text id="4kd7p6"
Dashboard
 ↓
Add expense
 ↓
Review
 ↓
Save
 ↓
Expense list
 ↓
Dashboard refresh
```

---

# 133. Dashboard → Payment Flow

Typical:

```text id="zlrk0k"
Dashboard
 ↓
Record payment
 ↓
Save
 ↓
Balance refresh
```

---

# 134. Join Approval Flow

Manager:

```text id="y52onq"
Dashboard
 ↓
Pending requests
 ↓
Members
 ↓
Approve
 ↓
Member becomes active
 ↓
Dashboard/member count refresh
```

---

# 135. Member Dashboard → Statement Flow

```text id="7v4r3f"
Home
 ↓
Current balance
 ↓
My Statement
 ↓
Breakdown
 ↓
Underlying transactions
```

---

# 136. Member Dashboard → Payment History

```text id="5vw02r"
Home
 ↓
Paid
 ↓
Payments
```

---

# 137. Member Dashboard → Meal History

```text id="x63l38"
Home
 ↓
Meals
 ↓
Daily/monthly history
```

---

# 138. Period History Flow

```text id="rt16kg"
History
 ↓
September 2026
 ↓
Final settlement
```

---

# 139. Manager History Flow

Manager may additionally access:

* historical expenses
* historical meals
* historical payments
* historical audit information

subject to the final permission specification.

---

# 140. Audit Page

Recommended route:

```text id="4m5hqq"
/app/periods/[periodId]/audit
```

## UI

```text id="b2ik4b"
Audit history

10 Sep · 14:32
Expense updated
৳850 → ৳800

09 Sep · 19:20
Payment recorded
৳2,000

09 Sep · 18:01
Member approved
John Doe
```

Filters may include:

* event
* actor
* entity
* date

V1 can keep filters minimal.

---

# 141. Audit Detail

For an event:

```text id="xhe7kg"
Expense updated

Actor
Manager A

Time
10 Sep 2026 14:32

Previous
৳850

New
৳800

Reason
Duplicate item
```

---

# 142. Audit Access

Managers only by default.

---

# 143. Account for Former Manager

Former manager's previous management records remain visible in audit/history.

They lose active manager controls after transfer.

---

# 144. Period Manager Badge

Historical period page:

```text id="7t5z66"
Manager
A
```

This is informational, not necessarily editable.

---

# 145. Current Manager Badge

Current period:

```text id="h2i4j8"
You are manager
```

for the current manager.

---

# 146. Member Balance Status Component

Canonical component states:

```text id="o4j7ko"
DUE
CREDIT
SETTLED
```

Each includes:

* textual label
* amount where relevant
* optional semantic styling

---

# 147. Calculation Status Component

States:

```text id="g1w6sx"
CALCULATING
AVAILABLE
UNAVAILABLE
BLOCKED
FINAL
```

Examples:

> Calculating…

> Meal rate unavailable

> Final settlement

---

# 148. Period Status Component

States:

```text id="kz6j9q"
OPEN
CLOSING
CLOSED
REOPENED
```

---

# 149. Membership Status Component

States:

```text id="qf2w2j"
PENDING
ACTIVE
ENDED
REMOVED
```

---

# 150. Join Request Status Component

States:

```text id="n4qr5w"
PENDING
APPROVED
REJECTED
```

---

# 151. Global Search

A global search is not required for V1.

Contextual search is sufficient.

---

# 152. Notifications Center

Not required for V1.

Pending requests and warnings can be surfaced directly on the dashboard.

---

# 153. Responsive Page Rules

## Mobile

* one-column layout
* sticky primary action when useful
* cards instead of dense tables
* full-screen forms
* bottom navigation

## Tablet

* two-column summaries where useful
* tables may become horizontally scrollable

## Desktop

* sidebar
* dense data tables
* multi-column forms
* detail drawers

---

# 154. Mobile Safe Areas

Bottom navigation and sticky controls must respect device safe-area insets where applicable.

---

# 155. Mobile Scroll Behavior

Avoid nested scrolling unless necessary.

Especially avoid:

```text id="4n1wkh"
page scroll
  +
table scroll
  +
card scroll
```

simultaneously.

---

# 156. Desktop Scroll Behavior

Large tables can scroll within their container if headers remain accessible.

---

# 157. Touch Feedback

Controls should provide clear pressed/focus states.

Avoid hover-only interaction.

---

# 158. Keyboard Interaction

Meal grid:

* Tab
* Arrow keys where sensible
* Enter to edit where useful

Forms:

* logical tab order
* Enter submits when appropriate
* Escape closes dialogs

---

# 159. Accessibility Error Summary

When multiple form fields fail, show a summary at the beginning of the form:

> Please correct 3 fields.

Then link to each field if practical.

---

# 160. Page Transition Loading

Navigation between pages should not produce unnecessary blank screens.

Use appropriate loading states.

---

# 161. Permission-Based Component Rendering

For manager-only controls:

```text id="lsat0q"
if user is manager:
    render control
```

is appropriate for UX.

But the corresponding backend mutation must still verify authorization.

---

# 162. Financial Data Consistency UX

If a mutation succeeds but calculations are temporarily refreshing:

Show:

> Updating balance…

rather than briefly showing a stale number without explanation.

---

# 163. Stale Data Marker

If needed:

> Updated just now.

or:

> Refreshing…

No manual "recalculate" button should be required.

---

# 164. Manual Refresh

A browser refresh is always available, but the product should not depend on it for normal consistency.

---

# 165. Close-Period Success

After closing:

```text id="f3vsmw"
September 2026 is closed.

Final meal rate:
৳58.50

[View final settlement]
[Start next period]
```

---

# 166. Reopen Success

```text id="az8xq0"
September 2026 reopened.

The period is editable again according to your permissions.
```

---

# 167. Member Approval Success

Manager receives:

> John Doe approved.

Member count updates.

---

# 168. Member Rejection Success

> Join request rejected.

The request disappears from pending list but remains historical.

---

# 169. Expense Save Success

> Expense recorded.

Show amount optionally.

---

# 170. Payment Save Success

> Payment recorded.

Balance should update.

---

# 171. Meal Save Success

> Meal changes saved.

Remain on date.

---

# 172. Regenerated Code Success

> Join code regenerated.

Display the new code immediately.

---

# 173. Empty Audit

```text id="32d9wx"
No audit activity yet.
```

---

# 174. Empty History

For new mess:

```text id="meb2ol"
No previous periods yet.
```

---

# 175. Empty Settlement

If there is no useful settlement data yet:

```text id="1t0mmy"
Settlement isn't ready yet.

Record meals and expenses to generate the current calculation.
```

---

# 176. No Payment History

Member:

> No payments recorded for this period.

Manager:

> No payments recorded yet.

---

# 177. No Shared Costs

Settlement:

> No shared non-meal costs.

This is not an error.

---

# 178. No Adjustments

Settlement:

> No adjustments.

---

# 179. No Guest Meals

Meal summary:

> No guest meals recorded.

---

# 180. Unavailable Meal Rate

When meals = 0:

```text id="7j2p3o"
Meal rate
Unavailable

No chargeable meals have been recorded.
```

If food expense exists, this should be prominent.

---

# 181. Zero Meal + Food Expense Dashboard

Manager dashboard should display a warning:

> Food expenses exist, but no chargeable meals are recorded. Meal rate cannot currently be calculated.

---

# 182. Zero Food Expense

Dashboard:

```text id="07t3ky"
Meal rate
৳0.00
```

with contextual supporting text where useful.

---

# 183. Member With Zero Meals

Statement:

```text id="e60wz5"
Meals
0

Food cost
৳0.00

Shared costs
৳650.00

Total due
৳650.00
```

The member is not omitted.

---

# 184. Credit State

Member dashboard:

```text id="5j0qjh"
Credit
৳350.00

You have paid ৳350 more than your current charges.
```

---

# 185. Settled State

```text id="7ap4ck"
Settled

Paid exactly
৳3,250.00
```

---

# 186. Outstanding State

```text id="w2g9s8"
Amount due
৳507.00
```

---

# 187. Open Period Disclaimer

At the bottom of member statement:

> This is the current estimated balance and may change before the period closes.

---

# 188. Closed Period Disclaimer

> Final settlement for September 2026.

No estimate language.

---

# 189. Manager Settlement Disclaimer

Before closure:

> Review all records before closing. Closing finalizes the period.

---

# 190. Final UX Acceptance Criteria

The UI specification is satisfied when:

### Navigation

* every major user task has a clear route
* manager and member navigation are appropriately separated

### Meals

* manager can rapidly enter an entire day's meals
* member can inspect their own meals

### Expenses

* manager can create ordinary and shared expenses
* allocation preview is clear
* invalid allocation cannot be finalized

### Payments

* manager can record payments
* member can inspect own payments

### Settlement

* manager can see the whole mess
* member can see their own statement
* calculated values are clearly distinguished from inputs
* current vs final status is obvious

### History

* closed periods remain accessible
* closed periods appear read-only

### Management

* join requests are obvious
* manager transfer is deliberate
* manager-only controls are hidden from members

### Security UX

* unauthorized operations produce understandable messages
* no private information is exposed through UI states

### Responsive behavior

* all critical workflows are usable on mobile
* desktop workflows can take advantage of larger screens

---

# 191. Page Inventory

The V1 implementation should therefore contain approximately these user-facing destinations:

```text id="yvnq0e"
AUTH
├── Login
├── Register
├── Forgot Password
└── Reset Password

ONBOARDING
├── Welcome
├── Create Mess
├── Join Mess
└── Join Request Pending

CORE
├── Dashboard
├── Meals
├── Expenses
├── Expense Detail
├── Add Expense
├── Payments
├── Payment Detail
├── Add Payment
├── Members
├── Member Detail
├── Settlement
├── My Statement
├── History
├── Period Detail
└── Historical Settlement

SETTINGS
├── Settings
├── Mess Settings
├── Accounting Settings
├── Management Settings
└── Account Settings

SPECIAL
├── Audit
├── New Period
├── Reopen Period
└── Access/Error States
```

---

# 192. Implementation Boundary

The page specification intentionally does **not** decide:

* exact PostgreSQL table names
* exact column types
* RLS SQL
* calculation SQL
* API function names
* migration file structure

Those belong to the next architecture documents.

---

# 193. Handoff

The UI now has a defined destination for essentially every V1 workflow.

The next document should establish the **data model and ERD**, because every subsequent implementation artifact—the Supabase schema, RLS policies, database functions, calculation engine, API contracts, and test plan—depends on a stable entity/relationship model.
