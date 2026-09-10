-- ============================================================================
-- MESS MANAGER — SUPABASE / POSTGRESQL DATABASE SCHEMA v2
-- ============================================================================
-- Purpose:
--   Authoritative consolidated schema for the Mess Manager application.
--
-- Stack assumptions:
--   - Supabase PostgreSQL
--   - Supabase Auth (auth.users)
--   - Next.js / Vercel application layer
--
-- Design principles:
--   1. A Mess Period is the accounting boundary.
--   2. Manager assignment is period-specific, not a permanent global role.
--   3. Historical accounting must remain reproducible after membership,
--      manager, or configuration changes.
--   4. Money uses NUMERIC, never floating-point types.
--   5. Source records are corrected/voided rather than silently rewritten in
--      ways that destroy the accounting history.
--   6. Closed periods are immutable except through an explicit reopen flow.
--   7. High-risk mutations should be exposed through controlled RPC/functions
--      and not arbitrary client-side CRUD.
--   8. RLS is mandatory for application tables.
--
-- IMPORTANT:
--   This file is the consolidated structural baseline. Calculation RPCs such
--   as close_period() and reporting views can be added in the next migration
--   once the application workflow is implemented. Do not improvise a second
--   schema in the frontend.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- Extensions
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ----------------------------------------------------------------------------
-- Private schema for security-sensitive helpers.
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS private;

-- ----------------------------------------------------------------------------
-- Enumerations
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mess_status') THEN
    CREATE TYPE public.mess_status AS ENUM ('ACTIVE', 'ARCHIVED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'join_request_status') THEN
    CREATE TYPE public.join_request_status AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'period_status') THEN
    CREATE TYPE public.period_status AS ENUM ('DRAFT', 'OPEN', 'CLOSED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'period_membership_status') THEN
    CREATE TYPE public.period_membership_status AS ENUM ('ACTIVE', 'ENDED', 'REMOVED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'expense_accounting_type') THEN
    CREATE TYPE public.expense_accounting_type AS ENUM (
      'MEAL_COST',
      'SHARED_NON_MEAL',
      'OTHER_NON_MEAL'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'allocation_method') THEN
    CREATE TYPE public.allocation_method AS ENUM ('NONE', 'EQUAL', 'WEIGHTED', 'FIXED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'adjustment_type') THEN
    CREATE TYPE public.adjustment_type AS ENUM ('CREDIT', 'DEBIT');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'balance_direction') THEN
    CREATE TYPE public.balance_direction AS ENUM ('DUE', 'CREDIT');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'settlement_balance_status') THEN
    CREATE TYPE public.settlement_balance_status AS ENUM ('DUE', 'CREDIT', 'SETTLED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'settlement_status') THEN
    CREATE TYPE public.settlement_status AS ENUM ('DRAFT', 'FINAL');
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- Shared domains / utility functions
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.current_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT auth.uid();
$$;

-- ----------------------------------------------------------------------------
-- PROFILES
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 120),
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- MESSES
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 160),
  currency_code char(3) NOT NULL DEFAULT 'BDT' CHECK (currency_code ~ '^[A-Z]{3}$'),
  status public.mess_status NOT NULL DEFAULT 'ACTIVE',
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messes_created_by ON public.messes(created_by);
CREATE INDEX IF NOT EXISTS idx_messes_status ON public.messes(status);

CREATE TRIGGER trg_messes_updated_at
BEFORE UPDATE ON public.messes
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- MESS JOIN CODES
-- One active code per mess. Codes are revocable/regeneratable.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mess_join_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mess_id uuid NOT NULL REFERENCES public.messes(id) ON DELETE CASCADE,
  code_hash text NOT NULL UNIQUE,
  label text,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_mess_one_active_join_code
ON public.mess_join_codes(mess_id)
WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_join_codes_mess
ON public.mess_join_codes(mess_id);

-- ----------------------------------------------------------------------------
-- JOIN REQUESTS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mess_join_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mess_id uuid NOT NULL REFERENCES public.messes(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  requested_with_code_id uuid REFERENCES public.mess_join_codes(id) ON DELETE SET NULL,
  status public.join_request_status NOT NULL DEFAULT 'PENDING',
  requested_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  rejection_reason text
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_pending_join_request_per_user_mess
ON public.mess_join_requests(mess_id, user_id)
WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_join_requests_mess_status
ON public.mess_join_requests(mess_id, status);

CREATE INDEX IF NOT EXISTS idx_join_requests_user
ON public.mess_join_requests(user_id);

-- ----------------------------------------------------------------------------
-- PERIODS
-- A period is the accounting boundary. Dates are inclusive.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mess_id uuid NOT NULL REFERENCES public.messes(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 100),
  start_date date NOT NULL,
  end_date date NOT NULL,
  status public.period_status NOT NULL DEFAULT 'DRAFT',
  closed_at timestamptz,
  closed_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reopened_at timestamptz,
  reopened_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reopen_reason text,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_date <= end_date),
  CHECK (
    (status = 'CLOSED' AND closed_at IS NOT NULL AND closed_by IS NOT NULL)
    OR status <> 'CLOSED'
  )
);

-- Date-range overlap protection. DRAFT periods are also prevented from
-- overlapping because they represent reserved accounting boundaries.
ALTER TABLE public.periods
  DROP CONSTRAINT IF EXISTS periods_no_overlap;

