# Document 15 — Database Test, Verification & Golden Dataset Specification

**Product:** Mess Manager
**Document:** Database Test, Verification & Golden Dataset Specification
**Version:** 1.0
**Status:** Implementation Specification
**Depends on:** Documents 1–14

---

# 1. Purpose

This document defines how the Mess Manager backend must be tested before the frontend is considered production-ready.

The objective is not merely to verify that SQL executes successfully.

The database must demonstrate that it can:

* enforce authorization
* preserve mess isolation
* preserve period isolation
* calculate accounting correctly
* reject impossible accounting states
* protect closed periods
* preserve historical settlement
* handle manager rotation
* handle corrections
* prevent duplicate operations
* survive concurrent operations without corrupting accounting
* produce trustworthy audit records

---

# 2. Testing Philosophy

Testing follows four principles.

## 2.1 Test the database directly

Do not rely only on frontend tests.

A browser can contain bugs.

The database must remain correct even if:

```text
UI validation = bypassed
API payload = manipulated
UUID = changed
request = duplicated
multiple clients = active
```

---

## 2.2 Test negative cases aggressively

A secure system is defined partly by what it refuses to do.

Therefore every important permission should have a corresponding denial test.

---

## 2.3 Test accounting with deterministic expected values

Accounting tests must compare exact expected results.

For example:

```text
Expected food cost = 3,716.67
Actual food cost = 3,716.67
PASS
```

not:

```text
Actual looks approximately correct
```

---

## 2.4 Test the complete lifecycle

The system must be tested as a sequence:

```text
Create
→ Join
→ Approve
→ Open period
→ Record meals
→ Record expenses
→ Record payments
→ Calculate
→ Close
→ Reopen
→ Correct
→ Recalculate
→ Reclose
→ Review history
```

---

# 3. Test Environments

At minimum maintain:

```text id="s7q1wa"
Local development
    ↓
Test / preview Supabase project
    ↓
Production Supabase project
```

Production data must never be used as the primary automated-test dataset.

---

# 4. Test Database Reset

Automated database tests should start from a deterministic state.

Recommended strategy:

```text id="r2p9vf"
Apply migrations
       ↓
Load test fixtures
       ↓
Run tests
       ↓
Discard/reset database
```

Tests should not depend on state left behind by another test.

---

# 5. Test User Set

The base test environment should include at least:

```text id="5h9ynf"
User A
User B
User C
User D
User E
```

with known credentials in the test environment only.

Their roles must be configurable through actual database relationships.

Example:

```text id="z7aom3"
Mess X:
A = manager
B = member
C = member
D = member

Mess Y:
E = manager
```

---

# 6. Test Mess Set

Create at least:

```text id="8s5f9z"
Mess X
Mess Y
```

These are required for cross-mess security tests.

---

# 7. Test Period Set

Use multiple periods:

```text id="ul7j2q"
August 2026
September 2026
October 2026
```

Example:

```text id="c4t08s"
August:
A manager
B/C/D members

September:
B manager
A/C/D members

October:
C manager
A/B/D members
```

This specifically tests manager rotation and period-specific authority.

---

# 8. Test Data Principle

The golden dataset should be deliberately small enough to manually verify.

At the same time, load a larger synthetic dataset separately for:

* pagination
* performance
* indexing
* query plans
* concurrency

Do not use only a large random dataset. Random data makes accounting failures difficult to diagnose.

---

# 9. Unit Test Categories

The backend test suite should contain:

```text id="d5j7vz"
Schema tests
Constraint tests
RLS tests
RPC tests
Accounting tests
Audit tests
Historical tests
Concurrency tests
Idempotency tests
Performance tests
Recovery/integrity tests
```

---

# 10. Schema Tests

Verify that all required objects exist.

At minimum:

```text id="qw0oe7"
Tables
Enums
Indexes
Constraints
Functions
Triggers
Views
RLS policies
Grants
```

The migration should fail verification if an expected object is missing.

---

# 11. Foreign-Key Tests

Verify relationships such as:

```text id="jwdt6m"
period_members.period_id
→ periods.id
```

and:

```text id="2lr7p7"
meals.period_member_id
→ period_members.id
```

and all relevant equivalent relationships.

Invalid foreign keys must be rejected.

---

# 12. Unique-Constraint Tests

Verify:

* duplicate pending join request rejected
* duplicate logical meal record rejected
* duplicate active manager rejected
* duplicate active join code rejected where applicable
* duplicate allocation for same expense/member rejected
* duplicate request ID rejected or handled idempotently according to operation semantics

---

# 13. Period Overlap Test

Attempt:

