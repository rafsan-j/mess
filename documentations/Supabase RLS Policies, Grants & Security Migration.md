# Document 13 — Supabase RLS Policies, Grants & Security Migration Specification

**Product:** Mess Manager
**Document:** Supabase RLS Policies, Grants & Security Migration Specification
**Version:** 1.0
**Status:** Implementation Specification
**Depends on:** Schema v2, RLS & Authorization Specification, Calculation Engine & Accounting Specification, Audit/Data Integrity Specification, RPC Specification

---

# 1. Purpose

This document defines the concrete database-security model for Supabase.

It establishes:

* which roles can access which tables
* which rows each user may see
* which operations must be blocked
* which mutations must occur only through RPC
* which functions are exposed to authenticated users
* how current-period manager authority is determined
* how historical access works
* how cross-mess and cross-period data leakage is prevented

The objective is:

> A user must never gain access to or control data merely by knowing a UUID.

---

# 2. Security Layers

Mess Manager uses several security layers simultaneously.

```text id="b0qq7g"
Supabase Auth
      ↓
Database grants
      ↓
RLS policies
      ↓
Security-definer / trusted RPC checks
      ↓
Table constraints & triggers
      ↓
Application authorization
```

The layers are complementary.

Removing one layer must not silently turn the entire application into unrestricted CRUD.

---

# 3. Supabase Roles

The application primarily uses:

```text id="xq5q7t"
anon
authenticated
service_role
```

## 3.1 `anon`

Unauthenticated users.

Expected capabilities:

* authentication-related public flows only
* no access to mess accounting tables
* no access to private application records

---

## 3.2 `authenticated`

Normal logged-in users.

This role is used by ordinary members and managers.

Access is then narrowed by RLS and RPC authorization.

---

## 3.3 `service_role`

Privileged server-side role.

This bypasses RLS and therefore must never be exposed to the browser.

It should only be used from trusted backend/server environments when necessary.

---

# 4. Schema Exposure

Application tables may remain in `public` because Supabase's PostgREST layer commonly operates there, but direct privileges must be intentionally restricted.

A preferred architecture is:

```text id="9y77on"
public
 ├── application tables
 ├── safe read views
 └── approved RPC entry points

private
 ├── helper functions
 ├── internal calculations
 └── privileged implementation details
```

The `private` schema should not be exposed as a normal client API surface.

---

# 5. Default Privilege Strategy

Avoid granting broad privileges such as:

```sql
GRANT ALL ON ALL TABLES IN SCHEMA public
TO authenticated;
```

Instead, privileges must be granted intentionally.

The application should distinguish:

```text id="a2whi4"
SELECT
INSERT
UPDATE
DELETE
EXECUTE
```

and grant only what is genuinely required.

---

# 6. Direct Table-Mutation Strategy

For V1, direct client writes to accounting tables should be minimized.

The preferred model is:

```text id="wvgmcu"
authenticated user
       ↓
public RPC
       ↓
private/helper logic
       ↓
table mutation
```

rather than:

```text id="dq3pkh"
authenticated user
       ↓
direct INSERT/UPDATE/DELETE
```

This is particularly important for:

* expenses
* expense allocations
* payments
* adjustments
* opening balances
* manager assignments
* period transitions
* settlement snapshots

---

# 7. Profile Table Security

## Members should be able to

Read their own profile.

They may update fields explicitly designated as user-editable.

## Members must not

Change:

* their own internal authorization
* mess ownership
* manager status
* period role
* historical accounting identity

---

# 8. Profile Policy

Conceptually:

```sql id="7oh0lv"
USING (id = auth.uid())
```

for self-read.

Self-update must use an explicit column strategy where possible.

Do not allow users to update privileged fields merely because they own their profile row.

---

# 9. Mess Table Security

A normal member may read the messes to which they currently or historically belong according to product policy.

A user must never be able to:

```text id="jslr5q"
UPDATE messes
SET owner_id = some_other_user
```

