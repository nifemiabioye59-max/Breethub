-- ============================================================
-- BREETHUB DATABASE FOUNDATION
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- ENUMS
-- ============================================================

do $$
begin
  create type public.user_role as enum (
    'reader',
    'affiliate',
    'writer',
    'advertiser',
    'admin'
  );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.story_status as enum (
    'draft',
    'pending_review',
    'published',
    'rejected',
    'archived'
  );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.order_status as enum (
    'pending',
    'paid',
    'completed',
    'cancelled',
    'refunded'
  );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.wallet_currency as enum (
    'NGN',
    'USD',
    'GBP',
    'GHS',
    'KES'
  );
exception
  when duplicate_object then null;
end $$;

-- ============================================================
-- PROFILES
-- ============================================================

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,

  real_name text not null,
  nickname text not null,
  phone text not null,
  country text not null,

  role public.user_role not null default 'reader',

  phone_verified boolean not null default false,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint profiles_phone_unique unique (phone)
);

create index if not exists profiles_role_idx
  on public.profiles(role);

create index if not exists profiles_country_idx
  on public.profiles(country);

-- ============================================================
-- WALLETS
-- ============================================================

create table if not exists public.wallets (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  currency public.wallet_currency not null,

  balance numeric(18,2) not null default 0,
  pending_balance numeric(18,2) not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint wallet_balance_nonnegative
    check (balance >= 0),

  constraint wallet_pending_nonnegative
    check (pending_balance >= 0),

  constraint one_wallet_per_currency
    unique (user_id, currency)
);

create index if not exists wallets_user_idx
  on public.wallets(user_id);

-- ============================================================
-- WALLET TRANSACTIONS
-- ============================================================

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),

  wallet_id uuid not null references public.wallets(id) on delete cascade,

  amount numeric(18,2) not null,

  transaction_type text not null,

  reference text,

  description text,

  created_at timestamptz not null default now()
);

create index if not exists wallet_transactions_wallet_idx
  on public.wallet_transactions(wallet_id);

create index if not exists wallet_transactions_created_idx
  on public.wallet_transactions(created_at desc);

-- ============================================================
-- STORIES
-- ============================================================

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),

  writer_id uuid not null references public.profiles(id),

  title text not null,
  description text,

  genre text not null,
  country text,

  cover_url text,

  price_ngn numeric(18,2) not null default 300,
  price_usd numeric(18,2) not null default 2,
  price_gbp numeric(18,2) not null default 2,

  full_story_price_ngn numeric(18,2) not null default 2500,
  full_story_price_usd numeric(18,2) not null default 15,

  hard_copy_price_ngn numeric(18,2) not null default 5000,

  status public.story_status not null default 'draft',

  views bigint not null default 0,
  tips numeric(18,2) not null default 0,

  published_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists stories_writer_idx
  on public.stories(writer_id);

create index if not exists stories_status_idx
  on public.stories(status);

create index if not exists stories_genre_idx
  on public.stories(genre);

-- ============================================================
-- CHAPTERS
-- ============================================================

create table if not exists public.chapters (
  id uuid primary key default gen_random_uuid(),

  story_id uuid not null references public.stories(id) on delete cascade,

  chapter_number integer not null,
  title text not null,
  content text not null,

  price_ngn numeric(18,2) not null default 300,
  price_usd numeric(18,2) not null default 2,

  is_free boolean not null default false,

  created_at timestamptz not null default now(),

  constraint unique_story_chapter
    unique (story_id, chapter_number),

  constraint chapter_number_positive
    check (chapter_number > 0)
);

create index if not exists chapters_story_idx
  on public.chapters(story_id);

-- ============================================================
-- CHAPTER UNLOCKS
-- ============================================================

create table if not exists public.chapter_unlocks (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,
  chapter_id uuid not null references public.chapters(id) on delete cascade,

  purchased_at timestamptz not null default now(),

  constraint unique_user_chapter_unlock
    unique (user_id, chapter_id)
);

create index if not exists chapter_unlocks_user_idx
  on public.chapter_unlocks(user_id);

-- ============================================================
-- REVIEWS
-- ============================================================

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,
  story_id uuid not null references public.stories(id) on delete cascade,

  rating integer not null,
  body text not null,

  created_at timestamptz not null default now(),

  constraint rating_range
    check (rating between 1 and 5)
);

create index if not exists reviews_story_idx
  on public.reviews(story_id);

-- ============================================================
-- ORDERS
-- ============================================================

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id),

  currency public.wallet_currency not null,

  subtotal numeric(18,2) not null,
  delivery_fee numeric(18,2) not null default 0,
  total numeric(18,2) not null,

  payment_provider text,
  payment_reference text,

  status public.order_status not null default 'pending',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists orders_user_idx
  on public.orders(user_id);

