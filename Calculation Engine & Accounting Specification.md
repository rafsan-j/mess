# Mess Manager

## Calculation Engine & Accounting Specification

**Document version:** 1.0
**Product version:** V1
**Related documents:** PRD v1.0, FRD v1.0, NFR v1.0, UI/UX v1.0, Data Model v1.0, Supabase Schema v1.0, RLS v1.0
**Accounting currency:** BDT
**Accounting precision:** Exact PostgreSQL `numeric` arithmetic
**Display precision:** 2 decimal places for money

---

# 1. Purpose

This document defines the authoritative mathematical model for Mess Manager.

It specifies exactly how the system calculates:

* chargeable meals
* meal units
* meal rate
* member food cost
* shared expenses
* expense allocations
* guest meals
* payments
* credits
* debits
* opening balances
* current balance
* final balance
* period reconciliation
* final settlement snapshots

The objective is deterministic behavior.

Given the same period data, every page, report, function, and future implementation must produce the same result.

---

# 2. Fundamental Accounting Principle

The system separates four conceptual layers:

```text id="5ngd7n"
CONSUMPTION
    │
    ▼
MEAL COST
    │
    ▼
NON-MEAL ALLOCATIONS
    │
    ▼
CASH / BALANCE SETTLEMENT
```

More precisely:

```text id="4k3p8g"
Meals
  ↓
Meal Rate
  ↓
Member Food Cost

Shared Expenses
  ↓
Member Allocations

Food Cost
+
Shared Cost
+
Debits
−
Credits
+
Opening Balance
−
Payments
  ↓
Final Balance
```

---

# 3. Authoritative Facts

The calculation engine may use only valid records from the relevant period.

Primary inputs:

```text id="wmz1s3"
period
period configuration
period members
period meal types
meals
expenses
expense allocations
payments
adjustments
opening balances
```

Voided/inactive records must be excluded according to their record semantics.

---

# 4. Period Scope

Every calculation must operate on one explicit period:

```text id="l1x4q7"
calculate_period(period_id)
```

A calculation must never silently combine:

```text September + October id="0mz73m"
```

unless an explicit cross-period carry-forward operation is being performed.

---

# 5. Valid Records

For ordinary current-period calculation, include a record only when:

```text id="4g1p6w"
record belongs to target period
AND
record is not voided
AND
record satisfies its validity constraints
```

Invalid records should not be silently ignored if their existence indicates database corruption.

---

# 6. Calculation Pipeline

The canonical pipeline is:

```text id="6q4n0r"
1. Validate period context
        ↓
2. Load period configuration
        ↓
3. Determine eligible period members
        ↓
4. Calculate meal units
        ↓
5. Calculate meal-related expenditure
        ↓
6. Calculate meal rate
        ↓
7. Calculate member food costs
        ↓
8. Calculate shared expense allocations
        ↓
9. Calculate adjustments
        ↓
10. Calculate opening balances
        ↓
11. Calculate payments
        ↓
12. Calculate member balances
        ↓
13. Reconcile
        ↓
14. Generate result
```

---

# 7. Meal Unit Definition

Each meal record has:

```text id="b6od1y"
quantity
meal weight
```

The effective meal units are:

```text id="f4bvc6"
meal_units
=
quantity × weight
```

---

# 8. Standard Meal Configuration

Default:

```text id="wawmb4"
Breakfast = 1.0000
Lunch     = 1.0000
Dinner    = 1.0000
```

Therefore:

```text id="xv6q8d"
1 breakfast = 1 meal unit
1 lunch     = 1 meal unit
1 dinner    = 1 meal unit
```

---

# 9. Weighted Meal Example

Suppose:

```text id="j6fl8f"
Breakfast weight = 0.5
Lunch weight = 1.0
Dinner weight = 1.0
```

Member consumes:

```text id="g4yk3t"
2 breakfasts
1 lunch
1 dinner
```

Then:

```text id="11h14z"
2 × 0.5
+
1 × 1
+
1 × 1
=
3 meal units
```

---

# 10. Chargeable Meal Definition

A meal contributes to chargeable meal units when it is:

* valid
* associated with the target period
* associated with an eligible member/host
* not voided
* associated with an active applicable meal type
* permitted by the period's meal rules

---

# 11. Normal Member Meal

For:

```text id="jh2kik"
member A
lunch
quantity 1
weight 1
```

chargeable units:

```text id="g2z08r"
1
```

---

# 12. Guest Meal

Guest meals are chargeable according to the V1 default rule.

For:

```text id="3w2r1w"
host A
guest lunch
quantity 2
weight 1
```

chargeable units:

```text id="d82zqo"
2
```

Those units contribute to the period meal total.

---

# 13. Guest Meal Attribution

The guest does not receive a separate member statement.

The cost is attributed to:

```text id="h4g9e0"
host period member
```

---

# 14. Host Food Cost

If:

```text id="em0xwo"
A's own meal units = 40
A's guest units = 3
```

then, by V1 default:

```text id="lo1f4o"
A's chargeable units = 43
```

and:

```text id="4c8e08"
A's food cost = 43 × meal rate
```

---

# 15. Total Period Meal Units

Let each valid meal record be `i`.

Then:

```text id="0v7j5k"
Total Meal Units
=
Σ(quantity_i × weight_i)
```

over all chargeable meal records in the period.

---

# 16. Meal-Related Expense Definition

Meal-related expenses are expenses whose:

```text id="f8m7w7"
accounting_type = MEAL_COST
```

and which are not voided.

---

# 17. Total Meal Cost

```text id="y1m2h4"
Total Meal Cost
=
Σ(valid MEAL_COST expense amounts)
```

This is the numerator of the meal-rate calculation.

---

# 18. Critical Separation

The following must **not** be included in meal cost merely because they are household expenses:

```text id="d6g4ja"
internet
water
electricity
cleaning
rent
maintenance
```

unless the manager explicitly classifies an expense as `MEAL_COST`.

---

# 19. Meal Rate

If:

```text id="q8dv0f"
Total Meal Units > 0
```

then:

```text id="b8a2q0"
Meal Rate
=
Total Meal Cost
÷
Total Meal Units
```

The internal result should retain precision.

---

# 20. Zero Meal Case

If:

```text id="x3fgh2"
Total Meal Units = 0
```

then:

```text id="7c8l4q"
Meal Rate = NULL / unavailable
```

not:

```text 0
```

and not:

```text Infinity
NaN
```

---

# 21. Zero Meal + Food Cost

If:

```text id="8h67ma"
Meal Units = 0
Meal Cost = ৳10,000
```

the settlement is mathematically unresolved.

Status:

```text id="xq4jg7"
MEAL_RATE_UNAVAILABLE
```

This should be a period-closing blocker.

---

# 22. Zero Meal + Zero Food Cost

If:

```text id="7g1qte"
Meal Units = 0
Meal Cost = ৳0
```

there is no meaningful meal rate.

The system should represent:

```text id="tk1qg5"
Meal Rate = NULL
```

with explanatory status.

The value should not automatically be displayed as `৳0.00` because there were no chargeable meals.

---

# 23. Non-Zero Meals + Zero Food Cost

If:

```text id="ex7wkp"
Meal Units > 0
Meal Cost = ৳0
```

then:

```text id="n2f4k0"
Meal Rate = ৳0.00
```

This is mathematically valid.

---

# 24. Internal Meal Rate Precision

The engine must not immediately round:

```text id="e7h4i9"
10000 / 171
```

to:

```text 58.48
```

before calculating individual costs.

Instead retain sufficient precision:

```text id="3uwc2e"
58.479532...
```

and only apply the defined rounding policy at the settlement stage.

---

# 25. Member Meal Units

For member `M`:

```text id="9dljj1"
Member Meal Units
=
Σ(member's chargeable meal units)
```

This includes applicable guest units hosted by M.

---

# 26. Member Food Cost

For member `M`:

```text id="1o9n1h"
Member Food Cost
=
Member Meal Units × Meal Rate
```

Use the canonical internal meal rate.

---

# 27. Example — Food Cost

Suppose:

```text id="h1pq3d"
Meal Rate = ৳58.50
A = 42 units
```

Then:

