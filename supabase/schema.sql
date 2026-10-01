-- ============================================================
-- BREETHUB
-- INITIAL DATABASE FOUNDATION
-- ============================================================

create extension if not exists "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================

create type public.app_role as enum (
  'reader',
  'writer',
  'affiliate',
  'advertiser',
  'admin',
  'management',
  'secretary',
  'accountant',
  'customer_care'
);

create type public.account_status as enum (
  'active',
  'suspended',
  'deactivated'
);

create type public.content_status as enum (
  'draft',
  'pending_review',
  'approved',
  'published',
  'rejected',
  'suspended'
);

create type public.content_type as enum (
  'book',
  'novel',
  'series',
  'script',
  'article',
  'poetry',
  'quote',
  'video',
  'audiobook'
);

create type public.payment_status as enum (
  'pending',
  'under_review',
  'approved',
  'rejected',
  'cancelled',
  'refunded'
);

create type public.payment_type as enum (
  'course',
  'chapter',
  'book',
  'script',
  'article',
  'audio',
  'advertising',
  'investment',
  'registration',
  'other'
);

create type public.staff_permission as enum (
  'view_users',
  'manage_users',
  'view_content',
  'review_content',
  'manage_content',
  'view_courses',
  'manage_courses',
  'view_payments',
  'review_payments',
  'view_withdrawals',
  'manage_withdrawals',
  'view_investments',
  'manage_investments',
  'view_advertising',
  'manage_advertising',
  'view_affiliates',
  'manage_affiliates',
  'view_messages',
  'reply_messages',
  'manage_messages',
  'view_reports',
  'manage_rewards',
  'manage_music',
  'manage_settings'
);

-- ============================================================
-- PROFILES
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,

  email text,
  full_name text,
  nickname text,
  phone text,
  country text,
  country_code text,

  avatar_url text,
  bio text,

  role public.app_role not null default 'reader',
  account_status public.account_status not null default 'active',

  is_verified boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_role_idx
  on public.profiles(role);

create index profiles_country_idx
  on public.profiles(country);

create index profiles_nickname_idx
  on public.profiles(nickname);

-- ============================================================
-- STAFF PERMISSIONS
-- ============================================================

create table public.staff_permissions (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  permission public.staff_permission not null,

  granted_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),

  unique(user_id, permission)
);

create index staff_permissions_user_idx
  on public.staff_permissions(user_id);

-- ============================================================
-- HELPER: ADMIN CHECK
-- ============================================================

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and account_status = 'active'
  );
$$;

-- ============================================================
-- HELPER: STAFF PERMISSION CHECK
-- ============================================================

create or replace function public.has_staff_permission(
  requested_permission public.staff_permission
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin()
    or exists (
      select 1
      from public.staff_permissions sp
      join public.profiles p
        on p.id = sp.user_id
      where sp.user_id = auth.uid()
        and sp.permission = requested_permission
        and p.account_status = 'active'
    );
$$;

-- ============================================================
-- AUTO-CREATE PROFILE WHEN AUTH USER IS CREATED
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    email,
    full_name,
    nickname,
    phone,
    country,
    role
  )
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'nickname',
    new.raw_user_meta_data ->> 'phone',
    new.raw_user_meta_data ->> 'country',
    case
      when (new.raw_user_meta_data ->> 'role') in (
        'reader',
        'writer',
        'affiliate',
        'advertiser'
      )
      then (new.raw_user_meta_data ->> 'role')::public.app_role
      else 'reader'::public.app_role
    end
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created
on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

-- ============================================================
-- UPDATED_AT HELPER
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

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles enable row level security;

alter table public.staff_permissions enable row level security;

-- Users can read their own profile.
create policy "Users can read own profile"
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or public.is_admin()
);

-- Users can update their own non-role profile information.
create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using (
  id = auth.uid()
)
with check (
  id = auth.uid()
);

-- Admin can manage profiles.
create policy "Admins can manage profiles"
on public.profiles
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);

-- Users can see their own permissions.
create policy "Users can read own permissions"
on public.staff_permissions
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);

-- Admin controls staff permissions.
create policy "Admins manage staff permissions"
on public.staff_permissions
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);-- ============================================================
-- BREETHUB CONTENT SYSTEM
-- STORIES / BOOKS / SERIES / CHAPTERS / MEDIA
-- ============================================================

-- ============================================================
-- STORIES / CONTENT
-- ============================================================

create table public.stories (
  id uuid primary key default gen_random_uuid(),

  creator_id uuid not null
    references public.profiles(id)
    on delete cascade,

  title text not null,
  slug text not null unique,

  description text,

  content_type public.content_type not null default 'book',

  genre text,
  language text default 'English',

  cover_url text,

  status public.content_status not null default 'draft',

  is_featured boolean not null default false,
  is_investment_eligible boolean not null default false,

  -- Admin-controlled reading price.
  -- Writers do not control this field.
  reading_price numeric(12,2),
  reading_currency text,

  -- Admin can activate/change pricing after the required
  -- platform rules have been met.
  price_locked boolean not null default true,

  total_views bigint not null default 0,
  total_likes bigint not null default 0,
  total_saves bigint not null default 0,

  published_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint stories_price_non_negative
    check (
      reading_price is null
      or reading_price >= 0
    )
);

create index stories_creator_idx
  on public.stories(creator_id);

create index stories_status_idx
  on public.stories(status);

create index stories_content_type_idx
  on public.stories(content_type);

create index stories_genre_idx
  on public.stories(genre);

create index stories_featured_idx
  on public.stories(is_featured);

create index stories_slug_idx
  on public.stories(slug);

-- ============================================================
-- SERIES
-- ============================================================

create table public.series (
  id uuid primary key default gen_random_uuid(),

  creator_id uuid not null
    references public.profiles(id)
    on delete cascade,

  title text not null,
  slug text not null unique,

  description text,
  cover_url text,

  status public.content_status not null default 'draft',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index series_creator_idx
  on public.series(creator_id);

create index series_status_idx
  on public.series(status);

-- ============================================================
-- STORIES IN SERIES
-- ============================================================

create table public.series_stories (
  id uuid primary key default gen_random_uuid(),

  series_id uuid not null
    references public.series(id)
    on delete cascade,

  story_id uuid not null
    references public.stories(id)
    on delete cascade,

  position integer not null default 1,

  created_at timestamptz not null default now(),

  unique(series_id, story_id)
);

create index series_stories_series_idx
  on public.series_stories(series_id);

create index series_stories_story_idx
  on public.series_stories(story_id);

-- ============================================================
-- CHAPTERS
-- ============================================================

create table public.chapters (
  id uuid primary key default gen_random_uuid(),

  story_id uuid not null
    references public.stories(id)
    on delete cascade,

  title text not null,

  chapter_number integer not null,

  content text,

  word_count integer not null default 0,

  status public.content_status not null default 'draft',

  -- Admin-controlled access.
  is_free boolean not null default false,

  -- Admin-controlled chapter reading price.
  price numeric(12,2),
  price_currency text,

  -- Number of successful paid chapter purchases.
  paid_unlock_count bigint not null default 0,

  total_views bigint not null default 0,

  -- Audio/narration.
  audio_url text,
  audio_duration_seconds integer,

  -- Whether the audio has passed the required review.
  audio_approved boolean not null default false,

  published_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(story_id, chapter_number),

  constraint chapters_price_non_negative
    check (
      price is null
      or price >= 0
    ),

  constraint chapters_number_positive
    check (chapter_number > 0)
);

create index chapters_story_idx
  on public.chapters(story_id);

create index chapters_status_idx
  on public.chapters(status);

create index chapters_number_idx
  on public.chapters(chapter_number);

-- ============================================================
-- CONTENT FILES
-- ============================================================

create table public.content_files (
  id uuid primary key default gen_random_uuid(),

  content_id uuid not null
    references public.stories(id)
    on delete cascade,

  uploaded_by uuid not null
    references public.profiles(id)
    on delete cascade,

  file_type text not null,
  file_url text not null,

  original_filename text,
  mime_type text,
  file_size_bytes bigint,

  created_at timestamptz not null default now()
);

create index content_files_content_idx
  on public.content_files(content_id);

-- ============================================================
-- MANUSCRIPT SUBMISSIONS
-- ============================================================

create table public.manuscript_submissions (
  id uuid primary key default gen_random_uuid(),

  story_id uuid not null
    references public.stories(id)
    on delete cascade,

  submitted_by uuid not null
    references public.profiles(id)
    on delete cascade,

  manuscript_url text,

  version_number integer not null default 1,

  status public.content_status not null default 'pending_review',

  creator_notes text,
  reviewer_notes text,

  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,

  reviewed_by uuid
    references public.profiles(id)
    on delete set null
);

create index manuscript_story_idx
  on public.manuscript_submissions(story_id);

create index manuscript_status_idx
  on public.manuscript_submissions(status);

-- ============================================================
-- AI CONTENT REVIEWS
-- ============================================================

create table public.ai_content_reviews (
  id uuid primary key default gen_random_uuid(),

  story_id uuid
    references public.stories(id)
    on delete cascade,

  chapter_id uuid
    references public.chapters(id)
    on delete cascade,

  submitted_by uuid not null
    references public.profiles(id)
    on delete cascade,

  grammar_score numeric(5,2),
  readability_score numeric(5,2),
  consistency_score numeric(5,2),
  originality_score numeric(5,2),

  overall_score numeric(5,2),

  grammar_feedback text,
  readability_feedback text,
  consistency_feedback text,
  cover_story_feedback text,

  suggestions jsonb not null default '[]'::jsonb,

  review_status text not null default 'pending',

  created_at timestamptz not null default now()
);

create index ai_reviews_story_idx
  on public.ai_content_reviews(story_id);

create index ai_reviews_chapter_idx
  on public.ai_content_reviews(chapter_id);

create index ai_reviews_creator_idx
  on public.ai_content_reviews(submitted_by);

-- ============================================================
-- CONTENT APPROVALS
-- ============================================================

create table public.content_approvals (
  id uuid primary key default gen_random_uuid(),

  story_id uuid
    references public.stories(id)
    on delete cascade,

  chapter_id uuid
    references public.chapters(id)
    on delete cascade,

  submitted_by uuid not null
    references public.profiles(id)
    on delete cascade,

  reviewed_by uuid
    references public.profiles(id)
    on delete set null,

  status public.content_status not null default 'pending_review',

  reviewer_notes text,

  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,

  constraint content_approval_has_content
    check (
      story_id is not null
      or chapter_id is not null
    )
);

create index content_approvals_story_idx
  on public.content_approvals(story_id);

create index content_approvals_chapter_idx
  on public.content_approvals(chapter_id);

create index content_approvals_status_idx
  on public.content_approvals(status);

-- ============================================================
-- AUDIO / NARRATION
-- ============================================================

create table public.content_audio (
  id uuid primary key default gen_random_uuid(),

  story_id uuid
    references public.stories(id)
    on delete cascade,

  chapter_id uuid
    references public.chapters(id)
    on delete cascade,

  uploaded_by uuid not null
    references public.profiles(id)
    on delete cascade,

  audio_url text not null,

  narrator_name text,

  duration_seconds integer,

  status public.content_status not null default 'pending_review',

  created_at timestamptz not null default now(),

  constraint content_audio_has_content
    check (
      story_id is not null
      or chapter_id is not null
    )
);

create index content_audio_story_idx
  on public.content_audio(story_id);

create index content_audio_chapter_idx
  on public.content_audio(chapter_id);

-- ============================================================
-- CONTENT MUSIC
-- ============================================================

create table public.music_tracks (
  id uuid primary key default gen_random_uuid(),

  title text not null,

  artist_name text,

  audio_url text not null,

  cover_url text,

  license_type text,

  license_reference text,

  is_active boolean not null default true,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now()
);

create index music_tracks_active_idx
  on public.music_tracks(is_active);

-- ============================================================
-- AUDIO MIXES
-- ============================================================

create table public.audio_mixes (
  id uuid primary key default gen_random_uuid(),

  content_audio_id uuid not null
    references public.content_audio(id)
    on delete cascade,

  music_track_id uuid
    references public.music_tracks(id)
    on delete set null,

  narration_volume numeric(5,2) not null default 1.0,
  music_volume numeric(5,2) not null default 0.2,

  mixed_audio_url text,

  status public.content_status not null default 'draft',

  created_at timestamptz not null default now()
);

-- ============================================================
-- UPDATED_AT TRIGGERS
-- ============================================================

create trigger stories_set_updated_at
before update on public.stories
for each row
execute function public.set_updated_at();

create trigger series_set_updated_at
before update on public.series
for each row
execute function public.set_updated_at();

create trigger chapters_set_updated_at
before update on public.chapters
for each row
execute function public.set_updated_at();

-- ============================================================
-- CONTENT RLS
-- ============================================================

alter table public.stories enable row level security;
alter table public.series enable row level security;
alter table public.series_stories enable row level security;
alter table public.chapters enable row level security;
alter table public.content_files enable row level security;
alter table public.manuscript_submissions enable row level security;
alter table public.ai_content_reviews enable row level security;
alter table public.content_approvals enable row level security;
alter table public.content_audio enable row level security;
alter table public.music_tracks enable row level security;
alter table public.audio_mixes enable row level security;

-- ============================================================
-- STORIES POLICIES
-- ============================================================

create policy "Anyone can read published stories"
on public.stories
for select
to anon, authenticated
using (
  status = 'published'
);

create policy "Creators can read own stories"
on public.stories
for select
to authenticated
using (
  creator_id = auth.uid()
  or public.is_admin()
);

create policy "Creators can create stories"
on public.stories
for insert
to authenticated
with check (
  creator_id = auth.uid()
  and exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'writer'
      and account_status = 'active'
  )
);

create policy "Creators can update own stories"
on public.stories
for update
to authenticated
using (
  creator_id = auth.uid()
  or public.is_admin()
)
with check (
  creator_id = auth.uid()
  or public.is_admin()
);

create policy "Admins manage stories"
on public.stories
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);

-- ============================================================
-- SERIES POLICIES
-- ============================================================

create policy "Anyone can read published series"
on public.series
for select
to anon, authenticated
using (
  status = 'published'
);

create policy "Creators can manage own series"
on public.series
for all
to authenticated
using (
  creator_id = auth.uid()
  or public.is_admin()
)
with check (
  creator_id = auth.uid()
  or public.is_admin()
);

-- ============================================================
-- SERIES/STORY RELATION POLICIES
-- ============================================================

create policy "Anyone can read series stories"
on public.series_stories
for select
to anon, authenticated
using (true);

create policy "Admins manage series stories"
on public.series_stories
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);

create policy "Creators manage own series stories"
on public.series_stories
for all
to authenticated
using (
  exists (
    select 1
    from public.series s
    where s.id = series_id
      and s.creator_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.series s
    where s.id = series_id
      and s.creator_id = auth.uid()
  )
);

-- ============================================================
-- CHAPTER POLICIES
-- ============================================================

create policy "Anyone can read free published chapters"
on public.chapters
for select
to anon, authenticated
using (
  status = 'published'
  and is_free = true
);

create policy "Creators can read own chapters"
on public.chapters
for select
to authenticated
using (
  exists (
    select 1
    from public.stories s
    where s.id = story_id
      and s.creator_id = auth.uid()
  )
  or public.is_admin()
);

create policy "Creators can create own chapters"
on public.chapters
for insert
to authenticated
with check (
  exists (
    select 1
    from public.stories s
    where s.id = story_id
      and s.creator_id = auth.uid()
  )
);

create policy "Creators can update own chapters"
on public.chapters
for update
to authenticated
using (
  exists (
    select 1
    from public.stories s
    where s.id = story_id
      and s.creator_id = auth.uid()
  )
  or public.is_admin()
)
with check (
  exists (
    select 1
    from public.stories s
    where s.id = story_id
      and s.creator_id = auth.uid()
  )
  or public.is_admin()
);

create policy "Admins manage chapters"
on public.chapters
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);

-- ============================================================
-- MANUSCRIPT POLICIES
-- ============================================================

create policy "Creators read own manuscripts"
on public.manuscript_submissions
for select
to authenticated
using (
  submitted_by = auth.uid()
  or public.is_admin()
  or public.has_staff_permission('review_content')
);

create policy "Creators submit manuscripts"
on public.manuscript_submissions
for insert
to authenticated
with check (
  submitted_by = auth.uid()
);

create policy "Admins and authorized staff manage manuscripts"
on public.manuscript_submissions
for update
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission('review_content')
)
with check (
  public.is_admin()
  or public.has_staff_permission('review_content')
);

-- ============================================================
-- AI REVIEW POLICIES
-- ============================================================

create policy "Creators read own AI reviews"
on public.ai_content_reviews
for select
to authenticated
using (
  submitted_by = auth.uid()
  or public.is_admin()
  or public.has_staff_permission('review_content')
);

create policy "Creators create AI reviews"
on public.ai_content_reviews
for insert
to authenticated
with check (
  submitted_by = auth.uid()
);

create policy "Admins manage AI reviews"
on public.ai_content_reviews
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);

-- ============================================================
-- CONTENT APPROVAL POLICIES
-- ============================================================

create policy "Creators read own approvals"
on public.content_approvals
for select
to authenticated
using (
  submitted_by = auth.uid()
  or public.is_admin()
  or public.has_staff_permission('review_content')
);

create policy "Creators submit approvals"
on public.content_approvals
for insert
to authenticated
with check (
  submitted_by = auth.uid()
);

create policy "Authorized staff manage approvals"
on public.content_approvals
for update
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission('review_content')
)
with check (
  public.is_admin()
  or public.has_staff_permission('review_content')
);

-- ============================================================
-- MUSIC POLICIES
-- ============================================================

create policy "Anyone can read active music"
on public.music_tracks
for select
to authenticated
using (
  is_active = true
);

create policy "Admins manage music"
on public.music_tracks
for all
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission('manage_music')
)
with check (
  public.is_admin()
  or public.has_staff_permission('manage_music')
);

-- ============================================================
-- AUDIO POLICIES
-- ============================================================

create policy "Creators read own audio"
on public.content_audio
for select
to authenticated
using (
  uploaded_by = auth.uid()
  or public.is_admin()
  or public.has_staff_permission('review_content')
);

create policy "Creators upload own audio"
on public.content_audio
for insert
to authenticated
with check (
  uploaded_by = auth.uid()
);

create policy "Creators update own audio"
on public.content_audio
for update
to authenticated
using (
  uploaded_by = auth.uid()
  or public.is_admin()
)
with check (
  uploaded_by = auth.uid()
  or public.is_admin()
);

create policy "Authorized staff manage audio"
on public.content_audio
for all
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission('review_content')
)
with check (
  public.is_admin()
  or public.has_staff_permission('review_content')
);

-- ============================================================
-- AUDIO MIX POLICIES
-- ============================================================

create policy "Users can read approved audio mixes"
on public.audio_mixes
for select
to authenticated
using (
  status = 'approved'
  or public.is_admin()
);

create policy "Admins manage audio mixes"
on public.audio_mixes
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);

-- ============================================================
-- CONTENT FILE POLICIES
-- ============================================================

create policy "Owners can read content files"
on public.content_files
for select
to authenticated
using (
  uploaded_by = auth.uid()
  or public.is_admin()
);

create policy "Owners can upload content files"
on public.content_files
for insert
to authenticated
with check (
  uploaded_by = auth.uid()
);

create policy "Admins manage content files"
on public.content_files
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);-- ============================================================
-- BREETHUB COURSES + ONBOARDING + PAYMENTS
-- BATCH 3
-- ============================================================


-- ============================================================
-- COURSE TYPES
-- ============================================================

create type public.course_type as enum (
  'required_onboarding',
  'ai_training',
  'for_sale',
  'affiliate_promotable'
);


-- ============================================================
-- COURSE STATUS
-- ============================================================

create type public.course_status as enum (
  'draft',
  'active',
  'paused',
  'archived'
);


-- ============================================================
-- COURSE ENROLLMENT STATUS
-- ============================================================

create type public.course_enrollment_status as enum (
  'pending_payment',
  'payment_pending_review',
  'active',
  'completed',
  'cancelled'
);


-- ============================================================
-- COURSE LESSON STATUS
-- ============================================================

create type public.lesson_completion_status as enum (
  'not_started',
  'in_progress',
  'completed'
);


-- ============================================================
-- PAYMENT METHOD
-- ============================================================

create type public.payment_method as enum (
  'flutterwave',
  'bank_transfer',
  'other'
);


-- ============================================================
-- COURSE ACCESS
-- ============================================================

create type public.course_access_status as enum (
  'locked',
  'pending_payment',
  'pending_approval',
  'approved',
  'completed',
  'rejected'
);


-- ============================================================
-- COURSES
-- ============================================================

create table public.courses (
  id uuid primary key default gen_random_uuid(),

  title text not null,

  slug text not null unique,

  description text,

  cover_url text,

  category text,

  course_type public.course_type not null,

  status public.course_status not null default 'draft',

  -- Admin-controlled pricing.
  price_ngn numeric(12,2),
  price_usd numeric(12,2),
  price_gbp numeric(12,2),
  price_eur numeric(12,2),

  -- Whether affiliates are allowed to promote this course.
  affiliate_promotion_enabled boolean not null default false,

  -- Admin-controlled affiliate commission.
  affiliate_commission_rate numeric(5,2),

  created_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint course_prices_non_negative
    check (
      (price_ngn is null or price_ngn >= 0)
      and
      (price_usd is null or price_usd >= 0)
      and
      (price_gbp is null or price_gbp >= 0)
      and
      (price_eur is null or price_eur >= 0)
    ),

  constraint affiliate_commission_valid
    check (
      affiliate_commission_rate is null
      or (
        affiliate_commission_rate >= 0
        and affiliate_commission_rate <= 100
      )
    )
);

create index courses_type_idx
  on public.courses(course_type);

create index courses_status_idx
  on public.courses(status);

create index courses_category_idx
  on public.courses(category);


-- ============================================================
-- COURSE LESSONS
-- ============================================================

create table public.course_lessons (
  id uuid primary key default gen_random_uuid(),

  course_id uuid not null
    references public.courses(id)
    on delete cascade,

  title text not null,

  description text,

  lesson_number integer not null,

  video_url text,

  content text,

  duration_seconds integer,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(course_id, lesson_number),

  constraint lesson_number_positive
    check (lesson_number > 0)
);

create index course_lessons_course_idx
  on public.course_lessons(course_id);


-- ============================================================
-- COURSE ENROLLMENTS
-- ============================================================

create table public.course_enrollments (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  course_id uuid not null
    references public.courses(id)
    on delete cascade,

  status public.course_enrollment_status
    not null default 'pending_payment',

  access_status public.course_access_status
    not null default 'locked',

  progress_percentage numeric(5,2) not null default 0,

  completed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(user_id, course_id),

  constraint enrollment_progress_valid
    check (
      progress_percentage >= 0
      and progress_percentage <= 100
    )
);

create index course_enrollments_user_idx
  on public.course_enrollments(user_id);

create index course_enrollments_course_idx
  on public.course_enrollments(course_id);

create index course_enrollments_status_idx
  on public.course_enrollments(status);


-- ============================================================
-- LESSON PROGRESS
-- ============================================================

create table public.course_lesson_progress (
  id uuid primary key default gen_random_uuid(),

  enrollment_id uuid not null
    references public.course_enrollments(id)
    on delete cascade,

  lesson_id uuid not null
    references public.course_lessons(id)
    on delete cascade,

  status public.lesson_completion_status
    not null default 'not_started',

  completed_at timestamptz,

  last_position_seconds integer not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(enrollment_id, lesson_id)
);

create index lesson_progress_enrollment_idx
  on public.course_lesson_progress(enrollment_id);

create index lesson_progress_lesson_idx
  on public.course_lesson_progress(lesson_id);


-- ============================================================
-- COURSE ASSESSMENTS
-- ============================================================

create table public.course_assessments (
  id uuid primary key default gen_random_uuid(),

  course_id uuid not null
    references public.courses(id)
    on delete cascade,

  title text not null,

  description text,

  passing_score numeric(5,2) not null default 80,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),

  constraint assessment_passing_score_valid
    check (
      passing_score >= 0
      and passing_score <= 100
    )
);

create index course_assessments_course_idx
  on public.course_assessments(course_id);


-- ============================================================
-- ASSESSMENT QUESTIONS
-- ============================================================

create table public.assessment_questions (
  id uuid primary key default gen_random_uuid(),

  assessment_id uuid not null
    references public.course_assessments(id)
    on delete cascade,

  question text not null,

  question_number integer not null,

  options jsonb not null default '[]'::jsonb,

  correct_answer text not null,

  points numeric(8,2) not null default 1,

  created_at timestamptz not null default now(),

  unique(assessment_id, question_number)
);

create index assessment_questions_assessment_idx
  on public.assessment_questions(assessment_id);


-- ============================================================
-- ASSESSMENT ATTEMPTS
-- ============================================================

create table public.assessment_attempts (
  id uuid primary key default gen_random_uuid(),

  assessment_id uuid not null
    references public.course_assessments(id)
    on delete cascade,

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  score numeric(5,2),

  passed boolean not null default false,

  answers jsonb not null default '{}'::jsonb,

  started_at timestamptz not null default now(),

  completed_at timestamptz
);

create index assessment_attempts_user_idx
  on public.assessment_attempts(user_id);

create index assessment_attempts_assessment_idx
  on public.assessment_attempts(assessment_id);


-- ============================================================
-- WRITER ONBOARDING
-- ============================================================

