# Mess Manager

## Non-Functional & Technical Requirements Specification

**Document version:** 1.0
**Product version:** V1
**Related documents:** Product Requirements Document v1.0; Functional Requirements Document v1.0
**Frontend target:** React/Next.js-based responsive web application
**Backend:** Supabase
**Database:** PostgreSQL
**Authentication:** Supabase Auth
**Deployment:** Vercel
**Development:** GitHub Codespaces
**Primary currency:** BDT (৳)
**Primary timezone:** Asia/Dhaka

---

# 1. Purpose

This document defines the technical and non-functional constraints under which Mess Manager must operate.

The goal is to ensure that the application is not merely functionally correct, but also:

* secure
* reliable
* maintainable
* performant
* auditable
* responsive
* accessible
* deployable
* recoverable
* resistant to accidental financial corruption

The requirements in this document constrain the architecture used in later documents.

---

# 2. Technical Architecture

The recommended V1 architecture is:

```text id="x1c0d4"
                   ┌───────────────────────┐
                   │       Browser         │
                   │ Mobile / Tablet / PC  │
                   └───────────┬───────────┘
                               │
                               ▼
                   ┌───────────────────────┐
                   │       Vercel          │
                   │ React / Next.js app   │
                   └───────────┬───────────┘
                               │
                 ┌─────────────┴─────────────┐
                 │                           │
                 ▼                           ▼
       ┌──────────────────┐       ┌──────────────────┐
       │ Supabase Auth    │       │ Supabase         │
       │                  │       │ PostgreSQL       │
       └──────────────────┘       │ + RLS            │
                                  │ + Functions       │
                                  │ + Triggers        │
                                  │ + Views           │
                                  └──────────────────┘
```

---

# 3. Architecture Principles

## NFR-ARCH-001 — Single source of truth

Persistent operational and accounting data shall reside in Supabase PostgreSQL.

The frontend must not be treated as the authoritative datastore.

---

## NFR-ARCH-002 — Server-authoritative accounting

Financial calculations affecting settlement must ultimately be calculated or validated in a trusted server/database context.

Client-side calculations may be used for previews but must never be treated as final accounting truth.

---

## NFR-ARCH-003 — Database-enforced authorization

Security-sensitive authorization shall be enforced at the database layer using Supabase/PostgreSQL mechanisms, particularly Row Level Security.

The application must not rely exclusively on:

```text id="ow10m7"
if (user.isManager) {
    showEditButton();
}
```

as a security mechanism.

The corresponding database operation must independently deny unauthorized users.

---

# 4. Technology Constraints

V1 should use technologies that:

* have mature TypeScript support
* work well in GitHub Codespaces
* deploy naturally to Vercel
* integrate cleanly with Supabase
* require no paid infrastructure for the initial deployment
* do not introduce unnecessary backend hosting

Recommended stack:

```text id="u2ow6k"
Language:
TypeScript

Framework:
Next.js

UI:
React

Styling:
Tailwind CSS or equivalent utility/component approach

Backend:
Supabase

Database:
PostgreSQL

Authentication:
Supabase Auth

Deployment:
Vercel

Source control:
GitHub
```

The exact framework configuration belongs in the implementation specification.

---

# 5. Environment Separation

At minimum, the project must distinguish:

```text id="av1z8h"
Development
Production
```

Preferably:

```text id="xjjwrr"
Local/Codespace development
        ↓
Preview deployment
        ↓
Production
```

Production database credentials must never be committed to Git.

---

# 6. Environment Variables

Secrets and environment-specific configuration must be supplied through environment variables.

Examples:

```text id="9kb4zr"
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
```

Any privileged server-side key must remain server-only.

A Supabase service-role key, if used by administrative backend operations, must never be exposed to browser JavaScript.

---

# 7. Repository Requirements

The Git repository shall contain:

```text id="q1b2be"
app source code
database migrations
configuration
tests
documentation
```

It shall not contain:

* production credentials
* Supabase service-role keys
* personal user data
* database dumps containing real user data
* generated secrets

---

# 8. Database Migration Requirements

Database changes must be represented as reproducible migrations.

A developer setting up a fresh environment must be able to reconstruct the database from migration files.

Do not rely on manually changing production tables through the Supabase dashboard as the normal development workflow.

---

# 9. Schema Change Principle

Every schema modification must be:

1. deliberate
2. versioned
3. reproducible
4. testable

Examples:

```text id="iu3xq9"
001_initial_schema.sql
002_add_guest_meals.sql
003_add_audit_log.sql
```

The exact migration naming strategy will be specified in the deployment document.

---

