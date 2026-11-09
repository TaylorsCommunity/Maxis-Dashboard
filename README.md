# eKelas Usahawan — Learning & Impact Portal

Version 5.0.0 adds operational administration, course authoring, mentor assignment and live attendance workflows while retaining the clean production foundation. It contains no demonstration participants, users, modules, videos, quizzes, attendance, financial records or testimonials.

The supplied Supabase project URL and publishable key are configured in `portal.config.json`. The foundation tables have been verified in the selected project. Run the version 5 upgrade migration before using the new administration and attendance tools.

## Architecture decision

This package uses its selected Supabase project with an explicit database namespace:

- Every portal table, function, type, index and policy begins with `m_` as this project's database signature.
- Supabase Authentication is scoped to the selected Supabase project.
- A valid Auth account receives no portal access unless it also has an active row in `m_memberships`.
- Row Level Security restricts data by role, participant identity and assigned cohorts.
- No table, policy or grant outside the `m_` namespace is modified by the portal migrations.

The portal is therefore independent from ChronoSphere users and application records.

## 1. Create the database foundation

1. Open the intended Supabase project.
2. Open **SQL Editor**.
3. Run `supabase/migrations/001_m_foundation.sql` once.
4. Run `supabase/migrations/002_admin_learning_attendance.sql` once.
5. Confirm that the new `m_` tables appear in Table Editor.

The migration creates empty production tables for:

- portal membership and roles;
- programmes, cohorts and cohort access;
- participant profiles and mentor assignment;
- modules, resources, assignments and learning progress;
- participant-private notes;
- quiz questions, protected answer keys and server-side grading;
- live attendance sessions and participant attendance;
- monthly business check-ins and consented impact stories.

No data is inserted by the migration.

## 2. Create the first administrator

1. In Supabase, open **Authentication → Users** and create the administrator account.
2. Open `supabase/bootstrap-admin.sql`.
3. Replace `ADMIN DISPLAY NAME` and `ADMIN EMAIL ADDRESS`.
4. Run the edited statement in SQL Editor.

This bootstrap is intentionally manual. The browser must never receive a Supabase service-role key.

## 3. Deploy administrator invitations

The **Add user** screen calls the included `m-admin-user` Supabase Edge Function. Deploy `supabase/functions/m-admin-user` to the same Supabase project. The function verifies that the caller is an active portal administrator before it invites a user or changes membership access.

The Supabase-hosted function receives `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in its server environment. Never copy the service-role key into `config.js`, `portal.config.json`, Vercel or browser code.

## 4. Connection configuration

The package is already linked to the supplied project URL using its publishable browser key. Publishable keys are expected to be visible in a web application's source; data protection comes from Authentication and Row Level Security. Never place a secret or service-role key in this repository or browser configuration.

### Local preview

Run `npm start` and open `http://localhost:3000`. No connection variables are required for this configured package.

Open `http://localhost:3000`.

### Vercel

The committed values in `portal.config.json` are authoritative and work without Vercel environment variables. This prevents stale settings from another Vercel project from silently overriding the intended database. If this portal is moved to another Supabase project, update `portal.config.json` and `config.js`, then rebuild and redeploy.

Older Vercel environment variables may remain configured, but version 5.0.0 does not allow them to override the committed portal configuration. The supported fallback variable names are:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

The build writes the two public values into `dist/config.js`. If the committed configuration is removed, these environment variables become the fallback. If neither source is complete, the deployed portal shows a setup screen.

In Supabase **Authentication → URL Configuration**, add the production Vercel URL to the allowed redirect URLs so magic-link sign-in can return to the portal.

## 5. Authentication and access

The product currently supports password and magic-link sign-in. Public self-registration is not exposed.

| Role | Intended access |
| --- | --- |
| Admin | Programme setup, participants, user access, modules, attendance and reports |
| Mentor | Assigned cohorts, participant monitoring, attendance and reports |
| Stakeholder | Read-only programme analytics and reports for assigned cohorts |
| Participant | Own learning, private notes, quizzes, attendance and business check-ins |

An Auth user who lacks an active `m_memberships` record sees an **Access pending** screen. This prevents existing ChronoSphere users from entering the portal merely because they already belong to the same Supabase project.

## Current product stage

Implemented in this package:

- clean production interface with no sample records;
- Supabase session handling;
- password and magic-link sign-in;
- membership and role gate;
- role-specific navigation;
- programme overview metrics and participant demographic summaries;
- administrator user, role, cohort access and mentor-assignment screens;
- courses with multiple modules and video, text, workbook and test sections;
- participant module viewer, private notes and server-graded tests;
- physical, Zoom, Teams and other class registers;
- mentor attendance marking limited to assigned mentees;
- isolated production schema;
- protected quiz answer keys and server-side quiz grading function;
- Vercel environment configuration and security headers.

Still to be developed:

- direct file uploads to Supabase Storage (the current authoring screen accepts external links and text);
- monthly business submission forms;
- downloadable stakeholder report generation;
- an approved user interface for the optional social-media monitoring tables;
- audit log, notifications, backups and operational monitoring.

## Commands

- `npm start` — local server on port 3000.
- `npm run check` — JavaScript syntax and production-content validation.
- `npm run build` — generates the static `dist` folder for Vercel.

No package installation is required for this foundation. The browser loads the Supabase JavaScript client from jsDelivr. A later application phase can move to a bundled framework if server-rendered routes or a larger component system becomes necessary.
