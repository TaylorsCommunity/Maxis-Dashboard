# eKelas Usahawan — Learning & Impact Portal

Version 7.0.0 turns the dashboard into an operational learning and monitoring product. It contains no demonstration users, participants, courses, videos, assessments, attendance, business records or testimonials.

## Version 7 capabilities

- Admin-issued invitations for mentors, stakeholders and additional administrators.
- Participant self-registration using secure cohort codes.
- Mandatory participant business onboarding after the first sign-in.
- Business profiles with descriptions, sector, baseline month, sales, costs, profit, employees and business goals.
- Private participant profile-photo uploads through Supabase Storage.
- Participant-published monthly sales, costs, profit, customer and employee monitoring.
- Course access assigned by cohort from inside each course workspace.
- Existing and future participants in an authorised cohort receive the course automatically.
- Ordered course modules, with later modules locked until the previous module is complete.
- Assessments locked until required videos, readings and workbooks are completed.
- Single-attempt or multiple-attempt assessment settings.
- Automatic tests and mentor-graded assignments with notifications.
- Filterable dashboard analytics, demographic breakdowns, attendance, learning completion and profit growth.
- Cohort-first People & Access, participant profiles, staff access and invitation history.
- URL-based view persistence, so refreshing or returning to the tab retains the current workspace.
- Production email-confirmation redirects using the current deployed website address.

## Database setup

Run these files in the intended Supabase project's **SQL Editor**, in order:

1. `supabase/migrations/001_m_foundation.sql`
2. `supabase/migrations/002_admin_learning_attendance.sql`
3. `supabase/migrations/003_cohort_signup_assessments.sql`
4. `supabase/migrations/004_product_workflows.sql`

If migrations 001–003 have already succeeded, run only migration 004. All migrations are idempotent and insert no demonstration programme records.

Every portal-owned table, policy and function uses the `m_` prefix. This keeps portal data separate from the other application using the same Supabase project.

## First administrator

The first administrator remains a trusted manual setup step:

1. In Supabase, open **Authentication → Users** and create the administrator account.
2. Edit `supabase/bootstrap-admin.sql` with the administrator's name and email.
3. Run the statement in SQL Editor.

After this, the administrator can issue mentor, stakeholder and administrator invitations inside **People & Access**. No service-role key or Edge Function is required in the browser.

## Mentor and staff invitation flow

1. Admin opens **People & Access → Staff access**.
2. Admin selects **Invite mentor**, enters the name, email, role and expiry.
3. The portal generates a secure, one-time invitation link.
4. Admin shares that link with the intended person.
5. The invitee sets their own password using the exact invited email address.
6. Supabase sends its normal confirmation email.
7. After confirmation, the staff member signs in with the role selected by the administrator.

Only administrators can create staff invitations. The invitation is email-bound, expires, and cannot be reused after acceptance.

## Participant registration and onboarding

1. Admin creates a programme and cohort.
2. Admin opens the cohort and generates a participant signup code.
3. Participant creates an account with that code.
4. Supabase assigns the participant to the matching cohort.
5. After email confirmation and first sign-in, the participant must complete their business profile and baseline.
6. Learning and monthly monitoring unlock after onboarding is complete.
7. Admin assigns a mentor from the cohort workspace.

## Course access and learning flow

1. Admin creates a course workspace.
2. Admin adds ordered modules.
3. Each module contains required or optional videos, readings and workbooks.
4. Admin creates ordered assessments and chooses one attempt or multiple attempts.
5. Admin selects **Manage cohort access** from inside the course.
6. All participants in the authorised cohort receive the course automatically.
7. Participants complete the course in sequence:
   - later modules remain locked until the previous module is complete;
   - assessments remain locked until all required content is complete;
   - later assessments remain locked until earlier assessments are passed.

Multiple-choice and checkbox questions are graded automatically. Short answers, long answers and assignment links enter the assigned mentor's grading queue.

## Business monitoring

Participants can publish one record per reporting month containing:

- sales or revenue;
- operating costs;
- net profit, including a negative result;
- customer count;
- employee count;
- business notes and changes;
- an optional, consented impact story.

Publishing the same month again updates that month's record.

## Email confirmation redirect

The website sends the current deployed website address to Supabase for signup and magic-link redirects. Supabase must also allow that address:

1. Open **Supabase → Authentication → URL Configuration**.
2. Set the production Vercel URL as the **Site URL**.
3. Add the same address to **Redirect URLs**.
4. Do not use a localhost Site URL for production testing.

The exact address expected by the running portal is also displayed under **Account & system**.

## Connection configuration

The selected Supabase project URL and publishable browser key are stored in `portal.config.json`. Publishable keys are expected to be visible in browser applications; security comes from Authentication, database functions and Row Level Security.

Never place a service-role key in this repository, Vercel or browser code.

## Role access

| Role | Intended access |
| --- | --- |
| Admin | Dashboard analytics, programmes, cohorts, staff invitations, participant profiles, mentor assignment, course authoring, cohort course access, attendance, grading and reports |
| Mentor | Assigned participant profiles, manual grading, attendance and reports |
| Stakeholder | Read-only programme analytics and authorised reports |
| Participant | Own profile, assigned learning path, private notes, assessments and monthly business monitoring |

## Run and deploy

- `npm start` — local server at `http://localhost:3000`
- `npm run check` — syntax and production validation
- `npm run build` — creates the static `dist` folder for Vercel

Redeploy to Vercel after running migration 004. No package installation is required.

## Current limitations

- Assignment submissions currently accept a shareable file or document URL rather than uploading full assignment files.
- Downloadable stakeholder report generation remains a later phase.
- Social-media monitoring remains optional and consent-based. Review `SOCIAL_MEDIA_MONITORING_RECOMMENDATION.md` before implementation.