# 10. Authentication Security

Authentication should be delegated to Supabase Auth rather than implemented manually.

Requirements:

* passwords must not be stored in application tables
* authentication tokens must be handled by the supported Supabase mechanism
* password-reset flows must be implemented using secure auth APIs
* email/account enumeration should be minimized

---

# 11. Authorization Model

The authorization hierarchy is:

```text id="okv0oz"
Authenticated
   ↓
Mess access
   ↓
Period access
   ↓
Membership context
   ↓
Manager status
   ↓
Operation permission
```

An authenticated user alone must not be considered authorized to access a mess.

---

# 12. RLS Requirement

All application tables exposed through the client-facing Supabase API must use appropriate Row Level Security policies.

At minimum, access should be restricted by:

* authenticated user
* mess membership
* period context
* manager role
* ownership of personal records

Tables that must not be directly client-writable should either:

* have no corresponding write policy
* or expose controlled database functions instead

---

# 13. RLS Design Principle

RLS policies should implement **positive authorization**.

Prefer:

> User belongs to this mess and is the current manager for this period.

rather than:

> User is not forbidden.

This reduces accidental overexposure.

---

# 14. Privilege Escalation Prevention

A malicious member must not be able to:

* modify their own role to manager
* modify another user's role
* change a period's manager
* insert themselves as an approved member
* modify an expense payer
* modify another member's balance
* modify an audit event
* reopen a period

merely by crafting a direct Supabase request.

---

# 15. Trust Boundary

The browser is untrusted.

Even if the UI is correct, the backend must assume an attacker may:

* alter request payloads
* change IDs
* replay requests
* call endpoints directly
* bypass UI validation
* manipulate client-side state

Therefore every sensitive operation requires server/database authorization and validation.

---

# 16. Service-Role Key

A privileged Supabase service-role key, where absolutely necessary, may be used only in a trusted server-side execution context.

It must never:

* appear in client bundles
* be placed in `NEXT_PUBLIC_*` variables
* be logged
* be stored in repository files

The preferred architecture is to minimize service-role usage and use normal authenticated database access plus RLS whenever possible.

---

# 17. Data Encryption

Data in transit must use HTTPS/TLS.

Application secrets must be stored using Vercel/Supabase secret/environment mechanisms rather than source control.

Password handling is delegated to Supabase Auth.

---

# 18. Sensitive Financial Data

Mess Manager does not primarily process highly sensitive banking credentials in V1.

However, financial records still require privacy.

Therefore:

* member balances must be access-controlled
* payment history must be protected
* expense allocations must be access-controlled
* audit history must be restricted
* cross-mess access must be prevented

---

# 19. Join Code Security

Join codes are low-sensitivity invitation credentials but still represent access into a mess.

Requirements:

* random generation
* sufficient entropy
* no sequential IDs
* rate-limited attempts where practical
* revocation support
* regeneration support
* no exposure of internal database IDs

The code must not itself provide immediate membership.

---

# 20. Rate Limiting

Rate limiting should be considered for:

* login attempts
* password-reset requests
* join-code validation
* repeated join requests
* suspicious mutation activity

Where a feature is already protected by Supabase infrastructure, application-level duplication should be avoided unless necessary.

---

# 21. Brute-Force Protection

An attacker must not be able to cheaply enumerate messes by testing enormous numbers of join codes.

Mitigations should include:

* adequate random code space
* server-side lookup
* rate limiting
* generic failure responses

---

# 22. Data Isolation

A user belonging to Mess A must not be able to query data from Mess B.

This must be true even if the attacker knows:

* mess UUID
* period UUID
* member UUID
* expense UUID
* payment UUID

---

# 23. ID Design

Internally generated identifiers should not depend on human-readable sequential numbers where exposing them creates unnecessary enumeration risk.

UUIDs are recommended for primary entities.

The join code should remain a separate human-facing identifier.

---

# 24. Financial Precision

Money shall be represented using PostgreSQL exact numeric/decimal types.

Do not use PostgreSQL floating-point types for accounting values.

JavaScript floating-point arithmetic must not determine final financial values.

---

# 25. Decimal Handling

The frontend must treat monetary values as decimal values rather than relying on unconstrained binary floating-point arithmetic.

Where calculations occur in JavaScript for display, the final authoritative result must still come from the trusted accounting layer.

---

# 26. Rounding

Rounding behavior must be deterministic.

The system must define:

* internal calculation precision
* display precision
* allocation precision
* residual handling
* final settlement precision

These exact rules will be specified in the Calculation Engine Specification.

---

# 27. Accounting Reconciliation