through direct client access.

Mess mutations should occur through controlled RPCs.

---

# 10. Mess Membership Access

The key authorization relationship is:

```text id="h0w82q"
profile
   ↓
period_members
   ↓
period
   ↓
mess
```

RLS decisions should be derived from this relationship rather than from a user-submitted `mess_id` alone.

---

# 11. Helper — Is Period Member?

Create a private helper conceptually equivalent to:

```sql id="dxxu8c"
private.is_period_member(
    p_period_id uuid,
    p_user_id uuid
)
RETURNS boolean
```

It should return true only when the user has an appropriate membership relationship with the period.

This helper should not accept a client-provided role as evidence.

---

# 12. Helper — Is Active Period Member?

Separate helper:

```sql id="v6j6zc"
private.is_active_period_member(
    p_period_id uuid,
    p_user_id uuid
)
RETURNS boolean
```

This distinguishes historical membership from active membership.

For example:

```text id="4et5zv"
Former member
    ↓
may view historical statement
```

but:

```text id="6v7jzx"
Former member
    ↓
may not edit current period
```

---

# 13. Helper — Is Period Manager?

Create:

```sql id="9n8xxn"
private.is_period_manager(
    p_period_id uuid,
    p_user_id uuid
)
RETURNS boolean
```

This must verify an active/current manager assignment for that exact period.

It must not simply inspect:

```text id="2aq4it"
messes.manager_id
```

because manager authority is period-specific.

---

# 14. Helper — Can Read Period?

A helper may be useful:

```text id="r34g1u"
private.can_read_period(
    p_period_id uuid,
    p_user_id uuid
)
```

Possible authorization:

```text id="q7z5cr"
active member
OR
historical member with permitted history access
OR
authorized manager
```

The precise historical-access rule should remain explicit rather than being inferred from current membership.

---

# 15. Helper — Can Manage Period?

```text id="0kz5sg"
private.can_manage_period(
    p_period_id uuid,
    p_user_id uuid
)
```

Expected result:

```text id="v2p4pj"
true
```

only for authorized current period managers or explicitly permitted higher-level administrators.

---

# 16. Function Security-Definer Hardening

Every security-definer helper/function should use a fixed search path.

Recommended pattern:

```sql id="gl9w2m"
SET search_path = public, private
```

and should schema-qualify sensitive object references.

Never leave security-definer search-path resolution ambiguous.

---

# 17. Profiles RLS

### SELECT

```text id="br9g6d"
user can read own profile
```

Potential manager read access to other users should occur only through appropriate membership/member views rather than unrestricted profile access.

### UPDATE

Own permitted profile fields only.

### INSERT

Prefer server-side/profile trigger creation rather than arbitrary client profile creation.

### DELETE

Not permitted through normal client access.

---

# 18. Mess Join Code Security

Join codes are sensitive because knowledge of a valid code can grant a user the ability to request membership.

Therefore:

* users may submit a join code to the controlled `request_to_join_mess()` RPC
* raw join-code table access should be restricted
* members should not receive all historical codes
* old/revoked codes should not be exposed unnecessarily

The system should avoid making join codes publicly queryable.

---

# 19. Join Request Security

## Requester

May view their own request.

## Manager

May view pending requests for the relevant mess/current workflow.

## Ordinary members

Must not view other users' pending join requests unless explicitly required.

## Mutation

Approval/rejection should occur through RPC only.

---

# 20. Period Security

A user may read period data only where authorized.

The policy must not be:

```text
period.id = requested_period_id
```

alone.

It must resolve whether:

```text id="6w2vjo"
auth.uid()
```

belongs to that period/mess with the appropriate historical or managerial relationship.

---

# 21. Period Mutation Security

Direct client `UPDATE periods` should normally be denied.

State transitions must use:

```text id="e91n3x"
create_period()
open_period()
close_period()
reopen_period()
```

This prevents a client from doing:

```sql id="f2p0b9"
UPDATE periods
SET status = 'CLOSED';
```

without performing all closure checks.

---

# 22. Period Members

## SELECT

A period member may see the membership records they are authorized to see.

A manager may see all members in the relevant period.

## INSERT/UPDATE/DELETE

Normally manager-only through RPC.

Ordinary users must not:

* add themselves
* remove others
* change another member's status
* make themselves manager

---

# 23. Manager Assignments

Direct client mutation should be denied.

Manager changes must use:

```text id="nm0wj5"
assign_manager()
transfer_manager()
```

The functions must validate:

* exact period
* caller authority
* target active membership
* current manager state

---

# 24. Meal Type Security

Meal types are period-specific.

## SELECT

Authorized period members may read meal types.

## INSERT/UPDATE

Manager only.

## DELETE

Prefer retirement/deactivation rather than destructive deletion once referenced by meals.

---

# 25. Meals Table Security

### SELECT

Members may read:

* their own meal records

Managers may read:

* all meal records in their managed period.

Whether a member can view all members' meal records should be a deliberate product decision. The default secure policy is **own records only**.

### INSERT/UPDATE/DELETE

Ordinary members:

```text id="qjw7dz"
DENY
```

Managers:

```text id="c1u3k8"
perform via save_meal_entries() / controlled RPC
```

---

# 26. Guest Meals

The same model applies.

### Member

May view guest meals associated with their own hosting account where appropriate.

### Manager

May view all guest meals in the managed period.

### Mutation

Manager/RPC only.

Guest meal data must not allow a member to manufacture arbitrary accounting charges.

---

# 27. Expense Categories

Expense categories are reference/configuration data.

Members may read categories needed for display where appropriate.

Normal members should not mutate categories.

Category management should be manager-only or system-controlled.

---

# 28. Expenses

Direct client writes should normally be denied.

### SELECT

Manager:

```text id="i7j1kx"
all expenses for managed period
```

Member:

```text id="4p3d7v"
only information product policy allows them to see
```

At minimum, members may need to see expenses contributing to their own statement, but the precise visibility of payer names, descriptions, or receipts should be intentional.

### INSERT/UPDATE/DELETE

Manager through RPC only.

---

# 29. Expense Allocations

Expense allocations must not be directly editable by ordinary clients.

They should be controlled by the expense RPC because allocation validity depends on:

* expense
* period
* members
* amount
* allocation method

Direct access creates a high risk of:

```text id="1ftr5i"
expense = 1000
allocations = 1200
```

or cross-period allocations.

---

# 30. Payments

### SELECT

Members may view their own payments.

Managers may view all payments for their period.

### INSERT/UPDATE/DELETE

Manager through RPC.

A member should not be able to manufacture a payment that reduces their own amount due.

---

# 31. Adjustments

### SELECT

A member may view their own adjustments.

Managers may view all period adjustments.

### Mutation

Manager only via RPC.

This prevents a member from inserting:

```text id="n8v2xv"
CREDIT 100000
```

to erase their own balance.

---

# 32. Opening Balances

Opening balances require strong restrictions because they directly affect settlement.

### SELECT

Member may view their own opening balance.

Manager may view all period opening balances.

### Mutation

Manager only through RPC.

No ordinary client insert/update/delete.

---

# 33. Settlement Snapshots

Finalized settlement snapshots should be effectively immutable.

### SELECT

Authorized historical users may read their permitted snapshot.

Managers may read the full period snapshot.

### INSERT/UPDATE/DELETE

Never through ordinary client CRUD.

Snapshot creation must happen through the settlement/close workflow.

---

# 34. Audit Events

### SELECT

Manager:

```text id="ex49hr"
authorized audit history
```

Member:

```text id="gldo6s"
restricted/no raw audit access
```

### INSERT

Not directly by client.

### UPDATE

Denied.

### DELETE

Denied.

Audit creation occurs through trusted RPCs/triggers.