```text id="7kq6sh"
Food Cost
=
42 × 58.50
=
৳2,457.00
```

---

# 28. Meal Rate Rounding Policy

The system must distinguish:

### Calculation precision

High precision.

### Display precision

Two decimal places.

### Settlement monetary precision

Two decimal places.

The exact method for reconciling member food costs after the high-precision calculation is defined below.

---

# 29. Food-Cost Rounding Problem

Consider:

```text id="rljz5l"
Total food cost = ৳100
Total meal units = 3
```

Exact meal rate:

```text id="gq3n2j"
33.333333...
```

Three members with one unit each theoretically have:

```text id="3z9w3p"
33.333333...
```

each.

Displaying each as:

```text id="vpu5yo"
33.33
```

produces:

```text 99.99
```

rather than:

```text 100.00
```

The engine therefore needs a deterministic residual mechanism.

---

# 30. Meal-Cost Residual Allocation

For final settlement, member food costs should reconcile exactly to total meal cost.

Recommended method:

1. Calculate each member's exact food cost.
2. Round each member to the smallest monetary unit.
3. Sum rounded values.
4. Calculate residual.
5. Allocate residual deterministically.

---

# 31. Residual Unit

For BDT with two decimal accounting precision:

```text id="2n0z3a"
1 residual unit = ৳0.01
```

---

# 32. Residual Allocation Determinism

Do not use:

* random member
* frontend array order
* database insertion order

as the residual rule.

Recommended deterministic ordering:

```text id="6b6g8z"
period_members.created_at
+
period_members.id as tie-breaker
```

or another explicitly stable ordering.

The final exact rule should be implemented centrally.

---

# 33. Better Residual Strategy

For larger residuals, allocate the smallest currency unit one at a time across members according to deterministic order, or use a mathematically equivalent largest-remainder method.

The selected algorithm must satisfy:

```text id="o9cy10"
Σ(final member food costs)
=
rounded(total meal cost)
```

---

# 34. Why Largest Remainder Is Preferred

For member cost allocation, the largest-remainder method is more mathematically reasonable than arbitrarily assigning all residual to one member.

Algorithm:

```text id="q5e47n"
1. Calculate exact shares.
2. Floor/round to 2 decimals.
3. Determine remaining cents.
4. Rank members by descending fractional remainder.
5. Distribute residual cents in that order.
6. Break ties using stable member ID/order.
```

This is recommended for V1.

---

# 35. Shared Expense Classification

Shared expenses are not meal-rate components.

Their calculation starts independently:

```text id="r9b4jy"
Expense Amount
→
Allocation Method
→
Member Allocations
```

---

# 36. Shared Expense Method: NONE

If:

```text id="g7tbgp"
allocation_method = NONE
```

there must be no allocation records.

This is appropriate for:

```text id="u1fp1h"
MEAL_COST
```

and non-shared expenses.

---

# 37. Shared Expense Method: EQUAL

For expense amount `E` and `N` participants:

```text id="u6ptq8"
Raw share
=
E / N
```

Then final allocation is rounded/reconciled using the same deterministic residual principle.

---

# 38. Equal Split Example

```text id="yz7p95"
Expense = ৳100
Members = A, B, C
```

Raw:

```text id="8h5u4l"
33.333...
```

Final:

```text id="m19n1e"
A = 33.34
B = 33.33
C = 33.33
```

Total:

```text ৳100.00
```

---

# 39. Shared Expense Method: WEIGHTED

For participants with weights:

```text id="zm2w3h"
A = 2
B = 1
C = 1
```

Total weight:

```text id="5s23rt"
4
```

For expense `E`:

```text id="thog3d"
A raw = E × 2 / 4
B raw = E × 1 / 4
C raw = E × 1 / 4
```

---

# 40. Weighted Example

Expense:

```text id="2wn7yu"
৳1,000
```

Weights:

```text id="av3g1v"
A = 2
B = 1
C = 1
```

Final:

```text id="ye6tg8"
A = ৳500
B = ৳250
C = ৳250
```

---

# 41. Weighted Allocation Validation

Every weight must satisfy:

```text id="xg0d1j"
weight > 0
```

Total weight must also be:

```text > 0
```

---

# 42. Shared Expense Method: FIXED

Manager defines:

```text id="s11b0g"
A = 300
B = 250
C = 450
```

The engine validates:

```text id="dx0c4b"
Σ allocations = expense amount
```

exactly at accounting precision.

---

# 43. Fixed Allocation Example

Expense:

```text id="7b0wms"
৳1,000
```

Allocation:

```text id="xv7ziw"
A = 300
B = 250
C = 450
```

Valid:

```text ৳1,000 = ৳1,000
```

---

# 44. Fixed Allocation Mismatch

Expense:

```text id="5iiu5h"
৳1,000
```

Allocation:

```text A = 300
B = 250
C = 400
```

Total:

```text ৳950
```

Result:

```text id="n8f3xz"
INVALID_ALLOCATION
```

The expense cannot be finalized.

---

# 45. Empty Participant Set

A shared expense cannot use:

```text id="2w9v3a"
EQUAL
WEIGHTED
FIXED
```

with zero participants.

The save operation must fail.

---

# 46. Allocation of Zero

Zero allocation may technically be representable but should generally not be stored.

For a participant to be included, their final allocated share should normally be:

```text ≥ ৳0.01
```

after final rounding.

However, an exact zero may arise in unusual weighted/fixed cases.

V1 recommendation:

> Do not include zero-value participants in allocation records.

---

# 47. Participant Eligibility

Every allocation participant must:

```text id="4f3fd1"
belong to the same period
AND
be eligible on the expense date
```

unless an explicit manager override is implemented.

---

# 48. Food Expense and Allocations

A `MEAL_COST` expense normally uses:

```text id="9pxdj3"
allocation_method = NONE
```

Its cost is distributed through meal consumption.

It should not simultaneously be treated as a manually shared allocation.

---

# 49. Prevent Double-Charging Food Expenses

The system must prevent this invalid model:

```text id="jqilqt"
৳1,000 grocery
+
meal-rate allocation
+
shared-expense allocation
```

which would charge the same expense twice.

---

# 50. Non-Meal Expense

A non-meal expense may be:

```text id="grx5v8"
not shared
```

or:

```text shared among selected members
```

Depending on the accounting rule.

---

# 51. Unallocated Non-Meal Expense

A non-meal expense marked `NONE` does not automatically affect member obligations.

It remains part of:

```text mess-level expenditure
```

but has no member-level allocation.

This must be a deliberate state, not an accidental omission.

---

# 52. Product Decision: Non-Allocated Expense

The manager should be warned when a non-meal expense has no allocation.

Example:

> This expense will not be charged to any member.

This prevents accidental omission.

Whether such an expense blocks period closure is a product policy.

Recommended:

> Warning, not blocker, unless the category is configured as required-to-share.

---

# 53. Shared Cost Total

For member `M`:

```text id="55d5h0"
Shared Cost(M)
=
Σ(valid allocation_amount
  for M)
```

---

# 54. Adjustment Calculation

Credit:

```text id="r6tgj0"
credit_total(M)
=
Σ(CREDIT adjustments)
```

Debit:

```text id="9q4lrr"
debit_total(M)
=
Σ(DEBIT adjustments)
```

Net adjustment:

```text id="s33gzg"
net_adjustment(M)
=
credit_total(M)
−
debit_total(M)
```

---

# 55. Opening Balance

Opening balance is the member's prior-period financial position carried into the current period.

Possible states:

```text id="73rtt7"
DUE
CREDIT
```

---

# 56. Opening Due

Example:

```text id="4h2kxy"
Opening balance:
৳500 DUE
```

This means the member starts the period owing:

```text ৳500
```

---

# 57. Opening Credit

Example:

```text id="6dydj6"
Opening balance:
৳300 CREDIT
```

This means:

```text Mess owes member / member has ৳300 available credit.
```

---

# 58. Opening Balance Mathematical Representation

For calculation purposes, define:

```text id="u3x7fy"
opening_effect(M)
=
+ amount    if DUE
− amount    if CREDIT
```

The positive/negative representation is internal only.

The UI should use semantic wording.

---

# 59. Current Period Charges

