-- eKelas Usahawan cohort onboarding and assessment workspace
-- Run after 001_m_foundation.sql and 002_admin_learning_attendance.sql.
-- No demonstration data is inserted.

create table if not exists public.m_signup_codes (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid not null references public.m_cohorts(id) on delete cascade,
  code_digest bytea not null unique,
  code_hint text not null,
  expires_at timestamptz,
  max_uses integer check (max_uses is null or max_uses > 0),
  used_count integer not null default 0 check (used_count >= 0),
  active boolean not null default true,
  created_by uuid references public.m_memberships(user_id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists m_signup_codes_cohort_idx
  on public.m_signup_codes(cohort_id, active, expires_at);

alter table public.m_signup_codes enable row level security;
revoke all on table public.m_signup_codes from anon;
grant select, insert, update, delete on table public.m_signup_codes to authenticated;

drop policy if exists m_signup_codes_admin_select on public.m_signup_codes;
create policy m_signup_codes_admin_select on public.m_signup_codes for select to authenticated
using (public.m_is_admin());
drop policy if exists m_signup_codes_admin_insert on public.m_signup_codes;
create policy m_signup_codes_admin_insert on public.m_signup_codes for insert to authenticated
with check (public.m_is_admin());
drop policy if exists m_signup_codes_admin_update on public.m_signup_codes;
create policy m_signup_codes_admin_update on public.m_signup_codes for update to authenticated
using (public.m_is_admin()) with check (public.m_is_admin());
drop policy if exists m_signup_codes_admin_delete on public.m_signup_codes;
create policy m_signup_codes_admin_delete on public.m_signup_codes for delete to authenticated
using (public.m_is_admin());

create or replace function public.m_create_signup_code(
  target_cohort uuid,
  valid_until timestamptz default (now() + interval '30 days'),
  allowed_uses integer default 100
)
returns table(signup_code text, code_id uuid, code_hint text, expires_at timestamptz, max_uses integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw_code text;
  created_id uuid;
begin
  if not public.m_is_admin() then
    raise exception 'Only an administrator can generate cohort codes.';
  end if;
  if not exists(select 1 from public.m_cohorts where id = target_cohort and active) then
    raise exception 'Select an active cohort.';
  end if;
  if valid_until is not null and valid_until <= now() then
    raise exception 'The expiry must be in the future.';
  end if;
  if allowed_uses is not null and allowed_uses < 1 then
    raise exception 'Allowed uses must be at least one.';
  end if;

  loop
    raw_code := 'EKU-' || upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 12));
    begin
      insert into public.m_signup_codes (
        cohort_id, code_digest, code_hint, expires_at, max_uses, created_by
      ) values (
        target_cohort,
        extensions.digest(raw_code, 'sha256'),
        right(raw_code, 4),
        valid_until,
        allowed_uses,
        auth.uid()
      ) returning id into created_id;
      exit;
    exception when unique_violation then
      -- Extremely unlikely, but generate a fresh code rather than fail.
    end;
  end loop;

  return query select raw_code, created_id, right(raw_code, 4), valid_until, allowed_uses;
end;
$$;

create or replace function public.m_validate_signup_code(raw_code text)
returns table(cohort_id uuid, cohort_name text, programme_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select cohort.id, cohort.name, programme.name
  from public.m_signup_codes signup
  join public.m_cohorts cohort on cohort.id = signup.cohort_id and cohort.active
  join public.m_programmes programme on programme.id = cohort.programme_id and programme.active
  where signup.code_digest = extensions.digest(upper(btrim(raw_code)), 'sha256')
    and signup.active
    and (signup.expires_at is null or signup.expires_at > now())
    and (signup.max_uses is null or signup.used_count < signup.max_uses)
  limit 1
$$;

create or replace function public.m_handle_signup_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw_code text;
  display_name text;
  selected_code public.m_signup_codes%rowtype;
begin
  raw_code := upper(btrim(coalesce(new.raw_user_meta_data ->> 'signup_code', '')));
  if raw_code = '' then
    return new;
  end if;

  select * into selected_code
  from public.m_signup_codes signup
  where signup.code_digest = extensions.digest(raw_code, 'sha256')
    and signup.active
    and (signup.expires_at is null or signup.expires_at > now())
    and (signup.max_uses is null or signup.used_count < signup.max_uses)
  for update;

  if selected_code.id is null then
    raise exception 'This cohort code is invalid, expired or has reached its limit.';
  end if;

  display_name := btrim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  if char_length(display_name) < 2 then
    raise exception 'A full name is required.';
  end if;

  insert into public.m_memberships(user_id, display_name, role, active)
  values (new.id, display_name, 'participant'::public.m_role, true)
  on conflict (user_id) do update
    set display_name = excluded.display_name,
        role = 'participant'::public.m_role,
        active = true;

  insert into public.m_participants(
    user_id, cohort_id, full_name, business_name, email, state, active
  ) values (
    new.id,
    selected_code.cohort_id,
    display_name,
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'business_name', '')), ''),
    new.email,
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'state', '')), ''),
    true
  ) on conflict (user_id) do update
    set cohort_id = excluded.cohort_id,
        full_name = excluded.full_name,
        business_name = excluded.business_name,
        email = excluded.email,
        state = excluded.state,
        active = true;

  update public.m_signup_codes
  set used_count = used_count + 1
  where id = selected_code.id;

  return new;