---

# 35. Historical Access Rules

Historical access should be explicit.

For a closed period:

### Former member

May see their own statement/history.

### Current member

May see permitted historical information.

### Current manager

May see authorized period details.

### Former manager

May not automatically obtain management privileges.

This distinction is critical.

---

# 36. Example Historical Authorization

Suppose:

```text id="4v0l26"
August:
A manager
B member

September:
C manager
B member
```

In September:

A must not be treated as September manager merely because:

```text id="ugcc7g"
A managed August
```

Likewise:

B may retain access to August and September personal history according to membership.

---

# 37. Cross-Mess Isolation

Suppose:

```text id="iuj5kn"
User A → Mess X
User A → Mess Y
```

The user may legitimately belong to multiple messes.

Therefore RLS must distinguish:

```text id="6g82in"
same user
```

from:

```text id="7cgzvs"
same mess
```

Access to Mess X must never accidentally expose Mess Y.

Every policy must resolve the target row's mess context.

---

# 38. UUID Tampering Test

A user must not be able to do:

```text id="4u9gfy"
SELECT *
FROM expenses
WHERE id = 'some-other-mess-expense-uuid';
```

and receive that record.

Likewise, a crafted RPC request containing somebody else's IDs must fail.

---

# 39. IDOR Protection

The security model explicitly protects against Insecure Direct Object Reference vulnerabilities.

Examples:

```text id="0p0t8v"
GET /payment/B's-payment-id
```

or:

```text id="gjqb3e"
RPC(member_id = another_member)
```

must not grant unauthorized access.

Authorization must derive from relationships, not from obscurity of UUIDs.

---

# 40. Table Grant Strategy

A recommended starting point is:

### `authenticated`

Grant limited `SELECT` on safe/readable tables where RLS controls row access.

### Mutating tables

Restrict direct `INSERT/UPDATE/DELETE`.

### RPCs

Grant:

```sql
EXECUTE
```

only on intended public functions.

The exact grants should be generated from the final migration rather than manually applied in the dashboard.

---

# 41. Example Grant Pattern

Conceptually:

```sql id="7er9a7"
REVOKE ALL
ON public.expenses
FROM authenticated;

GRANT SELECT
ON public.expenses
TO authenticated;
```

Then RLS determines which rows are visible.

For sensitive mutation operations:

```text id="hfe1u2"
No INSERT/UPDATE/DELETE grant
+
Public create_expense() RPC
```

This makes unauthorized direct mutation structurally harder.

---

# 42. Read Views

Some user interfaces should use safe views rather than exposing raw tables.

Examples:

```text id="p1l0xs"
member_statement_view
period_summary_view
member_history_view
manager_dashboard_view
```

These views can expose only the columns required by the UI.

Sensitive fields can remain hidden.

---

# 43. View Security

Views must not accidentally bypass intended row-level protections.

The implementation must deliberately choose appropriate:

* security-invoker behavior
* RLS interaction
* grants
* exposed columns

Do not assume that putting a table behind a view automatically creates secure authorization.

---

# 44. Dashboard Security

Manager dashboard data must be scoped to periods the caller actually manages.

A manager from Mess A must not query a dashboard view and receive Mess B because the query accepted arbitrary `mess_id`.

The view/function must derive scope from:

```text id="t8j3z5"
auth.uid()
```

plus valid manager membership/assignment.

---

# 45. Member Statement Security

A member statement function should accept:

```text id="v7v5a5"
period_id
```

and preferably derive the member from:

```text id="r1v5m8"
auth.uid()
```

for the personal statement endpoint.

This is safer than:

```text id="1ofxzu"
get_statement(period_id, arbitrary_member_id)
```

for member-facing clients.

A separate manager-authorized function may accept another member ID after checking manager authority.

---

# 46. Recommended Statement Functions

## Personal

```text id="5fiqvi"
get_my_statement(period_id)
```

