-- eKelas Usahawan dashboard v2: impact, learning, reach and needs-attention views
-- Run after 008_submitted_assignments_unlock.sql. Idempotent. Functions only; no data is changed.
--
-- The dashboard is organised around one reporting month. Monthly business updates for a month are due on
-- the 10th of the following month. All figures are computed here so stakeholders only receive totals:
-- for stakeholders, any financial figure built from fewer than 3 participants is withheld (null).
-- Medians are used for money because a single large business would distort an average.
--
-- Participants counted: active participants within the caller's scope (admin: all; mentor: own mentees;
-- stakeholder: cohorts granted through m_cohort_access), narrowed by the programme/cohort/state filters.
-- A participant is expected to report for a month once their baseline month is earlier than that month.

create or replace function public.m_dashboard_v2(
  target_programme uuid default null,
  target_cohort uuid default null,
  target_state text default null,
  target_month date default null
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
  min_group constant integer := 3;
  month_start date := date_trunc('month', coalesce(target_month, (date_trunc('month', now()) - interval '1 month')::date))::date;
  month_end date := (date_trunc('month', coalesce(target_month, (date_trunc('month', now()) - interval '1 month')::date)) + interval '1 month')::date;
  stakeholder boolean;
  result jsonb;
begin
  if caller_role is null or caller_role not in ('admin'::public.m_role, 'mentor'::public.m_role, 'stakeholder'::public.m_role) then
    raise exception 'Only active programme staff can view dashboard statistics.';
  end if;
  stakeholder := caller_role = 'stakeholder'::public.m_role;

  with scoped as (
    select p.*
    from public.m_participants p
    where p.active
      and (caller_role = 'admin'::public.m_role
        or (caller_role = 'mentor'::public.m_role and p.mentor_user_id = caller)
        or (caller_role = 'stakeholder'::public.m_role and exists(
              select 1 from public.m_cohort_access access
              where access.user_id = caller and access.cohort_id = p.cohort_id)))
  ),
  filtered as (
    select s.*,
      s.onboarding_completed_at is not null
        and coalesce(s.baseline_month, date_trunc('month', s.onboarding_completed_at)::date) < month_start as expected
    from scoped s
    left join public.m_cohorts cohort on cohort.id = s.cohort_id
    where (target_programme is null or cohort.programme_id = target_programme)
      and (target_cohort is null or s.cohort_id = target_cohort)
      and (target_state is null or s.state = target_state)
  ),
  reports as (
    select c.participant_id, c.reporting_month, c.sales, c.customer_count, c.employee_count,
           coalesce(c.net_profit, c.sales - c.operating_costs) as profit, c.impact_story, c.story_consent
    from public.m_business_checkins c
    join filtered f on f.id = c.participant_id
    where c.reporting_month < month_end
  ),
  latest as (
    select distinct on (r.participant_id) r.* from reports r order by r.participant_id, r.reporting_month desc
  ),
  first_report as (
    select distinct on (r.participant_id) r.* from reports r order by r.participant_id, r.reporting_month
  ),
  sales_change as (
    select f.id, (l.sales - f.baseline_sales) / f.baseline_sales * 100 as pct
    from filtered f join latest l on l.participant_id = f.id
    where f.baseline_sales > 0 and l.sales is not null
  ),
  profit_pair as (
    select f.baseline_profit, l.profit
    from filtered f join latest l on l.participant_id = f.id
    where f.baseline_profit is not null and l.profit is not null
  ),
  jobs as (
    select f.employee_count as baseline_jobs, l.employee_count as latest_jobs
    from filtered f join latest l on l.participant_id = f.id
    where f.employee_count is not null and l.employee_count is not null
  ),
  customers as (
    select fr.customer_count as first_customers, l.customer_count as latest_customers
    from first_report fr join latest l on l.participant_id = fr.participant_id
    where fr.reporting_month < l.reporting_month and fr.customer_count is not null and l.customer_count is not null
  ),
  months as (
    select generate_series(month_start - interval '11 months', month_start::timestamp, interval '1 month')::date as m
  ),
  series as (
    select months.m,
      count(r.participant_id) as reporters,
      percentile_cont(0.5) within group (order by r.sales) as median_sales,
      percentile_cont(0.5) within group (order by r.profit) as median_profit
    from months left join reports r on r.reporting_month = months.m
    group by months.m
  ),
  assigned as (
    select ma.participant_id, ma.module_id, module.course_id,
           public.m_module_complete_for(ma.participant_id, ma.module_id) as complete
    from public.m_module_assignments ma
    join filtered f on f.id = ma.participant_id
    join public.m_modules module on module.id = ma.module_id and module.published
  ),
  course_progress as (
    select a.course_id, a.participant_id, bool_and(a.complete) as finished
    from assigned a group by a.course_id, a.participant_id
  ),
  attendance as (
    select record.participant_id, session.session_date, record.status
    from public.m_attendance_records record
    join filtered f on f.id = record.participant_id
    join public.m_attendance_sessions session on session.id = record.session_id
    where session.session_date < month_end
  ),
  cohort_rows as (
    select cohort.id, cohort.name, programme.name as programme_name,
      count(f.id) as participants,
      count(f.id) filter (where f.expected) as expected,
      count(f.id) filter (where f.expected and exists(
        select 1 from reports r where r.participant_id = f.id and r.reporting_month = month_start)) as reported,
      (select round(100.0 * count(*) filter (where a.complete) / nullif(count(*), 0))
         from assigned a join filtered f2 on f2.id = a.participant_id where f2.cohort_id = cohort.id) as completion_pct,
      (select round(100.0 * count(*) filter (where at.status = 'present') / nullif(count(*) filter (where at.status <> 'unmarked'), 0))
         from attendance at join filtered f3 on f3.id = at.participant_id where f3.cohort_id = cohort.id) as attendance_pct,
      (select count(*) from sales_change sc join filtered f4 on f4.id = sc.id where f4.cohort_id = cohort.id) as growth_n,
      (select percentile_cont(0.5) within group (order by sc.pct)
         from sales_change sc join filtered f5 on f5.id = sc.id where f5.cohort_id = cohort.id) as median_growth
    from filtered f
    join public.m_cohorts cohort on cohort.id = f.cohort_id
    left join public.m_programmes programme on programme.id = cohort.programme_id
    group by cohort.id, cohort.name, programme.name
  ),
  counts as (
    select
      (select count(*) from filtered) as participants,
      (select count(*) from filtered where expected) as expected,
      (select count(*) from filtered f where f.expected and exists(
         select 1 from reports r where r.participant_id = f.id and r.reporting_month = month_start)) as reported,
      (select count(*) from sales_change) as sales_n,
      (select count(*) from sales_change where pct > 0) as sales_growing,
      (select percentile_cont(0.5) within group (order by pct) from sales_change) as sales_median_change,
      (select count(*) from profit_pair) as profit_n,
      (select count(*) from profit_pair where profit > baseline_profit) as profit_growing,
      (select avg(baseline_profit) from profit_pair) as paired_baseline,
      (select avg(profit) from profit_pair) as paired_latest,
      (select count(*) from latest where profit is not null) as profit_reporting,
      (select avg(profit) from latest) as latest_profit_avg,
      (select count(*) from jobs) as jobs_n,
      (select sum(baseline_jobs) from jobs) as jobs_baseline,
      (select sum(latest_jobs) from jobs) as jobs_latest,
      (select count(*) from customers) as customers_n,
      (select sum(first_customers) from customers) as customers_first,
      (select sum(latest_customers) from customers) as customers_latest
  ),
  bucketed as (
    select label, count(*) as n from (
      select case
        when nullif(btrim(coalesce(f.state, '')), '') is null then 'Not provided' else btrim(f.state) end as label
      from filtered f) x group by label
  )
  select jsonb_build_object(
    'period', jsonb_build_object('month', month_start, 'due', (month_end + 9), 'due_passed', current_date > month_end + 9),
    'role', caller_role, 'min_group', min_group,
    'states', coalesce((select jsonb_agg(state order by state) from (
                select distinct state from scoped where nullif(btrim(state), '') is not null) st), '[]'::jsonb),
    'impact', (select jsonb_build_object(
      'participants', c.participants,
      'expected', c.expected,
      'reported', c.reported,
      'sales_n', c.sales_n,
      'sales_growing', case when stakeholder and c.sales_n < min_group then null else c.sales_growing end,
      'sales_median_change', case when c.sales_n = 0 or (stakeholder and c.sales_n < min_group) then null else round(c.sales_median_change::numeric, 1) end,
      'profit_n', c.profit_n,
      'profit_growing', case when stakeholder and c.profit_n < min_group then null else c.profit_growing end,
      'profit_change_pct', case when c.profit_n = 0 or c.paired_baseline = 0 or (stakeholder and c.profit_n < min_group) then null
                                else round((c.paired_latest - c.paired_baseline) / abs(c.paired_baseline) * 100) end,
      'paired_baseline', case when c.profit_n = 0 or (stakeholder and c.profit_n < min_group) then null else round(c.paired_baseline) end,
      'paired_latest', case when c.profit_n = 0 or (stakeholder and c.profit_n < min_group) then null else round(c.paired_latest) end,
      'profit_reporting', c.profit_reporting,
      'latest_profit_avg', case when c.profit_reporting = 0 or (stakeholder and c.profit_reporting < min_group) then null else round(c.latest_profit_avg) end,
      'jobs_n', c.jobs_n,
      'jobs_baseline', case when stakeholder and c.jobs_n < min_group then null else c.jobs_baseline end,
      'jobs_latest', case when stakeholder and c.jobs_n < min_group then null else c.jobs_latest end,
      'customers_n', c.customers_n,
      'customers_first', case when stakeholder and c.customers_n < min_group then null else c.customers_first end,
      'customers_latest', case when stakeholder and c.customers_n < min_group then null else c.customers_latest end,
      'bands', case when c.sales_n = 0 or (stakeholder and c.sales_n < min_group) then null else (
        select jsonb_build_object(
          'declined', count(*) filter (where pct < -10),
          'flat', count(*) filter (where pct >= -10 and pct <= 10),
          'grew', count(*) filter (where pct > 10 and pct <= 50),
          'grew_big', count(*) filter (where pct > 50))
        from sales_change) end,
      'baseline_median_sales', (select case when count(*) = 0 or (stakeholder and count(*) < min_group) then null
                                  else round(percentile_cont(0.5) within group (order by baseline_sales)::numeric) end
                                from filtered where baseline_sales is not null),
      'baseline_median_profit', (select case when count(*) = 0 or (stakeholder and count(*) < min_group) then null
                                   else round(percentile_cont(0.5) within group (order by baseline_profit)::numeric) end
                                 from filtered where baseline_profit is not null),
      'series', (select jsonb_agg(jsonb_build_object(
          'month', s.m, 'reporters', s.reporters,
          'median_sales', case when s.reporters = 0 or (stakeholder and s.reporters < min_group) then null else round(s.median_sales::numeric) end,
          'median_profit', case when s.reporters = 0 or (stakeholder and s.reporters < min_group) then null else round(s.median_profit::numeric) end)
        order by s.m) from series s),
      'stories', coalesce((select jsonb_agg(story order by story->>'month' desc) from (
          select jsonb_build_object('text', r.impact_story, 'month', r.reporting_month,
                   'sector', f.sector, 'state', f.state,
                   'business', case when stakeholder then null else f.business_name end) as story
          from reports r join filtered f on f.id = r.participant_id
          where r.story_consent and nullif(btrim(coalesce(r.impact_story, '')), '') is not null
          order by r.reporting_month desc limit 6) stories), '[]'::jsonb)
    ) from counts c),
    'learning', jsonb_build_object(
      'modules_assigned', (select count(*) from assigned),
      'modules_completed', (select count(*) from assigned where complete),
      'active_learners', (select count(distinct x.participant_id) from (
          select progress.participant_id from public.m_resource_progress progress join filtered f on f.id = progress.participant_id
          where progress.studied_at >= month_start and progress.studied_at < month_end
          union all
          select submission.participant_id from public.m_assessment_submissions submission join filtered f on f.id = submission.participant_id
          where submission.submitted_at >= month_start and submission.submitted_at < month_end) x),
      'assessments_passed', (select count(distinct (submission.participant_id, submission.assessment_id))
          from public.m_assessment_submissions submission join filtered f on f.id = submission.participant_id
          where submission.passed and submission.submitted_at < month_end),
      'pending_grading', case when stakeholder then null else (select count(*)
          from public.m_assessment_submissions submission join filtered f on f.id = submission.participant_id
          where submission.status = 'submitted') end,
      'attendance_marked', (select count(*) from attendance where status <> 'unmarked'),
      'attendance_present', (select count(*) from attendance where status = 'present'),
      'month_attendance_marked', (select count(*) from attendance where status <> 'unmarked' and session_date >= month_start),
      'month_attendance_present', (select count(*) from attendance where status = 'present' and session_date >= month_start),
      'courses', coalesce((select jsonb_agg(jsonb_build_object('title', course.title, 'participants', cp.n, 'finished', cp.finished) order by course.title)
          from (select course_id, count(*) as n, count(*) filter (where finished) as finished from course_progress group by course_id) cp
          join public.m_courses course on course.id = cp.course_id), '[]'::jsonb)
    ),
    'reach', jsonb_build_object(
      'by_state', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'count', n)) from bucketed), '[]'::jsonb),
      'by_gender', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'count', n)) from (
          select coalesce(nullif(btrim(gender), ''), 'Not provided') as label, count(*) as n from filtered group by 1) g), '[]'::jsonb),
      'by_sector', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'count', n)) from (
          select coalesce(nullif(btrim(sector), ''), 'Not provided') as label, count(*) as n from filtered group by 1) g), '[]'::jsonb),
      'by_registration', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'count', n)) from (
          select coalesce(nullif(btrim(registration_status), ''), 'Not provided') as label, count(*) as n from filtered group by 1) g), '[]'::jsonb),
      'by_age', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'count', n) order by sort_key) from (
          select case when age is null then 'Not provided' when age < 25 then 'Under 25' when age < 35 then '25–34'
                      when age < 45 then '35–44' when age < 55 then '45–54' else '55 and over' end as label,
                 case when age is null then 9 when age < 25 then 1 when age < 35 then 2 when age < 45 then 3 when age < 55 then 4 else 5 end as sort_key,
                 count(*) as n
          from filtered group by 1, 2) g), '[]'::jsonb)
    ),
    'cohorts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', cr.id, 'name', cr.name, 'programme', cr.programme_name, 'participants', cr.participants,
        'expected', cr.expected, 'reported', cr.reported, 'completion_pct', cr.completion_pct, 'attendance_pct', cr.attendance_pct,
        'growth_n', cr.growth_n,
        'median_growth', case when cr.growth_n = 0 or (stakeholder and cr.growth_n < min_group) then null else round(cr.median_growth::numeric, 1) end)
      order by cr.name) from cohort_rows cr), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

