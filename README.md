# eKelas Usahawan — Learning & Impact Portal

Version 8.0.0 adds a Coursera-style learning player for participants on top of the version 7 learning and monitoring product. It contains no demonstration users, participants, courses, videos, assessments, attendance, business records or testimonials.

## Version 8 learning player

- Course player with a collapsible course outline, one item per page and "Go to next item" navigation.
- Videos, readings, workbooks and assessments in any order inside a module. Each required item unlocks the next one, enforced in the database.
- YouTube, Vimeo and Google Drive videos play inside the portal. Share Google Drive videos as “Anyone with the link”. Other links open on their host site.
- Transcript, private notes and downloadable file links beside each item.
- Assessment cover page with pass mark, best grade, attempts, time limit, due date and attempt history.
- Focused quiz mode with a database-enforced timer. Answers submit automatically when time runs out, and unanswered questions score zero. Due dates are shown but late work is still accepted.
- Daily goal (3 items) and points per item to encourage steady progress.
- The main navigation is a drawer: move the pointer to the left edge of the screen or use the menu button.
- Admins order module items with arrows, edit learning items, and set duration, points, transcript, files, time limit and due date.

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
- No email confirmation step: the admin-issued cohort code or staff invitation is the access check, and accounts work immediately.

## Database setup

Run these files in the intended Supabase project's **SQL Editor**, in order:

1. `supabase/migrations/001_m_foundation.sql`
2. `supabase/migrations/002_admin_learning_attendance.sql`
3. `supabase/migrations/003_cohort_signup_assessments.sql`
4. `supabase/migrations/004_product_workflows.sql`
5. `supabase/migrations/005_dashboard_privacy.sql`
6. `supabase/migrations/006_learning_player.sql`

If migrations 001–005 have already succeeded, run only migration 006. All migrations are idempotent and insert no demonstration programme records.

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
4. Admin shares that link privately with the intended person.
5. The invitee sets their own password using the exact invited email address.
6. The account is created with the role selected by the administrator and the staff member is signed in straight away.

Only administrators can create staff invitations. The invitation is email-bound, expires, and cannot be reused after acceptance. Because no confirmation email is sent, the invitation code itself is the proof of identity: share it only with the invitee, and use short expiries for administrator invitations.

## Participant registration and onboarding

1. Admin creates a programme and cohort.
2. Admin opens the cohort and generates a participant signup code.
3. Participant creates an account with that code.
4. Supabase assigns the participant to the matching cohort.
5. The participant is signed in immediately and must complete their business profile and baseline.
6. Learning and monthly monitoring unlock after onboarding is complete.
7. Admin assigns a mentor from the cohort workspace.

## Course access and learning flow

1. Admin creates a course workspace.
2. Admin adds ordered modules.
3. Each module contains required or optional videos, readings and workbooks, plus assessments, in any order. Use the arrows to reorder items.
4. For each assessment the admin sets the pass mark, attempts (blank = unlimited), optional time limit, optional due date and points.
5. Admin selects **Manage cohort access** from inside the course.
6. All participants in the authorised cohort receive the course automatically.
7. Participants complete the course in sequence:
   - later modules remain locked until the previous module is complete;
   - inside a module, each item stays locked until every earlier required item is finished (content completed, assessments passed);
   - a mentor-graded assignment unlocks the next item only once it is graded as a pass.

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

## Email confirmation (switched off)

The portal does not use email confirmation. Supabase's built-in email sender is for testing only. It is heavily rate-limited, and its messages were not reaching Taylor's mailboxes. Access is already controlled by admin-issued cohort codes and staff invitations, which are consumed by the `m_auth_signup_code` and `m_auth_staff_invite` triggers when the account is created.

Required Supabase setting: **Authentication → Sign In / Providers → Email → Confirm email = off**.

Consequences to be aware of:

- Email ownership is not proven. Signup forms ask for the email twice to reduce typos.
- Password recovery and magic links still need email, so the sign-in page asks people to contact an administrator instead. Configure custom SMTP (Authentication → Emails → SMTP settings) before re-enabling any email-based flow.
- Accounts created while confirmation was on stay unconfirmed until marked confirmed in Supabase.

## Auth redirect URLs

The website sends the current deployed website address to Supabase for auth redirects. Supabase must also allow that address:

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
| Stakeholder | Aggregated statistics for authorised cohorts only. No access to individual participant records; financial averages are hidden below 3 participants |
| Participant | Own profile, assigned learning path, private notes, assessments and monthly business monitoring |

## Run and deploy

- `npm start` — local server at `http://localhost:3000`
- `npm run check` — syntax and production validation
- `npm run build` — creates the static `dist` folder for Vercel

Redeploy to Vercel after running migration 006. No package installation is required.

## Current limitations

- Assignment submissions currently accept a shareable file or document URL rather than uploading full assignment files.
- Downloadable stakeholder report generation remains a later phase.
- Social-media monitoring remains optional and consent-based. Review `SOCIAL_MEDIA_MONITORING_RECOMMENDATION.md` before implementation.
