# Mess Manager

## Supabase RLS & Authorization Specification

**Document version:** 1.0
**Product version:** V1
**Database:** PostgreSQL via Supabase
**Authentication:** Supabase Auth
**Authorization model:** PostgreSQL Row Level Security + controlled database functions
**Primary roles:** `anon`, `authenticated`, application-level `member`, application-level `manager`

---

# 1. Purpose

This document defines exactly who can:

* read data
* create data
* update data
* delete/void data
* execute privileged workflows

within Mess Manager.

The objective is not merely to hide management controls from members in the frontend.

The objective is:

> **A member must remain unable to perform a manager-only operation even when directly calling Supabase's Data API with manipulated IDs and payloads.**

Supabase describes RLS as a database-level authorization mechanism and explicitly recommends enabling RLS on exposed tables while separately controlling PostgreSQL grants. Policies should be written for the specific operation being protected rather than relying on broad `FOR ALL` policies.

---

# 2. Security Model

The application has two different concepts that must not be confused.

## PostgreSQL request role

Supabase provides:

```text
anon
authenticated
```

depending on whether the request is authenticated. `auth.uid()` identifies the authenticated user and is `NULL` when no authenticated user is present.

## Application role

Mess Manager derives:

```text
MEMBER
MANAGER
```

from database relationships.

A user does not become a manager because their browser says:

```text
role = manager
```

The authoritative question is:

```text
Does this authenticated user have a current manager assignment
for this particular period?
```

---

# 3. Security Boundary

The security boundary is:

```text id="q9m7ax"
Browser
   ↓
Supabase Auth
   ↓
authenticated request
   ↓
PostgreSQL grants
   ↓
RLS
   ↓
business-rule functions
   ↓
database
```

Every relevant layer must cooperate.

Supabase specifically notes that grants and policies are both required: RLS policies do not remove table privileges that have already been granted. `service_role` also bypasses RLS and must therefore remain server-side.

---

# 4. Core Authorization Invariants

The following are non-negotiable:

```text
AUTH-INV-01
Unauthenticated users cannot access private mess data.

AUTH-INV-02
A user can only access messes in which they have an
authorized relationship.

AUTH-INV-03
A member can only access permitted personal data.

AUTH-INV-04
A member cannot perform manager-only mutations.

AUTH-INV-05
A manager can only manage the mess/period for which
they currently hold management authority.

AUTH-INV-06
A manager from Mess A cannot access Mess B.

AUTH-INV-07
A former manager cannot continue using manager-only
permissions after management has been transferred.

AUTH-INV-08
Closed-period financial data cannot be mutated through
ordinary application operations.

AUTH-INV-09
Audit records cannot be altered by ordinary users.

AUTH-INV-10
Changing URL/database IDs cannot bypass any of the above.
```

---

# 5. Access Context

Authorization should conceptually resolve:

```text id="6z2q0l"
auth.uid()
     ↓
user relationship
     ↓
mess
     ↓
period
     ↓
period membership
     ↓
manager assignment
     ↓
requested operation
```

The implementation should centralize these relationships into private helper functions where doing so makes RLS safer and easier to maintain.

---

# 6. Recommended Security Helper Schema

The project already defines:

```text
private
```

for internal database helpers.

Security-definer functions should remain outside exposed API schemas and should use a pinned empty `search_path`, with all relations schema-qualified. Supabase explicitly recommends this pattern for security-definer functions and warns that exposed security-definer functions can execute with their creator's privileges.

---

# 7. Core RLS Helper Functions

The following logical helpers are recommended:

```text
private.is_authenticated()
private.is_mess_member(mess_id uuid)
private.is_period_member(period_id uuid)
private.is_period_manager(period_id uuid)
private.can_view_member(period_member_id uuid)
private.can_manage_period(period_id uuid)
private.can_modify_period(period_id uuid)
```

The exact signatures may vary.

They must not become arbitrary privilege-escalation functions.

---

# 8. Authentication Helper

Conceptually:

```sql id="o0gjr3"
private.is_authenticated()
```

returns true only when:

```text
auth.uid() IS NOT NULL
```

Supabase documents that `auth.uid()` returns `NULL` for unauthenticated requests.

---

# 9. Mess Membership Helper

Conceptually:

```text id="2jx8ki"
private.is_mess_member(mess_id)
```

returns true when the authenticated user has an appropriate current relationship with that mess.

The function must define whether:

* active members only
* historical members
* pending users

are considered members.

Recommended V1:

> Only active or historically authorized relationships count as member access; pending applicants do not gain private mess access.

---

# 10. Period Membership Helper

Conceptually:

```text id="zcs5g4"
private.is_period_member(period_id)
```

returns true if:

```text auth.uid()
→ period_members
→ period_id
```

matches an appropriate membership.

For current operational access, membership must normally be active.

---

# 11. Manager Helper

Conceptually:

```text id="vv9x9n"
private.is_period_manager(period_id)
```

returns true if the current user has an active manager assignment for that period.

Do not derive manager status from:

```text profiles
```

or:

```text period_members.membership_status
```

alone.

---

# 12. Manager Authorization

A manager is effectively:

```text id="0h1nwa"
authenticated user
+
valid period membership
+
active manager assignment
```

This is contextual authorization.

The same user may therefore be:

```text September → manager
October → member
November → manager
```

without changing their global account role.

---

# 13. Why Helper Functions Are Useful

Complex RLS expressions can become difficult to read and can accidentally create recursive policy dependencies.

Supabase specifically documents security-definer helper functions as a way to safely inspect membership tables and avoid RLS recursion when necessary.

The helpers should therefore be:

* private
* narrowly scoped
* security-reviewed
* explicitly permissioned

---

# 14. Function Security Requirements

For any security-definer helper:

```sql id="9ud0vi"
security definer
set search_path = ''
```

and all referenced relations should be schema-qualified, for example:

```text
public.period_members
public.manager_assignments
```

Supabase recommends this exact style because an uncontrolled search path can allow object-name manipulation under elevated privileges.

---

# 15. Function EXECUTE Permissions

Functions do not inherit table RLS.

RLS does not protect a function's execution.

