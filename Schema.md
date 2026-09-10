# Mess Manager

## Supabase PostgreSQL Schema & Migration Specification

**Document version:** 1.0
**Product version:** V1
**Database:** PostgreSQL via Supabase
**Authentication:** Supabase Auth
**Migration system:** Supabase CLI migrations
**Schema:** `public` for application data, `private` for internal security helpers
**Currency:** BDT
**Default timezone:** Asia/Dhaka

---

# 1. Purpose

This document converts the logical data model into an executable PostgreSQL schema suitable for Supabase.

It provides:

* PostgreSQL extensions
* custom enum types
* application tables
* foreign keys
* unique constraints
* check constraints
* indexes
* update timestamps
* exclusion constraints
* historical structures
* settlement snapshot structures
* audit structures
* initial database security posture

It intentionally does **not** contain the complete RLS policy implementation. That is Document 9.

It also does not contain the full accounting engine. That is Document 10.

---

# 2. Migration Strategy

Recommended repository structure:

```text
supabase/
├── config.toml
├── migrations/
│   ├── 20260910000100_initial_schema.sql
│   ├── 20260910000200_rls_helpers.sql
│   ├── 20260910000300_rls_policies.sql
│   ├── 20260910000400_calculation_engine.sql
│   ├── 20260910000500_accounting_workflows.sql
│   └── ...
└── tests/
```

The filenames are examples.

Supabase migration files conventionally live in `supabase/migrations` and are intended to be version controlled and pushed to the remote project through the CLI.

---

# 3. Recommended Initial Migration

The first migration should be:

```text
20260910000100_initial_schema.sql
```

The following SQL constitutes the proposed V1 starting schema.

---

# 4. Initial Schema SQL

