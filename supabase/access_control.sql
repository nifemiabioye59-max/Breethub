-- Breethub access-control configuration
-- Apply this after schema.sql.

create type public.access_gate_type as enum (
  'affiliate',
  'writer',
  'chapter',
  'advertiser'
);

create type public.payment_status as enum (
  'pending',
  'confirmed',
  'failed',
  'cancelled',
  'refunded'
);

create type public.withdrawal_status as enum (
  'pending',
  'approved',
  'processing',
  'paid',
  'rejected',
  'failed'
);

create table public.platform_settings (
  id uuid primary key default gen_random_uuid(),

  affiliate_access_fee_ngn numeric(12,2) not null default 1000,
  affiliate_access_fee_usd numeric(12,2) not null default 5,

  writer_access_fee_ngn numeric(12,2) not null default 1000,
  writer_access_fee_usd numeric(12,2) not null default 5,

  affiliate_initial_free_days integer not null default 3,

  withdrawal_interval_days integer not null default 14,
  withdrawal_tax_percent numeric(5,2) not null default 5,
  minimum_withdrawal_ngn numeric(12,2) not null default 1000,

  updated_at timestamptz not null default now()
);

insert into public.platform_settings (
  id
)
values (
  gen_random_uuid()
)
on conflict do nothing;


create table public.account_access (
  user_id uuid primary key references public.profiles(id) on delete cascade,

  affiliate_free_started_at timestamptz,
  affiliate_access_until timestamptz,

  writer_access_until timestamptz,

  is_locked boolean not null default false,

  lock_reason text,

  updated_at timestamptz not null default now()
);


create table public.access_payments (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  gate_type public.access_gate_type not null,

  amount numeric(12,2) not null,
  currency public.wallet_currency not null,

  provider text,
  provider_reference text unique,

  status public.payment_status not null default 'pending',

  confirmed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


create table public.bank_accounts (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  account_name text not null,
  bank_name text not null,
  bank_code text,
  account_number text not null,

  is_verified boolean not null default false,
  is_primary boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(user_id, account_number)
);


create table public.withdrawals (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  bank_account_id uuid not null references public.bank_accounts(id),

  amount numeric(12,2) not null,
  tax_amount numeric(12,2) not null default 0,
  net_amount numeric(12,2) not null,

  currency public.wallet_currency not null,

  status public.withdrawal_status not null default 'pending',

  provider text,
  provider_reference text,

  requested_at timestamptz not null default now(),
  processed_at timestamptz,

  rejection_reason text
);


create index access_payments_user_idx
on public.access_payments(user_id);

create index access_payments_status_idx
on public.access_payments(status);

create index withdrawals_user_idx
on public.withdrawals(user_id);

create index withdrawals_status_idx
on public.withdrawals(status);

create index bank_accounts_user_idx
on public.bank_accounts(user_id);


alter table public.platform_settings enable row level security;
alter table public.account_access enable row level security;
alter table public.access_payments enable row level security;
alter table public.bank_accounts enable row level security;
alter table public.withdrawals enable row level security;


-- Users can see their own access status.
create policy "Users can view own access"
on public.account_access
for select
to authenticated
using (
  (select auth.uid()) = user_id
);


-- Users can see their own payment records.
create policy "Users can view own access payments"
on public.access_payments
for select
to authenticated
using (
  (select auth.uid()) = user_id
);


-- Users can manage their own bank account records.
create policy "Users can view own bank accounts"
on public.bank_accounts
for select
to authenticated
using (
  (select auth.uid()) = user_id
);

create policy "Users can add own bank account"
on public.bank_accounts
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
);

create policy "Users can update own bank account"
on public.bank_accounts
for update
to authenticated
using (
  (select auth.uid()) = user_id
)
with check (
  (select auth.uid()) = user_id
);


-- Users can view their own withdrawals.
create policy "Users can view own withdrawals"
on public.withdrawals
for select
to authenticated
using (
  (select auth.uid()) = user_id
);


-- Users should NOT be allowed to directly insert
-- confirmed payments or withdrawals from the browser.
--
-- Those operations will be performed by secure server-side
-- payment/withdrawal logic after validation.
