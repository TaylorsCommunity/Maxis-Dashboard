# eKelas Usahawan — Learning & Impact Portal

Version 6.0.0 replaces administrator-created participant accounts with secure cohort-code registration and expands course authoring into dedicated project workspaces. It contains no demonstration users, participants, courses, videos, tests, attendance, financial records or testimonials.

## What changed in version 6

- Administrators create a programme and cohort, then generate a time-limited signup code.
- Participants create their own email/password account with that code and automatically join the correct cohort.
- People & Access is cohort-first: open a cohort to see its participants, assigned mentors, staff access, code history and course assignment.
- Every course opens as a separate workspace containing modules, learning content and assessments.
- Learning content is clearly separated into video, reading and workbook types.
- The assessment builder supports multiple questions and multiple choice, checkboxes, short answer, long answer and assignment-link responses.
- Multiple choice and checkboxes are graded automatically. Written and assignment responses enter the assigned mentor's grading queue.
- Mentors receive an in-portal notification when manual grading is required.
- Validation errors appear inside the active dialog or form, so they are never hidden behind a modal.
- The obsolete participant-invitation Edge Function has been removed.

## Database setup

Use the intended Supabase project and run these files in **SQL Editor**, in order:

1. `supabase/migrations/001_m_foundation.sql`
2. `supabase/migrations/002_admin_learning_attendance.sql`
3. `supabase/migrations/003_cohort_signup_assessments.sql`

If migrations 001 and 002 have already been applied, run only migration 003. It adds cohort codes, participant self-registration, course privacy, advanced assessments, submissions, mentor notifications and grading functions. It does not insert any sample records.

Every portal table, policy and function uses the `m_` prefix. This keeps the portal's records separate from the other application already using the same Supabase project.

## First administrator and staff accounts

The first administrator remains a manual, trusted setup step:

1. In Supabase, open **Authentication → Users** and create the administrator account.
2. Edit `supabase/bootstrap-admin.sql` with the administrator's name and email.
3. Run that statement in SQL Editor.

Participant signup codes create participant memberships only. Additional administrators, mentors and stakeholders should be created as trusted staff accounts in Supabase Auth and given an `m_memberships` row. No service-role key is used in the browser.

## Participant registration flow

1. Admin creates a programme and cohort in **People & Access**.
2. Admin opens the cohort and selects **Generate signup code**.
3. Admin sets an expiry and maximum number of registrations, then securely shares the displayed code.
4. Participant opens the portal, chooses **Create participant account**, enters the code, profile details, email and password.
5. Supabase validates the code before signup and enforces it again during user creation.
6. The new participant appears inside the matching cohort.
7. Admin assigns a mentor and course from the cohort workspace. New modules added to that course are assigned automatically.

Only a hash of each signup code is stored. The full code is shown once when generated. This protects usable cohort codes if read-only reporting data is ever exposed.

## Course and assessment flow

1. Admin creates a course workspace.
2. Admin opens the course and adds modules.
3. Each module can contain video links, reading text and workbook links.
4. Admin creates an assessment, then adds any number of questions.
5. Multiple choice and checkbox questions receive protected answer keys and automatic grading.
6. Short answer, long answer and assignment-link questions create a mentor-grading task after submission.
7. Admin publishes the module and assessment, then assigns the course to participants.

Participants can select only courses containing modules assigned to their participant profile. Row Level Security enforces this in Supabase; hiding a course in the interface is not the security boundary.

## Connection configuration

The supplied project URL and publishable browser key live in `portal.config.json`. Publishable keys are expected to be visible in a web application's source. Authentication, database functions and Row Level Security protect the data. Never place a secret or service-role key in this repository, Vercel environment variables or browser code.

If the portal moves to another Supabase project, update `portal.config.json` and `config.js`, run all three migrations in that project, and rebuild.

In Supabase **Authentication → URL Configuration**, add the production Vercel URL to the allowed redirect URLs so email confirmation and magic-link sign-in can return to the portal.

## Role access

| Role | Intended access |
| --- | --- |
| Admin | Cohorts, signup codes, mentor assignment, staff access, courses, assessments, attendance, grading and reports |
| Mentor | Assigned participants, manual grading, attendance and reports |
| Stakeholder | Read-only programme analytics and reports for assigned cohorts |
| Participant | Assigned courses, learning content, private notes, assessments and own business records |

## Run and deploy

- `npm start` — local server on `http://localhost:3000`
- `npm run check` — JavaScript syntax and production-content validation
- `npm run build` — generates the static `dist` folder used by Vercel

No package installation is required. Vercel uses the included `vercel.json`, and the browser loads the Supabase JavaScript client from jsDelivr.

## Current limitations

- Workbook and assignment submissions currently use shareable external links; direct Supabase Storage uploads are a later phase.
- Monthly business submission forms and downloadable stakeholder report generation remain to be built.
- Social media monitoring remains an optional, consent-based feature. See `SOCIAL_MEDIA_MONITORING_RECOMMENDATION.md` before implementing it.
- Staff provisioning is intentionally separate from public participant signup.
