-- eKelas Usahawan learning and impact portal
-- Empty production foundation: no users, participants, modules, quizzes or programme records are seeded.
-- Safe to use beside another application because every database object is prefixed with portal_.

create extension if not exists pgcrypto;

do $$ begin
  create type public.portal_role as enum ('admin', 'mentor', 'stakeholder', 'participant');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.portal_resource_kind as enum ('video', 'reading', 'workbook');
exception when duplicate_object then null;
end $$;

create table if not exists public.portal_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 120),
  role public.portal_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portal_programmes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 2 and 160),
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portal_cohorts (
  id uuid primary key default gen_random_uuid(),
  programme_id uuid not null references public.portal_programmes(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 160),
  state text,
  starts_on date,
  ends_on date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (programme_id, name)
);

create table if not exists public.portal_cohort_access (
  user_id uuid not null references public.portal_memberships(user_id) on delete cascade,
  cohort_id uuid not null references public.portal_cohorts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, cohort_id)
);

create table if not exists public.portal_participants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  cohort_id uuid not null references public.portal_cohorts(id) on delete restrict,
  mentor_user_id uuid references public.portal_memberships(user_id) on delete set null,
  participant_code text unique,
  full_name text not null check (char_length(full_name) between 2 and 160),
  business_name text,
  email text,
  phone text,
  state text,
  gender text,
  age integer check (age is null or age between 15 and 100),
  sector text,
  background text,
  goal text,
  avatar_path text,
  required_class_count integer not null default 0 check (required_class_count >= 0),
  baseline_sales numeric(14,2) check (baseline_sales is null or baseline_sales >= 0),
  baseline_operating_costs numeric(14,2) check (baseline_operating_costs is null or baseline_operating_costs >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portal_modules (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 180),
  description text,
  sequence_number integer not null default 1 check (sequence_number > 0),
  pass_mark integer not null default 70 check (pass_mark between 0 and 100),
  revision integer not null default 1 check (revision > 0),
  published boolean not null default false,
  created_by uuid references public.portal_memberships(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portal_module_resources (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.portal_modules(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 180),
  kind public.portal_resource_kind not null,
  content text,
  external_url text,
  storage_path text,
  sequence_number integer not null default 1 check (sequence_number > 0),
  required boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (content is not null or external_url is not null or storage_path is not null)
);

create table if not exists public.portal_module_assignments (
  participant_id uuid not null references public.portal_participants(id) on delete cascade,
  module_id uuid not null references public.portal_modules(id) on delete cascade,
  assigned_by uuid references public.portal_memberships(user_id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (participant_id, module_id)
);

create table if not exists public.portal_resource_progress (
  participant_id uuid not null references public.portal_participants(id) on delete cascade,
  resource_id uuid not null references public.portal_module_resources(id) on delete cascade,
  studied_at timestamptz not null default now(),
  primary key (participant_id, resource_id)
);

create table if not exists public.portal_private_notes (
  participant_id uuid not null references public.portal_participants(id) on delete cascade,
  resource_id uuid not null references public.portal_module_resources(id) on delete cascade,
  note text not null default '' check (char_length(note) <= 10000),
  updated_at timestamptz not null default now(),
  primary key (participant_id, resource_id)
);

create table if not exists public.portal_quiz_questions (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.portal_modules(id) on delete cascade,
  prompt text not null check (char_length(prompt) between 2 and 1000),
  options jsonb not null check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) between 2 and 8),
  sequence_number integer not null default 1 check (sequence_number > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Correct answers are deliberately separated so participants never receive them through the browser API.
create table if not exists public.portal_quiz_keys (
  question_id uuid primary key references public.portal_quiz_questions(id) on delete cascade,
  correct_option integer not null check (correct_option >= 0),
  feedback text
);

create table if not exists public.portal_quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.portal_participants(id) on delete cascade,
  module_id uuid not null references public.portal_modules(id) on delete cascade,
  module_revision integer not null,
  answers jsonb not null,
  score integer not null check (score between 0 and 100),
  passed boolean not null,
  attempted_at timestamptz not null default now()
);

create table if not exists public.portal_attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid not null references public.portal_cohorts(id) on delete cascade,
  meeting_number integer not null check (meeting_number > 0),
  session_date date not null,
  title text not null check (char_length(title) between 2 and 180),
  finalized boolean not null default false,
  finalized_at timestamptz,
  created_by uuid references public.portal_memberships(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cohort_id, meeting_number)
);

create table if not exists public.portal_attendance_records (
  session_id uuid not null references public.portal_attendance_sessions(id) on delete cascade,
  participant_id uuid not null references public.portal_participants(id) on delete cascade,
  status text not null default 'unmarked' check (status in ('present', 'absent', 'unmarked')),
  marked_by uuid references public.portal_memberships(user_id) on delete set null,
  marked_at timestamptz not null default now(),
  primary key (session_id, participant_id)
);

create table if not exists public.portal_business_checkins (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.portal_participants(id) on delete cascade,
  reporting_month date not null check (date_trunc('month', reporting_month)::date = reporting_month),
  sales numeric(14,2) not null check (sales >= 0),
  operating_costs numeric(14,2) not null check (operating_costs >= 0),
  notes text,
  impact_story text,
  story_consent boolean not null default false,
  mentor_reviewed boolean not null default false,
  reviewed_by uuid references public.portal_memberships(user_id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (participant_id, reporting_month)
);

create index if not exists portal_cohorts_programme_idx on public.portal_cohorts(programme_id);
create index if not exists portal_participants_cohort_idx on public.portal_participants(cohort_id);
create index if not exists portal_participants_mentor_idx on public.portal_participants(mentor_user_id);
create index if not exists portal_assignments_module_idx on public.portal_module_assignments(module_id);
create index if not exists portal_attempts_participant_idx on public.portal_quiz_attempts(participant_id, attempted_at desc);
create index if not exists portal_sessions_cohort_idx on public.portal_attendance_sessions(cohort_id, session_date desc);
create index if not exists portal_checkins_participant_idx on public.portal_business_checkins(participant_id, reporting_month desc);

create or replace function public.portal_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'portal_memberships','portal_programmes','portal_cohorts','portal_participants','portal_modules',
    'portal_module_resources','portal_private_notes','portal_quiz_questions','portal_attendance_sessions',
    'portal_business_checkins'
  ] loop
    execute format('drop trigger if exists %I on public.%I', table_name || '_touch', table_name);
    execute format('create trigger %I before update on public.%I for each row execute function public.portal_touch_updated_at()', table_name || '_touch', table_name);
  end loop;
end $$;

create or replace function public.portal_current_role()
returns public.portal_role
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.portal_memberships
  where user_id = (select auth.uid()) and active
  limit 1
$$;

create or replace function public.portal_is_active_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1 from public.portal_memberships
    where user_id = (select auth.uid()) and active
  )