Function execution privileges must therefore be explicitly controlled. Supabase recommends revoking execution from broadly applicable roles and granting it only to intended callers where a function needs protection.

---

# 16. `anon` Access

Default V1 policy:

```text
anon:
No private application table access.
```

The application may have public marketing/about content outside the private accounting model.

The mess-management schema should not be publicly queryable.

---

# 17. `authenticated` Access

Authenticated users may access records only according to:

* membership
* period context
* personal ownership
* manager status

Authentication alone grants no mess-level privileges.

---

# 18. Profiles — Authorization

## SELECT

User can read their own profile.

Managers may not automatically read all profile fields.

For manager-facing member lists, the application should expose only the necessary profile information.

Recommended:

```text
display_name
avatar_url
```

not unnecessary account metadata.

---

# 19. Profiles — INSERT

A user may create their own profile row if application architecture requires client-side profile creation.

Constraint:

```text
profiles.id = auth.uid()
```

The database must reject creation of a profile belonging to another user.

---

# 20. Profiles — UPDATE

Users may update their own permitted profile fields.

The update must enforce:

```text existing row belongs to auth.uid()
AND
new row still belongs to auth.uid()
```

Supabase specifically notes that UPDATE policies should use `USING` for the existing row and `WITH CHECK` for the resulting row.

---

# 21. Profiles — DELETE

V1 should not expose direct client-side profile deletion.

Account deletion should be a controlled workflow because historical records depend on durable identity.

---

# 22. Messes — SELECT

An authenticated user may read a mess if they have an authorized relationship with it.

Recommended:

```text
active member
OR
authorized historical member
OR
current manager
```

Pending join-request users should not receive unrestricted mess information.

---

# 23. Messes — INSERT

Authenticated user may create a mess through the approved creation workflow.

The created-by identity must be:

```text
auth.uid()
```

not a user ID supplied independently by the client.

---

# 24. Messes — UPDATE

Only the current authorized manager for the relevant active context should change operational mess settings.

However, some settings may be mess-level rather than period-level.

The final policy should distinguish:

```text
identity settings
vs
historical accounting settings
```

Changing the mess name should not rewrite historical settlement semantics.

---

# 25. Messes — DELETE

No ordinary client delete.

Use:

```text
ARCHIVED
```

instead.

Hard deletion of a mess containing financial history should be an administrative recovery operation, not a normal UI action.

---

# 26. Mess Join Codes — SELECT

Manager can read the current join code for their mess.

Ordinary members should generally not have the ability to retrieve the code through raw table access merely because they are members.

The UI can choose whether members see the code, but V1 recommendation is:

> Join code management is manager-only.

---

# 27. Join Code — INSERT

Only an authorized manager/system workflow can generate a join code.

The client should not be allowed to insert arbitrary:

```text
mess_id
code
is_active
created_by
```

rows.

---

# 28. Join Code — UPDATE

Do not allow arbitrary code edits.

Instead use a controlled:

```text regenerate_join_code()
```

workflow.

This makes:

```text old code revoked
+
new code created
```

atomic.

---

# 29. Join Code — DELETE

No direct delete.

Revocation is represented through:

```text is_active = false
revoked_at = timestamp
```

---

# 30. Join Requests — SELECT

### Requester

Can read their own requests.

### Manager

Can read pending/historical requests for their mess.

### Other members

Cannot read other users' join requests.

---

# 31. Join Requests — INSERT

Authenticated user can create a pending request when:

* join code is valid
* mess is active
* user is not already a member
* no pending duplicate exists

Because join-code validation and membership creation are related, this should ideally be exposed through a controlled function:

```text
request_to_join_mess(code)
```

rather than broad direct table insert access.

---

# 32. Join Requests — UPDATE

Normal members cannot update approval status.

Manager approval/rejection should use controlled functions:

```text
approve_join_request(request_id)
reject_join_request(request_id)
```

This prevents a malicious member from sending:

```json
{
  "status": "APPROVED"
}
```

directly.

---

# 33. Join Requests — DELETE

No direct deletion.

Historical join attempts should remain.

---

# 34. Periods — SELECT

Users can read periods belonging to messes for which they have authorized access.

### Active member

Can read relevant current period information.

### Historical member

Can read appropriate historical information.

### Manager

Can read full period information.

### Non-member

No access.

---

# 35. Periods — INSERT

Only an authorized manager can create a new period for their mess.

Period creation should preferably use:

```text
create_period()
```

because it may need to create:

* period row
* meal types
* continuing memberships
* manager assignment
* opening balances

atomically.

---

# 36. Periods — UPDATE

Normal members cannot modify periods.

Manager may perform controlled lifecycle transitions:

```text
DRAFT → OPEN
OPEN → CLOSED
CLOSED → OPEN
```

according to the separate accounting workflow.

Direct unrestricted updates to:

```text status
start_date
end_date
manager-related fields
```

should not be exposed to members.

---

# 37. Periods — DELETE

No normal delete.

Periods with financial data should be retained.

---

# 38. Period Members — SELECT

### Member

Can read their own membership record.

### Manager

Can read all period members for their managed period.

### Historical member

Can read their own historical membership context.

### Non-member

No access.

---

# 39. Period Members — INSERT

Ordinary members must not insert themselves as period members.

Only:

```text approve_join_request()
create_period()
```

or equivalent trusted workflow should create period membership.

---

# 40. Period Members — UPDATE

Members cannot edit:

* their own status
* start date
* end date
* user ID
* period ID

The manager can modify membership through controlled workflows.

Recommended operations:

```text
end_membership()
remove_member()
```

rather than allowing arbitrary column updates.

---

# 41. Period Members — DELETE

Direct delete should be forbidden.

Use:

```text
ENDED
REMOVED
```

to preserve history.

---

# 42. Manager Assignments — SELECT

### Current manager

Can see current/history of management assignments relevant to the period.

### Ordinary member

May see the current manager's identity as part of mess information.

They do not need raw manager assignment history.

### Non-member

No access.

---

# 43. Manager Assignments — INSERT

Direct insert should not be client-permitted.

Use:

```text
assign_manager()
transfer_manager()
```

which verify:

* caller is current manager
* target is eligible
* target belongs to period
* period is in an appropriate state