For every period, the system should be able to verify:

```text id="xcp1s5"
Source expenses
=
allocated expenses
```

where applicable.

No final settlement should contain unexplained residual financial amounts.

---

# 28. Transaction Atomicity

Operations modifying related records must be atomic.

For example:

### Shared expense creation

Must avoid this state:

```text id="4j7m3r"
Expense exists
but
allocations are missing
```

unless an explicit draft state is designed for that purpose.

---

# 29. Transaction Isolation

Concurrent operations must not corrupt accounting state.

Examples:

* two users approve the same request
* two manager sessions transfer management
* two edits target the same expense
* close-period operation races with a transaction

Database transactions and appropriate constraints must protect these operations.

---

# 30. Concurrency Requirement

The system shall assume multiple sessions may be active simultaneously.

At minimum:

```text id="1k17jm"
Manager's laptop
+
Manager's phone
+
possibly another manager session
```

may access the same period.

---

# 31. Lost Update Prevention

For critical edits, the application should avoid silently overwriting changes made by another session.

Possible mechanisms include:

* server-side conditional updates
* updated-at comparison
* database transactions
* explicit conflict detection

The precise mechanism will be defined during implementation.

---

# 32. Idempotency

Important operations should be protected against duplicate submission.

For example, pressing:

```text id="iuw7tt"
Record Payment
```

twice should not accidentally create two payments where the same client action was only intended once.

Mechanisms may include:

* unique constraints
* request identifiers
* transaction semantics
* disabled submit state

The server/database remains authoritative.

---

# 33. Reliability

The application should prioritize:

> correctness > availability > optimization

for financial operations.

A temporarily unavailable feature is preferable to silently corrupting an accounting record.

---

# 34. Failure Handling

If a database operation fails:

The UI must not claim success.

Bad:

> Payment saved.

when the database returned an error.

Correct:

> Payment could not be saved. Please try again.

---

# 35. Unknown Outcome Handling

A network timeout may produce an uncertain state:

```text id="cvn6ng"
Client sent request
 ↓
No response
```

The UI must not blindly submit again if doing so could duplicate a financial record.

The application should provide a way to refresh/check the authoritative server state first.

---

# 36. Data Persistence

Operational records should persist independently of browser state.

The application must not rely on:

```text id="6opbbi"
localStorage
sessionStorage
IndexedDB
```

as the primary source of mess accounting data.

These may be used for UI conveniences such as temporary preferences or draft state.

---

# 37. Offline Operation

Full offline accounting is outside V1.

Core financial mutations require server confirmation.

A disconnected user should see an explicit offline/network state.

---

# 38. Autosave

For small single-field interactions, immediate save may be used.

For financial forms with multiple fields, explicit Save/Confirm is preferable.

The user must understand whether changes are:

```text id="3lmz8x"
Saved
Saving
Unsaved
Failed
```

---

# 39. Performance Goals

Under typical V1 workloads, the application should target:

### Initial application shell

Perceived interactive loading within approximately 2–3 seconds on a reasonable modern connection.

### Common page transitions

Preferably under approximately 1–2 seconds.

### Simple database operations

Usually sub-second server-side under normal conditions.

These are targets, not guarantees, and must be measured in production.

---

# 40. Expected Data Volume

V1 should comfortably support a typical student mess such as:

```text id="0b1l96"
5–30 members
≈1 month per active period
hundreds–thousands of meal records
hundreds of expense/payment records
multiple historical periods
```

The schema should remain efficient for substantially larger datasets.

---

# 41. Indexing

Indexes should be created based on actual access patterns.

Likely indexed fields include:

* mess_id
* period_id
* member_id
* user_id
* transaction_date
* expense category
* status
* join code where applicable

Composite indexes should be introduced where frequent queries justify them.

The detailed index plan belongs in the schema document.

---

# 42. Query Efficiency

The frontend should avoid:

```text id="x5eq5x"
N requests for N members
```

where one query can retrieve the required data efficiently.

Particularly important screens:

* dashboard
* member list
* daily meal grid
* settlement review

---

# 43. Calculation Efficiency

The system should avoid recalculating an entire mess unnecessarily for every small UI interaction if that becomes expensive.

However, correctness takes priority.

V1 may use database views/functions and optimized aggregate queries before introducing caching/materialized views.

---

# 44. Caching

Caching may be used for:

* static application assets
* relatively stable reference data
* dashboard optimization where safe

Financial calculations should not be cached in a way that allows stale values to be mistaken for authoritative current balances.

---

# 45. Cache Invalidation

If financial values are cached:

```text id="qjz7r1"
meal change
expense change
payment change
adjustment change
```