create index if not exists orders_payment_reference_idx
  on public.orders(payment_reference);

-- ============================================================
-- ORDER ITEMS
-- ============================================================

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),

  order_id uuid not null references public.orders(id) on delete cascade,

  story_id uuid references public.stories(id),
  chapter_id uuid references public.chapters(id),

  item_type text not null,

  quantity integer not null default 1,

  unit_price numeric(18,2) not null,

  created_at timestamptz not null default now()
);

create index if not exists order_items_order_idx
  on public.order_items(order_id);

-- ============================================================
-- READING ACTIVITY
-- ============================================================

create table if not exists public.reading_activity (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,
  chapter_id uuid not null references public.chapters(id) on delete cascade,

  completed boolean not null default false,

  read_at timestamptz not null default now()
);

create index if not exists reading_activity_user_idx
  on public.reading_activity(user_id);

create index if not exists reading_activity_date_idx
  on public.reading_activity(read_at);

-- ============================================================
-- READING REWARDS
-- ============================================================

create table if not exists public.reading_rewards (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  reward_type text not null,

  amount numeric(18,2) not null default 0,

  reference_date date,

  created_at timestamptz not null default now()
);

create index if not exists reading_rewards_user_idx
  on public.reading_rewards(user_id);

-- ============================================================
-- WRITER COURSES
-- ============================================================

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),

  title text not null,
  description text,

  audience public.user_role not null,

  price_ngn numeric(18,2) not null default 0,
  price_usd numeric(18,2) not null default 0,
  price_gbp numeric(18,2) not null default 0,
  price_ghs numeric(18,2) not null default 0,
  price_kes numeric(18,2) not null default 0,

  commission_percent numeric(5,2) not null default 40,

  published boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- COURSE MODULES
-- ============================================================

create table if not exists public.course_modules (
  id uuid primary key default gen_random_uuid(),

  course_id uuid not null references public.courses(id) on delete cascade,

  module_number integer not null,
  title text not null,

  content_type text not null default 'text',
  content text,
  video_url text,

  created_at timestamptz not null default now(),

  constraint unique_course_module
    unique(course_id, module_number)
);

-- ============================================================
-- COURSE PROGRESS
-- ============================================================

create table if not exists public.course_progress (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,

  completed_modules integer not null default 0,
  completed boolean not null default false,

  test_score numeric(5,2),

  passed boolean not null default false,

  updated_at timestamptz not null default now(),

  constraint unique_user_course
    unique(user_id, course_id)
);

-- ============================================================
-- AFFILIATE TASKS
-- ============================================================

create table if not exists public.affiliate_tasks (
  id uuid primary key default gen_random_uuid(),

  advertiser_id uuid not null references public.profiles(id),

  platform text not null,
  content_url text not null,

  engagement_type text not null,

  target_country text,

  target_people integer not null,

  price_per_engagement numeric(18,2) not null,

  total_budget numeric(18,2) not null,

  completed_count integer not null default 0,

  active boolean not null default false,

  created_at timestamptz not null default now()
);

-- ============================================================
-- TASK SUBMISSIONS
-- ============================================================

create table if not exists public.task_submissions (
  id uuid primary key default gen_random_uuid(),

  task_id uuid not null references public.affiliate_tasks(id) on delete cascade,

  affiliate_id uuid not null references public.profiles(id) on delete cascade,

  proof_url text,

  ocr_verified boolean not null default false,

  status text not null default 'pending',

  reward numeric(18,2) not null default 0,

  created_at timestamptz not null default now(),

  reviewed_at timestamptz
);

create index if not exists task_submissions_task_idx
  on public.task_submissions(task_id);

create index if not exists task_submissions_affiliate_idx
  on public.task_submissions(affiliate_id);

-- ============================================================
-- REFERRALS
-- ============================================================

create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),

  referrer_id uuid not null references public.profiles(id),

  referred_user_id uuid not null references public.profiles(id),

  reward numeric(18,2) not null default 2000,

  eligible boolean not null default false,
  paid boolean not null default false,

  created_at timestamptz not null default now(),

  constraint unique_referred_user
    unique(referred_user_id)
);

-- ============================================================
-- WITHDRAWALS
-- ============================================================

create table if not exists public.withdrawals (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id),

  currency public.wallet_currency not null,

  amount numeric(18,2) not null,

  tax_amount numeric(18,2) not null default 0,

  payout_amount numeric(18,2) not null,

  status text not null default 'pending',

  payout_reference text,

  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists withdrawals_user_idx
  on public.withdrawals(user_id);

-- ============================================================
-- ADVERTISER CAMPAIGNS
-- ============================================================