---

# 44. Manager Assignments — UPDATE

Do not allow arbitrary:

```text user_id
period_id
assigned_at
ended_at
```

updates.

Manager transfer must close the old assignment and create a new one transactionally.

---

# 45. Manager Assignments — DELETE

No direct delete.

History must remain.

---

# 46. Period Meal Types — SELECT

Members may read meal types relevant to the period.

Manager may read and configure them when period state allows.

---

# 47. Period Meal Types — INSERT

Only manager/workflow may create meal types.

Normal member cannot add:

> Midnight Snack Weight = 100

through raw API access.

---

# 48. Period Meal Types — UPDATE

Manager can update configuration for an open period when permitted.

Closed periods are immutable.

Historical configuration cannot be changed by ordinary operations.

---

# 49. Period Meal Types — DELETE

Prefer:

```text is_active = false
```

rather than hard deletion.

---

# 50. Meals — SELECT

### Member

Can read only their own meal records.

### Manager

Can read all meals within their managed period.

### Historical member

Can read own historical meals.

### Non-member

No access.

---

# 51. Meals — INSERT

Members:

```text DENIED
```

Managers:

```text ALLOWED only for:
- authorized period
- open period
- valid period member
- valid date
- valid meal type
```

However, V1 recommendation is to use a controlled mutation such as:

```text save_meal_entries()
```

for the daily meal grid rather than permitting arbitrary row insertion.

---

# 52. Why Batch Meal Mutation

The meal grid may submit dozens of changed cells.

A controlled function can:

```text id="m8r0g8"
validate all cells
↓
apply all changes
↓
write audit events
↓
commit
```

atomically.

This prevents half-saved daily grids.

---

# 53. Meals — UPDATE

Members:

```text DENIED
```

Managers:

```text ALLOWED
```

only while period is mutable.

The manager cannot change:

```text period_id
```

to move an existing record into another period.

---

# 54. Meals — DELETE

Normal members:

```text DENIED
```

Managers may correct/remove an operational meal record according to the period state.

For auditability, deletion should create an audit event.

---

# 55. Guest Meals — Authorization

Guest meals are still meals.

Therefore:

### Host member

does not gain permission to create the record.

### Manager

creates them.

The host relationship must be validated against the manager-controlled period context.

---

# 56. Expense Categories — SELECT

Authenticated users may read active default category definitions as needed.

The categories contain no private mess-specific financial information.

If category customization is added later, its RLS should follow mess/manager context.

---

# 57. Expense Categories — INSERT/UPDATE

V1 default categories should not be casually edited by ordinary users.

If custom categories are introduced:

> Only manager may create/disable mess-specific categories.

Global seed categories should be treated differently from user-controlled data.

---

# 58. Expenses — SELECT

### Manager

Full expense information for their managed/current or historical authorized periods.

### Member

The member should only receive information necessary to explain:

* their own allocated share
* expenses affecting their statement

A member should not automatically gain access to unrelated private expense information.

---

# 59. Expense Privacy Example

Suppose:

```text
Expense:
Private reimbursement for member A

Amount:
৳1,000

Applies only to A
```

Member B should not see:

```text
description
amount
payer
```

just because B is a mess member.

---

# 60. Shared Expense Visibility

For an expense shared among:

```text
A, B, C
```

members participating in the expense may need enough information to understand their own allocation.

Non-participants should not necessarily see full details.

Manager sees everything.

---

# 61. Expenses — INSERT

Members:

```text DENIED
```

Managers:

```text ALLOWED
```

but preferably through:

```text create_expense()
```

rather than direct insert.

The function can atomically create:

```text expense
+
allocations
+
audit
```

---

# 62. Expenses — UPDATE

Manager only.

Must verify:

* current manager
* open period
* valid expense
* valid payer
* valid category
* valid allocation state

Members cannot alter:

* amount
* payer
* category
* accounting treatment
* allocation method

---

# 63. Expenses — DELETE

No ordinary direct delete.

Use:

```text void_expense()
```

where practical.

The void operation must:

* verify manager
* verify open period
* mark expense voided
* exclude from active calculations
* record audit event

---

# 64. Expense Allocations — SELECT

### Participant

Can see their own allocation for an expense affecting them.

### Manager

Can see all allocations in their period.

### Other member

Cannot inspect private/non-participating allocations merely by knowing the expense ID.

---

# 65. Expense Allocations — INSERT

Members:

```text DENIED
```

Managers:

```text DENIED as arbitrary direct insert
```

Recommended:

```text create_expense()
```

creates the expense and allocations together.

This prevents orphan/incomplete allocation states.

---

# 66. Expense Allocations — UPDATE

Direct client update should be avoided.

Use:

```text update_expense_allocation()
```

or a higher-level:

```text update_shared_expense()
```

workflow.

---

# 67. Expense Allocations — DELETE

Direct delete:

```text DENIED
```

Manager updates the complete allocation set through a controlled workflow.

This is important because deleting one allocation could temporarily create:

```text expense = ৳1000
allocations = ৳750
```

---

# 68. Payments — SELECT

### Member

Only own payments.

### Manager

All payments in managed period.

### Non-member

No access.

---

# 69. Payments — INSERT

Member:

```text DENIED
```

Manager:

```text ALLOWED
```

Recommended function:

```text record_payment()
```

rather than broad insert.

---

# 70. Payments — UPDATE

Manager only while period allows mutation.

Members cannot edit their own payment records.

This prevents:

```text paid = 100
```

being changed client-side to:

```text paid = 10000
```

to eliminate a balance.

---

# 71. Payments — DELETE

Direct delete denied.

Use controlled void/correction function.

---

# 72. Adjustments — SELECT

### Member

Can view adjustments affecting their own statement.

### Manager

Can view all adjustments.

### Other members

Cannot inspect another member's private adjustments.

---

# 73. Adjustments — INSERT

Manager only.

Prefer:

```text create_adjustment()
```

because the function can validate:

* member
* period
* amount
* type
* reason
* period state

---

# 74. Adjustments — UPDATE

Manager only while period remains editable.

---

# 75. Adjustments — DELETE

Direct delete denied.

Use controlled void/correction.

---