must invalidate/revalidate relevant results.

For V1, minimizing bespoke cache complexity is preferable.

---

# 46. Scalability

The architecture should allow growth in:

* mess count
* period count
* member count
* transaction count

without changing the core accounting model.

---

# 47. Availability

The application depends on:

* Vercel availability
* Supabase availability
* internet connectivity

V1 does not require a custom multi-region disaster-resilient backend.

However, database backup/recovery must be considered.

---

# 48. Backup Requirement

The production database must be recoverable through the capabilities provided by the chosen Supabase plan and operational setup.

The project should not assume that GitHub repository history constitutes a database backup.

Source code and database state are separate recovery domains.

---

# 49. Recovery Objective

V1 should document:

### RPO

How much recently entered data could potentially be lost after a catastrophic database failure.

### RTO

How quickly the service should reasonably be restored.

These values should be selected based on the actual Supabase plan and realistic student-project operational needs rather than promising enterprise-grade recovery.

---

# 50. Disaster Recovery

At minimum, the project should maintain:

* version-controlled schema migrations
* documented environment configuration
* documented Supabase project setup
* production deployment instructions
* database backup/recovery procedure appropriate to the chosen plan

---

# 51. Historical Integrity

This is both a functional and non-functional requirement.

A closed period must remain reproducible.

Changing the current:

* manager
* membership
* meal settings
* join code
* current period

must not alter historical accounting results.

---

# 52. Auditability

Important changes must be traceable.

The audit system should provide enough information to answer:

> Who changed what, when, and why?

for management-level data modifications.

---

# 53. Audit Durability

Audit records must persist for at least as long as the associated financial record.

They must not disappear simply because:

* a member leaves
* a manager changes
* a period closes

---

# 54. Deletion Policy

Financial records should generally not be hard-deleted through normal application workflows.

Prefer:

```text id="8at4y2"
active / inactive / voided
```

or correction mechanisms where appropriate.

Historical deletion is a high-risk operation.

---

# 55. Soft Deletion

Where deletion is needed, use a controlled approach rather than physically deleting important historical data.

Examples:

* member ended
* mess archived
* category retired

Financial transaction deletion should be especially restricted.

---

# 56. Referential Integrity

Foreign-key relationships must protect against orphaned records.

Examples:

A payment must not reference a nonexistent member.

An allocation must not reference a nonexistent expense.

A meal must not reference a nonexistent period membership.

---

# 57. Database Constraints

Where business invariants can be expressed as constraints, they should be.

Examples:

* positive amount
* valid date range
* unique active manager
* unique active membership
* no duplicate pending request

Application validation should complement, not replace, database constraints.

---

# 58. Accessibility

The application should aim for WCAG 2.1 AA-oriented accessibility.

Requirements include:

* keyboard operability
* visible focus states
* sufficient contrast
* semantic HTML
* accessible form labels
* useful error messaging
* screen-reader-compatible interactive elements

The product is not primarily an accessibility showcase, but accessibility must not be sacrificed for visual design.

---

# 59. Keyboard Accessibility

All critical manager actions must be usable without a mouse:

* navigate meal grid
* enter values
* submit forms
* close dialogs
* approve requests
* review settlement

---

# 60. Focus Management

Dialogs and sheets must:

* move focus appropriately when opened
* trap focus while necessary
* return focus to a logical element after closing

---

# 61. Color Independence

Financial status must not rely solely on color.

Bad:

```text id="xuupzi"
red = due
green = credit
```

without text.

Correct:

```text id="cf7om5"
Amount due — ৳500
Credit — ৳200
Settled
```

Color may reinforce the state.

---

# 62. Responsive Design

The application must be designed around three major layouts:

```text id="qm7m6n"
Mobile
Tablet
Desktop
```

Responsive behavior must be intentionally designed rather than allowing desktop tables to overflow arbitrarily.

---

# 63. Touch Interaction

Important controls must have touch-friendly dimensions.

Meal-entry controls are particularly important.

---

# 64. Mobile Performance

The mobile experience should avoid:

* excessive JavaScript
* oversized images
* unnecessarily large bundles
* expensive animation
* giant unpaginated tables

---

# 65. Browser Support

V1 should target current stable versions of major modern browsers:

* Chrome/Chromium
* Edge
* Firefox
* Safari

Legacy Internet Explorer support is not required.

---

# 66. Visual Stability

The UI should avoid layout shifts when:

* data loads
* cards appear
* error messages appear
* dialogs open
* calculated totals update

Skeletons/placeholders should reserve space when appropriate.

---

# 67. Error Observability

