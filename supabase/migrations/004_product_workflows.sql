-- eKelas Usahawan product workflows
-- Run after 001, 002 and 003. No demonstration data is inserted.

-- Participant business profile and monthly monitoring fields.
alter table public.m_participants
  add column if not exists business_description text,
  add column if not exists business_started_on date,
  add column if not exists employee_count integer check (employee_count is null or employee_count >= 0),
  add column if not exists registration_status text,
  add column if not exists baseline_month date,
  add column if not exists baseline_profit numeric(14,2),
  add column if not exists onboarding_completed_at timestamptz;

alter table public.m_business_checkins
  add column if not exists net_profit numeric(14,2),
  add column if not exists customer_count integer check (customer_count is null or customer_count >= 0),
  add column if not exists employee_count integer check (employee_count is null or employee_count >= 0);

create or replace function public.m_save_business_profile(
  target_business_name text,
  target_description text,
  target_sector text,
  target_phone text,
  target_state text,
  target_gender text,
  target_age integer,
  target_goal text,
  target_baseline_month date,
  target_baseline_sales numeric,
  target_baseline_costs numeric,
  target_baseline_profit numeric,
  target_employee_count integer,
  target_business_started_on date,
  target_registration_status text,
  target_avatar_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  participant_uuid uuid;
begin
  participant_uuid := public.m_participant_id();
  if participant_uuid is null then raise exception 'Active participant profile required.'; end if;
  if char_length(btrim(coalesce(target_business_name, ''))) < 2 then raise exception 'Business name is required.'; end if;
  if char_length(btrim(coalesce(target_description, ''))) < 10 then raise exception 'Add a short description of the business.'; end if;
  if target_baseline_sales is null or target_baseline_costs is null or target_baseline_profit is null then raise exception 'Complete all baseline financial figures.'; end if;
  if target_baseline_sales < 0 or target_baseline_costs < 0 then raise exception 'Sales and operating costs cannot be negative.'; end if;
  if target_age is not null and (target_age < 15 or target_age > 100) then raise exception 'Enter a valid age.'; end if;
  if target_employee_count is not null and target_employee_count < 0 then raise exception 'Employee count cannot be negative.'; end if;

  update public.m_participants
  set business_name = btrim(target_business_name),
      business_description = btrim(target_description),
      sector = nullif(btrim(coalesce(target_sector, '')), ''),
      phone = nullif(btrim(coalesce(target_phone, '')), ''),
      state = nullif(btrim(coalesce(target_state, '')), ''),
      gender = nullif(btrim(coalesce(target_gender, '')), ''),
      age = target_age,
      goal = nullif(btrim(coalesce(target_goal, '')), ''),
      baseline_month = target_baseline_month,
      baseline_sales = target_baseline_sales,
      baseline_operating_costs = target_baseline_costs,
      baseline_profit = target_baseline_profit,
      employee_count = target_employee_count,
      business_started_on = target_business_started_on,
      registration_status = nullif(btrim(coalesce(target_registration_status, '')), ''),
      avatar_path = coalesce(nullif(btrim(coalesce(target_avatar_path, '')), ''), avatar_path),
      onboarding_completed_at = coalesce(onboarding_completed_at, now())
  where id = participant_uuid;
  return participant_uuid;
end;
$$;

revoke all on function public.m_save_business_profile(text,text,text,text,text,text,integer,text,date,numeric,numeric,numeric,integer,date,text,text) from public;
grant execute on function public.m_save_business_profile(text,text,text,text,text,text,integer,text,date,numeric,numeric,numeric,integer,date,text,text) to authenticated;

-- Private participant profile images. Authenticated portal users may view them;
-- participants may write only inside their own user-id folder.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('m-participant-avatars', 'm-participant-avatars', false, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists m_participant_avatars_select on storage.objects;
create policy m_participant_avatars_select on storage.objects for select to authenticated
using (bucket_id = 'm-participant-avatars' and public.m_is_active_member());
drop policy if exists m_participant_avatars_insert on storage.objects;
create policy m_participant_avatars_insert on storage.objects for insert to authenticated
with check (bucket_id = 'm-participant-avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists m_participant_avatars_update on storage.objects;
create policy m_participant_avatars_update on storage.objects for update to authenticated
using (bucket_id = 'm-participant-avatars' and ((storage.foldername(name))[1] = auth.uid()::text or public.m_is_admin()))
with check (bucket_id = 'm-participant-avatars' and ((storage.foldername(name))[1] = auth.uid()::text or public.m_is_admin()));
drop policy if exists m_participant_avatars_delete on storage.objects;
create policy m_participant_avatars_delete on storage.objects for delete to authenticated
using (bucket_id = 'm-participant-avatars' and ((storage.foldername(name))[1] = auth.uid()::text or public.m_is_admin()));

-- Admin-issued staff invitations. Only an administrator can create a mentor or stakeholder invitation.
create table if not exists public.m_staff_invites (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  display_name text not null check (char_length(display_name) between 2 and 120),
  role public.m_role not null check (role in ('admin'::public.m_role, 'mentor'::public.m_role, 'stakeholder'::public.m_role)),
  code_digest bytea not null unique,
  code_hint text not null,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_user_id uuid references auth.users(id) on delete set null,
  created_by uuid references public.m_memberships(user_id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists m_staff_invites_email_idx on public.m_staff_invites(lower(email), expires_at desc);
alter table public.m_staff_invites enable row level security;
revoke all on table public.m_staff_invites from anon;
grant select, insert, update, delete on table public.m_staff_invites to authenticated;

drop policy if exists m_staff_invites_admin_select on public.m_staff_invites;
create policy m_staff_invites_admin_select on public.m_staff_invites for select to authenticated using (public.m_is_admin());
drop policy if exists m_staff_invites_admin_insert on public.m_staff_invites;
create policy m_staff_invites_admin_insert on public.m_staff_invites for insert to authenticated with check (public.m_is_admin());
drop policy if exists m_staff_invites_admin_update on public.m_staff_invites;
create policy m_staff_invites_admin_update on public.m_staff_invites for update to authenticated using (public.m_is_admin()) with check (public.m_is_admin());
drop policy if exists m_staff_invites_admin_delete on public.m_staff_invites;
create policy m_staff_invites_admin_delete on public.m_staff_invites for delete to authenticated using (public.m_is_admin());

create or replace function public.m_create_staff_invite(
  target_email text,
  target_display_name text,
  target_role public.m_role default 'mentor'::public.m_role,
  valid_until timestamptz default (now() + interval '7 days')
)
returns table(invitation_code text, invite_id uuid, code_hint text, expires_at timestamptz, invited_role public.m_role)
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw_code text;
  created_id uuid;
begin
  if not public.m_is_admin() then raise exception 'Only an administrator can invite staff.'; end if;
  if target_role not in ('admin'::public.m_role, 'mentor'::public.m_role, 'stakeholder'::public.m_role) then raise exception 'Select a staff role.'; end if;
  if position('@' in coalesce(target_email, '')) < 2 then raise exception 'Enter a valid email address.'; end if;
  if char_length(btrim(coalesce(target_display_name, ''))) < 2 then raise exception 'Enter the staff member name.'; end if;
  if valid_until <= now() then raise exception 'The invitation expiry must be in the future.'; end if;

  raw_code := 'STAFF-' || upper(substr(encode(extensions.gen_random_bytes(10), 'hex'), 1, 16));
  insert into public.m_staff_invites(email, display_name, role, code_digest, code_hint, expires_at, created_by)
  values (lower(btrim(target_email)), btrim(target_display_name), target_role, extensions.digest(raw_code, 'sha256'), right(raw_code, 4), valid_until, auth.uid())
  returning id into created_id;

  return query select raw_code, created_id, right(raw_code, 4), valid_until, target_role;
end;
$$;

create or replace function public.m_validate_staff_invite(raw_code text, target_email text)
returns table(display_name text, invited_role public.m_role, expires_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select invite.display_name, invite.role, invite.expires_at
  from public.m_staff_invites invite
  where invite.code_digest = extensions.digest(upper(btrim(raw_code)), 'sha256')
    and lower(invite.email) = lower(btrim(target_email))
    and invite.accepted_at is null
    and invite.expires_at > now()
  limit 1
$$;

create or replace function public.m_handle_staff_invite()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw_code text;
  selected_invite public.m_staff_invites%rowtype;
begin
  raw_code := upper(btrim(coalesce(new.raw_user_meta_data ->> 'staff_invite_code', '')));
  if raw_code = '' then return new; end if;

  select * into selected_invite
  from public.m_staff_invites invite
  where invite.code_digest = extensions.digest(raw_code, 'sha256')
    and lower(invite.email) = lower(new.email)
    and invite.accepted_at is null
    and invite.expires_at > now()
  for update;

  if selected_invite.id is null then raise exception 'This staff invitation is invalid, expired or belongs to another email.'; end if;

  insert into public.m_memberships(user_id, display_name, role, active)
  values (new.id, selected_invite.display_name, selected_invite.role, true)
  on conflict (user_id) do update set display_name = excluded.display_name, role = excluded.role, active = true;

  update public.m_staff_invites set accepted_at = now(), accepted_user_id = new.id where id = selected_invite.id;
  return new;
end;
$$;

drop trigger if exists m_auth_staff_invite on auth.users;
create trigger m_auth_staff_invite after insert on auth.users for each row execute function public.m_handle_staff_invite();

revoke all on function public.m_create_staff_invite(text,text,public.m_role,timestamptz) from public;
revoke all on function public.m_validate_staff_invite(text,text) from public;
revoke all on function public.m_handle_staff_invite() from public;
grant execute on function public.m_create_staff_invite(text,text,public.m_role,timestamptz) to authenticated;
grant execute on function public.m_validate_staff_invite(text,text) to anon, authenticated;

-- Course access is now assigned to cohorts from inside each course workspace.
create table if not exists public.m_course_cohort_access (
  course_id uuid not null references public.m_courses(id) on delete cascade,
  cohort_id uuid not null references public.m_cohorts(id) on delete cascade,
  assigned_by uuid references public.m_memberships(user_id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (course_id, cohort_id)
);

alter table public.m_course_cohort_access enable row level security;
revoke all on table public.m_course_cohort_access from anon;
grant select, insert, update, delete on table public.m_course_cohort_access to authenticated;

drop policy if exists m_course_cohort_access_select on public.m_course_cohort_access;
create policy m_course_cohort_access_select on public.m_course_cohort_access for select to authenticated
using (public.m_is_admin() or public.m_can_access_cohort(cohort_id));
drop policy if exists m_course_cohort_access_admin_insert on public.m_course_cohort_access;
create policy m_course_cohort_access_admin_insert on public.m_course_cohort_access for insert to authenticated with check (public.m_is_admin());
drop policy if exists m_course_cohort_access_admin_delete on public.m_course_cohort_access;
create policy m_course_cohort_access_admin_delete on public.m_course_cohort_access for delete to authenticated using (public.m_is_admin());

create or replace function public.m_sync_course_cohort_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.m_course_assignments(participant_id, course_id, assigned_by)
    select participant.id, new.course_id, new.assigned_by
    from public.m_participants participant
    where participant.cohort_id = new.cohort_id and participant.active
    on conflict (participant_id, course_id) do nothing;
    return new;
  end if;

  delete from public.m_course_assignments assignment
  using public.m_participants participant
  where assignment.participant_id = participant.id
    and participant.cohort_id = old.cohort_id
    and assignment.course_id = old.course_id;
  return old;
end;
$$;

create or replace function public.m_sync_participant_course_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.cohort_id is distinct from new.cohort_id then
    delete from public.m_course_assignments assignment
    using public.m_course_cohort_access access
    where assignment.participant_id = new.id
      and assignment.course_id = access.course_id
      and access.cohort_id = old.cohort_id;
  end if;

  insert into public.m_course_assignments(participant_id, course_id, assigned_by)
  select new.id, access.course_id, access.assigned_by
  from public.m_course_cohort_access access
  where access.cohort_id = new.cohort_id
  on conflict (participant_id, course_id) do nothing;
  return new;
end;
$$;

create or replace function public.m_remove_course_modules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.m_module_assignments assignment
  using public.m_modules module
  where assignment.participant_id = old.participant_id
    and assignment.module_id = module.id
    and module.course_id = old.course_id;
  return old;
end;
$$;

drop trigger if exists m_course_cohort_sync on public.m_course_cohort_access;
create trigger m_course_cohort_sync after insert or delete on public.m_course_cohort_access for each row execute function public.m_sync_course_cohort_access();
drop trigger if exists m_participant_course_sync on public.m_participants;
create trigger m_participant_course_sync after insert or update of cohort_id on public.m_participants for each row execute function public.m_sync_participant_course_access();
drop trigger if exists m_course_assignment_remove_modules on public.m_course_assignments;
create trigger m_course_assignment_remove_modules after delete on public.m_course_assignments for each row execute function public.m_remove_course_modules();

revoke all on function public.m_sync_course_cohort_access() from public;
revoke all on function public.m_sync_participant_course_access() from public;
revoke all on function public.m_remove_course_modules() from public;

-- Ordered learning paths and assessment attempt rules.
alter table public.m_assessments
  add column if not exists sequence_number integer not null default 1 check (sequence_number > 0),
  add column if not exists max_attempts integer default 1 check (max_attempts is null or max_attempts > 0);

create or replace function public.m_module_complete_for(target_participant uuid, target_module uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(select 1 from public.m_modules where id = target_module)
    and (
      exists(select 1 from public.m_module_resources where module_id = target_module and required)
      or exists(select 1 from public.m_assessments where module_id = target_module and published)
    )
    and not exists(
      select 1 from public.m_module_resources resource
      where resource.module_id = target_module and resource.required
        and not exists(
          select 1 from public.m_resource_progress progress
          where progress.participant_id = target_participant and progress.resource_id = resource.id
        )
    )
    and not exists(
      select 1 from public.m_assessments assessment
      where assessment.module_id = target_module and assessment.published
        and not exists(
          select 1 from public.m_assessment_submissions submission
          where submission.participant_id = target_participant
            and submission.assessment_id = assessment.id
            and submission.passed
        )
    )
$$;

create or replace function public.m_participant_can_open_module(target_module uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.m_modules current_module
    join public.m_module_assignments current_assignment on current_assignment.module_id = current_module.id
    where current_module.id = target_module
      and current_module.published
      and current_assignment.participant_id = public.m_participant_id()
      and not exists(
        select 1
        from public.m_modules earlier_module
        join public.m_module_assignments earlier_assignment on earlier_assignment.module_id = earlier_module.id
        where earlier_module.course_id = current_module.course_id
          and earlier_module.published
          and earlier_assignment.participant_id = public.m_participant_id()
          and (earlier_module.sequence_number < current_module.sequence_number
            or (earlier_module.sequence_number = current_module.sequence_number and earlier_module.created_at < current_module.created_at))
          and not public.m_module_complete_for(public.m_participant_id(), earlier_module.id)
      )
  )
$$;

create or replace function public.m_can_access_module(target_module uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.m_is_admin() then true
    when not public.m_is_active_member() then false
    when public.m_current_role() = 'participant'::public.m_role then public.m_participant_can_open_module(target_module)
    else exists(select 1 from public.m_modules where id = target_module and published)
  end
$$;

create or replace function public.m_can_start_assessment(target_assessment uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1 from public.m_assessments current_assessment
    where current_assessment.id = target_assessment
      and current_assessment.published
      and public.m_can_access_module(current_assessment.module_id)
      and not exists(
        select 1 from public.m_module_resources resource
        where resource.module_id = current_assessment.module_id and resource.required
          and not exists(
            select 1 from public.m_resource_progress progress
            where progress.participant_id = public.m_participant_id() and progress.resource_id = resource.id
          )
      )
      and not exists(
        select 1 from public.m_assessments earlier_assessment
        where earlier_assessment.module_id = current_assessment.module_id
          and earlier_assessment.published
          and (earlier_assessment.sequence_number < current_assessment.sequence_number
            or (earlier_assessment.sequence_number = current_assessment.sequence_number and earlier_assessment.created_at < current_assessment.created_at))
          and not exists(
            select 1 from public.m_assessment_submissions submission
            where submission.participant_id = public.m_participant_id()
              and submission.assessment_id = earlier_assessment.id
              and submission.passed
          )
      )
  )
$$;

create or replace function public.m_course_path(target_course uuid)
returns table(
  module_id uuid,
  title text,
  description text,
  sequence_number integer,
  locked boolean,
  completed boolean,
  resource_count bigint,
  completed_resource_count bigint,
  assessment_count bigint,
  passed_assessment_count bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select module.id,
         module.title,
         module.description,
         module.sequence_number,
         not public.m_participant_can_open_module(module.id),
         public.m_module_complete_for(public.m_participant_id(), module.id),
         (select count(*) from public.m_module_resources resource where resource.module_id = module.id and resource.required),
         (select count(*) from public.m_module_resources resource join public.m_resource_progress progress on progress.resource_id = resource.id and progress.participant_id = public.m_participant_id() where resource.module_id = module.id and resource.required),
         (select count(*) from public.m_assessments assessment where assessment.module_id = module.id and assessment.published),
         (select count(distinct assessment.id) from public.m_assessments assessment join public.m_assessment_submissions submission on submission.assessment_id = assessment.id and submission.participant_id = public.m_participant_id() and submission.passed where assessment.module_id = module.id and assessment.published)
  from public.m_modules module
  join public.m_module_assignments assignment on assignment.module_id = module.id
  where module.course_id = target_course
    and module.published
    and assignment.participant_id = public.m_participant_id()
  order by module.sequence_number, module.created_at
$$;

revoke all on function public.m_module_complete_for(uuid,uuid) from public;
revoke all on function public.m_participant_can_open_module(uuid) from public;
revoke all on function public.m_can_start_assessment(uuid) from public;
revoke all on function public.m_course_path(uuid) from public;
grant execute on function public.m_module_complete_for(uuid,uuid) to authenticated;
grant execute on function public.m_participant_can_open_module(uuid) to authenticated;
grant execute on function public.m_can_start_assessment(uuid) to authenticated;
grant execute on function public.m_course_path(uuid) to authenticated;

create or replace function public.m_submit_assessment(target_assessment uuid, submitted_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  participant_uuid uuid;
  assessment_record public.m_assessments%rowtype;
  question_record record;
  answer_value jsonb;
  total_points numeric := 0;
  automatic_points numeric := 0;
  earned_points numeric := 0;
  contains_manual boolean := false;
  calculated_auto_score numeric;
  calculated_final_score numeric;
  submission_uuid uuid;
  previous_attempts integer;
begin
  participant_uuid := public.m_participant_id();
  if participant_uuid is null then raise exception 'A participant profile is required.'; end if;
  select * into assessment_record from public.m_assessments where id = target_assessment and published;
  if assessment_record.id is null or not public.m_can_start_assessment(target_assessment) then raise exception 'Complete the required learning items and earlier assessments first.'; end if;
  if submitted_answers is null or jsonb_typeof(submitted_answers) <> 'object' then raise exception 'Assessment answers are required.'; end if;

  select count(*) into previous_attempts from public.m_assessment_submissions
  where assessment_id = target_assessment and participant_id = participant_uuid;
  if assessment_record.max_attempts is not null and previous_attempts >= assessment_record.max_attempts then
    raise exception 'You have reached the maximum number of attempts for this assessment.';
  end if;

  for question_record in
    select question.*, answer_key.correct_answer
    from public.m_assessment_questions question
    left join public.m_assessment_keys answer_key on answer_key.question_id = question.id
    where question.assessment_id = target_assessment
    order by question.sequence_number, question.created_at
  loop
    answer_value := submitted_answers -> question_record.id::text;
    if question_record.required and (answer_value is null or answer_value = 'null'::jsonb or answer_value = '""'::jsonb or answer_value = '[]'::jsonb) then
      raise exception 'Please answer every required question.';
    end if;
    total_points := total_points + question_record.points;
    if question_record.question_type in ('multiple_choice', 'checkboxes') then
      automatic_points := automatic_points + question_record.points;
      if answer_value = question_record.correct_answer then earned_points := earned_points + question_record.points; end if;
    else
      contains_manual := true;
    end if;
  end loop;

  if total_points = 0 then raise exception 'This assessment has no questions.'; end if;
  calculated_auto_score := case when automatic_points > 0 then round(earned_points / automatic_points * 100, 2) else null end;
  calculated_final_score := case when contains_manual then null else round(earned_points / total_points * 100, 2) end;

  insert into public.m_assessment_submissions(assessment_id, participant_id, answers, status, auto_score, final_score, passed, graded_by, graded_at)
  values (target_assessment, participant_uuid, submitted_answers, case when contains_manual then 'submitted' else 'graded' end, calculated_auto_score, calculated_final_score, case when contains_manual then null else calculated_final_score >= assessment_record.pass_mark end, case when contains_manual then null else auth.uid() end, case when contains_manual then null else now() end)
  returning id into submission_uuid;

  return jsonb_build_object('submission_id', submission_uuid, 'status', case when contains_manual then 'submitted' else 'graded' end, 'auto_score', calculated_auto_score, 'final_score', calculated_final_score, 'passed', case when contains_manual then null else calculated_final_score >= assessment_record.pass_mark end, 'attempt_number', previous_attempts + 1);
end;
$$;

revoke all on function public.m_submit_assessment(uuid,jsonb) from public;
grant execute on function public.m_submit_assessment(uuid,jsonb) to authenticated;

-- Intentionally no demonstration participants, courses, assessments or business records are inserted.