# 76. Opening Balances — SELECT

### Member

Own opening balance.

### Manager

All opening balances for their period.

### Non-member

No access.

---

# 77. Opening Balances — INSERT

Do not allow ordinary direct insertion.

Use:

```text create_period()
carry_forward_balance()
```

or controlled manual opening-balance function.

---

# 78. Opening Balances — UPDATE

Manager only during appropriate period setup stage.

Once accounting activity has meaningfully progressed, changes should be tightly controlled.

---

# 79. Opening Balances — DELETE

Direct delete denied.

Correction should be explicit and audited.

---

# 80. Settlement Snapshots — SELECT

### Member

Only snapshots and information relevant to their own account.

### Manager

All settlement information for authorized periods.

### Non-member

No access.

---

# 81. Settlement Snapshots — INSERT

Members:

```text DENIED
```

Managers:

```text DENIED for arbitrary insert
```

Snapshots must be produced by the controlled settlement workflow.

---

# 82. Settlement Snapshots — UPDATE

Direct client update:

```text DENIED
```

A finalized settlement must be immutable.

Recalculation creates a new version rather than editing finalized values in place.

---

# 83. Settlement Snapshots — DELETE

Denied.

Historical finalization records must remain.

---

# 84. Settlement Member Snapshots — SELECT

### Member

Only own snapshot corresponding to a period membership they are authorized to view.

### Manager

All member snapshots for managed periods.

---

# 85. Settlement Member Snapshots — INSERT/UPDATE/DELETE

Normal client operations:

```text DENIED
```

Created by the settlement workflow.

This prevents members from manipulating their final balance directly.

---

# 86. Audit Events — SELECT

### Manager

Can access audit events for authorized periods/mess contexts.

### Member

No general audit access in V1.

### Non-member

No access.

---

# 87. Audit Events — INSERT

Normal application clients should not directly insert arbitrary audit events.

Audit records should be generated by trusted database workflows/triggers.

---

# 88. Audit Events — UPDATE

Denied for all ordinary application roles.

---

# 89. Audit Events — DELETE

Denied.

---

# 90. Grants Strategy

RLS alone is insufficient if broad table privileges remain available.

Supabase explicitly states that PostgreSQL grants and RLS both participate in Data API authorization.

Therefore the project should intentionally establish grants.

Recommended principle:

```text
anon
→ no private table access

authenticated
→ SELECT only where appropriate
→ direct INSERT/UPDATE/DELETE only where intentionally safe

service_role
→ server-only
```

---

# 91. Recommended Grant Philosophy

For tables involved in complex accounting workflows:

```text SELECT
```

may be granted to `authenticated`, with RLS restricting rows.

For high-risk mutations:

```text INSERT/UPDATE/DELETE
```

should be withheld from direct client access and replaced with controlled RPC/database functions.

---

# 92. High-Risk Function Operations

Recommended RPC/database functions:

```text id="yj5v79"
create_mess()
request_to_join_mess()
approve_join_request()
reject_join_request()

create_period()
assign_manager()
transfer_manager()

save_meal_entries()
create_guest_meal()
create_expense()
update_shared_expense()
void_expense()

record_payment()
void_payment()

create_adjustment()
void_adjustment()

create_opening_balance()

calculate_period_summary()
calculate_member_statement()

close_period()
reopen_period()
```

---

# 93. Function Authorization

Every protected function should independently verify the caller.

For example:

```text id="7t3w7v"
transfer_manager(period_id, new_manager)
```

must verify:

```text caller authenticated
AND
caller is current manager
AND
target belongs to period
AND
period state permits transfer
```

It must not trust frontend-provided:

```text current_manager_id
```

---

# 94. Function Argument Validation

Never rely solely on RLS when a function itself performs privileged work.

A function should validate its own:

* UUID references
* period state
* target membership
* monetary amounts
* dates
* allocation totals

---

# 95. Function Search Path

Security-sensitive security-definer functions should use:

```sql id="o2u4h1"
set search_path = ''
```

and explicit schema qualification.

---

# 96. Function Exposure

Internal helper functions used only inside RLS do not need to be exposed through PostgREST.

Supabase specifically notes that security-definer functions used inside policies do not need to be placed in exposed schemas.

This supports keeping the `private` schema outside the public API surface.

---

# 97. `service_role`

The application should avoid using the service-role key for normal user operations.

`service_role` bypasses RLS and therefore must remain on trusted server infrastructure. Supabase explicitly warns that it should not be exposed to the browser.

---

# 98. Direct Table Mutation Threat Model

Assume an attacker has:

* valid Supabase URL
* valid anonymous/public key
* their own authenticated session
* knowledge of database table names
* knowledge of another user's UUID
* knowledge of a period UUID
* knowledge of an expense UUID

They must still be unable to:

```text
read unauthorized data
insert unauthorized membership
change another member's meals
edit another member's payment
modify manager assignment
change settlement
modify audit records
```

---

# 99. ID Tampering

Example attacker request:

```text id="v7th0e"
period_member_id = victim_member_id
```

The database must verify relationship to:

```text auth.uid()
```

and deny the operation.

---

# 100. Mess ID Tampering

Example:

```text id="gqtp2d"
mess_id = another_mess
```

RLS/function authorization must resolve actual membership rather than trust the submitted ID.

---

# 101. Period ID Tampering

Example:

```text id="mwhjki"
period_id = another_period
```

The operation must verify that the caller is authorized for that period.

---

# 102. Manager ID Tampering

Example:

```text id="i1h5f8"
manager_assignments.user_id = attacker
```

A member cannot promote themselves.

The database function must determine manager identity from `auth.uid()` rather than arbitrary payload values.

---

# 103. Closed Period Attack

Attacker attempts:

```text id="d1b6it"
INSERT INTO meals
period_id = closed_period
```

Result:

```text DENIED
```

The period-state check must apply even if the attacker is technically the former/current manager.

---

# 104. Closed Expense Attack

Attacker attempts to edit:

```text id="vq0hf6"
amount = ৳1
```

on a closed period.

Database must reject.

---

# 105. Settlement Tampering

Attacker attempts:

```text id="qy6x8o"
UPDATE settlement_member_snapshots
SET final_balance = 0
```