ALTER TABLE public.periods
  ADD CONSTRAINT periods_no_overlap
  EXCLUDE USING gist (
    mess_id WITH =,
    daterange(start_date, end_date, '[]') WITH &&
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_open_period_per_mess
ON public.periods(mess_id)
WHERE status = 'OPEN';

CREATE INDEX IF NOT EXISTS idx_periods_mess_dates
ON public.periods(mess_id, start_date DESC, end_date DESC);

CREATE TRIGGER trg_periods_updated_at
BEFORE UPDATE ON public.periods
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- PERIOD MEMBERS
-- Membership is intentionally period-specific so historical accounting is
-- insulated from later membership changes.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.period_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  membership_status public.period_membership_status NOT NULL DEFAULT 'ACTIVE',
  joined_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  removed_at timestamptz,
  removal_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    membership_status = 'ACTIVE'
    OR ended_at IS NOT NULL
    OR removed_at IS NOT NULL
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_period_membership_user
ON public.period_members(period_id, user_id);

CREATE INDEX IF NOT EXISTS idx_period_members_period_status
ON public.period_members(period_id, membership_status);

CREATE INDEX IF NOT EXISTS idx_period_members_user
ON public.period_members(user_id);

CREATE TRIGGER trg_period_members_updated_at
BEFORE UPDATE ON public.period_members
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- MANAGER ASSIGNMENTS
-- A manager is a period-scoped accounting authority.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.manager_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  period_member_id uuid NOT NULL REFERENCES public.period_members(id) ON DELETE RESTRICT,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  assigned_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  ended_at timestamptz,
  ended_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reason text
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_current_manager_per_period
ON public.manager_assignments(period_id)
WHERE ended_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_manager_assignments_period
ON public.manager_assignments(period_id, assigned_at DESC);

CREATE INDEX IF NOT EXISTS idx_manager_assignments_member
ON public.manager_assignments(period_member_id);

-- ----------------------------------------------------------------------------
-- PERIOD MEAL TYPES
-- Meal weights belong to the period, not globally, for reproducibility.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.period_meal_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  code text NOT NULL CHECK (code ~ '^[a-z0-9_-]{1,40}$'),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  weight numeric(12,4) NOT NULL CHECK (weight > 0),
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_period_meal_type_code
ON public.period_meal_types(period_id, code);

CREATE INDEX IF NOT EXISTS idx_period_meal_types_period
ON public.period_meal_types(period_id, sort_order, name);

CREATE TRIGGER trg_period_meal_types_updated_at
BEFORE UPDATE ON public.period_meal_types
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- MEALS
-- quantity can represent multiple portions of a meal type on one day.
-- A guest meal is represented separately below so it can be accounted for
-- explicitly without assigning a mess membership.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  period_member_id uuid NOT NULL REFERENCES public.period_members(id) ON DELETE RESTRICT,
  meal_type_id uuid NOT NULL REFERENCES public.period_meal_types(id) ON DELETE RESTRICT,
  meal_date date NOT NULL,
  quantity numeric(12,4) NOT NULL CHECK (quantity > 0),
  note text,
  entered_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_member_meal_per_date_type
ON public.meals(period_id, period_member_id, meal_type_id, meal_date);

CREATE INDEX IF NOT EXISTS idx_meals_period_date
ON public.meals(period_id, meal_date);

CREATE INDEX IF NOT EXISTS idx_meals_member_date
ON public.meals(period_member_id, meal_date);

CREATE TRIGGER trg_meals_updated_at
BEFORE UPDATE ON public.meals
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- GUEST MEALS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.guest_meals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  host_period_member_id uuid NOT NULL REFERENCES public.period_members(id) ON DELETE RESTRICT,
  meal_type_id uuid NOT NULL REFERENCES public.period_meal_types(id) ON DELETE RESTRICT,
  meal_date date NOT NULL,
  quantity numeric(12,4) NOT NULL CHECK (quantity > 0),
  guest_label text,
  charge_to_host boolean NOT NULL DEFAULT true,
  note text,
  entered_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_guest_meals_period_date
ON public.guest_meals(period_id, meal_date);

CREATE INDEX IF NOT EXISTS idx_guest_meals_host
ON public.guest_meals(host_period_member_id, meal_date);

CREATE TRIGGER trg_guest_meals_updated_at
BEFORE UPDATE ON public.guest_meals
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- EXPENSE CATEGORIES
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.expense_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mess_id uuid NOT NULL REFERENCES public.messes(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 100),
  accounting_type public.expense_accounting_type NOT NULL,
  default_allocation_method public.allocation_method NOT NULL DEFAULT 'NONE',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_category_name_per_mess
ON public.expense_categories(mess_id, lower(name));

CREATE INDEX IF NOT EXISTS idx_expense_categories_mess_active
ON public.expense_categories(mess_id, is_active);

CREATE TRIGGER trg_expense_categories_updated_at
BEFORE UPDATE ON public.expense_categories
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- EXPENSES
-- paid_by_period_member_id is the key accounting field for vendor advances.
-- It means this member actually paid the vendor for the expense.
-- This is NOT the same thing as a member payment into the mess.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES public.expense_categories(id) ON DELETE RESTRICT,
  expense_date date NOT NULL,
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 1 AND 200),
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  accounting_type public.expense_accounting_type NOT NULL,
  allocation_method public.allocation_method NOT NULL DEFAULT 'NONE',
  paid_by_period_member_id uuid REFERENCES public.period_members(id) ON DELETE RESTRICT,
  note text,
  receipt_url text,
  voided_at timestamptz,
  voided_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  void_reason text,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    voided_at IS NULL
    OR (voided_by IS NOT NULL AND void_reason IS NOT NULL AND length(btrim(void_reason)) > 0)
  ),
  CHECK (
    accounting_type = 'MEAL_COST'
    OR allocation_method IN ('EQUAL', 'WEIGHTED', 'FIXED', 'NONE')
  )
);

CREATE INDEX IF NOT EXISTS idx_expenses_period_date
ON public.expenses(period_id, expense_date DESC);

CREATE INDEX IF NOT EXISTS idx_expenses_period_accounting
ON public.expenses(period_id, accounting_type, voided_at);

CREATE INDEX IF NOT EXISTS idx_expenses_paid_by_member
ON public.expenses(paid_by_period_member_id);