Member ID is derived from authenticated identity.

## Manager

```text id="rvpi5f"
get_member_statement(period_id, period_member_id)
```

Requires manager authorization.

This minimizes accidental IDOR.

---

# 47. Personal Meal Access

Similarly:

```text id="dqqy2s"
get_my_meals(period_id)
```

is preferable to allowing a member to specify an arbitrary period-member ID.

Manager meal views can use the full period context after authorization.

---

# 48. Personal Payment Access

Preferred:

```text id="m2wuv2"
get_my_payments(period_id)
```

rather than:

```text id="dcpu4p"
get_payments(period_id, member_id)
```

for normal member clients.

---

# 49. Personal Adjustment Access

Same pattern:

```text id="8u6ven"
get_my_adjustments(period_id)
```

The authenticated user's identity defines the target member.

---

# 50. RPC Authorization Matrix

| Operation              | Member | Manager |
| ---------------------- | -----: | ------: |
| Create mess            |    Yes |     Yes |
| Create join code       |     No |     Yes |
| Regenerate join code   |     No |     Yes |
| Request to join        |    Yes |     Yes |
| Approve request        |     No |     Yes |
| Reject request         |     No |     Yes |
| Create period          |     No |     Yes |
| Open period            |     No |     Yes |
| Assign manager         |     No |     Yes |
| Transfer manager       |     No |     Yes |
| End another member     |     No |     Yes |
| Save meals             |     No |     Yes |
| Create guest meal      |     No |     Yes |
| Create expense         |     No |     Yes |
| Update expense         |     No |     Yes |
| Void expense           |     No |     Yes |
| Record mess payment    |     No |     Yes |
| Void payment           |     No |     Yes |
| Create adjustment      |     No |     Yes |
| Void adjustment        |     No |     Yes |
| Create opening balance |     No |     Yes |
| Close period           |     No |     Yes |
| Reopen period          |     No |     Yes |

The manager column still requires **manager authority for the specific period**.

---

# 51. Member Read Matrix

| Resource          |         Member's Own | Other Members | Manager |
| ----------------- | -------------------: | ------------: | ------: |
| Profile           |                  Yes |       Limited | Limited |
| Period membership |                  Yes |       Limited |     Yes |
| Meals             |                  Yes | No by default |     Yes |
| Guest meals       |     Own host context |            No |     Yes |
| Expenses          | Relevant/shared view |       Limited |     Yes |
| Payments          |                  Yes |            No |     Yes |
| Adjustments       |                  Yes |            No |     Yes |
| Opening balance   |                  Yes |            No |     Yes |
| Settlement        |                  Yes |            No |     Yes |
| Audit log         |        No raw access |            No |     Yes |
| Historical period |          Own history |            No |     Yes |

The product may choose to expose more shared information, but the secure default is least privilege.

---

# 52. Closed-Period RLS

RLS should not be the only protection against closed-period mutation.

A closed-period mutation must be rejected by:

```text id="l0mt96"
RPC/trigger/business-rule validation
```

RLS can additionally deny direct writes.

This produces defense in depth.

---

# 53. RLS Does Not Replace Business Integrity

RLS answers:

> May this user access this row?

It does not fully answer:

> Is this expense allocation financially valid?

Therefore:

```text id="1m2oyi"
RLS
+
constraints
+
triggers
+
RPC validation
```

are all necessary.

---

# 54. Policy Design: Avoid Giant `FOR ALL`

Avoid policies like:

```sql id="2hw8q6"
CREATE POLICY "users can do everything"
ON expenses
FOR ALL
...
```

because this makes future auditing and security reasoning difficult.

Prefer explicit policies:

```text id="5l6tz1"
SELECT policy
INSERT policy
UPDATE policy
DELETE policy
```

and only add mutation policies where direct mutation is intentionally supported.

---

# 55. Direct DELETE Policy

For accounting tables:

```text id="a6jvng"
DELETE = DENY
```

