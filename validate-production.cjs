const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const forbiddenFiles = [
  'data.js',
  'store.js',
  'demo-lesson.mp4',
  'demo-lesson.vtt',
  'tests/prototype.test.cjs',
  'tests/interface.test.cjs'
];
const forbiddenTerms = [
  'Regional stakeholder',
  'Aina Rahman',
  'Daniel Lee',
  'EKU-001',
  'fictional data',
  'Reset demo',
  'Preview as'
];

for (const file of forbiddenFiles) {
  if (fs.existsSync(path.join(root, file))) throw new Error(`Prototype file still exists: ${file}`);
}

const sourceFiles = ['index.html', 'app.js', 'config.js', 'README.md'];
for (const file of sourceFiles) {
  const text = fs.readFileSync(path.join(root, file), 'utf8');
  for (const term of forbiddenTerms) {
    if (text.includes(term)) throw new Error(`Prototype content remains in ${file}: ${term}`);
  }
}

const migration = fs.readFileSync(path.join(root, 'supabase/migrations/001_m_foundation.sql'), 'utf8');
const upgrade = fs.readFileSync(path.join(root, 'supabase/migrations/002_admin_learning_attendance.sql'), 'utf8');
const onboarding = fs.readFileSync(path.join(root, 'supabase/migrations/003_cohort_signup_assessments.sql'), 'utf8');
const workflows = fs.readFileSync(path.join(root, 'supabase/migrations/004_product_workflows.sql'), 'utf8');
for (const table of ['m_memberships', 'm_programmes', 'm_cohorts', 'm_participants', 'm_modules', 'm_module_resources', 'm_quiz_questions']) {
  if (new RegExp(`insert\\s+into\\s+(public\\.)?${table}\\b`, 'i').test(migration)) throw new Error(`Foundation migration seeds ${table}.`);
}
if (!migration.includes('enable row level security')) throw new Error('RLS is missing from the portal migration.');
if (migration.includes('revoke all on all tables in schema public')) throw new Error('Migration must not alter grants for unrelated application tables.');
if (/insert\s+into\s+(public\.)?m_/i.test(upgrade)) throw new Error('Product upgrade migration must not seed portal records.');
for (const required of ['m_courses', 'm_social_accounts', 'm_social_snapshots']) {
  if (!upgrade.includes(required)) throw new Error(`Product upgrade is missing ${required}.`);
}
for (const required of ['m_signup_codes', 'm_create_signup_code', 'm_validate_signup_code', 'm_course_assignments', 'm_assessments', 'm_assessment_questions', 'm_assessment_submissions', 'm_notifications', 'm_submit_assessment', 'm_grade_submission']) {
  if (!onboarding.includes(required)) throw new Error(`Cohort and assessment migration is missing ${required}.`);
}
if (fs.existsSync(path.join(root, 'supabase/functions/m-admin-user/index.ts'))) throw new Error('Obsolete administrator invitation function still exists.');
if (fs.readFileSync(path.join(root, 'app.js'), 'utf8').includes("functions.invoke('m-admin-user'")) throw new Error('Browser still invokes the obsolete invitation function.');
if (!onboarding.trimEnd().endsWith('Existing and new installations remain free of dummy data.')) throw new Error('Cohort and assessment migration must end without seed data.');
if (!onboarding.includes("extensions.digest(raw_code, 'sha256')") || !onboarding.includes('extensions.gen_random_bytes(8)')) throw new Error('Supabase pgcrypto functions must use the extensions schema.');
for (const required of ['m_staff_invites', 'm_create_staff_invite', 'm_save_business_profile', 'm_course_cohort_access', 'm_course_path', 'm_can_start_assessment', 'max_attempts', 'm-participant-avatars']) {
  if (!workflows.includes(required)) throw new Error(`Product workflow migration is missing ${required}.`);
}
if (fs.readFileSync(path.join(root, 'app.js'), 'utf8').includes('assign-modal')) throw new Error('Individual course assignment remains in People & Access.');
if (!workflows.trimEnd().endsWith('assessments or business records are inserted.')) throw new Error('Product workflow migration must end without demonstration records.');

console.log('Production validation passed: staff invitations, business onboarding, cohort course access, ordered learning, no prototype records/media, and portal RLS are present.');