create table if not exists public.advertiser_campaigns (
  id uuid primary key default gen_random_uuid(),

  advertiser_id uuid not null references public.profiles(id),

  platform text not null,
  content_url text not null,

  countries text[] not null default '{}',

  engagement_type text not null,

  people_requested integer not null,

  price_per_engagement numeric(18,2) not null,

  total_budget numeric(18,2) not null,

  disclaimer_accepted boolean not null default false,

  status text not null default 'pending_admin_approval',

  created_at timestamptz not null default now()
);

-- ============================================================
-- SYNDICATION
-- ============================================================

create table if not exists public.syndications (
  id uuid primary key default gen_random_uuid(),

  story_id uuid not null references public.stories(id),

  platform text not null,

  external_url text,

  external_earnings numeric(18,2) not null default 0,

  writer_share_percent numeric(5,2) not null default 60,

  writer_paid boolean not null default false,

  created_at timestamptz not null default now()
);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  title text not null,
  message text not null,

  read boolean not null default false,

  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications(user_id);

-- ============================================================
-- UPDATED_AT FUNCTION
-- ============================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================
-- UPDATED_AT TRIGGERS
-- ============================================================

drop trigger if exists profiles_updated_at on public.profiles;

create trigger profiles_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

drop trigger if exists wallets_updated_at on public.wallets;

create trigger wallets_updated_at
before update on public.wallets
for each row
execute function public.set_updated_at();

drop trigger if exists stories_updated_at on public.stories;

create trigger stories_updated_at
before update on public.stories
for each row
execute function public.set_updated_at();

drop trigger if exists orders_updated_at on public.orders;

create trigger orders_updated_at
before update on public.orders
for each row
execute function public.set_updated_at();

drop trigger if exists courses_updated_at on public.courses;

create trigger courses_updated_at
before update on public.courses
for each row
execute function public.set_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.stories enable row level security;
alter table public.chapters enable row level security;
alter table public.chapter_unlocks enable row level security;
alter table public.reviews enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.reading_activity enable row level security;
alter table public.reading_rewards enable row level security;
alter table public.courses enable row level security;
alter table public.course_modules enable row level security;
alter table public.course_progress enable row level security;
alter table public.affiliate_tasks enable row level security;
alter table public.task_submissions enable row level security;
alter table public.referrals enable row level security;
alter table public.withdrawals enable row level security;
alter table public.advertiser_campaigns enable row level security;
alter table public.syndications enable row level security;
alter table public.notifications enable row level security;

-- ============================================================
-- PROFILE POLICIES
-- ============================================================

drop policy if exists "Users can view own profile" on public.profiles;

create policy "Users can view own profile"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

drop policy if exists "Users can update own profile" on public.profiles;

create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- ============================================================
-- STORY POLICIES
-- ============================================================

drop policy if exists "Anyone can view published stories" on public.stories;

create policy "Anyone can view published stories"
on public.stories
for select
to anon, authenticated
using (status = 'published');

drop policy if exists "Writers can view own stories" on public.stories;

create policy "Writers can view own stories"
on public.stories
for select
to authenticated
using ((select auth.uid()) = writer_id);

drop policy if exists "Writers can create stories" on public.stories;

create policy "Writers can create stories"
on public.stories
for insert
to authenticated
with check ((select auth.uid()) = writer_id);

drop policy if exists "Writers can update own stories" on public.stories;

create policy "Writers can update own stories"
on public.stories
for update
to authenticated
using ((select auth.uid()) = writer_id)
with check ((select auth.uid()) = writer_id);

-- ============================================================
-- CHAPTER POLICIES
-- ============================================================

drop policy if exists "Free chapters are public" on public.chapters;

create policy "Free chapters are public"
on public.chapters
for select
to anon, authenticated
using (
  is_free = true
  and exists (
    select 1
    from public.stories s
    where s.id = story_id
    and s.status = 'published'
  )
);

drop policy if exists "Unlocked chapters are visible" on public.chapters;

create policy "Unlocked chapters are visible"
on public.chapters
for select
to authenticated
using (
  exists (
    select 1
    from public.chapter_unlocks cu
    where cu.chapter_id = id
    and cu.user_id = (select auth.uid())
  )
);

-- ============================================================
-- UNLOCK POLICIES
-- ============================================================

drop policy if exists "Users can view own unlocks" on public.chapter_unlocks;

create policy "Users can view own unlocks"
on public.chapter_unlocks
for select
to authenticated
using ((select auth.uid()) = user_id);

-- ============================================================
-- REVIEW POLICIES
-- ============================================================

drop policy if exists "Published story reviews are public" on public.reviews;

create policy "Published story reviews are public"
on public.reviews
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.stories s
    where s.id = story_id
    and s.status = 'published'
  )
);