for ordinary authenticated clients.

Voiding should happen through RPC.

This includes:

* expenses
* payments
* adjustments
* opening balances
* meals where deletion would destroy evidence

---

# 56. Direct INSERT Policy

For high-risk accounting tables, preferably:

```text id="cz3cs9"
INSERT = DENY
```

through direct PostgREST access.

The public RPC owns the insertion workflow.

---

# 57. Direct UPDATE Policy

Similarly:

```text id="0vtqbl"
UPDATE = DENY
```

for high-risk accounting tables.

Controlled functions handle changes.

---

# 58. Exception — Low-Risk Profile Updates

A narrowly scoped direct update may be acceptable for user-owned profile fields such as:

* display name
* avatar reference
* timezone if supported

But only explicitly permitted columns should be writable.

Do not use unrestricted:

```sql
GRANT UPDATE ON profiles TO authenticated;
```

without column-level consideration.

---

# 59. Anonymous Access

No normal application table should be readable through `anon`.

Public authentication flows should not reveal:

* mess lists
* member names
* expenses
* balances
* join request details
* audit records

---

# 60. Search and Leakage

If the application later adds search:

A member searching for:

```text
"A"
```

must not obtain users merely because their profiles exist.

Search results must be scoped to authorized mess/period relationships.

---

# 61. Join-Code Leakage

A valid join code should not be embedded in:

* public URLs where avoidable
* analytics events
* error messages
* audit events as raw plaintext

Audit records may retain a safe representation such as code ID or masked value rather than exposing the complete secret.

---

# 62. Secrets in Logs

Do not log:

* Supabase service-role key
* authentication tokens
* session secrets
* passwords
* raw sensitive join codes

Database logs and application logs must follow the same rule.

---

# 63. Function Exposure

The final migration must explicitly revoke or restrict execution of private helper functions.

For example:

```text id="6bnj7m"
private.assert_period_manager()
```

must not become a public RPC merely because the schema allows execution.

Only public application commands should be exposed.

---

# 64. Public RPC Grants

Recommended model:

```sql id="w6cbdv"
GRANT EXECUTE
ON FUNCTION public.request_to_join_mess(...)
TO authenticated;
```

while:

```text id="k90y24"
private.calculate_food_costs(...)
```

remains inaccessible to the client.

---

# 65. Search Path and Function Overloading

Avoid unnecessary function overloading where authorization semantics could become ambiguous.

Prefer unique signatures for important public RPCs.

This simplifies:

* grants
* client invocation
* migrations
* security review

---

# 66. Mutable Function Search Paths

Do not allow callers to pass schema names or table names into security-definer functions.

Functions should know exactly which objects they operate on.

---

# 67. RLS Helper Performance

Policy helpers may be called for many rows.

Therefore helpers should:

* use indexed columns
* avoid unnecessarily expensive nested calculations
* avoid repeated full-period scans
* use stable/simple joins
* be tested on realistic data volumes

Security must not be implemented through pathological per-row queries.

---

# 68. Policy Index Requirements

Indexes should support common authorization paths.

Important candidates include:

```text id="x4z5h8"
period_members(user_id, period_id)
period_members(period_id, user_id)

manager_assignments(period_id, user_id)

periods(mess_id, status)

mess_join_requests(mess_id, status)

meals(period_member_id, meal_date)
```

The exact final index set belongs in the schema/migration.

---

# 69. RLS Test Philosophy

Security tests must test negative cases first.

For every operation:

```text id="c7u7o5"
What happens if the caller changes the UUID?
```

The answer must be:

```text id="qokz0v"
Access denied
```

---

# 70. Mandatory RLS Tests

## Test 1 — Member reads own meal

Expected:

```text id="3q4h3j"
PASS
```

## Test 2 — Member reads another member's meal

Expected:

```text id="xgqk7z"
DENY
```

## Test 3 — Member creates meal

Expected:

```text id="3m0ng7"
DENY
```