create table public.writer_onboarding (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null unique
    references public.profiles(id)
    on delete cascade,

  ghostwriting_course_id uuid
    references public.courses(id)
    on delete set null,

  ai_bootcamp_course_id uuid
    references public.courses(id)
    on delete set null,

  ghostwriting_access public.course_access_status
    not null default 'locked',

  ai_bootcamp_access public.course_access_status
    not null default 'locked',

  ghostwriting_completed boolean not null default false,

  ai_bootcamp_completed boolean not null default false,

  assessment_passed boolean not null default false,

  assessment_score numeric(5,2),

  dashboard_unlocked boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index writer_onboarding_user_idx
  on public.writer_onboarding(user_id);


-- ============================================================
-- AFFILIATE ONBOARDING
-- ============================================================

create table public.affiliate_onboarding (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null unique
    references public.profiles(id)
    on delete cascade,

  affiliate_course_id uuid
    references public.courses(id)
    on delete set null,

  ai_bootcamp_course_id uuid
    references public.courses(id)
    on delete set null,

  affiliate_course_access public.course_access_status
    not null default 'locked',

  ai_bootcamp_access public.course_access_status
    not null default 'locked',

  affiliate_course_completed boolean not null default false,

  ai_bootcamp_completed boolean not null default false,

  assessment_passed boolean not null default false,

  assessment_score numeric(5,2),

  dashboard_unlocked boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index affiliate_onboarding_user_idx
  on public.affiliate_onboarding(user_id);


-- ============================================================
-- PAYMENTS
-- ============================================================

create table public.payments (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  payment_type public.payment_type not null,

  method public.payment_method,

  amount numeric(12,2) not null,

  currency text not null,

  provider text,

  provider_reference text,

  provider_transaction_id text,

  purpose text,

  course_id uuid
    references public.courses(id)
    on delete set null,

  story_id uuid
    references public.stories(id)
    on delete set null,

  chapter_id uuid
    references public.chapters(id)
    on delete set null,

  status public.payment_status not null default 'pending',

  paid_at timestamptz,

  verified_at timestamptz,

  verified_by uuid
    references public.profiles(id)
    on delete set null,

  rejection_reason text,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint payment_amount_positive
    check (amount > 0)
);

create index payments_user_idx
  on public.payments(user_id);

create index payments_status_idx
  on public.payments(status);

create index payments_type_idx
  on public.payments(payment_type);

create index payments_reference_idx
  on public.payments(provider_reference);

create index payments_created_idx
  on public.payments(created_at);


-- ============================================================
-- PAYMENT PROOFS
-- ============================================================

create table public.payment_proofs (
  id uuid primary key default gen_random_uuid(),

  payment_id uuid not null
    references public.payments(id)
    on delete cascade,

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  proof_url text not null,

  proof_filename text,

  submitted_at timestamptz not null default now(),

  reviewed_at timestamptz,

  reviewed_by uuid
    references public.profiles(id)
    on delete set null,

  status public.payment_status not null default 'pending',

  rejection_reason text
);

create index payment_proofs_payment_idx
  on public.payment_proofs(payment_id);

create index payment_proofs_user_idx
  on public.payment_proofs(user_id);

create index payment_proofs_status_idx
  on public.payment_proofs(status);


-- ============================================================
-- PAYMENT REVIEW HISTORY
-- ============================================================

create table public.payment_review_history (
  id uuid primary key default gen_random_uuid(),

  payment_id uuid not null
    references public.payments(id)
    on delete cascade,

  reviewed_by uuid not null
    references public.profiles(id)
    on delete restrict,

  old_status public.payment_status,

  new_status public.payment_status not null,

  reason text,

  created_at timestamptz not null default now()
);

create index payment_review_history_payment_idx
  on public.payment_review_history(payment_id);


-- ============================================================
-- COURSE ACCESS REQUESTS
-- ============================================================

create table public.course_access_requests (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  course_id uuid not null
    references public.courses(id)
    on delete cascade,

  payment_id uuid
    references public.payments(id)
    on delete set null,

  status public.course_access_status
    not null default 'pending_payment',

  reviewed_by uuid
    references public.profiles(id)
    on delete set null,

  reviewed_at timestamptz,

  rejection_reason text,

  created_at timestamptz not null default now()
);

create index course_access_requests_user_idx
  on public.course_access_requests(user_id);

create index course_access_requests_course_idx
  on public.course_access_requests(course_id);

create index course_access_requests_status_idx
  on public.course_access_requests(status);


-- ============================================================
-- COURSE COVER / MEDIA
-- ============================================================

create table public.course_media (
  id uuid primary key default gen_random_uuid(),

  course_id uuid not null
    references public.courses(id)
    on delete cascade,

  media_type text not null,

  file_url text not null,

  original_filename text,

  mime_type text,

  file_size_bytes bigint,

  uploaded_by uuid not null
    references public.profiles(id)
    on delete cascade,

  created_at timestamptz not null default now()
);

create index course_media_course_idx
  on public.course_media(course_id);


-- ============================================================
-- COURSE UPDATED_AT TRIGGERS
-- ============================================================

create trigger courses_set_updated_at
before update on public.courses
for each row
execute function public.set_updated_at();

create trigger course_lessons_set_updated_at
before update on public.course_lessons
for each row
execute function public.set_updated_at();

create trigger course_enrollments_set_updated_at
before update on public.course_enrollments
for each row
execute function public.set_updated_at();

create trigger course_lesson_progress_set_updated_at
before update on public.course_lesson_progress
for each row
execute function public.set_updated_at();

create trigger writer_onboarding_set_updated_at
before update on public.writer_onboarding
for each row
execute function public.set_updated_at();

create trigger affiliate_onboarding_set_updated_at
before update on public.affiliate_onboarding
for each row
execute function public.set_updated_at();

create trigger payments_set_updated_at
before update on public.payments
for each row
execute function public.set_updated_at();


-- ============================================================
-- COURSE RLS
-- ============================================================

alter table public.courses enable row level security;
alter table public.course_lessons enable row level security;
alter table public.course_enrollments enable row level security;
alter table public.course_lesson_progress enable row level security;
alter table public.course_assessments enable row level security;
alter table public.assessment_questions enable row level security;
alter table public.assessment_attempts enable row level security;
alter table public.writer_onboarding enable row level security;
alter table public.affiliate_onboarding enable row level security;
alter table public.payments enable row level security;
alter table public.payment_proofs enable row level security;
alter table public.payment_review_history enable row level security;
alter table public.course_access_requests enable row level security;
alter table public.course_media enable row level security;


-- ============================================================
-- COURSES POLICIES
-- ============================================================

create policy "Anyone can read active courses"
on public.courses
for select
to anon, authenticated
using (
  status = 'active'
);

create policy "Admins manage courses"
on public.courses
for all
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission('manage_courses')
)
with check (
  public.is_admin()
  or public.has_staff_permission('manage_courses')
);


-- ============================================================
-- COURSE LESSON POLICIES
-- ============================================================

create policy "Enrolled users can read active lessons"
on public.course_lessons
for select
to authenticated
using (
  exists (
    select 1
    from public.course_enrollments ce
    where ce.course_id = course_lessons.course_id
      and ce.user_id = auth.uid()
      and ce.access_status in (
        'approved',
        'completed'
      )
  )
  or public.is_admin()
);

create policy "Admins manage course lessons"
on public.course_lessons
for all
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission('manage_courses')
)
with check (
  public.is_admin()
  or public.has_staff_permission('manage_courses')
);


-- ============================================================
-- COURSE ENROLLMENT POLICIES
-- ============================================================

create policy "Users read own enrollments"
on public.course_enrollments
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
  or public.has_staff_permission('view_courses')
);

create policy "Users create own enrollments"
on public.course_enrollments
for insert
to authenticated
with check (
  user_id = auth.uid()
);

create policy "Users update own enrollment progress"
on public.course_enrollments
for update
to authenticated
using (
  user_id = auth.uid()
)
with check (
  user_id = auth.uid()
);

create policy "Authorized staff manage enrollments"
on public.course_enrollments
for all
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission('manage_courses')
)
with check (
  public.is_admin()
  or public.has_staff_permission('manage_courses')
);


-- ============================================================
-- LESSON PROGRESS POLICIES
-- ============================================================

create policy "Users manage own lesson progress"
on public.course_lesson_progress
for all
to authenticated
using (
  exists (
    select 1
    from public.course_enrollments ce
    where ce.id = enrollment_id
      and ce.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.course_enrollments ce
    where ce.id = enrollment_id
      and ce.user_id = auth.uid()
  )
);


-- ============================================================
-- ASSESSMENT POLICIES
-- ============================================================

create policy "Enrolled users read active assessments"
on public.course_assessments
for select
to authenticated
using (
  is_active = true
  and exists (
    select 1
    from public.course_enrollments ce
    where ce.course_id = course_assessments.course_id
      and ce.user_id = auth.uid()
      and ce.access_status in (
        'approved',
        'completed'
      )
  )
  or public.is_admin()
);

create policy "Authorized staff manage assessments"
on public.course_assessments
for all
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission('manage_courses')
)
with check (
  public.is_admin()
  or public.has_staff_permission('manage_courses')
);


-- ============================================================
-- ASSESSMENT QUESTIONS
-- ============================================================

create policy "Enrolled users read assessment questions"
on public.assessment_questions
for select
to authenticated
using (
  exists (
    select 1
    from public.course_assessments ca
    join public.course_enrollments ce
      on ce.course_id = ca.course_id
    where ca.id = assessment_questions-- ============================================================
-- BREETHUB REQUIRED ONBOARDING COURSES
-- ============================================================

insert into public.courses (
  title,
  slug,
  description,
  category,
  course_type,
  status,
  price_ngn,
  price_usd,
  price_gbp,
  price_eur,
  affiliate_promotion_enabled
)
values
(
  'Ghostwriting Mastery',
  'ghostwriting-mastery',
  'Required onboarding course for Breethub writers.',
  'Writing',
  'required_onboarding',
  'active',
  15000,
  20,
  20,
  20,
  false
),
(
  'Affiliate Marketing Mastery',
  'affiliate-marketing-mastery',
  'Required onboarding course for Breethub affiliates.',
  'Affiliate Marketing',
  'required_onboarding',
  'active',
  15000,
  20,
  20,
  20,
  false
),
(
  'AI Bootcamp',
  'ai-bootcamp',
  'Required AI training for Breethub writers and affiliates.',
  'Artificial Intelligence',
  'ai_training',
  'active',
  5000,
  5,
  5,
  5,
  false
)
on conflict (slug) do nothing;-- ============================================================
-- BREETHUB BATCH 4
-- WALLETS, CHAPTER PURCHASES, REVENUE SPLITS,
-- WITHDRAWALS, CURRENCY RULES AND FREE SPIN
-- ============================================================


-- ============================================================
-- 1. CURRENCY
-- ============================================================

create type public.supported_currency as enum (
  'NGN',
  'USD',
  'GBP',
  'EUR',
  'GHS',
  'KES'
);


-- ============================================================
-- 2. WALLET
-- Each user can have one wallet per supported currency.
-- ============================================================

create table if not exists public.wallets (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  currency public.supported_currency not null,

  available_balance numeric(18,2) not null default 0,
  pending_balance numeric(18,2) not null default 0,
  withdrawn_balance numeric(18,2) not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(user_id, currency),

  constraint wallet_available_nonnegative
    check (available_balance >= 0),

  constraint wallet_pending_nonnegative
    check (pending_balance >= 0),

  constraint wallet_withdrawn_nonnegative
    check (withdrawn_balance >= 0)
);


-- ============================================================
-- 3. WALLET TRANSACTION TYPES
-- ============================================================

create type public.wallet_transaction_type as enum (
  'chapter_purchase',
  'book_purchase',
  'course_purchase',
  'affiliate_commission',
  'writer_earning',
  'investment_contribution',
  'investment_return',
  'gift_received',
  'reward_credit',
  'withdrawal',
  'withdrawal_reversal',
  'refund',
  'admin_adjustment',
  'advertising_payment',
  'platform_revenue',
  'investor_pool_contribution'
);


-- ============================================================
-- 4. WALLET TRANSACTIONS
-- Immutable-style financial ledger.
-- ============================================================

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),

  wallet_id uuid not null references public.wallets(id) on delete restrict,

  user_id uuid not null references public.profiles(id) on delete restrict,

  transaction_type public.wallet_transaction_type not null,

  amount numeric(18,2) not null,

  currency public.supported_currency not null,

  direction text not null
    check (direction in ('credit', 'debit')),

  status text not null default 'pending'
    check (status in ('pending', 'completed', 'reversed', 'cancelled')),

  description text,

  payment_id uuid references public.payments(id) on delete set null,

  chapter_id uuid references public.chapters(id) on delete set null,

  story_id uuid references public.stories(id) on delete set null,

  course_id uuid references public.courses(id) on delete set null,

  withdrawal_id uuid,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  completed_at timestamptz
);


-- ============================================================
-- 5. READING PRICE CONFIGURATION
--
-- Admin controls the actual price.
--
-- Default NGN chapter reading fee:
-- ₦200
--
-- Split:
-- Writer = 25%
-- Investor pool = 25%
-- Admin = 50%
--
-- Therefore:
-- ₦200
-- Writer = ₦50
-- Investor pool = ₦50
-- Admin = ₦100
-- ============================================================

create table if not exists public.reading_price_settings (
  id uuid primary key default gen_random_uuid(),

  currency public.supported_currency not null unique,

  chapter_price numeric(18,2) not null default 0,

  writer_percentage numeric(5,2) not null default 25.00,

  investor_percentage numeric(5,2) not null default 25.00,

  admin_percentage numeric(5,2) not null default 50.00,

  minimum_price numeric(18,2) not null default 0,

  price_locked boolean not null default true,

  active boolean not null default true,

  updated_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint reading_split_must_equal_100
    check (
      writer_percentage
      + investor_percentage
      + admin_percentage = 100
    ),

  constraint reading_price_nonnegative
    check (chapter_price >= 0)
);


-- ============================================================
-- DEFAULT PRICING
-- ============================================================

insert into public.reading_price_settings (
  currency,
  chapter_price,
  writer_percentage,
  investor_percentage,
  admin_percentage
)
values
  ('NGN', 200.00, 25.00, 25.00, 50.00),
  ('USD', 2.00, 25.00, 25.00, 50.00),
  ('GBP', 2.00, 25.00, 25.00, 50.00),
  ('EUR', 2.00, 25.00, 25.00, 50.00),
  ('GHS', 20.00, 25.00, 25.00, 50.00),
  ('KES', 200.00, 25.00, 25.00, 50.00)
on conflict (currency) do nothing;


-- ============================================================
-- 6. CURRENCY PAYMENT RULES
--
-- Admin can decide which currencies are directly payable.
--
-- NGN/USD/GBP/EUR can be enabled directly.
-- GHS/KES are initially marked as conversion currencies.
-- The application should display a converted local amount
-- while the actual supported settlement currency is determined
-- by the payment provider.
-- ============================================================

create table if not exists public.currency_payment_rules (
  id uuid primary key default gen_random_uuid(),

  currency public.supported_currency not null unique,

  direct_payment_enabled boolean not null default false,

  settlement_currency public.supported_currency not null default 'USD',

  display_enabled boolean not null default true,

  updated_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);


insert into public.currency_payment_rules (
  currency,
  direct_payment_enabled,
  settlement_currency
)
values
  ('NGN', true, 'NGN'),
  ('USD', true, 'USD'),
  ('GBP', true, 'GBP'),
  ('EUR', true, 'EUR'),
  ('GHS', false, 'USD'),
  ('KES', false, 'USD')
on conflict (currency) do nothing;


-- ============================================================
-- 7. FX RATE STORAGE
--
-- Rates will eventually come from a real FX provider.
-- We do NOT fake live exchange rates here.
-- ============================================================

create table if not exists public.exchange_rates (
  id uuid primary key default gen_random_uuid(),

  base_currency public.supported_currency not null,

  quote_currency public.supported_currency not null,

  rate numeric(20,10) not null,

  source text,

  fetched_at timestamptz not null default now(),

  expires_at timestamptz,

  active boolean not null default true,

  unique(base_currency, quote_currency),

  constraint exchange_rate_positive
    check (rate > 0)
);


-- ============================================================
-- 8. CHAPTER PURCHASES
-- ============================================================

create type public.chapter_purchase_status as enum (
  'pending_payment',
  'payment_pending_review',
  'approved',
  'rejected',
  'refunded',
  'cancelled'
);


create table if not exists public.chapter_purchases (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete restrict,

  story_id uuid not null references public.stories(id) on delete restrict,

  chapter_id uuid not null references public.chapters(id) on delete restrict,

  payment_id uuid references public.payments(id) on delete set null,

  currency public.supported_currency not null,

  amount numeric(18,2) not null,

  writer_amount numeric(18,2) not null default 0,

  investor_pool_amount numeric(18,2) not null default 0,

  admin_amount numeric(18,2) not null default 0,

  status public.chapter_purchase_status not null default 'pending_payment',

  purchased_at timestamptz,

  approved_at timestamptz,

  approved_by uuid references public.profiles(id) on delete set null,

  refunded_at timestamptz,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  unique(user_id, chapter_id)
);


-- ============================================================
-- 9. FULL BOOK PURCHASES
-- ============================================================

create type public.book_purchase_status as enum (
  'pending_payment',
  'payment_pending_review',
  'approved',
  'rejected',
  'refunded',
  'cancelled'
);


create table if not exists public.book_purchases (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete restrict,

  story_id uuid not null references public.stories(id) on delete restrict,

  payment_id uuid references public.payments(id) on delete set null,

  currency public.supported_currency not null,

  amount numeric(18,2) not null,

  status public.book_purchase_status not null default 'pending_payment',

  purchased_at timestamptz,

  approved_at timestamptz,

  approved_by uuid references public.profiles(id) on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  unique(user_id, story_id)
);


-- ============================================================
-- 10. CONTENT ACCESS
--
-- This is what actually unlocks paid chapters.
-- Frontend labels alone NEVER unlock content.
-- ============================================================

create table if not exists public.content_access (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  story_id uuid not null references public.stories(id) on delete cascade,

  chapter_id uuid references public.chapters(id) on delete cascade,

  book_purchase_id uuid references public.book_purchases(id) on delete cascade,

  chapter_purchase_id uuid references public.chapter_purchases(id) on delete cascade,

  access_type text not null
    check (access_type in (
      'chapter_purchase',
      'full_book_purchase',
      'free_reward',
      'admin_grant'
    )),

  granted_at timestamptz not null default now(),

  expires_at timestamptz,

  active boolean not null default true,

  unique(user_id, chapter_id, access_type)
);


-- ============================================================
-- 11. INVESTOR POOL LEDGER
--
-- This records the 25% investor allocation separately.
-- It does NOT automatically promise a return.
-- Actual investment functionality requires legal/regulatory review.
-- ============================================================

create table if not exists public.investor_pool_ledger (
  id uuid primary key default gen_random_uuid(),

  chapter_purchase_id uuid references public.chapter_purchases(id) on delete set null,

  story_id uuid references public.stories(id) on delete set null,

  chapter_id uuid references public.chapters(id) on delete set null,

  currency public.supported_currency not null,

  amount numeric(18,2) not null,

  status text not null default 'pending'
    check (status in ('pending', 'available', 'allocated', 'reversed')),

  created_at timestamptz not null default now(),

  allocated_at timestamptz
);


-- ============================================================
-- 12. WITHDRAWALS
-- ============================================================

create type public.withdrawal_status as enum (
  'pending',
  'under_review',
  'approved',
  'processing',
  'paid',
  'rejected',
  'cancelled'
);


create table if not exists public.withdrawals (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete restrict,

  wallet_id uuid not null references public.wallets(id) on delete restrict,

  currency public.supported_currency not null,

  amount numeric(18,2) not null,

  status public.withdrawal_status not null default 'pending',

  requested_at timestamptz not null default now(),

  reviewed_at timestamptz,

  reviewed_by uuid references public.profiles(id) on delete set null,

  processed_at timestamptz,

  payout_reference text,

  rejection_reason text,

  payout_method text,

  payout_details jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now()
);


-- ============================================================
-- 13. WITHDRAWAL SCHEDULE
--
-- Writer/Affiliate withdrawals are intended to be available
-- every two weeks, subject to approval and platform rules.
-- ============================================================

create table if not exists public.withdrawal_settings (
  id uuid primary key default gen_random_uuid(),

  role public.app_role not null unique,

  withdrawal_interval_days integer not null default 14,

  minimum_withdrawal numeric(18,2) not null default 0,

  enabled boolean not null default true,

  updated_by uuid references public.profiles(id) on delete set null,

  updated_at timestamptz not null default now(),

  constraint withdrawal_interval_positive
    check (withdrawal_interval_days > 0)
);


insert into public.withdrawal_settings (
  role,
  withdrawal_interval_days,
  minimum_withdrawal
)
values
  ('writer', 14, 0),
  ('affiliate', 14, 0)
on conflict (role) do nothing;


-- ============================================================
-- 14. LAST WITHDRAWAL RECORD
-- Helps enforce the 14-day interval.
-- ============================================================

create index if not exists withdrawals_user_requested_idx
on public.withdrawals(user_id, requested_at desc);


-- ============================================================
-- 15. FREE SPIN
--
-- Rule:
-- After 10 successfully approved paid chapter purchases,
-- reader earns 1 free spin.
--
-- Only APPROVED purchases count.
-- Cancelled/rejected/refunded purchases do not count.
-- ============================================================

create table if not exists public.reader_reward_progress (
  user_id uuid primary key references public.profiles(id) on delete cascade,

  paid_chapters_count integer not null default 0,

  spins_earned integer not null default 0,

  spins_used integer not null default 0,

  next_spin_available_at timestamptz,

  updated_at timestamptz not null default now(),

  constraint paid_chapters_nonnegative
    check (paid_chapters_count >= 0),

  constraint spins_earned_nonnegative
    check (spins_earned >= 0),

  constraint spins_used_nonnegative
    check (spins_used >= 0)
);


create type public.reward_type as enum (
  'free_chapter',
  'two_free_chapters',
  'three_free_chapters',
  'reading_credit',
  'another_spin',
  'special_reward',
  'try_again'
);


create table if not exists public.free_spin_rewards (
  id uuid primary key default gen_random_uuid(),

  reward_type public.reward_type not null,

  title text not null,

  description text,

  reward_value numeric(18,2),

  active boolean not null default true,

  weight numeric(10,4) not null default 1,

  created_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint reward_weight_positive
    check (weight > 0)
);


-- ============================================================
-- 16. FREE SPIN HISTORY
-- ============================================================

create table if not exists public.free_spin_history (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  reward_id uuid references public.free_spin_rewards(id) on delete set null,

  reward_type public.reward_type,

  reward_value numeric(18,2),

  spun_at timestamptz not null default now(),

  metadata jsonb not null default '{}'::jsonb
);


-- ============================================================
-- 17. REWARD CLAIMS
-- ============================================================

create type public.reward_claim_status as enum (
  'pending',
  'granted',
  'used',
  'expired',
  'cancelled'
);


create table if not exists public.reward_claims (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id) on delete cascade,

  spin_history_id uuid references public.free_spin_history(id) on delete set null,

  reward_type public.reward_type not null,

  chapter_id uuid references public.chapters(id) on delete set null,

  story_id uuid references public.stories(id) on delete set null,

  amount numeric(18,2),

  currency public.supported_currency,

  status public.reward_claim_status not null default 'granted',

  expires_at timestamptz,

  created_at timestamptz not null default now(),

  used_at timestamptz
);


-- ============================================================
-- 18. INDEXES
-- ============================================================

create index if not exists wallets_user_idx
on public.wallets(user_id);

create index if not exists wallet_transactions_user_idx
on public.wallet_transactions(user_id, created_at desc);

create index if not exists wallet_transactions_wallet_idx
on public.wallet_transactions(wallet_id, created_at desc);

create index if not exists chapter_purchases_user_idx
on public.chapter_purchases(user_id, created_at desc);

create index if not exists chapter_purchases_chapter_idx
on public.chapter_purchases(chapter_id);

create index if not exists chapter_purchases_status_idx
on public.chapter_purchases(status);

create index if not exists book_purchases_user_idx
on public.book_purchases(user_id, created_at desc);

create index if not exists content_access_user_idx
on public.content_access(user_id);

create index if not exists content_access_chapter_idx
on public.content_access(chapter_id);

create index if not exists investor_pool_story_idx
on public.investor_pool_ledger(story_id);

create index if not exists investor_pool_chapter_idx
on public.investor_pool_ledger(chapter_id);

create index if not exists free_spin_history_user_idx
on public.free_spin_history(user_id, spun_at desc);

create index if not exists reward_claims_user_idx
on public.reward_claims(user_id, created_at desc);


-- ============================================================
-- 19. UPDATED_AT TRIGGERS
-- ============================================================

drop trigger if exists wallets_updated_at on public.wallets;

create trigger wallets_updated_at
before update on public.wallets
for each row
execute function public.set_updated_at();


drop trigger if exists reading_price_settings_updated_at
on public.reading_price_settings;

create trigger reading_price_settings_updated_at
before update on public.reading_price_settings
for each row
execute function public.set_updated_at();


drop trigger if exists currency_payment_rules_updated_at
on public.currency_payment_rules;

create trigger currency_payment_rules_updated_at
before update on public.currency_payment_rules
for each row
execute function public.set_updated_at();


drop trigger if exists reader_reward_progress_updated_at
on public.reader_reward_progress;

create trigger reader_reward_progress_updated_at
before update on public.reader_reward_progress
for each row
execute function public.set_updated_at();


drop trigger if exists free_spin_rewards_updated_at
on public.free_spin_rewards;

create trigger free_spin_rewards_updated_at
before update on public.free_spin_rewards
for each row
execute function public.set_updated_at();


-- ============================================================
-- 20. CREATE WALLET FOR A USER
-- ============================================================

create or replace function public.create_user_wallets()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  insert into public.wallets(user_id, currency)
  values
    (new.id, 'NGN'),
    (new.id, 'USD'),
    (new.id, 'GBP'),
    (new.id, 'EUR'),
    (new.id, 'GHS'),
    (new.id, 'KES')
  on conflict (user_id, currency) do nothing;

  insert into public.reader_reward_progress(user_id)
  values(new.id)
  on conflict(user_id) do nothing;

  return new;

end;
$$;


drop trigger if exists create_wallets_after_profile
on public.profiles;

create trigger create_wallets_after_profile
after insert on public.profiles
for each row
execute function public.create_user_wallets();


-- ============================================================
-- 21. CONTENT ACCESS CHECK
-- ============================================================

