-- eKelas Usahawan learning player
-- Run after 005_dashboard_privacy.sql. Idempotent. No learning records are removed, and existing
-- items keep their current order (learning content first, then assessments).
--
-- 1. Free item order: videos, readings, workbooks and assessments share one position sequence per
--    module (item_position). Each required item must be finished before the next one opens.
-- 2. Item details for the player: duration, points, transcript and downloadable file links.
-- 3. Timed assessments: the database records each attempt's start and deadline. Questions are only
--    readable during an open attempt, late submissions are rejected, and a submission made as time
--    runs out is accepted with unanswered questions scored as zero. Due dates are shown, not enforced.
-- 4. m_course_outline() returns a participant's whole course (status, locks, scores, points) in one call.

-- 1. Item settings ---------------------------------------------------------------------------------
alter table public.m_module_resources
  add column if not exists item_position integer,
  add column if not exists duration_minutes integer,
  add column if not exists points integer not null default 10,
  add column if not exists transcript text,
  add column if not exists files jsonb not null default '[]'::jsonb;

alter table public.m_assessments
  add column if not exists item_position integer,
  add column if not exists time_limit_minutes integer,
  add column if not exists due_at timestamptz,
  add column if not exists points integer not null default 20;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'm_module_resources_player_check') then
    alter table public.m_module_resources add constraint m_module_resources_player_check check (
      (duration_minutes is null or duration_minutes between 1 and 600)
      and points between 0 and 1000
      and (transcript is null or char_length(transcript) <= 100000)
      and jsonb_typeof(files) = 'array' and jsonb_array_length(files) <= 20);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'm_assessments_player_check') then
    alter table public.m_assessments add constraint m_assessments_player_check check (
      (time_limit_minutes is null or time_limit_minutes between 1 and 600)
      and points between 0 and 1000);
  end if;
end
$$;

-- Give unpositioned items a place after any positioned ones: content first, then assessments.
update public.m_module_resources resource
set item_position = numbered.position
from (
  select r.id,
    coalesce((select max(p) from (
      select item_position p from public.m_module_resources x where x.module_id = r.module_id
      union all select item_position from public.m_assessments y where y.module_id = r.module_id) existing), 0)
    + row_number() over (partition by r.module_id order by r.sequence_number, r.created_at, r.id) as position
  from public.m_module_resources r
  where r.item_position is null
) numbered
where resource.id = numbered.id;

update public.m_assessments assessment
set item_position = numbered.position
from (
  select a.id,
    coalesce((select max(p) from (
      select item_position p from public.m_module_resources x where x.module_id = a.module_id
      union all select item_position from public.m_assessments y where y.module_id = a.module_id) existing), 0)
    + row_number() over (partition by a.module_id order by a.sequence_number, a.created_at, a.id) as position
  from public.m_assessments a
  where a.item_position is null
) numbered
where assessment.id = numbered.id;

-- New items are appended to the end of their module.
create or replace function public.m_set_item_position()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.item_position is null then
    select coalesce(max(p), 0) + 1 into new.item_position from (
      select item_position p from public.m_module_resources where module_id = new.module_id
      union all select item_position from public.m_assessments where module_id = new.module_id) existing;
  end if;
  return new;
end;
$$;

drop trigger if exists m_module_resources_position on public.m_module_resources;
create trigger m_module_resources_position before insert on public.m_module_resources
for each row execute function public.m_set_item_position();
drop trigger if exists m_assessments_position on public.m_assessments;
create trigger m_assessments_position before insert on public.m_assessments
for each row execute function public.m_set_item_position();

alter table public.m_module_resources alter column item_position set not null;
alter table public.m_assessments alter column item_position set not null;