Result:

```text DENIED
```

No direct client update policy should exist.

---

# 106. Audit Tampering

Attacker attempts:

```text id="1a7qpd"
DELETE FROM audit_events
```

Result:

```text DENIED
```

The audit trail is protected.

---

# 107. Self-Approval Attack

Attacker creates:

```text join_request
```

and then attempts:

```text UPDATE join_requests
SET status = 'APPROVED'
```

RLS/function design must make this impossible.

---

# 108. Self-Manager Attack

Member attempts:

```text INSERT INTO manager_assignments
```

with:

```text user_id = auth.uid()
```

Result:

```text DENIED
```

Only the controlled manager-transfer workflow can assign management.

---

# 109. Cross-Mess Allocation Attack

Manager of Mess A attempts to allocate an expense in Mess A to a period member from Mess B.

The database must reject because:

```text allocation.period_member.period
```

does not match:

```text expense.period
```

---

# 110. Cross-Period Payment Attack

User attempts to attach a payment to a member in an unrelated period.

The payment workflow must validate:

```text payment.period_id
=
period_member.period_id
```

---

# 111. Cross-Period Meal-Type Attack

User attempts:

```text meal.period_id = September
meal.meal_type_id = October dinner
```

Database/function must reject.

---

# 112. Cross-Membership Meal Attack

User attempts to insert:

```text September meal
```

for a member whose September membership ended before the meal date.

The operation must reject.

---

# 113. Former Member Read Attack

A former member should retain appropriate historical access but not automatically regain current manager/member operational access.

The RLS model must distinguish:

```text historical read
```

from:

```text current operational write
```

---

# 114. Former Manager Read/Write

After manager transfer:

### Former manager

May:

* remain a member
* read appropriate member/current information

May not:

* edit meals
* add expenses
* approve members
* close period
* transfer management again

unless they are later reassigned.

---

# 115. Multiple Browser Sessions

If manager authority changes in another session:

The next protected operation must use current database state.

The stale browser must not retain authority merely because it has an old UI state.

---

# 116. Race Condition — Manager Transfer

Two simultaneous calls:

```text A transfers to B
A transfers to C
```

must result in exactly one valid manager assignment transition.

The database unique current-manager constraint plus transactional function should enforce this.

---

# 117. Race Condition — Join Approval

Two simultaneous approval attempts should not create:

```text two period members
```

The membership unique constraint prevents duplicate membership.

The workflow must also ensure request status changes atomically.

---

# 118. Race Condition — Expense Allocation

Two simultaneous updates to a shared expense must not leave allocation rows inconsistent with the source expense.

Use a transaction around the complete allocation replacement.

---

# 119. Race Condition — Close Period

Two sessions attempting to close the same period should result in one successful closure.

The second should observe:

```text period already closed
```

rather than generating a second competing finalization.

---

# 120. RLS Recursion Risk

Avoid policies that create circular dependence.

Example:

```text period_members policy
→ needs mess membership
→ mess membership policy
→ needs period_members
```

This can recurse.

Supabase specifically documents using narrowly designed security-definer helpers to break such cycles when necessary.

---

# 121. RLS Performance

RLS expressions will run frequently.

Supabase recommends indexing columns used by policy predicates and wrapping stable helper calls in a `SELECT` form when appropriate so PostgreSQL can optimize them.

The schema therefore indexes:

```text user_id
period_id
mess_id
period_member_id
```

where needed.

---

# 122. Helper Function Caching

A helper such as:

```text
private.is_period_manager(period_id)
```

should be used in a way that allows PostgreSQL to evaluate it efficiently where the result is independent of row-specific values.

Supabase documents the `(select function())` pattern for this optimization.

---

# 123. Policy Structure

Each table should explicitly define policies for:

```text
SELECT
INSERT
UPDATE
DELETE
```

where applicable.

Avoid:

```text
FOR ALL
```

unless there is a compelling reason and the policy remains completely understandable.

Supabase explicitly recommends operation-specific policies.

---

# 124. `SELECT` Policy Requirement for UPDATE

When using RLS, an UPDATE operation also needs an appropriate SELECT policy on the rows being updated.

This must be considered when implementing manager UPDATE policies. Supabase documents this requirement directly.

---

# 125. `USING` vs `WITH CHECK`

Use:

### `USING`

to determine which existing rows a user can access/change.

### `WITH CHECK`

to ensure the resulting row remains valid.

Example:

A manager may update a meal, but:

```text
period_id cannot be changed
period_member_id cannot be changed
created_by cannot be reassigned
```

The resulting row must satisfy those restrictions.

---

# 126. Recommended Direct UPDATE Policy Philosophy

For many financial tables, direct UPDATE may be disallowed entirely.

This is preferable to writing enormous `WITH CHECK` expressions for every mutable field.

Use RPC/function workflows where business invariants are complex.

---

# 127. Recommended Direct DELETE Philosophy

For:

```text
expenses
payments
adjustments
allocations
settlements
manager assignments
period membership
```

direct DELETE should generally be denied.

Corrections are controlled operations.

---

# 128. Direct INSERT Philosophy

Allow direct INSERT only where:

* data is simple
* authorization is straightforward
* no multi-row invariants must be established simultaneously

For example, profile updates may qualify.

High-risk accounting workflows should use database functions.

---

# 129. Proposed Permission Matrix — Tables