create or replace function public.user_has_chapter_access(
  p_user_id uuid,
  p_chapter_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_story_id uuid;
begin

  select story_id
  into v_story_id
  from public.chapters
  where id = p_chapter_id;

  if v_story_id is null then
    return false;
  end if;

  -- Free chapter
  if exists (
    select 1
    from public.chapters
    where id = p_chapter_id
      and is_free = true
      and status = 'published'
  ) then
    return true;
  end if;

  -- Approved chapter purchase
  if exists (
    select 1
    from public.chapter_purchases
    where user_id = p_user_id
      and chapter_id = p_chapter_id
      and status = 'approved'
  ) then
    return true;
  end if;

  -- Full book purchase
  if exists (
    select 1
    from public.book_purchases
    where user_id = p_user_id
      and story_id = v_story_id
      and status = 'approved'
  ) then
    return true;
  end if;

  -- Explicit reward/admin access
  if exists (
    select 1
    from public.content_access
    where user_id = p_user_id
      and chapter_id = p_chapter_id
      and active = true
      and (
        expires_at is null
        or expires_at > now()
      )
  ) then
    return true;
  end if;

  return false;

end;
$$;


-- ============================================================
-- 22. SECURITY FIX:
-- USERS MUST NOT BE ABLE TO CHANGE THEIR OWN ROLE.
--
-- Only Admin should be able to change:
-- role
-- account_status
-- verification
-- ============================================================

create or replace function public.prevent_sensitive_profile_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  if auth.uid() = old.id then

    if new.role is distinct from old.role then
      raise exception 'Users cannot change their own role.';
    end if;

    if new.account_status is distinct from old.account_status then
      raise exception 'Users cannot change their own account status.';
    end if;

    if new.is_verified is distinct from old.is_verified then
      raise exception 'Users cannot change their own verification status.';
    end if;

  end if;

  return new;

end;
$$;


drop trigger if exists protect_profile_sensitive_fields
on public.profiles;

create trigger protect_profile_sensitive_fields
before update on public.profiles
for each row
execute function public.prevent_sensitive_profile_changes();


-- ============================================================
-- 23. READER REWARD COUNTER
--
-- Approved chapter purchase = 1 qualifying purchase.
--
-- Every 10 approved purchases:
-- +1 free spin.
-- ============================================================

create or replace function public.process_paid_chapter_reward()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_old_count integer;
begin

  if new.status = 'approved'
     and (
       old.status is distinct from 'approved'
     )
  then

    insert into public.reader_reward_progress(user_id)
    values(new.user_id)
    on conflict(user_id) do nothing;

    select paid_chapters_count
    into v_old_count
    from public.reader_reward_progress
    where user_id = new.user_id
    for update;

    v_count := v_old_count + 1;

    update public.reader_reward_progress
    set
      paid_chapters_count = v_count,
      spins_earned =
        spins_earned
        + floor(v_count / 10)::integer
        - floor(v_old_count / 10)::integer,
      updated_at = now()
    where user_id = new.user_id;

  end if;

  return new;

end;
$$;


drop trigger if exists chapter_purchase_reward_trigger
on public.chapter_purchases;

create trigger chapter_purchase_reward_trigger
after update on public.chapter_purchases
for each row
execute function public.process_paid_chapter_reward();


-- ============================================================
-- 24. HELPER FUNCTION:
-- DOES USER HAVE A READY FREE SPIN?
-- ============================================================

create or replace function public.user_has_free_spin(
  p_user_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.reader_reward_progress
    where user_id = p_user_id
      and spins_earned > spins_used
      and (
        next_spin_available_at is null
        or next_spin_available_at <= now()
      )
  );
$$;


-- ============================================================
-- 25. CONSUME FREE SPIN
--
-- One database transaction can consume one spin.
-- Refreshing the page cannot create another spin.
-- ============================================================

create or replace function public.consume_free_spin(
  p_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reward_id uuid;
  v_reward_type public.reward_type;
  v_spin_id uuid;
begin

  if auth.uid() is null
     or auth.uid() <> p_user_id
  then
    raise exception 'Not authorized.';
  end if;


  if not public.user_has_free_spin(p_user_id) then
    raise exception 'No free spin is available.';
  end if;


  -- Select an active reward.
  -- The application can later implement weighted random
  -- selection using the reward weight column.
  select id, reward_type
  into v_reward_id, v_reward_type
  from public.free_spin_rewards
  where active = true
  order by random()
  limit 1;


  if v_reward_id is null then
    raise exception 'No active rewards are configured.';
  end if;


  update public.reader_reward_progress
  set
    spins_used = spins_used + 1,
    next_spin_available_at =
      case
        when v_reward_type in ('another_spin', 'try_again')
        then now() + interval '3 days'
        else next_spin_available_at
      end,
    updated_at = now()
  where user_id = p_user_id
    and spins_earned > spins_used
    and (
      next_spin_available_at is null
      or next_spin_available_at <= now()
    );


  if not found then
    raise exception 'Spin could not be consumed.';
  end if;


  insert into public.free_spin_history (
    user_id,
    reward_id,
    reward_type
  )
  values (
    p_user_id,
    v_reward_id,
    v_reward_type
  )
  returning id into v_spin_id;


  return v_spin_id;

end;
$$;


-- ============================================================
-- 26. DEFAULT FREE-SPIN REWARDS
--
-- These are configuration records, not fake user rewards.
-- Admin can later edit/delete/deactivate them.
-- ============================================================

insert into public.free_spin_rewards (
  reward_type,
  title,
  description,
  weight
)
values
  (
    'free_chapter',
    'Free Chapter',
    'Unlock one eligible chapter for free.',
    1
  ),
  (
    'two_free_chapters',
    '2 Free Chapters',
    'Unlock two eligible chapters for free.',
    0.5
  ),
  (
    'three_free_chapters',
    '3 Free Chapters',
    'Unlock three eligible chapters for free.',
    0.25
  ),
  (
    'another_spin',
    'Another Spin',
    'Receive another spin after the applicable waiting period.',
    0.5
  ),
  (
    'reading_credit',
    'Reading Credit',
    'Receive reading credit according to Admin configuration.',
    0.5
  ),
  (
    'special_reward',
    'Special Reward',
    'A special Breethub reward configured by Admin.',
    0.25
  ),
  (
    'try_again',
    'Try Again',
    'Try again after the applicable waiting period.',
    1
  )
on conflict do nothing;


-- ============================================================
-- 27. ROW LEVEL SECURITY
-- ============================================================

alter table public.wallets enable row level security;

alter table public.wallet_transactions enable row level security;

alter table public.reading_price_settings enable row level security;

alter table public.currency_payment_rules enable row level security;

alter table public.exchange_rates enable row level security;

alter table public.chapter_purchases enable row level security;

alter table public.book_purchases enable row level security;

alter table public.content_access enable row level security;

alter table public.investor_pool_ledger enable row level security;

alter table public.withdrawals enable row level security;

alter table public.withdrawal_settings enable row level security;

alter table public.reader_reward_progress enable row level security;

alter table public.free_spin_rewards enable row level security;

alter table public.free_spin_history enable row level security;

alter table public.reward_claims enable row level security;


-- ============================================================
-- 28. WALLET POLICIES
-- ============================================================

drop policy if exists "Users can view own wallets"
on public.wallets;

create policy "Users can view own wallets"
on public.wallets
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- Users cannot directly modify wallet balances.
-- Financial changes must happen through trusted server/database
-- functions and approved payment workflows.


drop policy if exists "Users can view own wallet transactions"
on public.wallet_transactions;

create policy "Users can view own wallet transactions"
on public.wallet_transactions
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- ============================================================
-- 29. PUBLIC PRICE READ
-- ============================================================

drop policy if exists "Anyone can view active reading prices"
on public.reading_price_settings;

create policy "Anyone can view active reading prices"
on public.reading_price_settings
for select
to anon, authenticated
using (
  active = true
);


drop policy if exists "Anyone can view currency rules"
on public.currency_payment_rules;

create policy "Anyone can view currency rules"
on public.currency_payment_rules
for select
to anon, authenticated
using (
  display_enabled = true
);


drop policy if exists "Anyone can view active exchange rates"
on public.exchange_rates;

create policy "Anyone can view active exchange rates"
on public.exchange_rates
for select
to anon, authenticated
using (
  active = true
);


-- ============================================================
-- 30. CHAPTER PURCHASE POLICIES
-- ============================================================

drop policy if exists "Users can view own chapter purchases"
on public.chapter_purchases;

create policy "Users can view own chapter purchases"
on public.chapter_purchases
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Users can view own book purchases"
on public.book_purchases;

create policy "Users can view own book purchases"
on public.book_purchases
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- ============================================================
-- 31. CONTENT ACCESS POLICY
-- ============================================================

drop policy if exists "Users can view own content access"
on public.content_access;

create policy "Users can view own content access"
on public.content_access
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- ============================================================
-- 32. INVESTOR POOL
-- ============================================================

drop policy if exists "Admins can view investor pool ledger"
on public.investor_pool_ledger;

create policy "Admins can view investor pool ledger"
on public.investor_pool_ledger
for select
to authenticated
using (
  public.is_admin()
);


-- ============================================================
-- 33. WITHDRAWALS
-- ============================================================

drop policy if exists "Users can view own withdrawals"
on public.withdrawals;

create policy "Users can view own withdrawals"
on public.withdrawals
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- ============================================================
-- 34. READER REWARD POLICIES
-- ============================================================

drop policy if exists "Users can view own reward progress"
on public.reader_reward_progress;

create policy "Users can view own reward progress"
on public.reader_reward_progress
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Anyone can view active spin rewards"
on public.free_spin_rewards;

create policy "Anyone can view active spin rewards"
on public.free_spin_rewards
for select
to authenticated
using (
  active = true
);


drop policy if exists "Users can view own spin history"
on public.free_spin_history;

create policy "Users can view own spin history"
on public.free_spin_history
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Users can view own reward claims"
on public.reward_claims;

create policy "Users can view own reward claims"
on public.reward_claims
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- ============================================================
-- 35. ADMIN PRICE MANAGEMENT
-- ============================================================

drop policy if exists "Admins manage reading prices"
on public.reading_price_settings;

create policy "Admins manage reading prices"
on public.reading_price_settings
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Admins manage currency rules"
on public.currency_payment_rules;

create policy "Admins manage currency rules"
on public.currency_payment_rules
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Admins manage exchange rates"
on public.exchange_rates;

create policy "Admins manage exchange rates"
on public.exchange_rates
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Admins manage withdrawal settings"
on public.withdrawal_settings;

create policy "Admins manage withdrawal settings"
on public.withdrawal_settings
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Admins manage spin rewards"
on public.free_spin_rewards;

create policy "Admins manage spin rewards"
on public.free_spin_rewards
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ============================================================
-- 36. ADMIN FINANCIAL VISIBILITY
-- ============================================================

drop policy if exists "Admins can view all withdrawals"
on public.withdrawals;

create policy "Admins can view all withdrawals"
on public.withdrawals
for select
to authenticated
using (
  public.is_admin()
);


drop policy if exists "Admins can view all wallet transactions"
on public.wallet_transactions;

create policy "Admins can view all wallet transactions"
on public.wallet_transactions
for select
to authenticated
using (
  public.is_admin()
);


-- ============================================================
-- 37. FINAL COMMENTS
-- ============================================================

comment on table public.reading_price_settings is
'Admin-controlled reading prices. Default NGN chapter price is ₦200 with 25% Writer, 25% Investor Pool and 50% Admin allocation.';

comment on table public.chapter_purchases is
'Approved paid chapter purchases. Only approved purchases unlock paid chapters and count toward Free Spin progress.';

comment on table public.reader_reward_progress is
'Tracks qualifying paid chapters and earned Free Spins.';

comment on table public.investor_pool_ledger is
'Records the investor allocation from reading revenue. It does not itself constitute a regulated investment product or guarantee returns.';

comment on table public.wallet_transactions is
'Financial ledger. Browser clients must not directly alter balances.';

comment on table public.withdrawals is
'Writer/Affiliate withdrawal requests subject to Admin/Accountant review and configured withdrawal rules.';-- ============================================================
-- BREETHUB BATCH 5
-- PAYMENT VERIFICATION + PAYMENT ACCESS CONTROL
-- ============================================================


-- ============================================================
-- 1. PAYMENT PURPOSE
-- ============================================================

create type public.payment_purpose as enum (
  'registration',
  'writer_activation',
  'affiliate_activation',
  'ai_bootcamp',
  'chapter_reading',
  'book_purchase',
  'course_purchase',
  'script_purchase',
  'article_purchase',
  'advertising',
  'investment',
  'gift',
  'other'
);


-- ============================================================
-- 2. PAYMENT PROVIDER
-- ============================================================

create type public.payment_provider as enum (
  'flutterwave',
  'stripe',
  'bank_transfer',
  'manual',
  'other'
);


-- ============================================================
-- 3. PAYMENT VERIFICATION SOURCE
-- ============================================================

create type public.payment_verification_source as enum (
  'provider_webhook',
  'provider_api',
  'manual_review',
  'admin_adjustment'
);


-- ============================================================
-- 4. EXTEND PAYMENTS WITH PAYMENT-CONTROL FIELDS
-- ============================================================

alter table public.payments
add column if not exists purpose public.payment_purpose;

alter table public.payments
add column if not exists provider_name public.payment_provider;

alter table public.payments
add column if not exists verification_source
public.payment_verification_source;

alter table public.payments
add column if not exists expected_amount numeric(18,2);

alter table public.payments
add column if not exists expected_currency public.supported_currency;

alter table public.payments
add column if not exists customer_email text;

alter table public.payments
add column if not exists customer_phone text;

alter table public.payments
add column if not exists idempotency_key text;

alter table public.payments
add column if not exists checkout_reference text;

alter table public.payments
add column if not exists provider_status text;

alter table public.payments
add column if not exists provider_response jsonb
default '{}'::jsonb;

alter table public.payments
add column if not exists verification_notes text;

alter table public.payments
add column if not exists failed_at timestamptz;

alter table public.payments
add column if not exists refunded_at timestamptz;


-- ============================================================
-- 5. UNIQUE PAYMENT IDENTIFIERS
-- ============================================================

create unique index if not exists payments_provider_reference_unique
on public.payments(provider, provider_reference)
where provider is not null
and provider_reference is not null;


create unique index if not exists payments_idempotency_unique
on public.payments(idempotency_key)
where idempotency_key is not null;


create unique index if not exists payments_checkout_reference_unique
on public.payments(checkout_reference)
where checkout_reference is not null;


-- ============================================================
-- 6. PAYMENT EVENTS
--
-- Every provider event is retained.
-- This protects against duplicate webhooks.
-- ============================================================

create table if not exists public.payment_events (
  id uuid primary key default gen_random_uuid(),

  payment_id uuid references public.payments(id)
    on delete set null,

  provider public.payment_provider not null,

  provider_event_id text,

  event_type text not null,

  provider_reference text,

  payload jsonb not null default '{}'::jsonb,

  received_at timestamptz not null default now(),

  processed_at timestamptz,

  processing_status text not null default 'received'
    check (
      processing_status in (
        'received',
        'processing',
        'processed',
        'failed',
        'ignored'
      )
    ),

  error_message text
);


create unique index if not exists payment_events_provider_event_unique
on public.payment_events(provider, provider_event_id)
where provider_event_id is not null;


create index if not exists payment_events_reference_idx
on public.payment_events(provider_reference);


-- ============================================================
-- 7. PAYMENT REVIEW QUEUE
-- ============================================================

create type public.payment_review_status as enum (
  'pending',
  'under_review',
  'approved',
  'rejected'
);


create table if not exists public.payment_reviews (
  id uuid primary key default gen_random_uuid(),

  payment_id uuid not null references public.payments(id)
    on delete cascade,

  assigned_to uuid references public.profiles(id)
    on delete set null,

  status public.payment_review_status not null default 'pending',

  reviewer_role public.app_role,

  review_notes text,

  rejection_reason text,

  created_at timestamptz not null default now(),

  reviewed_at timestamptz
);


create index if not exists payment_reviews_status_idx
on public.payment_reviews(status);


create index if not exists payment_reviews_assigned_idx
on public.payment_reviews(assigned_to);


-- ============================================================
-- 8. PAYMENT REVIEW HISTORY
-- ============================================================

create table if not exists public.payment_review_actions (
  id uuid primary key default gen_random_uuid(),

  payment_id uuid not null references public.payments(id)
    on delete cascade,

  reviewer_id uuid references public.profiles(id)
    on delete set null,

  action text not null
    check (
      action in (
        'opened',
        'assigned',
        'approved',
        'rejected',
        'reopened'
      )
    ),

  notes text,

  created_at timestamptz not null default now()
);


-- ============================================================
-- 9. PAYMENT PURPOSE CONFIGURATION
-- ============================================================

create table if not exists public.payment_purpose_settings (
  id uuid primary key default gen_random_uuid(),

  purpose public.payment_purpose not null unique,

  enabled boolean not null default true,

  requires_manual_proof boolean not null default false,

  requires_admin_approval boolean not null default true,

  description text,

  updated_by uuid references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);


insert into public.payment_purpose_settings (
  purpose,
  requires_manual_proof,
  requires_admin_approval,
  description
)
values
(
  'registration',
  true,
  true,
  'Registration or account activation payment.'
),
(
  'writer_activation',
  true,
  true,
  'Required writer onboarding payment.'
),
(
  'affiliate_activation',
  true,
  true,
  'Required affiliate onboarding payment.'
),
(
  'ai_bootcamp',
  true,
  true,
  'AI Bootcamp payment.'
),
(
  'chapter_reading',
  true,
  true,
  'Paid chapter reading payment.'
),
(
  'book_purchase',
  true,
  true,
  'Full book purchase.'
),
(
  'course_purchase',
  true,
  true,
  'Course purchase.'
),
(
  'script_purchase',
  true,
  true,
  'Script/content purchase.'
),
(
  'article_purchase',
  true,
  true,
  'Paid article/content purchase.'
),
(
  'advertising',
  true,
  true,
  'Advertiser campaign payment.'
),
(
  'investment',
  true,
  true,
  'Investment payment subject to applicable legal/regulatory approval.'
),
(
  'gift',
  true,
  true,
  'Gift payment.'
)
on conflict (purpose) do nothing;


-- ============================================================
-- 10. PAYMENT ACCESS GRANTS
--
-- This table records exactly what an approved payment unlocked.
-- ============================================================

create type public.payment_access_type as enum (
  'registration',
  'writer_course',
  'affiliate_course',
  'ai_bootcamp',
  'chapter',
  'book',
  'course',
  'script',
  'article',
  'advertising',
  'investment',
  'gift'
);


create table if not exists public.payment_access_grants (
  id uuid primary key default gen_random_uuid(),

  payment_id uuid not null references public.payments(id)
    on delete restrict,

  user_id uuid not null references public.profiles(id)
    on delete restrict,

  access_type public.payment_access_type not null,

  story_id uuid references public.stories(id)
    on delete set null,

  chapter_id uuid references public.chapters(id)
    on delete set null,

  course_id uuid references public.courses(id)
    on delete set null,

  created_at timestamptz not null default now(),

  unique(payment_id, access_type, chapter_id, course_id)
);


-- ============================================================
-- 11. PAYMENT ALLOCATION LEDGER
--
-- Keeps the reading-money split separate.
-- ============================================================

create type public.payment_allocation_type as enum (
  'writer',
  'investor_pool',
  'admin',
  'affiliate',
  'platform',
  'other'
);


create table if not exists public.payment_allocations (
  id uuid primary key default gen_random_uuid(),

  payment_id uuid not null references public.payments(id)
    on delete restrict,

  user_id uuid references public.profiles(id)
    on delete set null,

  allocation_type public.payment_allocation_type not null,

  amount numeric(18,2) not null,

  currency public.supported_currency not null,

  wallet_transaction_id uuid references public.wallet_transactions(id)
    on delete set null,

  created_at timestamptz not null default now(),

  constraint payment_allocation_positive
    check (amount >= 0)
);


create index if not exists payment_allocations_payment_idx
on public.payment_allocations(payment_id);


-- ============================================================
-- 12. PAYMENT VERIFICATION FUNCTION
--
-- This is deliberately NOT a fake "payment successful" button.
--
-- The eventual Next.js server/webhook must first verify the
-- transaction with Flutterwave/Stripe before calling the trusted
-- verification workflow.
-- ============================================================

create or replace function public.mark_payment_verified(
  p_payment_id uuid,
  p_reviewer_id uuid,
  p_source public.payment_verification_source,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
begin

  if not public.is_admin()
     and not public.has_staff_permission(
       'approve_payments'::public.staff_permission
     )
  then
    raise exception 'Not authorized to verify payments.';
  end if;


  select *
  into v_payment
  from public.payments
  where id = p_payment_id
  for update;


  if v_payment.id is null then
    raise exception 'Payment not found.';
  end if;


  if v_payment.status = 'paid' then
    return true;
  end if;


  update public.payments
  set
    status = 'paid',
    verified_at = now(),
    verified_by = p_reviewer_id,
    verification_source = p_source,
    verification_notes = p_notes,
    paid_at = coalesce(paid_at, now())
  where id = p_payment_id;


  insert into public.payment_reviews (
    payment_id,
    assigned_to,
    status,
    reviewer_role,
    review_notes,
    reviewed_at
  )
  values (
    p_payment_id,
    p_reviewer_id,
    'approved',
    (
      select role
      from public.profiles
      where id = p_reviewer_id
    ),
    p_notes,
    now()
  );


  insert into public.payment_review_actions (
    payment_id,
    reviewer_id,
    action,
    notes
  )
  values (
    p_payment_id,
    p_reviewer_id,
    'approved',
    p_notes
  );


  return true;

end;
$$;


-- ============================================================
-- 13. REJECT PAYMENT
-- ============================================================

create or replace function public.reject_payment(
  p_payment_id uuid,
  p_reviewer_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin()
     and not public.has_staff_permission(
       'approve_payments'::public.staff_permission
     )
  then
    raise exception 'Not authorized to reject payments.';
  end if;


  if p_reason is null
     or length(trim(p_reason)) < 3
  then
    raise exception 'A rejection reason is required.';
  end if;


  update public.payments
  set
    status = 'failed',
    verified_by = p_reviewer_id,
    verified_at = now(),
    rejection_reason = p_reason
  where id = p_payment_id;


  insert into public.payment_reviews (
    payment_id,
    assigned_to,
    status,
    reviewer_role,
    review_notes,
    rejection_reason,
    reviewed_at
  )
  values (
    p_payment_id,
    p_reviewer_id,
    'rejected',
    (
      select role
      from public.profiles
      where id = p_reviewer_id
    ),
    p_reason,
    p_reason,
    now()
  );


  insert into public.payment_review_actions (
    payment_id,
    reviewer_id,
    action,
    notes
  )
  values (
    p_payment_id,
    p_reviewer_id,
    'rejected',
    p_reason
  );


  return true;

end;
$$;


-- ============================================================
-- 14. CREATE CHAPTER ACCESS AFTER APPROVAL
-- ============================================================

create or replace function public.grant_chapter_access_from_payment(
  p_payment_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
  v_access_id uuid;
begin

  select *
  into v_payment
  from public.payments
  where id = p_payment_id;


  if v_payment.id is null then
    raise exception 'Payment not found.';
  end if;


  if v_payment.status <> 'paid' then
    raise exception 'Payment has not been approved.';
  end if;


  if v_payment.chapter_id is null then
    raise exception 'Payment has no chapter.';
  end if;


  insert into public.content_access (
    user_id,
    story_id,
    chapter_id,
    access_type,
    active
  )
  select
    v_payment.user_id,
    v_payment.story_id,
    v_payment.chapter_id,
    'chapter_purchase',
    true
  on conflict (
    user_id,
    chapter_id,
    access_type
  )
  do update set
    active = true;


  insert into public.payment_access_grants (
    payment_id,
    user_id,
    access_type,
    story_id,
    chapter_id
  )
  values (
    p_payment_id,
    v_payment.user_id,
    'chapter',
    v_payment.story_id,
    v_payment.chapter_id
  )
  on conflict do nothing
  returning id into v_access_id;


  return v_access_id;

end;
$$;


-- ============================================================
-- 15. PAYMENT REVIEW RLS
-- ============================================================

alter table public.payment_events enable row level security;
alter table public.payment_reviews enable row level security;
alter table public.payment_review_actions enable row level security;
alter table public.payment_purpose_settings enable row level security;
alter table public.payment_access_grants enable row level security;
alter table public.payment_allocations enable row level security;


drop policy if exists "Users view own payment events"
on public.payment_events;

create policy "Users view own payment events"
on public.payment_events
for select
to authenticated
using (
  payment_id in (
    select id
    from public.payments
    where user_id = auth.uid()
  )
  or public.is_admin()
);


drop policy if exists "Payment staff view reviews"
on public.payment_reviews;

create policy "Payment staff view reviews"
on public.payment_reviews
for select
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission(
    'approve_payments'::public.staff_permission
  )
);


drop policy if exists "Payment staff view review actions"
on public.payment_review_actions;

create policy "Payment staff view review actions"
on public.payment_review_actions
for select
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission(
    'approve_payments'::public.staff_permission
  )
);


drop policy if exists "Admins manage payment purpose settings"
on public.payment_purpose_settings;

create policy "Admins manage payment purpose settings"
on public.payment_purpose_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


drop policy if exists "Users view own access grants"
on public.payment_access_grants;

create policy "Users view own access grants"
on public.payment_access_grants
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Finance staff view allocations"
on public.payment_allocations;

create policy "Finance staff view allocations"
on public.payment_allocations
for select
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission(
    'view_financials'::public.staff_permission
  )
);-- ============================================================
-- BREETHUB BATCH 6
-- REGISTRATION, INVESTMENT AND ADVERTISER PAYMENT FOUNDATION
-- ============================================================


-- ============================================================
-- 1. REGISTRATION / ACTIVATION PRICES
-- ============================================================

create table if not exists public.registration_price_settings (
  id uuid primary key default gen_random_uuid(),

  role public.app_role not null unique,

  price_ngn numeric(18,2),
  price_usd numeric(18,2),
  price_gbp numeric(18,2),
  price_eur numeric(18,2),

  enabled boolean not null default false,

  updated_by uuid references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);


-- ============================================================
-- 2. ADVERTISING PRICE PACKAGES
-- ============================================================

create type public.advertising_package_status as enum (
  'draft',
  'active',
  'paused',
  'archived'
);


create table if not exists public.advertising_packages (
  id uuid primary key default gen_random_uuid(),

  name text not null,

  description text,

  status public.advertising_package_status
    not null default 'draft',

  price_ngn numeric(18,2),
  price_usd numeric(18,2),
  price_gbp numeric(18,2),
  price_eur numeric(18,2),

  duration_days integer,

  impression_limit bigint,

  click_limit bigint,

  created_by uuid references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint advertising_package_duration_positive
    check (
      duration_days is null
      or duration_days > 0
    )
);


-- ============================================================
-- 3. ADVERTISER CAMPAIGNS
-- ============================================================

create type public.ad_campaign_status as enum (
  'draft',
  'payment_pending',
  'under_review',
  'active',
  'paused',
  'rejected',
  'completed'
);


create table if not exists public.ad_campaigns (
  id uuid primary key default gen_random_uuid(),

  advertiser_id uuid not null references public.profiles(id)
    on delete restrict,

  package_id uuid references public.advertising_packages(id)
    on delete set null,

  name text not null,

  headline text,

  body text,

  image_url text,

  video_url text,

  destination_url text,

  status public.ad_campaign_status
    not null default 'draft',

  currency public.supported_currency,

  budget numeric(18,2),

  amount_paid numeric(18,2) default 0,

  start_at timestamptz,

  end_at timestamptz,

  approved_by uuid references public.profiles(id)
    on delete set null,

  approved_at timestamptz,

  rejection_reason text,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);


-- ============================================================
-- 4. AD CAMPAIGN ANALYTICS
-- ============================================================

create table if not exists public.ad_campaign_metrics (
  id uuid primary key default gen_random_uuid(),

  campaign_id uuid not null references public.ad_campaigns(id)
    on delete cascade,

  metric_date date not null,

  impressions bigint not null default 0,

  clicks bigint not null default 0,

  spend numeric(18,2) not null default 0,

  created_at timestamptz not null default now(),

  unique(campaign_id, metric_date)
);


-- ============================================================
-- 5. INVESTMENT STATUS
-- ============================================================

create type public.investment_status as enum (
  'pending',
  'payment_pending',
  'under_review',
  'approved',
  'active',
  'matured',
  'completed',
  'rejected',
  'cancelled',
  'refunded'
);


-- ============================================================
-- 6. INVESTMENT ELIGIBILITY
-- ============================================================

create table if not exists public.investment_settings (
  id uuid primary key default gen_random_uuid(),

  story_id uuid not null references public.stories(id)
    on delete cascade,

  chapter_id uuid references public.chapters(id)
    on delete cascade,

  enabled boolean not null default false,

  minimum_amount numeric(18,2),

  maximum_amount numeric(18,2),

  currency public.supported_currency,

  reading_access_required boolean not null default true,

  terms_text text,

  risk_disclosure text,

  legal_review_required boolean not null default true,

  legal_review_completed boolean not null default false,

  approved_by uuid references public.profiles(id)
    on delete set null,

  approved_at timestamptz,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);


-- ============================================================
-- 7. INVESTMENTS
-- ============================================================

create table if not exists public.investments (
  id uuid primary key default gen_random_uuid(),

  investor_id uuid not null references public.profiles(id)
    on delete restrict,

  story_id uuid not null references public.stories(id)
    on delete restrict,

  chapter_id uuid references public.chapters(id)
    on delete restrict,

  payment_id uuid references public.payments(id)
    on delete set null,

  reading_purchase_id uuid references public.chapter_purchases(id)
    on delete set null,

  currency public.supported_currency not null,

  principal_amount numeric(18,2) not null,

  status public.investment_status not null default 'pending',

  terms_version text,

  terms_accepted_at timestamptz,

  risk_acknowledged_at timestamptz,

  approved_by uuid references public.profiles(id)
    on delete set null,

  approved_at timestamptz,

  start_at timestamptz,

  maturity_at timestamptz,

  actual_return numeric(18,2),

  completed_at timestamptz,

  rejection_reason text,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now()
);


-- ============================================================
-- 8. INVESTMENT LEDGER
-- ============================================================

create type public.investment_ledger_type as enum (
  'contribution',
  'return',
  'refund',
  'adjustment'
);


create table if not exists public.investment_ledger (
  id uuid primary key default gen_random_uuid(),

  investment_id uuid not null references public.investments(id)
    on delete restrict,

  investor_id uuid not null references public.profiles(id)
    on delete restrict,

  transaction_type public.investment_ledger_type not null,

  amount numeric(18,2) not null,

  currency public.supported_currency not null,

  wallet_transaction_id uuid references public.wallet_transactions(id)
    on delete set null,

  created_at timestamptz not null default now()
);


-- ============================================================
-- 9. INVESTMENT PAYMENT + READING REQUIREMENT
--
-- Investment cannot be activated until:
--
-- A. reading access exists
-- OR
-- B. the combined checkout explicitly purchased both.
-- ============================================================

create or replace function public.investor_has_reading_access(
  p_user_id uuid,
  p_story_id uuid,
  p_chapter_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if p_chapter_id is not null then

    if exists (
      select 1
      from public.chapter_purchases
      where user_id = p_user_id
        and chapter_id = p_chapter_id
        and status = 'approved'
    ) then
      return true;
    end if;

    if exists (
      select 1
      from public.content_access
      where user_id = p_user_id
        and chapter_id = p_chapter_id
        and active = true
        and (
          expires_at is null
          or expires_at > now()
        )
    ) then
      return true;
    end if;

  end if;


  if exists (
    select 1
    from public.book_purchases
    where user_id = p_user_id
      and story_id = p_story_id
      and status = 'approved'
  ) then
    return true;
  end if;


  return false;

end;
$$;


-- ============================================================
-- 10. INVESTMENT APPROVAL
-- ============================================================

create or replace function public.approve_investment(
  p_investment_id uuid,
  p_reviewer_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_investment public.investments%rowtype;
begin

  if not public.is_admin()
     and not public.has_staff_permission(
       'approve_payments'::public.staff_permission
     )
  then
    raise exception 'Not authorized to approve investments.';
  end if;


  select *
  into v_investment
  from public.investments
  where id = p_investment_id
  for update;


  if v_investment.id is null then
    raise exception 'Investment not found.';
  end if;


  if not public.investor_has_reading_access(
    v_investment.investor_id,
    v_investment.story_id,
    v_investment.chapter_id
  ) then
    raise exception
      'Investor must have reading access before investment activation.';
  end if;


  update public.investments
  set
    status = 'active',
    approved_by = p_reviewer_id,
    approved_at = now(),
    start_at = coalesce(start_at, now())
  where id = p_investment_id;


  return true;

end;
$$;


-- ============================================================
-- 11. INVESTMENT RLS
-- ============================================================

alter table public.investment_settings enable row level security;
alter table public.investments enable row level security;
alter table public.investment_ledger enable row level security;


drop policy if exists "Users view eligible investments"
on public.investment_settings;

create policy "Users view eligible investments"
on public.investment_settings
for select
to authenticated
using (
  enabled = true
  and legal_review_required = false
  or (
    enabled = true
    and legal_review_completed = true
  )
  or public.is_admin()
);


drop policy if exists "Users view own investments"
on public.investments;

create policy "Users view own investments"
on public.investments
for select
to authenticated
using (
  investor_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Finance staff view investment ledger"
on public.investment_ledger;

create policy "Finance staff view investment ledger"
on public.investment_ledger
for select
to authenticated
using (
  investor_id = auth.uid()
  or public.is_admin()
  or public.has_staff_permission(
    'view_financials'::public.staff_permission
  )
);


-- ============================================================
-- 12. ADVERTISING RLS
-- ============================================================

alter table public.advertising_packages enable row level security;
alter table public.ad_campaigns enable row level security;
alter table public.ad_campaign_metrics enable row level security;


drop policy if exists "Anyone can view active advertising packages"
on public.advertising_packages;

create policy "Anyone can view active advertising packages"
on public.advertising_packages
for select
to anon, authenticated
using (
  status = 'active'
);


drop policy if exists "Advertisers view own campaigns"
on public.ad_campaigns;

create policy "Advertisers view own campaigns"
on public.ad_campaigns
for select
to authenticated
using (
  advertiser_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Advertisers view own campaign metrics"
on public.ad_campaign_metrics;

create policy "Advertisers view own campaign metrics"
on public.ad_campaign_metrics
for select
to authenticated
using (
  campaign_id in (
    select id
    from public.ad_campaigns
    where advertiser_id = auth.uid()
  )
  or public.is_admin()
);


-- ============================================================
-- 13. ADMIN AD PACKAGE CONTROL
-- ============================================================

drop policy if exists "Admins manage advertising packages"
on public.advertising_packages;

create policy "Admins manage advertising packages"
on public.advertising_packages
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


-- ============================================================
-- 14. ADMIN INVESTMENT CONTROL
-- ============================================================

drop policy if exists "Admins manage investment settings"
on public.investment_settings;

create policy "Admins manage investment settings"
on public.investment_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


-- ============================================================
-- 15. REGISTRATION PRICE ADMIN CONTROL
-- ============================================================

alter table public.registration_price_settings enable row level security;


drop policy if exists "Anyone view enabled registration prices"
on public.registration_price_settings;

create policy "Anyone view enabled registration prices"
on public.registration_price_settings
for select
to anon, authenticated
using (
  enabled = true
);


drop policy if exists "Admins manage registration prices"
on public.registration_price_settings;

create policy "Admins manage registration prices"
on public.registration_price_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


-- ============================================================
-- 16. ADMIN PAYMENT OVERVIEW FUNCTION
-- ============================================================

create or replace function public.get_payment_finance_summary()
returns table (
  pending_count bigint,
  approved_count bigint,
  rejected_count bigint,
  total_approved numeric,
  total_pending numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin()
     and not public.has_staff_permission(
       'view_financials'::public.staff_permission
     )
  then
    raise exception 'Not authorized.';
  end if;


  return query
  select
    count(*) filter (
      where status in ('pending', 'pending_review')
    ),
    count(*) filter (
      where status = 'paid'
    ),
    count(*) filter (
      where status in ('failed', 'cancelled')
    ),
    coalesce(
      sum(amount) filter (
        where status = 'paid'
      ),
      0
    ),
    coalesce(
      sum(amount) filter (
        where status in ('pending', 'pending_review')
      ),
      0
    )
  from public.payments;

end;
$$;


-- ============================================================
-- 17. UPDATED AT
-- ============================================================

drop trigger if exists registration_price_settings_updated_at
on public.registration_price_settings;

create trigger registration_price_settings_updated_at
before update on public.registration_price_settings
for each row
execute function public.set_updated_at();


drop trigger if exists advertising_packages_updated_at
on public.advertising_packages;

create trigger advertising_packages_updated_at
before update on public.advertising_packages
for each row
execute function public.set_updated_at();


drop trigger if exists ad_campaigns_updated_at
on public.ad_campaigns;

create trigger ad_campaigns_updated_at
before update on public.ad_campaigns
for each row
execute function public.set_updated_at();


drop trigger if exists investment_settings_updated_at
on public.investment_settings;

create trigger investment_settings_updated_at
before update on public.investment_settings
for each row
execute function public.set_updated_at();


-- ============================================================
-- 18. INDEXES
-- ============================================================

create index if not exists payments_purpose_idx
on public.payments(purpose);

create index if not exists payments_status_created_idx
on public.payments(status, created_at desc);

create index if not exists investments_investor_idx
on public.investments(investor_id);

create index if not exists investments_story_idx
on public.investments(story_id);

create index if not exists investments_status_idx
on public.investments(status);

create index if not exists ad_campaigns_advertiser_idx
on public.ad_campaigns(advertiser_id);

create index if not exists ad_campaigns_status_idx
on public.ad_campaigns(status);


-- ============================================================
-- 19. COMMENTS
-- ============================================================

comment on table public.payments is
'Central payment records. Payment success must come from verified provider/server workflow, never from browser state alone.';

comment on table public.payment_events is
'Immutable-style provider event history used for webhook idempotency and payment reconciliation.';

comment on table public.payment_access_grants is
'Records exactly what an approved payment unlocked.';

comment on table public.investments is
'Investment records. Real-money investment functionality requires applicable legal and regulatory review before activation.';

comment on table public.ad_campaigns is
'Advertiser campaigns. Campaigns become active only after required payment and Admin review.';-- ============================================================
-- BREETHUB BATCH 7
-- AFFILIATE REFERRALS, COMMISSIONS, LEADERBOARDS AND GIFTS
-- ============================================================


-- ============================================================
-- 1. AFFILIATE REFERRAL LINKS
-- ============================================================

create table if not exists public.affiliate_links (
  id uuid primary key default gen_random_uuid(),

  affiliate_id uuid not null references public.profiles(id)
    on delete cascade,

  code text not null unique,

  name text,

  destination_path text,

  active boolean not null default true,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);


create index if not exists affiliate_links_affiliate_idx
on public.affiliate_links(affiliate_id);


-- ============================================================
-- 2. REFERRAL CLICKS
-- ============================================================

create table if not exists public.affiliate_clicks (
  id uuid primary key default gen_random_uuid(),

  affiliate_link_id uuid not null references public.affiliate_links(id)
    on delete cascade,

  affiliate_id uuid not null references public.profiles(id)
    on delete cascade,

  visitor_user_id uuid references public.profiles(id)
    on delete set null,

  session_id text,

  source text,

  user_agent text,

  clicked_at timestamptz not null default now()
);


create index if not exists affiliate_clicks_affiliate_idx
on public.affiliate_clicks(affiliate_id, clicked_at desc);


create index if not exists affiliate_clicks_link_idx
on public.affiliate_clicks(affiliate_link_id, clicked_at desc);


-- ============================================================
-- 3. REFERRALS
-- ============================================================

create type public.referral_status as enum (
  'clicked',
  'registered',
  'qualified',
  'rejected',
  'cancelled'
);


create table if not exists public.affiliate_referrals (
  id uuid primary key default gen_random_uuid(),

  affiliate_id uuid not null references public.profiles(id)
    on delete restrict,

  referred_user_id uuid references public.profiles(id)
    on delete set null,

  affiliate_link_id uuid references public.affiliate_links(id)
    on delete set null,

  status public.referral_status not null default 'clicked',

  registered_at timestamptz,

  qualified_at timestamptz,

  created_at timestamptz not null default now()
);


create index if not exists affiliate_referrals_affiliate_idx
on public.affiliate_referrals(affiliate_id, created_at desc);


create index if not exists affiliate_referrals_user_idx
on public.affiliate_referrals(referred_user_id);


-- ============================================================
-- 4. AFFILIATE COMMISSION RULES
-- ============================================================

create table if not exists public.affiliate_commission_rules (
  id uuid primary key default gen_random_uuid(),

  name text not null,

  course_id uuid references public.courses(id)
    on delete cascade,

  commission_percentage numeric(5,2),

  fixed_amount numeric(18,2),

  currency public.supported_currency,

  active boolean not null default true,

  starts_at timestamptz,

  ends_at timestamptz,

  created_by uuid references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint commission_percentage_valid
    check (
      commission_percentage is null
      or (
        commission_percentage >= 0
        and commission_percentage <= 100
      )
    ),

  constraint commission_value_present
    check (
      commission_percentage is not null
      or fixed_amount is not null
    )
);


-- ============================================================
-- 5. AFFILIATE COMMISSIONS
-- ============================================================

create type public.commission_status as enum (
  'pending',
  'approved',
  'available',
  'paid',
  'reversed',
  'cancelled'
);


create table if not exists public.affiliate_commissions (
  id uuid primary key default gen_random_uuid(),

  affiliate_id uuid not null references public.profiles(id)
    on delete restrict,

  referral_id uuid references public.affiliate_referrals(id)
    on delete set null,

  payment_id uuid references public.payments(id)
    on delete set null,

  course_id uuid references public.courses(id)
    on delete set null,

  amount numeric(18,2) not null,

  currency public.supported_currency not null,

  status public.commission_status not null default 'pending',

  available_at timestamptz,

  paid_at timestamptz,

  wallet_transaction_id uuid references public.wallet_transactions(id)
    on delete set null,

  created_at timestamptz not null default now()
);


create index if not exists affiliate_commissions_affiliate_idx
on public.affiliate_commissions(affiliate_id, created_at desc);


create index if not exists affiliate_commissions_status_idx
on public.affiliate_commissions(status);


-- ============================================================
-- 6. AFFILIATE DASHBOARD SUMMARY
-- ============================================================

create table if not exists public.affiliate_daily_stats (
  id uuid primary key default gen_random_uuid(),

  affiliate_id uuid not null references public.profiles(id)
    on delete cascade,

  stat_date date not null,

  clicks integer not null default 0,

  registrations integer not null default 0,

  qualified_referrals integer not null default 0,

  purchases integer not null default 0,

  commission_amount numeric(18,2) not null default 0,

  currency public.supported_currency,

  unique(affiliate_id, stat_date, currency)
);


-- ============================================================
-- 7. AFFILIATE PROMOTION SAFETY
-- Only Admin-created eligible courses/products may be promoted.
-- ============================================================

create or replace function public.affiliate_can_promote_course(
  p_course_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.courses
    where id = p_course_id
      and status = 'active'
      and course_type = 'affiliate_promotable'
      and affiliate_promotion_enabled = true
  );
$$;


-- ============================================================
-- 8. LEADERBOARD PERIOD
-- ============================================================

create type public.leaderboard_period as enum (
  'weekly',
  'monthly',
  'all_time'
);


-- ============================================================
-- 9. WRITER LEADERBOARD
-- ============================================================

create table if not exists public.writer_leaderboard (
  id uuid primary key default gen_random_uuid(),

  writer_id uuid not null references public.profiles(id)
    on delete cascade,

  period public.leaderboard_period not null,

  period_start date not null,

  period_end date,

  rank integer,

  score numeric(18,4) not null default 0,

  views bigint not null default 0,

  likes bigint not null default 0,

  saves bigint not null default 0,

  followers bigint not null default 0,

  approved_paid_chapters bigint not null default 0,

  earnings numeric(18,2) not null default 0,

  currency public.supported_currency,

  calculated_at timestamptz not null default now(),

  unique(writer_id, period, period_start)
);


create index if not exists writer_leaderboard_rank_idx
on public.writer_leaderboard(period, period_start, rank);


-- ============================================================
-- 10. AFFILIATE LEADERBOARD
-- ============================================================

create table if not exists public.affiliate_leaderboard (
  id uuid primary key default gen_random_uuid(),

  affiliate_id uuid not null references public.profiles(id)
    on delete cascade,

  period public.leaderboard_period not null,

  period_start date not null,

  period_end date,

  rank integer,

  score numeric(18,4) not null default 0,

  clicks bigint not null default 0,

  qualified_referrals bigint not null default 0,

  approved_purchases bigint not null default 0,

  commissions numeric(18,2) not null default 0,

  currency public.supported_currency,

  calculated_at timestamptz not null default now(),

  unique(affiliate_id, period, period_start)
);


create index if not exists affiliate_leaderboard_rank_idx
on public.affiliate_leaderboard(period, period_start, rank);


-- ============================================================
-- 11. LEADERBOARD PUBLIC VIEW
--
-- The website can show the Top 20 writers and Top 10 affiliates.
-- Ranking is calculated by Admin/backend.
-- ============================================================

create or replace view public.public_top_writers
with (security_invoker = true)
as
select
  wl.rank,
  wl.writer_id,
  p.nickname,
  p.profile_photo_url,
  p.bio,
  wl.score,
  wl.views,
  wl.likes,
  wl.followers,
  wl.calculated_at
from public.writer_leaderboard wl
join public.profiles p
  on p.id = wl.writer_id
where wl.period = 'all_time'
  and p.role = 'writer'
  and wl.rank between 1 and 20
order by wl.rank;


create or replace view public.public_top_affiliates
with (security_invoker = true)
as
select
  al.rank,
  al.affiliate_id,
  p.nickname,
  p.profile_photo_url,
  p.bio,
  al.score,
  al.qualified_referrals,
  al.approved_purchases,
  al.calculated_at
from public.affiliate_leaderboard al
join public.profiles p
  on p.id = al.affiliate_id
where al.period = 'all_time'
  and p.role = 'affiliate'
  and al.rank between 1 and 10
order by al.rank;


-- ============================================================
-- 12. GIFT TYPES
-- ============================================================

create type public.gift_recipient_type as enum (
  'writer',
  'affiliate'
);


create table if not exists public.gift_types (
  id uuid primary key default gen_random_uuid(),

  name text not null,

  description text,

  recipient_type public.gift_recipient_type not null,

  amount numeric(18,2),

  currency public.supported_currency,

  image_url text,

  active boolean not null default true,

  created_by uuid references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);


-- ============================================================
-- 13. GIFTS
-- ============================================================

create type public.gift_status as enum (
  'pending_payment',
  'paid',
  'approved',
  'delivered',
  'rejected',
  'cancelled'
);


create table if not exists public.gifts (
  id uuid primary key default gen_random_uuid(),

  sender_id uuid not null references public.profiles(id)
    on delete restrict,

  recipient_id uuid not null references public.profiles(id)
    on delete restrict,

  gift_type_id uuid not null references public.gift_types(id)
    on delete restrict,

  payment_id uuid references public.payments(id)
    on delete set null,

  amount numeric(18,2),

  currency public.supported_currency,

  message text,

  status public.gift_status not null default 'pending_payment',

  delivered_at timestamptz,

  created_at timestamptz not null default now()
);


create index if not exists gifts_recipient_idx
on public.gifts(recipient_id, created_at desc);


create index if not exists gifts_sender_idx
on public.gifts(sender_id, created_at desc);


-- ============================================================
-- 14. TOP-10 AFFILIATE REWARD CONFIGURATION
-- ============================================================

create table if not exists public.affiliate_reward_settings (
  id uuid primary key default gen_random_uuid(),

  enabled boolean not null default true,

  top_n integer not null default 10,

  gift_type_id uuid references public.gift_types(id)
    on delete set null,

  reward_period public.leaderboard_period
    not null default 'monthly',

  updated_by uuid references public.profiles(id)
    on delete set null,

  updated_at timestamptz not null default now(),

  constraint affiliate_reward_top_n_positive
    check (top_n > 0)
);


-- ============================================================
-- 15. TOP-20 WRITER DISPLAY CONFIGURATION
-- ============================================================

create table if not exists public.writer_leaderboard_settings (
  id uuid primary key default gen_random_uuid(),

  enabled boolean not null default true,

  top_n integer not null default 20,

  period public.leaderboard_period
    not null default 'all_time',

  updated_by uuid references public.profiles(id)
    on delete set null,

  updated_at timestamptz not null default now(),

  constraint writer_leaderboard_top_n_positive
    check (top_n > 0)
);


-- ============================================================
-- 16. GIFTS / LEADERBOARD INDEXES
-- ============================================================

create index if not exists gifts_status_idx
on public.gifts(status);

create index if not exists gift_types_recipient_idx
on public.gift_types(recipient_type);

create index if not exists affiliate_daily_stats_idx
on public.affiliate_daily_stats(affiliate_id, stat_date);


-- ============================================================
-- 17. UPDATED AT
-- ============================================================

drop trigger if exists affiliate_links_updated_at
on public.affiliate_links;

create trigger affiliate_links_updated_at
before update on public.affiliate_links
for each row
execute function public.set_updated_at();


drop trigger if exists affiliate_commission_rules_updated_at
on public.affiliate_commission_rules;

create trigger affiliate_commission_rules_updated_at
before update on public.affiliate_commission_rules
for each row
execute function public.set_updated_at();


drop trigger if exists gift_types_updated_at
on public.gift_types;

create trigger gift_types_updated_at
before update on public.gift_types
for each row
execute function public.set_updated_at();


-- ============================================================
-- 18. RLS
-- ============================================================

alter table public.affiliate_links enable row level security;
alter table public.affiliate_clicks enable row level security;
alter table public.affiliate_referrals enable row level security;
alter table public.affiliate_commission_rules enable row level security;
alter table public.affiliate_commissions enable row level security;
alter table public.affiliate_daily_stats enable row level security;
alter table public.writer_leaderboard enable row level security;
alter table public.affiliate_leaderboard enable row level security;
alter table public.gift_types enable row level security;
alter table public.gifts enable row level security;
alter table public.affiliate_reward_settings enable row level security;
alter table public.writer_leaderboard_settings enable row level security;


-- ============================================================
-- 19. AFFILIATE POLICIES
-- ============================================================

drop policy if exists "Affiliates view own links"
on public.affiliate_links;

create policy "Affiliates view own links"
on public.affiliate_links
for select
to authenticated
using (
  affiliate_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Affiliates view own referrals"
on public.affiliate_referrals;

create policy "Affiliates view own referrals"
on public.affiliate_referrals
for select
to authenticated
using (
  affiliate_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Affiliates view own commissions"
on public.affiliate_commissions;

create policy "Affiliates view own commissions"
on public.affiliate_commissions
for select
to authenticated
using (
  affiliate_id = auth.uid()
  or public.is_admin()
  or public.has_staff_permission(
    'view_financials'::public.staff_permission
  )
);


drop policy if exists "Admins manage commission rules"
on public.affiliate_commission_rules;

create policy "Admins manage commission rules"
on public.affiliate_commission_rules
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


-- ============================================================
-- 20. LEADERBOARD POLICIES
-- ============================================================

drop policy if exists "Anyone can view writer leaderboard"
on public.writer_leaderboard;

create policy "Anyone can view writer leaderboard"
on public.writer_leaderboard
for select
to anon, authenticated
using (
  period = 'all_time'
);


drop policy if exists "Anyone can view affiliate leaderboard"
on public.affiliate_leaderboard;

create policy "Anyone can view affiliate leaderboard"
on public.affiliate_leaderboard
for select
to anon, authenticated
using (
  period = 'all_time'
);


drop policy if exists "Admins manage writer leaderboard"
on public.writer_leaderboard;

create policy "Admins manage writer leaderboard"
on public.writer_leaderboard
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


drop policy if exists "Admins manage affiliate leaderboard"
on public.affiliate_leaderboard;

create policy "Admins manage affiliate leaderboard"
on public.affiliate_leaderboard
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


-- ============================================================
-- 21. GIFT POLICIES
-- ============================================================

drop policy if exists "Anyone can view active gift types"
on public.gift_types;

create policy "Anyone can view active gift types"
on public.gift_types
for select
to authenticated
using (
  active = true
);


drop policy if exists "Users view gifts they sent or received"
on public.gifts;

create policy "Users view gifts they sent or received"
on public.gifts
for select
to authenticated
using (
  sender_id = auth.uid()
  or recipient_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Admins manage gift types"
on public.gift_types;

create policy "Admins manage gift types"
on public.gift_types
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


drop policy if exists "Admins manage affiliate reward settings"
on public.affiliate_reward_settings;

create policy "Admins manage affiliate reward settings"
on public.affiliate_reward_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());


drop policy if exists "Admins manage writer leaderboard settings"
on public.writer_leaderboard_settings;

create policy "Admins manage writer leaderboard settings"
on public.writer_leaderboard_settings
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());-- ============================================================
-- BREETHUB BATCH 8
-- NOTIFICATIONS, AUDIT LOGS AND REALTIME CHAT
-- ============================================================


-- ============================================================
-- 1. NOTIFICATION TYPES
-- ============================================================

create type public.notification_type as enum (
  'system',
  'payment',
  'payment_approved',
  'payment_rejected',
  'course',
  'course_approved',
  'course_completed',
  'content',
  'content_approved',
  'content_rejected',
  'writer',
  'affiliate',
  'advertiser',
  'investment',
  'withdrawal',
  'gift',
  'reward',
  'leaderboard',
  'message',
  'security'
);


-- ============================================================
-- 2. NOTIFICATIONS
-- ============================================================

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null references public.profiles(id)
    on delete cascade,

  type public.notification_type not null,

  title text not null,

  message text not null,

  action_url text,

  metadata jsonb not null default '{}'::jsonb,

  read_at timestamptz,

  created_at timestamptz not null default now()
);


create index if not exists notifications_user_idx
on public.notifications(user_id, created_at desc);


create index if not exists notifications_unread_idx
on public.notifications(user_id)
where read_at is null;


-- ============================================================
-- 3. NOTIFICATION DELIVERY PREFERENCES
-- ============================================================

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id)
    on delete cascade,

  in_app_enabled boolean not null default true,

  email_enabled boolean not null default true,

  payment_notifications boolean not null default true,

  course_notifications boolean not null default true,

  content_notifications boolean not null default true,

  message_notifications boolean not null default true,

  marketing_notifications boolean not null default false,

  updated_at timestamptz not null default now()
);


-- ============================================================
-- 4. CREATE DEFAULT NOTIFICATION PREFERENCES
-- ============================================================

create or replace function public.create_notification_preferences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  insert into public.notification_preferences(user_id)
  values(new.id)
  on conflict(user_id) do nothing;

  return new;

end;
$$;


drop trigger if exists create_notification_preferences_after_profile
on public.profiles;

create trigger create_notification_preferences_after_profile
after insert on public.profiles
for each row
execute function public.create_notification_preferences();


-- ============================================================
-- 5. AUDIT LOG TYPES
-- ============================================================

create type public.audit_action_type as enum (
  'create',
  'update',
  'delete',
  'approve',
  'reject',
  'suspend',
  'restore',
  'publish',
  'unpublish',
  'login',
  'logout',
  'payment_verify',
  'payment_reject',
  'withdrawal_approve',
  'withdrawal_reject',
  'role_change',
  'permission_change',
  'price_change',
  'content_review',
  'investment_approve',
  'campaign_approve',
  'staff_change',
  'other'
);


-- ============================================================
-- 6. AUDIT LOG
--
-- Important administrative and financial actions are recorded.
-- ============================================================

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),

  actor_id uuid references public.profiles(id)
    on delete set null,

  action public.audit_action_type not null,

  entity_type text not null,

  entity_id uuid,

  old_data jsonb,

  new_data jsonb,

  metadata jsonb not null default '{}'::jsonb,

  ip_hash text,

  user_agent text,

  created_at timestamptz not null default now()
);


create index if not exists audit_logs_actor_idx
on public.audit_logs(actor_id, created_at desc);


create index if not exists audit_logs_entity_idx
on public.audit_logs(entity_type, entity_id, created_at desc);


create index if not exists audit_logs_action_idx
on public.audit_logs(action, created_at desc);


-- ============================================================
-- 7. CHAT CONVERSATIONS
-- ============================================================

create type public.conversation_type as enum (
  'direct',
  'support',
  'advertiser_writer',
  'payment_support',
  'script_inquiry',
  'content_inquiry',
  'admin_support'
);


create type public.conversation_status as enum (
  'open',
  'assigned',
  'resolved',
  'archived'
);


create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),

  type public.conversation_type not null,

  status public.conversation_status not null default 'open',

  subject text,

  created_by uuid references public.profiles(id)
    on delete set null,

  assigned_to uuid references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);


-- ============================================================
-- 8. CONVERSATION PARTICIPANTS
-- ============================================================

create type public.conversation_participant_role as enum (
  'member',
  'admin',
  'support',
  'secretary',
  'assigned_staff'
);


create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations(id)
    on delete cascade,

  user_id uuid not null references public.profiles(id)
    on delete cascade,

  participant_role public.conversation_participant_role
    not null default 'member',

  joined_at timestamptz not null default now(),

  last_read_at timestamptz,

  primary key(conversation_id, user_id)
);