## Test 4 — Manager reads period meals

Expected:

```text id="dtfdqv"
PASS
```

## Test 5 — Manager from Mess A reads Mess B

Expected:

```text id="3lq4ay"
DENY
```

---

# 71. Cross-Period Tests

A manager of September should not use September authorization to mutate August merely because the same mess is involved.

Expected:

```text id="3jfb5n"
attempt to modify unauthorized period
→ DENY
```

Even when:

```text id="y0bo3f"
same mess
same user
different period
```

---

# 72. Former Manager Test

Scenario:

```text id="3nks7k"
A = August manager
B = September manager
```

A attempts:

```text id="rp6m8c"
update September expense
```

Expected:

```text id="hs5xy0"
DENY
```

---

# 73. Former Member Test

A member leaves the mess.

They attempt:

```text id="l3qfx0"
create September expense
```

Expected:

```text id="s04wbo"
DENY
```

They may still read their own historical statement according to history rules.

---

# 74. Self-Promotion Test

Member attempts to call:

```text id="0m3pmj"
assign_manager(period, self)
```

Expected:

```text id="x6ol6y"
DENY
```

unless the explicit manager workflow authorizes it, which V1 should not.

---

# 75. Self-Approval Test

User creates a join request to a mess.

User then attempts:

```text id="25mb6j"
approve_join_request(their_own_request)
```

Expected:

```text id="hyy2eu"
DENY
```

---

# 76. Direct Accounting Insert Test

Authenticated member attempts direct:

```sql id="q6h3r1"
INSERT INTO payments ...
```

Expected:

```text id="49c4e2"
DENY
```

Manager direct insert should also be denied if the intended architecture requires the RPC.

---

# 77. RPC ID-Tampering Test

User calls:

```text id="r1c0cc"
get_member_statement(
    period_id = authorized,
    period_member_id = victim
)
```

Expected for ordinary member:

```text id="d8j3kz"
DENY
```

Manager may pass only if they manage that exact period.

---

# 78. Closed-Period Test

Manager calls:

```text id="x4m8z7"
update_expense()
```

against a closed period.

Expected:

```text id="b3p8l4"
PERIOD_CLOSED
```

not merely an empty RLS result.

The distinction is important for UX and diagnostics.

---

# 79. RLS Policy Recursion

Policies must be designed carefully to avoid recursion.

For example:

```text id="7d8l9m"
period_members policy
    ↓
queries period_members
    ↓
same policy
    ↓
recursive evaluation
```

Where helper logic would cause recursion, move the authorization query into a carefully designed security-definer helper with controlled access.

---

# 80. Security-Definer Helper Safety

A security-definer helper must not become a privilege escalation mechanism.

Therefore:

* it should expose a boolean or tightly constrained result
* it should not return arbitrary rows
* it should not accept arbitrary SQL conditions
* its caller authorization semantics should be explicit

---

# 81. Trigger Security

Audit and integrity triggers execute inside the transaction.

They must not silently bypass intended protections in a way that creates a public escalation path.

The trigger's purpose must remain narrow.

---

# 82. Service-Role Operations

Some server-side workflows may need service-role access for:

* scheduled maintenance
* administrative recovery
* background analytics
* system notifications in future

These operations must not be exposed through user-controlled request parameters.

A client request such as:

```text id="m0n2vx"
role = service_role
```

must have no effect.

---

# 83. Environment Security

The frontend may safely contain:

```text id="x34j7a"
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
```

The frontend must never contain:

```text id="4l4pv6"
SUPABASE_SERVICE_ROLE_KEY
```

The exact environment-variable names may differ by framework, but the security principle is fixed.

---

# 84. Audit of Security Events

Security-relevant business actions should also be audited:

* join approval/rejection
* manager transfer
* period close
* period reopen
* major accounting corrections
* join-code regeneration

Routine SELECT operations generally do not need audit events unless there is a specific security requirement.

---

