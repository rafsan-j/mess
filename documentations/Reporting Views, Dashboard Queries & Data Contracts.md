# Document 14 — Reporting Views, Dashboard Queries & Data Contracts

**Product:** Mess Manager
**Document:** Reporting Views, Dashboard Queries & Data Contracts
**Version:** 1.0
**Status:** Implementation Specification
**Depends on:** Documents 1–13

---

# 1. Purpose

This document defines the read/query layer of Mess Manager.

The system has already defined:

* the database structure
* authorization
* accounting rules
* settlement calculation
* audit behavior
* mutation RPCs

This document defines how the frontend retrieves that information safely and consistently.

The core principle is:

> A page should consume a trusted read model instead of rebuilding accounting logic from raw tables.

This avoids:

* duplicated SQL
* duplicated calculations
* inconsistent balances
* accidental data leakage
* unnecessary database requests
* different pages showing different versions of the same number

---

# 2. Read Architecture

The intended data flow is:

```text id="9c9xtn"
PostgreSQL tables
      ↓
RLS / authorization
      ↓
Trusted views / read functions
      ↓
Supabase query / RPC
      ↓
Application data layer
      ↓
Page / component
```

For complex accounting:

```text id="f4c8vz"
Source records
      ↓
Calculation functions
      ↓
Reporting model
      ↓
UI
```

The UI must not independently recompute authoritative accounting figures.

---

# 3. Read Model Categories

The application should expose several conceptual read models.

## 3.1 Identity

* current profile
* authorized messes
* current period context

## 3.2 Dashboard

* current period status
* manager/member state
* financial summary
* warnings
* blockers
* recent activity

## 3.3 Meals

* personal meals
* manager meal grid
* meal totals
* guest meals

## 3.4 Expenses

* expense list
* expense details
* allocation details
* expense advance information

## 3.5 Payments

* personal payments
* manager payment list

## 3.6 Settlement

* period settlement
* personal statement
* member balances
* reconciliation state

## 3.7 History

* closed periods
* historical personal statements
* historical manager settlement
* audit information

---

# 4. Current User Context

The frontend should have a single authoritative query for the basic authenticated context.

Conceptually:

```text id="br6s6t"
get_current_user_context()
```

The result can include:

```json id="vhwuw4"
{
  "user": {...},
  "messes": [...],
  "currentMessId": "...",
  "currentPeriodId": "...",
  "currentRole": "MANAGER"
}
```

The backend must determine these values from actual database relationships.

---

# 5. Mess Selector

The user may belong to more than one mess in the future.

Therefore the frontend must not hard-code:

```text id="h2nwid"
one user = one mess
```

The read layer should be able to return:

```text id="k6pyil"
Mess A
Mess B
Mess C
```

with the appropriate access state for each.

---

# 6. Current Period Resolver

The frontend should not guess the current period from dates.

Prefer a trusted query such as:

```text id="i3q4tg"
get_current_period(mess_id)
```

The backend determines:

* whether a period exists
* its status
* its date range
* current manager
* relevant membership state

---

# 7. Dashboard Data Contract

The dashboard should have one consolidated read model rather than making many independent accounting queries.

Conceptually:

```text id="1r9tdp"
get_dashboard_summary(period_id)
```

Possible output:

```json id="02i68x"
{
  "period": {
    "id": "...",
    "name": "September 2026",
    "status": "OPEN",
    "startDate": "2026-09-01",
    "endDate": "2026-09-30"
  },
  "user": {
    "periodMemberId": "...",
    "role": "MANAGER"
  },
  "accounting": {
    "mealUnits": 142,
    "mealCost": "12600.00",
    "mealRate": "88.732394",
    "sharedCost": "4300.00",
    "payments": "5000.00",
    "expenseAdvances": "12600.00"
  },
  "memberSummary": {
    "totalMembers": 5,
    "activeMembers": 5
  },
  "health": {
    "blockers": [],
    "warnings": [...]
  }
}
```

The exact JSON structure can be normalized during implementation.

---

# 8. Dashboard for Ordinary Member

Members should receive a reduced dashboard.

Conceptually:

```text id="w3syii"
get_my_dashboard(period_id)
```

Return:

* current period
* own meal count
* own food cost
* own shared cost
* own payments
* own expense advances
* own final balance
* balance status
* relevant warnings
* recent personal activity

The member dashboard should not automatically expose manager-only diagnostics.