Define:

```text id="5b75v3"
period_charges(M)
=
food_cost(M)
+
shared_cost(M)
+
debit_adjustments(M)
```

---

# 60. Current Period Credits

Define:

```text id="2x6h7k"
period_credits(M)
=
credit_adjustments(M)
```

---

# 61. Payment Treatment

A payment made by the member reduces what they owe.

Therefore:

```text payment_effect(M)
=
− total_paid(M)
```

---

# 62. Current Balance Formula

The canonical member balance is:

```text id="3v9qkp"
Final Balance(M)
=
Opening Effect(M)
+
Food Cost(M)
+
Shared Cost(M)
+
Debit Adjustments(M)
−
Credit Adjustments(M)
−
Payments(M)
```

---

# 63. Balance Interpretation

If:

```text id="1c8l15"
Final Balance > 0
```

then:

> Amount Due.

If:

```text id="u9i3qv"
Final Balance = 0
```

then:

> Settled.

If:

```text id="6k7g8w"
Final Balance < 0
```

then:

> Credit.

---

# 64. Example — Standard Member

```text id="z8i4lm"
Food cost             ৳2,500
Shared costs            ৳500
Debit adjustments       ৳100
Credit adjustments       ৳50
Opening balance          ৳0
Payments              ৳2,000
```

Formula:

```text id="c4u6sd"
0
+ 2500
+ 500
+ 100
- 50
- 2000
=
৳1,050
```

Result:

> Amount due: ৳1,050.

---

# 65. Example — Opening Credit

```text id="f4t0a7"
Opening credit = ৳300
Food cost = ৳1,000
Shared cost = ৳200
Payments = ৳500
```

Calculation:

```text id="w1g5uy"
−300
+1000
+200
−500
=
৳400
```

Result:

> Amount due: ৳400.

---

# 66. Example — Overpayment

```text id="j6l8yl"
Current charges = ৳3,000
Payments = ৳3,500
```

Balance:

```text id="v7c7v0"
৳3,000 − ৳3,500
=
−৳500
```

Result:

> Credit: ৳500.

---

# 67. Example — Exact Settlement

```text id="m8n4nq"
Charges = ৳4,250
Payments = ৳4,250
```

Balance:

```text id="9f7jb2"
৳0
```

Status:

> Settled.

---

# 68. Example — Zero Meals

Suppose:

```text id="f5sp7s"
Food expenses = ৳5,000
Meal units = 0
```

The engine must not create member food costs.

Settlement state:

```text id="2f2j1r"
MEAL_RATE_UNAVAILABLE
```

Period closure is blocked.

---

# 69. Member With Zero Meals

Suppose:

```text id="2dm3c2"
Meal units = 0
Meal rate = ৳50
Shared costs = ৳300
Payments = ৳0
```

Food cost:

```text ৳0
```

Final balance:

```text ৳300
```

Result:

> Amount due: ৳300.

---

# 70. Member With Zero Meals and Credit

Suppose:

```text id="e1omz0"
Food = ৳0
Shared = ৳300
Credit adjustment = ৳500
Payment = ৳0
```

Balance:

```text ৳300 − ৳500
=
−৳200
```

Result:

> Credit: ৳200.

---

# 71. Guest-Only Host

A member can have:

```text id="a9jz8y"
own meals = 0
guest meals = 4
```

if the manager records guests.

Their food cost is based on:

```text 4 chargeable units.
```

---

# 72. Guest Charge Surcharge

V1 default:

```text id="8a3gy4"
guest meal = normal meal unit
```

No surcharge.

The architecture may later support:

```text guest surcharge
```

but it is excluded from V1.

---

# 73. Expense Payer Accounting

Critical rule:

> The payer of an expense is not automatically the sole beneficiary of that expense.

Example:

```text id="e1h8l5"
Expense = ৳1,000
Paid by A
Shared = A/B/C/D
```

Allocation:

```text A = 250
B = 250
C = 250
D = 250
```

A receives only their allocation as a charge.

The financial fact that A paid ৳1,000 is separately recognized through the payment/expense-payer mechanism.

---

# 74. Critical Distinction: Payer vs Payment

There are two different economic facts:

### Expense advance

A pays the vendor on behalf of the mess.

### Member payment

A pays money into the mess.

These are not inherently identical database events.

---

# 75. Recommended V1 Treatment of Expense Payer

The source expense remains:

```text id="f1b8s6"
expense amount = ৳1,000
paid_by = A
```

The member's settlement gets the allocation:

```text A = ৳250
```

But the mess-level accounting reconciliation must also recognize that A funded the entire expense.

---

# 76. Need for an Expense Funding Credit

To correctly settle members when one person directly pays a mess expense, the engine must account for the payer's advance.

Therefore define:

```text id="3h0db1"
Expense Advance Credit(M)
=
sum of valid expense amounts directly paid by M
```

for expenses where:

```text id="0jq4o3"
paid_by_period_member_id = M
```

---

# 77. Revised Balance Formula

This is a critical accounting refinement.

Member balance should be:

```text id="r6f2d1"
Final Balance(M)
=
Opening Effect
+
Food Cost
+
Shared Cost
+
Debit Adjustments
−
Credit Adjustments
−
Payments
−
Expense Advances
```

where `Expense Advances` are actual member-paid mess expenses.

---

# 78. Why This Is Necessary

Example:

```text id="g06j2s"
Internet expense = ৳1,000
A paid vendor directly
A/B/C/D share it equally
```

Without recognizing A's funding:

```text id="09y1oa"
A is charged ৳250
but their ৳1,000 advance disappears from settlement.
```

That incorrectly makes A effectively pay the full amount without receiving the appropriate credit.

With the advance:

```text id="o8x1z3"
A charge = 250
A expense advance = 1000
Net effect = −750
```

B/C/D each:

```text +250
```

Total settlement impact reconciles to zero across these four participants.

---

# 79. Expense Advance Definition

For member M:

```text id="l7cl4n"
Expense Advance(M)
=
Σ(expense.amount)
where paid_by_period_member_id = M
and expense is valid
```

However, this should be restricted to expenses whose payment was actually made by the member and whose accounting treatment is intended to affect settlement.

---

# 80. Why Payment and Expense Advance Remain Separate

Suppose A:

```text id="59o8ed"
pays vendor ৳1,000
```

and later:

```text id="l7q9a0"
pays mess ৳500
```

These are economically distinct:

```text Expense Advance = ৳1,000
Member Payment = ৳500
```

Both affect the balance differently.

---

# 81. Food Expense Payer

For meal-related groceries, the payer also advances money.

Example:

```text id="2x6d3d"
Groceries = ৳10,000
Paid by A
```

A receives:

```text Expense Advance = ৳10,000
```

while all members pay through food cost.

This automatically reallocates the grocery funding fairly according to meal consumption.

---

# 82. Mess-Level Settlement Reconciliation

This creates an important property:

```text id="afq4h5"
sum(member charges)
−
sum(member expense advances)
```

must reconcile with the remaining external cash/settlement position according to the payment model.

---

# 83. Expense Advance and Meal Rate

Expense advances do **not** reduce the expense itself.

The food expense remains:

```text id="dj6q5c"
৳10,000
```

and therefore still contributes to meal rate.

The payer's advance is simply a settlement credit.

---

# 84. Expense Advance and Shared Allocation

For a shared non-meal expense:

```text id="t5z1st"
expense = 1000
A pays
participants = A/B/C/D
```

the accounting is:

```text charges:
A +250
B +250
C +250
D +250

advance:
A -1000
```

Net:

```text id="d8n8r8"
A −750
B +250
C +250
D +250
```

Total:

```text 0
```

This is correct from the perspective of member-to-member settlement.

---

# 85. Expense Advance and Non-Allocated Expense

If:

```text id="hju9l2"
expense = ৳1,000
paid by A
allocation_method = NONE
```

then:

```text A = −৳1,000 advance
```

but no member charges arise.

This creates a net credit rather than a fully allocated cost.

Therefore V1 should strongly warn the manager that:

> This expense is not being charged to any member.

---

# 86. Recommended V1 Rule

For non-meal expenses where `allocation_method = NONE`:

* the expense remains a mess-level expense
* payer receives an expense advance credit
* no member receives an allocation

This is mathematically coherent but may not be what the manager intended.

Therefore show a strong warning.

---

# 87. Expense Advances Are Not Member Payments

This distinction must be visible in statements.

Example:

```text id="q2j4v4"
Payments made to mess        ৳500
Expenses paid on behalf      ৳1,000
```

Combined settlement effect:

```text ৳1,500
```

but displayed separately.

---

# 88. Member Statement Structure

The statement should therefore include:

```text id="pjm9s9"
Food cost
Shared costs
Debits
Credits
Opening balance
Payments made
Expenses paid on behalf
Final balance
```

This makes the accounting explainable.

---

# 89. Revised Complete Formula

Define:

```text id="4w6i7o"
Opening Effect
=
+ opening_due
− opening_credit

Charges
=
food_cost
+
shared_cost
+
debit_adjustments

Credits
=
credit_adjustments
+
payments
+
expense_advances

Final Balance
=
Opening Effect
+
Charges
−
Credits
```

---

# 90. Why Payments Are Credits

A member paying the mess reduces their obligation.

Thus:

```text payment → credit against balance
```

---

# 91. Why Expense Advances Are Credits

A member paying a mess expense on behalf of others also reduces what that member should ultimately owe.

Thus:

```text expense advance → credit against balance
```

---

# 92. Potential Double-Counting Warning

This model introduces a critical implementation rule:

> An expense paid directly by a member must not also be entered as a separate member payment for the same vendor transaction unless the member actually paid the mess in addition to paying the vendor.

Example:

```text Grocery bill ৳1,000
A paid vendor
```

Do not also automatically create:

```text Payment by A ৳1,000
```

because that would double-credit A.

---

# 93. Member Payment Example

Correct:

```text id="fk2tdf"
A pays grocery store ৳1,000
→ Expense advance = ৳1,000

Later A pays mess account ৳500
→ Payment = ৳500
```

Total credits affecting A:

```text ৳1,500
```

---

# 94. Expense Payer and Payment Records

The application should therefore communicate clearly:

### Expense

> Who paid the vendor?

### Payment

> Who paid money into the mess?

These are separate questions.

---

# 95. Period-Level Reconciliation

For every period, calculate:

```text id="6h0xqz"
Total external expenses
=
sum of all valid expenses
```

Then distinguish:

```text meal-related expenses
+
non-meal expenses
```

---

# 96. Allocation Reconciliation

For every shared expense:

```text id="s3t4ab"
sum(allocations)
=
expense amount
```

If not, calculation status is:

```text INVALID
```

and closure must be blocked.

---

# 97. Payer-Funding Reconciliation

For a valid expense:

```text id="e1c8vq"
payer advance
=
expense amount
```

The engine can therefore independently report:

```text total expenses paid by members
```

---

# 98. Member-Level Reconciliation

For each member:

```text id="m5g9hx"
final_balance
=
opening
+
charges
−
credits
```

The calculation engine must be able to expose every term.

---

# 99. Period Cash Reconciliation

The system should produce:

```text id="5i1fla"
Total member payments
+
Total expense advances
```

as a funding summary.

This is not necessarily equal to total expenses because:

* members may have outstanding balances
* members may have credits
* opening balances may exist
* adjustments may exist

But it is useful for operational reconciliation.

---

# 100. Outstanding Balance

Total amount currently owed by members is:

```text id="r15j1h"
Σ(max(final_balance, 0))
```

---

# 101. Total Member Credits

Total credits owed to members are:

```text id="5e7d7y"
Σ(max(-final_balance, 0))
```

---

# 102. Net Member Balance

The net member balance is:

```text id="2j4v6r"
Σ(final_balance)
```

The sign depends on the accounting direction.

---

# 103. Settlement Status Distribution

The system should count:

```text id="y3qstq"
members_due
members_credit
members_settled
```

---

# 104. Rounding at Period Level

The final mess-level summary should use exactly rounded monetary values.

No report should produce:

```text ৳999.999999 id="9c2s1m"
```

for a user-visible total.

---

# 105. Rounding of Final Member Balances

The final member balance should be expressed to two decimal places.

Any intermediate residual must be resolved before snapshot finalization.

---

# 106. Rounding Rule Consistency

The same rounding algorithm must be used for:

* meal-cost allocation
* equal expense allocation
* weighted expense allocation
* final settlement amounts

where residuals arise.

---

# 107. Fixed Allocation Rounding

Fixed allocations are already explicit.

No residual algorithm is needed unless the manager enters more precision than the currency supports.

V1 monetary inputs are restricted to two decimal places.

---

# 108. Weighted Allocation Rounding

Calculate raw exact allocation:

```text id="c0g2jp"
expense × weight / total_weight
```

then use deterministic largest-remainder allocation to reach exactly the original expense amount.

---

# 109. Equal Allocation Rounding

Same principle:

```text id="0l2s4s"
expense / participant_count
```

then deterministic residual distribution.

---

# 110. Meal Cost Allocation

Member food cost is a proportional allocation of total meal cost based on member meal units.

Therefore it should also use the largest-remainder approach for final settlement.

---

# 111. Why Member Food Cost Must Reconcile to Meal Cost

Suppose:

```text id="6id3h2"
Total meal cost = ৳10,000
```

The sum of all member food costs should be:

```text ৳10,000.00
```

not:

```text ৳9,999.98
```

or:

```text ৳10,000.04.
```

---

# 112. Shared Costs and Food Cost Are Separate

A shared internet expense must not modify the meal rate.

Thus:

```text id="34qdz2"
Meal Rate
=
Meal-related expenses
÷
Meal units
```

only.

---

# 113. Shared Expense Does Not Increase Food Cost

Suppose:

```text id="gk4d96"
Food expenses = ৳10,000
Internet = ৳1,000
```

Meal rate uses:

```text ৳10,000
```

not:

```text ৳11,000
```

---

# 114. Shared Expense Included in Member Settlement

Internet does affect the relevant members:

```text id="t8z2dd"
A +250
B +250
C +250
D +250
```

---

# 115. Rent

Rent is treated like any other non-meal expense.

If selected participants share it:

```text id="8w6z93"
allocated through shared-cost engine.
```

If not:

```text id="5q1i2z"
mess-level unallocated expense
+
payer advance if member-funded.
```

---

# 116. Electricity

Same principle.

Electricity does not automatically affect meal rate.

---

# 117. Cooking Gas

V1 default recommendation:

```text id="h85y8g"
Cooking gas = OTHER_NON_MEAL
```

The manager can explicitly classify it otherwise if the mess accounting policy requires.

The category's default treatment is not the final immutable truth for an expense.

---

# 118. Adjustment Treatment

A credit/debit is deliberately separate from expenses.

It should never alter:

* meal rate
* meal count
* expense amount
* payment record

It only changes the member's settlement position.

---

# 119. Credit Adjustment Example

```text id="0r1w6g"
Member overcharged by ৳100
```

Create:

```text CREDIT = ৳100
```

No expense is modified.

---

# 120. Debit Adjustment Example

```text id="3q8k63"
Member owes ৳200 for a correction
```

Create:

```text DEBIT = ৳200
```

No meal count is modified.

---

# 121. Opening Balance vs Adjustment

Opening balance represents prior-period settlement.

Adjustment represents a current-period manual correction.

Do not use one as a substitute for the other.

---

# 122. Carry-Forward Rule

At close of period:

```text Previous final balance
→
Next period opening balance
```

Example:

September:

```text id="0gq8qk"
A = ৳500 due
```

October:

```text opening balance = ৳500 DUE
```

---

# 123. Credit Carry-Forward

September:

```text id="8g1yqp"
A = ৳300 credit
```

October:

```text opening balance = ৳300 CREDIT
```

---

# 124. No Silent Carry-Forward

The next period should explicitly contain the opening balance.

Do not simply subtract September's amount from October's calculation with no traceable record.

---

# 125. Automatic Carry-Forward Source

The opening balance should reference:

```text id="g3s4y4"
source_period_id
```

where it is derived from a prior finalized settlement.

---

# 126. Manual Opening Balance

