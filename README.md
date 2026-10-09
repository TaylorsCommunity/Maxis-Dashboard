# Maxis eKelas Usahawan — Learning & Impact Portal

Version 3 is a complete redesign of the earlier monitoring prototype. It is a separate product from ChronoSphere. The interface follows the supplied slide palette: white surfaces, forest-green headings, lime highlights and a restrained blue accent. Reporting uses clear KPI cards, demographic breakdowns and progress tables.

## Open in VS Code

1. Extract the ZIP and open `Maxis-Prototype` in VS Code.
2. Open a terminal in that folder. Install Node.js 18 or later if needed.
3. Run `npm start`. No `npm install` or API keys are needed.
4. Open `http://localhost:3000` in your browser.

`npm run check` checks source syntax; `npm test` runs the included dependency-free integration checks. Use the server rather than double-clicking the HTML so the video, captions and exports work consistently. If port 3000 is busy, close the other local server or set another `PORT`.

## Deploy to Vercel

This version includes a static Vercel build. Vercel should serve the generated `dist` folder and must not run the local preview server as a function.

1. Upload or connect the **`Maxis-Prototype` folder itself** as the Vercel project root. `package.json` and `vercel.json` must be visible at that root.
2. Deploy. The included configuration sets Framework Preset to **Other**, runs `npm run build`, and serves `dist`.
3. If this Vercel project previously had manual overrides, open **Project Settings → Build and Deployment**. Turn off the existing overrides, or set Build Command to `npm run build` and Output Directory to `dist`, then redeploy without the previous build cache.

Do not set the Build Command to `npm start` or `node local-server.cjs`. Those commands start the local preview server. Vercel should serve the static `dist` output.

## Four role previews

Select **Preview as** at the top, then choose a user.

| Role | Navigation and access |
| --- | --- |
| Participant | My learning, My business, My profile. Assigned published modules, video, readings, downloadable workbooks, private notes, quizzes, own financial check-ins, own photo and class history. |
| Programme admin | Programme overview, People & access, Learning content, Live attendance, Reports. Enrol participants, assign mentors and modules, enable/disable participant workspaces, manage staff cohort permissions, publish content and configure quizzes. |
| Mentor | Cohort overview, Participants, Live attendance, Reports. Views accessible cohorts; edits business check-ins only for assigned participants. Records attendance for the whole accessible programme/cohort roster. |
| Maxis stakeholder | Programme overview and Reports. Read-only analytics, state/gender breakdowns, module completion, class requirements and participant progress within authorised cohorts. |

Try **Regional stakeholder** to see a user restricted to the Northern/Penang cohort. Participant notes are never shown in admin, mentor or stakeholder profiles/reports.

This supersedes the earlier design where participants had no accounts. Participant access is now part of the proposed product, simulated by the local preview selector.

## Demonstrate the learning experience

- Switch to Participant, choose a learner and open an assigned module.
- Module 1 includes a local 16-second demonstration video with English captions. Use the contents panel to open it; a previously completed module may initially open the knowledge check.
- Read materials, download the workbook, save a private note and click **Mark as studied** for each resource.
- The quiz unlocks once every resource is studied. Select an answer to every question and submit.
- Failed attempts show feedback and allow retries. A passing attempt plus all studied resources completes the module. Subsequent failed retries do not remove an earlier passing result for the same revision.
- Switch to Maxis or admin to see the updated module and pathway totals.

Resources are explicitly marked as studied by the participant. The prototype does not measure video watch duration or independently verify engagement.

## Demonstrate administration

- **People & access → Add participant:** name, business, demographics, cohort, mentor, baseline sales/costs, required class count, participant-access checkbox and module assignments.
- Open a profile to edit access, change assignments or upload/remove a photo. Photos start blank; no faces are generated.
- **Staff & stakeholders:** add a mentor/stakeholder and choose the cohorts they can access. Mentors must be reassigned before their cohort access is removed.
- **Learning content → Create module:** enter settings, add readings/video URLs/workbooks, configure quiz questions, publish, then assign the module through the participant form.
- Videos support HTTPS MP4 or YouTube URLs. External videos require internet access and may depend on the provider's embedding settings.
- Workbooks can contain downloadable text or a local PDF upload up to 1 MB. Photos accept JPG/PNG/WebP up to 2 MB and are resized to 600 px.
- Resource/quiz changes, or a changed pass mark, create a new revision and reset current completion. Existing private notes remain available for unchanged resource IDs. This is a deliberately simple prototype revision model; historical completion reporting would need a server-side revision ledger.

## Live class attendance

