-- eKelas Usahawan dashboard privacy and profit-growth correction
-- Run after 004_product_workflows.sql. Idempotent. No data is inserted, changed or deleted.
--
-- 1. Stakeholders lose row-level access to participant records (names, emails, phones,
--    business finances, check-ins, attendance, assignments, progress). They see programme
--    statistics only, through m_dashboard_overview().
-- 2. m_dashboard_overview() computes the overview figures in the database for every staff role.
--    Net profit change now compares the SAME participants' baseline and latest monthly report.
--    Before this, participants without a baseline counted as RM 0 and two different groups were
--    compared, which overstated growth.

-- Same as 002 minus the stakeholder branch. Every participant-data SELECT policy uses this helper,
-- so removing the branch closes stakeholder access to all of them at once.
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
      )
  )
$$;

create or replace function public.m_dashboard_overview(
  target_programme uuid default null,
  target_cohort uuid default null,
  target_state text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  caller_role public.m_role := public.m_current_role();
  -- Stakeholders never see an average built from fewer participants than this,
  -- so a narrow filter cannot reveal one person's finances.
  min_group constant integer := 3;
  result jsonb;
begin
  if caller_role is null or caller_role not in ('admin'::public.m_role, 'mentor'::public.m_role, 'stakeholder'::public.m_role) then
    raise exception 'Only active programme staff can view dashboard statistics.';
  end if;

  with scoped as (
    select p.id, p.cohort_id, p.state, p.gender, p.baseline_profit, p.onboarding_completed_at
    from public.m_participants p
    where caller_role = 'admin'::public.m_role
       or (caller_role = 'mentor'::public.m_role and p.mentor_user_id = caller)
       or (caller_role = 'stakeholder'::public.m_role and exists(
            select 1 from public.m_cohort_access access
            where access.user_id = caller and access.cohort_id = p.cohort_id))
  ),
  filtered as (
    select s.*
    from scoped s
    left join public.m_cohorts cohort on cohort.id = s.cohort_id
    where (target_programme is null or cohort.programme_id = target_programme)
      and (target_cohort is null or s.cohort_id = target_cohort)
      and (target_state is null or s.state = target_state)
  ),
  latest as (
    select distinct on (checkin.participant_id)
      checkin.participant_id,
      coalesce(checkin.net_profit, coalesce(checkin.sales, 0) - coalesce(checkin.operating_costs, 0)) as profit
    from public.m_business_checkins checkin
    join filtered f on f.id = checkin.participant_id
    order by checkin.participant_id, checkin.reporting_month desc
  ),
  paired as (
    select f.baseline_profit, l.profit
    from filtered f
    join latest l on l.participant_id = f.id
    where f.baseline_profit is not null
  ),
  assigned as (
    select ma.participant_id, ma.module_id
    from public.m_module_assignments ma
    join filtered f on f.id = ma.participant_id
  ),
  passed as (
    select distinct submission.participant_id, assessment.module_id
    from public.m_assessment_submissions submission
    join public.m_assessments assessment on assessment.id = submission.assessment_id
    join filtered f on f.id = submission.participant_id
    where submission.passed
  ),
  attendance as (
    select
      count(*) filter (where record.status <> 'unmarked') as marked,
      count(*) filter (where record.status = 'present') as present
    from public.m_attendance_records record
    join filtered f on f.id = record.participant_id
  ),
  finance as (
    select
      (select count(*) from latest) as reporting,
      (select avg(profit) from latest) as avg_latest,
      (select count(*) from paired) as paired,
      (select avg(baseline_profit) from paired) as paired_baseline,
      (select avg(profit) from paired) as paired_latest
  )
  select jsonb_build_object(
    'participants', (select count(*) from filtered),
    'profiles_completed', (select count(*) from filtered where onboarding_completed_at is not null),
    'cohorts', (select count(distinct cohort_id) from filtered),
    'modules_assigned', (select count(*) from assigned),
    'modules_passed', (select count(*) from passed),
    'completion_pct', (select case when count(*) = 0 then 0
                         else round(100.0 * count(*) filter (where exists(
                           select 1 from passed p where p.participant_id = a.participant_id and p.module_id = a.module_id)) / count(*)) end
                       from assigned a),
    'attendance_present', (select present from attendance),
    'attendance_pct', (select case when marked = 0 then 0 else round(100.0 * present / marked) end from attendance),
    'pending_grading', (select count(*) from public.m_assessment_submissions submission
                        join filtered f on f.id = submission.participant_id
                        where submission.status = 'submitted'),
    'profit_reporting', (select reporting from finance),
    'avg_latest_profit', (select case
                            when reporting = 0 then null
                            when caller_role = 'stakeholder'::public.m_role and reporting < min_group then null
                            else round(avg_latest) end from finance),
    'profit_paired', (select paired from finance),
    'paired_avg_baseline', (select case when paired = 0 or (caller_role = 'stakeholder'::public.m_role and paired < min_group) then null else round(paired_baseline) end from finance),
    'paired_avg_latest', (select case when paired = 0 or (caller_role = 'stakeholder'::public.m_role and paired < min_group) then null else round(paired_latest) end from finance),
    'profit_change_pct', (select case
                            when paired = 0 or paired_baseline = 0 then null
                            when caller_role = 'stakeholder'::public.m_role and paired < min_group then null
                            else round((paired_latest - paired_baseline) / abs(paired_baseline) * 100) end from finance),
    'financials_suppressed', (select caller_role = 'stakeholder'::public.m_role and (reporting between 1 and min_group - 1 or paired between 1 and min_group - 1) from finance),
    'min_group', min_group,
    'by_state', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'count', n)) from (
                   select coalesce(nullif(btrim(state), ''), 'Not provided') as label, count(*) as n from filtered group by 1) s), '[]'::jsonb),
    'by_gender', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'count', n)) from (
                   select coalesce(nullif(btrim(gender), ''), 'Not provided') as label, count(*) as n from filtered group by 1) g), '[]'::jsonb),
    'states', coalesce((select jsonb_agg(state order by state) from (
                   select distinct state from scoped where nullif(btrim(state), '') is not null) st), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

revoke all on function public.m_dashboard_overview(uuid, uuid, text) from public;
revoke all on function public.m_dashboard_overview(uuid, uuid, text) from anon;
grant execute on function public.m_dashboard_overview(uuid, uuid, text) to authenticated;