```text id="u8c9g1"
Period A:
2026-09-01 → 2026-09-30

Period B:
2026-09-15 → 2026-10-15
```

Expected:

```text id="kl7z5k"
REJECTED
```

Test the database constraint directly and through the period-creation RPC.

---

# 14. Adjacent Period Test

Verify:

```text id="0j3qcs"
August:
2026-08-01 → 2026-08-31

September:
2026-09-01 → 2026-09-30
```

is valid if the application's period semantics permit contiguous periods.

---

# 15. Invalid Date Test

Attempt:

```text id="6nfjwd"
start = 2026-09-30
end   = 2026-09-01
```

Expected:

```text id="z08m7j"
REJECTED
```

---

# 16. RLS Test Framework

Every RLS test should establish:

```text id="4s7v8h"
SET authenticated user
→ perform query/mutation
→ assert result
```

The test harness must use actual Supabase authentication context or an equivalent controlled test mechanism.

It must not simply run everything as service role.

---

# 17. RLS Positive Tests

Examples:

### Own profile

```text id="1e1x7n"
A reads A profile
→ PASS
```

### Own statement

```text id="j56l3w"
A reads A statement
→ PASS
```

### Manager reads managed period

```text id="p8be7r"
A reads August where A is manager
→ PASS
```

---

# 18. RLS Negative Tests

### Another member's statement

```text id="2w7k43"
B requests C's statement
→ DENY
```

### Other mess

```text id="svx5n1"
A queries Mess Y
→ DENY
```

### Former manager

```text id="7agk9u"
A manages August but not September
A modifies September
→ DENY
```

---

# 19. Direct CRUD Security Tests

For every protected accounting table test direct client operations.

Example:

```text id="6n6c86"
authenticated member
→ direct INSERT payment
→ DENY
```

Also test:

```text id="2s1p5v"
manager
→ direct UPDATE expense
→ DENY
```

where the intended architecture requires RPC-only mutation.

---

# 20. RPC Authorization Tests

For every mutation RPC, test:

```text id="rj2v1j"
anonymous
member
authorized manager
former manager
unrelated mess manager
```

Expected access must be explicitly defined.

---

# 21. Create Mess Test

Execute:

```text id="61sbsq"
create_mess()
```

Verify:

* mess created
* creator profile exists
* initial membership state correct
* manager assignment correct
* join code state correct according to workflow
* audit event exists

---

# 22. Join Request Test

User B submits valid join code.

Verify:

```text id="0c9ufr"
join_request.status = PENDING
```

and:

```text id="z98hi3"
JOIN_REQUEST_CREATED
```

exists in audit history.

---

# 23. Duplicate Join Request Test

User B submits the same request twice.

Expected:

```text id="8qz8wd"
one pending request only
```

The second operation should return an appropriate conflict/idempotency result.

---

# 24. Approval Test

Manager A approves B.

Verify atomically:

```text id="p5d4rv"
request = APPROVED
period membership = ACTIVE
audit = JOIN_REQUEST_APPROVED
```

There must be no state where one is updated and the other is not.

---

# 25. Self-Approval Test

B attempts to approve B's own pending request.

Expected:

```text id="d8c8bz"
DENY
```

---

# 26. Rejection Test

Manager rejects a pending request.

Verify:

* request becomes rejected
* reason is preserved if required
* audit event exists
* requester can submit a new request later where product rules permit it

---

# 27. Manager Transfer Test

A → B.

Verify:

```text id="7p8l98"
A manager assignment ended
B manager assignment active
exactly one current manager
audit event exists
```

---

# 28. Concurrent Manager Transfer Test

Start simultaneously:

```text id="j35q2n"
A → B
A → C
```

Expected final state:

```text id="f4dy0e"
one valid manager
```

not:

```text id="r6g1w4"
B + C both managers
```

---

# 29. Period Creation Test

Create a valid period.

Verify:

* status correct
* manager correct
* membership initialized appropriately
* meal types configured
* audit event exists

---

# 30. Period State Tests

Verify valid:

```text id="0r2u8w"
DRAFT → OPEN
OPEN → CLOSED
CLOSED → OPEN
```

Verify invalid:

```text id="y1hqed"
OPEN → DRAFT
CLOSED → DRAFT
```

---

# 31. Closed-Period Mutation Tests

After closing:

Attempt:

```text id="z5cn5f"
save meal
create expense
update expense
void expense
record payment
create adjustment
change membership
change meal type
```

Expected:

```text id="v2of47"
all rejected
```

except explicitly permitted reopen workflow.

---

# 32. Meal Entry Tests

Test:

```text id="2h1e3a"
quantity = 0
quantity = 1
quantity = multiple units
invalid negative quantity
date outside period
wrong meal type
wrong period member
```

Expected outcomes must match validation rules.

---

# 33. Meal Weight Tests

Example:

```text id="hmzjzi"
Breakfast weight = 1
Lunch weight = 1
Dinner weight = 1

Member:
Breakfast 1
Lunch 1
Dinner 1

Meal units = 3
```

Then:

```text id="9dk3l5"
Dinner weight = 2
```

Meal units should become:

```text id="l4h4vt"
4
```

Historical records in another period must remain unaffected.

---

# 34. Guest Meal Tests

Test:

```text id="g0r2tn"
1 guest meal
multiple guest meals
invalid host
invalid date
invalid meal type
void guest meal
```

Verify guest meals affect the intended accounting calculation and no unintended member identity is created for the guest.

---

# 35. Food Expense Test

Create:

```text id="5p7zrv"
MEAL_COST = 10,000
```

with:

```text id="3vquq8"
meal units = 100
```

Expected:

```text id="23ff1o"
meal rate = 100
```

---

# 36. Zero-Meal Test

Create:

```text id="y3q9du"
MEAL_COST = 10,000
meal units = 0
```

Expected:

```text id="la6oxw"
meal_rate = NULL
close = BLOCKED
```

No division-by-zero error should escape as an uncontrolled database error.

---

# 37. Zero-Food-Cost Test

Create:

```text id="f3xtus"
meal units > 0
meal cost = 0
```

Expected:

```text id="e3gqnb"
meal_rate = 0
```

and closure is not blocked merely because food cost is zero.

---

# 38. Food-Cost Distribution Test

Suppose:

```text id="c56t9v"
A = 50 units
B = 30 units
C = 20 units

Food cost = 10,000
```

Expected proportional result:

```text id="j1evku"
A = 5,000
B = 3,000
C = 2,000
```

Verify:

```text id="ikz5is"
SUM = 10,000
```

---

# 39. Largest-Remainder Food Test

Use a case producing fractions.

Example:

```text id="q8d3t2"
Meal units:
A = 1
B = 1
C = 1

Food cost = 100
```

Expected final values must follow the selected deterministic residual policy.

The exact expected residual recipient must be encoded in the test according to the final implementation rule.

---

# 40. Equal Expense Allocation Test

Expense:

```text id="m34g0w"
1,000
```

Members:

```text id="q50t8o"
A
B
C
D
```

Expected:

```text id="b2qx3x"
250
250
250
250
```

---

# 41. Uneven Equal Split Test

Expense:

```text id="ey3n2c"
100
```

Members:

```text id="0t3hcy"
A
B
C
```

Expected results must sum exactly to:

```text id="4d0e7n"
100
```

The residual distribution must follow the deterministic largest-remainder rule.

---

# 42. Weighted Allocation Test

Expense:

```text id="f9xll4"
1,000
```

Weights:

```text id="d7l78j"
A = 2
B = 1
```

Expected:

```text id="znos9i"
A = 666.67
B = 333.33
```

Verify exact total:

```text id="b3e4b6"
1,000.00
```

---

# 43. Fixed Allocation Test

Expense:

```text id="1hy3g3"
1,000
```

Fixed:

```text id="j4dycr"
A = 400
B = 600
```

Expected:

```text id="bn4v7l"
PASS
```

---

# 44. Invalid Fixed Allocation Test

Expense:

```text id="2u0z08"
1,000
```

Fixed:

```text id="bi2zg7"
A = 400
B = 500
```

Expected:

```text id="2o4d2j"
REJECT
```

because:

```text id="3bxy8l"
400 + 500 ≠ 1,000
```

---

# 45. Cross-Period Allocation Test

Create an expense in September and attempt to allocate part of it to an August member.

Expected:

```text id="b5k3z9"
REJECT
```

---

# 46. Cross-Mess Allocation Test

Create expense in Mess X.

Attempt to allocate it to a Mess Y member.

Expected:

```text id="qz9f6u"
REJECT
```

---

# 47. Invalid Payer Test

Create September expense and specify a payer who:

* belongs to another mess
* belongs only to another period
* is not an active eligible member

Each case must be rejected.

---

# 48. Expense Advance Test

Set:

```text id="u6b6ik"
Expense = 1,000
Payer = A
Shared equally among A/B/C/D
```

Expected:

```text id="g1n6an"
A shared cost      = 250
A expense advance  = 1000
A net effect       = -750

B = 250
C = 250
D = 250
```

Period-level net contribution must reconcile correctly.