---

# 9. Dashboard for Manager

Managers require broader operational information.

The manager dashboard should include:

```text id="q6f8x9"
Period status
Member count
Meals entered / missing
Total meal units
Meal-related expenses
Current meal rate
Shared expenses
Total payments
Total expense advances
Outstanding balances
Credits
Integrity status
Warnings
Recent activity
```

---

# 10. Dashboard Health Model

The dashboard should distinguish:

```text id="x0u2do"
Healthy
Warning
Blocked
```

These states must not rely only on color.

Example:

```text id="jo7slc"
Settlement
✓ Reconciled
```

versus:

```text id="h0y0p2"
Settlement
⚠ 1 warning
```

versus:

```text id="j0ekr8"
Settlement
✕ Cannot close
```

---

# 11. Blocker Contract

The backend should return machine-readable blockers.

Example:

```json id="gwnr3m"
{
  "code": "MEAL_COST_WITHOUT_MEAL_UNITS",
  "severity": "BLOCKER",
  "message": "Meal-related expenses exist but there are no chargeable meal units."
}
```

The frontend can display the message while using the code for deterministic UI behavior.

---

# 12. Warning Contract

Warnings may look like:

```json id="f2c9dy"
{
  "code": "HIGH_MANUAL_ADJUSTMENT",
  "severity": "WARNING",
  "message": "This period contains unusually large manual adjustments."
}
```

Warnings do not necessarily prevent closing.

---

# 13. Meal Grid Read Model

The manager meal page needs a compact, date/member-oriented representation.

Conceptually:

```text id="p4b8c2"
get_manager_meal_grid(
    period_id,
    start_date,
    end_date
)
```

Output:

```json id="ps12lk"
{
  "members": [...],
  "mealTypes": [...],
  "days": [
    {
      "date": "2026-09-10",
      "entries": [...]
    }
  ]
}
```

The response should avoid returning duplicated member metadata for every meal row.

---

# 14. Personal Meal Read Model

Use:

```text id="y5us0e"
get_my_meals(period_id, date_range)
```

Return:

* date
* meal type
* quantity
* weight
* weighted units
* relevant guest meal data

The backend should calculate weighted units consistently with the canonical calculation engine.

---

# 15. Meal Totals

The meal page may display:

```text id="wof2xm"
Breakfast = 25
Lunch = 32
Dinner = 28
Total units = 85
```

Totals should come from trusted SQL aggregation.

The frontend may sum visible rows for an instantaneous UI preview, but the server result remains authoritative.

---

# 16. Guest Meal Read Model

Guest meal queries should return:

* date
* meal type
* quantity
* host
* active/void state where manager is authorized to see it

For a member, use a scoped personal query.

---

# 17. Expense List Read Model

Manager expense list should support:

```text id="v3f06d"
get_period_expenses(
    period_id,
    date_from,
    date_to,
    category,
    accounting_type,
    status,
    search
)
```

Fields:

* expense ID
* date
* description
* category
* accounting type
* amount
* payer
* allocation method
* status
* created timestamp

---

# 18. Expense List Pagination

Expense lists should use pagination.

Recommended:

```text id="oep0dn"
limit
cursor
```

rather than returning the entire period.

Default page size might be around:

```text id="c2h43a"
20–50 rows
```

with the exact value tuned during implementation.

---

# 19. Expense Detail Read Model

Conceptually:

```text id="au4j4q"
get_expense_detail(expense_id)
```

The backend must authorize access to the expense's period.

The result can include:

```text id="80xpqw"
Expense
 ├── basic details
 ├── category
 ├── accounting type
 ├── payer
 ├── allocation method
 ├── allocations
 ├── advance effect
 ├── created/updated information
 └── relevant correction history
```

---

# 20. Expense Allocation Display

For equal allocation:

```text id="l6js1w"
A   250
B   250
C   250
D   250
```

For weighted:

```text id="0ajc9y"
A   weight 2   → 666.67
B   weight 1   → 333.33
```

For fixed:

```text id="w4x8li"
A   400
B   600
```

The UI should display both method and resulting amounts.

---

# 21. Expense Advance Display

When a member paid the vendor directly, the UI should clearly differentiate:

```text id="7u2xka"
Expense allocated to you       250 BDT
You advanced for this expense  1000 BDT
Net effect                    -750 BDT
```

Do not label the 1,000 BDT as a "payment" because it is a vendor advance.