CREATE TRIGGER trg_expenses_updated_at
BEFORE UPDATE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- EXPENSE ALLOCATIONS
-- Explicitly stores the final allocation amount per member for shared costs.
-- For EQUAL/WEIGHTED allocations, the application/DB function computes the
-- exact residual distribution. For FIXED, the user supplies the amounts.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.expense_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id uuid NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
  period_member_id uuid NOT NULL REFERENCES public.period_members(id) ON DELETE RESTRICT,
  allocation_amount numeric(14,2) NOT NULL CHECK (allocation_amount >= 0),
  allocation_weight numeric(14,6) CHECK (allocation_weight IS NULL OR allocation_weight > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_expense_allocation_member
ON public.expense_allocations(expense_id, period_member_id);

CREATE INDEX IF NOT EXISTS idx_expense_allocations_member
ON public.expense_allocations(period_member_id);

CREATE TRIGGER trg_expense_allocations_updated_at
BEFORE UPDATE ON public.expense_allocations
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- PAYMENTS
-- A payment is money paid by a member INTO THE MESS / manager's accounting.
-- It reduces the member's balance. It must not be used to represent a vendor
-- advance already captured by expenses.paid_by_period_member_id.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  period_member_id uuid NOT NULL REFERENCES public.period_members(id) ON DELETE RESTRICT,
  payment_date date NOT NULL,
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  method text,
  reference_text text,
  note text,
  voided_at timestamptz,
  voided_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  void_reason text,
  recorded_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    voided_at IS NULL
    OR (voided_by IS NOT NULL AND void_reason IS NOT NULL AND length(btrim(void_reason)) > 0)
  )
);

CREATE INDEX IF NOT EXISTS idx_payments_period_date
ON public.payments(period_id, payment_date DESC);

CREATE INDEX IF NOT EXISTS idx_payments_member
ON public.payments(period_member_id, payment_date DESC);

CREATE TRIGGER trg_payments_updated_at
BEFORE UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- ADJUSTMENTS
-- Credit decreases what the member owes; Debit increases it.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  period_member_id uuid NOT NULL REFERENCES public.period_members(id) ON DELETE RESTRICT,
  adjustment_type public.adjustment_type NOT NULL,
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 300),
  voided_at timestamptz,
  voided_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  void_reason text,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    voided_at IS NULL
    OR (voided_by IS NOT NULL AND void_reason IS NOT NULL AND length(btrim(void_reason)) > 0)
  )
);

CREATE INDEX IF NOT EXISTS idx_adjustments_period_member
ON public.adjustments(period_id, period_member_id, voided_at);

CREATE TRIGGER trg_adjustments_updated_at
BEFORE UPDATE ON public.adjustments
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- OPENING BALANCES
-- Positive internal effect for DUE, negative internal effect for CREDIT.
-- Opening balances are period-specific and should normally be set once when
-- creating a period from the prior period settlement.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.opening_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  period_member_id uuid NOT NULL REFERENCES public.period_members(id) ON DELETE RESTRICT,
  direction public.balance_direction NOT NULL,
  amount numeric(14,2) NOT NULL CHECK (amount >= 0),
  source_period_id uuid REFERENCES public.periods(id) ON DELETE RESTRICT,
  note text,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_opening_balance_per_member_period
ON public.opening_balances(period_id, period_member_id);

CREATE INDEX IF NOT EXISTS idx_opening_balances_source_period
ON public.opening_balances(source_period_id);

CREATE TRIGGER trg_opening_balances_updated_at
BEFORE UPDATE ON public.opening_balances
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- ----------------------------------------------------------------------------
-- SETTLEMENT SNAPSHOTS
-- A period can have multiple calculation versions across reopen/reclose cycles.
-- The final snapshot is the authoritative historical accounting result for that
-- closure event.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.settlement_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.periods(id) ON DELETE CASCADE,
  version integer NOT NULL CHECK (version >= 1),
  calculation_version text NOT NULL,
  status public.settlement_status NOT NULL DEFAULT 'DRAFT',
  superseded_at timestamptz,
  superseded_by uuid REFERENCES public.settlement_snapshots(id) ON DELETE RESTRICT,
  calculated_at timestamptz NOT NULL DEFAULT now(),
  calculated_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  finalized_at timestamptz,
  finalized_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  total_meal_units numeric(18,6) NOT NULL DEFAULT 0 CHECK (total_meal_units >= 0),
  total_meal_cost numeric(18,2) NOT NULL DEFAULT 0 CHECK (total_meal_cost >= 0),
  meal_rate numeric(18,8),
  total_shared_cost numeric(18,2) NOT NULL DEFAULT 0 CHECK (total_shared_cost >= 0),
  total_payments numeric(18,2) NOT NULL DEFAULT 0 CHECK (total_payments >= 0),
  total_expense_advances numeric(18,2) NOT NULL DEFAULT 0 CHECK (total_expense_advances >= 0),
  total_credit_adjustments numeric(18,2) NOT NULL DEFAULT 0 CHECK (total_credit_adjustments >= 0),
  total_debit_adjustments numeric(18,2) NOT NULL DEFAULT 0 CHECK (total_debit_adjustments >= 0),
  reconciliation_difference numeric(18,2) NOT NULL DEFAULT 0,
  diagnostic_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(period_id, version),
  UNIQUE(period_id, id),
  CHECK (
    meal_rate IS NULL OR meal_rate >= 0
  ),
  CHECK (
    (status = 'FINAL' AND finalized_at IS NOT NULL AND finalized_by IS NOT NULL)
    OR status <> 'FINAL'
  ),
  CHECK (superseded_at IS NULL OR superseded_by IS NOT NULL),
  CHECK (superseded_by IS NULL OR superseded_by <> id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_current_final_snapshot_per_period
ON public.settlement_snapshots(period_id)
WHERE status = 'FINAL' AND superseded_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_settlement_snapshots_period
ON public.settlement_snapshots(period_id, version DESC);

-- ----------------------------------------------------------------------------
-- SETTLEMENT MEMBER SNAPSHOTS
-- Stores the immutable per-member accounting result associated with a snapshot.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.settlement_member_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_snapshot_id uuid NOT NULL REFERENCES public.settlement_snapshots(id) ON DELETE CASCADE,
  period_member_id uuid NOT NULL REFERENCES public.period_members(id) ON DELETE RESTRICT,
  meal_units numeric(18,6) NOT NULL DEFAULT 0 CHECK (meal_units >= 0),
  food_cost numeric(18,2) NOT NULL DEFAULT 0 CHECK (food_cost >= 0),
  shared_cost numeric(18,2) NOT NULL DEFAULT 0 CHECK (shared_cost >= 0),
  credit_adjustments numeric(18,2) NOT NULL DEFAULT 0 CHECK (credit_adjustments >= 0),
  debit_adjustments numeric(18,2) NOT NULL DEFAULT 0 CHECK (debit_adjustments >= 0),
  opening_effect numeric(18,2) NOT NULL DEFAULT 0,
  payments numeric(18,2) NOT NULL DEFAULT 0 CHECK (payments >= 0),
  expense_advances numeric(18,2) NOT NULL DEFAULT 0 CHECK (expense_advances >= 0),
  total_charges numeric(18,2) NOT NULL DEFAULT 0,
  total_credits numeric(18,2) NOT NULL DEFAULT 0,
  final_balance numeric(18,2) NOT NULL DEFAULT 0,
  balance_status public.settlement_balance_status NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(settlement_snapshot_id, period_member_id)
);