create index if not exists conversation_participants_user_idx
on public.conversation_participants(user_id);


-- ============================================================
-- 9. CHAT MESSAGES
-- ============================================================

create type public.message_type as enum (
  'text',
  'image',
  'file',
  'system'
);


create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),

  conversation_id uuid not null references public.conversations(id)
    on delete cascade,

  sender_id uuid references public.profiles(id)
    on delete set null,

  message_type public.message_type not null default 'text',

  body text,

  attachment_url text,

  attachment_name text,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  edited_at timestamptz,

  deleted_at timestamptz
);


create index if not exists messages_conversation_idx
on public.messages(conversation_id, created_at);


-- ============================================================
-- 10. MESSAGE READ RECEIPTS
-- ============================================================

create table if not exists public.message_reads (
  message_id uuid not null references public.messages(id)
    on delete cascade,

  user_id uuid not null references public.profiles(id)
    on delete cascade,

  read_at timestamptz not null default now(),

  primary key(message_id, user_id)
);


-- ============================================================
-- 11. CONVERSATION ASSIGNMENTS
--
-- Allows Admin to assign chats to Secretary/Customer Care/etc.
-- ============================================================

create table if not exists public.conversation_assignments (
  id uuid primary key default gen_random_uuid(),

  conversation_id uuid not null references public.conversations(id)
    on delete cascade,

  assigned_to uuid not null references public.profiles(id)
    on delete cascade,

  assigned_by uuid references public.profiles(id)
    on delete set null,

  notes text,

  active boolean not null default true,

  assigned_at timestamptz not null default now(),

  unassigned_at timestamptz
);


