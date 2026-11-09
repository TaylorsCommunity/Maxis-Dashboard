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
for (const table of ['m_memberships', 'm_programmes', 'm_cohorts', 'm_participants', 'm_modules', 'm_module_resources', 'm_quiz_questions']) {
  if (new RegExp(`insert\\s+into\\s+(public\\.)?${table}\\b`, 'i').test(migration)) throw new Error(`Foundation migration seeds ${table}.`);
}
if (!migration.includes('enable row level security')) throw new Error('RLS is missing from the portal migration.');
if (migration.includes('revoke all on all tables in schema public')) throw new Error('Migration must not alter grants for unrelated application tables.');
if (/insert\s+into\s+(public\.)?m_/i.test(upgrade)) throw new Error('Product upgrade migration must not seed portal records.');
for (const required of ['m_courses', 'm_social_accounts', 'm_social_snapshots']) {
  if (!upgrade.includes(required)) throw new Error(`Product upgrade is missing ${required}.`);
}
if (!fs.existsSync(path.join(root, 'supabase/functions/m-admin-user/index.ts'))) throw new Error('Administrator invitation function is missing.');

console.log('Production validation passed: no prototype records/media, no seed inserts, and portal RLS is present.');