---

# 22. Payment List

Conceptually:

```text id="vyp9z8"
get_period_payments(
    period_id,
    member_id?,
    date_range?,
    status?
)
```

Manager sees the period.

Member sees their own payments.

The result should distinguish:

```text id="7j9qdl"
VALID
VOIDED
```

where historical visibility requires it.

---

# 23. Payment Detail

The payment detail response should include:

* payment date
* amount
* member
* description
* created timestamp
* void status
* void reason where authorized

A payment should never appear as valid merely because a row exists.

Its active accounting state must be respected.

---

# 24. Personal Statement Data Contract

The canonical personal statement is:

```text id="nfx0o2"
get_my_statement(period_id)
```

Recommended result:

```json id="78x9ne"
{
  "periodId": "...",
  "member": {...},
  "mealUnits": "42",
  "foodCost": "3716.23",
  "sharedCost": "850.00",
  "debitAdjustments": "0.00",
  "creditAdjustments": "200.00",
  "openingEffect": "0.00",
  "payments": "2500.00",
  "expenseAdvances": "1000.00",
  "totalCharges": "4566.23",
  "totalCredits": "3700.00",
  "finalBalance": "866.23",
  "balanceStatus": "DUE"
}
```

---

# 25. Member Statement Breakdown

The statement page should support expandable detail.

### Charges

```text id="txg4sp"
Food cost
Shared cost
Debit adjustments
Opening due
```

### Credits

```text id="5e4dvz"
Payments
Expense advances
Credit adjustments
Opening credit
```

### Result

```text id="rpz1df"
Amount due
```

or:

```text id="h3m4g8"
Credit
```

---

# 26. Signed-Balance Presentation

The database may internally use a signed balance.

The UI should not make users interpret:

```text id="a5n6h8"
-5750
```

Instead display:

```text id="x9w3kw"
Credit
5,750 BDT
```

or:

```text id="f3xq1r"
Amount due
866 BDT
```

The sign remains a calculation representation, not the primary user-facing terminology.

---

# 27. Settlement Overview

Manager settlement page requires:

```text id="mgf5st"
get_period_settlement(period_id)
```

Output should include:

```text id="p6g9aj"
Member
Meal units
Food cost
Shared cost
Adjustments
Payments
Expense advances
Final balance
Status
```

This should support sorting by:

* member
* balance
* meal units
* amount due
* credit

---

# 28. Settlement Summary

At the top of the settlement page:

```text id="9x4sp0"
Total meal units
Total meal cost
Meal rate
Total shared expenses
Total payments
Total expense advances
Net outstanding
Reconciliation status
```

The exact wording should distinguish gross charges from member contributions.

---

# 29. Settlement Member Details

Selecting a member should open a detailed statement rather than forcing the manager to reconstruct the balance from the overview table.

Conceptually:

```text id="i6y7k1"
get_member_settlement_detail(period_id, period_member_id)
```

The backend must verify manager authority for the period.

---

# 30. Settlement Status

Each member should have:

```text id="8xpr58"
DUE
CREDIT
SETTLED
```

These are derived from final balance.

Do not permit a client to set status manually.

---

# 31. Historical Settlement

For a closed period:

```text id="2c8q6x"
get_historical_settlement(period_id)
```

should return the finalized settlement snapshot.

Do not unnecessarily recalculate a closed period for every page request.

The snapshot is the authoritative historical result.

---

# 32. Historical Snapshot Detail

The historical settlement should expose:

* snapshot version
* calculation version
* finalized time
* period data
* member snapshots
* reconciliation status
* superseded status if applicable

---

# 33. Reopened Historical Period

When a closed period is reopened:

```text id="d96lwd"
Current state = OPEN
Old snapshot = preserved
```

During reopening, the UI should indicate:

> This period was previously finalized and has been reopened. A new settlement version will be created when it is closed again.

This avoids users confusing live values with the old finalized result.

---

# 34. History Page

The history page should return:

```text id="x8s77e"
get_period_history(mess_id)
```

Possible result:

```text id="3z7o9z"
September 2026   CLOSED   Final v2
August 2026      CLOSED   Final v1
July 2026        CLOSED   Final v3
```

Each row can include:

* period name
* date range
* status
* manager
* settlement version
* finalized timestamp

---

# 35. Personal History

Member-facing history should show only periods the member is authorized to view.

Example:

```text id="jkf84q"
September 2026
Amount due 1,250 BDT

August 2026
Credit 340 BDT
```

---

# 36. Manager Historical Access

A manager may view authorized periods according to the exact access rules.

Current manager status must not automatically grant unrestricted historical management power.

Historical viewing and historical mutation remain separate concepts.

---

# 37. Audit History Read Model

Manager-facing audit view may use:

```text id="ar9jpw"
get_period_audit_events(
    period_id,
    filters,
    cursor
)
```

Fields may include:

* event timestamp
* actor
* action
* entity type
* entity reference
* reason
* summary

Detailed before/after payloads may be shown only when necessary.

---

# 38. Audit Event Filtering

Useful filters:

* actor
* action
* entity type
* date range
* accounting category

Avoid exposing arbitrary JSON search to the frontend as a first-class requirement.

---

# 39. Recent Activity Feed

The dashboard can expose a simplified activity feed:

```text id="o4w9tj"
Today
A added 4 lunches
B recorded a payment of 2,000 BDT
C updated the electricity expense
```

This is a presentation layer derived from audit events.

It must not reveal data the viewer is not authorized to see.

---

# 40. Member Dashboard Activity

A member should receive a restricted version:

```text id="g5j7gs"
Your meal updated
Your payment recorded
Your adjustment added
```

not the entire mess's operational activity.

---

# 41. Query Scoping Rule

Every query that accepts a period ID must ultimately verify:

```text id="4lf6v4"
the caller is authorized for that period
```

Every query that accepts a member ID must verify:

```text id="70axl8"
the member belongs to the authorized period
```

Every query that accepts an expense/payment/meal ID must derive its mess/period relationship and enforce access.

---

# 42. Avoid Arbitrary `mess_id` Trust

The frontend may store the currently selected mess.

It is not authoritative.

For example:

```text id="6y6fom"
mess_id = "X"
```

must not by itself grant access to X.

The backend must verify the relationship between:

```text id="02ho3f"
auth.uid()
→ membership
→ period/mess
```

---

# 43. Pagination Contract

Paginated endpoints should return:

```json id="q4o7xi"
{
  "items": [...],
  "nextCursor": "...",
  "hasMore": true
}
```

Avoid:

```json id="8n7gpg"
{
  "items": [...],
  "total": 28471
}
```

on every request unless total counts are explicitly needed.

Large count queries can become unnecessarily expensive.

---

# 44. Sorting Contract

Sorting must be deterministic.

For example:

```text id="tj7b7a"
created_at DESC
+
id DESC
```

This ensures stable pagination when multiple rows share the same timestamp.

---

# 45. Filtering Contract

Filters should use typed values.

Examples:

```text id="r6p6ih"
status = OPEN
accounting_type = SHARED_NON_MEAL
date_from = 2026-09-01
date_to = 2026-09-30
```

Avoid passing arbitrary SQL expressions from the frontend.

---

# 46. Numeric Data Contract

Money values returned to the frontend should be represented safely.

Because PostgreSQL `NUMERIC` may not map exactly to JavaScript `Number`, the API layer should preserve precision.

Recommended representation:

```text id="d8h0w4"
"1234.50"
```

as a decimal string for monetary values where necessary.

The frontend may convert to a dedicated decimal representation for display/calculation previews.

It must not silently lose cents through binary floating-point conversion.

---

# 47. Dates and Time

Accounting dates should be returned as:

```text id="5owcpl"
YYYY-MM-DD
```

Timestamps should include timezone information.

The frontend should not reinterpret accounting dates through the user's local timezone in a way that changes the calendar date.

---

# 48. Nullability Contract

The reporting layer must preserve meaningful nulls.

Example:

```text id="z5xvwl"
mealRate = null
```

means:

> Meal rate cannot currently be defined.

It must not be converted to:

```text id="g7k07x"
0
```

for convenience.

---

# 49. Empty Results

No records should be represented consistently.

For lists:

```json id="c8l3l4"
[]
```

For nullable single records:

```json id="q9r9j5"
null
```

Do not randomly return `{}`, `null`, `[]`, or missing fields for the same conceptual state.

---

# 50. Loading Contract

The application data layer should distinguish:

```text id="0uv0qd"
loading
loaded with data
loaded empty
error
forbidden
not found
```

A page must not interpret an empty array as evidence that the user has no access.

---

# 51. Forbidden vs Empty