---

# 49. Double-Payment Test

After A directly pays the vendor 1,000 BDT through an expense, create another 1,000 BDT mess payment.

The system should treat the second payment as a genuine separate payment if entered by the manager.

It must not automatically assume it is duplicate.

The important requirement is that:

```text id="4uxv4c"
expense advance
```

and:

```text id="5t0h4m"
mess payment
```

remain distinct.

---

# 50. Payment Test

Create:

```text id="pc2d6i"
A pays mess 2,000
```

Verify:

```text id="z1p0h9"
payments = 2,000
```

and final balance decreases by 2,000.

---

# 51. Payment Idempotency Test

Submit the same payment request with identical request ID twice.

Expected:

```text id="zyl91v"
one payment
one accounting effect
one operation result
```

---

# 52. Payment Correction Test

Change:

```text id="aq1v1u"
2,000 → 2,500
```

Verify:

* payment changes correctly
* balance changes by 500
* audit records before/after
* no duplicate payment exists

---

# 53. Payment Void Test

Void a 2,000 BDT payment.

Verify:

```text id="qwhs6c"
active payment contribution = 0
historical payment still exists
void metadata exists
audit exists
```

---

# 54. Adjustment Tests

Test:

```text id="51ecp3"
CREDIT 500
DEBIT 500
```

and verify the balance equation.

Test:

```text id="oe0t9v"
negative amount
missing reason
invalid member
closed period
```

all reject appropriately.

---

# 55. Opening Balance Tests

Test:

```text id="g8p70u"
500 DUE
```

and:

```text id="xj1xgi"
500 CREDIT
```

Verify the sign/effect is correct.

---

# 56. Balance Equation Test

Construct:

```text id="u01qf3"
Opening effect      = +500
Food cost           = +3,000
Shared cost         = +1,000
Debit adjustments   = +200
Credit adjustments  = -100
Payments            = -1,000
Expense advances    = -500
```

Expected:

```text id="9q5gt7"
Final balance
= 500 + 3000 + 1000 + 200 - 100 - 1000 - 500
= 3,100
```

Status:

```text id="x2c9p1"
DUE
```

---

# 57. Credit Balance Test

Construct a case where credits exceed charges.

Expected:

```text id="qjyj5n"
final_balance < 0
balance_status = CREDIT
```

The UI/data contract should report the absolute credit amount separately from the signed internal result.

---

# 58. Settled Balance Test

Construct:

```text id="10wh1a"
final_balance = 0
```

Expected:

```text id="wn2gfa"
balance_status = SETTLED
```

---

# 59. Reconciliation Test

For every finalized period verify:

```text id="xauz8n"
SUM member food costs
= total meal cost

SUM expense allocations
= total active allocated expense amounts

SUM member balances
= expected period-level net result
```

All must pass before finalization.

---

# 60. Close-Period Happy Path

Run:

```text id="4hguv2"
open period
→ meals
→ food expense
→ shared expense
→ payments
→ expense advance
→ adjustment
→ calculate
→ integrity check
→ close
```

Verify:

* snapshot created
* snapshot final
* period closed
* audit exists
* all totals reconcile

---

# 61. Close-Period Blocker Test

Introduce:

```text id="8v8dqh"
food expense > 0
meal units = 0
```

Attempt close.

Expected:

```text id="u2b3xe"
CLOSURE_BLOCKED
```

Period remains:

```text id="r4j9r3"
OPEN
```

No final snapshot should be created.

---

# 62. Close-Period Atomicity Test

Force a failure after calculation but before finalization in a controlled test.

Expected:

```text id="egm3yq"
no partially finalized snapshot
period remains open
```

No partial accounting state should survive the failed transaction.

---

# 63. Snapshot Test

Close a period.

Verify:

```text id="yg3b8d"
settlement_snapshot.version = 1
status = FINAL
```

and all member snapshot rows exist.

---

# 64. Reopen Test

After Version 1 finalization:

```text id="2g2q6x"
reopen period
```

Verify:

```text id="c1j8dk"
period = OPEN
Version 1 remains FINAL/historically preserved or becomes SUPERSEDED according to snapshot-state design
```

The key requirement is that Version 1's financial contents are not modified.

---

# 65. Reclose Test

Correct an expense.

Close again.

Verify:

```text id="ylpl3x"
Version 1 = historical
Version 2 = current final
```

and:

```text id="ywrxtm"
Version 2 supersedes Version 1
```

where implemented.

---

# 66. Historical Immutability Test

After Version 2 is created, query Version 1.

Its values must match the original Version 1 result exactly.

No recalculation should rewrite Version 1.