| Table                       | Member SELECT |            Manager SELECT | Member INSERT |    Manager INSERT | Member UPDATE | Manager UPDATE | Member DELETE | Manager DELETE |
| --------------------------- | ------------: | ------------------------: | ------------: | ----------------: | ------------: | -------------: | ------------: | -------------: |
| profiles                    |           Own |               Appropriate |           Own |               Own |           Own |    Appropriate |            No |             No |
| messes                      |    Authorized |                      Full |            No |          Workflow |            No |     Controlled |            No |             No |
| join codes                  |    No/limited |                  Own mess |            No |          Workflow |            No |       Workflow |            No |             No |
| join requests               |           Own |                  Own mess |           Own |          Workflow |            No |       Workflow |            No |             No |
| periods                     |    Authorized |                      Full |            No |          Workflow |            No |       Workflow |            No |             No |
| period_members              |           Own |                      Full |            No |          Workflow |            No |       Workflow |            No |             No |
| manager_assignments         |       Limited |                      Full |            No |          Workflow |            No |       Workflow |            No |             No |
| period_meal_types           |          Read |                      Full |            No |          Workflow |            No |     Controlled |            No |             No |
| meals                       |           Own |                       All |            No |          Workflow |            No |     Controlled |            No |     Controlled |
| expense_categories          |          Read | Read/manage as applicable |            No |        Controlled |            No |     Controlled |            No |     Controlled |
| expenses                    |    Own-impact |                      Full |            No |          Workflow |            No |       Workflow |            No |           Void |
| allocations                 |    Own-impact |                      Full |            No |          Workflow |            No |       Workflow |            No |             No |
| payments                    |           Own |                      Full |            No |          Workflow |            No |     Controlled |            No |           Void |
| adjustments                 |           Own |                      Full |            No |          Workflow |            No |     Controlled |            No |           Void |
| opening_balances            |           Own |                      Full |            No |          Workflow |            No |     Controlled |            No |             No |
| settlement_snapshots        |           Own |                      Full |            No |          Workflow |            No |             No |            No |             No |
| settlement_member_snapshots |           Own |                      Full |            No |          Workflow |            No |             No |            No |             No |
| audit_events                |            No |                Authorized |            No | Internal workflow |            No |             No |            No |             No |

"Workflow" means a controlled database function/RPC rather than an unrestricted table mutation.

---

# 130. Member Read Matrix

A normal active member can read:

```text
Own profile
Own membership
Own meals
Own payments
Own adjustments
Own allocations affecting them
Own settlement
Appropriate period/mess metadata
Appropriate aggregate statistics
```

They cannot read arbitrary:

```text other member's payments
other member's private adjustments
unrelated expense details
audit history
manager controls
```

---

# 131. Manager Read Matrix

A current manager can read all operational/accounting data for their managed period:

```text members
meals
expenses
allocations
payments
adjustments
opening balances
settlements
audit events
```

Historical access should also be defined according to the manager's relationship with the mess and period.

---

# 132. Historical Manager Access

An old manager who is no longer manager should generally retain member-level/historical access appropriate to their membership but not unrestricted management access.

This distinction avoids giving former managers permanent administrative authority.

---

# 133. Mess-Level Membership vs Period Membership

Authorization should not infer:

```text user belongs to mess forever
```

from an old period membership.

A user may have historical access to an old period but no current membership.

This must be handled explicitly.

---

# 134. Recommended Access Helper Categories

Use two concepts:

```text
can_view_historical_period()
can_operate_current_period()
```

rather than a single generic `is_member()` function.

---

# 135. Historical Read Rule

A former member may view their finalized statements from periods in which they were legitimately a member.

They should not automatically see:

* current members' private data
* current pending requests
* current manager controls

---

# 136. Current Operational Rule

To mutate an operational record:

```text
user
+
current manager
+
target period
+
period OPEN
```

must all be true.

---

# 137. Closed Period Rule

Even:

```text current manager
```

does not automatically mean:

```text can edit closed period
```

The period-state check is an independent requirement.

---

# 138. Reopen Rule

Reopening is itself a privileged operation.

Therefore:

```text CLOSED
```

is not bypassed simply because a user wants to edit.

The caller must invoke:

```text reopen_period()
```

with appropriate authorization and reason.

---

# 139. Audit of Security-Sensitive Operations

The following must generate audit events:

```text member approval
member rejection
member removal
manager assignment
manager transfer
join code regeneration
expense creation
expense update
expense void
allocation update
payment creation
payment update
payment void
adjustment creation
adjustment update
period close
period reopen
opening balance modification
```

---

# 140. RLS Test Suite

Supabase provides a database test workflow using pgTAP and recommends testing the actual RLS policies, including member/non-member cases.

The project should create tests under:

```text
supabase/tests/
```

for each critical table/security boundary.

---

# 141. Required RLS Test Identities

At minimum:

```text
user_A = manager of Mess 1
user_B = member of Mess 1
user_C = non-member of Mess 1
user_D = member of Mess 2
user_E = former manager/member of Mess 1
```

Also test:

```text unauthenticated
```

where supported.

---

# 142. Required RLS Test — Cross-Mess Access

Test:

```text User B → Mess 2
```

Must return no unauthorized data.

---

# 143. Required RLS Test — Member Write

Test:

```text User B → insert expense
```

Must fail.

---

# 144. Required RLS Test — Member Meal Modification

Test:

```text User B → update meal
```

Must fail.

---

# 145. Required RLS Test — Member Payment Modification

Test:

```text User B → update payment
```

Must fail.

---

# 146. Required RLS Test — Member Settlement Modification

Test:

```text User B → update settlement snapshot
```

Must fail.

---

# 147. Required RLS Test — Self-Promotion

Test:

```text User B → become manager
```

Must fail.

---

# 148. Required RLS Test — Join Self-Approval

Test:

```text User C → approve own request
```

Must fail.

---

# 149. Required RLS Test — Closed Period Mutation

Test:

```text User A → insert meal into closed period
```

Must fail.

---

# 150. Required RLS Test — Former Manager

Test:

```text User E → manager-only mutation
```

Must fail after transfer.

---

# 151. Required RLS Test — Personal Privacy

Test:

```text User B → read User C's payment
```

Must fail.

---

# 152. Required RLS Test — Own Data

Test:

```text User B → read own payment
```

Must succeed.

---

# 153. Required RLS Test — Manager Full Access

Test:

```text User A → read all current member statements
```

Must succeed.

---

# 154. Required RLS Test — Participant Privacy

For shared expenses:

```text B participates
C does not participate
```

B should see their relevant allocation.

C should not gain full private allocation detail merely by knowing the expense UUID.

---

# 155. Required RLS Test — ID Substitution

Take a legitimate member request and replace:

```text member_id
period_id
expense_id
payment_id
```

with IDs belonging to another user/mess.

Every unauthorized case must fail.

---

# 156. Required Function Test — Manager Transfer

Verify:

```text current manager → valid member
```