Production failures should be diagnosable.

The system should have enough logging/monitoring to determine:

* what operation failed
* whether database/server error occurred
* relevant request context
* timestamp

but must not log:

* passwords
* authentication secrets
* service-role keys
* sensitive personal data unnecessarily

---

# 68. Logging Strategy

Logs should use structured information where practical.

Example:

```text id="rgd0t7"
event:
expense_creation_failed

period_id:
...

user_id:
...

timestamp:
...
```

Do not log raw authentication headers or credentials.

---

# 69. Privacy by Design

Only collect data necessary for operating the application.

V1 does not require:

* national ID
* home address
* phone number
* bank account number
* card details

Do not add such fields merely because they might be useful in the future.

---

# 70. Data Minimization

The database should not contain unnecessary personal information.

A member generally needs:

```text id="zv2o3b"
user identity
display name
membership metadata
financial/meal records
```

not a complete personal profile.

---

# 71. Account Deletion

Because financial records may reference a user indefinitely, account deletion must not blindly cascade through historical accounting records.

The future deletion strategy should distinguish:

```text id="9wjyj5"
Authentication identity
        vs
Historical accounting identity
```

---

# 72. Anonymization Consideration

A future account-deletion workflow may replace personal display information with an anonymized label while retaining necessary financial records.

Example:

```text id="e2qhrf"
Former Member #123
```

The exact privacy/legal treatment should be finalized before implementing hard deletion.

---

# 73. Data Retention

V1 should retain:

* current periods
* closed periods
* financial records
* relevant membership history
* audit history

until the mess is intentionally archived and any applicable deletion procedure is executed.

---

# 74. Session Security

The application must:

* use secure authentication sessions
* avoid persisting secrets in insecure browser storage where unnecessary
* ensure logout invalidates application access appropriately

---

# 75. Cross-Site Security

The application should follow framework and Supabase best practices for:

* XSS prevention
* CSRF-sensitive operations
* secure cookie/session handling
* safe HTML rendering
* input escaping

The application must never inject arbitrary user-provided descriptions as raw HTML.

---

# 76. User Input Handling

All input should be validated at both:

### Client side

for immediate feedback.

### Server/database side

for security and correctness.

A client-side validation bypass must not allow invalid data into the database.

---

# 77. Rich Text

V1 should avoid rich-text inputs for financial descriptions.

Plain text is sufficient and reduces XSS complexity.

---

# 78. File Uploads

Receipt/document uploads are outside V1 core functionality.

If added later, file storage must have its own:

* access policies
* size limits
* MIME validation
* filename strategy
* retention policy

---

# 79. Internationalization

V1 may be Bangladesh-focused.

Therefore:

```text id="n3pqr2"
Currency = BDT
Locale = en-BD
Timezone = Asia/Dhaka
```

The architecture should nevertheless avoid hardcoding currency symbols throughout the codebase.

---

# 80. Date and Time

Database timestamps should use a consistent timezone-aware representation.

User-visible times should be displayed according to the mess/user timezone policy.

Because the initial target is Bangladesh:

```text id="cf6x5c"
Asia/Dhaka
```

is the default.

---

# 81. Date Boundary

A meal recorded at:

```text id="j0x1hy"
00:05
```

must not accidentally appear under the previous date because of UTC/local-time conversion errors.

Date-only accounting concepts such as meal dates should use date semantics rather than arbitrary timestamps wherever appropriate.

---

# 82. Timezone Boundary

Server and browser timezones may differ.

The system must explicitly distinguish:

### Date-only value

Example:

```text id="6yclkn"
2026-09-10
```

from:

### Timestamp

Example:

```text id="6de0a3"
2026-09-10 17:20 Asia/Dhaka
```

This distinction is essential for meals and accounting periods.

---

# 83. Data Validation

Validation shall occur at multiple layers:

```text id="p4pnlr"
UI validation
      ↓
Server/action validation
      ↓
Database constraints
      ↓
RLS authorization
```

These layers have different purposes and should not be conflated.

---

# 84. Validation Responsibility

### Frontend

User experience.

### Server/database functions

Business logic.

### Database constraints

Data invariants.

### RLS

Authorization.

---

# 85. Business Rule Centralization

Rules such as:

```text id="6wgzk5"
Can this person approve this request?
Can this expense be allocated to this participant?
Can this period be closed?
Can this member's balance be viewed?
```

should not be independently implemented differently across multiple frontend pages.

---

# 86. API Surface Minimization

The product should expose the minimum necessary mutation operations.

Instead of allowing arbitrary table writes for complex workflows, controlled database functions/server actions should be considered for:

* approval
* manager transfer
* expense + allocation creation
* period closure
* period reopening

This reduces partial-state and authorization problems.

---

# 87. Direct Table Writes

Simple records may be directly inserted through RLS-protected operations where safe.

Complex workflows should use transactional mechanisms.

---

# 88. Function Security

Any privileged PostgreSQL function must be carefully designed to avoid privilege escalation.

If a function runs with elevated privileges, it must independently verify:

* authenticated user
* mess membership
* manager authorization
* period state

A security-definer function must not become an unrestricted backdoor.

---

# 89. Database Function Search Path

Security-sensitive PostgreSQL functions should use a controlled search path and fully qualified references where appropriate to reduce object-resolution vulnerabilities.

---

# 90. SQL Injection

Dynamic SQL should be avoided unless necessary.

When dynamic SQL is unavoidable:

* parameterize inputs
* validate identifiers
* never interpolate arbitrary user strings directly

---

# 91. Frontend State Model

The frontend should distinguish:

```text id="yqp0da"
Authentication state
Mess context
Period context
Data state
Mutation state
UI state
```

Do not encode all of these as one global boolean/object.

---

# 92. Client Cache

A client-side data-fetching/cache layer may be used.

However:

> Cached data is a representation of server state, not the accounting source of truth.

After financial mutations, stale caches must be invalidated/revalidated.

---

# 93. Navigation Guard

Sensitive forms should warn users before leaving when unsaved changes exist.

---

# 94. Accessibility of Financial Tables

Large tables must remain usable on small screens.

Possible methods:

* responsive cards
* horizontal scrolling with clear affordance
* sticky labels
* condensed views

Do not force users to zoom the page to operate the application.

---

# 95. UI Feedback

Every mutation should provide a clear result:

```text id="0x1sem"
Saving...
Saved
Failed
```

Success messages should not obscure errors.

---

# 96. Destructive Action Safety

Actions such as:

* remove member
* regenerate join code
* reopen period
* close period

must have confirmation.

---

# 97. Confirmation Severity

Not all confirmations need the same intensity.

### Normal

Add expense.

No extra confirmation beyond Save.

### Important

Remove member.

Confirmation dialog.

### High-impact

Close period.

Detailed review + confirmation.

### Very high-impact

Reopen closed period.

Reason + explicit confirmation + audit.

---

# 98. Accessibility of Confirmations

Confirmation dialogs must clearly state:

* action
* consequences
* cancel option
* confirm option

Example:

> Close September 2026? After closing, ordinary meal, expense, payment, and adjustment edits will be disabled.

---

# 99. Performance of Settlement

Settlement calculation should remain responsive for expected mess sizes.

The UI should distinguish:

```text id="h0x6lq"
Calculating...
```

from:

```text id="h1tvag"
No data
```

---

# 100. Data Integrity Over Convenience

A manager should never be allowed to bypass a required accounting invariant merely because doing so produces a faster workflow.

For example:

> Save an expense even though allocations total only ৳900 for a ৳1,000 shared expense.

must not be permitted as a finalized state.

---

# 101. Draft States

Where operational convenience requires multi-step entry, draft states may be introduced.

For example:

```text id="q8q8m6"
Expense draft
 ↓
Complete allocation
 ↓
Finalized expense
```

But a draft must never silently enter final settlement calculations unless explicitly defined to do so.

---

# 102. Data Consistency During Drafts

If draft entities exist, the calculation engine must know whether they are:

```text id="p79gtr"
excluded
or
included
```

This must be explicit.

---

# 103. Production Configuration

Production should have:

* production Supabase project
* production Vercel deployment
* production environment variables
* protected main branch
* migration discipline

Development test data must not accidentally contaminate production accounting.

---

# 104. Preview Environments

Vercel preview deployments may use a development/staging backend.

A preview environment should not silently point at the production mess database unless deliberately configured.

---

# 105. Branching

Recommended:

```text id="n4f8s0"
main
 │
 └── feature/*
```

Production deployment should follow a controlled merge path.

---

# 106. CI Requirements

The repository should eventually automate:

* type checking
* linting
* unit tests
* build verification

before production deployment.

---

# 107. Type Safety

TypeScript should be used throughout the frontend/server application.

Generated database types should preferably be used so that:

* table names
* column names
* RPC parameters
* query result shapes

remain synchronized with Supabase.

---

# 108. Error Type Safety

Application code should distinguish:

```text id="l2p2d6"
validation errors
authorization errors
conflict errors
database errors
network errors
unknown errors
```

rather than showing a generic failure for everything.

---

