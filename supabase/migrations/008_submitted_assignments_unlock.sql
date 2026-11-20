-- eKelas Usahawan: submitted mentor-graded work unlocks the next item
-- Run after 007_function_grants.sql. Idempotent. Functions only; no data is changed.
--
-- Decision (owner, 20 Nov 2026): a participant who submits work that needs mentor grading can carry on
-- straight away. The next item (and the next module) unlocks once the work is submitted, whether or
-- not the mentor has graded it yet, and even if it is later graded below the pass mark.
-- Automatically graded quizzes are unchanged: they must be passed to unlock what follows.
-- Passing still matters for the grade, the "You passed!" status, points and dashboard completion.

-- True when the assessment has at least one question a mentor must grade.
create or replace function public.m_assessment_needs_mentor(target_assessment uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1 from public.m_assessment_questions question
    where question.assessment_id = target_assessment
      and question.question_type not in ('multiple_choice', 'checkboxes'))
$$;

-- Finished for unlocking: content completed; quiz passed; mentor-graded work submitted.
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
      where submission.participant_id = target_participant and submission.assessment_id = target_item
        and (submission.passed or public.m_assessment_needs_mentor(target_item)))
  end
$$;

-- A module is complete when every required item in it is finished (same rule as m_item_done).
create or replace function public.m_module_complete_for(target_participant uuid, target_module uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(select 1 from public.m_module_items(target_module) item where item.blocking)
    and not exists(
      select 1 from public.m_module_items(target_module) item
      where item.blocking and not public.m_item_done(target_participant, item.item_kind, item.item_id))
$$;

-- Same as 006 except finished_at: mentor-graded work is finished at its first submission.
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
      case
        when it.item_kind = 'resource' then
          (select p.studied_at from public.m_resource_progress p
           where p.participant_id = (select pid from me) and p.resource_id = it.item_id)
        when public.m_assessment_needs_mentor(it.item_id) then
          (select min(s.submitted_at) from public.m_assessment_submissions s
           where s.participant_id = (select pid from me) and s.assessment_id = it.item_id)
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

-- Internal helper: only other security-definer functions call it.
revoke execute on function public.m_assessment_needs_mentor(uuid) from public, anon, authenticated;