$$;

create or replace function public.portal_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.portal_current_role() = 'admin'::public.portal_role, false)
$$;

create or replace function public.portal_participant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.portal_participants
  where user_id = (select auth.uid()) and active
  limit 1
$$;

create or replace function public.portal_can_access_cohort(target_cohort uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not public.portal_is_active_member() then false
    when public.portal_current_role() = 'admin'::public.portal_role then true
    when public.portal_current_role() = 'participant'::public.portal_role then exists(
      select 1 from public.portal_participants
      where user_id = (select auth.uid()) and cohort_id = target_cohort and active
    )
    else exists(
      select 1 from public.portal_cohort_access
      where user_id = (select auth.uid()) and cohort_id = target_cohort
    )
  end
$$;

create or replace function public.portal_can_access_participant(target_participant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1 from public.portal_participants participant
    where participant.id = target_participant
      and (
        participant.user_id = (select auth.uid())
        or public.portal_is_admin()
        or public.portal_can_access_cohort(participant.cohort_id)
      )
  )
$$;

create or replace function public.portal_can_access_module(target_module uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.portal_is_admin() then true
    when not public.portal_is_active_member() then false
    when public.portal_current_role() = 'participant'::public.portal_role then exists(
      select 1 from public.portal_module_assignments assignment
      join public.portal_modules module on module.id = assignment.module_id
      where assignment.module_id = target_module
        and assignment.participant_id = public.portal_participant_id()
        and module.published
    )
    else exists(select 1 from public.portal_modules where id = target_module and published)
  end
$$;

revoke all on function public.portal_current_role() from public;
revoke all on function public.portal_is_active_member() from public;
revoke all on function public.portal_is_admin() from public;
revoke all on function public.portal_participant_id() from public;
revoke all on function public.portal_can_access_cohort(uuid) from public;
revoke all on function public.portal_can_access_participant(uuid) from public;
revoke all on function public.portal_can_access_module(uuid) from public;
grant execute on function public.portal_current_role() to authenticated;
grant execute on function public.portal_is_active_member() to authenticated;
grant execute on function public.portal_is_admin() to authenticated;
grant execute on function public.portal_participant_id() to authenticated;
grant execute on function public.portal_can_access_cohort(uuid) to authenticated;
grant execute on function public.portal_can_access_participant(uuid) to authenticated;
grant execute on function public.portal_can_access_module(uuid) to authenticated;

alter table public.portal_memberships enable row level security;
alter table public.portal_programmes enable row level security;
alter table public.portal_cohorts enable row level security;
alter table public.portal_cohort_access enable row level security;
alter table public.portal_participants enable row level security;
alter table public.portal_modules enable row level security;
alter table public.portal_module_resources enable row level security;
alter table public.portal_module_assignments enable row level security;
alter table public.portal_resource_progress enable row level security;
alter table public.portal_private_notes enable row level security;
alter table public.portal_quiz_questions enable row level security;
alter table public.portal_quiz_keys enable row level security;
alter table public.portal_quiz_attempts enable row level security;
alter table public.portal_attendance_sessions enable row level security;
alter table public.portal_attendance_records enable row level security;
alter table public.portal_business_checkins enable row level security;

revoke all on table
  public.portal_memberships, public.portal_programmes, public.portal_cohorts, public.portal_cohort_access,
  public.portal_participants, public.portal_modules, public.portal_module_resources, public.portal_module_assignments,
  public.portal_resource_progress, public.portal_private_notes, public.portal_quiz_questions, public.portal_quiz_keys,
  public.portal_quiz_attempts, public.portal_attendance_sessions, public.portal_attendance_records,
  public.portal_business_checkins
from anon;
grant select, insert, update, delete on table
  public.portal_memberships, public.portal_programmes, public.portal_cohorts, public.portal_cohort_access,
  public.portal_participants, public.portal_modules, public.portal_module_resources, public.portal_module_assignments,
  public.portal_resource_progress, public.portal_private_notes, public.portal_quiz_questions, public.portal_quiz_keys,
  public.portal_quiz_attempts, public.portal_attendance_sessions, public.portal_attendance_records,
  public.portal_business_checkins
to authenticated;

drop policy if exists portal_memberships_select on public.portal_memberships;
create policy portal_memberships_select on public.portal_memberships for select to authenticated
using (user_id = (select auth.uid()) or public.portal_is_admin());
drop policy if exists portal_memberships_admin_insert on public.portal_memberships;
create policy portal_memberships_admin_insert on public.portal_memberships for insert to authenticated
with check (public.portal_is_admin());
drop policy if exists portal_memberships_admin_update on public.portal_memberships;
create policy portal_memberships_admin_update on public.portal_memberships for update to authenticated
using (public.portal_is_admin()) with check (public.portal_is_admin());
drop policy if exists portal_memberships_admin_delete on public.portal_memberships;
create policy portal_memberships_admin_delete on public.portal_memberships for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_programmes_select on public.portal_programmes;
create policy portal_programmes_select on public.portal_programmes for select to authenticated
using (public.portal_is_active_member());
drop policy if exists portal_programmes_admin_insert on public.portal_programmes;
create policy portal_programmes_admin_insert on public.portal_programmes for insert to authenticated
with check (public.portal_is_admin());
drop policy if exists portal_programmes_admin_update on public.portal_programmes;
create policy portal_programmes_admin_update on public.portal_programmes for update to authenticated
using (public.portal_is_admin()) with check (public.portal_is_admin());
drop policy if exists portal_programmes_admin_delete on public.portal_programmes;
create policy portal_programmes_admin_delete on public.portal_programmes for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_cohorts_select on public.portal_cohorts;
create policy portal_cohorts_select on public.portal_cohorts for select to authenticated
using (public.portal_can_access_cohort(id));
drop policy if exists portal_cohorts_admin_insert on public.portal_cohorts;
create policy portal_cohorts_admin_insert on public.portal_cohorts for insert to authenticated
with check (public.portal_is_admin());
drop policy if exists portal_cohorts_admin_update on public.portal_cohorts;
create policy portal_cohorts_admin_update on public.portal_cohorts for update to authenticated
using (public.portal_is_admin()) with check (public.portal_is_admin());
drop policy if exists portal_cohorts_admin_delete on public.portal_cohorts;
create policy portal_cohorts_admin_delete on public.portal_cohorts for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_cohort_access_select on public.portal_cohort_access;
create policy portal_cohort_access_select on public.portal_cohort_access for select to authenticated
using (user_id = (select auth.uid()) or public.portal_is_admin());
drop policy if exists portal_cohort_access_admin_insert on public.portal_cohort_access;
create policy portal_cohort_access_admin_insert on public.portal_cohort_access for insert to authenticated
with check (public.portal_is_admin());
drop policy if exists portal_cohort_access_admin_delete on public.portal_cohort_access;
create policy portal_cohort_access_admin_delete on public.portal_cohort_access for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_participants_select on public.portal_participants;
create policy portal_participants_select on public.portal_participants for select to authenticated
using (public.portal_can_access_participant(id));
drop policy if exists portal_participants_admin_insert on public.portal_participants;
create policy portal_participants_admin_insert on public.portal_participants for insert to authenticated
with check (public.portal_is_admin());
drop policy if exists portal_participants_admin_update on public.portal_participants;
create policy portal_participants_admin_update on public.portal_participants for update to authenticated
using (public.portal_is_admin()) with check (public.portal_is_admin());
drop policy if exists portal_participants_admin_delete on public.portal_participants;
create policy portal_participants_admin_delete on public.portal_participants for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_modules_select on public.portal_modules;
create policy portal_modules_select on public.portal_modules for select to authenticated
using (public.portal_can_access_module(id));
drop policy if exists portal_modules_admin_insert on public.portal_modules;
create policy portal_modules_admin_insert on public.portal_modules for insert to authenticated
with check (public.portal_is_admin());
drop policy if exists portal_modules_admin_update on public.portal_modules;
create policy portal_modules_admin_update on public.portal_modules for update to authenticated
using (public.portal_is_admin()) with check (public.portal_is_admin());
drop policy if exists portal_modules_admin_delete on public.portal_modules;
create policy portal_modules_admin_delete on public.portal_modules for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_resources_select on public.portal_module_resources;
create policy portal_resources_select on public.portal_module_resources for select to authenticated
using (public.portal_can_access_module(module_id));
drop policy if exists portal_resources_admin_insert on public.portal_module_resources;
create policy portal_resources_admin_insert on public.portal_module_resources for insert to authenticated
with check (public.portal_is_admin());
drop policy if exists portal_resources_admin_update on public.portal_module_resources;
create policy portal_resources_admin_update on public.portal_module_resources for update to authenticated
using (public.portal_is_admin()) with check (public.portal_is_admin());
drop policy if exists portal_resources_admin_delete on public.portal_module_resources;
create policy portal_resources_admin_delete on public.portal_module_resources for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_assignments_select on public.portal_module_assignments;
create policy portal_assignments_select on public.portal_module_assignments for select to authenticated
using (public.portal_can_access_participant(participant_id));
drop policy if exists portal_assignments_admin_insert on public.portal_module_assignments;
create policy portal_assignments_admin_insert on public.portal_module_assignments for insert to authenticated
with check (public.portal_is_admin());
drop policy if exists portal_assignments_admin_delete on public.portal_module_assignments;
create policy portal_assignments_admin_delete on public.portal_module_assignments for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_progress_select on public.portal_resource_progress;
create policy portal_progress_select on public.portal_resource_progress for select to authenticated
using (public.portal_can_access_participant(participant_id));
drop policy if exists portal_progress_participant_insert on public.portal_resource_progress;
create policy portal_progress_participant_insert on public.portal_resource_progress for insert to authenticated
with check (participant_id = public.portal_participant_id());
drop policy if exists portal_progress_participant_delete on public.portal_resource_progress;
create policy portal_progress_participant_delete on public.portal_resource_progress for delete to authenticated
using (participant_id = public.portal_participant_id());

drop policy if exists portal_notes_owner_select on public.portal_private_notes;
create policy portal_notes_owner_select on public.portal_private_notes for select to authenticated
using (participant_id = public.portal_participant_id());
drop policy if exists portal_notes_owner_insert on public.portal_private_notes;
create policy portal_notes_owner_insert on public.portal_private_notes for insert to authenticated
with check (participant_id = public.portal_participant_id());
drop policy if exists portal_notes_owner_update on public.portal_private_notes;
create policy portal_notes_owner_update on public.portal_private_notes for update to authenticated
using (participant_id = public.portal_participant_id()) with check (participant_id = public.portal_participant_id());
drop policy if exists portal_notes_owner_delete on public.portal_private_notes;
create policy portal_notes_owner_delete on public.portal_private_notes for delete to authenticated
using (participant_id = public.portal_participant_id());

drop policy if exists portal_questions_select on public.portal_quiz_questions;
create policy portal_questions_select on public.portal_quiz_questions for select to authenticated
using (public.portal_can_access_module(module_id));
drop policy if exists portal_questions_admin_write on public.portal_quiz_questions;
create policy portal_questions_admin_write on public.portal_quiz_questions for all to authenticated
using (public.portal_is_admin()) with check (public.portal_is_admin());
drop policy if exists portal_keys_admin_only on public.portal_quiz_keys;
create policy portal_keys_admin_only on public.portal_quiz_keys for all to authenticated
using (public.portal_is_admin()) with check (public.portal_is_admin());

drop policy if exists portal_attempts_select on public.portal_quiz_attempts;
create policy portal_attempts_select on public.portal_quiz_attempts for select to authenticated
using (public.portal_can_access_participant(participant_id));

drop policy if exists portal_sessions_select on public.portal_attendance_sessions;
create policy portal_sessions_select on public.portal_attendance_sessions for select to authenticated
using (public.portal_can_access_cohort(cohort_id));
drop policy if exists portal_sessions_staff_insert on public.portal_attendance_sessions;
create policy portal_sessions_staff_insert on public.portal_attendance_sessions for insert to authenticated
with check (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_cohort(cohort_id));
drop policy if exists portal_sessions_staff_update on public.portal_attendance_sessions;
create policy portal_sessions_staff_update on public.portal_attendance_sessions for update to authenticated
using (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_cohort(cohort_id))
with check (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_cohort(cohort_id));
drop policy if exists portal_sessions_admin_delete on public.portal_attendance_sessions;
create policy portal_sessions_admin_delete on public.portal_attendance_sessions for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_attendance_select on public.portal_attendance_records;
create policy portal_attendance_select on public.portal_attendance_records for select to authenticated
using (public.portal_can_access_participant(participant_id));
drop policy if exists portal_attendance_staff_insert on public.portal_attendance_records;
create policy portal_attendance_staff_insert on public.portal_attendance_records for insert to authenticated
with check (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_participant(participant_id));
drop policy if exists portal_attendance_staff_update on public.portal_attendance_records;
create policy portal_attendance_staff_update on public.portal_attendance_records for update to authenticated
using (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_participant(participant_id))
with check (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_participant(participant_id));
drop policy if exists portal_attendance_admin_delete on public.portal_attendance_records;
create policy portal_attendance_admin_delete on public.portal_attendance_records for delete to authenticated
using (public.portal_is_admin());

drop policy if exists portal_checkins_select on public.portal_business_checkins;
create policy portal_checkins_select on public.portal_business_checkins for select to authenticated
using (public.portal_can_access_participant(participant_id));
drop policy if exists portal_checkins_insert on public.portal_business_checkins;
create policy portal_checkins_insert on public.portal_business_checkins for insert to authenticated
with check (
  participant_id = public.portal_participant_id()
  or (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_participant(participant_id))
);
drop policy if exists portal_checkins_update on public.portal_business_checkins;
create policy portal_checkins_update on public.portal_business_checkins for update to authenticated
using (
  participant_id = public.portal_participant_id()
  or (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_participant(participant_id))
)
with check (
  participant_id = public.portal_participant_id()
  or (public.portal_current_role() in ('admin'::public.portal_role, 'mentor'::public.portal_role) and public.portal_can_access_participant(participant_id))
);
drop policy if exists portal_checkins_admin_delete on public.portal_business_checkins;
create policy portal_checkins_admin_delete on public.portal_business_checkins for delete to authenticated
using (public.portal_is_admin());

create or replace function public.portal_submit_quiz(target_module uuid, submitted_answers jsonb)
returns table (attempt_id uuid, score integer, passed boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_participant uuid;
  module_revision integer;
  module_pass_mark integer;
  total_questions integer;
  correct_answers integer;
  calculated_score integer;
  new_attempt uuid;
begin
  current_participant := public.portal_participant_id();
  if current_participant is null then raise exception 'Active participant membership required'; end if;
  if not public.portal_can_access_module(target_module) then raise exception 'Module is not assigned or published'; end if;
  if jsonb_typeof(submitted_answers) <> 'object' then raise exception 'Answers must be a JSON object'; end if;

  select revision, pass_mark into module_revision, module_pass_mark
  from public.portal_modules where id = target_module and published;

  select count(*) into total_questions
  from public.portal_quiz_questions where module_id = target_module;
  if total_questions = 0 then raise exception 'Quiz has no questions'; end if;

  select count(*) into correct_answers
  from public.portal_quiz_questions question
  join public.portal_quiz_keys answer_key on answer_key.question_id = question.id
  where question.module_id = target_module
    and submitted_answers ? question.id::text
    and (submitted_answers ->> question.id::text) ~ '^[0-9]+$'
    and (submitted_answers ->> question.id::text)::integer = answer_key.correct_option;

  calculated_score := round((correct_answers::numeric / total_questions::numeric) * 100)::integer;
  insert into public.portal_quiz_attempts (participant_id, module_id, module_revision, answers, score, passed)
  values (current_participant, target_module, module_revision, submitted_answers, calculated_score, calculated_score >= module_pass_mark)
  returning id into new_attempt;

  return query select new_attempt, calculated_score, calculated_score >= module_pass_mark;
end;
$$;

revoke all on function public.portal_submit_quiz(uuid, jsonb) from public;
grant execute on function public.portal_submit_quiz(uuid, jsonb) to authenticated;

-- Intentionally no INSERT statements follow. The production portal starts empty.