succeeds.

Verify:

```text ordinary member → valid member
```

fails.

Verify:

```text manager → non-member target
```

fails.

---

# 157. Required Function Test — Expense Allocation

Verify:

```text expense = 1000
allocations = 1000
```

succeeds.

Verify:

```text expense = 1000
allocations = 999
```

fails.

---

# 158. Required Function Test — Period Closure

Verify:

```text valid open period
```

can close.

Verify:

```text already closed
```

cannot close again.

Verify blockers prevent closure.

---

# 159. RLS Policy Test Principle

Do not test only the happy path:

> manager can edit.

Also test the inverse:

> member, former manager, non-member, wrong mess, wrong period, closed period, manipulated ID cannot edit.

Security correctness comes from the negative cases.

---

# 160. Views and RLS

Any reporting view exposed through Supabase must be examined separately.

Supabase warns that PostgreSQL views can bypass underlying RLS depending on how they are defined, and recommends `security_invoker = true` for safe views on PostgreSQL 15+ when the view should obey underlying RLS.

Therefore:

> No settlement/reporting view may be exposed casually.

---

# 161. Recommended Reporting View Strategy

For user-facing views:

```sql
create view ...
with (security_invoker = true)
as ...
```

where appropriate.

Alternatively:

* keep sensitive views in a non-exposed schema
* expose data through RLS-protected tables/functions

The exact choice will be made in the reporting layer.

---

# 162. Function vs View Security

Remember:

### Table

RLS applies.

### View

Requires deliberate RLS/security design.

### Function

RLS does not automatically protect function execution.

Every category requires separate security consideration.

---

# 163. Grants for Private Helpers

The private schema should not be broadly executable by application users.

Where a helper must be called from policies, it can remain internal while policy execution invokes it appropriately.

---

# 164. No Client-Supplied Role Claims for Authorization

Do not authorize through:

```text
localStorage.role
JWT custom claim controlled by client
request.body.role
query parameter role
```

Manager authorization must derive from authoritative database state.

---

# 165. JWT Consideration

Supabase Auth JWT claims can sometimes be used in authorization, but the product's manager relationship changes frequently.

Therefore V1 should not store manager status solely in long-lived JWT custom claims.

A manager transfer should take effect immediately at the database level.

---

# 166. Immediate Permission Revocation

When:

```text
A → B
```

manager transfer occurs:

A should lose manager privileges as soon as database state changes.

Do not require waiting for a periodic permission cache refresh.

---

# 167. Immediate Membership Revocation

Likewise, if member B is removed:

Their next protected query/mutation must see the updated state.

---

# 168. Policy Staleness

Frontend role state may become stale.

That is acceptable.

Backend authorization must not be stale in a way that grants old privileges.

---

# 169. Security Logging

Unauthorized attempts may be logged at infrastructure level where useful.

Do not expose internal authorization details to users.

---

# 170. Error Messages

Security-sensitive errors should be intentionally generic.

Bad:

> You failed because user X is the manager and period Y is closed.

Better:

> You don't have permission to perform this action.

This reduces information leakage.

---

# 171. Join Code Error Messages

Invalid code should produce a generic response.

Do not reveal:

* mess existence details
* member count
* manager name
* expiration implementation
* internal ID

unless intentionally public.

---

# 172. Protected Data Enumeration

A user should not be able to determine whether:

```text expense UUID exists
payment UUID exists
period UUID exists
```

when they are not authorized to see it.

Generic not-found/access-denied behavior is preferred.

---

# 173. RLS and Frontend Hiding

Frontend hiding is useful:

```text member doesn't see edit button
```

but is not a security mechanism.

The database must independently deny:

```text update
insert
delete
```

---

# 174. Server Components and Client Components

Where Next.js server components are used, they may improve UX/security by keeping some queries server-side.

However, this does not eliminate RLS requirements.

A compromised browser or direct API request still needs protection.

---

# 175. Server-Side Secrets

Any privileged key used by server-side functions must not be imported into browser/client components.

---

# 176. Anonymous Request Behavior

Every private table policy should explicitly target:

```text to authenticated
```

rather than accidentally allowing anonymous access.

Supabase recommends explicit `TO` clauses in RLS policies.

---

# 177. Policy Naming

Use consistent names:

```text
profiles_select_own
profiles_update_own

messes_select_member
messes_update_manager

meals_select_own
meals_select_manager
meals_insert_manager

...
```

Names should reveal:

```text table
operation
scope
```

---

# 178. Policy Documentation

Every non-trivial policy should have a comment in the migration explaining:

* intended actor
* data scope
* reason
* helper function used

This is especially useful when the policy looks cryptic six months later.

---

# 179. RLS Migration Structure

Recommended:

```text id="0rt3ah"
002_rls_helpers.sql
003_grants.sql
004_rls_profiles.sql
005_rls_messes.sql
006_rls_membership.sql
007_rls_operations.sql
008_rls_settlement.sql
009_rls_audit.sql
```

Alternatively, combine related tables into fewer migrations.

---

# 180. Recommended Security Function Layer

A useful internal layer is:

```text id="p5bptf"
private.is_period_member(uuid)
private.is_period_manager(uuid)

private.can_view_period(uuid)
private.can_operate_period(uuid)

private.can_view_period_member(uuid)
private.can_manage_period_member(uuid)
```

The final implementation should keep these functions small.

---

# 181. Avoid Overly Generic `can_access_everything()`

Do not create one giant function:

```text id="3rv8i8"
can_access(...)
```

with hundreds of branches.

That becomes difficult to audit.

Use small composable authorization concepts.

---

# 182. Authorization Decision Table

For an operation:

```text id="a62xjb"
Can user X do action Y on record Z?
```

check:

```text
1. Is X authenticated?
2. Does Z belong to a mess?
3. Does X have an allowed relationship with that mess?
4. Does Z belong to a period?
5. Is X an appropriate period member/manager?
6. Is the period in a mutable state?
7. Is the requested operation allowed for X?
```

---

# 183. Example — Add Expense

```text id="8c6g1k"
authenticated?
   ↓ yes
manager for period?
   ↓ yes
period open?
   ↓ yes
payer belongs to period?
   ↓ yes
category valid?
   ↓ yes
allocation valid?
   ↓ yes
CREATE
```