This distinction is especially important.

Example:

```text id="z8lqg0"
User requests another member's statement
```

The system should not simply return:

```text id="5f1k10"
[]
```

because that can cause misleading UI.

Where appropriate, return a proper:

```text id="9d9pbv"
FORBIDDEN
```

response.

---

# 52. Not Found vs Forbidden

Security-sensitive resources may intentionally blur:

```text id="s7c3b0"
not found
```

and:

```text id="k9v9je"
not authorized
```

depending on the access model.

The implementation should choose one consistent strategy for protected object lookup.

The frontend must support the selected behavior.

---

# 53. Data Freshness

Open-period financial summaries are dynamic.

Therefore the application should refresh after mutations such as:

* meal save
* expense create/update/void
* payment create/void
* adjustment
* opening balance correction

The source of truth remains Supabase.

The frontend should invalidate affected query caches after a successful mutation.

---

# 54. Realtime

Realtime can be added later.

V1 does not require full realtime synchronization between every manager device.

A good initial model is:

```text id="w4e9k2"
mutation succeeds
    ↓
invalidate relevant queries
    ↓
refetch
```

If realtime is introduced, it must not bypass RLS or become an alternate accounting system.

---

# 55. Manager Multi-Device Consistency

If manager A updates meals on a phone while manager B views the dashboard on another device:

The second device should refresh or revalidate after relevant changes.

The final database value remains authoritative.

---

# 56. Query Cache Policy

The application may cache:

* meal types
* period metadata
* category lists
* historical closed statements

with reasonable lifetimes.

Do not treat cached financial values as permanent.

Open-period settlement values should have short freshness windows and should be invalidated after mutations.

---

# 57. Personal Statement Cache

A personal statement may be cached briefly, but must be invalidated after any operation that can affect:

* that member's meals
* shared allocations
* payments
* expense advances
* adjustments
* opening balance

---

# 58. Manager Settlement Cache

Manager settlement should be invalidated after:

```text id="5h6s1f"
meal mutation
guest meal mutation
expense mutation
allocation mutation
payment mutation
adjustment mutation
opening balance mutation
```

No mutation should leave a stale authoritative-looking settlement on screen without a freshness strategy.

---

# 59. Query Naming Convention

Use clear names separating:

### Personal

```text id="3qt6xo"
get_my_...
```

### Manager

```text id="ol4czn"
get_period_...
get_member_...
```

### Historical

```text id="q1w8j1"
get_historical_...
```

### Diagnostic

```text id="x5pjio"
get_..._integrity...
```

This reduces accidental use of a manager-capable function from a member-facing page.

---

# 60. Recommended Read API

The frontend should ultimately consume a small set of stable operations.

### Context

```text id="w00fah"
get_current_user_context
get_current_period
```

### Dashboard

```text id="m0pk9a"
get_my_dashboard
get_dashboard_summary
```

### Meals

```text id="ajddwr"
get_my_meals
get_manager_meal_grid
get_period_meal_totals
```

### Expenses

```text id="xkca6j"
get_period_expenses
get_expense_detail
```

### Payments

```text id="b1j8y8"
get_my_payments
get_period_payments
```

### Statements

```text id="wycf6t"
get_my_statement
get_member_statement
```

### Settlement

```text id="ox9i8p"
get_period_settlement
get_member_settlement_detail
```

### History

```text id="j0c0fu"
get_period_history
get_historical_settlement
get_historical_member_statement
```

### Audit

```text id="n8wytj"
get_period_audit_events
```

---

# 61. Query Ownership

Each read operation should have a single authoritative implementation.

Do not have:

```text id="0l9r1e"
Dashboard calculation
Settlement calculation
Statement calculation
```

all independently calculate:

```text id="m3g1h7"
food cost
```

Instead:

```text id="3x33aw"
canonical calculation
      ↓
dashboard
settlement
statement
```

---

# 62. Reporting Layer Must Not Mutate Data

Read functions/views should be side-effect free.

They must not:

* insert expenses
* create payments
* update balances
* close periods
* modify audit events

except for narrowly controlled internal diagnostics where the mutation is explicitly part of the design.

---

# 63. Security of Reporting Views

Every exposed view/function must be reviewed under RLS.

Questions to answer:

```text id="o0v6w9"
Can this view reveal another mess?
Can this function accept another member's ID?
Can a former member see current data?
Can a non-manager see manager-only data?
Can a user infer private information through aggregation?
```