CREATE INDEX IF NOT EXISTS idx_settlement_member_snapshot_member
ON public.settlement_member_snapshots(period_member_id);

-- ----------------------------------------------------------------------------
-- AUDIT EVENTS
-- Append-only audit trail. payload stores the event-specific before/after
-- context where appropriate. This table is not a substitute for the source
-- records; it documents who changed what and why.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mess_id uuid REFERENCES public.messes(id) ON DELETE RESTRICT,
  period_id uuid REFERENCES public.periods(id) ON DELETE RESTRICT,
  actor_user_id uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  event_type text NOT NULL CHECK (length(btrim(event_type)) BETWEEN 1 AND 100),
  entity_type text NOT NULL CHECK (length(btrim(entity_type)) BETWEEN 1 AND 100),
  entity_id uuid,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  transaction_id text,
  request_id text,
  reason text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_audit_events_mess_time
ON public.audit_events(mess_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_events_period_time
ON public.audit_events(period_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_events_entity
ON public.audit_events(entity_type, entity_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_events_actor
ON public.audit_events(actor_user_id, occurred_at DESC);

-- ----------------------------------------------------------------------------
-- IMMUTABILITY / CROSS-TABLE INTEGRITY FUNCTIONS
-- ----------------------------------------------------------------------------

-- Generic helper: ensure two records belong to the same period.
CREATE OR REPLACE FUNCTION private.assert_same_period(
  p_expected_period uuid,
  p_actual_period uuid,
  p_message text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_expected_period IS DISTINCT FROM p_actual_period THEN
    RAISE EXCEPTION '%', p_message
      USING ERRCODE = '23514';
  END IF;
END;
$$;

-- Period membership must point to the same period as the referenced entity.
CREATE OR REPLACE FUNCTION private.trg_validate_period_membership_links()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_member_period uuid;
  v_period_meal_type_period uuid;
BEGIN
  IF TG_TABLE_NAME = 'meals' THEN
    SELECT pm.period_id INTO v_member_period
    FROM public.period_members pm
    WHERE pm.id = NEW.period_member_id;

    PERFORM private.assert_same_period(
      NEW.period_id,
      v_member_period,
      'Meal period and member period do not match.'
    );

    SELECT pmt.period_id INTO v_period_meal_type_period
    FROM public.period_meal_types pmt
    WHERE pmt.id = NEW.meal_type_id;

    PERFORM private.assert_same_period(
      NEW.period_id,
      v_period_meal_type_period,
      'Meal period and meal type period do not match.'
    );
  ELSIF TG_TABLE_NAME = 'guest_meals' THEN
    SELECT pm.period_id INTO v_member_period
    FROM public.period_members pm
    WHERE pm.id = NEW.host_period_member_id;

    PERFORM private.assert_same_period(
      NEW.period_id,
      v_member_period,
      'Guest meal period and host member period do not match.'
    );

    SELECT pmt.period_id INTO v_period_meal_type_period
    FROM public.period_meal_types pmt
    WHERE pmt.id = NEW.meal_type_id;

    PERFORM private.assert_same_period(
      NEW.period_id,
      v_period_meal_type_period,
      'Guest meal period and meal type period do not match.'
    );
  ELSIF TG_TABLE_NAME IN ('payments','adjustments','opening_balances') THEN
    SELECT pm.period_id INTO v_member_period
    FROM public.period_members pm
    WHERE pm.id = NEW.period_member_id;

    PERFORM private.assert_same_period(
      NEW.period_id,
      v_member_period,
      'Record period and member period do not match.'
    );

    IF TG_TABLE_NAME = 'opening_balances' AND NEW.source_period_id IS NOT NULL THEN
      -- Source period is intentionally allowed to differ from target period.
      -- It represents where the opening amount originated.
      NULL;
    END IF;
  ELSIF TG_TABLE_NAME = 'expense_allocations' THEN
    DECLARE
      v_expense_period uuid;
    BEGIN
      SELECT e.period_id INTO v_expense_period
      FROM public.expenses e
      WHERE e.id = NEW.expense_id;

      SELECT pm.period_id INTO v_member_period
      FROM public.period_members pm
      WHERE pm.id = NEW.period_member_id;

      PERFORM private.assert_same_period(
        v_expense_period,
        v_member_period,
        'Expense allocation member must belong to the same period as the expense.'
      );
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_meals_period_links ON public.meals;
CREATE TRIGGER trg_validate_meals_period_links
BEFORE INSERT OR UPDATE ON public.meals
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_period_membership_links();

DROP TRIGGER IF EXISTS trg_validate_guest_meals_period_links ON public.guest_meals;
CREATE TRIGGER trg_validate_guest_meals_period_links
BEFORE INSERT OR UPDATE ON public.guest_meals
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_period_membership_links();

DROP TRIGGER IF EXISTS trg_validate_payments_period_links ON public.payments;
CREATE TRIGGER trg_validate_payments_period_links
BEFORE INSERT OR UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_period_membership_links();

DROP TRIGGER IF EXISTS trg_validate_adjustments_period_links ON public.adjustments;
CREATE TRIGGER trg_validate_adjustments_period_links
BEFORE INSERT OR UPDATE ON public.adjustments
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_period_membership_links();

DROP TRIGGER IF EXISTS trg_validate_opening_balances_period_links ON public.opening_balances;
CREATE TRIGGER trg_validate_opening_balances_period_links
BEFORE INSERT OR UPDATE ON public.opening_balances
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_period_membership_links();

DROP TRIGGER IF EXISTS trg_validate_expense_allocations_period_links ON public.expense_allocations;
CREATE TRIGGER trg_validate_expense_allocations_period_links
BEFORE INSERT OR UPDATE ON public.expense_allocations
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_period_membership_links();

-- Paid-by member must belong to the same period as the expense.
CREATE OR REPLACE FUNCTION private.trg_validate_expense_payer()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_member_period uuid;
BEGIN
  IF NEW.paid_by_period_member_id IS NOT NULL THEN
    SELECT pm.period_id INTO v_member_period
    FROM public.period_members pm
    WHERE pm.id = NEW.paid_by_period_member_id;

    PERFORM private.assert_same_period(
      NEW.period_id,
      v_member_period,
      'Expense payer must belong to the same period as the expense.'
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_expense_payer ON public.expenses;
CREATE TRIGGER trg_validate_expense_payer
BEFORE INSERT OR UPDATE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_expense_payer();

-- Expense category must belong to the same mess as the expense's period.
CREATE OR REPLACE FUNCTION private.trg_validate_expense_category()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_period_mess uuid;
  v_category_mess uuid;
BEGIN
  SELECT p.mess_id INTO v_period_mess
  FROM public.periods p
  WHERE p.id = NEW.period_id;

  SELECT ec.mess_id INTO v_category_mess
  FROM public.expense_categories ec
  WHERE ec.id = NEW.category_id;

  IF v_period_mess IS DISTINCT FROM v_category_mess THEN
    RAISE EXCEPTION 'Expense category must belong to the same mess as the expense period.'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_expense_category ON public.expenses;
CREATE TRIGGER trg_validate_expense_category
BEFORE INSERT OR UPDATE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_expense_category();



-- Accounting dates must lie inside the owning period.
CREATE OR REPLACE FUNCTION private.trg_validate_accounting_date()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_start date;
  v_end date;
  v_period_id uuid;
  v_date date;
BEGIN
  v_period_id := NEW.period_id;

  IF TG_TABLE_NAME = 'meals' THEN
    v_date := NEW.meal_date;
  ELSIF TG_TABLE_NAME = 'guest_meals' THEN
    v_date := NEW.meal_date;
  ELSIF TG_TABLE_NAME = 'expenses' THEN
    v_date := NEW.expense_date;
  ELSIF TG_TABLE_NAME = 'payments' THEN
    v_date := NEW.payment_date;
  ELSE
    RETURN NEW;
  END IF;

  SELECT start_date, end_date
    INTO v_start, v_end
  FROM public.periods
  WHERE id = v_period_id;

  IF v_date < v_start OR v_date > v_end THEN
    RAISE EXCEPTION 'Accounting date must fall within the owning period (% to %).', v_start, v_end
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_meals_accounting_date ON public.meals;
CREATE TRIGGER trg_validate_meals_accounting_date
BEFORE INSERT OR UPDATE ON public.meals
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_accounting_date();

DROP TRIGGER IF EXISTS trg_validate_guest_meals_accounting_date ON public.guest_meals;
CREATE TRIGGER trg_validate_guest_meals_accounting_date
BEFORE INSERT OR UPDATE ON public.guest_meals
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_accounting_date();

DROP TRIGGER IF EXISTS trg_validate_expenses_accounting_date ON public.expenses;
CREATE TRIGGER trg_validate_expenses_accounting_date
BEFORE INSERT OR UPDATE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_accounting_date();

DROP TRIGGER IF EXISTS trg_validate_payments_accounting_date ON public.payments;
CREATE TRIGGER trg_validate_payments_accounting_date
BEFORE INSERT OR UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_accounting_date();

-- Only an active period member can hold the current manager assignment.
CREATE OR REPLACE FUNCTION private.trg_validate_manager_assignment_member()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_status public.period_membership_status;
BEGIN
  SELECT membership_status INTO v_status
  FROM public.period_members
  WHERE id = NEW.period_member_id;

  IF NEW.ended_at IS NULL AND v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Current manager must be an active period member.'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_manager_assignment_member ON public.manager_assignments;
CREATE TRIGGER trg_validate_manager_assignment_member
BEFORE INSERT OR UPDATE ON public.manager_assignments
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_manager_assignment_member();

-- A member cannot be ended/removed while still holding the current manager
-- assignment. The controlled manager-transfer workflow must end the manager
-- assignment first.
CREATE OR REPLACE FUNCTION private.trg_block_ending_current_manager()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.membership_status <> 'ACTIVE'
     AND OLD.membership_status = 'ACTIVE'
     AND EXISTS (
       SELECT 1
       FROM public.manager_assignments ma
       WHERE ma.period_id = NEW.period_id
         AND ma.period_member_id = NEW.id
         AND ma.ended_at IS NULL
     ) THEN
    RAISE EXCEPTION 'End the current manager assignment before ending or removing this member.'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_ending_current_manager ON public.period_members;
CREATE TRIGGER trg_block_ending_current_manager
BEFORE UPDATE ON public.period_members
FOR EACH ROW EXECUTE FUNCTION private.trg_block_ending_current_manager();

-- Manager assignment must point to a member of the same period.
CREATE OR REPLACE FUNCTION private.trg_validate_manager_assignment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_member_period uuid;
BEGIN
  SELECT pm.period_id INTO v_member_period
  FROM public.period_members pm
  WHERE pm.id = NEW.period_member_id;

  IF NEW.period_id IS DISTINCT FROM v_member_period THEN
    RAISE EXCEPTION 'Manager assignment member must belong to the same period.'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_manager_assignment ON public.manager_assignments;
CREATE TRIGGER trg_validate_manager_assignment
BEFORE INSERT OR UPDATE ON public.manager_assignments
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_manager_assignment();

-- Opening balance source period must belong to the same mess as target period.
CREATE OR REPLACE FUNCTION private.trg_validate_opening_balance_source()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_target_mess uuid;
  v_source_mess uuid;
BEGIN
  IF NEW.source_period_id IS NOT NULL THEN
    SELECT mess_id INTO v_target_mess FROM public.periods WHERE id = NEW.period_id;
    SELECT mess_id INTO v_source_mess FROM public.periods WHERE id = NEW.source_period_id;

    IF v_target_mess IS DISTINCT FROM v_source_mess THEN
      RAISE EXCEPTION 'Opening balance source period must belong to the same mess.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_opening_balance_source ON public.opening_balances;
CREATE TRIGGER trg_validate_opening_balance_source
BEFORE INSERT OR UPDATE ON public.opening_balances
FOR EACH ROW EXECUTE FUNCTION private.trg_validate_opening_balance_source();

-- Closed periods are protected at the database layer. Reopening must be done
-- by a dedicated controlled function that changes the period status first.
CREATE OR REPLACE FUNCTION private.trg_block_closed_period_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_period_id uuid;
  v_status public.period_status;
BEGIN
  IF TG_TABLE_NAME = 'period_members' THEN
    v_period_id := COALESCE(NEW.period_id, OLD.period_id);
  ELSIF TG_TABLE_NAME = 'manager_assignments' THEN
    v_period_id := COALESCE(NEW.period_id, OLD.period_id);
  ELSIF TG_TABLE_NAME = 'period_meal_types' THEN
    v_period_id := COALESCE(NEW.period_id, OLD.period_id);
  ELSIF TG_TABLE_NAME IN ('meals','guest_meals','payments','adjustments','opening_balances','expenses') THEN
    v_period_id := COALESCE(NEW.period_id, OLD.period_id);
  ELSIF TG_TABLE_NAME = 'expense_allocations' THEN
    SELECT e.period_id INTO v_period_id
    FROM public.expenses e
    WHERE e.id = COALESCE(NEW.expense_id, OLD.expense_id);
  ELSE
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT status INTO v_status FROM public.periods WHERE id = v_period_id;

  IF v_status = 'CLOSED' THEN
    RAISE EXCEPTION 'Period is closed. Reopen the period through the controlled reopen workflow before modifying accounting data.'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_closed_period_period_members ON public.period_members;
CREATE TRIGGER trg_block_closed_period_period_members
BEFORE INSERT OR UPDATE OR DELETE ON public.period_members
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_manager_assignments ON public.manager_assignments;
CREATE TRIGGER trg_block_closed_period_manager_assignments
BEFORE INSERT OR UPDATE OR DELETE ON public.manager_assignments
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_meal_types ON public.period_meal_types;
CREATE TRIGGER trg_block_closed_period_meal_types
BEFORE INSERT OR UPDATE OR DELETE ON public.period_meal_types
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_meals ON public.meals;
CREATE TRIGGER trg_block_closed_period_meals
BEFORE INSERT OR UPDATE OR DELETE ON public.meals
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_guest_meals ON public.guest_meals;
CREATE TRIGGER trg_block_closed_period_guest_meals
BEFORE INSERT OR UPDATE OR DELETE ON public.guest_meals
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_expenses ON public.expenses;
CREATE TRIGGER trg_block_closed_period_expenses
BEFORE INSERT OR UPDATE OR DELETE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_expense_allocations ON public.expense_allocations;
CREATE TRIGGER trg_block_closed_period_expense_allocations
BEFORE INSERT OR UPDATE OR DELETE ON public.expense_allocations
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_payments ON public.payments;
CREATE TRIGGER trg_block_closed_period_payments
BEFORE INSERT OR UPDATE OR DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_adjustments ON public.adjustments;
CREATE TRIGGER trg_block_closed_period_adjustments
BEFORE INSERT OR UPDATE OR DELETE ON public.adjustments
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();

DROP TRIGGER IF EXISTS trg_block_closed_period_opening_balances ON public.opening_balances;
CREATE TRIGGER trg_block_closed_period_opening_balances
BEFORE INSERT OR UPDATE OR DELETE ON public.opening_balances
FOR EACH ROW EXECUTE FUNCTION private.trg_block_closed_period_mutation();


-- Final settlement snapshots and their member rows are historical records.
-- They may be superseded by a later closure version, but their accounting
-- contents are not edited in place.
CREATE OR REPLACE FUNCTION private.reject_snapshot_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    -- A controlled reopen/reclose operation may only mark an old snapshot as
    -- superseded. No financial result fields may be rewritten.
    IF OLD.period_id IS DISTINCT FROM NEW.period_id
       OR OLD.version IS DISTINCT FROM NEW.version
       OR OLD.calculation_version IS DISTINCT FROM NEW.calculation_version
       OR OLD.status IS DISTINCT FROM NEW.status
       OR OLD.calculated_at IS DISTINCT FROM NEW.calculated_at
       OR OLD.calculated_by IS DISTINCT FROM NEW.calculated_by
       OR OLD.finalized_at IS DISTINCT FROM NEW.finalized_at
       OR OLD.finalized_by IS DISTINCT FROM NEW.finalized_by
       OR OLD.total_meal_units IS DISTINCT FROM NEW.total_meal_units
       OR OLD.total_meal_cost IS DISTINCT FROM NEW.total_meal_cost
       OR OLD.meal_rate IS DISTINCT FROM NEW.meal_rate
       OR OLD.total_shared_cost IS DISTINCT FROM NEW.total_shared_cost
       OR OLD.total_payments IS DISTINCT FROM NEW.total_payments
       OR OLD.total_expense_advances IS DISTINCT FROM NEW.total_expense_advances
       OR OLD.total_credit_adjustments IS DISTINCT FROM NEW.total_credit_adjustments
       OR OLD.total_debit_adjustments IS DISTINCT FROM NEW.total_debit_adjustments
       OR OLD.reconciliation_difference IS DISTINCT FROM NEW.reconciliation_difference
       OR OLD.diagnostic_json IS DISTINCT FROM NEW.diagnostic_json THEN
      RAISE EXCEPTION 'Settlement snapshot financial contents are immutable.'
        USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Settlement snapshots cannot be deleted.' USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_snapshot_mutation ON public.settlement_snapshots;
CREATE TRIGGER trg_reject_snapshot_mutation
BEFORE UPDATE OR DELETE ON public.settlement_snapshots
FOR EACH ROW EXECUTE FUNCTION private.reject_snapshot_mutation();

CREATE OR REPLACE FUNCTION private.reject_settlement_member_snapshot_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Settlement member snapshots are immutable.' USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_settlement_member_snapshot_mutation ON public.settlement_member_snapshots;
CREATE TRIGGER trg_reject_settlement_member_snapshot_mutation
BEFORE UPDATE OR DELETE ON public.settlement_member_snapshots
FOR EACH ROW EXECUTE FUNCTION private.reject_settlement_member_snapshot_mutation();


-- Automatic row-level audit for source accounting records. High-level workflows
-- should additionally insert an explicit event with a human-readable reason.
CREATE OR REPLACE FUNCTION private.audit_row_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = private, public
AS $$
DECLARE
  v_mess_id uuid;
  v_period_id uuid;
  v_entity_id uuid;
  v_event_type text;
  v_before jsonb;
  v_after jsonb;
BEGIN
  v_entity_id := COALESCE((to_jsonb(NEW)->>'id')::uuid, (to_jsonb(OLD)->>'id')::uuid);

  IF TG_TABLE_NAME = 'messes' THEN
    v_mess_id := v_entity_id;
  ELSIF TG_TABLE_NAME = 'periods' THEN
    v_period_id := v_entity_id;
    v_mess_id := COALESCE((to_jsonb(NEW)->>'mess_id')::uuid, (to_jsonb(OLD)->>'mess_id')::uuid);
  ELSIF TG_TABLE_NAME IN (
    'period_members','manager_assignments','period_meal_types','meals',
    'guest_meals','expenses','expense_allocations','payments','adjustments',
    'opening_balances','settlement_snapshots','settlement_member_snapshots'
  ) THEN
    IF TG_TABLE_NAME = 'period_members' THEN
      v_period_id := COALESCE(NEW.period_id, OLD.period_id);
    ELSIF TG_TABLE_NAME = 'manager_assignments' THEN
      v_period_id := COALESCE(NEW.period_id, OLD.period_id);
    ELSIF TG_TABLE_NAME = 'period_meal_types' THEN
      v_period_id := COALESCE(NEW.period_id, OLD.period_id);
    ELSIF TG_TABLE_NAME IN ('meals','guest_meals','expenses','payments','adjustments','opening_balances') THEN
      v_period_id := COALESCE(NEW.period_id, OLD.period_id);
    ELSIF TG_TABLE_NAME = 'expense_allocations' THEN
      SELECT e.period_id INTO v_period_id
      FROM public.expenses e
      WHERE e.id = COALESCE(NEW.expense_id, OLD.expense_id);
    ELSIF TG_TABLE_NAME = 'settlement_snapshots' THEN
      v_period_id := COALESCE(NEW.period_id, OLD.period_id);
    ELSIF TG_TABLE_NAME = 'settlement_member_snapshots' THEN
      SELECT ss.period_id INTO v_period_id
      FROM public.settlement_snapshots ss
      WHERE ss.id = COALESCE(NEW.settlement_snapshot_id, OLD.settlement_snapshot_id);
    END IF;

    SELECT p.mess_id INTO v_mess_id FROM public.periods p WHERE p.id = v_period_id;
  END IF;

  v_event_type := lower(TG_OP) || '_' || TG_TABLE_NAME;
  v_before := CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END;
  v_after  := CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END;

  INSERT INTO public.audit_events (
    mess_id, period_id, actor_user_id, event_type, entity_type, entity_id,
    transaction_id, before_data, after_data
  ) VALUES (
    v_mess_id, v_period_id, auth.uid(), v_event_type, TG_TABLE_NAME, v_entity_id,
    txid_current()::text, v_before, v_after
  );

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

-- Automatic audit triggers on accounting/security-sensitive records.
DROP TRIGGER IF EXISTS trg_audit_messes ON public.messes;
CREATE TRIGGER trg_audit_messes AFTER INSERT OR UPDATE OR DELETE ON public.messes
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_periods ON public.periods;
CREATE TRIGGER trg_audit_periods AFTER INSERT OR UPDATE OR DELETE ON public.periods
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_period_members ON public.period_members;
CREATE TRIGGER trg_audit_period_members AFTER INSERT OR UPDATE OR DELETE ON public.period_members
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_manager_assignments ON public.manager_assignments;
CREATE TRIGGER trg_audit_manager_assignments AFTER INSERT OR UPDATE OR DELETE ON public.manager_assignments
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_period_meal_types ON public.period_meal_types;
CREATE TRIGGER trg_audit_period_meal_types AFTER INSERT OR UPDATE OR DELETE ON public.period_meal_types
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_meals ON public.meals;
CREATE TRIGGER trg_audit_meals AFTER INSERT OR UPDATE OR DELETE ON public.meals
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_guest_meals ON public.guest_meals;
CREATE TRIGGER trg_audit_guest_meals AFTER INSERT OR UPDATE OR DELETE ON public.guest_meals
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_expenses ON public.expenses;
CREATE TRIGGER trg_audit_expenses AFTER INSERT OR UPDATE OR DELETE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_expense_allocations ON public.expense_allocations;
CREATE TRIGGER trg_audit_expense_allocations AFTER INSERT OR UPDATE OR DELETE ON public.expense_allocations
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_payments ON public.payments;
CREATE TRIGGER trg_audit_payments AFTER INSERT OR UPDATE OR DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_adjustments ON public.adjustments;
CREATE TRIGGER trg_audit_adjustments AFTER INSERT OR UPDATE OR DELETE ON public.adjustments
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_opening_balances ON public.opening_balances;
CREATE TRIGGER trg_audit_opening_balances AFTER INSERT OR UPDATE OR DELETE ON public.opening_balances
FOR EACH ROW EXECUTE FUNCTION private.audit_row_change();

-- ----------------------------------------------------------------------------
-- AUDIT IMMUTABILITY
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.reject_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit_events is append-only.' USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_events_no_update ON public.audit_events;
CREATE TRIGGER trg_audit_events_no_update
BEFORE UPDATE OR DELETE ON public.audit_events
FOR EACH ROW EXECUTE FUNCTION private.reject_audit_mutation();

-- ----------------------------------------------------------------------------
-- VIEWS
-- These are convenience views. Authorization still depends on RLS/security
-- configuration and should be tested against Supabase's execution model.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.current_period_manager AS
SELECT
  ma.period_id,
  ma.id AS manager_assignment_id,
  ma.period_member_id,
  pm.user_id,
  ma.assigned_at,
  ma.assigned_by
FROM public.manager_assignments ma
JOIN public.period_members pm ON pm.id = ma.period_member_id
WHERE ma.ended_at IS NULL;

CREATE OR REPLACE VIEW public.active_period_members AS
SELECT
  pm.id AS period_member_id,
  pm.period_id,
  pm.user_id,
  p.display_name,
  pm.joined_at,
  pm.membership_status
FROM public.period_members pm
JOIN public.profiles p ON p.id = pm.user_id
WHERE pm.membership_status = 'ACTIVE';

-- ----------------------------------------------------------------------------
-- RLS
-- Enable RLS now. Detailed policies should be maintained in the dedicated
-- authorization migration so that policy changes remain reviewable separately.
-- No table should be exposed as an unrestricted anonymous data source.
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mess_join_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mess_join_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.period_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manager_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.period_meal_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.guest_meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opening_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_member_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

ALTER VIEW public.current_period_manager SET (security_invoker = true);
ALTER VIEW public.active_period_members SET (security_invoker = true);

-- ----------------------------------------------------------------------------
-- GRANTS
-- Lock default PUBLIC access down. The application should use authenticated
-- requests plus tightly controlled RPCs for sensitive operations.
-- ----------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;

-- Basic read access is granted only to authenticated; RLS remains authoritative.
GRANT SELECT ON
  public.profiles,
  public.messes,
  public.mess_join_codes,
  public.mess_join_requests,
  public.periods,
  public.period_members,
  public.manager_assignments,
  public.period_meal_types,
  public.meals,
  public.guest_meals,
  public.expense_categories,
  public.expenses,
  public.expense_allocations,
  public.payments,
  public.adjustments,
  public.opening_balances,
  public.settlement_snapshots,
  public.settlement_member_snapshots,
  public.audit_events
TO authenticated;

-- Views need explicit grants as well.
GRANT SELECT ON public.current_period_manager, public.active_period_members
TO authenticated;

COMMIT;

-- ============================================================================
-- SCHEMA V2 ACCOUNTING CONTRACT
-- ============================================================================
-- The final member balance is:
--
--   Opening Effect
-- + Food Cost
-- + Shared Cost
-- + Debit Adjustments
-- - Credit Adjustments
-- - Payments
-- - Expense Advances
--
-- Expense advance = amount of a valid expense whose
--   paid_by_period_member_id = that member.
--
-- Examples:
--   1) Shared internet bill = 1000, 4 members, member A pays vendor.
--      Shared cost allocations = 250 each.
--      A expense advance = 1000.
--      Net effects: A -750, others +250 each, total = 0.
--
--   2) Meal groceries = 10000, meal units A/B/C = 50/30/20.
--      Food costs = 5000/3000/2000.
--      A pays vendor -> A expense advance = 10000.
--      Net effects = -5000/+3000/+2000.
--
-- Meal-rate contract:
--   total_meal_cost / total_chargeable_meal_units
--   If units = 0, meal_rate is NULL (never NaN, never an artificial 0).
--
-- Allocation reconciliation:
--   SUM(expense_allocations.allocation_amount) = expenses.amount
--   for every non-voided allocated shared expense.
--
-- Settlement statuses:
--   final_balance > 0  => DUE
--   final_balance = 0  => SETTLED
--   final_balance < 0  => CREDIT
--
-- Important implementation note:
--   The database schema intentionally does NOT allow silent historical
--   recalculation to overwrite a prior FINAL settlement snapshot. Reopen,
--   recalculate, and reclose must create a new version.
-- ============================================================================