```sql
-- ============================================================
-- Mess Manager
-- Initial PostgreSQL / Supabase Schema
-- Migration: 20260910000100_initial_schema.sql
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Extensions
-- ------------------------------------------------------------

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

-- ------------------------------------------------------------
-- 2. Private schema
-- ------------------------------------------------------------

create schema if not exists private;

-- ------------------------------------------------------------
-- 3. Enum types
-- ------------------------------------------------------------

create type public.mess_status as enum (
  'ACTIVE',
  'ARCHIVED'
);

create type public.join_request_status as enum (
  'PENDING',
  'APPROVED',
  'REJECTED'
);

create type public.period_status as enum (
  'DRAFT',
  'OPEN',
  'CLOSED'
);

create type public.period_membership_status as enum (
  'ACTIVE',
  'ENDED',
  'REMOVED'
);

create type public.expense_accounting_type as enum (
  'MEAL_COST',
  'SHARED_NON_MEAL',
  'OTHER_NON_MEAL'
);

create type public.allocation_method as enum (
  'NONE',
  'EQUAL',
  'WEIGHTED',
  'FIXED'
);

create type public.adjustment_type as enum (
  'CREDIT',
  'DEBIT'
);

create type public.balance_direction as enum (
  'CREDIT',
  'DUE'
);

create type public.settlement_balance_status as enum (
  'DUE',
  'CREDIT',
  'SETTLED'
);

create type public.settlement_status as enum (
  'DRAFT',
  'FINAL'
);

-- ------------------------------------------------------------
-- 4. Profiles
-- ------------------------------------------------------------

create table public.profiles (
  id uuid primary key
    references auth.users(id)
    on delete restrict,

  display_name text not null,

  avatar_url text null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint profiles_display_name_length_ck
    check (char_length(trim(display_name)) between 1 and 100)
);

-- ------------------------------------------------------------
-- 5. Messes
-- ------------------------------------------------------------

create table public.messes (
  id uuid primary key
    default gen_random_uuid(),

  name text not null,

  status public.mess_status not null
    default 'ACTIVE',

  timezone text not null
    default 'Asia/Dhaka',

  currency_code text not null
    default 'BDT',

  created_by uuid not null
    references auth.users(id)
    on delete restrict,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint messes_name_length_ck
    check (char_length(trim(name)) between 1 and 150),

  constraint mess_timezone_nonempty_ck
    check (char_length(trim(timezone)) > 0),

  constraint mess_currency_code_ck
    check (currency_code ~ '^[A-Z]{3}$')
);

-- ------------------------------------------------------------
-- 6. Join codes
-- ------------------------------------------------------------

create table public.mess_join_codes (
  id uuid primary key
    default gen_random_uuid(),

  mess_id uuid not null
    references public.messes(id)
    on delete restrict,

  code text not null,

  is_active boolean not null
    default true,

  created_at timestamptz not null
    default now(),

  revoked_at timestamptz null,

  created_by uuid not null
    references auth.users(id)
    on delete restrict,

  constraint mess_join_codes_code_format_ck
    check (
      code ~ '^[A-Z0-9]{6,8}$'
    ),

  constraint mess_join_codes_revoked_state_ck
    check (
      (is_active = true and revoked_at is null)
      or
      (is_active = false and revoked_at is not null)
    )
);

create unique index mess_join_codes_code_uq
  on public.mess_join_codes(code);

create unique index mess_join_codes_one_active_per_mess_uq
  on public.mess_join_codes(mess_id)
  where is_active = true;

create index mess_join_codes_mess_id_idx
  on public.mess_join_codes(mess_id);

-- ------------------------------------------------------------
-- 7. Join requests
-- ------------------------------------------------------------

create table public.mess_join_requests (
  id uuid primary key
    default gen_random_uuid(),

  mess_id uuid not null
    references public.messes(id)
    on delete restrict,

  user_id uuid not null
    references auth.users(id)
    on delete restrict,

  requested_at timestamptz not null
    default now(),

  status public.join_request_status not null
    default 'PENDING',

  reviewed_at timestamptz null,

  reviewed_by uuid null
    references auth.users(id)
    on delete restrict,

  rejection_reason text null,

  constraint join_requests_review_consistency_ck
    check (
      (
        status = 'PENDING'
        and reviewed_at is null
        and reviewed_by is null
      )
      or
      (
        status in ('APPROVED', 'REJECTED')
        and reviewed_at is not null
        and reviewed_by is not null
      )
    ),

  constraint join_requests_rejection_reason_ck
    check (
      status <> 'REJECTED'
      or rejection_reason is not null
  ),

  constraint join_requests_rejection_reason_length_ck
    check (
      rejection_reason is null
      or char_length(trim(rejection_reason)) between 1 and 500
    )
);

create unique index join_requests_one_pending_uq
  on public.mess_join_requests(mess_id, user_id)
  where status = 'PENDING';

create index join_requests_mess_status_idx
  on public.mess_join_requests(mess_id, status);

create index join_requests_user_id_idx
  on public.mess_join_requests(user_id);

-- ------------------------------------------------------------
-- 8. Accounting periods
-- ------------------------------------------------------------

create table public.periods (
  id uuid primary key
    default gen_random_uuid(),

  mess_id uuid not null
    references public.messes(id)
    on delete restrict,

  name text not null,

  start_date date not null,

  end_date date not null,

  status public.period_status not null
    default 'DRAFT',

  timezone text not null
    default 'Asia/Dhaka',

  currency_code text not null
    default 'BDT',

  opened_at timestamptz null,

  closed_at timestamptz null,

  reopened_at timestamptz null,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint periods_name_length_ck
    check (char_length(trim(name)) between 1 and 100),

  constraint periods_date_order_ck
    check (start_date <= end_date),

  constraint periods_timezone_nonempty_ck
    check (char_length(trim(timezone)) > 0),

  constraint periods_currency_code_ck
    check (currency_code ~ '^[A-Z]{3}$'),

  constraint periods_status_timestamp_ck
    check (
      (
        status = 'DRAFT'
        and closed_at is null
      )
      or
      (
        status = 'OPEN'
        and closed_at is null
      )
      or
      (
        status = 'CLOSED'
        and closed_at is not null
      )
    )
);

-- Prevent overlapping periods belonging to the same mess.
alter table public.periods
add constraint periods_no_overlap_excl
exclude using gist (
  mess_id with =,
  daterange(start_date, end_date, '[]') with &&
);

create index periods_mess_id_idx
  on public.periods(mess_id);

create index periods_mess_status_idx
  on public.periods(mess_id, status);

create index periods_dates_idx
  on public.periods(mess_id, start_date, end_date);

create unique index periods_one_open_per_mess_uq
  on public.periods(mess_id)
  where status = 'OPEN';

-- ------------------------------------------------------------
-- 9. Period membership
-- ------------------------------------------------------------

create table public.period_members (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  user_id uuid not null
    references auth.users(id)
    on delete restrict,

  membership_status public.period_membership_status not null
    default 'ACTIVE',

  start_date date not null,

  end_date date null,

  joined_from_request_id uuid null
    references public.mess_join_requests(id)
    on delete restrict,

  created_at timestamptz not null
    default now(),

  ended_at timestamptz null,

  constraint period_members_date_order_ck
    check (
      end_date is null
      or
      start_date <= end_date
    ),

  constraint period_membership_dates_within_period_ck
    check (
      start_date >= (
        select p.start_date
        from public.periods p
        where p.id = period_id
      )
      and
      start_date <= (
        select p.end_date
        from public.periods p
        where p.id = period_id
      )
    )
);

-- IMPORTANT:
-- PostgreSQL CHECK constraints cannot safely contain subqueries.
-- The cross-table date rule above will therefore be removed and
-- enforced by trigger/function logic in a later migration.

alter table public.period_members
drop constraint if exists period_membership_dates_within_period_ck;

create unique index period_members_one_user_per_period_uq
  on public.period_members(period_id, user_id);

create index period_members_user_id_idx
  on public.period_members(user_id);

create index period_members_period_status_idx
  on public.period_members(period_id, membership_status);

create index period_members_period_start_end_idx
  on public.period_members(period_id, start_date, end_date);

-- ------------------------------------------------------------
-- 10. Manager assignments
-- ------------------------------------------------------------

create table public.manager_assignments (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  user_id uuid not null
    references auth.users(id)
    on delete restrict,

  assigned_at timestamptz not null
    default now(),

  assigned_by uuid not null
    references auth.users(id)
    on delete restrict,

  ended_at timestamptz null,

  constraint manager_assignments_date_order_ck
    check (
      ended_at is null
      or ended_at >= assigned_at
    )
);

create unique index manager_assignments_one_current_manager_uq
  on public.manager_assignments(period_id)
  where ended_at is null;

create index manager_assignments_period_id_idx
  on public.manager_assignments(period_id);

create index manager_assignments_user_id_idx
  on public.manager_assignments(user_id);

-- ------------------------------------------------------------
-- 11. Period meal types
-- ------------------------------------------------------------

create table public.period_meal_types (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  code text not null,

  name text not null,

  weight numeric(12,4) not null
    default 1.0000,

  is_active boolean not null
    default true,

  sort_order integer not null
    default 0,

  created_at timestamptz not null
    default now(),

  constraint period_meal_types_code_ck
    check (code ~ '^[A-Z0-9_]+$'),

  constraint period_meal_types_name_length_ck
    check (char_length(trim(name)) between 1 and 100),

  constraint period_meal_types_weight_ck
    check (weight > 0),

  constraint period_meal_types_sort_order_ck
    check (sort_order >= 0)
);

create unique index period_meal_types_period_code_uq
  on public.period_meal_types(period_id, code);

create unique index period_meal_types_period_name_uq
  on public.period_meal_types(period_id, name);

create index period_meal_types_period_idx
  on public.period_meal_types(period_id);

-- ------------------------------------------------------------
-- 12. Meals
-- ------------------------------------------------------------

create table public.meals (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  period_member_id uuid not null
    references public.period_members(id)
    on delete restrict,

  meal_type_id uuid not null
    references public.period_meal_types(id)
    on delete restrict,

  meal_date date not null,

  quantity numeric(12,4) not null,

  is_guest boolean not null
    default false,

  guest_host_period_member_id uuid null
    references public.period_members(id)
    on delete restrict,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  created_by uuid not null
    references auth.users(id)
    on delete restrict,

  updated_by uuid not null
    references auth.users(id)
    on delete restrict,

  constraint meals_quantity_ck
    check (quantity > 0),

  constraint meals_guest_host_ck
    check (
      (
        is_guest = false
        and guest_host_period_member_id is null
      )
      or
      (
        is_guest = true
        and guest_host_period_member_id is not null
      )
    )
);

create unique index meals_normal_record_uq
  on public.meals(
    period_member_id,
    meal_type_id,
    meal_date
  )
  where is_guest = false;

create unique index meals_guest_record_uq
  on public.meals(
    guest_host_period_member_id,
    meal_type_id,
    meal_date
  )
  where is_guest = true;

create index meals_period_date_idx
  on public.meals(period_id, meal_date);

create index meals_member_date_idx
  on public.meals(period_member_id, meal_date);

create index meals_type_date_idx
  on public.meals(meal_type_id, meal_date);

-- ------------------------------------------------------------
-- 13. Expense categories
-- ------------------------------------------------------------

create table public.expense_categories (
  id uuid primary key
    default gen_random_uuid(),

  code text not null,

  name text not null,

  default_accounting_type public.expense_accounting_type not null,

  is_active boolean not null
    default true,

  sort_order integer not null
    default 0,

  created_at timestamptz not null
    default now(),

  constraint expense_categories_code_ck
    check (code ~ '^[A-Z0-9_]+$'),

  constraint expense_categories_name_length_ck
    check (char_length(trim(name)) between 1 and 100),

  constraint expense_categories_sort_order_ck
    check (sort_order >= 0)
);

create unique index expense_categories_code_uq
  on public.expense_categories(code);

create unique index expense_categories_name_uq
  on public.expense_categories(name);

-- ------------------------------------------------------------
-- 14. Expenses
-- ------------------------------------------------------------

create table public.expenses (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  expense_date date not null,

  description text not null,

  amount numeric(14,2) not null,

  category_id uuid not null
    references public.expense_categories(id)
    on delete restrict,

  accounting_type public.expense_accounting_type not null,

  allocation_method public.allocation_method not null
    default 'NONE',

  paid_by_period_member_id uuid not null
    references public.period_members(id)
    on delete restrict,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  created_by uuid not null
    references auth.users(id)
    on delete restrict,

  updated_by uuid not null
    references auth.users(id)
    on delete restrict,

  voided_at timestamptz null,

  void_reason text null,

  constraint expenses_description_length_ck
    check (char_length(trim(description)) between 1 and 500),

  constraint expenses_amount_ck
    check (amount > 0),

  constraint expenses_void_state_ck
    check (
      (
        voided_at is null
        and void_reason is null
      )
      or
      (
        voided_at is not null
        and void_reason is not null
      )
    ),

  constraint expenses_allocation_method_ck
    check (
      (
        accounting_type = 'MEAL_COST'
        and allocation_method = 'NONE'
      )
      or
      accounting_type <> 'MEAL_COST'
    )
);

create index expenses_period_date_idx
  on public.expenses(period_id, expense_date);

create index expenses_period_category_idx
  on public.expenses(period_id, category_id);

create index expenses_period_payer_idx
  on public.expenses(period_id, paid_by_period_member_id);

create index expenses_period_accounting_type_idx
  on public.expenses(period_id, accounting_type);

-- ------------------------------------------------------------
-- 15. Expense allocations
-- ------------------------------------------------------------

create table public.expense_allocations (
  id uuid primary key
    default gen_random_uuid(),

  expense_id uuid not null
    references public.expenses(id)
    on delete restrict,

  period_member_id uuid not null
    references public.period_members(id)
    on delete restrict,

  allocation_amount numeric(14,2) not null,

  allocation_weight numeric(12,4) null,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint expense_allocations_amount_ck
    check (allocation_amount >= 0),

  constraint expense_allocations_weight_ck
    check (
      allocation_weight is null
      or allocation_weight > 0
    )
);

create unique index expense_allocations_expense_member_uq
  on public.expense_allocations(expense_id, period_member_id);

create index expense_allocations_expense_id_idx
  on public.expense_allocations(expense_id);

create index expense_allocations_member_id_idx
  on public.expense_allocations(period_member_id);

-- ------------------------------------------------------------
-- 16. Payments
-- ------------------------------------------------------------

create table public.payments (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  period_member_id uuid not null
    references public.period_members(id)
    on delete restrict,

  payment_date date not null,

  amount numeric(14,2) not null,

  note text null,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  created_by uuid not null
    references auth.users(id)
    on delete restrict,

  updated_by uuid not null
    references auth.users(id)
    on delete restrict,

  voided_at timestamptz null,

  void_reason text null,

  constraint payments_amount_ck
    check (amount > 0),

  constraint payments_void_state_ck
    check (
      (
        voided_at is null
        and void_reason is null
      )
      or
      (
        voided_at is not null
        and void_reason is not null
      )
    ),

  constraint payments_note_length_ck
    check (
      note is null
      or char_length(trim(note)) <= 500
    )
);

create index payments_period_date_idx
  on public.payments(period_id, payment_date);

create index payments_member_date_idx
  on public.payments(period_member_id, payment_date);

-- ------------------------------------------------------------
-- 17. Adjustments
-- ------------------------------------------------------------

create table public.adjustments (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  period_member_id uuid not null
    references public.period_members(id)
    on delete restrict,

  adjustment_type public.adjustment_type not null,

  amount numeric(14,2) not null,

  adjustment_date date not null,

  reason text not null,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  created_by uuid not null
    references auth.users(id)
    on delete restrict,

  updated_by uuid not null
    references auth.users(id)
    on delete restrict,

  voided_at timestamptz null,

  void_reason text null,

  constraint adjustments_amount_ck
    check (amount > 0),

  constraint adjustments_reason_ck
    check (char_length(trim(reason)) between 1 and 500),

  constraint adjustments_void_state_ck
    check (
      (
        voided_at is null
        and void_reason is null
      )
      or
      (
        voided_at is not null
        and void_reason is not null
      )
    )
);

create index adjustments_period_date_idx
  on public.adjustments(period_id, adjustment_date);

create index adjustments_member_date_idx
  on public.adjustments(period_member_id, adjustment_date);

-- ------------------------------------------------------------
-- 18. Opening balances
-- ------------------------------------------------------------

create table public.opening_balances (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  period_member_id uuid not null
    references public.period_members(id)
    on delete restrict,

  amount numeric(14,2) not null,

  balance_direction public.balance_direction not null,

  source_period_id uuid null
    references public.periods(id)
    on delete restrict,

  created_at timestamptz not null
    default now(),

  created_by uuid null
    references auth.users(id)
    on delete restrict,

  reason text null,

  constraint opening_balances_amount_ck
    check (amount > 0),

  constraint opening_balances_reason_ck
    check (
      source_period_id is not null
      or
      reason is not null
    )
);

create unique index opening_balances_one_per_member_uq
  on public.opening_balances(period_id, period_member_id);

create index opening_balances_period_idx
  on public.opening_balances(period_id);

create index opening_balances_member_idx
  on public.opening_balances(period_member_id);

-- ------------------------------------------------------------
-- 19. Settlement snapshots
-- ------------------------------------------------------------

create table public.settlement_snapshots (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  version integer not null,

  status public.settlement_status not null
    default 'DRAFT',

  meal_units_total numeric(16,4) not null
    default 0,

  meal_cost_total numeric(16,2) not null
    default 0,

  meal_rate numeric(16,8) null,

  shared_cost_total numeric(16,2) not null
    default 0,

  payment_total numeric(16,2) not null
    default 0,

  credit_adjustment_total numeric(16,2) not null
    default 0,

  debit_adjustment_total numeric(16,2) not null
    default 0,

  closing_balance_total numeric(16,2) not null
    default 0,

  calculation_version text not null
    default '1.0',

  generated_at timestamptz not null
    default now(),

  finalized_at timestamptz null,

  constraint settlement_snapshots_version_ck
    check (version > 0),

  constraint settlement_snapshots_nonnegative_totals_ck
    check (
      meal_units_total >= 0
      and meal_cost_total >= 0
      and shared_cost_total >= 0
      and payment_total >= 0
      and credit_adjustment_total >= 0
      and debit_adjustment_total >= 0
    ),

  constraint settlement_snapshots_status_timestamp_ck
    check (
      (
        status = 'DRAFT'
        and finalized_at is null
      )
      or
      (
        status = 'FINAL'
        and finalized_at is not null
      )
    )
);

create unique index settlement_snapshots_period_version_uq
  on public.settlement_snapshots(period_id, version);

create unique index settlement_snapshots_one_final_uq
  on public.settlement_snapshots(period_id)
  where status = 'FINAL';

create index settlement_snapshots_period_idx
  on public.settlement_snapshots(period_id);

-- ------------------------------------------------------------
-- 20. Settlement member snapshots
-- ------------------------------------------------------------

create table public.settlement_member_snapshots (
  id uuid primary key
    default gen_random_uuid(),

  settlement_snapshot_id uuid not null
    references public.settlement_snapshots(id)
    on delete restrict,

  period_member_id uuid not null
    references public.period_members(id)
    on delete restrict,

  meal_units numeric(16,4) not null
    default 0,

  food_cost numeric(16,2) not null
    default 0,

  shared_cost numeric(16,2) not null
    default 0,

  credit_adjustments numeric(16,2) not null
    default 0,

  debit_adjustments numeric(16,2) not null
    default 0,

  opening_balance numeric(16,2) not null
    default 0,

  opening_balance_direction public.balance_direction null,

  payments numeric(16,2) not null
    default 0,

  total_obligation numeric(16,2) not null
    default 0,

  final_balance numeric(16,2) not null
    default 0,

  balance_status public.settlement_balance_status not null,

  generated_at timestamptz not null
    default now(),

  constraint settlement_member_snapshots_nonnegative_inputs_ck
    check (
      meal_units >= 0
      and food_cost >= 0
      and shared_cost >= 0
      and credit_adjustments >= 0
      and debit_adjustments >= 0
      and opening_balance >= 0
      and payments >= 0
    ),

  constraint settlement_member_snapshots_opening_direction_ck
    check (
      (
        opening_balance = 0
        and opening_balance_direction is null
      )
      or
      (
        opening_balance > 0
        and opening_balance_direction is not null
      )
    )
);

create unique index settlement_member_snapshots_one_member_per_snapshot_uq
  on public.settlement_member_snapshots(
    settlement_snapshot_id,
    period_member_id
  );

create index settlement_member_snapshots_member_idx
  on public.settlement_member_snapshots(period_member_id);

create index settlement_member_snapshots_snapshot_idx
  on public.settlement_member_snapshots(settlement_snapshot_id);

-- ------------------------------------------------------------
-- 21. Audit events
-- ------------------------------------------------------------

create table public.audit_events (
  id uuid primary key
    default gen_random_uuid(),

  mess_id uuid null
    references public.messes(id)
    on delete restrict,

  period_id uuid null
    references public.periods(id)
    on delete restrict,

  actor_user_id uuid null
    references auth.users(id)
    on delete restrict,

  event_type text not null,

  entity_type text not null,

  entity_id uuid null,

  old_data jsonb null,

  new_data jsonb null,

  reason text null,

  created_at timestamptz not null
    default now(),

  constraint audit_event_type_ck
    check (char_length(trim(event_type)) between 1 and 100),

  constraint audit_entity_type_ck
    check (char_length(trim(entity_type)) between 1 and 100)
);

create index audit_events_mess_time_idx
  on public.audit_events(mess_id, created_at desc);

create index audit_events_period_time_idx
  on public.audit_events(period_id, created_at desc);

create index audit_events_entity_idx
  on public.audit_events(entity_type, entity_id);

create index audit_events_actor_idx
  on public.audit_events(actor_user_id, created_at desc);

-- ------------------------------------------------------------
-- 22. Updated-at trigger function
-- ------------------------------------------------------------

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- 23. Updated-at triggers
-- ------------------------------------------------------------

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function private.set_updated_at();

create trigger messes_set_updated_at
before update on public.messes
for each row
execute function private.set_updated_at();

create trigger periods_set_updated_at
before update on public.periods
for each row
execute function private.set_updated_at();

create trigger meals_set_updated_at
before update on public.meals
for each row
execute function private.set_updated_at();

create trigger expenses_set_updated_at
before update on public.expenses
for each row
execute function private.set_updated_at();

create trigger expense_allocations_set_updated_at
before update on public.expense_allocations
for each row
execute function private.set_updated_at();

create trigger payments_set_updated_at
before update on public.payments
for each row
execute function private.set_updated_at();

create trigger adjustments_set_updated_at
before update on public.adjustments
for each row
execute function private.set_updated_at();

-- ------------------------------------------------------------
-- 24. Seed default expense categories
-- ------------------------------------------------------------

insert into public.expense_categories (
  code,
  name,
  default_accounting_type,
  sort_order
)
values
  ('GROCERIES', 'Groceries', 'MEAL_COST', 10),
  ('FOOD', 'Food', 'MEAL_COST', 20),
  ('GAS', 'Cooking Gas', 'OTHER_NON_MEAL', 30),
  ('ELECTRICITY', 'Electricity', 'SHARED_NON_MEAL', 40),
  ('WATER', 'Water', 'SHARED_NON_MEAL', 50),
  ('INTERNET', 'Internet', 'SHARED_NON_MEAL', 60),
  ('CLEANING', 'Cleaning', 'SHARED_NON_MEAL', 70),
  ('MAINTENANCE', 'Maintenance', 'SHARED_NON_MEAL', 80),
  ('RENT', 'Rent', 'SHARED_NON_MEAL', 90),
  ('HOUSEHOLD', 'Household Supplies', 'SHARED_NON_MEAL', 100),
  ('OTHER', 'Other', 'OTHER_NON_MEAL', 999)
on conflict (code) do nothing;

-- ------------------------------------------------------------
-- 25. Initial RLS posture
-- ------------------------------------------------------------
-- RLS is enabled now.
-- Policies are intentionally added by the dedicated RLS migration.

alter table public.profiles enable row level security;
alter table public.messes enable row level security;
alter table public.mess_join_codes enable row level security;
alter table public.mess_join_requests enable row level security;
alter table public.periods enable row level security;
alter table public.period_members enable row level security;
alter table public.manager_assignments enable row level security;
alter table public.period_meal_types enable row level security;
alter table public.meals enable row level security;
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_allocations enable row level security;
alter table public.payments enable row level security;
alter table public.adjustments enable row level security;
alter table public.opening_balances enable row level security;
alter table public.settlement_snapshots enable row level security;
alter table public.settlement_member_snapshots enable row level security;
alter table public.audit_events enable row level security;

-- No broad anon/authenticated grants are intentionally defined here.
-- The RLS/grant migration will establish the exact client permissions.

commit;
```