---

# 64. Aggregation Privacy

Even aggregate values can leak information.

Example:

If a mess has only two members and a manager sees a sensitive category breakdown, an individual member might infer another person's behavior.

V1 should prioritize accounting transparency within a mess, but future privacy-sensitive features must consider small-group inference.

---

# 65. Manager Dashboard Query Composition

The dashboard should ideally be assembled from a trusted database reporting function or a small number of clearly defined queries.

Avoid dozens of components independently querying Supabase for:

```text id="r8f89g"
member count
meal count
expense count
payment count
balance count
```

and each calculating its own filters.

Centralized reporting improves consistency.

---

# 66. Mobile Query Optimization

Mobile networks are slower and more variable.

Therefore:

* return only necessary fields
* paginate long lists
* avoid giant historical payloads
* use consolidated dashboard reads
* avoid repeated metadata queries

The data contract should be designed for responsive mobile use.

---

# 67. Desktop Query Optimization

Desktop managers may request more data at once, especially:

* meal grids
* settlement table
* expense lists

But the application should still use pagination/virtualization where datasets become large.

---

# 68. Failure-Tolerant UI

If a secondary query fails, the application should not necessarily blank the entire page.

For example:

```text id="u8t4l1"
Dashboard
 ├── balance ✓
 ├── member count ✓
 ├── recent activity ✕
```

The UI can display the available primary data and a localized error state.

Critical accounting pages should nevertheless fail closed when authoritative settlement data cannot be obtained.

---

# 69. Settlement Read Failure

If the system cannot retrieve a trusted settlement:

Do not display:

```text id="t9j0l6"
0 BDT
```

as a fallback.

Display an explicit unavailable/error state.

This prevents a technical failure from being interpreted as a zero balance.

---

# 70. Historical Snapshot Failure

Similarly, if a finalized snapshot cannot be retrieved:

Do not silently calculate a new live value and label it:

> Final settlement.

The UI must distinguish:

```text id="3rj11p"
FINAL SNAPSHOT
```

from:

```text id="52kn0z"
LIVE CALCULATION
```

---

# 71. Reporting Invariants

Every trusted reporting function must preserve:

```text id="d0wvj5"
Food cost reconciliation
Allocation reconciliation
Balance equation
Period scope
Member scope
Historical snapshot version
Authorization
```

A reporting function that produces an impressive-looking table but violates these invariants is not acceptable.

---

# 72. Final Read-Layer Architecture

The complete flow becomes:

```text id="pyu9uq"
                    ┌───────────────┐
                    │ Source Tables │
                    └───────┬───────┘
                            │
                    ┌───────▼───────┐
                    │ RLS / Grants  │
                    └───────┬───────┘
                            │
             ┌──────────────▼──────────────┐
             │ Trusted Reporting Functions │
             └──────────────┬──────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
      Dashboard         Statements        Settlement
          │                 │                 │
          └─────────────────┼─────────────────┘
                            ▼
                         Frontend
```

---

# 73. Final Data-Contract Principles

The frontend implementation must follow these rules:

```text id="1m9leu"
1. Never trust arbitrary IDs for authorization.
2. Never calculate authoritative accounting in the browser.
3. Never turn NULL accounting values into zero.
4. Never treat a failed query as an empty result.
5. Never expose manager-only data to members.
6. Never expose one mess through another mess's query.
7. Use finalized snapshots for closed-period settlement.
8. Use live calculations for open-period settlement.
9. Preserve NUMERIC precision.
10. Keep pagination deterministic.
11. Invalidate affected cached data after mutations.
12. Keep reporting logic centralized.
```

---

# 74. Implementation Outcome

After this document, the frontend will have a clearly defined read contract for:

```text
Authentication/context
Dashboard
Meals
Guest meals
Expenses
Payments
Adjustments
Opening balances
Statements
Settlement
History
Audit
```

The backend now has three distinct logical layers:

```text id="j5m4ag"
1. Source-of-truth tables
2. Command/RPC layer
3. Reporting/read layer
```

with security and accounting integrity surrounding all three.

---

# 75. Next Implementation Artifact

The next document should define the **Database Test & Verification Specification**.

It should convert the accounting invariants, RLS restrictions, RPC rules, historical rules, concurrency behavior, and edge cases into an executable test plan so that the final Supabase migrations can be validated before the frontend is built.