-- Participants who need a mentor's attention in the reporting month. Admins see all, mentors their mentees.
create or replace function public.m_dashboard_attention(
  target_programme uuid default null,
  target_cohort uuid default null,
  target_month date default null
)
returns table(
  participant_id uuid, full_name text, business_name text, cohort_name text, mentor_name text, phone text,
  missing_report boolean, profit_falling boolean, learning_inactive boolean, low_attendance boolean, profile_incomplete boolean,
  last_report_month date, last_activity timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  caller_role public.m_role := public.m_current_role();
  month_start date := date_trunc('month', coalesce(target_month, (date_trunc('month', now()) - interval '1 month')::date))::date;
begin
  if caller_role is null or caller_role not in ('admin'::public.m_role, 'mentor'::public.m_role) then
    raise exception 'Only administrators and mentors can view participants who need attention.';
  end if;

  return query
  with people as (
    select p.*, cohort.name as cohort_label, mentor.display_name as mentor_label,
      p.onboarding_completed_at is not null
        and coalesce(p.baseline_month, date_trunc('month', p.onboarding_completed_at)::date) < month_start as expected
    from public.m_participants p
    left join public.m_cohorts cohort on cohort.id = p.cohort_id
    left join public.m_memberships mentor on mentor.user_id = p.mentor_user_id
    where p.active
      and (caller_role = 'admin'::public.m_role or p.mentor_user_id = caller)
      and (target_programme is null or cohort.programme_id = target_programme)
      and (target_cohort is null or p.cohort_id = target_cohort)
  ),
  flags as (
    select pe.*,
      pe.expected and not exists(
        select 1 from public.m_business_checkins c where c.participant_id = pe.id and c.reporting_month = month_start) as missing,
      (select (array_agg(coalesce(c.net_profit, c.sales - c.operating_costs) order by c.reporting_month desc))[1:3]
         from public.m_business_checkins c where c.participant_id = pe.id and c.reporting_month <= month_start) as recent_profits,
      (select max(c.reporting_month) from public.m_business_checkins c where c.participant_id = pe.id) as last_month,
      greatest(
        (select max(progress.studied_at) from public.m_resource_progress progress where progress.participant_id = pe.id),
        (select max(submission.submitted_at) from public.m_assessment_submissions submission where submission.participant_id = pe.id)) as last_seen,
      exists(select 1 from public.m_module_assignments ma join public.m_modules module on module.id = ma.module_id and module.published
             where ma.participant_id = pe.id and not public.m_module_complete_for(pe.id, ma.module_id)) as unfinished,
      (select count(*) filter (where r.status <> 'unmarked') from public.m_attendance_records r where r.participant_id = pe.id) as marked,
      (select count(*) filter (where r.status = 'present') from public.m_attendance_records r where r.participant_id = pe.id) as present
    from people pe
  ),
  evaluated as (
    select f.*,
      coalesce(array_length(f.recent_profits, 1) = 3 and f.recent_profits[1] < f.recent_profits[2] and f.recent_profits[2] < f.recent_profits[3], false) as falling,
      f.onboarding_completed_at is not null and f.unfinished
        and coalesce(f.last_seen, f.onboarding_completed_at) < now() - interval '14 days' as inactive,
      f.marked >= 2 and f.present::numeric / f.marked < 0.5 as low_att,
      f.onboarding_completed_at is null as no_profile
    from flags f
  )
  select e.id, e.full_name, e.business_name, e.cohort_label, e.mentor_label, e.phone,
         e.missing, e.falling, e.inactive, e.low_att, e.no_profile, e.last_month, e.last_seen
  from evaluated e
  where e.missing or e.falling or e.inactive or e.low_att or e.no_profile
  order by (e.missing::int + e.falling::int + e.inactive::int + e.low_att::int + e.no_profile::int) desc, e.full_name;
end;
$$;

revoke all on function public.m_dashboard_v2(uuid, uuid, text, date) from public;
revoke execute on function public.m_dashboard_v2(uuid, uuid, text, date) from anon;
grant execute on function public.m_dashboard_v2(uuid, uuid, text, date) to authenticated;
revoke all on function public.m_dashboard_attention(uuid, uuid, date) from public;
revoke execute on function public.m_dashboard_attention(uuid, uuid, date) from anon;
grant execute on function public.m_dashboard_attention(uuid, uuid, date) to authenticated;
