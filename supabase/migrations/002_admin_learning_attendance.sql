-- eKelas Usahawan product expansion
-- Run after 001_m_foundation.sql. No demonstration data is inserted.

create table if not exists public.m_courses (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 180),
  description text,
  active boolean not null default true,
  created_by uuid references public.m_memberships(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.m_modules
  add column if not exists course_id uuid references public.m_courses(id) on delete cascade;

alter table public.m_attendance_sessions
  add column if not exists starts_at time,
  add column if not exists delivery_mode text not null default 'physical',
  add column if not exists join_url text,
  add column if not exists location text;

do $$ begin
  alter table public.m_attendance_sessions
    add constraint m_attendance_delivery_mode_check
    check (delivery_mode in ('physical', 'zoom', 'teams', 'other'));
exception when duplicate_object then null;
end $$;

create table if not exists public.m_social_accounts (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.m_participants(id) on delete cascade,
  platform text not null check (platform in ('tiktok', 'instagram', 'facebook')),
  handle text not null,
  profile_url text,
  baseline_month date not null check (date_trunc('month', baseline_month)::date = baseline_month),
  consent_confirmed boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (participant_id, platform, handle)
);

create table if not exists public.m_social_snapshots (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.m_social_accounts(id) on delete cascade,
  reporting_month date not null check (date_trunc('month', reporting_month)::date = reporting_month),
  followers integer check (followers is null or followers >= 0),
  posts_published integer check (posts_published is null or posts_published >= 0),
  reach integer check (reach is null or reach >= 0),
  views integer check (views is null or views >= 0),
  engagements integer check (engagements is null or engagements >= 0),
  tagged_posts integer check (tagged_posts is null or tagged_posts >= 0),
  evidence_url text,
  screenshot_path text,
  source text not null default 'participant' check (source in ('participant', 'mentor', 'admin', 'api')),
  verified_by uuid references public.m_memberships(user_id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (account_id, reporting_month)
);

create index if not exists m_modules_course_idx on public.m_modules(course_id, sequence_number);
create index if not exists m_social_accounts_participant_idx on public.m_social_accounts(participant_id);
create index if not exists m_social_snapshots_account_idx on public.m_social_snapshots(account_id, reporting_month desc);

drop trigger if exists m_courses_touch on public.m_courses;
create trigger m_courses_touch before update on public.m_courses
for each row execute function public.m_touch_updated_at();
drop trigger if exists m_social_accounts_touch on public.m_social_accounts;
create trigger m_social_accounts_touch before update on public.m_social_accounts
for each row execute function public.m_touch_updated_at();
drop trigger if exists m_social_snapshots_touch on public.m_social_snapshots;
create trigger m_social_snapshots_touch before update on public.m_social_snapshots
for each row execute function public.m_touch_updated_at();

-- Mentors see only participants assigned to them. Stakeholders retain cohort-level read access.
create or replace function public.m_can_access_participant(target_participant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1 from public.m_participants participant
    where participant.id = target_participant
      and (
        participant.user_id = (select auth.uid())
        or public.m_is_admin()
        or (
          public.m_current_role() = 'mentor'::public.m_role
          and participant.mentor_user_id = (select auth.uid())
        )
        or (
          public.m_current_role() = 'stakeholder'::public.m_role
          and exists(
            select 1 from public.m_cohort_access access
            where access.user_id = (select auth.uid())
              and access.cohort_id = participant.cohort_id
          )
        )
      )
  )
$$;

create or replace function public.m_can_access_cohort(target_cohort uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not public.m_is_active_member() then false
    when public.m_current_role() = 'admin'::public.m_role then true
    when public.m_current_role() = 'participant'::public.m_role then exists(
      select 1 from public.m_participants
      where user_id = (select auth.uid()) and cohort_id = target_cohort and active
    )
    when public.m_current_role() = 'mentor'::public.m_role then exists(
      select 1 from public.m_participants
      where mentor_user_id = (select auth.uid()) and cohort_id = target_cohort and active
    ) or exists(
      select 1 from public.m_cohort_access
      where user_id = (select auth.uid()) and cohort_id = target_cohort
    )
    else exists(
      select 1 from public.m_cohort_access
      where user_id = (select auth.uid()) and cohort_id = target_cohort
    )
  end
$$;

alter table public.m_courses enable row level security;
alter table public.m_social_accounts enable row level security;
alter table public.m_social_snapshots enable row level security;

revoke all on table public.m_courses, public.m_social_accounts, public.m_social_snapshots from anon;
grant select, insert, update, delete on table
  public.m_courses, public.m_social_accounts, public.m_social_snapshots
to authenticated;

drop policy if exists m_courses_select on public.m_courses;
create policy m_courses_select on public.m_courses for select to authenticated
using (public.m_is_active_member());
drop policy if exists m_courses_admin_insert on public.m_courses;
create policy m_courses_admin_insert on public.m_courses for insert to authenticated
with check (public.m_is_admin());
drop policy if exists m_courses_admin_update on public.m_courses;
create policy m_courses_admin_update on public.m_courses for update to authenticated
using (public.m_is_admin()) with check (public.m_is_admin());
drop policy if exists m_courses_admin_delete on public.m_courses;
create policy m_courses_admin_delete on public.m_courses for delete to authenticated
using (public.m_is_admin());

drop policy if exists m_social_accounts_select on public.m_social_accounts;
create policy m_social_accounts_select on public.m_social_accounts for select to authenticated
using (public.m_can_access_participant(participant_id));
drop policy if exists m_social_accounts_insert on public.m_social_accounts;
create policy m_social_accounts_insert on public.m_social_accounts for insert to authenticated
with check (public.m_is_admin() or participant_id = public.m_participant_id());
drop policy if exists m_social_accounts_update on public.m_social_accounts;
create policy m_social_accounts_update on public.m_social_accounts for update to authenticated
using (public.m_is_admin() or participant_id = public.m_participant_id())
with check (public.m_is_admin() or participant_id = public.m_participant_id());
drop policy if exists m_social_accounts_admin_delete on public.m_social_accounts;
create policy m_social_accounts_admin_delete on public.m_social_accounts for delete to authenticated
using (public.m_is_admin());

drop policy if exists m_social_snapshots_select on public.m_social_snapshots;
create policy m_social_snapshots_select on public.m_social_snapshots for select to authenticated
using (exists(
  select 1 from public.m_social_accounts account
  where account.id = account_id and public.m_can_access_participant(account.participant_id)
));
drop policy if exists m_social_snapshots_insert on public.m_social_snapshots;
create policy m_social_snapshots_insert on public.m_social_snapshots for insert to authenticated
with check (exists(
  select 1 from public.m_social_accounts account
  where account.id = account_id
    and (
      account.participant_id = public.m_participant_id()
      or public.m_is_admin()
      or (
        public.m_current_role() = 'mentor'::public.m_role
        and public.m_can_access_participant(account.participant_id)
      )
    )
));
drop policy if exists m_social_snapshots_update on public.m_social_snapshots;
create policy m_social_snapshots_update on public.m_social_snapshots for update to authenticated
using (exists(
  select 1 from public.m_social_accounts account
  where account.id = account_id and public.m_can_access_participant(account.participant_id)
))
with check (exists(
  select 1 from public.m_social_accounts account
  where account.id = account_id and public.m_can_access_participant(account.participant_id)
));
drop policy if exists m_social_snapshots_admin_delete on public.m_social_snapshots;
create policy m_social_snapshots_admin_delete on public.m_social_snapshots for delete to authenticated
using (public.m_is_admin());

-- Intentionally no INSERT statements follow. Existing and new installations remain free of dummy data.