# 109. Observability

At minimum, the project should be capable of diagnosing:

* production build failures
* database query failures
* authorization failures
* unexpected exceptions
* period-calculation errors

---

# 110. Monitoring

V1 does not require an expensive monitoring stack.

Vercel and Supabase-provided logs/observability may serve as the initial operational layer.

An external error-tracking platform can be added later.

---

# 111. Maintainability

Code should favor:

* domain-based modules
* reusable UI components
* shared validation schemas
* centralized calculation logic
* shared authorization helpers
* database migrations
* clear naming

Avoid duplicating business rules in page components.

---

# 112. Domain Separation

The codebase should conceptually separate:

```text id="6zd5wy"
auth
mess
membership
periods
meals
expenses
allocations
payments
adjustments
settlement
audit
```

This will make later schema/API changes easier.

---

# 113. No Business Logic in Presentation-Only Components

A card displaying:

> Meal rate: ৳58.50

should not independently implement how meal rate is calculated.

It consumes authoritative data.

---

# 114. Testing Requirements

Testing must cover:

### Unit

Calculation functions and utility functions.

### Integration

Database workflows.

### Authorization

RLS and role restrictions.

### End-to-end

Real user journeys.

### Regression

Previously working accounting cases.

---

# 115. Security Testing

At minimum test:

```text id="ygh70g"
Member → attempts manager mutation
Member → attempts another member's read
Mess A user → attempts Mess B access
Former member → attempts active-member mutation
Closed period → attempts edit
Non-manager → attempts manager transfer
```

All must fail.

---

# 116. Financial Testing

Must test:

* 0 meals
* 0 food cost
* one member
* many members
* fractional meals
* guest meals
* equal split
* weighted split
* fixed split
* rounding
* overpayment
* underpayment
* exact payment
* credits
* debits
* opening balance
* manager change
* mid-month membership

---

# 117. Load Testing Consideration

V1 need not include formal enterprise-scale load testing.

However, performance should be manually evaluated with realistic data:

```text id="x4z980"
30 members
30 days
3 meals/day
hundreds of expenses
hundreds of payments
multiple historical periods
```

---

# 118. Accessibility Testing

At minimum:

* keyboard navigation
* basic screen-reader sanity check
* mobile touch testing
* contrast testing
* form error testing

---

# 119. Browser Testing

Test core workflows on:

* Chromium-based browser
* Firefox
* Safari if available

Particularly:

* login
* meal grid
* expense form
* dialogs
* settlement review

---

# 120. Deployment Requirements

A production deployment must contain:

```text id="d88kqj"
Application
+
correct environment variables
+
compatible database schema
+
required RLS
+
required functions
+
required indexes
```

Deploying frontend code without the corresponding database migration should be treated as an invalid release state when the change depends on the schema.

---

# 121. Migration Safety

Database migrations must be:

* incremental
* reviewable
* reversible where practical
* tested before production

Destructive migrations require extra caution.

---

# 122. Backward Compatibility

Frontend and database changes should be coordinated.

Avoid deploying a frontend that assumes a column exists before the production migration has successfully created it.

---

# 123. Release Strategy

Recommended:

```text id="2w3z9m"
Feature development
 ↓
Local/Codespace testing
 ↓
Preview deployment
 ↓
Database migration testing
 ↓
Integration test
 ↓
Production deployment
```

---

# 124. Production Database Safeguard

The developer should not casually run experimental SQL against the production database.

Development/testing should use separate environments.

---

# 125. Recovery From Bad Migration

Migration procedures must include a recovery strategy.

Possible mechanisms:

* restore from database backup
* apply corrective migration
* revert application deployment
* reconcile data manually if necessary

Rollback must not be assumed to mean simply "run the opposite SQL," especially for destructive financial changes.

---

# 126. Domain-Level Invariants

The system must preserve:

```text id="q75ko6"
At most one manager per period.

No unauthorized financial write.

No allocation total mismatch.

No period-overlap corruption.

No duplicate active membership.

No settlement based on unauthorized records.

No divide-by-zero meal rate.

No casual mutation of closed-period accounting.
```

---

# 127. Operational Simplicity

Because the application is intended for a student mess rather than a large enterprise, technical complexity should be justified by actual risk.

Avoid introducing:

* microservices
* message brokers
* Kubernetes
* separate backend servers
* elaborate event buses

unless a later scale requirement truly demands them.

---

# 128. Recommended V1 Deployment Architecture

```text id="2a6q2v"
GitHub
  │
  ▼
Vercel
  │
  │ HTTPS
  ▼
Supabase
 ├── Auth
 ├── PostgreSQL
 ├── RLS
 ├── Functions
 └── Audit/Calculation layer
```