1. Admin or mentor opens **Live attendance** and selects programme, cohort and meeting number.
2. Create a meeting with a number, date and title. Reusing a meeting number in that programme/cohort opens the existing register.
3. Mark each participant **Present**, **Absent** or **Not marked**. The entire cohort is shown, not just one mentor's assigned participants.
4. Changes appear immediately in the participant's class history as a live draft.
5. Finalize after everyone is marked. Only finalized registers enter attendance percentages and class requirements.
6. Reopen to correct, then finalize again. A previously finalized roster remains frozen, including during correction, so new participants are not marked absent for past sessions. New draft registers can pick up later enrolments.

## Stakeholder reporting

**Programme overview** shows participant enrolment, online pathway completions, participant-module completions and participants meeting their class requirement. State and gender charts can be clicked to filter. Programme/cohort/state/gender filters apply to progress tables and reports. Business outcomes and consented stories are consolidated into one expandable section rather than repeated tabs.

**Reports** provides Programme impact, Learning & completion, and Class attendance reports. Generate a preview, download scoped CSV/standalone HTML, or use Print / Save as PDF. Reports are generated on demand; scheduled delivery and AI-written narratives are not implemented.

The business reporting month filters financial records. Online learning is the current cumulative position; finalized class attendance is cumulative across dates. These scopes are labelled separately rather than implying the business month filters learning or class counts.

## Metric definitions

- **Participants enrolled:** all participant records in the accessible, selected scope, including participants whose workspace access is currently disabled.
- **Module completion:** all resources marked studied plus a quiz result at or above the configured pass mark for the current module revision.
- **Online pathway completion:** every assigned, eligible, published module completed. No module assignment does not count as a completed pathway.
- **Module completion rate:** completed participant-module assignments divided by eligible published participant-module assignments. This is not a headcount.
- **Class requirement met:** present marks in finalized registers reach the participant's admin-configured required class count. Demo targets are 4 for Accelerator and 2 for Digital Marketing; these are illustrative and editable.
- **Programme complete:** online pathway complete AND the class requirement met. It is not an independently issued certification.
- **Finalized class registers:** number of finalized meeting registers; distinct from participants meeting a class requirement.
- **Attendance rate:** present marks divided by participant attendance opportunities in finalized registers. Drafts are excluded. No finalized history is shown as a dash, not fabricated zero.
- **Average participant monthly income:** average business net income, sales minus operating costs, among participants with a record for the selected month. This is not household income. Missing records are excluded, not treated as zero.
- **Income growth:** matched follow-up income vs matched positive baseline income. Zero, negative and missing baselines are excluded from percentage growth.
- **Reporting coverage:** submitted monthly check-ins divided by participants in scope. One record per participant/month; edits replace that record.
- **Mentor reviewed:** review status set by a mentor/admin, not independently verified financial evidence. A participant edit returns the record to self-reported.
- **Stories:** shown in stakeholder reports only when the monthly story consent is enabled.

## Prototype boundaries and future backend

All 30 seed participants, states, demographics, financial figures, quiz results, class registers and testimonials are fictional. They are not findings from the MBR impact report or Maxis programme outcomes. The demonstration lesson is not approved programme training material.

Everything is stored locally using `maxis-learning-impact-v3` in browser localStorage. It is not synced between users/devices. The selector is not authentication, and browser data can be inspected regardless of simulated roles. Use fictional information. Supabase and Vercel are not connected by this package.

A production implementation needs Supabase Auth, server-enforced cohort/role permissions and row-level security, durable database/storage, protected video/material access, quiz grading on the server, audit history, backup/recovery and deployment configuration. Real quiz answer keys must not be shipped to the participant browser as in this demonstration.

The new storage key does not migrate earlier local prototype edits, and **Reset demo** leaves older prototype storage untouched. Reset removes all version-3 edits, uploaded files and notes. If storage is full, the failed change is rolled back and a message is shown.

## Files

| File | Purpose |
| --- | --- |
| `index.html` / `brand.js` / `maxis-logo.png` | Workspace shell, supplied Maxis logo and embedded report logo |
| `style.css` | Reference palette, responsive interface and print styles |
| `data.js` | Fictional participants, courses, users and registers |
| `store.js` | Shared data, permission checks, learning outcomes, calculations and persistence |
| `app.js` | Role-based pages, forms, learning player, live attendance and exports |
| `demo-lesson.mp4` / `.vtt` | Local demonstration lesson and captions |
| `local-server.cjs` | Dependency-free local preview server, including media range support |
| `build-static.cjs` / `vercel.json` | Static Vercel build and deployment settings |
| `tests/prototype.test.cjs` | Integration checks for learning, access, reporting, attendance and persistence |

The previous hosted concept has not been republished by this code-package update.