end;
$$;

drop trigger if exists m_auth_signup_code on auth.users;
create trigger m_auth_signup_code
after insert on auth.users
for each row execute function public.m_handle_signup_code();

revoke all on function public.m_create_signup_code(uuid, timestamptz, integer) from public;
revoke all on function public.m_validate_signup_code(text) from public;
revoke all on function public.m_handle_signup_code() from public;
grant execute on function public.m_create_signup_code(uuid, timestamptz, integer) to authenticated;
grant execute on function public.m_validate_signup_code(text) to anon, authenticated;

-- A course assignment remains valid when an administrator adds future modules.
create table if not exists public.m_course_assignments (
  participant_id uuid not null references public.m_participants(id) on delete cascade,
  course_id uuid not null references public.m_courses(id) on delete cascade,
  assigned_by uuid references public.m_memberships(user_id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (participant_id, course_id)
);

create index if not exists m_course_assignments_course_idx
  on public.m_course_assignments(course_id, participant_id);

alter table public.m_course_assignments enable row level security;
revoke all on table public.m_course_assignments from anon;
grant select, insert, update, delete on table public.m_course_assignments to authenticated;

drop policy if exists m_course_assignments_select on public.m_course_assignments;
create policy m_course_assignments_select on public.m_course_assignments for select to authenticated
using (participant_id = public.m_participant_id() or public.m_can_access_participant(participant_id));
drop policy if exists m_course_assignments_admin_insert on public.m_course_assignments;
create policy m_course_assignments_admin_insert on public.m_course_assignments for insert to authenticated
with check (public.m_is_admin());
drop policy if exists m_course_assignments_admin_delete on public.m_course_assignments;
create policy m_course_assignments_admin_delete on public.m_course_assignments for delete to authenticated
using (public.m_is_admin());

create or replace function public.m_apply_course_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.m_module_assignments(participant_id, module_id, assigned_by)
  select new.participant_id, module.id, new.assigned_by
  from public.m_modules module
  where module.course_id = new.course_id
  on conflict (participant_id, module_id) do nothing;
  return new;
end;
$$;

create or replace function public.m_apply_new_course_module()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.course_id is not null then
    insert into public.m_module_assignments(participant_id, module_id, assigned_by)
    select assignment.participant_id, new.id, assignment.assigned_by
    from public.m_course_assignments assignment
    where assignment.course_id = new.course_id
    on conflict (participant_id, module_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists m_course_assignment_modules on public.m_course_assignments;
create trigger m_course_assignment_modules
after insert on public.m_course_assignments
for each row execute function public.m_apply_course_assignment();

drop trigger if exists m_new_course_module_assignments on public.m_modules;
create trigger m_new_course_module_assignments
after insert on public.m_modules
for each row execute function public.m_apply_new_course_module();

revoke all on function public.m_apply_course_assignment() from public;
revoke all on function public.m_apply_new_course_module() from public;

-- Participants can discover only courses assigned to their profile.
create or replace function public.m_can_access_course(target_course uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.m_is_admin() then true
    when not public.m_is_active_member() then false
    when public.m_current_role() = 'participant'::public.m_role then exists(
      select 1 from public.m_course_assignments assignment
      where assignment.course_id = target_course
        and assignment.participant_id = public.m_participant_id()
    ) or exists(
      select 1 from public.m_modules module
      join public.m_module_assignments assignment on assignment.module_id = module.id
      where module.course_id = target_course
        and assignment.participant_id = public.m_participant_id()
    )
    else true
  end
$$;

revoke all on function public.m_can_access_course(uuid) from public;
grant execute on function public.m_can_access_course(uuid) to authenticated;

drop policy if exists m_courses_select on public.m_courses;
create policy m_courses_select on public.m_courses for select to authenticated
using (public.m_can_access_course(id));

create table if not exists public.m_assessments (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.m_modules(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 180),
  description text,
  grading_mode text not null default 'automatic' check (grading_mode in ('automatic', 'mentor', 'mixed')),
  pass_mark numeric(5,2) not null default 70 check (pass_mark between 0 and 100),
  published boolean not null default false,
  created_by uuid references public.m_memberships(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.m_assessment_questions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.m_assessments(id) on delete cascade,
  prompt text not null check (char_length(prompt) between 2 and 2000),
  question_type text not null check (question_type in ('multiple_choice', 'checkboxes', 'short_text', 'long_text', 'file_url')),
  options jsonb,
  required boolean not null default true,
  points numeric(8,2) not null default 1 check (points > 0),
  sequence_number integer not null default 1 check (sequence_number > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (question_type in ('multiple_choice', 'checkboxes') and jsonb_typeof(options) = 'array' and jsonb_array_length(options) between 2 and 20)
    or (question_type in ('short_text', 'long_text', 'file_url') and options is null)
  )
);

-- Answer keys remain in a separate admin-only table.
create table if not exists public.m_assessment_keys (
  question_id uuid primary key references public.m_assessment_questions(id) on delete cascade,
  correct_answer jsonb not null,
  explanation text
);

create table if not exists public.m_assessment_submissions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.m_assessments(id) on delete cascade,
  participant_id uuid not null references public.m_participants(id) on delete cascade,
  answers jsonb not null check (jsonb_typeof(answers) = 'object'),
  status text not null default 'submitted' check (status in ('submitted', 'graded')),
  auto_score numeric(5,2) check (auto_score is null or auto_score between 0 and 100),
  final_score numeric(5,2) check (final_score is null or final_score between 0 and 100),
  passed boolean,
  feedback text,
  submitted_at timestamptz not null default now(),
  graded_by uuid references public.m_memberships(user_id) on delete set null,
  graded_at timestamptz
);

create table if not exists public.m_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.m_memberships(user_id) on delete cascade,
  kind text not null,
  title text not null,
  body text,
  entity_type text,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists m_assessments_module_idx on public.m_assessments(module_id, published);
create index if not exists m_assessment_questions_idx on public.m_assessment_questions(assessment_id, sequence_number);
create index if not exists m_assessment_submissions_idx on public.m_assessment_submissions(assessment_id, participant_id, submitted_at desc);
create index if not exists m_notifications_user_idx on public.m_notifications(user_id, read_at, created_at desc);

drop trigger if exists m_assessments_touch on public.m_assessments;
create trigger m_assessments_touch before update on public.m_assessments
for each row execute function public.m_touch_updated_at();
drop trigger if exists m_assessment_questions_touch on public.m_assessment_questions;
create trigger m_assessment_questions_touch before update on public.m_assessment_questions
for each row execute function public.m_touch_updated_at();

alter table public.m_assessments enable row level security;
alter table public.m_assessment_questions enable row level security;
alter table public.m_assessment_keys enable row level security;
alter table public.m_assessment_submissions enable row level security;
alter table public.m_notifications enable row level security;

revoke all on table
  public.m_assessments, public.m_assessment_questions, public.m_assessment_keys,
  public.m_assessment_submissions, public.m_notifications
from anon;
grant select, insert, update, delete on table
  public.m_assessments, public.m_assessment_questions, public.m_assessment_keys,
  public.m_assessment_submissions, public.m_notifications
to authenticated;

drop policy if exists m_assessments_select on public.m_assessments;
create policy m_assessments_select on public.m_assessments for select to authenticated
using (public.m_can_access_module(module_id));
drop policy if exists m_assessments_admin_insert on public.m_assessments;
create policy m_assessments_admin_insert on public.m_assessments for insert to authenticated
with check (public.m_is_admin());
drop policy if exists m_assessments_admin_update on public.m_assessments;
create policy m_assessments_admin_update on public.m_assessments for update to authenticated
using (public.m_is_admin()) with check (public.m_is_admin());
drop policy if exists m_assessments_admin_delete on public.m_assessments;
create policy m_assessments_admin_delete on public.m_assessments for delete to authenticated
using (public.m_is_admin());

drop policy if exists m_assessment_questions_select on public.m_assessment_questions;
create policy m_assessment_questions_select on public.m_assessment_questions for select to authenticated
using (exists(
  select 1 from public.m_assessments assessment
  where assessment.id = assessment_id and public.m_can_access_module(assessment.module_id)
));
drop policy if exists m_assessment_questions_admin_insert on public.m_assessment_questions;
create policy m_assessment_questions_admin_insert on public.m_assessment_questions for insert to authenticated
with check (public.m_is_admin());
drop policy if exists m_assessment_questions_admin_update on public.m_assessment_questions;
create policy m_assessment_questions_admin_update on public.m_assessment_questions for update to authenticated
using (public.m_is_admin()) with check (public.m_is_admin());
drop policy if exists m_assessment_questions_admin_delete on public.m_assessment_questions;
create policy m_assessment_questions_admin_delete on public.m_assessment_questions for delete to authenticated
using (public.m_is_admin());

drop policy if exists m_assessment_keys_admin_select on public.m_assessment_keys;
create policy m_assessment_keys_admin_select on public.m_assessment_keys for select to authenticated
using (public.m_is_admin());
drop policy if exists m_assessment_keys_admin_insert on public.m_assessment_keys;
create policy m_assessment_keys_admin_insert on public.m_assessment_keys for insert to authenticated
with check (public.m_is_admin());
drop policy if exists m_assessment_keys_admin_update on public.m_assessment_keys;
create policy m_assessment_keys_admin_update on public.m_assessment_keys for update to authenticated
using (public.m_is_admin()) with check (public.m_is_admin());
drop policy if exists m_assessment_keys_admin_delete on public.m_assessment_keys;
create policy m_assessment_keys_admin_delete on public.m_assessment_keys for delete to authenticated
using (public.m_is_admin());

drop policy if exists m_assessment_submissions_select on public.m_assessment_submissions;
create policy m_assessment_submissions_select on public.m_assessment_submissions for select to authenticated
using (
  participant_id = public.m_participant_id()
  or public.m_is_admin()
  or (
    public.m_current_role() = 'mentor'::public.m_role
    and exists(
      select 1 from public.m_participants participant
      where participant.id = participant_id
        and participant.mentor_user_id = (select auth.uid())
    )
  )
);

drop policy if exists m_notifications_select on public.m_notifications;
create policy m_notifications_select on public.m_notifications for select to authenticated
using (user_id = (select auth.uid()));
drop policy if exists m_notifications_update on public.m_notifications;
create policy m_notifications_update on public.m_notifications for update to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

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
begin
  participant_uuid := public.m_participant_id();
  if participant_uuid is null then
    raise exception 'A participant profile is required.';
  end if;

  select * into assessment_record
  from public.m_assessments
  where id = target_assessment and published;
  if assessment_record.id is null or not public.m_can_access_module(assessment_record.module_id) then
    raise exception 'This assessment is not available to your account.';
  end if;
  if submitted_answers is null or jsonb_typeof(submitted_answers) <> 'object' then
    raise exception 'Assessment answers are required.';
  end if;

  for question_record in
    select question.*, answer_key.correct_answer
    from public.m_assessment_questions question
    left join public.m_assessment_keys answer_key on answer_key.question_id = question.id
    where question.assessment_id = target_assessment
    order by question.sequence_number, question.created_at
  loop
    answer_value := submitted_answers -> question_record.id::text;
    if question_record.required and (
      answer_value is null or answer_value = 'null'::jsonb or answer_value = '""'::jsonb or answer_value = '[]'::jsonb
    ) then
      raise exception 'Please answer every required question.';
    end if;
    total_points := total_points + question_record.points;
    if question_record.question_type in ('multiple_choice', 'checkboxes') then
      automatic_points := automatic_points + question_record.points;
      if answer_value = question_record.correct_answer then
        earned_points := earned_points + question_record.points;
      end if;
    else
      contains_manual := true;
    end if;
  end loop;

  if total_points = 0 then
    raise exception 'This assessment has no questions.';
  end if;
  calculated_auto_score := case when automatic_points > 0 then round(earned_points / automatic_points * 100, 2) else null end;
  calculated_final_score := case when contains_manual then null else round(earned_points / total_points * 100, 2) end;

  insert into public.m_assessment_submissions(
    assessment_id, participant_id, answers, status, auto_score, final_score, passed,
    graded_by, graded_at
  ) values (
    target_assessment,
    participant_uuid,
    submitted_answers,
    case when contains_manual then 'submitted' else 'graded' end,
    calculated_auto_score,
    calculated_final_score,
    case when contains_manual then null else calculated_final_score >= assessment_record.pass_mark end,
    case when contains_manual then null else auth.uid() end,
    case when contains_manual then null else now() end
  ) returning id into submission_uuid;

  return jsonb_build_object(
    'submission_id', submission_uuid,
    'status', case when contains_manual then 'submitted' else 'graded' end,
    'auto_score', calculated_auto_score,
    'final_score', calculated_final_score,
    'passed', case when contains_manual then null else calculated_final_score >= assessment_record.pass_mark end
  );
end;
$$;

create or replace function public.m_grade_submission(target_submission uuid, grade_score numeric, grade_feedback text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  submission_record public.m_assessment_submissions%rowtype;
  assessment_record public.m_assessments%rowtype;
  participant_record public.m_participants%rowtype;
begin
  if grade_score < 0 or grade_score > 100 then
    raise exception 'The final score must be between 0 and 100.';
  end if;

  select * into submission_record from public.m_assessment_submissions where id = target_submission;
  if submission_record.id is null then raise exception 'Submission not found.'; end if;
  select * into participant_record from public.m_participants where id = submission_record.participant_id;
  if not public.m_is_admin() and not (
    public.m_current_role() = 'mentor'::public.m_role
    and participant_record.mentor_user_id = auth.uid()
  ) then
    raise exception 'You are not assigned to grade this participant.';
  end if;
  select * into assessment_record from public.m_assessments where id = submission_record.assessment_id;

  update public.m_assessment_submissions
  set status = 'graded',
      final_score = grade_score,
      passed = grade_score >= assessment_record.pass_mark,
      feedback = nullif(btrim(coalesce(grade_feedback, '')), ''),
      graded_by = auth.uid(),
      graded_at = now()
  where id = target_submission;

  if participant_record.user_id is not null then
    insert into public.m_notifications(user_id, kind, title, body, entity_type, entity_id)
    values (
      participant_record.user_id,
      'assessment_graded',
      'Your assessment has been graded',
      assessment_record.title,
      'assessment_submission',
      target_submission
    );
  end if;

  return jsonb_build_object(
    'submission_id', target_submission,
    'status', 'graded',
    'final_score', grade_score,
    'passed', grade_score >= assessment_record.pass_mark
  );
end;
$$;

create or replace function public.m_notify_assignment_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  mentor_uuid uuid;
  participant_name text;
  assessment_title text;
begin
  if new.status <> 'submitted' then return new; end if;
  select participant.mentor_user_id, participant.full_name
    into mentor_uuid, participant_name
  from public.m_participants participant where participant.id = new.participant_id;
  if mentor_uuid is null then return new; end if;
  select title into assessment_title from public.m_assessments where id = new.assessment_id;
  insert into public.m_notifications(user_id, kind, title, body, entity_type, entity_id)
  values (
    mentor_uuid,
    'assignment_submitted',
    'Assignment ready for grading',
    participant_name || ' submitted ' || assessment_title,
    'assessment_submission',
    new.id
  );
  return new;
end;
$$;

drop trigger if exists m_assignment_submission_notification on public.m_assessment_submissions;
create trigger m_assignment_submission_notification
after insert on public.m_assessment_submissions
for each row execute function public.m_notify_assignment_submission();

revoke all on function public.m_submit_assessment(uuid, jsonb) from public;
revoke all on function public.m_grade_submission(uuid, numeric, text) from public;
revoke all on function public.m_notify_assignment_submission() from public;
grant execute on function public.m_submit_assessment(uuid, jsonb) to authenticated;
grant execute on function public.m_grade_submission(uuid, numeric, text) to authenticated;

-- Intentionally no INSERT statements follow. Existing and new installations remain free of dummy data.