This minimizes the number of moving pieces.

---

# 129. Cost Constraint

V1 should be designed to operate using free-tier services where their current limits are sufficient.

However, the application must not encode assumptions that a free-tier quota is infinite.

The deployment document should identify:

* database storage constraints
* bandwidth constraints
* authentication limits
* deployment limits
* potential upgrade triggers

These are operational limits, not product rules.

---

# 130. Dependency Management

Use a minimal dependency set.

Every significant dependency should have a reason.

Avoid installing large UI/component libraries merely for one component unless doing so materially improves consistency and maintainability.

---

# 131. Package Security

Dependencies should be periodically updated and checked for known vulnerabilities.

Do not blindly apply major dependency upgrades immediately before production release.

---

# 132. Secret Management

Secrets must exist only in:

* local development environment configuration
* Codespaces secret/environment mechanism
* Vercel environment variables
* Supabase configuration

Never:

* Git
* screenshots
* documentation
* test fixtures
* browser-visible source

---

# 133. User Data in Development

Real member/payment data should not be copied into public repositories or development fixtures.

Use synthetic test data.

---

# 134. Test Data

A standard test dataset should eventually be created containing:

```text id="95rr0v"
Mess A
4 members
30 days
meal records
food expenses
shared costs
payments
credits
debits
former member
manager transfer
closed month
```

This becomes the canonical regression scenario.

---

# 135. Documentation Requirement

The project repository should contain at least:

```text id="l0wkk5"
README.md
architecture documentation
environment setup
database migration instructions
deployment instructions
testing instructions
```

The detailed product documents generated for this project should also be retained alongside the codebase or project documentation.

---

# 136. Developer Onboarding

A fresh developer should be able to determine:

1. how to install dependencies
2. how to run the app
3. how to connect Supabase
4. how to apply migrations
5. how to run tests
6. how to create local/test data
7. how to deploy

without relying on undocumented personal knowledge.

---

# 137. Definition of Technical Readiness

The product is technically ready for initial production when:

* production authentication works
* RLS is verified
* database migrations are reproducible
* financial calculations pass the test suite
* closed periods are protected
* manager-only writes are protected
* production environment variables are correctly configured
* no privileged secret reaches the browser
* basic monitoring/logging is available
* recovery procedure is documented
* core workflows pass end-to-end

---

# 138. Architecture Decisions to Carry Forward

The following are now locked as design constraints for subsequent documents:

### ADR-01

Use Supabase PostgreSQL as the authoritative persistence layer.

### ADR-02

Use Supabase Auth for authentication.

### ADR-03

Use RLS for database-level authorization.

### ADR-04

Use period-specific manager and membership context.

### ADR-05

Use exact numeric accounting rather than floating-point money.

### ADR-06

Keep financial transactions separate from derived settlement values.

### ADR-07

Preserve historical settlement state.

### ADR-08

Treat audit history as protected data.

### ADR-09

Use transactional database operations for high-risk workflows.

### ADR-10

Keep the V1 architecture monolithic/simple rather than introducing unnecessary infrastructure.

---

# 139. Technical Non-Negotiables

The following requirements should not be weakened merely for implementation convenience:

1. Members cannot bypass permissions through direct database calls.
2. Closed periods cannot be casually edited.
3. Financial calculations cannot depend on JavaScript floating-point arithmetic as final authority.
4. Shared expense allocations must reconcile.
5. Historical accounting cannot be silently rewritten.
6. Audit records cannot be manipulated by ordinary application users.
7. Manager transfer cannot create an ownerless or multiply-managed period.
8. A user from one mess cannot access another mess's records.
9. Important mutations must be atomic.
10. Credentials and privileged Supabase keys must never reach the client.

---

# 140. Relationship to the Next Documents

This document establishes the technical constraints.

The next documents translate them as follows:

```text
PRD
 │
 ▼
FRD
 │
 ▼
NFR / Technical Requirements
 │
 ▼
UI/UX Architecture
 │
 ▼
Page Specifications
 │
 ▼
Data Model / ERD
 │
 ▼
Supabase SQL Schema
 │
 ▼
RLS / Authorization
 │
 ▼
Calculation Engine
 │
 ▼
Audit & Integrity
 │
 ▼
API / Server Actions
 │
 ▼
Validation & Error Matrix
 │
 ▼
Test Plan
 │
 ▼
Deployment
 │
 ▼
Implementation Roadmap
```

No later document should contradict the invariants established here without explicitly revising the earlier requirement set.

---