---

# 5. Important Correction to the Initial SQL

The migration above deliberately demonstrates and then removes a cross-table `CHECK` constraint because PostgreSQL `CHECK` constraints are not the right mechanism for queries against another table.

The actual migration should therefore simply omit that attempted constraint rather than include the create/drop pair in a polished final migration.

The clean production version of the `period_members` table is:

```sql
create table public.period_members (
  id uuid primary key
    default gen_random_uuid(),

  period_id uuid not null
    references public.periods(id)
    on delete restrict,

  user_id uuid not null
    references auth.users(id)
    on delete restrict,

  membership_status public.period_membership_status not null
    default 'ACTIVE',

  start_date date not null,

  end_date date null,

  joined_from_request_id uuid null
    references public.mess_join_requests(id)
    on delete restrict,

  created_at timestamptz not null
    default now(),

  ended_at timestamptz null,

  constraint period_members_date_order_ck
    check (
      end_date is null
      or start_date <= end_date
    )
);

create unique index period_members_one_user_per_period_uq
  on public.period_members(period_id, user_id);

create index period_members_user_id_idx
  on public.period_members(user_id);

create index period_members_period_status_idx
  on public.period_members(period_id, membership_status);

create index period_members_period_start_end_idx
  on public.period_members(period_id, start_date, end_date);
```