create index if not exists conversation_assignments_staff_idx
on public.conversation_assignments(assigned_to, active);


-- ============================================================
-- 12. SUPPORT IDENTITY
--
-- Secretary replies must identify the actual official role.
-- They do not impersonate Admin.
-- ============================================================

create table if not exists public.staff_display_identity (
  user_id uuid primary key references public.profiles(id)
    on delete cascade,

  display_name text not null,

  title text,

  avatar_url text,

  updated_by uuid references public.profiles(id)
    on delete set null,

  updated_at timestamptz not null default now()
);


-- ============================================================
-- 13. CHAT SECURITY FUNCTION
-- ============================================================

create or replace function public.user_is_conversation_participant(
  p_conversation_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversation_participants
    where conversation_id = p_conversation_id
      and user_id = p_user_id
  )
  or public.is_admin();
$$;


-- ============================================================
-- 14. NOTIFICATION RLS
-- ============================================================

alter table public.notifications enable row level security;
alter table public.notification_preferences enable row level security;


drop policy if exists "Users view own notifications"
on public.notifications;

create policy "Users view own notifications"
on public.notifications
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Users update own notification read state"
on public.notifications;

create policy "Users update own notification read state"
on public.notifications
for update
to authenticated
using (
  user_id = auth.uid()
)
with check (
  user_id = auth.uid()
);


drop policy if exists "Users view own notification preferences"
on public.notification_preferences;

create policy "Users view own notification preferences"
on public.notification_preferences
for select
to authenticated
using (
  user_id = auth.uid()
);


drop policy if exists "Users update own notification preferences"
on public.notification_preferences;

create policy "Users update own notification preferences"
on public.notification_preferences
for update
to authenticated
using (
  user_id = auth.uid()
)
with check (
  user_id = auth.uid()
);


-- ============================================================
-- 15. AUDIT RLS
-- ============================================================

alter table public.audit_logs enable row level security;


drop policy if exists "Admins view audit logs"
on public.audit_logs;

create policy "Admins view audit logs"
on public.audit_logs
for select
to authenticated
using (
  public.is_admin()
);


-- No normal client INSERT/UPDATE/DELETE policy.
-- Audit records should be created by trusted server functions.


-- ============================================================
-- 16. CONVERSATION RLS
-- ============================================================

alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.message_reads enable row level security;
alter table public.conversation_assignments enable row level security;
alter table public.staff_display_identity enable row level security;


drop policy if exists "Participants view conversations"
on public.conversations;

create policy "Participants view conversations"
on public.conversations
for select
to authenticated
using (
  public.user_is_conversation_participant(
    id,
    auth.uid()
  )
);


drop policy if exists "Participants view participant records"
on public.conversation_participants;

create policy "Participants view participant records"
on public.conversation_participants
for select
to authenticated
using (
  user_is_conversation_participant(
    conversation_id,
    auth.uid()
  )
);


drop policy if exists "Participants view messages"
on public.messages;

create policy "Participants view messages"
on public.messages
for select
to authenticated
using (
  public.user_is_conversation_participant(
    conversation_id,
    auth.uid()
  )
);


drop policy if exists "Participants send messages"
on public.messages;

create policy "Participants send messages"
on public.messages
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.user_is_conversation_participant(
    conversation_id,
    auth.uid()
  )
);


drop policy if exists "Participants view message reads"
on public.message_reads;

create policy "Participants view message reads"
on public.message_reads
for select
to authenticated
using (
  public.user_is_conversation_participant(
    (
      select conversation_id
      from public.messages
      where id = message_id
    ),
    auth.uid()
  )
);


drop policy if exists "Users mark messages read"
on public.message_reads;

create policy "Users mark messages read"
on public.message_reads
for insert
to authenticated
with check (
  user_id = auth.uid()
);


-- ============================================================
-- 17. STAFF CHAT OVERSIGHT
-- ============================================================

drop policy if exists "Authorized staff view assigned conversations"
on public.conversation_assignments;

create policy "Authorized staff view assigned conversations"
on public.conversation_assignments
for select
to authenticated
using (
  assigned_to = auth.uid()
  or public.is_admin()
  or public.has_staff_permission(
    'manage_support'::public.staff_permission
  )
);


drop policy if exists "Authorized staff view identities"
on public.staff_display_identity;

create policy "Authorized staff view identities"
on public.staff_display_identity
for select
to authenticated
using (
  true
);


-- ============================================================
-- 18. REALTIME CHAT
--
-- Supabase Realtime will subscribe to messages.
-- ============================================================

alter table public.messages replica identity full;

alter table public.notifications replica identity full;


-- ============================================================
-- 19. CHAT UPDATED AT
-- ============================================================

drop trigger if exists conversations_updated_at
on public.conversations;

create trigger conversations_updated_at
before update on public.conversations
for each row
execute function public.set_updated_at();


-- ============================================================
-- 20. AUDIT HELPER
-- ============================================================

create or replace function public.write_audit_log(
  p_action public.audit_action_type,
  p_entity_type text,
  p_entity_id uuid,
  p_old_data jsonb default null,
  p_new_data jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin

  insert into public.audit_logs (
    actor_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    metadata
  )
  values (
    auth.uid(),
    p_action,
    p_entity_type,
    p_entity_id,
    p_old_data,
    p_new_data,
    p_metadata
  )
  returning id into v_id;

  return v_id;

end;
$$;


-- ============================================================
-- 21. NOTIFICATION HELPER
-- ============================================================

create or replace function public.create_notification(
  p_user_id uuid,
  p_type public.notification_type,
  p_title text,
  p_message text,
  p_action_url text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin

  insert into public.notifications (
    user_id,
    type,
    title,
    message,
    action_url,
    metadata
  )
  values (
    p_user_id,
    p_type,
    p_title,
    p_message,
    p_action_url,
    p_metadata
  )
  returning id into v_id;

  return v_id;

end;
$$;


-- ============================================================
-- 22. UPDATED AT
-- ============================================================

drop trigger if exists notification_preferences_updated_at
on public.notification_preferences;

create trigger notification_preferences_updated_at
before update on public.notification_preferences
for each row
execute function public.set_updated_at();


drop trigger if exists staff_display_identity_updated_at
on public.staff_display_identity;

create trigger staff_display_identity_updated_at
before update on public.staff_display_identity
for each row
execute function public.set_updated_at();


-- ============================================================
-- 23. INDEXES
-- ============================================================

create index if not exists conversations_status_idx
on public.conversations(status, updated_at desc);

create index if not exists conversations_assigned_idx
on public.conversations(assigned_to, updated_at desc);

create index if not exists messages_sender_idx
on public.messages(sender_id, created_at desc);

create index if not exists audit_logs_created_idx
on public.audit_logs(created_at desc);


-- ============================================================
-- 24. COMMENTS
-- ============================================================

comment on table public.notifications is
'In-app notifications for payments, courses, content, rewards, messages and other Breethub events.';

comment on table public.audit_logs is
'Administrative and security audit trail. Important actions must be recorded server-side.';

comment on table public.conversations is
'Breethub in-platform chat conversations. Phone numbers are not required or exposed.';

comment on table public.messages is
'Realtime chat messages. Access is restricted to conversation participants and authorized staff.';

comment on table public.conversation_assignments is
'Allows Admin to assign support/customer conversations to authorized staff such as Secretary or Customer Care.';-- =========================================================
-- BREETHUB BATCH 9
-- STORAGE BUCKETS + SECURE MEDIA POLICIES
-- =========================================================

-- ---------------------------------------------------------
-- 1. STORAGE BUCKETS
-- ---------------------------------------------------------

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('story-covers', 'story-covers', true),
  ('content-files', 'content-files', false),
  ('manuscripts', 'manuscripts', false),
  ('audio', 'audio', false),
  ('course-media', 'course-media', false),
  ('payment-proofs', 'payment-proofs', false),
  ('advertiser-media', 'advertiser-media', false),
  ('chat-attachments', 'chat-attachments', false)
on conflict (id) do nothing;


-- ---------------------------------------------------------
-- 2. AVATARS
-- Users may upload their own avatar.
-- Public can view avatars.
-- ---------------------------------------------------------

create policy "Users can upload their own avatar"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can update their own avatar"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can delete their own avatar"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Anyone can view avatars"
on storage.objects
for select
to public
using (bucket_id = 'avatars');


-- ---------------------------------------------------------
-- 3. STORY COVERS
-- Writers upload their own covers.
-- Admin can manage all covers.
-- Published covers can be viewed publicly.
-- ---------------------------------------------------------

create policy "Creators can upload story covers"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'story-covers'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators can update story covers"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'story-covers'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
)
with check (
  bucket_id = 'story-covers'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators can delete story covers"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'story-covers'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Anyone can view story covers"
on storage.objects
for select
to public
using (bucket_id = 'story-covers');


-- ---------------------------------------------------------
-- 4. PRIVATE CONTENT FILES
-- ---------------------------------------------------------

create policy "Creators can upload content files"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'content-files'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators can update content files"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'content-files'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
)
with check (
  bucket_id = 'content-files'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators can delete content files"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'content-files'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Owners and admins can view content files"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'content-files'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);


-- ---------------------------------------------------------
-- 5. MANUSCRIPTS
-- Manuscripts remain private.
-- ---------------------------------------------------------

create policy "Creators can upload manuscripts"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'manuscripts'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators and admins can update manuscripts"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'manuscripts'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
)
with check (
  bucket_id = 'manuscripts'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators and admins can delete manuscripts"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'manuscripts'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators and admins can view manuscripts"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'manuscripts'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);


-- ---------------------------------------------------------
-- 6. AUDIO
-- Narrations and approved audio assets.
-- ---------------------------------------------------------

create policy "Creators can upload audio"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'audio'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators and admins can update audio"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'audio'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
)
with check (
  bucket_id = 'audio'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Creators and admins can delete audio"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'audio'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Authenticated users can view audio"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'audio'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);


-- ---------------------------------------------------------
-- 7. COURSE MEDIA
-- ---------------------------------------------------------

create policy "Course creators and admins can upload course media"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'course-media'
  and public.is_admin()
);

create policy "Admins can update course media"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'course-media'
  and public.is_admin()
)
with check (
  bucket_id = 'course-media'
  and public.is_admin()
);

create policy "Admins can delete course media"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'course-media'
  and public.is_admin()
);

create policy "Authenticated users can view course media"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'course-media'
);


-- ---------------------------------------------------------
-- 8. PAYMENT PROOFS
-- Payment proofs must remain private.
-- ---------------------------------------------------------

create policy "Users can upload their own payment proof"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'payment-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can update their own payment proof"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'payment-proofs'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
)
with check (
  bucket_id = 'payment-proofs'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Users and authorized staff can view payment proofs"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'payment-proofs'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
    or public.has_staff_permission(
      'view_financials'::public.staff_permission
    )
  )
);


-- ---------------------------------------------------------
-- 9. ADVERTISER MEDIA
-- ---------------------------------------------------------

create policy "Advertisers can upload their own media"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'advertiser-media'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Advertisers can update their own media"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'advertiser-media'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
)
with check (
  bucket_id = 'advertiser-media'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Advertisers can delete their own media"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'advertiser-media'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

create policy "Advertisers and admins can view advertiser media"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'advertiser-media'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);


-- ---------------------------------------------------------
-- 10. CHAT ATTACHMENTS
-- ---------------------------------------------------------

create policy "Users can upload chat attachments"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can update their chat attachments"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can delete their chat attachments"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'chat-attachments'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users can view chat attachments"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'chat-attachments'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);


-- =========================================================
-- END BATCH 9
-- =========================================================-- =========================================================
-- BREETHUB BATCH 10
-- WRITER PUBLISHING + AI REVIEW WORKFLOW
-- =========================================================

-- ---------------------------------------------------------
-- 1. WRITER PUBLICATION STATUS
-- ---------------------------------------------------------

create type public.writer_submission_status as enum (
  'draft',
  'submitted',
  'ai_review',
  'changes_requested',
  'ready_for_admin_review',
  'admin_review',
  'approved',
  'rejected',
  'published',
  'suspended'
);

create type public.ai_review_result as enum (
  'pending',
  'passed',
  'needs_revision',
  'failed'
);


-- ---------------------------------------------------------
-- 2. WRITER PUBLICATION SUBMISSIONS
-- ---------------------------------------------------------

create table public.writer_publication_submissions (
  id uuid primary key default gen_random_uuid(),

  writer_id uuid not null references public.profiles(id)
    on delete cascade,

  story_id uuid references public.stories(id)
    on delete cascade,

  chapter_id uuid references public.chapters(id)
    on delete cascade,

  manuscript_submission_id uuid
    references public.manuscript_submissions(id)
    on delete set null,

  status public.writer_submission_status not null
    default 'draft',

  ai_result public.ai_review_result not null
    default 'pending',

  submitted_at timestamptz,
  ai_reviewed_at timestamptz,
  admin_reviewed_at timestamptz,
  published_at timestamptz,

  writer_notes text,
  admin_notes text,
  rejection_reason text,
  revision_notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint publication_submission_has_content
  check (
    story_id is not null
    or chapter_id is not null
  )
);


-- ---------------------------------------------------------
-- 3. AI REVIEW CHECKLIST
-- ---------------------------------------------------------

create table public.writer_ai_review_checks (
  id uuid primary key default gen_random_uuid(),

  submission_id uuid not null
    references public.writer_publication_submissions(id)
    on delete cascade,

  grammar_score numeric(5,2),
  readability_score numeric(5,2),
  originality_score numeric(5,2),
  consistency_score numeric(5,2),
  structure_score numeric(5,2),
  title_score numeric(5,2),
  description_score numeric(5,2),
  cover_presentation_score numeric(5,2),

  grammar_notes text,
  readability_notes text,
  originality_notes text,
  consistency_notes text,
  structure_notes text,
  title_notes text,
  description_notes text,
  cover_notes text,

  overall_score numeric(5,2),

  result public.ai_review_result not null
    default 'pending',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 4. AI SUGGESTIONS
-- ---------------------------------------------------------

create table public.writer_ai_suggestions (
  id uuid primary key default gen_random_uuid(),

  submission_id uuid not null
    references public.writer_publication_submissions(id)
    on delete cascade,

  category text not null,

  original_text text,
  suggested_text text,

  explanation text,

  accepted_by_writer boolean,

  created_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 5. WRITER REVISION HISTORY
-- ---------------------------------------------------------

create table public.writer_revision_history (
  id uuid primary key default gen_random_uuid(),

  submission_id uuid not null
    references public.writer_publication_submissions(id)
    on delete cascade,

  revision_number integer not null default 1,

  change_summary text,

  submitted_by uuid not null
    references public.profiles(id)
    on delete cascade,

  created_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 6. CONTENT REVIEW DECISIONS
-- ---------------------------------------------------------

create table public.content_review_decisions (
  id uuid primary key default gen_random_uuid(),

  submission_id uuid not null
    references public.writer_publication_submissions(id)
    on delete cascade,

  reviewer_id uuid not null
    references public.profiles(id)
    on delete restrict,

  decision text not null
    check (
      decision in (
        'approved',
        'rejected',
        'changes_requested'
      )
    ),

  notes text,
  rejection_reason text,

  created_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 7. PREVENT NORMAL USERS FROM PUBLISHING DIRECTLY
-- ---------------------------------------------------------

create or replace function public.can_publish_submission(
  submission_uuid uuid
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.writer_publication_submissions s
    where s.id = submission_uuid
      and s.status = 'approved'
  );
$$;


-- ---------------------------------------------------------
-- 8. INDEXES
-- ---------------------------------------------------------

create index writer_publication_submissions_writer_idx
on public.writer_publication_submissions(writer_id);

create index writer_publication_submissions_story_idx
on public.writer_publication_submissions(story_id);

create index writer_publication_submissions_chapter_idx
on public.writer_publication_submissions(chapter_id);

create index writer_publication_submissions_status_idx
on public.writer_publication_submissions(status);

create index writer_ai_review_checks_submission_idx
on public.writer_ai_review_checks(submission_id);

create index writer_ai_suggestions_submission_idx
on public.writer_ai_suggestions(submission_id);

create index writer_revision_history_submission_idx
on public.writer_revision_history(submission_id);

create index content_review_decisions_submission_idx
on public.content_review_decisions(submission_id);


-- ---------------------------------------------------------
-- 9. UPDATED-AT TRIGGERS
-- ---------------------------------------------------------

create trigger writer_publication_submissions_updated_at
before update on public.writer_publication_submissions
for each row
execute function public.set_updated_at();

create trigger writer_ai_review_checks_updated_at
before update on public.writer_ai_review_checks
for each row
execute function public.set_updated_at();


-- ---------------------------------------------------------
-- 10. ROW LEVEL SECURITY
-- ---------------------------------------------------------

alter table public.writer_publication_submissions enable row level security;
alter table public.writer_ai_review_checks enable row level security;
alter table public.writer_ai_suggestions enable row level security;
alter table public.writer_revision_history enable row level security;
alter table public.content_review_decisions enable row level security;


-- ---------------------------------------------------------
-- 11. WRITERS CAN VIEW THEIR OWN SUBMISSIONS
-- ---------------------------------------------------------

create policy "Writers can view their own publication submissions"
on public.writer_publication_submissions
for select
to authenticated
using (
  writer_id = auth.uid()
  or public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
);


-- ---------------------------------------------------------
-- 12. WRITERS CAN CREATE THEIR OWN SUBMISSIONS
-- ---------------------------------------------------------

create policy "Writers can create their own publication submissions"
on public.writer_publication_submissions
for insert
to authenticated
with check (
  writer_id = auth.uid()
);


-- ---------------------------------------------------------
-- 13. WRITERS CAN UPDATE THEIR OWN DRAFTS/REVISIONS
-- ---------------------------------------------------------

create policy "Writers can update their own publication submissions"
on public.writer_publication_submissions
for update
to authenticated
using (
  writer_id = auth.uid()
  and status in (
    'draft',
    'changes_requested'
  )
)
with check (
  writer_id = auth.uid()
  and status in (
    'draft',
    'submitted',
    'ai_review',
    'changes_requested',
    'ready_for_admin_review'
  )
);


-- ---------------------------------------------------------
-- 14. ADMIN/CONTENT STAFF CAN MANAGE SUBMISSIONS
-- ---------------------------------------------------------

create policy "Authorized staff can manage publication submissions"
on public.writer_publication_submissions
for all
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
)
with check (
  public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
);


-- ---------------------------------------------------------
-- 15. AI REVIEW CHECKS
-- ---------------------------------------------------------

create policy "Writers can view their AI review"
on public.writer_ai_review_checks
for select
to authenticated
using (
  exists (
    select 1
    from public.writer_publication_submissions s
    where s.id = submission_id
      and s.writer_id = auth.uid()
  )
  or public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
);

create policy "Authorized reviewers can create AI reviews"
on public.writer_ai_review_checks
for insert
to authenticated
with check (
  public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
);

create policy "Authorized reviewers can update AI reviews"
on public.writer_ai_review_checks
for update
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
)
with check (
  public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
);


-- ---------------------------------------------------------
-- 16. AI SUGGESTIONS
-- ---------------------------------------------------------

create policy "Writers can view their AI suggestions"
on public.writer_ai_suggestions
for select
to authenticated
using (
  exists (
    select 1
    from public.writer_publication_submissions s
    where s.id = submission_id
      and s.writer_id = auth.uid()
  )
  or public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
);

create policy "Authorized reviewers can create AI suggestions"
on public.writer_ai_suggestions
for insert
to authenticated
with check (
  public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
);

create policy "Writers can update their suggestion decisions"
on public.writer_ai_suggestions
for update
to authenticated
using (
  exists (
    select 1
    from public.writer_publication_submissions s
    where s.id = submission_id
      and s.writer_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.writer_publication_submissions s
    where s.id = submission_id
      and s.writer_id = auth.uid()
  )
);


-- ---------------------------------------------------------
-- 17. REVISION HISTORY
-- ---------------------------------------------------------

create policy "Writers can view their revision history"
on public.writer_revision_history
for select
to authenticated
using (
  submitted_by = auth.uid()
  or exists (
    select 1
    from public.writer_publication_submissions s
    where s.id = submission_id
      and s.writer_id = auth.uid()
  )
  or public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
);

create policy "Writers can create revision history"
on public.writer_revision_history
for insert
to authenticated
with check (
  submitted_by = auth.uid()
);


-- ---------------------------------------------------------
-- 18. REVIEW DECISIONS
-- ---------------------------------------------------------

create policy "Authorized staff can view review decisions"
on public.content_review_decisions
for select
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission(
    'manage_content'::public.staff_permission
  )
  or exists (
    select 1
    from public.writer_publication_submissions s
    where s.id = submission_id
      and s.writer_id = auth.uid()
  )
);

create policy "Authorized staff can create review decisions"
on public.content_review_decisions
for insert
to authenticated
with check (
  reviewer_id = auth.uid()
  and (
    public.is_admin()
    or public.has_staff_permission(
      'manage_content'::public.staff_permission
    )
  )
);


-- ---------------------------------------------------------
-- 19. COMMENTS
-- ---------------------------------------------------------

comment on table public.writer_publication_submissions is
'Controls the writer submission lifecycle from draft through AI review and admin approval.';

comment on table public.writer_ai_review_checks is
'Stores AI quality checks for grammar, readability, originality, consistency, structure and presentation.';

comment on table public.writer_ai_suggestions is
'Stores AI suggestions that the writer can review before publication.';

comment on table public.writer_revision_history is
'Stores revision history for writer submissions.';

comment on table public.content_review_decisions is
'Stores Admin or authorized staff publication decisions.';


-- =========================================================
-- END BATCH 10
-- =========================================================-- =========================================================
-- BREETHUB BATCH 11
-- FOLLOWS + LIKES + SAVES + COMMENTS + ENGAGEMENT
-- =========================================================


-- ---------------------------------------------------------
-- 1. FOLLOWS
-- ---------------------------------------------------------

create table public.user_follows (
  id uuid primary key default gen_random_uuid(),

  follower_id uuid not null
    references public.profiles(id)
    on delete cascade,

  following_id uuid not null
    references public.profiles(id)
    on delete cascade,

  created_at timestamptz not null default now(),

  constraint user_follows_no_self_follow
    check (follower_id <> following_id),

  constraint user_follows_unique
    unique (follower_id, following_id)
);

create index user_follows_follower_idx
on public.user_follows(follower_id);

create index user_follows_following_idx
on public.user_follows(following_id);


-- ---------------------------------------------------------
-- 2. STORY LIKES
-- ---------------------------------------------------------

create table public.story_likes (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  story_id uuid not null
    references public.stories(id)
    on delete cascade,

  created_at timestamptz not null default now(),

  constraint story_likes_unique
    unique (user_id, story_id)
);

create index story_likes_story_idx
on public.story_likes(story_id);

create index story_likes_user_idx
on public.story_likes(user_id);


-- ---------------------------------------------------------
-- 3. CHAPTER LIKES
-- ---------------------------------------------------------

create table public.chapter_likes (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  chapter_id uuid not null
    references public.chapters(id)
    on delete cascade,

  created_at timestamptz not null default now(),

  constraint chapter_likes_unique
    unique (user_id, chapter_id)
);

create index chapter_likes_chapter_idx
on public.chapter_likes(chapter_id);


-- ---------------------------------------------------------
-- 4. SAVED STORIES
-- ---------------------------------------------------------

create table public.saved_stories (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  story_id uuid not null
    references public.stories(id)
    on delete cascade,

  created_at timestamptz not null default now(),

  constraint saved_stories_unique
    unique (user_id, story_id)
);

create index saved_stories_user_idx
on public.saved_stories(user_id);

create index saved_stories_story_idx
on public.saved_stories(story_id);


-- ---------------------------------------------------------
-- 5. COMMENTS
-- ---------------------------------------------------------

create table public.content_comments (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  story_id uuid
    references public.stories(id)
    on delete cascade,

  chapter_id uuid
    references public.chapters(id)
    on delete cascade,

  parent_comment_id uuid
    references public.content_comments(id)
    on delete cascade,

  body text not null,

  is_edited boolean not null default false,
  is_deleted boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint comment_has_content
    check (
      story_id is not null
      or chapter_id is not null
    )
);

create index content_comments_story_idx
on public.content_comments(story_id);

create index content_comments_chapter_idx
on public.content_comments(chapter_id);

create index content_comments_parent_idx
on public.content_comments(parent_comment_id);

create index content_comments_user_idx
on public.content_comments(user_id);


-- ---------------------------------------------------------
-- 6. COMMENT REPORTS
-- ---------------------------------------------------------

create table public.comment_reports (
  id uuid primary key default gen_random_uuid(),

  comment_id uuid not null
    references public.content_comments(id)
    on delete cascade,

  reporter_id uuid not null
    references public.profiles(id)
    on delete cascade,

  reason text not null,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'reviewed',
        'dismissed',
        'action_taken'
      )
    ),

  reviewed_by uuid
    references public.profiles(id)
    on delete set null,

  reviewed_at timestamptz,

  created_at timestamptz not null default now(),

  constraint comment_report_unique
    unique (comment_id, reporter_id)
);


-- ---------------------------------------------------------
-- 7. SHARES
-- ---------------------------------------------------------

create table public.content_shares (
  id uuid primary key default gen_random_uuid(),

  user_id uuid
    references public.profiles(id)
    on delete set null,

  story_id uuid
    references public.stories(id)
    on delete cascade,

  chapter_id uuid
    references public.chapters(id)
    on delete cascade,

  platform text,

  created_at timestamptz not null default now(),

  constraint share_has_content
    check (
      story_id is not null
      or chapter_id is not null
    )
);

create index content_shares_story_idx
on public.content_shares(story_id);

create index content_shares_chapter_idx
on public.content_shares(chapter_id);


-- ---------------------------------------------------------
-- 8. NOTIFICATION TRIGGER FOR NEW FOLLOWERS
-- ---------------------------------------------------------

create or replace function public.notify_new_follower()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  insert into public.notifications (
    user_id,
    type,
    title,
    body,
    data
  )
  values (
    new.following_id,
    'social',
    'New follower',
    'Someone started following you on Breethub.',
    jsonb_build_object(
      'follower_id', new.follower_id
    )
  );

  return new;

exception
  when others then
    return new;
end;
$$;


drop trigger if exists user_follow_notification
on public.user_follows;

create trigger user_follow_notification
after insert on public.user_follows
for each row
execute function public.notify_new_follower();


-- ---------------------------------------------------------
-- 9. UPDATED AT
-- ---------------------------------------------------------

create trigger content_comments_updated_at
before update on public.content_comments
for each row
execute function public.set_updated_at();


-- ---------------------------------------------------------
-- 10. ENABLE RLS
-- ---------------------------------------------------------

alter table public.user_follows enable row level security;
alter table public.story_likes enable row level security;
alter table public.chapter_likes enable row level security;
alter table public.saved_stories enable row level security;
alter table public.content_comments enable row level security;
alter table public.comment_reports enable row level security;
alter table public.content_shares enable row level security;


