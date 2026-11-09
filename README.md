# eKelas Usahawan — Learning & Impact Portal

Version 4.0.2 is the clean production foundation. It contains no demonstration participants, users, modules, videos, quizzes, attendance, financial records or testimonials. The role simulator and browser-local database have been removed.

The supplied Supabase project URL and publishable key are configured in `portal.config.json`. The endpoint has been verified, but the `m_*` tables do not exist yet. Run the included migration before using the portal.

## Architecture decision

This package can use the existing ChronoSphere Supabase project without mixing application data:

- Every portal table, function, type, index and policy begins with `m_` as this project's database signature.
- Supabase Authentication remains project-wide, so both applications' identities appear in the same `auth.users` directory.
- A valid Auth account receives no portal access unless it also has an active row in `m_memberships`.
- Row Level Security restricts data by role, participant identity and assigned cohorts.
- No ChronoSphere table, policy or grant is modified by the portal migration.

If completely separate Auth users, email templates, backups and database administration are required later, move the same schema to a separate Supabase project and change only the environment variables.

## 1. Create the database foundation

1. Open the intended Supabase project.
2. Open **SQL Editor**.
3. Run `supabase/migrations/001_m_foundation.sql` once.
4. Confirm that the new `m_` tables appear in Table Editor.

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

This bootstrap is intentionally manual. The browser must never receive a Supabase service-role key. A secure admin invitation workflow can be added as a server-side function in the next development phase.

## 3. Connection configuration

The package is already linked to the supplied project URL using its publishable browser key. Publishable keys are expected to be visible in a web application's source; data protection comes from Authentication and Row Level Security. Never place a secret or service-role key in this repository or browser configuration.

### Local preview

Run `npm start` and open `http://localhost:3000`. No connection variables are required for this configured package.

Open `http://localhost:3000`.

### Vercel

The committed public configuration works without Vercel environment variables. To override it for another Supabase project, add these in **Project Settings → Environment Variables**:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Then redeploy. The build writes the two public values into `dist/config.js`. If either value is missing, the deployed portal shows a setup screen.

In Supabase **Authentication → URL Configuration**, add the production Vercel URL to the allowed redirect URLs so magic-link sign-in can return to the portal.

## 4. Authentication and access

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
- live empty-state/count queries protected by RLS;
- isolated production schema;
- protected quiz answer keys and server-side quiz grading function;
- Vercel environment configuration and security headers.

Still to be developed after the live connection is confirmed:

- admin forms for creating programmes, cohorts, users and participants;
- secure user invitations through a server-side function;
- module/video/workbook upload and authoring;
- participant lesson player, notes and quiz interface;
- live attendance marking workflow;
- monthly business submission forms;
- stakeholder charts and report generation;
- audit log, notifications, backups and operational monitoring.

## Commands

- `npm start` — local server on port 3000.
- `npm run check` — JavaScript syntax and production-content validation.
- `npm run build` — generates the static `dist` folder for Vercel.

No package installation is required for this foundation. The browser loads the Supabase JavaScript client from jsDelivr. A later application phase can move to a bundled framework if server-rendered routes or a larger component system becomes necessary.