drop policy if exists "Users can create reviews" on public.reviews;

create policy "Users can create reviews"
on public.reviews
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- ============================================================
-- READING ACTIVITY
-- ============================================================

drop policy if exists "Users can view own reading activity"
on public.reading_activity;

create policy "Users can view own reading activity"
on public.reading_activity
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can create own reading activity"
on public.reading_activity;

create policy "Users can create own reading activity"
on public.reading_activity
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- ============================================================
-- COURSE POLICIES
-- ============================================================

drop policy if exists "Published courses are public"
on public.courses;

create policy "Published courses are public"
on public.courses
for select
to anon, authenticated
using (published = true);

drop policy if exists "Course modules for published courses"
on public.course_modules;

create policy "Course modules for published courses"
on public.course_modules
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.courses c
    where c.id = course_id
    and c.published = true
  )
);

-- ============================================================
-- COURSE PROGRESS
-- ============================================================

drop policy if exists "Users view own course progress"
on public.course_progress;

create policy "Users view own course progress"
on public.course_progress
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users create own course progress"
on public.course_progress;

create policy "Users create own course progress"
on public.course_progress
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own course progress"
on public.course_progress;

create policy "Users update own course progress"
on public.course_progress
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================

drop policy if exists "Users view own notifications"
on public.notifications;

create policy "Users view own notifications"
on public.notifications
for select
to authenticated
using ((select auth.uid()) = user_id);

-- ============================================================
-- WALLET POLICIES
-- ============================================================

drop policy if exists "Users view own wallets"
on public.wallets;

create policy "Users view own wallets"
on public.wallets
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users view own transactions"
on public.wallet_transactions;

create policy "Users view own transactions"
on public.wallet_transactions
for select
to authenticated
using (
  exists (
    select 1
    from public.wallets w
    where w.id = wallet_id
    and w.user_id = (select auth.uid())
  )
);

-- ============================================================
-- ORDERS
-- ============================================================

drop policy if exists "Users view own orders"
on public.orders;

create policy "Users view own orders"
on public.orders
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users view own order items"
on public.order_items;

create policy "Users view own order items"
on public.order_items
for select
to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
    and o.user_id = (select auth.uid())
  )
);

-- ============================================================
-- AFFILIATE TASKS
-- ============================================================

drop policy if exists "Active tasks are visible"
on public.affiliate_tasks;

create policy "Active tasks are visible"
on public.affiliate_tasks
for select
to authenticated
using (active = true);

drop policy if exists "Advertisers view own tasks"
on public.affiliate_tasks;

create policy "Advertisers view own tasks"
on public.affiliate_tasks
for select
to authenticated
using ((select auth.uid()) = advertiser_id);

-- ============================================================
-- TASK SUBMISSIONS
-- ============================================================

drop policy if exists "Affiliates view own submissions"
on public.task_submissions;

create policy "Affiliates view own submissions"
on public.task_submissions
for select
to authenticated
using ((select auth.uid()) = affiliate_id);

drop policy if exists "Affiliates create submissions"
on public.task_submissions;

create policy "Affiliates create submissions"
on public.task_submissions
for insert
to authenticated
with check ((select auth.uid()) = affiliate_id);

-- ============================================================
-- REFERRALS
-- ============================================================

drop policy if exists "Users view own referrals"
on public.referrals;

create policy "Users view own referrals"
on public.referrals
for select
to authenticated
using (
  (select auth.uid()) = referrer_id
  or
  (select auth.uid()) = referred_user_id
);

-- ============================================================
-- WITHDRAWALS
-- ============================================================

drop policy if exists "Users view own withdrawals"
on public.withdrawals;

create policy "Users view own withdrawals"
on public.withdrawals
for select
to authenticated
using ((select auth.uid()) = user_id);

-- ============================================================
-- ADVERTISER CAMPAIGNS
-- ============================================================

drop policy if exists "Advertisers view own campaigns"
on public.advertiser_campaigns;

create policy "Advertisers view own campaigns"
on public.advertiser_campaigns
for select
to authenticated
using ((select auth.uid()) = advertiser_id);

drop policy if exists "Advertisers create campaigns"
on public.advertiser_campaigns;

create policy "Advertisers create campaigns"
on public.advertiser_campaigns
for insert
to authenticated
with check ((select auth.uid()) = advertiser_id);

-- ============================================================
-- SYNDICATION
-- ============================================================

drop policy if exists "Writers view own syndications"
on public.syndications;

create policy "Writers view own syndications"
on public.syndications
for select
to authenticated
using (
  exists (
    select 1
    from public.stories s
    where s.id = story_id
    and s.writer_id = (select auth.uid())
  )
);

-- ============================================================
-- DONE
-- ============================================================