Any failed step blocks the operation.

---

# 184. Example — View Own Payment

```text id="v5w1ef"
authenticated?
   ↓
payment exists?
   ↓
payment period/member relationship
belongs to auth.uid()?
   ↓
SELECT
```

---

# 185. Example — View Any Member Balance as Manager

```text id="h2d8x8"
authenticated?
   ↓
manager for target period?
   ↓
target member belongs to target period?
   ↓
SELECT
```

---

# 186. Example — Close Period

```text id="z84t9y"
authenticated?
   ↓
current manager?
   ↓
period OPEN?
   ↓
blocking validation errors = none?
   ↓
create final snapshot
   ↓
close period
```

This is not a normal table update.

It is a transactional privileged workflow.

---

# 187. Example — Reopen Period

```text id="jbbynx"
authenticated?
   ↓
authorized manager?
   ↓
period CLOSED?
   ↓
reason present?
   ↓
create audit
   ↓
transition OPEN
```

---

# 188. Security Boundary of the Calculation Engine

The calculation engine must receive trusted period/member/record context.

Users must not be able to call:

```text calculate_member_statement(
  victim_member_id
)
```

and bypass the read authorization associated with that member.

The function's execution privileges and returned data must be carefully designed.

---

# 189. SECURITY DEFINER Calculation Functions

Prefer `security invoker` unless elevated privileges are genuinely required.

Supabase documents `security invoker` as the default/best practice and recommends `security definer` only when necessary, with a fixed search path.

---

# 190. If Calculation Function Is SECURITY DEFINER

It must:

1. verify caller authorization
2. validate requested mess/period/member
3. expose only authorized data
4. use a pinned search path
5. avoid returning unrelated rows
6. have narrowly controlled EXECUTE privileges

A security-definer calculation function must never become a data-exfiltration endpoint.

---

# 191. API Security Surface

The application's public API surface should be intentionally small.

Prefer:

```text id="0dhcik"
read queries
+
small set of approved RPC/workflow functions
```

over:

```text unrestricted table CRUD
+
complex client-generated mutations
```

---

# 192. Recommended Client Mutation Surface

The frontend should primarily call functions such as:

```text
request_to_join_mess
approve_join_request
transfer_manager
save_meal_entries
create_expense
update_expense
record_payment
create_adjustment
close_period
reopen_period
```

This provides a clean business-operation boundary.

---

# 193. Security Acceptance Criteria

The RLS implementation is acceptable only when:

```text
✓ unauthenticated users cannot access private data
✓ non-members cannot access mess data
✓ members cannot modify accounting data
✓ members cannot approve themselves
✓ members cannot promote themselves
✓ members cannot modify settlement
✓ former managers lose manager privileges
✓ cross-mess access is blocked
✓ cross-period access is blocked
✓ closed periods reject mutations
✓ audit events cannot be modified
✓ direct ID tampering fails
✓ high-risk functions validate caller authority
✓ security-definer functions use safe search_path
✓ service-role credentials never reach browser
✓ views do not accidentally bypass RLS
✓ RLS tests cover positive and negative cases
```

---

# 194. Security Test Matrix

| Attack/Case                                 | Expected Result        |
| ------------------------------------------- | ---------------------- |
| Anonymous reads messes                      | Denied                 |
| Anonymous reads meals                       | Denied                 |
| Non-member reads mess                       | Denied                 |
| Member reads own meals                      | Allowed                |
| Member reads another member's private meals | Denied                 |
| Member inserts meal                         | Denied                 |
| Member updates meal                         | Denied                 |
| Member creates expense                      | Denied                 |
| Member changes allocation                   | Denied                 |
| Member creates payment                      | Denied                 |
| Member edits payment                        | Denied                 |
| Member creates adjustment                   | Denied                 |
| Member changes manager                      | Denied                 |
| Member approves own join request            | Denied                 |
| Manager reads all period meals              | Allowed                |
| Manager adds meal                           | Allowed if period open |
| Manager adds expense                        | Allowed if authorized  |
| Former manager adds expense                 | Denied                 |
| Manager edits closed-period expense         | Denied                 |
| User from Mess A reads Mess B               | Denied                 |
| User substitutes victim member ID           | Denied                 |
| User updates settlement snapshot            | Denied                 |
| User deletes audit event                    | Denied                 |
| Two managers transfer simultaneously        | One valid result       |
| Duplicate join request                      | Prevented              |
| Cross-period allocation                     | Denied                 |
| Cross-period meal type                      | Denied                 |

---

# 195. Final Authorization Architecture

The intended security architecture is:

```text id="v6yyq8"
                 SUPABASE AUTH
                      │
                      ▼
                auth.uid()
                      │
                      ▼
             ┌─────────────────┐
             │ PRIVATE HELPERS │
             │ membership      │
             │ manager status  │
             │ period access   │
             └────────┬────────┘
                      │
                      ▼
             POSTGRES RLS POLICIES
                      │
          ┌───────────┴───────────┐
          │                       │
          ▼                       ▼
      READ ACCESS            WRITE ACCESS
          │                       │
          │              controlled functions
          │                       │
          └──────────┬────────────┘
                     ▼
                  TABLES
                     │
                     ▼
                  AUDIT
```

---

# 196. Final Security Principle

The application should be designed so that the following statement is always true:

> **If the frontend disappears completely and a user interacts directly with Supabase, the database still enforces the product's authorization rules.**

That is the standard the subsequent SQL/RLS implementation must meet.

---

# 197. Handoff to the Calculation Engine

The authorization model is now defined.

The next critical document is **Document 10 — Calculation Engine & Accounting Specification**.

That document will formally define the mathematics of:

* meal units
* meal rate
* food cost
* guest meals
* shared expenses
* equal/weighted/fixed allocations
* rounding and residual cents
* payments
* credits
* debits
* opening balances
* carry-forward
* settlement
* reconciliation
* zero-meal scenarios
* zero-food-cost scenarios
* reopened-period recalculation
* finalization/versioning

The objective is that two independent developers implementing the calculation engine from that document would produce the same result for every test case.