Membership-date validity will instead be implemented as a trusted database function/trigger.

---

# 6. Why the Schema Uses `numeric`

The schema deliberately uses PostgreSQL `numeric` rather than floating-point types for money and meal calculations.

Examples:

```text
numeric(14,2)
numeric(16,2)
numeric(16,4)
numeric(16,8)
```

The distinction matters:

### Monetary amount

```text
numeric(14,2)
```

### Meal quantity

```text
numeric(12,4)
```

### Meal weight

```text
numeric(12,4)
```

### Meal rate

```text
numeric(16,8)
```

The calculation engine can therefore retain precision before final display rounding.

---

# 7. Why `meal_rate` Has More Precision

Suppose:

```text
food cost = ৳10,000
meal units = 171
```

The exact rate is:

```text
৳58.479532...
```

The application may display:

```text
৳58.48
```

but intermediate calculations should not necessarily be performed using the already-rounded display value.

The calculation engine will formally define this in Document 10.

---

# 8. Why Meal Types Are Period-Specific

The schema deliberately uses:

```text
period_meal_types
```

instead of only a global meal-type table.

Therefore:

```text
September
Breakfast = 1
Lunch     = 1
Dinner    = 1
```

can remain independent from:

```text
October
Breakfast = 0.5
Lunch     = 1
Dinner    = 1
```