-- ---------------------------------------------------------
-- 11. FOLLOW POLICIES
-- ---------------------------------------------------------

create policy "Users can view follows"
on public.user_follows
for select
to authenticated
using (
  follower_id = auth.uid()
  or following_id = auth.uid()
  or public.is_admin()
);

create policy "Users can follow"
on public.user_follows
for insert
to authenticated
with check (
  follower_id = auth.uid()
  and follower_id <> following_id
);

create policy "Users can unfollow"
on public.user_follows
for delete
to authenticated
using (
  follower_id = auth.uid()
);


-- ---------------------------------------------------------
-- 12. STORY LIKE POLICIES
-- ---------------------------------------------------------

create policy "Users can view story likes"
on public.story_likes
for select
to authenticated
using (true);

create policy "Users can like stories"
on public.story_likes
for insert
to authenticated
with check (
  user_id = auth.uid()
);

create policy "Users can remove story likes"
on public.story_likes
for delete
to authenticated
using (
  user_id = auth.uid()
);


-- ---------------------------------------------------------
-- 13. CHAPTER LIKE POLICIES
-- ---------------------------------------------------------

create policy "Users can view chapter likes"
on public.chapter_likes
for select
to authenticated
using (true);

create policy "Users can like chapters"
on public.chapter_likes
for insert
to authenticated
with check (
  user_id = auth.uid()
);

create policy "Users can remove chapter likes"
on public.chapter_likes
for delete
to authenticated
using (
  user_id = auth.uid()
);


-- ---------------------------------------------------------
-- 14. SAVE POLICIES
-- ---------------------------------------------------------

create policy "Users can view their saved stories"
on public.saved_stories
for select
to authenticated
using (
  user_id = auth.uid()
);

create policy "Users can save stories"
on public.saved_stories
for insert
to authenticated
with check (
  user_id = auth.uid()
);

create policy "Users can remove saved stories"
on public.saved_stories
for delete
to authenticated
using (
  user_id = auth.uid()
);


-- ---------------------------------------------------------
-- 15. COMMENT POLICIES
-- ---------------------------------------------------------

create policy "Users can view comments"
on public.content_comments
for select
to authenticated
using (
  is_deleted = false
  or user_id = auth.uid()
  or public.is_admin()
);

create policy "Users can create comments"
on public.content_comments
for insert
to authenticated
with check (
  user_id = auth.uid()
);

create policy "Users can edit their comments"
on public.content_comments
for update
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
)
with check (
  user_id = auth.uid()
  or public.is_admin()
);

create policy "Users can delete their comments"
on public.content_comments
for delete
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- ---------------------------------------------------------
-- 16. COMMENT REPORT POLICIES
-- ---------------------------------------------------------

create policy "Users can report comments"
on public.comment_reports
for insert
to authenticated
with check (
  reporter_id = auth.uid()
);

create policy "Users can view their reports"
on public.comment_reports
for select
to authenticated
using (
  reporter_id = auth.uid()
  or public.is_admin()
);

create policy "Admins can manage comment reports"
on public.comment_reports
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ---------------------------------------------------------
-- 17. SHARE POLICIES
-- ---------------------------------------------------------

create policy "Users can view their shares"
on public.content_shares
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);

create policy "Users can create shares"
on public.content_shares
for insert
to authenticated
with check (
  user_id = auth.uid()
);


-- ---------------------------------------------------------
-- 18. COMMENTS
-- ---------------------------------------------------------

comment on table public.user_follows is
'Stores creator and user follow relationships.';

comment on table public.story_likes is
'Stores story likes without allowing duplicate likes.';

comment on table public.chapter_likes is
'Stores chapter likes without allowing duplicate likes.';

comment on table public.saved_stories is
'Stores stories saved by readers.';

comment on table public.content_comments is
'Stores story and chapter comments and replies.';

comment on table public.comment_reports is
'Stores reports submitted against comments.';

comment on table public.content_shares is
'Stores content sharing activity.';


-- =========================================================
-- END BATCH 11
-- =========================================================-- =========================================================
-- BREETHUB BATCH 12
-- PAID READING ACCESS + CHAPTER UNLOCKS + FREE SPIN
-- =========================================================


-- ---------------------------------------------------------
-- 1. CHAPTER PURCHASE STATUS
-- ---------------------------------------------------------

create type public.chapter_purchase_status as enum (
  'pending',
  'payment_pending',
  'approved',
  'rejected',
  'refunded',
  'cancelled'
);


-- ---------------------------------------------------------
-- 2. CHAPTER PURCHASES
-- ---------------------------------------------------------

create table public.chapter_purchases (
  id uuid primary key default gen_random_uuid(),

  reader_id uuid not null
    references public.profiles(id)
    on delete cascade,

  story_id uuid not null
    references public.stories(id)
    on delete cascade,

  chapter_id uuid not null
    references public.chapters(id)
    on delete cascade,

  payment_id uuid
    references public.payments(id)
    on delete set null,

  amount numeric(14,2) not null,
  currency text not null,

  status public.chapter_purchase_status not null
    default 'pending',

  purchased_at timestamptz,
  approved_at timestamptz,
  approved_by uuid
    references public.profiles(id)
    on delete set null,

  rejection_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chapter_purchase_positive_amount
    check (amount >= 0),

  constraint chapter_purchase_unique_reader_chapter
    unique (reader_id, chapter_id)
);


-- ---------------------------------------------------------
-- 3. READING ACCESS
-- ---------------------------------------------------------

create table public.chapter_access (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  chapter_id uuid not null
    references public.chapters(id)
    on delete cascade,

  purchase_id uuid
    references public.chapter_purchases(id)
    on delete set null,

  access_type text not null
    check (
      access_type in (
        'free',
        'purchase',
        'reward',
        'admin_grant'
      )
    ),

  granted_at timestamptz not null default now(),

  expires_at timestamptz,

  constraint chapter_access_unique
    unique (user_id, chapter_id)
);


-- ---------------------------------------------------------
-- 4. FREE SPIN CONFIGURATION
-- ---------------------------------------------------------

create table public.free_spin_settings (
  id uuid primary key default gen_random_uuid(),

  paid_chapters_required integer not null default 10,

  enabled boolean not null default true,

  cooldown_days integer not null default 3,

  updated_by uuid
    references public.profiles(id)
    on delete set null,

  updated_at timestamptz not null default now(),

  constraint free_spin_positive_requirement
    check (paid_chapters_required > 0),

  constraint free_spin_valid_cooldown
    check (cooldown_days >= 0)
);


-- ---------------------------------------------------------
-- 5. INSERT DEFAULT CONFIGURATION
-- ---------------------------------------------------------

insert into public.free_spin_settings (
  paid_chapters_required,
  enabled,
  cooldown_days
)
select 10, true, 3
where not exists (
  select 1
  from public.free_spin_settings
);


-- ---------------------------------------------------------
-- 6. READER REWARD ACCOUNT
-- ---------------------------------------------------------

create table public.reader_reward_accounts (
  user_id uuid primary key
    references public.profiles(id)
    on delete cascade,

  qualifying_paid_chapters integer not null default 0,

  spins_earned integer not null default 0,

  spins_used integer not null default 0,

  next_spin_available_at timestamptz,

  updated_at timestamptz not null default now(),

  constraint qualifying_paid_chapters_nonnegative
    check (qualifying_paid_chapters >= 0),

  constraint spins_earned_nonnegative
    check (spins_earned >= 0),

  constraint spins_used_nonnegative
    check (spins_used >= 0)
);


-- ---------------------------------------------------------
-- 7. FREE SPIN REWARDS
-- ---------------------------------------------------------

create table public.free_spin_rewards (
  id uuid primary key default gen_random_uuid(),

  name text not null,

  description text,

  reward_type text not null
    check (
      reward_type in (
        'free_chapter',
        'two_free_chapters',
        'three_free_chapters',
        'reading_credit',
        'another_spin',
        'special_reward',
        'try_again'
      )
    ),

  reward_value numeric(14,2),

  active boolean not null default true,

  probability_weight numeric(12,4) not null default 1,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),

  constraint reward_probability_nonnegative
    check (probability_weight >= 0)
);


-- ---------------------------------------------------------
-- 8. SPIN HISTORY
-- ---------------------------------------------------------

create table public.free_spin_history (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  reward_id uuid
    references public.free_spin_rewards(id)
    on delete set null,

  result_name text,

  reward_type text,

  reward_value numeric(14,2),

  created_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 9. REWARD GRANTS
-- ---------------------------------------------------------

create table public.reader_reward_grants (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  reward_type text not null,

  chapter_id uuid
    references public.chapters(id)
    on delete set null,

  amount numeric(14,2),

  source text not null
    check (
      source in (
        'free_spin',
        'admin',
        'promotion',
        'other'
      )
    ),

  used boolean not null default false,

  used_at timestamptz,

  created_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 10. INDEXES
-- ---------------------------------------------------------

create index chapter_purchases_reader_idx
on public.chapter_purchases(reader_id);

create index chapter_purchases_story_idx
on public.chapter_purchases(story_id);

create index chapter_purchases_chapter_idx
on public.chapter_purchases(chapter_id);

create index chapter_purchases_status_idx
on public.chapter_purchases(status);

create index chapter_access_user_idx
on public.chapter_access(user_id);

create index chapter_access_chapter_idx
on public.chapter_access(chapter_id);

create index free_spin_history_user_idx
on public.free_spin_history(user_id);

create index reader_reward_grants_user_idx
on public.reader_reward_grants(user_id);


-- ---------------------------------------------------------
-- 11. UPDATED AT
-- ---------------------------------------------------------

create trigger chapter_purchases_updated_at
before update on public.chapter_purchases
for each row
execute function public.set_updated_at();

create trigger free_spin_settings_updated_at
before update on public.free_spin_settings
for each row
execute function public.set_updated_at();

create trigger reader_reward_accounts_updated_at
before update on public.reader_reward_accounts
for each row
execute function public.set_updated_at();


-- ---------------------------------------------------------
-- 12. ENABLE RLS
-- ---------------------------------------------------------

alter table public.chapter_purchases enable row level security;
alter table public.chapter_access enable row level security;
alter table public.free_spin_settings enable row level security;
alter table public.reader_reward_accounts enable row level security;
alter table public.free_spin_rewards enable row level security;
alter table public.free_spin_history enable row level security;
alter table public.reader_reward_grants enable row level security;


-- ---------------------------------------------------------
-- 13. CHAPTER PURCHASE POLICIES
-- ---------------------------------------------------------

create policy "Users can view their chapter purchases"
on public.chapter_purchases
for select
to authenticated
using (
  reader_id = auth.uid()
  or public.is_admin()
  or public.has_staff_permission(
    'view_financials'::public.staff_permission
  )
);

create policy "Users can create chapter purchases"
on public.chapter_purchases
for insert
to authenticated
with check (
  reader_id = auth.uid()
);

create policy "Authorized staff can manage chapter purchases"
on public.chapter_purchases
for update
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission(
    'view_financials'::public.staff_permission
  )
)
with check (
  public.is_admin()
  or public.has_staff_permission(
    'view_financials'::public.staff_permission
  )
);


-- ---------------------------------------------------------
-- 14. CHAPTER ACCESS POLICIES
-- ---------------------------------------------------------

create policy "Users can view their chapter access"
on public.chapter_access
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);

create policy "Authorized systems can create chapter access"
on public.chapter_access
for insert
to authenticated
with check (
  user_id = auth.uid()
  or public.is_admin()
);


-- ---------------------------------------------------------
-- 15. FREE SPIN SETTINGS
-- ---------------------------------------------------------

create policy "Authenticated users can view free spin settings"
on public.free_spin_settings
for select
to authenticated
using (true);

create policy "Admins can manage free spin settings"
on public.free_spin_settings
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ---------------------------------------------------------
-- 16. REWARD ACCOUNTS
-- ---------------------------------------------------------

create policy "Users can view their reward account"
on public.reader_reward_accounts
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);

create policy "Users can create their reward account"
on public.reader_reward_accounts
for insert
to authenticated
with check (
  user_id = auth.uid()
);

create policy "Admins can manage reward accounts"
on public.reader_reward_accounts
for update
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ---------------------------------------------------------
-- 17. FREE SPIN REWARDS
-- ---------------------------------------------------------

create policy "Authenticated users can view active rewards"
on public.free_spin_rewards
for select
to authenticated
using (
  active = true
  or public.is_admin()
);

create policy "Admins can manage rewards"
on public.free_spin_rewards
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ---------------------------------------------------------
-- 18. SPIN HISTORY
-- ---------------------------------------------------------

create policy "Users can view their spin history"
on public.free_spin_history
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- ---------------------------------------------------------
-- 19. REWARD GRANTS
-- ---------------------------------------------------------

create policy "Users can view their rewards"
on public.reader_reward_grants
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);

create policy "Admins can manage reward grants"
on public.reader_reward_grants
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ---------------------------------------------------------
-- 20. FUNCTION TO CHECK QUALIFYING PAID CHAPTERS
-- ---------------------------------------------------------