A manager may eventually need to create a manual opening balance.

If allowed:

* reason required
* creator required
* audit required

---

# 127. Opening Balance and Payments

If a member begins October with:

```text id="9e7m6k"
৳500 due
```

and pays:

```text ৳200
```

their remaining opening obligation becomes:

```text ৳300
```

before considering October activity.

---

# 128. Opening Credit and New Charges

If:

```text id="p3r8mi"
৳500 credit
```

and current charges are:

```text ৳300
```

member remains:

```text ৳200 credit
```

if no additional payment is made.

---

# 129. Settlement Snapshot Data

A finalized snapshot should store enough information to reproduce the member statement.

Minimum:

```text id="iw0xqj"
meal units
food cost
shared cost
credit adjustments
debit adjustments
opening balance
payments
expense advances
total obligation
final balance
balance status
```

The existing schema should therefore be extended to include:

```text expense_advances
```

in `settlement_member_snapshots`.

---

# 130. Required Schema Refinement

Add:

```sql id="5k7sqw"
alter table public.settlement_member_snapshots
add column expense_advances numeric(16,2) not null default 0;
```

This is required because the corrected accounting model explicitly recognizes member-funded expenses as settlement credits.

The schema document should be considered updated by this requirement.

---

# 131. Settlement Member Calculation Structure

The engine should return:

```text id="7lm5hd"
{
  meal_units,
  food_cost,
  shared_cost,
  credit_adjustments,
  debit_adjustments,
  opening_balance,
  opening_direction,
  payments,
  expense_advances,
  total_charges,
  total_credits,
  final_balance,
  balance_status
}
```

---

# 132. Total Charges

```text id="y6rm4x"
total_charges
=
food_cost
+
shared_cost
+
debit_adjustments
+
opening_due
```

---

# 133. Total Credits

```text id="0e3s8y"
total_credits
=
opening_credit
+
credit_adjustments
+
payments
+
expense_advances
```

---

# 134. Final Balance

```text id="3ty7ot"
final_balance
=
total_charges
−
total_credits
```

This is an alternative equivalent form of the canonical formula.

---

# 135. Settlement Status Determination

After exact calculation:

```text id="d2qf1x"
if final_balance > 0:
    DUE

if final_balance = 0:
    SETTLED

if final_balance < 0:
    CREDIT
```

---

# 136. Final Display Rounding

If an internal final balance is extremely close to zero due to calculation precision:

```text id="p9c0kt"
abs(balance) < minimum accounting unit
```

normalize to:

```text ৳0.00
```

The exact tolerance should be the currency precision, not an arbitrary floating tolerance.

---

# 137. Never Use `Math.abs(x) < 0.000001` for Money

Financial equality should use exact decimal semantics.

Do not use generic floating-point epsilon logic for final accounting.

---

# 138. Period Validation

Before calculating final settlement, the engine should validate:

```text id="5d6q6x"
all relevant records belong to period
no invalid allocations
no invalid member relationships
no invalid meal types
no illegal dates
```

---

# 139. Invalid Data Handling

If invalid data exists:

The calculation engine should not silently calculate around it.

Return:

```text id="hk3up6"
calculation_status = INVALID
```

with structured errors.

---

# 140. Calculation Result Status

Recommended:

```text id="w3m7td"
READY
UNAVAILABLE
INVALID
FINAL
```

### READY

Current calculation is valid.

### UNAVAILABLE

Example: no meals.

### INVALID

Data integrity problem.

### FINAL

Finalized snapshot.

---

# 141. Blocking Conditions

Recommended settlement blockers:

### Blocker 1

Invalid shared allocation.

### Blocker 2

Cross-context financial record inconsistency.

### Blocker 3

Food expenses > 0 with zero meals.

### Blocker 4

Invalid meal configuration.

### Blocker 5

Missing manager.

### Blocker 6

Period already in incompatible state.

---

# 142. Warning Conditions

Possible warnings:

* no meals for a specific day
* member has zero meals
* non-meal expense has no allocation
* unusually high expense
* unusually low meal count

Warnings do not automatically block closure.

---

# 143. No Manual Calculation Override

The manager must not be able to type:

```text id="sy1kxx"
Meal rate = ৳60.00
```

to override the calculated rate.

If an exceptional correction is required:

> Use an adjustment or correct the underlying records.

---

# 144. No Manual Member Food Cost Override

Likewise, a manager should not be able to type:

```text id="4l5cje"
A food cost = ৳2,500
```

while the underlying meal records produce a different result.

---

# 145. Corrections Belong at the Source

If the number is wrong because:

```text id="n5o6vc"
A lunch was missed
```

correct the meal record.

If:

```text id="d1r6v9"
grocery expense was entered incorrectly
```

correct the expense.

If:

```text id="8q3x9w"
exceptional financial correction
```

use an adjustment.

---

# 146. Calculation Version

Every finalized settlement must store:

```text id="em8k4m"
calculation_version = '1.0'
```

Future versions can use:

```text 1.1
2.0
```

when material accounting rules change.

---

# 147. Backward Compatibility

The application must know how to render historical snapshots generated by older calculation versions.

Do not assume every historical period will always be recalculated using the newest formulas.

---

# 148. Reopen/Recalculate Behavior

When a closed period is reopened:

```text id="z5b8i7"
Old snapshot remains historical
 ↓
Period becomes OPEN
 ↓
Live calculation resumes
 ↓
New snapshot created at subsequent closure
```

---

# 149. Snapshot Versioning

Example:

```text id="l0r9hz"
September 2026
Snapshot 1 → FINAL
```

Reopened:

```text id="z4g7fp"
Snapshot 1 → historical
Snapshot 2 → FINAL
```

The application should identify Snapshot 2 as current final state.

---

# 150. Meal Rate History

A closed snapshot should preserve the final meal rate used.

Even if the current calculation engine produces a different rate later because the formula changed, the old final statement retains its original result.

---

# 151. Member Statement Source Priority

For a closed period:

```text id="2gyq1o"
finalized snapshot
```

is the authoritative presentation source.

For an open period:

```text id="t4dw3g"
live calculation
```

is the authoritative source.

---

# 152. Live vs Final

### Open

> Current estimated balance

### Closed

> Final balance

---

# 153. Calculation Cache

V1 should prefer recalculation from facts rather than storing mutable per-member balances.

Snapshots are the exception.

---

# 154. Recalculation Triggers

Changes affecting calculation include:

```text id="m1n6ca"
meal create/update/delete
meal type weight change
food expense create/update/void
shared expense allocation change
payment create/update/void
adjustment create/update/void
opening balance change
```

---

# 155. No Explicit "Recalculate" UI

The system recalculates automatically.

Technical recalculation functions may exist.

Managers should not manually initiate arithmetic.

---

# 156. Meal Entry Impact

Changing:

```text A lunch 0 → 1
```

can change:

* total meal units
* meal rate
* every member's food cost
* every member's final balance

Therefore meal changes can have period-wide financial impact.

---

# 157. Food Expense Impact

Adding:

```text ৳2,000 grocery
```

changes:

* total meal cost
* meal rate
* every member's food cost
* potentially all final balances

This should be clear to the manager.

---

# 158. Shared Expense Impact

Adding:

```text internet ৳1,000
```

affects only:

* source expense
* selected allocations
* payer's expense advance
* balances of participants/payer

It does not affect:

* meal rate
* meal count
* unrelated members

unless they are included in the allocation.

---

# 159. Payment Impact

Payment affects only:

* payer/member's balance

It does not alter:

* meal rate
* meal cost
* expense allocation

---

# 160. Adjustment Impact

Adjustment affects only the selected member.

---

# 161. Expense Advance Impact

Recording an expense paid by A affects:

* A's settlement credit
* mess funding statistics
* member-level balance

It does not change:

* expense amount
* expense allocation
* meal rate unless the expense itself is meal-related

---

# 162. Global Invariant — Food Cost

```text id="lq4y2v"
Σ(member food costs)
=
total meal-related expense
```

after final settlement rounding.

---

# 163. Global Invariant — Shared Allocation

For every allocated expense:

```text id="4wlv1p"
Σ(member allocations)
=
expense.amount
```

---

# 164. Global Invariant — Statement