Historical calculations are therefore protected from current settings.

---

# 9. Why `period_id` Is Explicit on Meals

The meal contains both:

```text
period_id
period_member_id
```

although the period could theoretically be derived from the member.

This is intentional.

It allows:

* easier querying
* stronger validation
* more efficient RLS
* simpler indexing
* explicit accounting context

However, the database must later validate that:

```text
meal.period_id
=
period_member.period_id
=
meal_type.period_id
```

This cross-table integrity belongs in the function/trigger layer.

---

# 10. Why `period_id` Is Explicit on Expenses

The same reasoning applies.

An expense must belong explicitly to an accounting period.

The application should never infer its period solely from the date after the record has been created.

---

# 11. Why `allocation_method` Is Stored

Suppose a historical expense was split using:

```text
WEIGHTED
```

and the current UI default later becomes:

```text
EQUAL
```

The historical expense must still be interpretable.

The `allocation_method` therefore belongs to the expense itself.

---

# 12. Why Allocation Weights Are Stored

For weighted allocation:

```text
A = 2
B = 1
C = 1
```

the resulting allocation can be explained later.

If the system stored only:

```text
A = ৳500
B = ৳250
C = ৳250
```

it would lose how those figures were generated.

Keeping the weight on the allocation record improves auditability.

---