# 85. Failed Authorization Logging

The application should avoid generating enormous audit-table noise from ordinary unauthorized API attempts.

However, repeated suspicious failures may be captured in security/operational logs at the application/infrastructure layer.

The accounting audit log should remain focused on meaningful business state.

---

# 86. Data Minimization

RLS protects access, but the schema should also minimize exposure.

Do not return fields simply because the table contains them.

For member-facing views, expose the minimum information required.

Example:

A member may need:

```text id="8n6cn2"
expense description
expense amount
their allocation
```

but may not need:

```text id="qqb8xk"
internal database metadata
audit payload
service identifiers
```

unless product requirements explicitly justify them.

---

# 87. Production Security Checklist

Before deployment:

```text id="t7dr2s"
[ ] RLS enabled on every application table
[ ] anon has no unintended table access
[ ] authenticated has only intended grants
[ ] accounting tables have controlled mutation paths
[ ] security-definer functions hardened
[ ] private functions not publicly executable
[ ] service-role key server-only
[ ] historical access tested
[ ] cross-mess isolation tested
[ ] cross-period isolation tested
[ ] ID tampering tested
[ ] manager authority tested
[ ] former manager tested
[ ] former member tested
[ ] self-approval blocked
[ ] self-promotion blocked
[ ] closed-period mutation blocked
[ ] direct accounting CRUD blocked where required
[ ] audit events protected
[ ] policy performance tested
```

---

# 88. Final Security Architecture

The intended final architecture is:

```text id="ydm4vi"
                 ┌─────────────────────┐
                 │    Supabase Auth    │
                 └──────────┬──────────┘
                            │
                       auth.uid()
                            │
                 ┌──────────▼──────────┐
                 │   RLS / Grants      │
                 └──────────┬──────────┘
                            │
                ┌───────────▼───────────┐
                │ Public RPC Commands   │
                └───────────┬───────────┘
                            │
               ┌────────────▼────────────┐
               │ Authorization Helpers   │
               ├─────────────────────────┤
               │ Period Manager Check     │
               │ Period Member Check      │
               │ Period State Check       │
               │ Same-Mess Check          │
               │ Same-Period Check        │
               └────────────┬────────────┘
                            │
                 ┌──────────▼──────────┐
                 │ PostgreSQL Mutation │
                 └──────────┬──────────┘
                            │
             ┌──────────────▼──────────────┐
             │ Constraints / Triggers      │
             ├─────────────────────────────┤
             │ Accounting Integrity        │
             │ Closed-Period Protection    │
             │ Audit                       │
             └──────────────┬──────────────┘
                            │
                 ┌──────────▼──────────┐
                 │ Trusted Accounting  │
                 │ / Settlement State  │
                 └─────────────────────┘
```

---

# 89. Final Security Rules

The implementation must preserve these rules:

```text id="g2wrkm"
1. Authentication identifies the user.
2. RLS determines which rows are visible.
3. Grants determine which operations are structurally available.
4. RPCs determine whether business operations are valid.
5. Database constraints prevent impossible data.
6. Audit records preserve accountability.
7. Historical period authority is independent of current manager status.
8. A UUID is never authorization.
9. A hidden UI button is never authorization.
10. The browser is never trusted with accounting authority.
```

---

# 90. Implementation Outcome

After implementing this migration, the security model should provide:

```text id="72rl8z"
Member
  → sees authorized personal/shared data
  → cannot edit accounting
  → cannot promote self
  → cannot approve self
  → cannot access another mess

Manager
  → manages only authorized periods
  → performs mutations through controlled commands
  → cannot bypass closed-period rules
  → cannot rewrite historical authority

Database
  → enforces relationships
  → enforces accounting invariants
  → preserves audit history
  → rejects unauthorized operations
```

This document should be implemented together with the RPC migration rather than as an independent dashboard configuration exercise. The policies, grants, helper functions, and public RPC signatures must remain version-controlled in the repository.