create or replace function public.refresh_reader_reward_account(
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  qualifying_count integer;
  required_count integer;
  current_spins integer;
begin

  select count(*)
  into qualifying_count
  from public.chapter_purchases
  where reader_id = target_user_id
    and status = 'approved';

  select paid_chapters_required
  into required_count
  from public.free_spin_settings
  where enabled = true
  order by updated_at desc
  limit 1;

  if required_count is null then
    required_count := 10;
  end if;

  insert into public.reader_reward_accounts (
    user_id,
    qualifying_paid_chapters
  )
  values (
    target_user_id,
    qualifying_count
  )
  on conflict (user_id)
  do update set
    qualifying_paid_chapters = excluded.qualifying_paid_chapters,
    updated_at = now();

  select spins_earned
  into current_spins
  from public.reader_reward_accounts
  where user_id = target_user_id;

  if qualifying_count >= required_count then

    update public.reader_reward_accounts
    set
      spins_earned =
        greatest(
          spins_earned,
          floor(qualifying_count / required_count)
        ),
      updated_at = now()
    where user_id = target_user_id;

  end if;

end;
$$;


-- ---------------------------------------------------------
-- 21. COMMENTS
-- ---------------------------------------------------------

comment on table public.chapter_purchases is
'Stores verified reader chapter purchases. Only approved purchases qualify for paid-chapter rewards.';

comment on table public.chapter_access is
'Stores actual reading access granted to a user.';

comment on table public.free_spin_settings is
'Admin-controlled Free Spin configuration.';

comment on table public.reader_reward_accounts is
'Tracks qualifying paid chapters and Free Spin eligibility.';

comment on table public.free_spin_rewards is
'Admin-controlled rewards available through Free Spin.';

comment on table public.free_spin_history is
'Records every Free Spin result.';

comment on table public.reader_reward_grants is
'Stores actual rewards granted to readers.';


-- =========================================================
-- END BATCH 12
-- =========================================================-- ============================================================
-- BREETHUB BATCH 13
-- SECURE PAYMENTS, PRICING & ACCESS CONTROLS
-- ============================================================

-- ------------------------------------------------------------
-- 1. Payment purpose / verification configuration
-- ------------------------------------------------------------

create table if not exists public.platform_pricing (
  id uuid primary key default gen_random_uuid(),

  setting_key text not null unique,

  description text,

  ngn_amount numeric(14,2),
  usd_amount numeric(14,2),
  gbp_amount numeric(14,2),
  eur_amount numeric(14,2),
  ghs_amount numeric(14,2),
  kes_amount numeric(14,2),

  is_active boolean not null default true,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.platform_pricing is
'Admin-controlled platform pricing. Users and creators cannot change these values.';

comment on column public.platform_pricing.setting_key is
'Unique machine-readable pricing key such as reading_fee, writer_course_fee, ai_bootcamp_fee.';


-- ------------------------------------------------------------
-- 2. Reader chapter fee distribution configuration
-- ------------------------------------------------------------

create table if not exists public.chapter_revenue_rules (
  id uuid primary key default gen_random_uuid(),

  currency_code text not null unique,

  reading_fee numeric(14,2) not null,

  writer_share numeric(14,2) not null default 0,
  investor_pool_share numeric(14,2) not null default 0,
  admin_share numeric(14,2) not null default 0,

  is_active boolean not null default true,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chapter_revenue_rules_nonnegative
    check (
      reading_fee >= 0
      and writer_share >= 0
      and investor_pool_share >= 0
      and admin_share >= 0
    ),

  constraint chapter_revenue_rules_balanced
    check (
      reading_fee =
      writer_share +
      investor_pool_share +
      admin_share
    )
);

comment on table public.chapter_revenue_rules is
'Admin-controlled chapter reading fee and revenue allocation.';


-- ------------------------------------------------------------
-- 3. Only administrators can manage pricing
-- ------------------------------------------------------------

alter table public.platform_pricing enable row level security;
alter table public.chapter_revenue_rules enable row level security;

drop policy if exists "Admins manage platform pricing"
on public.platform_pricing;

create policy "Admins manage platform pricing"
on public.platform_pricing
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Admins manage chapter revenue rules"
on public.chapter_revenue_rules;

create policy "Admins manage chapter revenue rules"
on public.chapter_revenue_rules
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ------------------------------------------------------------
-- 4. Prevent normal users from inserting approved payments
-- ------------------------------------------------------------

drop policy if exists "Users create pending payments"
on public.payments;

create policy "Users create pending payments"
on public.payments
for insert
to authenticated
with check (
  user_id = auth.uid()
  and status in (
    'pending',
    'payment_pending'
  )
);


-- ------------------------------------------------------------
-- 5. Prevent normal users from inserting approved chapter purchases
-- ------------------------------------------------------------

drop policy if exists "Users create chapter purchases"
on public.chapter_purchases;

create policy "Users create chapter purchases"
on public.chapter_purchases
for insert
to authenticated
with check (
  reader_id = auth.uid()
  and status in (
    'pending',
    'payment_pending'
  )
);


-- ------------------------------------------------------------
-- 6. Remove direct client creation of paid chapter access
-- ------------------------------------------------------------

drop policy if exists "Users create their own chapter access"
on public.chapter_access;


-- ------------------------------------------------------------
-- 7. Secure function for granting chapter access
-- ------------------------------------------------------------

create or replace function public.grant_paid_chapter_access(
  p_user_id uuid,
  p_chapter_id uuid,
  p_purchase_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_access_id uuid;
begin

  if not (
    public.is_admin()
    or auth.uid() = p_user_id
  ) then
    raise exception 'Not authorized';
  end if;

  if not exists (
    select 1
    from public.chapter_purchases cp
    where cp.id = p_purchase_id
      and cp.reader_id = p_user_id
      and cp.chapter_id = p_chapter_id
      and cp.status = 'approved'
  ) then
    raise exception 'Approved chapter purchase not found';
  end if;

  insert into public.chapter_access (
    user_id,
    chapter_id,
    access_type,
    purchase_id,
    granted_at
  )
  values (
    p_user_id,
    p_chapter_id,
    'purchase',
    p_purchase_id,
    now()
  )
  on conflict (user_id, chapter_id)
  do update set
    purchase_id = excluded.purchase_id,
    access_type = excluded.access_type,
    granted_at = excluded.granted_at

  returning id into v_access_id;

  return v_access_id;
end;
$$;


-- ------------------------------------------------------------
-- 8. Secure function for checking chapter access
-- ------------------------------------------------------------

create or replace function public.user_can_read_chapter(
  p_user_id uuid,
  p_chapter_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_free boolean;
  v_has_access boolean;
begin

  select is_free
  into v_is_free
  from public.chapters
  where id = p_chapter_id
    and status = 'published';

  if coalesce(v_is_free, false) then
    return true;
  end if;

  select exists (
    select 1
    from public.chapter_access ca
    where ca.user_id = p_user_id
      and ca.chapter_id = p_chapter_id
  )
  into v_has_access;

  return coalesce(v_has_access, false);
end;
$$;


-- ------------------------------------------------------------
-- 9. Prevent writers from setting their own story prices
-- ------------------------------------------------------------

create or replace function public.prevent_creator_price_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

  if auth.uid() is null then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  if auth.uid() = old.creator_id then

    if new.reading_price is distinct from old.reading_price
       or new.reading_currency is distinct from old.reading_currency
       or new.price_locked is distinct from old.price_locked then

      raise exception 'Only Breethub Admin can change story pricing';
    end if;

  end if;

  return new;
end;
$$;


drop trigger if exists prevent_creator_price_change_trigger
on public.stories;

create trigger prevent_creator_price_change_trigger
before update on public.stories
for each row
execute function public.prevent_creator_price_change();


-- ------------------------------------------------------------
-- 10. Prevent writers from setting their own chapter prices
-- ------------------------------------------------------------

create or replace function public.prevent_chapter_price_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creator_id uuid;
begin

  if auth.uid() is null then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  select creator_id
  into v_creator_id
  from public.stories
  where id = new.story_id;

  if auth.uid() = v_creator_id then

    if new.price is distinct from old.price
       or new.price_currency is distinct from old.price_currency then

      raise exception 'Only Breethub Admin can change chapter pricing';
    end if;

  end if;

  return new;
end;
$$;


drop trigger if exists prevent_chapter_price_change_trigger
on public.chapters;

create trigger prevent_chapter_price_change_trigger
before update on public.chapters
for each row
execute function public.prevent_chapter_price_change();


-- ------------------------------------------------------------
-- 11. Admin-only price update helpers
-- ------------------------------------------------------------

create or replace function public.admin_set_story_price(
  p_story_id uuid,
  p_amount numeric,
  p_currency text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  update public.stories
  set
    reading_price = p_amount,
    reading_currency = p_currency,
    price_locked = true,
    updated_at = now()
  where id = p_story_id;

  return found;
end;
$$;


create or replace function public.admin_set_chapter_price(
  p_chapter_id uuid,
  p_amount numeric,
  p_currency text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  update public.chapters
  set
    price = p_amount,
    price_currency = p_currency,
    updated_at = now()
  where id = p_chapter_id;

  return found;
end;
$$;


-- ------------------------------------------------------------
-- 12. Default NGN reading fee configuration
-- ------------------------------------------------------------

insert into public.platform_pricing (
  setting_key,
  description,
  ngn_amount
)
values (
  'chapter_reading_fee_default',
  'Default chapter reading fee controlled by Breethub Admin',
  200
)
on conflict (setting_key)
do nothing;


-- ------------------------------------------------------------
-- 13. Default NGN chapter revenue distribution
-- ------------------------------------------------------------

insert into public.chapter_revenue_rules (
  currency_code,
  reading_fee,
  writer_share,
  investor_pool_share,
  admin_share
)
values (
  'NGN',
  200,
  50,
  50,
  100
)
on conflict (currency_code)
do nothing;


-- ------------------------------------------------------------
-- 14. Updated-at triggers
-- ------------------------------------------------------------

drop trigger if exists platform_pricing_updated_at
on public.platform_pricing;

create trigger platform_pricing_updated_at
before update on public.platform_pricing
for each row
execute function public.set_updated_at();


drop trigger if exists chapter_revenue_rules_updated_at
on public.chapter_revenue_rules;

create trigger chapter_revenue_rules_updated_at
before update on public.chapter_revenue_rules
for each row
execute function public.set_updated_at();


-- ------------------------------------------------------------
-- 15. Indexes
-- ------------------------------------------------------------

create index if not exists platform_pricing_active_idx
on public.platform_pricing(is_active);

create index if not exists chapter_revenue_rules_active_idx
on public.chapter_revenue_rules(is_active);


-- ------------------------------------------------------------
-- END BATCH 13
-- ============================================================-- ============================================================
-- BREETHUB BATCH 14
-- STORY / CHAPTER INVESTMENT SYSTEM
-- ============================================================

-- ------------------------------------------------------------
-- 1. Investment status
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'investment_status'
  ) then
    create type public.investment_status as enum (
      'draft',
      'pending_payment',
      'payment_pending_review',
      'active',
      'completed',
      'cancelled',
      'rejected',
      'suspended'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 2. Investment payment arrangement
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'investment_payment_mode'
  ) then
    create type public.investment_payment_mode as enum (
      'reading_already_paid',
      'reading_and_investment_together'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 3. Investment eligibility / configuration
-- ------------------------------------------------------------

create table if not exists public.investment_settings (
  id uuid primary key default gen_random_uuid(),

  name text not null,
  description text,

  is_enabled boolean not null default false,

  minimum_amount_ngn numeric(14,2),
  minimum_amount_usd numeric(14,2),
  minimum_amount_gbp numeric(14,2),
  minimum_amount_eur numeric(14,2),

  maximum_amount_ngn numeric(14,2),
  maximum_amount_usd numeric(14,2),
  maximum_amount_gbp numeric(14,2),
  maximum_amount_eur numeric(14,2),

  return_rate numeric(8,4),

  return_period_days integer,

  risk_disclosure text,

  legal_review_required boolean not null default true,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 4. Story / chapter investment eligibility
-- ------------------------------------------------------------

create table if not exists public.investment_offerings (
  id uuid primary key default gen_random_uuid(),

  story_id uuid not null
    references public.stories(id)
    on delete cascade,

  chapter_id uuid
    references public.chapters(id)
    on delete cascade,

  investment_settings_id uuid
    references public.investment_settings(id)
    on delete set null,

  is_enabled boolean not null default false,

  minimum_amount numeric(14,2),
  maximum_amount numeric(14,2),

  currency_code text not null default 'NGN',

  stated_return_rate numeric(8,4),

  return_period_days integer,

  terms text,

  risk_disclosure text,

  legal_review_status text not null default 'pending',

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint investment_offering_amount_check
    check (
      minimum_amount is null
      or minimum_amount >= 0
    ),

  constraint investment_offering_max_check
    check (
      maximum_amount is null
      or maximum_amount >= 0
    )
);


-- ------------------------------------------------------------
-- 5. Investments
-- ------------------------------------------------------------

create table if not exists public.investments (
  id uuid primary key default gen_random_uuid(),

  investor_id uuid not null
    references public.profiles(id)
    on delete cascade,

  offering_id uuid not null
    references public.investment_offerings(id)
    on delete restrict,

  story_id uuid not null
    references public.stories(id)
    on delete restrict,

  chapter_id uuid
    references public.chapters(id)
    on delete restrict,

  payment_mode public.investment_payment_mode not null,

  reading_payment_id uuid
    references public.payments(id)
    on delete set null,

  investment_payment_id uuid
    references public.payments(id)
    on delete set null,

  reading_fee numeric(14,2) not null default 0,

  investment_amount numeric(14,2) not null,

  currency_code text not null,

  status public.investment_status not null default 'pending_payment',

  agreed_to_terms boolean not null default false,
  agreed_at timestamptz,

  payment_verified_at timestamptz,
  activated_at timestamptz,

  expected_return_amount numeric(14,2),
  expected_return_date timestamptz,

  actual_return_amount numeric(14,2),

  completed_at timestamptz,

  rejection_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint investment_amount_positive
    check (investment_amount > 0),

  constraint reading_fee_nonnegative
    check (reading_fee >= 0)
);


-- ------------------------------------------------------------
-- 6. Investment transactions / ledger
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'investment_transaction_type'
  ) then
    create type public.investment_transaction_type as enum (
      'investment',
      'return',
      'refund',
      'fee',
      'adjustment'
    );
  end if;
end
$$;


create table if not exists public.investment_transactions (
  id uuid primary key default gen_random_uuid(),

  investment_id uuid not null
    references public.investments(id)
    on delete cascade,

  investor_id uuid not null
    references public.profiles(id)
    on delete cascade,

  transaction_type public.investment_transaction_type not null,

  amount numeric(14,2) not null,

  currency_code text not null,

  description text,

  payment_id uuid
    references public.payments(id)
    on delete set null,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),

  constraint investment_transaction_amount_check
    check (amount >= 0)
);


-- ------------------------------------------------------------
-- 7. Investment terms acceptance
-- ------------------------------------------------------------

create table if not exists public.investment_terms_acceptances (
  id uuid primary key default gen_random_uuid(),

  investment_id uuid not null
    references public.investments(id)
    on delete cascade,

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  terms_version text not null,

  accepted_at timestamptz not null default now(),

  ip_hash text,
  user_agent text
);


-- ------------------------------------------------------------
-- 8. Investment status history
-- ------------------------------------------------------------

create table if not exists public.investment_status_history (
  id uuid primary key default gen_random_uuid(),

  investment_id uuid not null
    references public.investments(id)
    on delete cascade,

  old_status public.investment_status,
  new_status public.investment_status not null,

  changed_by uuid
    references public.profiles(id)
    on delete set null,

  reason text,

  created_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 9. Investor dashboard view
-- ------------------------------------------------------------

create or replace view public.investor_portfolio_summary
with (security_invoker = true)
as
select
  i.investor_id,
  i.id as investment_id,
  i.story_id,
  i.chapter_id,
  s.title as story_title,
  c.title as chapter_title,
  i.investment_amount,
  i.currency_code,
  i.status,
  i.expected_return_amount,
  i.expected_return_date,
  i.actual_return_amount,
  i.created_at,
  i.activated_at,
  i.completed_at
from public.investments i
join public.stories s
  on s.id = i.story_id
left join public.chapters c
  on c.id = i.chapter_id;


-- ------------------------------------------------------------
-- 10. Check that reading access exists
-- ------------------------------------------------------------

create or replace function public.investor_has_required_reading_access(
  p_user_id uuid,
  p_story_id uuid,
  p_chapter_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_access boolean;
begin

  if p_chapter_id is null then

    select exists (
      select 1
      from public.stories s
      where s.id = p_story_id
        and (
          s.reading_price is null
          or s.reading_price = 0
        )
    )
    into v_has_access;

    return v_has_access;
  end if;


  select public.user_can_read_chapter(
    p_user_id,
    p_chapter_id
  )
  into v_has_access;

  return coalesce(v_has_access, false);
end;
$$;


-- ------------------------------------------------------------
-- 11. Create an investment after reading is already paid
-- ------------------------------------------------------------

create or replace function public.create_investment_after_reading(
  p_offering_id uuid,
  p_investment_amount numeric,
  p_currency_code text,
  p_reading_payment_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_story_id uuid;
  v_chapter_id uuid;
  v_has_access boolean;
  v_agreed boolean;
  v_investment_id uuid;
begin

  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select
    story_id,
    chapter_id
  into
    v_story_id,
    v_chapter_id
  from public.investment_offerings
  where id = p_offering_id
    and is_enabled = true
    and legal_review_status = 'approved';

  if v_story_id is null then
    raise exception 'Investment offering is not available';
  end if;

  v_has_access := public.investor_has_required_reading_access(
    v_user_id,
    v_story_id,
    v_chapter_id
  );

  if not v_has_access then
    raise exception 'Reading access is required before investing';
  end if;

  select exists (
    select 1
    from public.payments
    where id = p_reading_payment_id
      and user_id = v_user_id
      and status = 'approved'
  )
  into v_agreed;

  if not v_agreed then
    raise exception 'Approved reading payment is required';
  end if;

  insert into public.investments (
    investor_id,
    offering_id,
    story_id,
    chapter_id,
    payment_mode,
    reading_payment_id,
    investment_amount,
    currency_code,
    status
  )
  values (
    v_user_id,
    p_offering_id,
    v_story_id,
    v_chapter_id,
    'reading_already_paid',
    p_reading_payment_id,
    p_investment_amount,
    p_currency_code,
    'pending_payment'
  )
  returning id into v_investment_id;

  return v_investment_id;
end;
$$;


-- ------------------------------------------------------------
-- 12. Create investment where reading + investment are paid
-- together
-- ------------------------------------------------------------

create or replace function public.create_investment_with_reading(
  p_offering_id uuid,
  p_reading_fee numeric,
  p_investment_amount numeric,
  p_currency_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_story_id uuid;
  v_chapter_id uuid;
  v_investment_id uuid;
begin

  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select
    story_id,
    chapter_id
  into
    v_story_id,
    v_chapter_id
  from public.investment_offerings
  where id = p_offering_id
    and is_enabled = true
    and legal_review_status = 'approved';

  if v_story_id is null then
    raise exception 'Investment offering is not available';
  end if;

  insert into public.investments (
    investor_id,
    offering_id,
    story_id,
    chapter_id,
    payment_mode,
    reading_fee,
    investment_amount,
    currency_code,
    status
  )
  values (
    v_user_id,
    p_offering_id,
    v_story_id,
    v_chapter_id,
    'reading_and_investment_together',
    p_reading_fee,
    p_investment_amount,
    p_currency_code,
    'pending_payment'
  )
  returning id into v_investment_id;

  return v_investment_id;
end;
$$;


-- ------------------------------------------------------------
-- 13. Admin investment status update
-- ------------------------------------------------------------

create or replace function public.admin_update_investment_status(
  p_investment_id uuid,
  p_new_status public.investment_status,
  p_reason text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status public.investment_status;
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  select status
  into v_old_status
  from public.investments
  where id = p_investment_id
  for update;

  if v_old_status is null then
    raise exception 'Investment not found';
  end if;

  update public.investments
  set
    status = p_new_status,
    rejection_reason =
      case
        when p_new_status = 'rejected'
        then p_reason
        else rejection_reason
      end,
    activated_at =
      case
        when p_new_status = 'active'
        then coalesce(activated_at, now())
        else activated_at
      end,
    completed_at =
      case
        when p_new_status = 'completed'
        then coalesce(completed_at, now())
        else completed_at
      end,
    updated_at = now()
  where id = p_investment_id;

  insert into public.investment_status_history (
    investment_id,
    old_status,
    new_status,
    changed_by,
    reason
  )
  values (
    p_investment_id,
    v_old_status,
    p_new_status,
    auth.uid(),
    p_reason
  );

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 14. Updated-at triggers
-- ------------------------------------------------------------

drop trigger if exists investment_settings_updated_at
on public.investment_settings;

create trigger investment_settings_updated_at
before update on public.investment_settings
for each row
execute function public.set_updated_at();


drop trigger if exists investment_offerings_updated_at
on public.investment_offerings;

create trigger investment_offerings_updated_at
before update on public.investment_offerings
for each row
execute function public.set_updated_at();


drop trigger if exists investments_updated_at
on public.investments;

create trigger investments_updated_at
before update on public.investments
for each row
execute function public.set_updated_at();


-- ------------------------------------------------------------
-- 15. Row Level Security
-- ------------------------------------------------------------

alter table public.investment_settings enable row level security;
alter table public.investment_offerings enable row level security;
alter table public.investments enable row level security;
alter table public.investment_transactions enable row level security;
alter table public.investment_terms_acceptances enable row level security;
alter table public.investment_status_history enable row level security;


-- Investment settings
drop policy if exists "Admins manage investment settings"
on public.investment_settings;

create policy "Admins manage investment settings"
on public.investment_settings
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- Investment offerings
drop policy if exists "Users view approved investment offerings"
on public.investment_offerings;

create policy "Users view approved investment offerings"
on public.investment_offerings
for select
to authenticated
using (
  is_enabled = true
  and legal_review_status = 'approved'
);


drop policy if exists "Admins manage investment offerings"
on public.investment_offerings;

create policy "Admins manage investment offerings"
on public.investment_offerings
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- Investments
drop policy if exists "Users view own investments"
on public.investments;

create policy "Users view own investments"
on public.investments
for select
to authenticated
using (
  investor_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Admins manage investments"
on public.investments;

create policy "Admins manage investments"
on public.investments
for update
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- Investment transactions
drop policy if exists "Users view own investment transactions"
on public.investment_transactions;

create policy "Users view own investment transactions"
on public.investment_transactions
for select
to authenticated
using (
  investor_id = auth.uid()
  or public.is_admin()
);


-- Terms acceptance
drop policy if exists "Users manage own investment term acceptance"
on public.investment_terms_acceptances;

create policy "Users manage own investment term acceptance"
on public.investment_terms_acceptances
for insert
to authenticated
with check (
  user_id = auth.uid()
);


create policy "Users view own investment term acceptance"
on public.investment_terms_acceptances
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- Investment status history
drop policy if exists "Users view own investment status history"
on public.investment_status_history;

create policy "Users view own investment status history"
on public.investment_status_history
for select
to authenticated
using (
  exists (
    select 1
    from public.investments i
    where i.id = investment_status_history.investment_id
      and (
        i.investor_id = auth.uid()
        or public.is_admin()
      )
  )
);


-- ------------------------------------------------------------
-- 16. Indexes
-- ------------------------------------------------------------

create index if not exists investment_offerings_story_idx
on public.investment_offerings(story_id);

create index if not exists investment_offerings_chapter_idx
on public.investment_offerings(chapter_id);

create index if not exists investment_offerings_enabled_idx
on public.investment_offerings(is_enabled);

create index if not exists investments_investor_idx
on public.investments(investor_id);

create index if not exists investments_story_idx
on public.investments(story_id);

create index if not exists investments_chapter_idx
on public.investments(chapter_id);

create index if not exists investments_status_idx
on public.investments(status);

create index if not exists investment_transactions_investment_idx
on public.investment_transactions(investment_id);

create index if not exists investment_terms_user_idx
on public.investment_terms_acceptances(user_id);

create index if not exists investment_status_history_investment_idx
on public.investment_status_history(investment_id);


-- ------------------------------------------------------------
-- 17. Do NOT activate investment automatically
-- ------------------------------------------------------------

insert into public.investment_settings (
  name,
  description,
  is_enabled,
  legal_review_required
)
values (
  'Breethub Story Investment',
  'Investment configuration for eligible Breethub stories and chapters.',
  false,
  true
)
on conflict do nothing;


-- ------------------------------------------------------------
-- END BATCH 14
-- ============================================================-- ============================================================
-- BREETHUB BATCH 15
-- WALLETS, EARNINGS & WITHDRAWALS
-- ============================================================

-- ------------------------------------------------------------
-- 1. Wallet type
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'wallet_type'
  ) then
    create type public.wallet_type as enum (
      'creator',
      'affiliate',
      'investor',
      'advertiser',
      'platform'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 2. Wallet transaction type
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'wallet_transaction_type'
  ) then
    create type public.wallet_transaction_type as enum (
      'earning',
      'commission',
      'gift',
      'reward',
      'investment_return',
      'refund',
      'withdrawal',
      'withdrawal_reversal',
      'purchase',
      'fee',
      'adjustment'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 3. Wallet transaction status
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'wallet_transaction_status'
  ) then
    create type public.wallet_transaction_status as enum (
      'pending',
      'available',
      'processing',
      'completed',
      'reversed',
      'cancelled'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 4. Wallets
-- ------------------------------------------------------------

create table if not exists public.wallets (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  wallet_type public.wallet_type not null,

  currency_code text not null,

  available_balance numeric(18,2) not null default 0,
  pending_balance numeric(18,2) not null default 0,
  withdrawn_balance numeric(18,2) not null default 0,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint wallet_balances_nonnegative
    check (
      available_balance >= 0
      and pending_balance >= 0
      and withdrawn_balance >= 0
    ),

  unique(user_id, wallet_type, currency_code)
);


-- ------------------------------------------------------------
-- 5. Wallet transactions
-- ------------------------------------------------------------

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),

  wallet_id uuid not null
    references public.wallets(id)
    on delete cascade,

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  transaction_type public.wallet_transaction_type not null,

  status public.wallet_transaction_status not null default 'pending',

  amount numeric(18,2) not null,

  currency_code text not null,

  description text,

  reference text unique,

  payment_id uuid
    references public.payments(id)
    on delete set null,

  investment_id uuid
    references public.investments(id)
    on delete set null,

  chapter_purchase_id uuid
    references public.chapter_purchases(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint wallet_transaction_amount_positive
    check (amount > 0)
);


-- ------------------------------------------------------------
-- 6. Bank / payout accounts
-- ------------------------------------------------------------

create table if not exists public.payout_accounts (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  country text not null,
  currency_code text not null,

  account_name text not null,
  bank_name text not null,

  account_number text,

  routing_number text,
  sort_code text,
  iban text,
  swift_code text,

  mobile_money_number text,

  is_default boolean not null default false,
  is_verified boolean not null default false,
  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 7. Withdrawal status
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'withdrawal_status'
  ) then
    create type public.withdrawal_status as enum (
      'requested',
      'pending_review',
      'approved',
      'processing',
      'paid',
      'rejected',
      'cancelled',
      'failed'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 8. Withdrawals
-- ------------------------------------------------------------

create table if not exists public.withdrawals (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  wallet_id uuid not null
    references public.wallets(id)
    on delete restrict,

  payout_account_id uuid not null
    references public.payout_accounts(id)
    on delete restrict,

  amount numeric(18,2) not null,

  currency_code text not null,

  fee numeric(18,2) not null default 0,

  net_amount numeric(18,2) not null,

  status public.withdrawal_status not null default 'requested',

  requested_at timestamptz not null default now(),

  reviewed_at timestamptz,
  reviewed_by uuid
    references public.profiles(id)
    on delete set null,

  processed_at timestamptz,
  paid_at timestamptz,

  rejection_reason text,
  failure_reason text,

  provider text,
  provider_reference text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint withdrawal_amount_positive
    check (amount > 0),

  constraint withdrawal_fee_nonnegative
    check (fee >= 0),

  constraint withdrawal_net_nonnegative
    check (net_amount >= 0)
);


-- ------------------------------------------------------------
-- 9. Withdrawal schedule
-- ------------------------------------------------------------

create table if not exists public.withdrawal_settings (
  id uuid primary key default gen_random_uuid(),

  role public.app_role not null,

  minimum_withdrawal numeric(18,2) not null default 0,

  withdrawal_interval_days integer not null default 14,

  is_enabled boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(role)
);


-- ------------------------------------------------------------
-- 10. Check whether user can request withdrawal
-- ------------------------------------------------------------

create or replace function public.can_request_withdrawal(
  p_user_id uuid,
  p_wallet_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_available numeric;
  v_role public.app_role;
  v_minimum numeric;
  v_interval integer;
  v_last_withdrawal timestamptz;
begin

  if auth.uid() <> p_user_id
     and not public.is_admin() then
    return false;
  end if;

  select
    available_balance,
    wallet_type
  into
    v_available,
    v_role
  from public.wallets
  where id = p_wallet_id
    and user_id = p_user_id
    and is_active = true;

  if v_available is null then
    return false;
  end if;

  select role
  into v_role
  from public.profiles
  where id = p_user_id;

  select
    minimum_withdrawal,
    withdrawal_interval_days
  into
    v_minimum,
    v_interval
  from public.withdrawal_settings
  where role = v_role
    and is_enabled = true;

  if v_minimum is null then
    v_minimum := 0;
  end if;

  if v_interval is null then
    v_interval := 14;
  end if;

  if v_available < v_minimum then
    return false;
  end if;

  select max(requested_at)
  into v_last_withdrawal
  from public.withdrawals
  where user_id = p_user_id
    and status not in ('rejected', 'cancelled', 'failed');

  if v_last_withdrawal is not null
     and v_last_withdrawal >
         now() - make_interval(days => v_interval) then
    return false;
  end if;

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 11. Request withdrawal securely
-- ------------------------------------------------------------

create or replace function public.request_withdrawal(
  p_wallet_id uuid,
  p_payout_account_id uuid,
  p_amount numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_currency text;
  v_available numeric;
  v_net numeric;
  v_fee numeric := 0;
  v_withdrawal_id uuid;
begin

  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_amount <= 0 then
    raise exception 'Withdrawal amount must be greater than zero';
  end if;

  select
    currency_code,
    available_balance
  into
    v_currency,
    v_available
  from public.wallets
  where id = p_wallet_id
    and user_id = v_user_id
    and is_active = true
  for update;

  if v_available is null then
    raise exception 'Wallet not found';
  end if;

  if v_available < p_amount then
    raise exception 'Insufficient available balance';
  end if;

  if not public.can_request_withdrawal(
    v_user_id,
    p_wallet_id
  ) then
    raise exception 'Withdrawal is not currently available';
  end if;

  if not exists (
    select 1
    from public.payout_accounts
    where id = p_payout_account_id
      and user_id = v_user_id
      and is_active = true
      and is_verified = true
  ) then
    raise exception 'Verified payout account required';
  end if;

  v_net := p_amount - v_fee;

  update public.wallets
  set
    available_balance = available_balance - p_amount,
    pending_balance = pending_balance + p_amount,
    updated_at = now()
  where id = p_wallet_id;

  insert into public.withdrawals (
    user_id,
    wallet_id,
    payout_account_id,
    amount,
    currency_code,
    fee,
    net_amount,
    status
  )
  values (
    v_user_id,
    p_wallet_id,
    p_payout_account_id,
    p_amount,
    v_currency,
    v_fee,
    v_net,
    'requested'
  )
  returning id into v_withdrawal_id;

  return v_withdrawal_id;
end;
$$;


-- ------------------------------------------------------------
-- 12. Admin / Accountant withdrawal decision
-- ------------------------------------------------------------

create or replace function public.review_withdrawal(
  p_withdrawal_id uuid,
  p_status public.withdrawal_status,
  p_reason text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet_id uuid;
  v_amount numeric;
  v_old_status public.withdrawal_status;
begin

  if not (
    public.is_admin()
    or public.has_staff_permission(
      'view_financials'::public.staff_permission
    )
  ) then
    raise exception 'Financial permission required';
  end if;

  select
    wallet_id,
    amount,
    status
  into
    v_wallet_id,
    v_amount,
    v_old_status
  from public.withdrawals
  where id = p_withdrawal_id
  for update;

  if v_wallet_id is null then
    raise exception 'Withdrawal not found';
  end if;

  if v_old_status in ('paid', 'cancelled') then
    raise exception 'Withdrawal can no longer be changed';
  end if;

  update public.withdrawals
  set
    status = p_status,
    reviewed_at = now(),
    reviewed_by = auth.uid(),
    rejection_reason =
      case
        when p_status = 'rejected'
        then p_reason
        else rejection_reason
      end,
    updated_at = now()
  where id = p_withdrawal_id;

  if p_status in ('rejected', 'cancelled', 'failed') then

    update public.wallets
    set
      pending_balance = greatest(
        pending_balance - v_amount,
        0
      ),
      available_balance =
        available_balance + v_amount,
      updated_at = now()
    where id = v_wallet_id;

  end if;

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 13. Mark withdrawal as paid
-- ------------------------------------------------------------

create or replace function public.mark_withdrawal_paid(
  p_withdrawal_id uuid,
  p_provider_reference text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet_id uuid;
  v_amount numeric;
  v_status public.withdrawal_status;
begin

  if not (
    public.is_admin()
    or public.has_staff_permission(
      'view_financials'::public.staff_permission
    )
  ) then
    raise exception 'Financial permission required';
  end if;

  select
    wallet_id,
    amount,
    status
  into
    v_wallet_id,
    v_amount,
    v_status
  from public.withdrawals
  where id = p_withdrawal_id
  for update;

  if v_wallet_id is null then
    raise exception 'Withdrawal not found';
  end if;

  if v_status not in ('approved', 'processing') then
    raise exception 'Withdrawal is not ready to be marked paid';
  end if;

  update public.withdrawals
  set
    status = 'paid',
    paid_at = now(),
    processed_at = now(),
    provider_reference = p_provider_reference,
    updated_at = now()
  where id = p_withdrawal_id;

  update public.wallets
  set
    pending_balance = greatest(
      pending_balance - v_amount,
      0
    ),
    withdrawn_balance =
      withdrawn_balance + v_amount,
    updated_at = now()
  where id = v_wallet_id;

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 14. RLS
-- ------------------------------------------------------------

alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.payout_accounts enable row level security;
alter table public.withdrawals enable row level security;
alter table public.withdrawal_settings enable row level security;


drop policy if exists "Users view own wallets"
on public.wallets;

create policy "Users view own wallets"
on public.wallets
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Users view own wallet transactions"
on public.wallet_transactions;

create policy "Users view own wallet transactions"
on public.wallet_transactions
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Users manage own payout accounts"
on public.payout_accounts;

create policy "Users manage own payout accounts"
on public.payout_accounts
for all
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
)
with check (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Users view own withdrawals"
on public.withdrawals;

create policy "Users view own withdrawals"
on public.withdrawals
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Financial staff view withdrawals"
on public.withdrawals;

create policy "Financial staff view withdrawals"
on public.withdrawals
for select
to authenticated
using (
  public.is_admin()
  or public.has_staff_permission(
    'view_financials'::public.staff_permission
  )
);


drop policy if exists "Admins manage withdrawal settings"
on public.withdrawal_settings;

create policy "Admins manage withdrawal settings"
on public.withdrawal_settings
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ------------------------------------------------------------
-- 15. Default withdrawal settings
-- ------------------------------------------------------------

insert into public.withdrawal_settings (
  role,
  minimum_withdrawal,
  withdrawal_interval_days,
  is_enabled
)
values
  ('writer', 0, 14, true),
  ('affiliate', 0, 14, true)
on conflict (role)
do nothing;


-- ------------------------------------------------------------
-- 16. Updated-at triggers
-- ------------------------------------------------------------

drop trigger if exists wallets_updated_at
on public.wallets;

create trigger wallets_updated_at
before update on public.wallets
for each row
execute function public.set_updated_at();


drop trigger if exists wallet_transactions_updated_at
on public.wallet_transactions;

create trigger wallet_transactions_updated_at
before update on public.wallet_transactions
for each row
execute function public.set_updated_at();


drop trigger if exists payout_accounts_updated_at
on public.payout_accounts;

create trigger payout_accounts_updated_at
before update on public.payout_accounts
for each row
execute function public.set_updated_at();


drop trigger if exists withdrawals_updated_at
on public.withdrawals;

create trigger withdrawals_updated_at
before update on public.withdrawals
for each row
execute function public.set_updated_at();


drop trigger if exists withdrawal_settings_updated_at
on public.withdrawal_settings;

create trigger withdrawal_settings_updated_at
before update on public.withdrawal_settings
for each row
execute function public.set_updated_at();


-- ------------------------------------------------------------
-- 17. Indexes
-- ------------------------------------------------------------

create index if not exists wallets_user_idx
on public.wallets(user_id);

create index if not exists wallets_currency_idx
on public.wallets(currency_code);

create index if not exists wallet_transactions_user_idx
on public.wallet_transactions(user_id);

create index if not exists wallet_transactions_wallet_idx
on public.wallet_transactions(wallet_id);

create index if not exists wallet_transactions_status_idx
on public.wallet_transactions(status);

create index if not exists payout_accounts_user_idx
on public.payout_accounts(user_id);

create index if not exists withdrawals_user_idx
on public.withdrawals(user_id);

create index if not exists withdrawals_status_idx
on public.withdrawals(status);


-- ------------------------------------------------------------
-- END BATCH 15
-- ============================================================-- ============================================================
-- BREETHUB BATCH 16
-- ADVERTISER SYSTEM
-- ============================================================

-- ------------------------------------------------------------
-- 1. Advertising package status
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'advertising_package_status'
  ) then
    create type public.advertising_package_status as enum (
      'draft',
      'active',
      'paused',
      'archived'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 2. Advertising campaign status
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'advertising_campaign_status'
  ) then
    create type public.advertising_campaign_status as enum (
      'draft',
      'payment_pending',
      'under_review',
      'active',
      'paused',
      'rejected',
      'completed',
      'cancelled'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 3. Advertising objective
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'advertising_objective'
  ) then
    create type public.advertising_objective as enum (
      'brand_awareness',
      'website_visits',
      'product_sales',
      'course_sales',
      'story_discovery',
      'creator_discovery',
      'app_downloads',
      'other'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 4. Advertising packages
-- ------------------------------------------------------------

create table if not exists public.advertising_packages (
  id uuid primary key default gen_random_uuid(),

  name text not null,
  slug text not null unique,

  description text,

  status public.advertising_package_status not null default 'draft',

  price_ngn numeric(18,2),
  price_usd numeric(18,2),
  price_gbp numeric(18,2),
  price_eur numeric(18,2),

  duration_days integer,

  included_impressions bigint,
  included_clicks bigint,

  is_featured boolean not null default false,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  updated_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 5. Campaigns
-- ------------------------------------------------------------

create table if not exists public.advertising_campaigns (
  id uuid primary key default gen_random_uuid(),

  advertiser_id uuid not null
    references public.profiles(id)
    on delete cascade,

  package_id uuid
    references public.advertising_packages(id)
    on delete set null,

  name text not null,

  objective public.advertising_objective not null,

  status public.advertising_campaign_status not null default 'draft',

  headline text,
  description text,

  call_to_action text,
  destination_url text,

  media_url text,
  logo_url text,

  budget_amount numeric(18,2),
  budget_currency text,

  daily_budget numeric(18,2),

  start_at timestamptz,
  end_at timestamptz,

  target_country text,
  target_language text,
  target_category text,

  target_age_min integer,
  target_age_max integer,

  target_gender text,

  payment_id uuid
    references public.payments(id)
    on delete set null,

  payment_verified_at timestamptz,

  reviewed_at timestamptz,
  reviewed_by uuid
    references public.profiles(id)
    on delete set null,

  rejection_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint campaign_budget_nonnegative
    check (
      budget_amount is null
      or budget_amount >= 0
    ),

  constraint campaign_daily_budget_nonnegative
    check (
      daily_budget is null
      or daily_budget >= 0
    )
);


-- ------------------------------------------------------------
-- 6. Campaign analytics
-- ------------------------------------------------------------

create table if not exists public.advertising_campaign_daily_stats (
  id uuid primary key default gen_random_uuid(),

  campaign_id uuid not null
    references public.advertising_campaigns(id)
    on delete cascade,

  stat_date date not null,

  impressions bigint not null default 0,
  clicks bigint not null default 0,

  spend numeric(18,2) not null default 0,

  conversions bigint not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(campaign_id, stat_date),

  constraint ad_stats_nonnegative
    check (
      impressions >= 0
      and clicks >= 0
      and spend >= 0
      and conversions >= 0
    )
);


-- ------------------------------------------------------------
-- 7. Individual ad events
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'advertising_event_type'
  ) then
    create type public.advertising_event_type as enum (
      'impression',
      'click',
      'conversion'
    );
  end if;
end
$$;


create table if not exists public.advertising_events (
  id uuid primary key default gen_random_uuid(),

  campaign_id uuid not null
    references public.advertising_campaigns(id)
    on delete cascade,

  event_type public.advertising_event_type not null,

  user_id uuid
    references public.profiles(id)
    on delete set null,

  session_id text,

  created_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 8. Advertiser campaign payment review
-- ------------------------------------------------------------

create table if not exists public.advertising_payment_reviews (
  id uuid primary key default gen_random_uuid(),

  campaign_id uuid not null
    references public.advertising_campaigns(id)
    on delete cascade,

  payment_id uuid not null
    references public.payments(id)
    on delete cascade,

  status text not null default 'pending',

  reviewed_by uuid
    references public.profiles(id)
    on delete set null,

  reviewed_at timestamptz,

  rejection_reason text,

  created_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 9. Advertiser targeting options
-- ------------------------------------------------------------

create table if not exists public.advertising_targeting_options (
  id uuid primary key default gen_random_uuid(),

  option_type text not null,
  option_value text not null,

  display_name text not null,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),

  unique(option_type, option_value)
);


-- ------------------------------------------------------------
-- 10. Campaign approval helper
-- ------------------------------------------------------------

create or replace function public.can_activate_ad_campaign(
  p_campaign_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment_verified boolean;
  v_status public.advertising_campaign_status;
  v_start timestamptz;
  v_end timestamptz;
begin

  select
    (
      payment_verified_at is not null
      and payment_id is not null
    ),
    status,
    start_at,
    end_at
  into
    v_payment_verified,
    v_status,
    v_start,
    v_end
  from public.advertising_campaigns
  where id = p_campaign_id;

  if not v_payment_verified then
    return false;
  end if;

  if v_status in ('rejected', 'cancelled') then
    return false;
  end if;

  if v_start is null or v_end is null then
    return false;
  end if;

  if v_end <= v_start then
    return false;
  end if;

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 11. Admin approves campaign
-- ------------------------------------------------------------

create or replace function public.admin_approve_ad_campaign(
  p_campaign_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  if not public.can_activate_ad_campaign(p_campaign_id) then
    raise exception 'Campaign payment or campaign requirements are incomplete';
  end if;

  update public.advertising_campaigns
  set
    status = 'active',
    reviewed_at = now(),
    reviewed_by = auth.uid(),
    updated_at = now()
  where id = p_campaign_id;

  return found;
end;
$$;


-- ------------------------------------------------------------
-- 12. Admin rejects campaign
-- ------------------------------------------------------------

create or replace function public.admin_reject_ad_campaign(
  p_campaign_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  update public.advertising_campaigns
  set
    status = 'rejected',
    rejection_reason = p_reason,
    reviewed_at = now(),
    reviewed_by = auth.uid(),
    updated_at = now()
  where id = p_campaign_id;

  return found;
end;
$$;


-- ------------------------------------------------------------
-- 13. Advertiser can view own campaigns
-- ------------------------------------------------------------

alter table public.advertising_packages enable row level security;
alter table public.advertising_campaigns enable row level security;
alter table public.advertising_campaign_daily_stats enable row level security;
alter table public.advertising_events enable row level security;
alter table public.advertising_payment_reviews enable row level security;
alter table public.advertising_targeting_options enable row level security;


drop policy if exists "Users view active advertising packages"
on public.advertising_packages;

create policy "Users view active advertising packages"
on public.advertising_packages
for select
to authenticated
using (
  status = 'active'
);


drop policy if exists "Admins manage advertising packages"
on public.advertising_packages;

create policy "Admins manage advertising packages"
on public.advertising_packages
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Advertisers manage own campaigns"
on public.advertising_campaigns;

create policy "Advertisers manage own campaigns"
on public.advertising_campaigns
for all
to authenticated
using (
  advertiser_id = auth.uid()
  or public.is_admin()
)
with check (
  advertiser_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Advertisers view own campaign stats"
on public.advertising_campaign_daily_stats;

create policy "Advertisers view own campaign stats"
on public.advertising_campaign_daily_stats
for select
to authenticated
using (
  exists (
    select 1
    from public.advertising_campaigns c
    where c.id = advertising_campaign_daily_stats.campaign_id
      and (
        c.advertiser_id = auth.uid()
        or public.is_admin()
      )
  )
);


drop policy if exists "Advertisers view own ad events"
on public.advertising_events;

create policy "Advertisers view own ad events"
on public.advertising_events
for select
to authenticated
using (
  exists (
    select 1
    from public.advertising_campaigns c
    where c.id = advertising_events.campaign_id
      and (
        c.advertiser_id = auth.uid()
        or public.is_admin()
      )
  )
);


drop policy if exists "Advertisers view own payment reviews"
on public.advertising_payment_reviews;

create policy "Advertisers view own payment reviews"
on public.advertising_payment_reviews
for select
to authenticated
using (
  exists (
    select 1
    from public.advertising_campaigns c
    where c.id = advertising_payment_reviews.campaign_id
      and (
        c.advertiser_id = auth.uid()
        or public.is_admin()
      )
  )
);


drop policy if exists "Users view active targeting options"
on public.advertising_targeting_options;

create policy "Users view active targeting options"
on public.advertising_targeting_options
for select
to authenticated
using (
  is_active = true
);


drop policy if exists "Admins manage targeting options"
on public.advertising_targeting_options;

create policy "Admins manage targeting options"
on public.advertising_targeting_options
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ------------------------------------------------------------
-- 14. Advertiser payment must be verified before activation
-- ------------------------------------------------------------

create or replace function public.verify_advertiser_payment(
  p_campaign_id uuid,
  p_payment_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not (
    public.is_admin()
    or public.has_staff_permission(
      'view_financials'::public.staff_permission
    )
  ) then
    raise exception 'Financial permission required';
  end if;

  if not exists (
    select 1
    from public.advertising_campaigns
    where id = p_campaign_id
      and payment_id = p_payment_id
  ) then
    raise exception 'Campaign/payment relationship not found';
  end if;

  if not exists (
    select 1
    from public.payments
    where id = p_payment_id
      and status = 'approved'
  ) then
    raise exception 'Payment has not been approved';
  end if;

  update public.advertising_campaigns
  set
    payment_verified_at = now(),
    status = 'under_review',
    updated_at = now()
  where id = p_campaign_id;

  update public.advertising_payment_reviews
  set
    status = 'approved',
    reviewed_by = auth.uid(),
    reviewed_at = now()
  where campaign_id = p_campaign_id
    and payment_id = p_payment_id;

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 15. Campaign analytics recording function
-- ------------------------------------------------------------

create or replace function public.record_ad_event(
  p_campaign_id uuid,
  p_event_type public.advertising_event_type,
  p_session_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
begin

  insert into public.advertising_events (
    campaign_id,
    event_type,
    user_id,
    session_id
  )
  values (
    p_campaign_id,
    p_event_type,
    auth.uid(),
    p_session_id
  )
  returning id into v_event_id;

  return v_event_id;
end;
$$;


-- ------------------------------------------------------------
-- 16. Updated-at triggers
-- ------------------------------------------------------------

drop trigger if exists advertising_packages_updated_at
on public.advertising_packages;

create trigger advertising_packages_updated_at
before update on public.advertising_packages
for each row
execute function public.set_updated_at();


drop trigger if exists advertising_campaigns_updated_at
on public.advertising_campaigns;

create trigger advertising_campaigns_updated_at
before update on public.advertising_campaigns
for each row
execute function public.set_updated_at();


drop trigger if exists advertising_campaign_daily_stats_updated_at
on public.advertising_campaign_daily_stats;

create trigger advertising_campaign_daily_stats_updated_at
before update on public.advertising_campaign_daily_stats
for each row
execute function public.set_updated_at();


-- ------------------------------------------------------------
-- 17. Indexes
-- ------------------------------------------------------------

create index if not exists advertising_packages_status_idx
on public.advertising_packages(status);

create index if not exists advertising_campaigns_advertiser_idx
on public.advertising_campaigns(advertiser_id);

create index if not exists advertising_campaigns_status_idx
on public.advertising_campaigns(status);

create index if not exists advertising_campaigns_dates_idx
on public.advertising_campaigns(start_at, end_at);

create index if not exists advertising_stats_campaign_idx
on public.advertising_campaign_daily_stats(campaign_id);

create index if not exists advertising_stats_date_idx
on public.advertising_campaign_daily_stats(stat_date);

create index if not exists advertising_events_campaign_idx
on public.advertising_events(campaign_id);

create index if not exists advertising_events_type_idx
on public.advertising_events(event_type);


-- ------------------------------------------------------------
-- 18. No fake advertising packages are inserted.
-- Admin will create real packages later.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- END BATCH 16
-- ============================================================-- ============================================================
-- BREETHUB BATCH 17
-- ADMIN CONTROL, STAFF MANAGEMENT & PLATFORM SETTINGS
-- ============================================================

-- ------------------------------------------------------------
-- 1. Staff account status
-- ------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_type where typname = 'staff_account_status'
  ) then
    create type public.staff_account_status as enum (
      'active',
      'suspended',
      'inactive'
    );
  end if;
end
$$;


-- ------------------------------------------------------------
-- 2. Staff members
-- ------------------------------------------------------------

create table if not exists public.staff_members (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null unique
    references public.profiles(id)
    on delete cascade,

  staff_role public.app_role not null,

  display_name text,

  job_title text,

  status public.staff_account_status not null default 'active',

  can_manage_users boolean not null default false,
  can_manage_content boolean not null default false,
  can_manage_courses boolean not null default false,
  can_manage_payments boolean not null default false,
  can_manage_withdrawals boolean not null default false,
  can_manage_investments boolean not null default false,
  can_manage_advertising boolean not null default false,
  can_manage_messages boolean not null default false,
  can_view_reports boolean not null default false,

  created_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 3. Platform settings
-- ------------------------------------------------------------

create table if not exists public.platform_settings (
  id uuid primary key default gen_random_uuid(),

  setting_key text not null unique,

  setting_value text,

  setting_type text not null default 'text',

  description text,

  is_public boolean not null default false,

  updated_by uuid
    references public.profiles(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 4. Admin activity log
-- ------------------------------------------------------------

create table if not exists public.admin_activity_logs (
  id uuid primary key default gen_random_uuid(),

  admin_id uuid
    references public.profiles(id)
    on delete set null,

  action text not null,

  target_type text,

  target_id uuid,

  description text,

  metadata jsonb,

  created_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 5. Secure staff management
-- ------------------------------------------------------------

create or replace function public.admin_add_staff(
  p_user_id uuid,
  p_staff_role public.app_role,
  p_display_name text,
  p_job_title text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id uuid;
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  if p_staff_role not in (
    'management',
    'secretary',
    'accountant',
    'customer_care'
  ) then
    raise exception 'Invalid staff role';
  end if;

  update public.profiles
  set
    role = p_staff_role,
    updated_at = now()
  where id = p_user_id;

  insert into public.staff_members (
    user_id,
    staff_role,
    display_name,
    job_title,
    created_by
  )
  values (
    p_user_id,
    p_staff_role,
    p_display_name,
    p_job_title,
    auth.uid()
  )
  on conflict (user_id)
  do update set
    staff_role = excluded.staff_role,
    display_name = excluded.display_name,
    job_title = excluded.job_title,
    status = 'active',
    updated_at = now()
  returning id into v_staff_id;

  insert into public.admin_activity_logs (
    admin_id,
    action,
    target_type,
    target_id,
    description
  )
  values (
    auth.uid(),
    'staff_added',
    'staff',
    v_staff_id,
    'Staff member added by administrator'
  );

  return v_staff_id;
end;
$$;


-- ------------------------------------------------------------
-- 6. Suspend staff
-- ------------------------------------------------------------

create or replace function public.admin_set_staff_status(
  p_staff_id uuid,
  p_status public.staff_account_status
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  update public.staff_members
  set
    status = p_status,
    updated_at = now()
  where id = p_staff_id;

  insert into public.admin_activity_logs (
    admin_id,
    action,
    target_type,
    target_id,
    description
  )
  values (
    auth.uid(),
    'staff_status_changed',
    'staff',
    p_staff_id,
    'Staff status changed'
  );

  return found;
end;
$$;


-- ------------------------------------------------------------
-- 7. Grant staff permission
-- ------------------------------------------------------------

create or replace function public.admin_grant_staff_permission(
  p_user_id uuid,
  p_permission public.staff_permission
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  insert into public.staff_permissions (
    user_id,
    permission,
    granted_by
  )
  values (
    p_user_id,
    p_permission,
    auth.uid()
  )
  on conflict (user_id, permission)
  do update set
    granted_by = auth.uid();

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 8. Revoke staff permission
-- ------------------------------------------------------------

create or replace function public.admin_revoke_staff_permission(
  p_user_id uuid,
  p_permission public.staff_permission
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  delete from public.staff_permissions
  where user_id = p_user_id
    and permission = p_permission;

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 9. RLS
-- ------------------------------------------------------------

alter table public.staff_members enable row level security;
alter table public.platform_settings enable row level security;
alter table public.admin_activity_logs enable row level security;


drop policy if exists "Admins manage staff members"
on public.staff_members;

create policy "Admins manage staff members"
on public.staff_members
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Staff view own staff record"
on public.staff_members;

create policy "Staff view own staff record"
on public.staff_members
for select
to authenticated
using (
  user_id = auth.uid()
);


drop policy if exists "Admins manage platform settings"
on public.platform_settings;

create policy "Admins manage platform settings"
on public.platform_settings
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Users view public platform settings"
on public.platform_settings;

create policy "Users view public platform settings"
on public.platform_settings
for select
to authenticated
using (
  is_public = true
);


drop policy if exists "Admins view activity logs"
on public.admin_activity_logs;

create policy "Admins view activity logs"
on public.admin_activity_logs
for select
to authenticated
using (
  public.is_admin()
);


-- ------------------------------------------------------------
-- 10. Updated timestamps
-- ------------------------------------------------------------

drop trigger if exists staff_members_updated_at
on public.staff_members;

create trigger staff_members_updated_at
before update on public.staff_members
for each row
execute function public.set_updated_at();


drop trigger if exists platform_settings_updated_at
on public.platform_settings;

create trigger platform_settings_updated_at
before update on public.platform_settings
for each row
execute function public.set_updated_at();


-- ------------------------------------------------------------
-- 11. Indexes
-- ------------------------------------------------------------

create index if not exists staff_members_role_idx
on public.staff_members(staff_role);

create index if not exists staff_members_status_idx
on public.staff_members(status);

create index if not exists admin_activity_logs_admin_idx
on public.admin_activity_logs(admin_id);

create index if not exists admin_activity_logs_target_idx
on public.admin_activity_logs(target_type, target_id);


-- ------------------------------------------------------------
-- END BATCH 17
-- ============================================================-- ============================================================
-- BREETHUB BATCH 18
-- COURSE COMPLETION, AI TRAINING & DASHBOARD UNLOCK
-- ============================================================

-- ------------------------------------------------------------
-- 1. Course completion certificate records
-- ------------------------------------------------------------

create table if not exists public.course_certificates (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  course_id uuid not null
    references public.courses(id)
    on delete cascade,

  certificate_number text not null unique,

  issued_at timestamptz not null default now(),

  unique(user_id, course_id)
);


-- ------------------------------------------------------------
-- 2. Training milestones
-- ------------------------------------------------------------

create table if not exists public.training_milestones (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  milestone_key text not null,

  completed boolean not null default false,

  completed_at timestamptz,

  metadata jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(user_id, milestone_key)
);


-- ------------------------------------------------------------
-- 3. Determine whether a course is completed
-- ------------------------------------------------------------

create or replace function public.course_is_completed(
  p_user_id uuid,
  p_course_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
  v_completed integer;
begin

  select count(*)
  into v_total
  from public.course_lessons
  where course_id = p_course_id
    and is_published = true;

  if v_total = 0 then
    return false;
  end if;

  select count(*)
  into v_completed
  from public.course_lesson_progress clp
  join public.course_lessons cl
    on cl.id = clp.lesson_id
  where clp.user_id = p_user_id
    and cl.course_id = p_course_id
    and cl.is_published = true
    and clp.status = 'completed';

  return v_completed >= v_total;
end;
$$;


-- ------------------------------------------------------------
-- 4. Mark required course completed
-- ------------------------------------------------------------

create or replace function public.complete_required_course(
  p_user_id uuid,
  p_course_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.app_role;
  v_course_type public.course_type;
begin

  if auth.uid() <> p_user_id
     and not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  select role
  into v_role
  from public.profiles
  where id = p_user_id;

  select course_type
  into v_course_type
  from public.courses
  where id = p_course_id;

  if not public.course_is_completed(
    p_user_id,
    p_course_id
  ) then
    raise exception 'Course has not been completed';
  end if;

  update public.course_enrollments
  set
    status = 'completed',
    completed_at = now(),
    updated_at = now()
  where user_id = p_user_id
    and course_id = p_course_id
    and status = 'active';

  insert into public.course_certificates (
    user_id,
    course_id,
    certificate_number
  )
  values (
    p_user_id,
    p_course_id,
    'BH-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
  )
  on conflict (user_id, course_id)
  do nothing;

  insert into public.training_milestones (
    user_id,
    milestone_key,
    completed,
    completed_at
  )
  values (
    p_user_id,
    case
      when v_role = 'writer'
        then 'writer_required_course_completed'
      when v_role = 'affiliate'
        then 'affiliate_required_course_completed'
      else
        'required_course_completed'
    end,
    true,
    now()
  )
  on conflict (user_id, milestone_key)
  do update set
    completed = true,
    completed_at = now(),
    updated_at = now();

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 5. Record AI Bootcamp completion
-- ------------------------------------------------------------

create or replace function public.complete_ai_bootcamp(
  p_user_id uuid,
  p_course_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.app_role;
begin

  if auth.uid() <> p_user_id
     and not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  select role
  into v_role
  from public.profiles
  where id = p_user_id;

  if not public.course_is_completed(
    p_user_id,
    p_course_id
  ) then
    raise exception 'AI Bootcamp has not been completed';
  end if;

  update public.course_enrollments
  set
    status = 'completed',
    completed_at = now(),
    updated_at = now()
  where user_id = p_user_id
    and course_id = p_course_id
    and status = 'active';

  insert into public.training_milestones (
    user_id,
    milestone_key,
    completed,
    completed_at
  )
  values (
    p_user_id,
    case
      when v_role = 'writer'
        then 'writer_ai_bootcamp_completed'
      when v_role = 'affiliate'
        then 'affiliate_ai_bootcamp_completed'
      else
        'ai_bootcamp_completed'
    end,
    true,
    now()
  )
  on conflict (user_id, milestone_key)
  do update set
    completed = true,
    completed_at = now(),
    updated_at = now();

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 6. Assessment result
-- ------------------------------------------------------------

create or replace function public.assessment_passed(
  p_user_id uuid,
  p_assessment_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_score numeric;
  v_pass_score numeric;
begin

  select
    score,
    passed
  into
    v_score,
    v_passed
  from public.assessment_attempts
  where user_id = p_user_id
    and assessment_id = p_assessment_id
  order by submitted_at desc
  limit 1;

  select passing_score
  into v_pass_score
  from public.course_assessments
  where id = p_assessment_id;

  return coalesce(
    v_passed,
    false
  )
  and coalesce(
    v_score,
    0
  ) >= coalesce(
    v_pass_score,
    80
  );
end;
$$;


-- ------------------------------------------------------------
-- 7. Unlock Writer Dashboard
-- ------------------------------------------------------------

create or replace function public.try_unlock_writer_dashboard(
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_onboarding public.writer_onboarding%rowtype;
begin

  if auth.uid() <> p_user_id
     and not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  select *
  into v_onboarding
  from public.writer_onboarding
  where user_id = p_user_id
  for update;

  if not found then
    return false;
  end if;

  if not v_onboarding.ghostwriting_completed then
    return false;
  end if;

  if not v_onboarding.ai_bootcamp_completed then
    return false;
  end if;

  if not v_onboarding.assessment_passed then
    return false;
  end if;

  update public.writer_onboarding
  set
    dashboard_unlocked = true,
    updated_at = now()
  where user_id = p_user_id;

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 8. Unlock Affiliate Dashboard
-- ------------------------------------------------------------

create or replace function public.try_unlock_affiliate_dashboard(
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_onboarding public.affiliate_onboarding%rowtype;
begin

  if auth.uid() <> p_user_id
     and not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  select *
  into v_onboarding
  from public.affiliate_onboarding
  where user_id = p_user_id
  for update;

  if not found then
    return false;
  end if;

  if not v_onboarding.affiliate_course_completed then
    return false;
  end if;

  if not v_onboarding.ai_bootcamp_completed then
    return false;
  end if;

  if not v_onboarding.assessment_passed then
    return false;
  end if;

  update public.affiliate_onboarding
  set
    dashboard_unlocked = true,
    updated_at = now()
  where user_id = p_user_id;

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 9. Secure dashboard access check
-- ------------------------------------------------------------

create or replace function public.user_dashboard_unlocked(
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.app_role;
  v_unlocked boolean;
begin

  if auth.uid() <> p_user_id
     and not public.is_admin() then
    return false;
  end if;

  select role
  into v_role
  from public.profiles
  where id = p_user_id;

  if v_role = 'writer' then

    select dashboard_unlocked
    into v_unlocked
    from public.writer_onboarding
    where user_id = p_user_id;

  elsif v_role = 'affiliate' then

    select dashboard_unlocked
    into v_unlocked
    from public.affiliate_onboarding
    where user_id = p_user_id;

  else
    return true;
  end if;

  return coalesce(v_unlocked, false);
end;
$$;


-- ------------------------------------------------------------
-- 10. RLS
-- ------------------------------------------------------------

alter table public.course_certificates enable row level security;
alter table public.training_milestones enable row level security;


drop policy if exists "Users view own certificates"
on public.course_certificates;

create policy "Users view own certificates"
on public.course_certificates
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


drop policy if exists "Users view own training milestones"
on public.training_milestones;

create policy "Users view own training milestones"
on public.training_milestones
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);


-- ------------------------------------------------------------
-- 11. Updated-at trigger
-- ------------------------------------------------------------

drop trigger if exists training_milestones_updated_at
on public.training_milestones;

create trigger training_milestones_updated_at
before update on public.training_milestones
for each row
execute function public.set_updated_at();


-- ------------------------------------------------------------
-- 12. Indexes
-- ------------------------------------------------------------

create index if not exists course_certificates_user_idx
on public.course_certificates(user_id);

create index if not exists training_milestones_user_idx
on public.training_milestones(user_id);

create index if not exists training_milestones_key_idx
on public.training_milestones(milestone_key);


-- ------------------------------------------------------------
-- END BATCH 18
-- ============================================================-- ============================================================
-- BREETHUB BATCH 19
-- CURRENCY, FX RATES & INTERNATIONAL PRICING
-- ============================================================

-- ------------------------------------------------------------
-- 1. Currency configuration
-- ------------------------------------------------------------

create table if not exists public.currency_settings (
  id uuid primary key default gen_random_uuid(),

  currency_code text not null unique,

  currency_name text not null,

  symbol text,

  is_active boolean not null default true,

  is_primary boolean not null default false,

  direct_payment_enabled boolean not null default false,

  conversion_source text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ------------------------------------------------------------
-- 2. FX rates
-- ------------------------------------------------------------

create table if not exists public.fx_rates (
  id uuid primary key default gen_random_uuid(),

  base_currency text not null,

  quote_currency text not null,

  rate numeric(20,10) not null,

  source text,

  effective_at timestamptz not null default now(),

  expires_at timestamptz,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),

  unique(
    base_currency,
    quote_currency,
    effective_at
  ),

  constraint fx_rate_positive
    check (rate > 0)
);


-- ------------------------------------------------------------
-- 3. Currency conversion function
-- ------------------------------------------------------------

create or replace function public.convert_currency(
  p_amount numeric,
  p_base_currency text,
  p_quote_currency text
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate numeric;
begin

  if p_base_currency = p_quote_currency then
    return round(p_amount, 2);
  end if;

  select rate
  into v_rate
  from public.fx_rates
  where base_currency = p_base_currency
    and quote_currency = p_quote_currency
    and is_active = true
    and effective_at <= now()
    and (
      expires_at is null
      or expires_at > now()
    )
  order by effective_at desc
  limit 1;

  if v_rate is null then
    raise exception
      'No active FX rate available for % to %',
      p_base_currency,
      p_quote_currency;
  end if;

  return round(
    p_amount * v_rate,
    2
  );
end;
$$;


-- ------------------------------------------------------------
-- 4. Determine whether direct payment is allowed
-- ------------------------------------------------------------

create or replace function public.currency_direct_payment_allowed(
  p_currency_code text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed boolean;
begin

  select direct_payment_enabled
  into v_allowed
  from public.currency_settings
  where currency_code = p_currency_code
    and is_active = true;

  return coalesce(v_allowed, false);
end;
$$;


-- ------------------------------------------------------------
-- 5. Resolve a user's display/payment currency
-- ------------------------------------------------------------

create or replace function public.resolve_payment_currency(
  p_requested_currency text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin

  if public.currency_direct_payment_allowed(
    p_requested_currency
  ) then
    return p_requested_currency;
  end if;

  return 'USD';
end;
$$;


-- ------------------------------------------------------------
-- 6. Admin currency management
-- ------------------------------------------------------------

create or replace function public.admin_set_currency(
  p_currency_code text,
  p_currency_name text,
  p_symbol text,
  p_direct_payment_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  insert into public.currency_settings (
    currency_code,
    currency_name,
    symbol,
    direct_payment_enabled
  )
  values (
    upper(p_currency_code),
    p_currency_name,
    p_symbol,
    p_direct_payment_enabled
  )
  on conflict (currency_code)
  do update set
    currency_name = excluded.currency_name,
    symbol = excluded.symbol,
    direct_payment_enabled =
      excluded.direct_payment_enabled,
    updated_at = now();

  return true;
end;
$$;


-- ------------------------------------------------------------
-- 7. Admin FX rate management
-- ------------------------------------------------------------

create or replace function public.admin_set_fx_rate(
  p_base_currency text,
  p_quote_currency text,
  p_rate numeric,
  p_source text default null,
  p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin

  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  if p_rate <= 0 then
    raise exception 'FX rate must be greater than zero';
  end if;

  insert into public.fx_rates (
    base_currency,
    quote_currency,
    rate,
    source,
    expires_at,
    is_active
  )
  values (
    upper(p_base_currency),
    upper(p_quote_currency),
    p_rate,
    p_source,
    p_expires_at,
    true
  )
  returning id into v_id;

  return v_id;
end;
$$;


-- ------------------------------------------------------------
-- 8. RLS
-- ------------------------------------------------------------

alter table public.currency_settings enable row level security;
alter table public.fx_rates enable row level security;


drop policy if exists "Authenticated users view active currencies"
on public.currency_settings;

create policy "Authenticated users view active currencies"
on public.currency_settings
for select
to authenticated
using (
  is_active = true
);


drop policy if exists "Admins manage currencies"
on public.currency_settings;

create policy "Admins manage currencies"
on public.currency_settings
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


drop policy if exists "Authenticated users view active FX rates"
on public.fx_rates;

create policy "Authenticated users view active FX rates"
on public.fx_rates
for select
to authenticated
using (
  is_active = true
);


drop policy if exists "Admins manage FX rates"
on public.fx_rates;

create policy "Admins manage FX rates"
on public.fx_rates
for all
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ------------------------------------------------------------
-- 9. Initial currency configuration
-- ------------------------------------------------------------

insert into public.currency_settings (
  currency_code,
  currency_name,
  symbol,
  is_active,
  is_primary,
  direct_payment_enabled
)
values
  ('NGN', 'Nigerian Naira', '₦', true, true, true),
  ('USD', 'United States Dollar', '$', true, false, true),
  ('GBP', 'British Pound', '£', true, false, true),
  ('EUR', 'Euro', '€', true, false, true),
  ('GHS', 'Ghanaian Cedi', 'GH₵', true, false, false),
  ('KES', 'Kenyan Shilling', 'KSh', true, false, false)
on conflict (currency_code)
do nothing;


-- ------------------------------------------------------------
-- 10. Updated-at trigger
-- ------------------------------------------------------------

drop trigger if exists currency_settings_updated_at
on public.currency_settings;

create trigger currency_settings_updated_at
before update on public.currency_settings
for each row
execute function public.set_updated_at();


-- ------------------------------------------------------------
-- 11. Indexes
-- ------------------------------------------------------------

create index if not exists currency_settings_active_idx
on public.currency_settings(is_active);

create index if not exists fx_rates_lookup_idx
on public.fx_rates(
  base_currency,
  quote_currency,
  effective_at desc
);


-- ------------------------------------------------------------
-- END BATCH 19
-- ============================================================