---

# 67. Calculation-Version Test

Finalize Version 1 with:

```text id="yj6l5o"
calculation_version = 1
```

Then use a newer calculation implementation.

Historical Version 1 must still report:

```text id="slb6c9"
calculation_version = 1
```

and retain original values.

---

# 68. Membership History Test

Create:

```text id="ul5fqa"
August:
A B C

September:
A C D
```

Change September membership.

Verify August membership remains unchanged.

---

# 69. Manager History Test

Assign:

```text id="14f1sp"
August = A
September = B
```

Verify:

```text id="q3x3mu"
August manager = A
September manager = B
```

after any subsequent current-manager changes.

---

# 70. Audit Test — Expense

Create an expense.

Verify audit contains:

```text id="n6lx6m"
action = EXPENSE_CREATED
actor = manager
entity = expense
period = correct period
```

Then modify it.

Verify before/after state.

Then void it.

Verify void event.

---

# 71. Audit Test — Payment

Create:

```text id="z8m54j"
2,000 payment
```

Then void.

Verify:

```text id="e16o0g"
PAYMENT_CREATED
PAYMENT_VOIDED
```

both exist.

---

# 72. Audit Immutability Test

Attempt:

```text id="h1onw7"
UPDATE audit_events
```

Expected:

```text id="31v7n9"
DENY
```

Attempt:

```text id="w6ls7p"
DELETE audit_events
```

Expected:

```text id="k4wz5m"
DENY
```

for ordinary application roles.

---

# 73. Audit Atomicity Test

Perform a successful accounting mutation.

Verify corresponding audit event is committed.

Perform a mutation that intentionally fails.

Verify:

```text id="j1k1g5"
no misleading successful audit event
```

remains.

---

# 74. Idempotency Conflict Test

Use the same request ID for:

```text id="u0s55k"
payment = 1000
```

then retry with:

```text id="nrx1la"
payment = 2000
```

Expected:

```text id="8cs1he"
IDEMPOTENCY_CONFLICT
```

No second accounting operation should occur.

---

# 75. Concurrent Payment Test

Two different valid request IDs:

```text id="4y50ve"
payment A = 1,000
payment B = 2,000
```

submitted concurrently.

Expected:

```text id="s7vve6"
both valid payments exist
total = 3,000
```

No lost update.

---

# 76. Concurrent Expense Test

Two managers/devices create different expenses simultaneously.

Expected:

* both persist
* totals reconcile
* no audit event missing
* no duplicate IDs
* no inconsistent settlement

---

# 77. Concurrent Close Test

Two clients attempt:

```text id="ux4zxl"
close_period()
```

simultaneously.

Expected:

```text id="w1hc4l"
one succeeds
one safely fails as already closed/conflict/idempotent
```

There must not be:

```text id="x0w2ga"
two final snapshots both considered current
```

---

# 78. Concurrent Reopen Test

Two clients simultaneously attempt reopen.

Expected:

```text id="l7fd98"
one logical reopen
```

with no contradictory state.

---

# 79. Audit Ordering Test

Perform several events rapidly.

Verify:

* unique event identifiers
* timestamps available
* deterministic ordering where required

The system must not assume timestamps alone uniquely identify order.

---

# 80. Historical Access Security Test

Former member B:

```text id="n9t7ct"
reads own August statement
```

should succeed according to the historical access policy.

B then attempts:

```text id="ra7mxx"
reads C's statement
```

must fail.

B attempts:

```text id="e5g5kg"
modifies August
```

must fail when August is closed.

---

# 81. Cross-Mess IDOR Test

User A has Mess X access.

A manually replaces:

```text id="2hxk5k"
period_id
```

with Mess Y period UUID.

Expected:

```text id="g5g5s9"
DENY
```

Repeat for:

* meals
* expenses
* payments
* statements
* settlements
* audit records

---

# 82. Manager Scope Test

Manager B controls September but not August.

B attempts:

```text id="hfxh3m"
close August
```

Expected:

```text id="l7f9d8"
DENY
```

---

# 83. Closed Snapshot Mutation Test

Attempt direct modification of:

```text id="m4v4g4"
settlement_snapshots
settlement_member_snapshots
```

Expected:

```text id="w6b9v3"
DENY
```

through normal client roles.

---

# 84. Reporting-Function Security Test

For every read function test:

```text id="q1m16t"
authorized user
unauthorized user
wrong mess
wrong period
wrong member
```

where applicable.

---

# 85. Null-Handling Test

Verify:

```text id="2w0qj8"
food cost > 0
meal units = 0
```

returns:

```text id="k7ckza"
meal_rate = NULL
```

not:

```text id="u5w8sf"
0
NaN
Infinity
error string
```

---

# 86. Decimal Precision Test

Use:

```text id="2dh3eq"
100 / 3
```

and other fractional values.

Verify:

* final displayed money is correct
* stored NUMERIC values maintain intended precision
* allocations reconcile
* no binary floating-point corruption occurs

---

# 87. Boundary Amount Tests

Test:

```text id="9t9k5k"
0.01
1.00
999.99
10000.00
large valid amount
invalid oversized amount
```

as permitted by the schema's numeric precision.

---

# 88. Invalid Numeric Input Tests

Reject:

```text id="r5rf5s"
negative expense
negative payment
negative meal quantity
NaN
Infinity
non-numeric values
```

where those values are not valid.

---

# 89. Date Boundary Tests

Test meals/expenses on:

```text id="l3af0n"
period start
period end
one day before
one day after
```

Expected:

```text id="n89g3j"
inside period → accepted
outside period → rejected
```

---

# 90. Timezone Test

Use users with different browser timezones.

Accounting dates must remain based on the period/accounting date rather than accidentally shifting because of browser-local conversion.

---

# 91. Deleted/Deactivated User Test

Deactivate a user who has historical accounting records.

Verify:

* historical records remain consistent
* foreign keys remain valid
* historical settlement remains readable according to policy
* user cannot perform new privileged actions

---

# 92. Profile Privacy Test

A member should not be able to enumerate arbitrary user profiles merely by querying the profile table.

Verify that only authorized profile data is exposed.

---

# 93. Join-Code Security Test

Verify:

* code is unpredictable
* revoked code fails
* regenerated code invalidates prior active code where intended
* code cannot expose arbitrary database IDs
* raw code table is not publicly enumerable

---

# 94. Audit Reason Test

Operations requiring reasons must reject empty/meaningless reasons where the specification requires one.

Examples:

```text id="e7u5hl"
void expense
reopen period
create manual adjustment
```

---

# 95. Performance Test Dataset

Create a larger synthetic period, for example:

```text id="hn2k23"
100 members
30 days
3 meal types/day
9,000+ meal rows
500+ expenses
1,000+ payments/adjustments
```

Exact counts can be adjusted based on the target scale.

Measure:

* meal-grid query
* dashboard query
* settlement calculation
* statement query
* expense pagination
* audit pagination

---

# 96. Performance Targets

V1 should establish practical targets rather than unrealistic guarantees.

Recommended starting targets for normal-sized periods:

```text id="2d6co1"
common read query:      < 500 ms target
common mutation RPC:    < 1000 ms target
settlement calculation: < 2000 ms target
```

These are engineering targets for a healthy test environment, not contractual guarantees.

---

# 97. Query Plan Inspection

For slow queries inspect:

```text id="5p6czm"
EXPLAIN
EXPLAIN ANALYZE
```

Look for:

* sequential scans on large tables
* missing indexes
* repeated nested scans
* expensive policy helpers
* unnecessary joins

Do not optimize solely from intuition.

---

# 98. RLS Performance Test

Run common queries under the actual `authenticated` role/context.

Do not test performance only as service role.

RLS itself contributes query complexity.

---

# 99. Pagination Performance Test

Populate:

```text id="wsj3cl"
10,000+ expense/audit rows
```

and verify cursor pagination remains performant.

---

# 100. Load Test

Where practical, simulate:

```text id="bn7p9g"
10–50 concurrent authenticated operations
```

with realistic workloads.

The objective is to expose:

* locking problems
* race conditions
* deadlocks
* connection exhaustion
* slow RLS policies

rather than to establish enterprise-scale capacity.

---

# 101. Deadlock Testing

Run concurrent operations affecting the same period in different orders.

The transaction design should use a consistent locking order to minimize deadlocks.

For example:

```text id="l1zsy7"
period
→ dependent member/configuration records
→ accounting records
→ snapshot/audit
```

The exact order should be standardized in implementation.

---

# 102. Transaction-Rollback Test

For every multi-step RPC, intentionally make a later validation step fail.

Verify that earlier changes are rolled back.

Example:

```text id="p7o7d1"
expense created
allocation validation fails
```

Expected:

```text id="0m8vfn"
no expense
no allocations
no successful audit event
```

---

# 103. Migration Test

For every migration:

1. apply to a clean database
2. apply all migrations sequentially
3. verify all objects
4. load fixtures
5. run tests

Also test migrations against a representative pre-existing dataset where practical.

---

# 104. Migration Idempotency

A migration should not be accidentally executed twice in production.