For every member:

```text id="q5w8r4"
final balance
=
charges
−
credits
```

exactly at accounting precision.

---

# 165. Global Invariant — Status

```text id="3l7wzq"
balance > 0 → DUE
balance = 0 → SETTLED
balance < 0 → CREDIT
```

---

# 166. Global Invariant — No Circular Meal Calculation

Meal rate depends on:

```text id="9g2z2g"
meal expenses
meal units
```

not member balances.

---

# 167. Global Invariant — No Circular Shared Expense

Allocation depends on:

```text id="p17j8h"
source expense
participants
method
weights
```

not member balances.

---

# 168. Global Invariant — Payment Independence

Payments do not change the meal rate.

---

# 169. Global Invariant — Expense Advance Independence

Expense advances do not change the meal rate.

---

# 170. Period-Level Summary

The period summary should contain:

```text id="q1n25m"
total members
total meal units
total meal-related expenses
meal rate
total non-meal expenses
total shared allocations
total payments
total expense advances
total credits
total debits
total outstanding
total member credits
```

---

# 171. Total Food Expense vs Total Food Cost

For a valid period:

```text total meal-related expenses
```

and:

```text total member food cost
```

must reconcile.

---

# 172. Total Shared Expense vs Total Shared Allocations

For all allocated expenses:

```text id="2uw1g5"
Σ shared expense amounts
=
Σ shared allocations
```

---

# 173. Unallocated Expenses

Unallocated non-meal expenses may exist.

Therefore:

```text total non-meal expenses
```

does not necessarily equal:

```text total member shared cost
```

The difference is explicitly:

```text unallocated non-meal expenditure.
```

The dashboard should distinguish these.

---

# 174. Payer Funding

Period summary should separately show:

```text id="9g6lcb"
Expenses paid by members
```

This tells the manager how much members advanced on behalf of the mess.

---

# 175. Payments vs Expense Advances

Dashboard may show:

```text id="x3y0wf"
Member payments
৳X

Expenses paid on behalf
৳Y
```

These should not be merged into one ambiguous "money received" number.

---

# 176. Current Outstanding

Total member amount due:

```text id="ch9wv8"
Σ(max(balance, 0))
```

---

# 177. Current Credit

Total member credit:

```text id="8kq4cc"
Σ(max(-balance, 0))
```

---

# 178. Net Position

```text id="n7j2lj"
Net Member Position
=
Σ(balance)
```

This is useful internally but should not replace the separate due/credit totals in the UI.

---

# 179. Reconciliation Diagnostic

The engine should expose a diagnostics object:

```text id="9i65ig"
{
  is_valid,
  blockers[],
  warnings[],
  reconciliation[]
}
```

This is useful for the settlement screen.

---

# 180. Example Diagnostic

```text id="x2i4sg"
{
  is_valid: false,

  blockers: [
    {
      code: "ALLOCATION_MISMATCH",
      expense_id: "...",
      expected: "1000.00",
      actual: "980.00"
    }
  ],

  warnings: [
    {
      code: "NO_MEALS_ON_DATE",
      date: "2026-09-12"
    }
  ]
}
```

---

# 181. Calculation Engine API — Conceptual

Recommended internal functions:

```text id="p7dx6o"
calculate_meal_units(period_id)

calculate_meal_cost(period_id)

calculate_meal_rate(period_id)

calculate_member_food_costs(period_id)

calculate_expense_allocations(expense_id)

calculate_member_statement(period_id, period_member_id)

calculate_period_summary(period_id)

validate_period_for_closure(period_id)

generate_settlement_snapshot(period_id)
```

---

# 182. Function Purity

Where possible, calculation functions should be pure/read-only.

For example:

```text id="g0qkl8"
calculate_member_statement(...)
```

should return values, not modify accounting data.

---

# 183. Mutation Functions

Separate functions should perform mutations:

```text id="t3c9ib"
create_expense()
update_expense()
record_payment()
close_period()
```

This creates a clean separation:

```text calculation
vs
mutation
```

---

# 184. Close Period Calculation

`close_period()` must:

1. verify authorization
2. verify period state
3. run blockers
4. calculate all results
5. verify reconciliations
6. create final snapshot
7. finalize snapshot
8. mark period closed
9. write audit event

All in one transaction.

---

# 185. Close Period Atomicity

If snapshot creation fails:

```text id="p09h9h"
period remains OPEN
```

rather than:

```text period CLOSED
but snapshot missing
```

---

# 186. Finalized Snapshot Immutability

After:

```text id="df4p8m"
status = FINAL
```

snapshot records cannot be directly updated by application users.

---

# 187. Calculation Version on Snapshot

Every snapshot receives:

```text id="6u5uvt"
calculation_version
```

at finalization.

---

# 188. Reopening and Historical Snapshot

When reopened:

The previous final snapshot remains a historical record.

The period's live state becomes editable.

A new final snapshot is generated upon reclosure.

---

# 189. Multiple Reopen Cycles

Supported:

```text id="4x9w8m"
Snapshot 1
 ↓
Reopen
 ↓
Snapshot 2
 ↓
Reopen
 ↓
Snapshot 3
```

Only one latest snapshot is current final state.

The application can retain all versions for auditability.

---

# 190. Manager Review

Before closing, the settlement screen should display:

```text id="m9l9d3"
Meal rate
438 meal units
৳24,880 meal cost

Shared costs
৳6,450

Expense advances
৳8,200

Member payments
৳26,100

Outstanding
৳4,230

Credits
৳850
```

---

# 191. No Hidden Calculations

A final statement should be derivable from the visible categories:

```text id="85j8sf"
Opening
+
Food
+
Shared
+
Debits
−
Credits
−
Payments
−
Expense Advances
=
Final Balance
```

---

# 192. Formula Presentation

The user-facing UI should simplify the terminology:

```text id="70aqg3"
Charges
Credits
Payments
Expenses paid on behalf
Final balance
```

The underlying engine can maintain more technical distinctions.

---

# 193. Accounting Vocabulary

Preferred member-facing terms:

| Internal concept    | User-facing term       |
| ------------------- | ---------------------- |
| `food_cost`         | Food cost              |
| `shared_cost`       | Shared costs           |
| `debit_adjustment`  | Extra charge           |
| `credit_adjustment` | Credit                 |
| `payment`           | Payment                |
| `expense_advance`   | Expense paid on behalf |
| `opening_due`       | Previous balance       |
| `opening_credit`    | Previous credit        |
| `final_balance > 0` | Amount due             |
| `final_balance < 0` | Credit                 |

---

# 194. Manager-Facing Detail

Managers may optionally see more explicit accounting terminology:

```text id="f3gf1d"
Expense advance
Allocation
Credit adjustment
Debit adjustment
Opening balance
```

---

# 195. Settlement Example

Suppose A has:

```text id="p6a1ax"
Meal units              42
Meal rate               ৳58.50
Food cost               ৳2,457.00
Shared cost             ৳650.00
Debit adjustment        ৳100.00
Credit adjustment        ৳50.00
Opening due             ৳200.00
Payments                ৳2,000.00
Expense advances        ৳500.00
```

Calculation:

```text id="i8z6q0"
Charges
= 2,457 + 650 + 100 + 200
= 3,407

Credits
= 50 + 2,000 + 500
= 2,550

Final balance
= 3,407 − 2,550
= ৳857 due
```

---

# 196. Example — Shared Expense Paid by Member

Internet:

```text id="s4vqp5"
Expense = ৳1,000
Paid by A
Participants = A/B/C/D
```

Allocations:

```text id="de3ehk"
A = 250
B = 250
C = 250
D = 250
```

Expense advance:

```text A = 1,000
```

Net settlement impact:

```text id="m1d6ro"
A = −750
B = +250
C = +250
D = +250
```

Total:

```text ৳0
```

---

# 197. Example — Food Expense Paid by One Member

Groceries:

```text id="t25w08"
৳10,000
Paid by A
```

Meal rate:

```text food cost = ৳10,000
```

Suppose:

```text id="1myx0f"
A meal units = 50
B meal units = 30
C meal units = 20
```

Total:

```text 100
```

Food costs:

```text id="xf21jk"
A = ৳5,000
B = ৳3,000
C = ৳2,000
```

A's expense advance:

```text −৳10,000
```

Therefore net grocery settlement impact:

```text id="w4gpw6"
A = −৳5,000
B = +৳3,000
C = +৳2,000
```

Exactly balances to zero.

---

# 198. Example — Member Pays More Than Their Charges

Suppose:

```text id="kn7a6z"
Charges = ৳2,000
Payments = ৳2,000
Expense advances = ৳500
```

Balance:

```text id="5o5y4j"
−৳500
```

Result:

> Credit ৳500.

---

# 199. Example — Expense Advance Without Allocation

Expense:

```text id="l3xov8"
৳500
Paid by A
No allocation
```

A gets:

```text −৳500
```

and the mess has an unallocated expense.

This should trigger a warning because the manager may have forgotten to select beneficiaries.

---

# 200. Example — Non-Member Payer

V1 does not support an external payer.

Therefore:

```text expense.paid_by_period_member_id
```

must reference an eligible period member.

Future versions may support external suppliers/landlords.

---

# 201. Negative Expense Values

Expenses must not be negative.

To reverse an expense:

```text id="z7qz5m"
void expense
```

or create a separate correction mechanism.

Do not enter:

```text −৳500
```

as a normal expense.

---

# 202. Negative Payment Values

Payments must not be negative.

Reverse through:

```text id="z9l6zy"
void/correction
```

not:

```text −৳500
```

---

# 203. Negative Allocation Values

Never.

---

# 204. Negative Meal Quantities

Never.

---

# 205. Negative Adjustments

Never.

Use:

```text CREDIT
DEBIT
```

instead.

---

# 206. Member With No Food Cost but Shared Cost

Valid.

Example:

```text id="6k0w1m"
0 meals
৳300 shared cost
```

Member owes:

```text ৳300
```

unless credits/payments offset it.

---

# 207. Member With No Charges but Expense Advance

Example:

```text id="3t3zq8"
Food = 0
Shared = 0
Paid expense = ৳1,000
```

Member receives:

```text ৳1,000 credit
```

This is logically correct because the member financed a mess expense.

---

# 208. Member With No Charges but Payment

Example:

```text id="s1r2u3"
Food = 0
Shared = 0
Payment = ৳500
```

Member receives:

```text ৳500 credit
```

unless the payment is explicitly assigned to another period/context by an approved future mechanism.

---

# 209. Multiple Credits

Credits can stack:

```text id="q2ou1i"
Opening credit = 100
Adjustment credit = 50
Payment = 200
Expense advance = 300
```

Total credits:

```text ৳650
```

---

# 210. Member Final Balance Visibility

The UI should not expose a confusing raw negative number.

Translate:

```text −650
```

to:

> Credit ৳650.

---

# 211. Settlement Snapshot Formula Fields

The snapshot should preserve both source quantities and final outputs.

At period level:

```text id="ft5g8k"
meal_units_total
meal_cost_total
meal_rate
shared_cost_total
payment_total
expense_advance_total
credit_adjustment_total
debit_adjustment_total
closing_balance_total
```

---

# 212. Schema Refinement — Period Snapshot

The existing `settlement_snapshots` table should also add:

```sql id="v8d9x2"
alter table public.settlement_snapshots
add column expense_advance_total numeric(16,2) not null default 0;
```

This provides a complete period-level snapshot.

---

# 213. Snapshot Reconciliation Fields

The final snapshot should make it possible to independently verify:

```text id="f7n7ub"
member food costs
+
member shared costs
+
debits
+
opening dues
−
credits
−
payments
−
expense advances
```

---

# 214. Final Snapshot Integrity

At finalization:

```text id="s9gq8w"
all member balances
```

must be generated from the same calculation version and calculation run.

Do not calculate each member using unrelated asynchronous requests.

---

# 215. Atomic Settlement Generation

Use one database transaction.

Conceptually:

```text id="9j3kph"
BEGIN

validate period

calculate summary

calculate member statements

insert snapshot

insert member snapshots

finalize snapshot

close period

audit

COMMIT
```

---

# 216. Failure During Settlement

If any step fails:

```text ROLLBACK id="j1s5xc"
```

The period stays open.

No partial final snapshot should remain.

---

# 217. Calculation Reproducibility

A calculation should be reproducible from:

```text id="c30jwr"
period_id
source data
calculation_version
configuration
```

---

# 218. Calculation Engine as a Domain Boundary

The frontend should ask:

```text id="2f91fj"
"What is A's current balance?"
```

not:

```text "Give me meals, then I will independently calculate everything." id="qf4t7v"
```

The canonical calculation service should produce the authoritative result.

---

# 219. Reporting Consistency

Dashboard, settlement, history, and member statement should all use the same calculation definitions.

---

# 220. No Screen-Specific Formula

There must not be:

```text id="lk2d1e"
dashboard formula ≠ settlement formula
```

---

# 221. Currency Unit

V1 uses:

```text id="nd3e9m"
BDT
```

All monetary values are represented to two decimal places.

Bangladesh currency is commonly denominated in taka and poisha, so two-decimal monetary precision is appropriate for V1.

---

# 222. Currency Configuration

Although V1 is BDT-only, the database keeps:

```text currency_code
```

to prevent hardcoding the accounting architecture.

---

# 223. Future Currency Support

Multi-currency is not supported in V1.

If introduced later, exchange-rate behavior would require a new specification.

---

# 224. Date Scope

Accounting calculations are based on the period's date boundaries.

Each source record must be within the relevant period unless an explicitly supported exception exists.

---

# 225. Membership Scope

Meals and allocations should normally be restricted by membership effective dates.

---

# 226. Membership Boundary Example

Member joins:

```text id="0a7e9f"
15 Sep
```

Meal:

```text 14 Sep
```

must be rejected.

---

# 227. Membership End Example

Member leaves:

```text id="7k9gg7"
22 Sep
```

Meal:

```text 23 Sep
```

must be rejected.

---

# 228. Manager Status Does Not Affect Calculation

Changing manager does not alter:

* meal totals
* expenses
* allocations
* payments
* balance

It only changes authority.

---

# 229. Membership Change Does Not Rewrite History

Changing current membership does not rewrite historical records.

---

# 230. Join Code Does Not Affect Accounting

Changing the join code must not affect:

* periods
* meals
* expenses
* payments
* balances

---

# 231. Period Settings Snapshot

Meal weights and applicable accounting settings must be interpreted from the period configuration.

---

# 232. Current Settings Do Not Rewrite Closed History

A later settings change cannot alter a finalized historical snapshot.

---

# 233. Reopening Explicitly Changes History

If a manager intentionally reopens a period:

The resulting final settlement may change.

The system must document this through audit/versioning.

---

# 234. Settlement Calculation Result

Recommended conceptual structure:

```text id="jmbxau"
PeriodResult {
    periodId,
    calculationStatus,
    blockers[],
    warnings[],
    summary,
    members[],
    reconciliation
}
```

---

# 235. Member Result

```text id="f2v2wu"
MemberSettlement {
    periodMemberId,
    mealUnits,
    foodCost,
    sharedCost,
    creditAdjustments,
    debitAdjustments,
    openingBalance,
    payments,
    expenseAdvances,
    totalCharges,
    totalCredits,
    finalBalance,
    balanceStatus
}
```

---

# 236. Reconciliation Result

```text id="7g39y0"
Reconciliation {
    mealCostExpected,
    mealCostAllocated,
    mealCostDifference,

    sharedExpensesExpected,
    sharedAllocationsActual,
    sharedAllocationDifference,

    memberBalanceTotal,

    isBalanced
}
```

---

# 237. Meal-Cost Reconciliation

Expected:

```text id="41cwr5"
mealCostExpected
=
Σ(MEAL_COST expenses)
```

Actual:

```text id="8h3i8c"
mealCostAllocated
=
Σ(member food costs)
```

Difference should be:

```text ৳0.00
```

---

# 238. Shared Allocation Reconciliation

Expected:

```text id="y55bjp"
Σ(shared expense amounts)
```

Actual:

```text id="v4m4xw"
Σ(all shared allocation amounts)
```