# 13. Why Fixed Allocations Store Only Amounts

For:

```text
FIXED
```

the manager directly defines:

```text
A = ৳300
B = ৳250
C = ৳450
```

No weight is needed.

---

# 14. Why Expense Allocations Use Positive Amounts

Do not represent:

```text
A = -250
```

for an allocation.

An allocation is always a positive cost share.

Credits/debits belong in the adjustment system.

---

# 15. Why Payments Use Positive Amounts

A payment is always:

```text > 0
```

A reversal should not be represented by manually entering:

```text -৳500
```

Instead, a future correction/void/refund mechanism should be used.

---

# 16. Why Adjustments Have a Type

Instead of:

```text
amount = -100
```

use:

```text
type = CREDIT
amount = 100
```

or:

```text
type = DEBIT
amount = 100
```

This makes the meaning explicit.

---

# 17. Why Opening Balance Has Direction

Similarly:

```text
amount = 250
direction = CREDIT
```

is clearer than:

```text
amount = -250
```

The presentation/accounting layer can convert this into a mathematical representation.

---

# 18. Why Expenses Have `voided_at`

Financial data should not be casually deleted.

A mistaken expense can eventually be changed into:

```text
voided_at = timestamp
void_reason = 'Duplicate purchase entry'
```

The record remains available for audit.

The calculation engine must exclude voided expenses from active accounting.

---

# 19. Why Payments Have the Same Concept

A payment can also be entered incorrectly.

For example:

```text
৳5,000
```

was accidentally entered instead of:

```text
৳500
```

A controlled void/correction mechanism is safer than destroying the payment row.

---

# 20. Why Settlement Snapshots Are Separate

Operational data answers:

> What happened?

Settlement snapshots answer:

> What did the system finalize as the result?

Those are different concerns.

---

# 21. Settlement Versioning

Example:

```text
September 2026

Snapshot 1
FINAL

Period reopened

Snapshot 2
FINAL
```

This allows historical audit of the fact that the settlement changed.

---

# 22. Calculation Version

The snapshot contains:

```text
calculation_version
```

Example:

```text
1.0
```

This means:

> These figures were generated by calculation rules version 1.0.

This becomes valuable if the application later changes rounding or allocation logic.

---

# 23. One Final Snapshot Constraint

The schema permits multiple snapshot versions but only one:

```text
status = FINAL
```

per period.

The reopening workflow can first move the current state out of finalized status according to the later accounting design, or create a new version after reopening.

The exact lifecycle will be defined in Documents 10 and 11.

---

# 24. Why Audit Events Are Not Automatically Deleted

Every audit record references the event context but does not depend on the continued existence of an active member.

Thus:

```text
member leaves
```

does not erase:

```text
member approved
member changed meals
member received adjustment
```

from history.

---

# 25. Why `actor_user_id` Is Nullable

Most audit events will have an authenticated actor.

However, certain future system-generated events may not map cleanly to a human user.

Example:

```text
automated settlement process
```

The system can then use:

```text actor_user_id = NULL
```

while recording the event type.

---

# 26. Default Expense Categories

The initial seed contains:

```text
GROCERIES
FOOD
GAS
ELECTRICITY
WATER
INTERNET
CLEANING
MAINTENANCE
RENT
HOUSEHOLD
OTHER
```

The seed intentionally gives categories a **default accounting type**, but the actual expense stores its own `accounting_type`.

This is important.

Changing the category configuration later must not silently change historical expense accounting.

---

# 27. Category vs Accounting Treatment

A category answers:

> What kind of expense is this?

Accounting treatment answers:

> How should this expense affect settlement?

Therefore these concepts remain distinct.

Example:

```text
Category:
OTHER

Accounting treatment:
MEAL_COST
```

is possible if a manager deliberately chooses it.

---

# 28. Why `currency_code` Exists on Both Mess and Period

Mess-level currency provides the default.

Period-level currency preserves historical context.

If future versions permit a configuration change, a historical period does not automatically change currency semantics.

V1 should normally use:

```text BDT
```

for both.

---

# 29. Why `timezone` Exists on Both Mess and Period

Same principle.

Mess timezone is the default.

Period timezone preserves the context under which date/time-based operations occurred.

---

# 30. Period Overlap Protection

The schema uses a PostgreSQL exclusion constraint:

```sql
exclude using gist (
  mess_id with =,
  daterange(start_date, end_date, '[]') with &&
)
```

This is stronger than relying only on application validation.

It prevents a race condition in which:

```text
Request A checks "no overlap"
Request B checks "no overlap"
Request A inserts
Request B inserts
```

and both incorrectly succeed.

The database makes the final decision.

---

# 31. Why `btree_gist` Is Included

The exclusion constraint combines:

```text
mess_id equality
```

with:

```text
date-range overlap
```

The `btree_gist` extension supplies the required GiST operator support for the equality component.