Use the normal migration tooling's version tracking.

Do not rely on manually re-running arbitrary SQL in the Supabase dashboard.

---

# 105. Backup/Restore Verification

At an appropriate development/test level:

```text id="e3a78n"
seed database
→ backup/export
→ restore
→ run integrity checks
```

Verify:

* foreign keys
* historical snapshots
* audit events
* accounting totals

remain consistent.

---

# 106. Corruption Detection Test

Manually construct invalid data only in a controlled test database where constraints are temporarily bypassed if necessary.

Run the integrity checker.

It should identify:

* allocation mismatch
* invalid balances
* inconsistent snapshot
* broken relationships

The system should report the problem rather than silently "fixing" it.

---

# 107. Integrity Checker Test

Test known-valid dataset:

```text id="upvps7"
integrity = PASS
```

Then deliberately introduce one known discrepancy.

Expected:

```text id="4yx4px"
integrity = FAIL
blocker identified
affected entity identified
```

---

# 108. Golden Dataset A — Simple

```text id="5jko2x"
Members:
A
B

Meals:
A = 10
B = 10

Food expense:
1,000

Shared expense:
200 equal

Payments:
A = 300
B = 100

No adjustments
No expense advances
No opening balance
```

Expected:

```text id="xd1f87"
meal rate = 50

A:
food = 500
shared = 100
payments = 300
balance = 300

B:
food = 500
shared = 100
payments = 100
balance = 500
```

Total balance:

```text id="2j4j1l"
800
```

This represents remaining member obligations before any vendor-payer advances.

---

# 109. Golden Dataset B — Expense Advance

```text id="m87n2f"
Members:
A
B
C
D

Food units:
A = 50
B = 30
C = 20
D = 0

Food expense:
10,000

Shared internet:
1,000 equal

A pays both vendors

No member payments
```

Expected:

```text id="1c2mcf"
A:
food = 5,000
shared = 250
advance = 11,000
balance = -5,750

B:
food = 3,000
shared = 250
advance = 0
balance = 3,250

C:
food = 2,000
shared = 250
advance = 0
balance = 2,250

D:
food = 0
shared = 250
advance = 0
balance = 250
```

Total:

```text id="fmx3oi"
0
```

This is a critical regression test.

---

# 110. Golden Dataset C — Adjustments

Use:

```text id="x09jwg"
Food cost = 3,000
Shared cost = 500
Debit adjustment = 200
Credit adjustment = 300
Payments = 1,000
```

Expected:

```text id="0zoqso"
3,000 + 500 + 200 - 300 - 1,000
= 2,400
```

---

# 111. Golden Dataset D — Opening Credit

Use:

```text id="4idfo2"
Opening = 500 CREDIT
Food = 2,000
Shared = 500
Payments = 1,000
```

Expected:

```text id="k3g68t"
Opening effect = -500

Final
= -500 + 2000 + 500 - 1000
= 1,000 DUE
```

---

# 112. Golden Dataset E — Zero Meal Cost

```text id="7xpv6l"
Meal units = 100
Meal cost = 0
```

Expected:

```text id="x7xiy8"
meal rate = 0
food cost for all members = 0
```

---

# 113. Golden Dataset F — Zero Meal Units

```text id="bd1f9x"
Meal units = 0
Meal cost = 1,000
```

Expected:

```text id="1zi8ub"
meal rate = NULL
period close = BLOCKED
```

---

# 114. Golden Dataset G — Fractional Allocation

Use expenses designed to force residual allocation.

Example:

```text id="r0e5y3"
Expense = 100
Members = A, B, C
```

Verify deterministic final values.

The exact expected values must match the final selected residual algorithm.

---

# 115. Golden Dataset H — Manager Rotation

```text id="bj63u8"
August → A
September → B
October → C
```

Perform accounting operations in all three.

Verify each manager can only mutate the correct period.

---

# 116. Golden Dataset I — Reopen/Reclose

Sequence:

```text id="m5u4eq"
close Version 1
reopen
change expense
close Version 2
```

Verify:

```text id="s6k1k9"
Version 1 unchanged
Version 2 changed appropriately
current final = Version 2
audit records complete
```

---

# 117. Golden Dataset J — Full Lifecycle

This is the principal end-to-end regression test.

```text id="r2wcz4"
Create Mess
↓
Generate Join Code
↓
B joins
↓
A approves B
↓
Create September period
↓
Assign A manager
↓
Create meal types
↓
Enter meals
↓
Add guest meal
↓
Add food expense
↓
Add shared expense
↓
Record vendor payer
↓
Record member payments
↓
Add adjustment
↓
Calculate statements
↓
Run integrity check
↓
Close
↓
Read final snapshot
↓
Reopen
↓
Correct expense
↓
Recalculate
↓
Close Version 2
↓
Read historical Version 1
↓
Read current Version 2
```