The difference must be zero for every allocated expense.

---

# 239. Member Balance Reconciliation

The engine should sum:

```text id="jvvtvr"
all member balances
```

and make this value available.

This is a useful diagnostic, not necessarily expected to be zero because members may owe money or have credit.

---

# 240. Finalization Rule

A period can be finalized only if:

```text id="hgpq0s"
calculationStatus = READY
AND
all blocking reconciliations pass
AND
authorized manager confirms
```

---

# 241. Final Snapshot Rule

The snapshot itself should contain:

```text id="h9yd6l"
the exact numbers that were shown in the final confirmation
```

No recalculation should occur after the transaction commits that could produce a different number without creating a new version.

---

# 242. Manager Confirmation

The final UI confirmation should show the same data that the database will snapshot.

This avoids:

```text id="6p3wff"
UI says ৳58.50
database snapshots different value
```

---

# 243. Calculation Test Requirement

Every formula must have deterministic test cases.

Minimum:

```text id="gd0y70"
single member
multiple members
zero meals
zero food cost
weighted meals
guest meals
equal split
weighted split
fixed split
rounding
opening due
opening credit
payment
overpayment
expense advance
adjustments
mid-month membership
```

---

# 244. Golden Test Cases

Create canonical test fixtures.

Example:

```text id="s02bqa"
TEST-001
3 members
100 meal units
৳10,000 food cost
```

Expected:

```text meal rate = ৳100
```

These outputs become regression tests.

---

# 245. Golden Test — Rounding

```text id="2m2t8v"
Food cost = ৳100
Members = 3
Each = 1 unit
```

Expected:

```text id="s6w6i0"
33.34
33.33
33.33
```

Total:

```text ৳100.00
```

---

# 246. Golden Test — Equal Expense

```text id="9w4c4n"
Expense = ৳100
A/B/C
```

Expected:

```text A 33.34
B 33.33
C 33.33
```

---

# 247. Golden Test — Payer

```text id="g9a4jl"
Expense = ৳1,000
A pays
A/B/C/D share equally
```

Expected net settlement effect:

```text A -750
B +250
C +250
D +250
```

---

# 248. Golden Test — Opening Credit

```text id="i7f4t1"
Opening credit = 300
Current charges = 500
Payments = 100
```

Expected:

```text due = 100
```

Because:

```text -300 + 500 - 100 = 100
```

---

# 249. Golden Test — Overpayment

```text id="3w7c0k"
Charges = 500
Payments = 700
```

Expected:

```text credit = 200
```

---

# 250. Golden Test — Adjustments

```text id="5f4c1c"
Charges = 1000
Debit = 100
Credit = 50
Payments = 500
```

Expected:

```text 1000 + 100 - 50 - 500
= 550 due
```

---

# 251. Golden Test — Zero Food Expense

```text id="5p5s1b"
Meal units = 100
Food cost = 0
```

Expected:

```text Meal rate = 0
Food cost per member = 0
```

---

# 252. Golden Test — Zero Meals

```text id="tk63c3"
Meal units = 0
Food cost = 100
```

Expected:

```text unavailable
closure blocker
```

---

# 253. Golden Test — Zero Meals/Zero Food

```text id="q3xqko"
Meal units = 0
Food cost = 0
```

Expected:

```text rate unavailable
```

not:

```text rate = 0
```

---

# 254. Golden Test — Guest Meals

```text id="5s8v7k"
A own meals = 10
A guest meals = 2
Meal rate = 50
```

Expected:

```text A food cost = 600
```

---

# 255. Golden Test — Weighted Expense

```text id="ii2v7y"
Expense = 1000

A weight = 2
B weight = 1
C weight = 1
```

Expected:

```text A = 500
B = 250
C = 250
```

---

# 256. Golden Test — Fixed Expense

```text id="zb9eaf"
Expense = 1000
A = 300
B = 700
```

Expected:

```text valid
```

---

# 257. Golden Test — Fixed Mismatch

```text id="7jd59g"
Expense = 1000
A = 300
B = 600
```

Expected:

```text invalid
closure blocked
```

---

# 258. Golden Test — Mid-Month Member

A joins on September 15.

Meals before September 15:

```text id="f4l23k"
invalid
```

Meals from September 15 onward:

```text valid
```

---

# 259. Golden Test — Mid-Month Departure

A ends membership September 22.

Meals after September 22:

```text invalid
```

---

# 260. Golden Test — Manager Transfer

Changing manager from A to B must produce identical accounting output.

Only authorization context changes.

---

# 261. Golden Test — Current Configuration Change

Changing October meal weight must not change September's finalized snapshot.

---

# 262. Golden Test — Reopen

September snapshot 1:

```text id="cbx1ga"
meal rate = 50
```

After reopening and correcting an expense:

```text id="1byb5z"
meal rate = 52
```

Final snapshot 2:

```text 52
```

Snapshot 1 remains historical.

---

# 263. Calculation Security

Users must not be able to request arbitrary private member statements through a privileged function.

Calculation functions must respect the same authorization boundaries as the underlying data.

---

# 264. Calculation Function Isolation

Prefer:

```text id="dzq2m5"
security invoker
```

when possible.

If:

```text security definer
```

is necessary, explicitly enforce authorization inside the function.

---

# 265. Calculation Function Performance

For a normal period:

```text 5–30 members
```

the engine should calculate in a reasonable server-side operation rather than issuing hundreds of browser round trips.

---

# 266. One Canonical Calculation Path

Every user-facing settlement should conceptually invoke:

```text id="20c7p7"
calculate_period_summary()
```

or a shared underlying calculation layer.

---

# 267. Calculation Engine Independence

The engine should not depend on:

* React state
* component rendering
* page-specific query order
* localStorage
* browser locale

---

# 268. Final Accounting Model

The final canonical formula is:

```text id="n5v9w9"
FOR EACH MEMBER:

Opening Effect
+
Food Cost
+
Shared Cost
+
Debit Adjustments
−
Credit Adjustments
−
Payments
−
Expense Advances
=
Final Balance
```

And:

```text id="c5c5ue"
Food Cost
is derived from
Meal Units × canonical Meal Rate
```

while:

```text id="1u6by4"
Meal Rate
=
Total MEAL_COST Expenses
÷
Total Chargeable Meal Units
```

---

# 269. Final Non-Circular Accounting Structure

```text id="g02j38"
                    MEALS
                      │
                      ▼
               TOTAL MEAL UNITS
                      │
                      │
FOOD EXPENSES ────────┤
                      ▼
                  MEAL RATE
                      │
                      ▼
               MEMBER FOOD COST
                      │
                      │
SHARED EXPENSES ──────┤
                      ▼
               MEMBER SHARED COST
                      │
                      │
ADJUSTMENTS ──────────┤
                      │
OPENING BALANCE ──────┤
                      │
PAYMENTS ─────────────┤
                      │
EXPENSE ADVANCES ─────┤
                      ▼
                FINAL BALANCE
```

---

# 270. Final Accounting Invariants

The production calculation engine must guarantee:

```text id="t48q7l"
1. No division by zero.
2. Meal-related expenses determine the meal rate.
3. Shared non-meal expenses do not affect meal rate.
4. Member food costs reconcile to total meal-related expenditure.
5. Shared allocations reconcile to their expenses.
6. Expense payer advances are distinct from member payments.
7. Payments reduce member balances.
8. Expense advances reduce member balances.
9. Credits and debits use explicit direction.
10. Opening balances are explicit.
11. Zero-meal cases are represented as unavailable, not zero.
12. Every member receives a deterministic final balance.
13. Rounding is deterministic.
14. Closed snapshots are reproducible.
15. The same source data yields the same result.

### Important architectural consequence

This document uncovered one requirement that needs to be carried backward into the schema: **`expense_advances` must be captured in settlement snapshots**, because a member who directly pays a mess expense needs a settlement credit distinct from a normal payment. That is why the schema refinement above adds `expense_advance_total` at period level and `expense_advances` at member level.

The next document is **Document 11 — Audit, Data Integrity & Historical Accounting Specification**. That will define exactly how corrections, voids, reopening, manager changes, membership changes, snapshot versioning, audit events, and historical data protection work together.
```