---

# 32. Active Period Constraint

The partial unique index:

```sql
create unique index periods_one_open_per_mess_uq
  on public.periods(mess_id)
  where status = 'OPEN';
```

prevents two simultaneously open periods for one mess.

This directly implements an important business invariant.

---

# 33. One Manager Constraint

The partial unique index:

```sql
create unique index manager_assignments_one_current_manager_uq
  on public.manager_assignments(period_id)
  where ended_at is null;
```

ensures one current manager assignment.

Historical assignments can coexist.

---

# 34. One Pending Join Request

This index:

```sql
create unique index join_requests_one_pending_uq
  on public.mess_join_requests(mess_id, user_id)
  where status = 'PENDING';
```

prevents duplicate pending requests.

---

# 35. One Current Join Code

This index:

```sql
create unique index mess_join_codes_one_active_per_mess_uq
```

means:

```text
Mess
 ├── old code → revoked
 └── current code → active
```

rather than multiple simultaneously valid codes.

---

# 36. One Period Membership

The database uses:

```text
UNIQUE(period_id, user_id)
```

so one user has one period-membership row per period.

This deliberately does not support multiple membership episodes within the same period in V1.

That keeps accounting significantly simpler.

---

# 37. One Meal Record

The partial unique indexes distinguish:

### Member meal

```text
period_member
+
meal type
+
date
```

from:

### Guest meal

```text
host
+
meal type
+
date
```

Therefore multiple guest meal quantities can later be represented as quantity rather than creating ambiguous duplicate rows.

---

# 38. Why Guest Meal Quantity Is Aggregated

Instead of:

```text
Guest 1
Guest 2
Guest 3
```

V1 can store:

```text
host A
lunch
10 Sep
quantity = 3
```

This is sufficient for accounting while remaining simple.

---

# 39. Cross-Entity Integrity Still Required

The schema intentionally does not attempt to enforce every rule using basic foreign keys.

These relationships must later be validated:

```text
meal.period_id
    = period_member.period_id

meal.meal_type_id
    belongs to same period

expense.paid_by_period_member_id
    belongs to same period

allocation.period_member_id
    belongs to expense period

payment.period_member_id
    belongs to payment period

adjustment.period_member_id
    belongs to adjustment period
```

These require controlled database functions/triggers.

---

# 40. Why Not Encode Everything Using Triggers Immediately?

Because there is a distinction between:

### Structural integrity

Foreign keys/constraints.

and:

### Business workflows

Approval, manager transfer, allocation calculation, period closure.

Business workflows are safer when exposed through explicit database functions rather than a large collection of hidden trigger side effects.

---

# 41. Trigger Scope

The first migration only uses a lightweight `updated_at` trigger.

Business-event triggers will be deliberately introduced later.

This keeps the base schema predictable.

---

# 42. Profiles and Auth

`profiles.id` is directly tied to:

```text
auth.users.id
```

This gives the application a simple identity mapping.

No password information is duplicated.

---

# 43. User Deletion Protection

The schema uses:

```sql
on delete restrict
```

for historical relationships.

This intentionally prevents:

```text
delete auth user
→ delete financial history
```

The final account-deletion/anonymization process will be defined separately.

---

# 44. Why `on delete restrict` Is Used Heavily

Financial and historical records must not disappear through accidental cascading deletion.

This is a major safety property.

---

# 45. Tables Intentionally Not Cascaded

The following records should not disappear merely because a parent is removed:

* meals
* expenses
* allocations
* payments
* adjustments
* periods
* settlements
* audit events

---

# 46. Table Classification

## Identity

```text
profiles
```

## Mess

```text
messes
mess_join_codes
mess_join_requests
```

## Period

```text
periods
period_members
manager_assignments
period_meal_types
```

## Operations

```text
meals
expenses
expense_categories
expense_allocations
payments
adjustments
opening_balances
```

## Finalization

```text
settlement_snapshots
settlement_member_snapshots
```

## Governance

```text
audit_events
```

---

# 47. Expected Table Growth

The biggest tables are expected to be:

```text
meals
audit_events
expenses
payments
expense_allocations
```

Indexes therefore prioritize:

* period
* member
* date
* entity

---

# 48. RLS-Oriented Indexing

Supabase specifically recommends indexing columns frequently used in RLS predicates because policy evaluation can otherwise become expensive as data grows.

The schema therefore intentionally indexes:

```text
user_id
period_id
mess_id
period_member_id
```

where the authorization layer will frequently need them.

---

# 49. Security Posture

The migration enables RLS on application tables before application use.

This is intentional.

Supabase documents that policies and grants work together: enabling RLS does not itself define which operations are allowed, and table privileges also matter.

Therefore the production sequence is:

```text
Schema
 ↓
RLS enabled
 ↓
Grants/policies added
 ↓
Application access enabled
```

---

# 50. Why No Permissive Policies Are Added Here

A schema migration that creates:

```sql
using (true)
```

policies simply to make development convenient creates a dangerous gap if it is accidentally deployed.

The policy layer deserves its own deliberate migration.

---

# 51. Private Schema

The `private` schema is reserved for internal helper functions and implementation details that should not be part of the public Data API surface.

Supabase warns that `security definer` functions should not be casually exposed through an exposed schema, and recommends setting `search_path = ''` and schema-qualifying objects when using them.

The initial `set_updated_at()` helper is deliberately:

```text
security invoker
```

because it requires no elevated privilege.

---

# 52. Security-Definer Functions

Later functions such as RLS helper functions may require `security definer`.

When that happens, they should follow the documented pattern:

```sql
security definer
set search_path = ''
```

with fully qualified object references.

Supabase specifically recommends this approach to reduce privilege/search-path risks.

---

# 53. No Calculation Functions Yet

This schema deliberately does not implement:

```text
calculate_member_statement()
calculate_period_summary()
close_period()
```

yet.

Those functions are tightly coupled to the final accounting rules.

They will be introduced only after the formal calculation specification.

---

# 54. No RLS Policies Yet