-- 2. Ordering and unlocking helpers ----------------------------------------------------------------
create or replace function public.m_module_items(target_module uuid, include_drafts boolean default false)
returns table(item_kind text, item_id uuid, ordinal bigint, blocking boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select item.kind, item.id,
         row_number() over (order by item.item_position, item.kind_rank, item.created_at, item.id),
         item.blocking
  from (
    select 'resource'::text as kind, r.id, r.item_position, 0 as kind_rank, r.created_at, r.required as blocking
    from public.m_module_resources r
    where r.module_id = target_module
    union all
    select 'assessment'::text, a.id, a.item_position, 1, a.created_at, true
    from public.m_assessments a
    where a.module_id = target_module and (a.published or include_drafts)
  ) item
$$;

create or replace function public.m_item_done(target_participant uuid, target_kind text, target_item uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when target_kind = 'resource' then exists(
      select 1 from public.m_resource_progress progress
      where progress.participant_id = target_participant and progress.resource_id = target_item)
    else exists(
      select 1 from public.m_assessment_submissions submission
      where submission.participant_id = target_participant and submission.assessment_id = target_item and submission.passed)
  end
$$;

-- True when the calling participant may open this item: its module is open and every earlier
-- required item in the module is finished (content completed, assessments passed).
create or replace function public.m_item_unlocked(target_kind text, target_item uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with target as (
    select r.module_id from public.m_module_resources r where target_kind = 'resource' and r.id = target_item
    union all
    select a.module_id from public.m_assessments a where target_kind = 'assessment' and a.id = target_item and a.published
  ),
  items as (
    select i.* from target t cross join lateral public.m_module_items(t.module_id) i
  )
  select exists(select 1 from target t where public.m_participant_can_open_module(t.module_id))
    and not exists(
      select 1
      from items earlier
      join items current_item on current_item.item_kind = target_kind and current_item.item_id = target_item
      where earlier.ordinal < current_item.ordinal
        and earlier.blocking
        and not public.m_item_done(public.m_participant_id(), earlier.item_kind, earlier.item_id))
$$;

create or replace function public.m_can_start_assessment(target_assessment uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(select 1 from public.m_assessments where id = target_assessment and published)
    and public.m_item_unlocked('assessment', target_assessment)
$$;

-- 3. Timed attempts --------------------------------------------------------------------------------
create table if not exists public.m_assessment_attempts (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.m_assessments(id) on delete cascade,
  participant_id uuid not null references public.m_participants(id) on delete cascade,
  started_at timestamptz not null default now(),
  deadline_at timestamptz,
  submission_id uuid references public.m_assessment_submissions(id) on delete set null,
  closed_at timestamptz
);

create unique index if not exists m_assessment_attempts_open_idx
  on public.m_assessment_attempts(assessment_id, participant_id) where closed_at is null;

alter table public.m_assessment_attempts enable row level security;
revoke all on table public.m_assessment_attempts from anon;
revoke insert, update, delete on table public.m_assessment_attempts from authenticated;
grant select on table public.m_assessment_attempts to authenticated;

drop policy if exists m_assessment_attempts_select on public.m_assessment_attempts;
create policy m_assessment_attempts_select on public.m_assessment_attempts for select to authenticated
using (participant_id = public.m_participant_id() or public.m_can_access_participant(participant_id));

-- Submissions plus timed attempts that ran out without being submitted (2-minute network grace).
create or replace function public.m_attempts_used(target_participant uuid, target_assessment uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select ((select count(*) from public.m_assessment_submissions s
           where s.participant_id = target_participant and s.assessment_id = target_assessment)
        + (select count(*) from public.m_assessment_attempts attempt
           where attempt.participant_id = target_participant and attempt.assessment_id = target_assessment
             and attempt.submission_id is null and attempt.deadline_at is not null
             and attempt.deadline_at + interval '2 minutes' < now()))::integer
$$;

create or replace function public.m_start_assessment(target_assessment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  participant_uuid uuid := public.m_participant_id();
  assessment_record public.m_assessments%rowtype;
  attempt_record public.m_assessment_attempts%rowtype;
begin
  if participant_uuid is null then raise exception 'A participant profile is required.'; end if;
  select * into assessment_record from public.m_assessments where id = target_assessment and published;
  if assessment_record.id is null or not public.m_can_start_assessment(target_assessment) then
    raise exception 'Finish the earlier items in this module first.';
  end if;

  select * into attempt_record from public.m_assessment_attempts
  where assessment_id = target_assessment and participant_id = participant_uuid and closed_at is null
  for update;

  if attempt_record.id is not null then
    -- Reuse an open attempt unless it has expired, or the assessment became timed after it started.
    if (attempt_record.deadline_at is null and assessment_record.time_limit_minutes is null)
       or (attempt_record.deadline_at is not null and attempt_record.deadline_at + interval '2 minutes' > now()) then
      return jsonb_build_object('attempt_id', attempt_record.id, 'started_at', attempt_record.started_at,
        'deadline_at', attempt_record.deadline_at, 'server_now', now(), 'resumed', true);
    end if;
    update public.m_assessment_attempts set closed_at = now() where id = attempt_record.id;
  end if;

  if assessment_record.max_attempts is not null
     and public.m_attempts_used(participant_uuid, target_assessment) >= assessment_record.max_attempts then
    raise exception 'You have used every attempt for this assessment.';
  end if;

  insert into public.m_assessment_attempts(assessment_id, participant_id, deadline_at)
  values (target_assessment, participant_uuid,
    case when assessment_record.time_limit_minutes is null then null
         else now() + make_interval(mins => assessment_record.time_limit_minutes) end)
  returning * into attempt_record;

  return jsonb_build_object('attempt_id', attempt_record.id, 'started_at', attempt_record.started_at,
    'deadline_at', attempt_record.deadline_at, 'server_now', now(), 'resumed', false);
end;
$$;

-- Same grading as 004, plus attempt deadlines and the attempt-based limit.
create or replace function public.m_submit_assessment(target_assessment uuid, submitted_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  participant_uuid uuid;
  assessment_record public.m_assessments%rowtype;
  attempt_record public.m_assessment_attempts%rowtype;
  question_record record;
  answer_value jsonb;
  total_points numeric := 0;
  automatic_points numeric := 0;
  earned_points numeric := 0;
  contains_manual boolean := false;
  time_up boolean := false;
  calculated_auto_score numeric;
  calculated_final_score numeric;
  submission_uuid uuid;
  previous_attempts integer;
begin
  participant_uuid := public.m_participant_id();
  if participant_uuid is null then raise exception 'A participant profile is required.'; end if;
  select * into assessment_record from public.m_assessments where id = target_assessment and published;
  if assessment_record.id is null or not public.m_can_start_assessment(target_assessment) then
    raise exception 'Finish the earlier items in this module first.';
  end if;
  if submitted_answers is null or jsonb_typeof(submitted_answers) <> 'object' then
    raise exception 'Assessment answers are required.';
  end if;

  select * into attempt_record from public.m_assessment_attempts
  where assessment_id = target_assessment and participant_id = participant_uuid and closed_at is null
  for update;

  if assessment_record.time_limit_minutes is not null then
    if attempt_record.id is null or attempt_record.deadline_at is null then
      raise exception 'Start the timed assessment before submitting.';
    end if;
    if now() > attempt_record.deadline_at + interval '2 minutes' then
      raise exception 'Time ran out for this attempt. Start a new attempt if you have one left.';
    end if;
    time_up := now() >= attempt_record.deadline_at - interval '5 seconds';
  end if;

  previous_attempts := public.m_attempts_used(participant_uuid, target_assessment);
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
    if question_record.required and not time_up
       and (answer_value is null or answer_value = 'null'::jsonb or answer_value = '""'::jsonb or answer_value = '[]'::jsonb) then
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
  values (target_assessment, participant_uuid, submitted_answers,
    case when contains_manual then 'submitted' else 'graded' end,
    calculated_auto_score, calculated_final_score,
    case when contains_manual then null else calculated_final_score >= assessment_record.pass_mark end,
    case when contains_manual then null else auth.uid() end,
    case when contains_manual then null else now() end)
  returning id into submission_uuid;

  if attempt_record.id is not null then
    update public.m_assessment_attempts set submission_id = submission_uuid, closed_at = now() where id = attempt_record.id;
  end if;

  return jsonb_build_object('submission_id', submission_uuid,
    'status', case when contains_manual then 'submitted' else 'graded' end,
    'auto_score', calculated_auto_score, 'final_score', calculated_final_score,
    'passed', case when contains_manual then null else calculated_final_score >= assessment_record.pass_mark end,
    'attempt_number', previous_attempts + 1, 'time_up', time_up);
end;
$$;

-- Participants read questions only once the assessment is unlocked and, when timed, during an open attempt.
create or replace function public.m_participant_can_read_questions(target_assessment uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.m_can_start_assessment(target_assessment)
    and exists(
      select 1 from public.m_assessments a
      where a.id = target_assessment
        and (a.time_limit_minutes is null or exists(
          select 1 from public.m_assessment_attempts attempt
          where attempt.assessment_id = a.id and attempt.participant_id = public.m_participant_id()
            and attempt.closed_at is null and attempt.deadline_at + interval '2 minutes' > now())))
$$;

-- 4. Row Level Security on locked content ---------------------------------------------------------
drop policy if exists m_resources_select on public.m_module_resources;
create policy m_resources_select on public.m_module_resources for select to authenticated
using (
  public.m_can_access_module(module_id)
  and (public.m_current_role() is distinct from 'participant'::public.m_role or public.m_item_unlocked('resource', id))
);

drop policy if exists m_progress_participant_insert on public.m_resource_progress;
create policy m_progress_participant_insert on public.m_resource_progress for insert to authenticated
with check (participant_id = public.m_participant_id() and public.m_item_unlocked('resource', resource_id));

drop policy if exists m_assessment_questions_select on public.m_assessment_questions;
create policy m_assessment_questions_select on public.m_assessment_questions for select to authenticated
using (exists(
  select 1 from public.m_assessments assessment
  where assessment.id = m_assessment_questions.assessment_id
    and public.m_can_access_module(assessment.module_id)
    and (public.m_current_role() is distinct from 'participant'::public.m_role
         or public.m_participant_can_read_questions(assessment.id))
));

-- 5. Course outline for the participant player ----------------------------------------------------
create or replace function public.m_course_outline(target_course uuid)
returns table(
  module_id uuid, module_title text, module_description text, module_number bigint,
  module_locked boolean, module_completed boolean,
  item_kind text, item_id uuid, item_type text, title text, item_number bigint,
  duration_minutes integer, points integer, required boolean,
  locked boolean, done boolean, done_at timestamptz,
  awaiting_review boolean, best_score numeric, attempts_used integer, max_attempts integer,
  time_limit_minutes integer, due_at timestamptz, pass_mark numeric, question_count bigint,
  has_open_attempt boolean, open_attempt_deadline timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select public.m_participant_id() as pid),
  course_modules as (
    select m.id as module_id, m.title as module_title, m.description as module_description,
           row_number() over (order by m.sequence_number, m.created_at) as module_number,
           not public.m_participant_can_open_module(m.id) as module_locked,
           public.m_module_complete_for((select pid from me), m.id) as module_completed
    from public.m_modules m
    join public.m_module_assignments assignment
      on assignment.module_id = m.id and assignment.participant_id = (select pid from me)
    where m.course_id = target_course and m.published
  ),
  items as (
    select cm.*, i.item_kind, i.item_id, i.ordinal, i.blocking
    from course_modules cm
    cross join lateral public.m_module_items(cm.module_id) i
  ),
  detailed as (
    select it.*,
      coalesce(r.kind::text, a.grading_mode) as item_type,
      coalesce(r.title, a.title) as item_title,
      case when it.item_kind = 'resource' then r.duration_minutes else a.time_limit_minutes end as item_duration,
      coalesce(r.points, a.points) as item_points,
      case when it.item_kind = 'resource' then
        (select p.studied_at from public.m_resource_progress p
         where p.participant_id = (select pid from me) and p.resource_id = it.item_id)
      else
        (select min(coalesce(s.graded_at, s.submitted_at)) from public.m_assessment_submissions s
         where s.participant_id = (select pid from me) and s.assessment_id = it.item_id and s.passed)
      end as finished_at,
      it.item_kind = 'assessment' and exists(
        select 1 from public.m_assessment_submissions s
        where s.participant_id = (select pid from me) and s.assessment_id = it.item_id and s.status = 'submitted') as awaiting,
      (select max(s.final_score) from public.m_assessment_submissions s
       where s.participant_id = (select pid from me) and s.assessment_id = it.item_id and s.status = 'graded') as best,
      case when it.item_kind = 'assessment' then public.m_attempts_used((select pid from me), it.item_id) end as used,
      a.max_attempts as attempt_limit, a.time_limit_minutes as time_limit, a.due_at as due, a.pass_mark as pass,
      case when it.item_kind = 'assessment' then
        (select count(*) from public.m_assessment_questions q where q.assessment_id = it.item_id) end as questions,
      (select attempt.deadline_at from public.m_assessment_attempts attempt
       where it.item_kind = 'assessment' and attempt.assessment_id = it.item_id
         and attempt.participant_id = (select pid from me) and attempt.closed_at is null
         and (attempt.deadline_at is null or attempt.deadline_at + interval '2 minutes' > now())) as open_deadline,
      exists(select 1 from public.m_assessment_attempts attempt
       where it.item_kind = 'assessment' and attempt.assessment_id = it.item_id
         and attempt.participant_id = (select pid from me) and attempt.closed_at is null
         and (attempt.deadline_at is null or attempt.deadline_at + interval '2 minutes' > now())) as open_attempt
    from items it
    left join public.m_module_resources r on it.item_kind = 'resource' and r.id = it.item_id
    left join public.m_assessments a on it.item_kind = 'assessment' and a.id = it.item_id
  )
  select d.module_id, d.module_title, d.module_description, d.module_number,
         d.module_locked, d.module_completed,
         d.item_kind, d.item_id, d.item_type, d.item_title, d.ordinal,
         d.item_duration, d.item_points, d.blocking,
         d.module_locked or coalesce(sum(case when d.blocking and d.finished_at is null then 1 else 0 end)
           over (partition by d.module_id order by d.ordinal rows between unbounded preceding and 1 preceding), 0) > 0,
         d.finished_at is not null, d.finished_at,
         d.awaiting, d.best, d.used, d.attempt_limit,
         d.time_limit, d.due, d.pass, d.questions,
         d.open_attempt, d.open_deadline
  from detailed d
  order by d.module_number, d.ordinal
$$;

-- 6. Admin reordering -----------------------------------------------------------------------------
create or replace function public.m_move_module_item(target_kind text, target_item uuid, direction text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_module uuid;
  current_position integer;
  new_position integer;
begin
  if not public.m_is_admin() then raise exception 'Only an administrator can reorder course items.'; end if;
  if direction not in ('up', 'down') then raise exception 'Choose up or down.'; end if;

  select module_id into target_module from (
    select module_id from public.m_module_resources where target_kind = 'resource' and id = target_item
    union all
    select module_id from public.m_assessments where target_kind = 'assessment' and id = target_item) found;
  if target_module is null then raise exception 'Course item not found.'; end if;

  -- Renumber the module 1..n in its current order (one snapshot), then swap with the neighbour.
  with ordered as materialized (select * from public.m_module_items(target_module, true)),
  resources_renumbered as (
    update public.m_module_resources r set item_position = o.ordinal
    from ordered o where o.item_kind = 'resource' and r.id = o.item_id
    returning 1)
  update public.m_assessments a set item_position = o.ordinal
  from ordered o where o.item_kind = 'assessment' and a.id = o.item_id;

  select item_position into current_position from (
    select item_position from public.m_module_resources where target_kind = 'resource' and id = target_item
    union all
    select item_position from public.m_assessments where target_kind = 'assessment' and id = target_item) found;
  new_position := current_position + case when direction = 'up' then -1 else 1 end;

  if not exists(select 1 from public.m_module_resources where module_id = target_module and item_position = new_position)
     and not exists(select 1 from public.m_assessments where module_id = target_module and item_position = new_position) then
    return;
  end if;

  update public.m_module_resources set item_position = current_position where module_id = target_module and item_position = new_position;
  update public.m_assessments set item_position = current_position where module_id = target_module and item_position = new_position;
  if target_kind = 'resource' then
    update public.m_module_resources set item_position = new_position where id = target_item;
  else
    update public.m_assessments set item_position = new_position where id = target_item;
  end if;
end;
$$;

-- Grants: helpers used inside policies need execute for authenticated; internal helpers stay private.
revoke all on function public.m_set_item_position() from public;
revoke all on function public.m_module_items(uuid, boolean) from public;
revoke all on function public.m_item_done(uuid, text, uuid) from public;
revoke all on function public.m_item_unlocked(text, uuid) from public;
revoke all on function public.m_attempts_used(uuid, uuid) from public;
revoke all on function public.m_start_assessment(uuid) from public;
revoke all on function public.m_participant_can_read_questions(uuid) from public;
revoke all on function public.m_course_outline(uuid) from public;
revoke all on function public.m_move_module_item(text, uuid, text) from public;
revoke all on function public.m_can_start_assessment(uuid) from public;
revoke all on function public.m_submit_assessment(uuid, jsonb) from public;
grant execute on function public.m_item_unlocked(text, uuid) to authenticated;
grant execute on function public.m_participant_can_read_questions(uuid) to authenticated;
grant execute on function public.m_can_start_assessment(uuid) to authenticated;
grant execute on function public.m_start_assessment(uuid) to authenticated;
grant execute on function public.m_submit_assessment(uuid, jsonb) to authenticated;
grant execute on function public.m_course_outline(uuid) to authenticated;
grant execute on function public.m_move_module_item(text, uuid, text) to authenticated;