Every state transition and accounting result should be asserted.

---

# 118. Regression Suite

Whenever the schema or accounting engine changes, the following must automatically run:

```text id="v2y7kr"
All schema tests
All RLS tests
All RPC tests
All accounting golden tests
All settlement tests
All audit tests
All historical tests
All idempotency tests
```

A failed golden accounting test blocks release.

---

# 119. Release Gate

Backend release should be considered successful only when:

```text id="k2q6uy"
[ ] Migrations apply cleanly
[ ] Schema verification passes
[ ] RLS tests pass
[ ] Authorization tests pass
[ ] Accounting tests pass
[ ] All reconciliation tests pass
[ ] Audit tests pass
[ ] Closed-period tests pass
[ ] Historical tests pass
[ ] Idempotency tests pass
[ ] Concurrency smoke tests pass
[ ] Performance targets are acceptable
[ ] No critical security finding remains
```

---

# 120. Defect Severity

Suggested classifications:

### Critical

* cross-mess data leak
* member can alter own balance
* closed period can be modified
* final settlement calculation incorrect
* audit history can be manipulated
* duplicate financial transaction possible

### High

* manager scope incorrect
* historical snapshot changes unexpectedly
* concurrency creates invalid accounting
* payment/expense advance double-counting

### Medium

* incorrect non-critical report
* filtering problem
* audit display issue
* pagination defect

### Low

* wording
* cosmetic data formatting
* non-critical performance issue

Critical defects block release.

---

# 121. Test Data Cleanup

Tests must not leave permanent production-like users or messes in the production environment.

The test environment should use isolated:

```text id="f1wzq8"
auth users
database
storage
environment variables
```

where practical.

---

# 122. Security-Test Rule

Never use real user passwords, real production tokens, or production service-role credentials in automated tests.

Use dedicated test secrets.

---

# 123. Final Verification Architecture

```text id="1j74v3"
                 ┌──────────────────┐
                 │ Migration Tests  │
                 └────────┬─────────┘
                          │
                 ┌────────▼─────────┐
                 │ Schema Tests     │
                 └────────┬─────────┘
                          │
             ┌────────────▼────────────┐
             │ Security / RLS Tests    │
             └────────────┬────────────┘
                          │
             ┌────────────▼────────────┐
             │ RPC / Transaction Tests │
             └────────────┬────────────┘
                          │
             ┌────────────▼────────────┐
             │ Accounting Test Suite   │
             └────────────┬────────────┘
                          │
             ┌────────────▼────────────┐
             │ Historical/Audit Tests  │
             └────────────┬────────────┘
                          │
             ┌────────────▼────────────┐
             │ Concurrency Tests       │
             └────────────┬────────────┘
                          │
             ┌────────────▼────────────┐
             │ Performance Tests       │
             └────────────┬────────────┘
                          │
                    RELEASE GATE
```

---

# 124. Final Definition of Backend Correctness

The Mess Manager backend is correct only when all of the following are simultaneously true:

```text id="0mx3xr"
Security:
Unauthorized users cannot access or mutate protected data.

Integrity:
Invalid accounting states cannot be committed.

Accounting:
All balances reconcile mathematically.

History:
Closed-period results remain reproducible.

Audit:
Material changes remain attributable.

Concurrency:
Simultaneous operations do not corrupt state.

Idempotency:
Retries do not duplicate accounting events.

Explainability:
Every final balance can be traced back to source records.

Determinism:
Identical inputs produce identical settlement results.
```

---

# 125. Final Backend Test Principle

The most important automated test is not:

> Does the button work?

It is:

> Can an untrusted client, a buggy client, a duplicate request, a concurrent request, or a later software change cause the accounting history to become incorrect?

The test suite must demonstrate that the answer is **no** under the supported operating conditions.

---

# 126. Implementation Outcome

With this document, the backend design has reached the point where implementation can proceed without inventing additional accounting behavior during coding.

The implementation package should now consist of:

```text
01. Base schema / migrations
02. Cross-table integrity constraints
03. Helper authorization functions
04. RLS policies and grants
05. Accounting/calculation functions
06. Public mutation RPCs
07. Reporting/read functions and views
08. Audit triggers/functions
09. Settlement/period lifecycle functions
10. Seed/demo data
11. Automated database tests
```

The final SQL package should be assembled only after these specifications are kept consistent with one another.