Likewise, this document does not attempt to write all policies.

Document 9 should formally specify:

```text
SELECT
INSERT
UPDATE
DELETE
```

for every table and role.

Supabase recommends defining policies separately for the operations that need to be allowed rather than hiding everything under a broad `FOR ALL` policy.

---

# 55. No General-Purpose Admin Role

The V1 database does not add:

```text
admin
superadmin
owner
```

because those roles were not required by the product.

The core authorization model remains:

```text
authenticated
→ mess member
→ period member
→ current manager
```

---

# 56. Expected Seed Meal Types

Meal types are period-specific, so they should be created when a period is initialized.

Default seed for a newly created period:

```text
BREAKFAST
LUNCH
DINNER
```

with:

```text
weight = 1
```

The period-creation function will create them automatically.

---

# 57. Expected Initial Mess Creation

Creating a mess should eventually be implemented as one transaction:

```text
messes
↓
initial period
↓
period member
↓
manager assignment
↓
period meal types
↓
join code
```

That function belongs to the later workflow migration.

---

# 58. Expected New Period Creation

Similarly:

```text
new period
↓
copy eligible configuration
↓
create continuing members
↓
assign manager
↓
create meal types
↓
carry forward balances if configured
```

must be handled transactionally.

Supabase recommends database functions for data-intensive operations that execute within PostgreSQL, making them suitable for these multi-row operations.

---

# 59. Expected Expense Creation

Normal application flow should eventually call a controlled operation:

```text
create expense
```

which can:

1. verify manager
2. validate period
3. create expense
4. calculate allocation if applicable
5. create allocation rows
6. verify reconciliation
7. write audit event

---

# 60. Expected Period Closure

Similarly:

```text
close period
```

should eventually:

1. verify manager
2. verify open period
3. run blockers
4. calculate final results
5. create snapshot
6. finalize snapshot
7. close period
8. audit action

This should be atomic.

---

# 61. Schema-Level Invariants Achieved by This Migration

The initial schema already protects several major invariants:

```text
✓ unique active join code per mess
✓ one pending request per user/mess
✓ no overlapping periods
✓ one open period per mess
✓ one period membership per user
✓ one current manager per period
✓ one allocation per expense/member
✓ positive monetary amounts
✓ positive meal quantity
✓ positive meal weights
✓ no arbitrary deletion cascades
✓ RLS enabled
✓ exact numeric accounting fields
```

---

# 62. Invariants Still Requiring Database Functions/Triggers

The next implementation layer must enforce:

```text
• manager must be period member
• meal member must belong to meal period
• meal type must belong to meal period
• meal date must be inside period
• meal date must fall within membership dates
• guest host must be eligible
• expense payer must belong to expense period
• expense date must be inside period
• allocation member must belong to expense period
• allocation total must equal expense amount
• payment member must belong to payment period
• payment date must be inside period
• adjustment member/date must be valid
• closed period cannot be mutated
• only manager can execute management workflows
• settlement member snapshot must match settlement period
• finalized snapshots must be immutable
```

---

# 63. Final Production Migration Recommendation

For the actual repository, I recommend splitting the conceptual schema into several migrations rather than making one enormous SQL file.

Recommended sequence:

```text
001_initial_schema.sql
        ↓
002_integrity_functions.sql
        ↓
003_rls_helpers.sql
        ↓
004_rls_policies.sql
        ↓
005_calculation_engine.sql
        ↓
006_accounting_workflows.sql
        ↓
007_audit_triggers.sql
        ↓
008_reporting_views.sql
        ↓
009_seed_defaults.sql
```

This makes failures easier to isolate and migrations easier to review.

---

# 64. Supabase CLI Workflow

The intended development workflow is:

```bash
supabase migration new initial_schema
```

Write the migration.

Then test locally:

```bash
supabase db reset
```

After validation, link the project and deploy:

```bash
supabase link
supabase db push
```

These are aligned with Supabase's documented migration workflow.

---

# 65. Do Not Make Production Schema Changes Manually

Once the migration workflow is established, production changes should go through migrations.

Supabase explicitly warns that manually changing the remote schema can desynchronize migration history and cause deployment problems.

---

# 66. Schema Acceptance Criteria

The database schema is acceptable for V1 when:

```text
✓ all entities from the approved ERD exist
✓ foreign keys are correctly defined
✓ historical records cannot cascade-delete
✓ period overlap is prevented
✓ one open period per mess is enforced
✓ one manager per period is enforced
✓ exact decimal types are used
✓ critical uniqueness constraints exist
✓ audit structure exists
✓ settlement snapshot structure exists
✓ RLS is enabled
✓ schema can be recreated from migrations
✓ database reset succeeds
```

---

# 67. Final Data Architecture

The resulting physical architecture is:

```text
AUTH.USERS
     │
     ▼
PROFILES
     │
     ▼
MESSES
 ├── MESS_JOIN_CODES
 ├── MESS_JOIN_REQUESTS
 └── PERIODS
       │
       ├── PERIOD_MEMBERS
       │      ├── MEALS
       │      ├── PAYMENTS
       │      ├── ADJUSTMENTS
       │      └── OPENING_BALANCES
       │
       ├── MANAGER_ASSIGNMENTS
       │
       ├── PERIOD_MEAL_TYPES
       │
       └── EXPENSES
              │
              └── EXPENSE_ALLOCATIONS

PERIODS
   │
   └── SETTLEMENT_SNAPSHOTS
            │
            └── SETTLEMENT_MEMBER_SNAPSHOTS

ALL MAJOR ENTITIES
   │
   └── AUDIT_EVENTS
```

---

# 68. Important Implementation Boundary

This schema should **not yet be treated as the finished security/accounting layer**.

It is the structural foundation.

The next layers are essential:

```text
Schema
 ↓
Cross-row integrity
 ↓
RLS
 ↓
Calculation engine
 ↓
Accounting workflows
 ↓
Audit triggers
 ↓
Reporting views
```

Only after those layers exist should the frontend be granted production write access.
