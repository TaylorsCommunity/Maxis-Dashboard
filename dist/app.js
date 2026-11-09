(() => {
  'use strict';

  const $ = id => document.getElementById(id);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const opt = (value, label, selected = false) => `<option value="${esc(value)}" ${selected ? 'selected' : ''}>${esc(label)}</option>`;
  const state = { client: null, session: null, member: null, page: 'overview', sessionId: null, moduleId: null, participantId: null };

  const navigation = {
    admin: [['overview', 'Programme overview', 'overview'], ['people', 'People & access', 'people'], ['learning', 'Courses & modules', 'learning'], ['attendance', 'Live attendance', 'attendance'], ['reports', 'Reports', 'reports']],
    mentor: [['overview', 'Mentor overview', 'overview'], ['people', 'My mentees', 'people'], ['attendance', 'Live attendance', 'attendance'], ['reports', 'Reports', 'reports']],
    stakeholder: [['overview', 'Programme overview', 'overview'], ['reports', 'Reports', 'reports']],
    participant: [['learning', 'My learning', 'learning'], ['business', 'My business', 'business']]
  };

  function icon(name) {
    const paths = {
      overview: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>',
      people: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 1 3-3.87"/>',
      learning: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
      attendance: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M8 15l2 2 5-5"/>',
      reports: '<path d="M3 3v18h18"/><path d="M7 16l4-4 3 3 5-7"/>',
      business: '<rect x="3" y="7" width="18" height="14" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12h18"/>',
      plus: '<path d="M12 5v14M5 12h14"/>'
    };
    return `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.overview}</svg>`;
  }

  function toast(message) { const el = $('toast'); el.textContent = message; el.classList.add('show'); setTimeout(() => el.classList.remove('show'), 3500); }
  function initials(name) { return String(name || 'TC').split(/\s+/).filter(Boolean).slice(0, 2).map(v => v[0]).join('').toUpperCase(); }
  function head(title, description, eyebrow = 'PORTAL', actions = '') { return `<div class="page-head"><div><div class="eyebrow">${esc(eyebrow)}</div><h1>${esc(title)}</h1><p>${esc(description)}</p></div>${actions ? `<div class="actions">${actions}</div>` : ''}</div>`; }
  function empty(title, description, iconName = 'overview') { return `<div class="empty-product">${icon(iconName)}<h2>${esc(title)}</h2><p>${esc(description)}</p></div>`; }
  function stat(label, value, note) { return `<div class="stat"><span class="label">${esc(label)}</span><strong>${esc(value)}</strong><small>${esc(note)}</small></div>`; }
  function modal(id, title, description, body, submit = 'Save') { return `<dialog id="${id}"><form id="${id}-form"><div class="modal-head"><div><h2>${esc(title)}</h2><p>${esc(description)}</p></div><button class="close-btn" type="button" data-close-dialog>×</button></div><div class="modal-body">${body}<div class="form-actions"><button class="secondary" type="button" data-close-dialog>Cancel</button><button class="primary" type="submit">${esc(submit)}</button></div></div></form></dialog>`; }

  async function rows(table, columns = '*', configure = q => q) { const { data, error } = await configure(state.client.from(table).select(columns)); if (error) throw error; return data || []; }
  async function count(table, configure = q => q) { const { count: total, error } = await configure(state.client.from(table).select('*', { count: 'exact', head: true })); if (error) throw error; return total || 0; }
  async function save(operation, message) { const { error } = await operation; if (error) throw error; toast(message); }

  function renderLogin(message = '', type = '') {
    $('sidebar').hidden = true; document.querySelector('.shell').style.marginLeft = '0'; $('account-control').hidden = true;
    $('content').innerHTML = `<div class="auth-layout"><section class="auth-card"><div class="eyebrow">LEARNING & IMPACT PORTAL</div><h1>Welcome back</h1><p>Sign in using the email registered by the programme administrator.</p><form id="password-login"><label class="field">Email<input type="email" name="email" required></label><label class="field">Password<input type="password" name="password" required minlength="8"></label><button class="primary" type="submit">Sign in</button></form><div class="auth-divider">OR</div><form id="magic-login"><label class="field">Email<input type="email" name="email" required></label><button class="secondary" type="submit" style="width:100%;margin-top:14px">Send magic link</button></form><div id="login-message" class="login-message ${esc(type)}">${esc(message)}</div></section></div>`;
  }

  function renderNoAccess() {
    $('sidebar').hidden = true; document.querySelector('.shell').style.marginLeft = '0'; $('account-control').hidden = false;
    const email = state.session?.user?.email || ''; $('account-name').textContent = email; $('account-avatar').textContent = initials(email);
    $('content').innerHTML = `<section class="card access-card"><div class="eyebrow">ACCESS PENDING</div><h1>Your account is not assigned to this portal</h1><p>An administrator must activate your membership and role.</p><button class="secondary" id="retry-access">Check access again</button></section>`;
  }

  function renderShell() {
    const nav = navigation[state.member.role] || [];
    if (state.page !== 'account' && !nav.some(v => v[0] === state.page)) state.page = nav[0]?.[0] || 'overview';
    $('sidebar').hidden = false; document.querySelector('.shell').style.marginLeft = ''; $('account-control').hidden = false;
    $('account-name').textContent = state.member.display_name; $('account-avatar').textContent = initials(state.member.display_name);
    $('nav').innerHTML = nav.map(([id, label, ico]) => `<button data-page="${id}" class="${state.page === id ? 'active' : ''}">${icon(ico)}${esc(label)}</button>`).join('');
    $('crumb').textContent = state.page === 'account' ? 'Account' : nav.find(v => v[0] === state.page)?.[1] || 'Portal';
  }

  function bars(items, key) {
    const map = new Map(); items.forEach(item => { const value = item[key] || 'Not provided'; map.set(value, (map.get(value) || 0) + 1); });
    const max = Math.max(1, ...map.values());
    return [...map].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([label, value]) => `<div class="bar-row"><div class="bar-meta"><span>${esc(label)}</span><b>${value}</b></div><div class="progress"><i style="width:${Math.round(value / max * 100)}%"></i></div></div>`).join('');
  }

  async function overview() {
    const [participants, courseCount, modules, classes, checkins, assignments, attempts] = await Promise.all([
      rows('m_participants', 'id,state,gender'), count('m_courses', q => q.eq('active', true)), count('m_modules', q => q.eq('published', true)), count('m_attendance_sessions', q => q.eq('finalized', true)), rows('m_business_checkins', 'participant_id,sales,operating_costs'), rows('m_module_assignments', 'participant_id,module_id'), rows('m_quiz_attempts', 'participant_id,module_id,passed')
    ]);
    const passed = new Set(attempts.filter(v => v.passed).map(v => `${v.participant_id}:${v.module_id}`));
    const completion = assignments.length ? Math.round(assignments.filter(v => passed.has(`${v.participant_id}:${v.module_id}`)).length / assignments.length * 100) : 0;
    const income = checkins.length ? Math.round(checkins.reduce((sum, v) => sum + Number(v.sales || 0) - Number(v.operating_costs || 0), 0) / checkins.length) : 0;
    return `${head(state.member.role === 'mentor' ? 'Mentor overview' : 'Programme overview', 'Current programme participation, learning completion and outcomes within your authorised scope.', `${state.member.role.toUpperCase()} WORKSPACE`)}<div class="stats">${stat('Participants', participants.length, 'Visible active profiles')}${stat('Active courses', courseCount, `${modules} published modules`)}${stat('Module completion', `${completion}%`, `${assignments.length} assignments`)}${stat('Average participant income', `RM ${income.toLocaleString('en-MY')}`, 'Average monthly net income submitted')}</div><div class="grid-equal"><section class="card"><div class="card-head"><div><h2>Participants by state</h2><p>Based on participant profiles</p></div></div>${participants.length ? bars(participants, 'state') : empty('No participant profiles', 'State analytics will appear after enrolment.', 'people')}</section><section class="card"><div class="card-head"><div><h2>Participants by gender</h2><p>Only supplied values are counted</p></div></div>${participants.length ? bars(participants, 'gender') : empty('No demographic data', 'Gender analytics will appear after enrolment.', 'people')}</section></div><section class="card"><div class="funnel"><div><span>Finalized classes</span><strong>${classes}</strong></div><div><span>Business submissions</span><strong>${checkins.length}</strong></div><div><span>Learning assignments</span><strong>${assignments.length}</strong></div><div><span>Passed modules</span><strong>${passed.size}</strong></div></div></section>`;
  }

  function membershipTable(members) {
    return `<div class="table-wrap"><table><thead><tr><th>User</th><th>Role</th><th>Active</th><th></th></tr></thead><tbody>${members.map(v => `<tr data-membership="${v.user_id}"><td><strong>${esc(v.display_name)}</strong></td><td><select class="inline-select" data-role>${['admin', 'mentor', 'stakeholder', 'participant'].map(role => opt(role, role, role === v.role)).join('')}</select></td><td><input data-active type="checkbox" ${v.active ? 'checked' : ''}></td><td><button class="secondary btn-sm" data-save-member>Save</button></td></tr>`).join('')}</tbody></table></div>`;
  }

  function participantTable(participants, cohorts, mentors, editable) {
    const cohortMap = new Map(cohorts.map(v => [v.id, v.name]));
    return `<div class="table-wrap"><table><thead><tr><th>Participant</th><th>Business</th><th>Cohort</th><th>Mentor</th>${editable ? '<th></th>' : ''}</tr></thead><tbody>${participants.map(v => `<tr data-participant="${v.id}"><td><strong>${esc(v.full_name)}</strong><small>${esc(v.email || v.state || '—')}</small></td><td>${esc(v.business_name || '—')}</td><td>${esc(cohortMap.get(v.cohort_id) || 'Assigned cohort')}</td><td>${editable ? `<select class="inline-select" data-mentor><option value="">Unassigned</option>${mentors.map(m => opt(m.user_id, m.display_name, m.user_id === v.mentor_user_id)).join('')}</select>` : 'Assigned to you'}</td>${editable ? '<td><button class="secondary btn-sm" data-save-mentor>Save</button></td>' : ''}</tr>`).join('')}</tbody></table></div>`;
  }

  async function people() {
    const participants = await rows('m_participants', 'id,user_id,cohort_id,mentor_user_id,full_name,business_name,email,state,active', q => q.order('full_name'));
    if (state.member.role !== 'admin') return `${head('My mentees', 'Participants assigned to you by an administrator.', 'MENTOR WORKSPACE')}<section class="card">${participants.length ? participantTable(participants, [], [], false) : empty('No mentees assigned', 'An administrator can assign participants to you.', 'people')}</section>`;
    const [members, cohorts, programmes] = await Promise.all([rows('m_memberships', 'user_id,display_name,role,active', q => q.order('display_name')), rows('m_cohorts', 'id,name,state', q => q.order('name')), rows('m_programmes', 'id,name,active', q => q.order('name'))]);
    const mentors = members.filter(v => v.role === 'mentor' && v.active);
    const actions = `<button class="secondary" data-open="programme-modal">New programme</button><button class="secondary" data-open="cohort-modal">New cohort</button><button class="secondary" data-open="access-modal">Cohort access</button><button class="secondary" data-open="assign-modal">Assign course</button><button class="primary" data-open="user-modal">${icon('plus')} Add user</button>`;
    const userForm = `<div class="form-grid"><label class="field">Full name<input name="display_name" required></label><label class="field">Email<input type="email" name="email" required></label><label class="field">Role<select name="role" id="new-role"><option value="participant">Participant</option><option value="mentor">Mentor</option><option value="stakeholder">Stakeholder</option><option value="admin">Administrator</option></select></label><label class="field participant-only">Cohort<select name="cohort_id"><option value="">Select cohort</option>${cohorts.map(v => opt(v.id, v.name)).join('')}</select></label><label class="field participant-only">Mentor<select name="mentor_user_id"><option value="">Assign later</option>${mentors.map(v => opt(v.user_id, v.display_name)).join('')}</select></label><label class="field participant-only">Business name<input name="business_name"></label><label class="field participant-only">State<input name="state"></label><p class="help-text full">The user receives an invitation email. Participant profiles are created automatically.</p></div>`;
    const accessUsers = members.filter(v => ['mentor', 'stakeholder'].includes(v.role));
    const accessForm = `<div class="form-grid"><label class="field">User<select name="user_id" required><option value="">Select user</option>${accessUsers.map(v => opt(v.user_id, `${v.display_name} · ${v.role}`)).join('')}</select></label><label class="field">Cohort<select name="cohort_id" required><option value="">Select cohort</option>${cohorts.map(v => opt(v.id, v.name)).join('')}</select></label></div>`;
    const assignForm = `<div class="form-grid"><label class="field">Participant<select name="participant_id" required><option value="">Select participant</option>${participants.map(v => opt(v.id, v.full_name)).join('')}</select></label><label class="field">Course<select name="course_id" id="assign-course" required><option value="">Select course</option></select></label></div>`;
    const programmeForm = `<div class="form-grid"><label class="field full">Programme name<input name="name" required></label><label class="field full">Description<textarea name="description"></textarea></label></div>`;
    const cohortForm = `<div class="form-grid"><label class="field">Programme<select name="programme_id" required><option value="">Select programme</option>${programmes.map(v => opt(v.id, v.name)).join('')}</select></label><label class="field">Cohort name<input name="name" required></label><label class="field">State<input name="state"></label><label class="field">Start date<input type="date" name="starts_on"></label><label class="field">End date<input type="date" name="ends_on"></label></div>`;
    return `${head('People & access', 'Invite users, control roles, assign mentors and grant programme access.', 'ADMINISTRATION', actions)}<section class="card section-gap"><div class="card-head"><div><h2>Portal users</h2><p>Authentication access and portal roles</p></div></div>${members.length ? membershipTable(members) : empty('No users', 'Invite the first portal user.', 'people')}</section><section class="card"><div class="card-head"><div><h2>Participant and mentor assignments</h2><p>Administrators control mentor assignment</p></div></div>${participants.length ? participantTable(participants, cohorts, mentors, true) : empty('No participants', 'Create a programme and cohort, then invite a participant.', 'people')}</section>${modal('programme-modal', 'New programme', 'Create the programme that will contain one or more cohorts.', programmeForm, 'Create programme')}${modal('cohort-modal', 'New cohort', 'Create a participant cohort inside a programme.', cohortForm, 'Create cohort')}${modal('user-modal', 'Add portal user', 'Invite an administrator, mentor, stakeholder or participant.', userForm, 'Invite user')}${modal('access-modal', 'Grant cohort access', 'Give a mentor or stakeholder access to a cohort.', accessForm, 'Grant access')}${modal('assign-modal', 'Assign course', 'Assign every current module in a course to a participant.', assignForm, 'Assign course')}`;
  }

  async function learning() { return state.member.role === 'admin' ? courseAdmin() : participantLearning(); }

  async function courseAdmin() {
    const [courses, modules, resources, questions] = await Promise.all([rows('m_courses', '*', q => q.order('created_at')), rows('m_modules', 'id,course_id,title,description,sequence_number,pass_mark,published', q => q.order('sequence_number')), rows('m_module_resources', 'id,module_id,title,kind'), rows('m_quiz_questions', 'id,module_id')]);
    const actions = `<button class="secondary" data-open="module-modal">Add module</button><button class="primary" data-open="course-modal">${icon('plus')} Add course</button>`;
    const courseForm = `<div class="form-grid"><label class="field full">Course title<input name="title" required></label><label class="field full">Description<textarea name="description"></textarea></label></div>`;
    const moduleForm = `<div class="form-grid"><label class="field">Course<select name="course_id" required><option value="">Select course</option>${courses.map(v => opt(v.id, v.title)).join('')}</select></label><label class="field">Order<input type="number" name="sequence_number" min="1" value="1" required></label><label class="field full">Module title<input name="title" required></label><label class="field">Pass mark (%)<input type="number" name="pass_mark" min="0" max="100" value="70"></label><label class="field">Visibility<select name="published"><option value="false">Draft</option><option value="true">Published</option></select></label><label class="field full">Description<textarea name="description"></textarea></label></div>`;
    const sectionForm = `<div class="form-grid"><label class="field">Module<select name="module_id" required><option value="">Select module</option>${modules.map(v => opt(v.id, v.title)).join('')}</select></label><label class="field">Type<select name="kind" id="section-type"><option value="reading">Text / reading</option><option value="video">Video</option><option value="workbook">Workbook / file link</option><option value="test">Test question</option></select></label><label class="field full normal-section">Section title<input name="title"></label><label class="field full normal-section">Text content<textarea name="content"></textarea></label><label class="field full normal-section">External URL<input type="url" name="external_url" placeholder="https://"></label><div class="test-section full" hidden><label class="field">Question<textarea name="prompt"></textarea></label><label class="field">Options, one per line<textarea name="options"></textarea></label><label class="field">Correct option number<input type="number" name="correct_option" min="1" value="1"></label><label class="field">Feedback<textarea name="feedback"></textarea></label></div><label class="field">Order<input type="number" name="sequence_number" min="1" value="1"></label></div>`;
    const cards = courses.map(course => { const list = modules.filter(v => v.course_id === course.id); return `<section class="card course-card"><div class="card-head"><div><span class="pill">Active course</span><h2>${esc(course.title)}</h2><p>${esc(course.description || 'No description')}</p></div><strong>${list.length} modules</strong></div>${list.length ? `<div class="module-list">${list.map(module => { const total = resources.filter(v => v.module_id === module.id).length + questions.filter(v => v.module_id === module.id).length; return `<article><div><span class="module-index">${module.sequence_number}</span><strong>${esc(module.title)}</strong><small>${total} sections · Pass mark ${module.pass_mark}%</small></div><div class="actions"><span class="pill ${module.published ? '' : 'gray'}">${module.published ? 'Published' : 'Draft'}</span><button class="secondary btn-sm" data-add-section="${module.id}">Add section</button><button class="secondary btn-sm" data-toggle-module="${module.id}" data-published="${module.published}">${module.published ? 'Unpublish' : 'Publish'}</button></div></article>`; }).join('')}</div>` : empty('No modules', 'Add the first module to this course.', 'learning')}</section>`; }).join('');
    return `${head('Courses & modules', 'Build courses with video, text, workbook and test sections.', 'LEARNING ADMINISTRATION', actions)}${cards || `<section class="card">${empty('Create your first course', 'Courses contain multiple modules and learning sections.', 'learning')}</section>`}${modal('course-modal', 'Add course', 'Create a learning course.', courseForm, 'Create course')}${modal('module-modal', 'Add module', 'Add a module inside a course.', moduleForm, 'Create module')}${modal('section-modal', 'Add module section', 'Add video, text, workbook material or a test question.', sectionForm, 'Add section')}`;
  }

  async function participantLearning() {
    if (state.moduleId) return moduleView(state.moduleId);
    const modules = await rows('m_modules', 'id,title,description,sequence_number,pass_mark,published', q => q.eq('published', true).order('sequence_number'));
    return `${head('My learning', 'Complete assigned modules and tests.', 'PARTICIPANT LEARNING')}<section class="card">${modules.length ? `<div class="grid-3">${modules.map(v => `<article class="card module-card"><div class="module-cover"><span class="module-number">MODULE ${v.sequence_number}</span>${icon('learning')}</div><div class="module-body"><span class="pill">Pass mark ${v.pass_mark}%</span><h2>${esc(v.title)}</h2><p>${esc(v.description || 'Learning module')}</p><button class="primary" data-open-module="${v.id}">Open module</button></div></article>`).join('')}</div>` : empty('No modules assigned', 'An administrator can assign a course to your profile.', 'learning')}</section>`;
  }

  function mediaBlock(resource) {
    if (resource.kind !== 'video' || !resource.external_url) return '';
    let embed = '';
    try {
      const url = new URL(resource.external_url);
      if (url.hostname.includes('youtube.com')) embed = `https://www.youtube.com/embed/${url.searchParams.get('v') || ''}`;
      else if (url.hostname === 'youtu.be') embed = `https://www.youtube.com/embed/${url.pathname.slice(1)}`;
      else if (url.hostname.includes('vimeo.com')) embed = `https://player.vimeo.com/video/${url.pathname.split('/').filter(Boolean).pop()}`;
    } catch {}
    return embed ? `<div class="video-frame"><iframe src="${esc(embed)}" title="${esc(resource.title)}" allowfullscreen></iframe></div>` : `<p><a class="secondary" href="${esc(resource.external_url)}" target="_blank" rel="noopener">Open video</a></p>`;
  }

  async function moduleView(moduleId) {
    const [moduleRows, resources, questions] = await Promise.all([
      rows('m_modules', 'id,title,description,pass_mark', q => q.eq('id', moduleId)),
      rows('m_module_resources', 'id,title,kind,content,external_url,sequence_number', q => q.eq('module_id', moduleId).order('sequence_number')),
      rows('m_quiz_questions', 'id,prompt,options,sequence_number', q => q.eq('module_id', moduleId).order('sequence_number'))
    ]);
    const module = moduleRows[0]; if (!module) throw new Error('Module not found or not assigned.');
    if (!state.participantId) { const { data, error } = await state.client.rpc('m_participant_id'); if (error) throw error; state.participantId = data; }
    const notes = state.participantId ? await rows('m_private_notes', 'resource_id,note', q => q.eq('participant_id', state.participantId)) : [];
    const noteMap = new Map(notes.map(v => [v.resource_id, v.note]));
    const sections = resources.map(resource => `<section class="card lesson-section"><span class="pill">${esc(resource.kind)}</span><h2>${esc(resource.title)}</h2>${mediaBlock(resource)}${resource.content ? `<div class="content-block">${esc(resource.content)}</div>` : ''}${resource.external_url && resource.kind !== 'video' ? `<p><a class="secondary" href="${esc(resource.external_url)}" target="_blank" rel="noopener">Open material</a></p>` : ''}<form class="note-form" data-resource="${resource.id}"><label class="field">My private notes<textarea name="note">${esc(noteMap.get(resource.id) || '')}</textarea></label><div class="actions"><button class="secondary btn-sm" type="button" data-studied="${resource.id}">Mark studied</button><button class="primary btn-sm" type="submit">Save notes</button></div></form></section>`).join('');
    const quiz = questions.length ? `<section class="card"><div class="card-head"><div><h2>Module test</h2><p>Pass mark ${module.pass_mark}%</p></div></div><form id="quiz-form" data-module="${module.id}">${questions.map((question, index) => `<fieldset class="quiz-question"><legend>${index + 1}. ${esc(question.prompt)}</legend>${(question.options || []).map((answer, answerIndex) => `<label class="quiz-answer"><input type="radio" name="${question.id}" value="${answerIndex}" required>${esc(answer)}</label>`).join('')}</fieldset>`).join('')}<button class="primary" type="submit">Submit test</button></form><div id="quiz-result"></div></section>` : '';
    return `${head(module.title, module.description || 'Assigned learning module', 'MY LEARNING', '<button class="secondary" id="back-modules">Back to modules</button>')}<div class="lesson-stack">${sections || empty('No learning sections', 'The administrator is still preparing this module.', 'learning')}${quiz}</div>`;
  }

  async function attendance() {
    if (state.sessionId) return register(state.sessionId);
    const [sessions, cohorts] = await Promise.all([rows('m_attendance_sessions', '*', q => q.order('session_date', { ascending: false })), rows('m_cohorts', 'id,name,state', q => q.order('name'))]);
    const cohortMap = new Map(cohorts.map(v => [v.id, v.name]));
    const body = `<div class="form-grid"><label class="field">Cohort<select name="cohort_id" required><option value="">Select cohort</option>${cohorts.map(v => opt(v.id, v.name)).join('')}</select></label><label class="field">Meeting number<input type="number" name="meeting_number" min="1" required></label><label class="field full">Class title<input name="title" required></label><label class="field">Date<input type="date" name="session_date" required></label><label class="field">Start time<input type="time" name="starts_at"></label><label class="field">Delivery<select name="delivery_mode"><option value="physical">Physical</option><option value="zoom">Zoom</option><option value="teams">Microsoft Teams</option><option value="other">Other</option></select></label><label class="field">Location<input name="location"></label><label class="field full">Meeting link<input type="url" name="join_url" placeholder="https://"></label></div>`;
    const actions = cohorts.length ? `<button class="primary" data-open="session-modal">${icon('plus')} New class register</button>` : '';
    return `${head('Live attendance', 'Record attendance for physical, Zoom or Microsoft Teams classes.', 'ATTENDANCE', actions)}<section class="card">${sessions.length ? `<div class="table-wrap"><table><thead><tr><th>Date</th><th>Cohort</th><th>Session</th><th>Delivery</th><th>Status</th><th></th></tr></thead><tbody>${sessions.map(v => `<tr><td>${esc(v.session_date)}<small>${esc(v.starts_at || '')}</small></td><td>${esc(cohortMap.get(v.cohort_id) || 'Cohort')}</td><td><strong>${esc(v.title)}</strong><small>Meeting ${v.meeting_number}</small></td><td>${esc(v.delivery_mode)}</td><td><span class="pill ${v.finalized ? '' : 'amber'}">${v.finalized ? 'Finalized' : 'Open'}</span></td><td><button class="secondary btn-sm" data-register="${v.id}">Open register</button></td></tr>`).join('')}</tbody></table></div>` : empty('No class registers', 'Create a register when a live class is scheduled.', 'attendance')}</section>${modal('session-modal', 'New class register', 'The session can be physical or hosted externally.', body, 'Create register')}`;
  }

  async function register(id) {
    const sessions = await rows('m_attendance_sessions', '*', q => q.eq('id', id)); const session = sessions[0]; if (!session) throw new Error('Session not found.');
    const [participants, records] = await Promise.all([rows('m_participants', 'id,full_name,business_name', q => q.eq('cohort_id', session.cohort_id).eq('active', true).order('full_name')), rows('m_attendance_records', 'participant_id,status', q => q.eq('session_id', id))]);
    const map = new Map(records.map(v => [v.participant_id, v.status])); const present = participants.filter(v => map.get(v.id) === 'present').length; const absent = participants.filter(v => map.get(v.id) === 'absent').length;
    const actions = `<button class="secondary" id="back-sessions">Back</button>${session.finalized ? '' : '<button class="primary" id="finalize-session">Finalize register</button>'}`;
    return `${head(session.title, `${session.session_date} · Meeting ${session.meeting_number} · ${session.delivery_mode}`, 'CLASS REGISTER', actions)}<div class="attendance-summary"><div><strong>${present}</strong><span>Present</span></div><div><strong>${absent}</strong><span>Absent</span></div><div><strong>${participants.length - present - absent}</strong><span>Unmarked</span></div></div><section class="card">${participants.length ? `<div class="table-wrap"><table><thead><tr><th>Participant</th><th>Business</th><th>Attendance</th></tr></thead><tbody>${participants.map(v => { const status = map.get(v.id) || 'unmarked'; return `<tr><td><strong>${esc(v.full_name)}</strong></td><td>${esc(v.business_name || '—')}</td><td><div class="status-buttons" data-attendee="${v.id}">${['present', 'absent', 'unmarked'].map(s => `<button data-status="${s}" class="${status === s ? `selected-${s}` : ''}" ${session.finalized ? 'disabled' : ''}>${s}</button>`).join('')}</div></td></tr>`; }).join('')}</tbody></table></div>` : empty('No assigned mentees', 'Only participants assigned to this mentor are shown.', 'people')}</section>`;
  }

  async function business() {
    const records = await rows('m_business_checkins', '*', q => q.order('reporting_month', { ascending: false }).limit(24));
    return `${head('My business', 'Review monthly business performance.', 'BUSINESS MONITORING')}<section class="card">${records.length ? `<div class="table-wrap"><table><thead><tr><th>Month</th><th>Sales</th><th>Costs</th><th>Net income</th><th>Review</th></tr></thead><tbody>${records.map(v => `<tr><td>${esc(v.reporting_month)}</td><td>RM ${Number(v.sales).toLocaleString('en-MY')}</td><td>RM ${Number(v.operating_costs).toLocaleString('en-MY')}</td><td>RM ${Number(v.sales - v.operating_costs).toLocaleString('en-MY')}</td><td><span class="pill ${v.mentor_reviewed ? '' : 'gray'}">${v.mentor_reviewed ? 'Reviewed' : 'Self-reported'}</span></td></tr>`).join('')}</tbody></table></div>` : empty('No monthly records', 'Your first business check-in will appear here.', 'business')}</section>`;
  }

  function account() {
    let ref = 'Configured project'; try { ref = new URL(window.PORTAL_CONFIG.supabaseUrl).hostname.split('.')[0]; } catch {}
    return `${head('Account', 'Profile and system details are kept here instead of the programme dashboard.', 'ACCOUNT')}<div class="grid-equal"><section class="card"><div class="card-head"><div><h2>Profile</h2><p>Your portal identity</p></div><span class="role-badge">${esc(state.member.role)}</span></div><dl class="definition-list"><dt>Name</dt><dd>${esc(state.member.display_name)}</dd><dt>Email</dt><dd>${esc(state.session.user.email)}</dd><dt>Role</dt><dd>${esc(state.member.role)}</dd><dt>Status</dt><dd>Active</dd></dl></section><section class="card"><div class="card-head"><div><h2>System connection</h2><p>Technical account information</p></div><span class="pill">Connected</span></div><dl class="definition-list"><dt>Database project</dt><dd>${esc(ref)}</dd><dt>Authentication</dt><dd>Supabase Auth</dd><dt>Protection</dt><dd>Row Level Security</dd><dt>Namespace</dt><dd>m_</dd></dl></section></div>`;
  }

  function reports() { return `${head('Reports', 'Generate stakeholder-ready programme reports from approved records.', 'REPORTING')}<section class="card">${empty('Reports will populate from live records', 'Demographics, completion, attendance, income outcomes and approved stories will be consolidated here.', 'reports')}</section>`; }

  async function loadPage() {
    renderShell(); $('account-menu').hidden = true; $('content').innerHTML = '<div class="loading-card">Loading live data…</div>';
    try {
      let html;
      if (state.page === 'overview') html = await overview(); else if (state.page === 'people') html = await people(); else if (state.page === 'learning') html = await learning(); else if (state.page === 'attendance') html = await attendance(); else if (state.page === 'business') html = await business(); else if (state.page === 'account') html = account(); else html = reports();
      $('content').innerHTML = html;
    } catch (error) { console.error(error); $('content').innerHTML = `${head('Database upgrade required', 'One or more product tables are unavailable.', 'ACTION REQUIRED')}<section class="notice amber">${esc(error.message)}</section>${empty('Run the product upgrade migration', 'Apply 002_admin_learning_attendance.sql and refresh.', 'overview')}`; }
  }

  async function loadMembership() {
    const { data, error } = await state.client.from('m_memberships').select('user_id,display_name,role,active').eq('user_id', state.session.user.id).eq('active', true).maybeSingle(); if (error) throw error;
    state.member = data; if (!data) renderNoAccess(); else loadPage();
  }

  document.addEventListener('click', async event => {
    try {
      const page = event.target.closest('[data-page]'); if (page && state.member) { state.page = page.dataset.page; state.sessionId = null; state.moduleId = null; await loadPage(); return; }
      if (event.target.closest('#account-trigger')) { $('account-menu').hidden = !$('account-menu').hidden; return; }
      if (event.target.closest('#sign-out')) { await state.client.auth.signOut(); return; }
      if (event.target.closest('#retry-access')) { await loadMembership(); return; }
      const open = event.target.closest('[data-open]'); if (open) { if (open.dataset.open === 'assign-modal') { const courses = await rows('m_courses', 'id,title', q => q.eq('active', true).order('title')); $('assign-course').innerHTML = '<option value="">Select course</option>' + courses.map(v => opt(v.id, v.title)).join(''); } $(open.dataset.open).showModal(); return; }
      const close = event.target.closest('[data-close-dialog]'); if (close) { close.closest('dialog').close(); return; }
      const addSection = event.target.closest('[data-add-section]'); if (addSection) { $('section-modal').querySelector('[name=module_id]').value = addSection.dataset.addSection; $('section-modal').showModal(); return; }
      const toggle = event.target.closest('[data-toggle-module]'); if (toggle) { await save(state.client.from('m_modules').update({ published: toggle.dataset.published !== 'true' }).eq('id', toggle.dataset.toggleModule), 'Module visibility updated.'); await loadPage(); return; }
      const saveMember = event.target.closest('[data-save-member]'); if (saveMember) { const tr = saveMember.closest('[data-membership]'); await save(state.client.from('m_memberships').update({ role: tr.querySelector('[data-role]').value, active: tr.querySelector('[data-active]').checked }).eq('user_id', tr.dataset.membership), 'User access updated.'); await loadPage(); return; }
      const saveMentor = event.target.closest('[data-save-mentor]'); if (saveMentor) { const tr = saveMentor.closest('[data-participant]'); await save(state.client.from('m_participants').update({ mentor_user_id: tr.querySelector('[data-mentor]').value || null }).eq('id', tr.dataset.participant), 'Mentor assignment updated.'); await loadPage(); return; }
      const registerButton = event.target.closest('[data-register]'); if (registerButton) { state.sessionId = registerButton.dataset.register; await loadPage(); return; }
      if (event.target.closest('#back-sessions')) { state.sessionId = null; await loadPage(); return; }
      if (event.target.closest('#finalize-session')) { await save(state.client.from('m_attendance_sessions').update({ finalized: true, finalized_at: new Date().toISOString() }).eq('id', state.sessionId), 'Register finalized.'); await loadPage(); return; }
      const status = event.target.closest('[data-status]'); if (status) { const participantId = status.closest('[data-attendee]').dataset.attendee; await save(state.client.from('m_attendance_records').upsert({ session_id: state.sessionId, participant_id: participantId, status: status.dataset.status, marked_by: state.session.user.id, marked_at: new Date().toISOString() }, { onConflict: 'session_id,participant_id' }), 'Attendance updated.'); await loadPage(); }
      const moduleButton = event.target.closest('[data-open-module]'); if (moduleButton) { state.moduleId = moduleButton.dataset.openModule; await loadPage(); return; }
      if (event.target.closest('#back-modules')) { state.moduleId = null; await loadPage(); return; }
      const studied = event.target.closest('[data-studied]'); if (studied) { if (!state.participantId) throw new Error('Participant profile not found.'); await save(state.client.from('m_resource_progress').upsert({ participant_id: state.participantId, resource_id: studied.dataset.studied }, { onConflict: 'participant_id,resource_id' }), 'Section marked as studied.'); }
    } catch (error) { console.error(error); toast(error.message || 'Action failed.'); }
  });

  document.addEventListener('change', event => {
    if (event.target.id === 'new-role') document.querySelectorAll('.participant-only').forEach(v => { v.hidden = event.target.value !== 'participant'; });
    if (event.target.id === 'section-type') { const test = event.target.value === 'test'; document.querySelectorAll('.normal-section').forEach(v => { v.hidden = test; }); document.querySelector('.test-section').hidden = !test; }
  });

  document.addEventListener('submit', async event => {
    event.preventDefault(); const form = event.target; const data = Object.fromEntries(new FormData(form).entries()); const button = form.querySelector('[type=submit]'); if (button) button.disabled = true;
    try {
      if (form.id === 'password-login') { const { error } = await state.client.auth.signInWithPassword({ email: data.email, password: data.password }); if (error) throw error; return; }
      if (form.id === 'magic-login') { const { error } = await state.client.auth.signInWithOtp({ email: data.email, options: { emailRedirectTo: location.origin } }); if (error) throw error; $('login-message').textContent = 'Magic link sent.'; return; }
      if (form.id === 'user-modal-form') { if (data.role === 'participant' && !data.cohort_id) throw new Error('Select a cohort for the participant.'); const { data: result, error } = await state.client.functions.invoke('m-admin-user', { body: data }); if (error) throw error; if (result?.error) throw new Error(result.error); toast(result.invited ? 'Invitation sent.' : 'Existing user updated.'); }
      else if (form.id === 'programme-modal-form') await save(state.client.from('m_programmes').insert({ name: data.name, description: data.description || null }), 'Programme created.');
      else if (form.id === 'cohort-modal-form') await save(state.client.from('m_cohorts').insert({ programme_id: data.programme_id, name: data.name, state: data.state || null, starts_on: data.starts_on || null, ends_on: data.ends_on || null }), 'Cohort created.');
      else if (form.id === 'access-modal-form') await save(state.client.from('m_cohort_access').upsert({ user_id: data.user_id, cohort_id: data.cohort_id }, { onConflict: 'user_id,cohort_id' }), 'Cohort access granted.');
      else if (form.id === 'assign-modal-form') { const modules = await rows('m_modules', 'id', q => q.eq('course_id', data.course_id)); if (!modules.length) throw new Error('Course has no modules.'); await save(state.client.from('m_module_assignments').upsert(modules.map(v => ({ participant_id: data.participant_id, module_id: v.id, assigned_by: state.session.user.id })), { onConflict: 'participant_id,module_id' }), 'Course assigned.'); }
      else if (form.id === 'course-modal-form') await save(state.client.from('m_courses').insert({ title: data.title, description: data.description || null, created_by: state.session.user.id }), 'Course created.');
      else if (form.id === 'module-modal-form') await save(state.client.from('m_modules').insert({ course_id: data.course_id, title: data.title, description: data.description || null, sequence_number: Number(data.sequence_number), pass_mark: Number(data.pass_mark), published: data.published === 'true', created_by: state.session.user.id }), 'Module created.');
      else if (form.id === 'section-modal-form') {
        if (data.kind === 'test') { const options = String(data.options || '').split(/\r?\n/).map(v => v.trim()).filter(Boolean); if (options.length < 2) throw new Error('Enter at least two options.'); const { data: question, error } = await state.client.from('m_quiz_questions').insert({ module_id: data.module_id, prompt: data.prompt, options, sequence_number: Number(data.sequence_number) }).select('id').single(); if (error) throw error; await save(state.client.from('m_quiz_keys').insert({ question_id: question.id, correct_option: Number(data.correct_option) - 1, feedback: data.feedback || null }), 'Test question added.'); }
        else { if (!data.content && !data.external_url) throw new Error('Add text or an external URL.'); await save(state.client.from('m_module_resources').insert({ module_id: data.module_id, title: data.title, kind: data.kind, content: data.content || null, external_url: data.external_url || null, sequence_number: Number(data.sequence_number) }), 'Section added.'); }
      }
      else if (form.id === 'session-modal-form') await save(state.client.from('m_attendance_sessions').insert({ cohort_id: data.cohort_id, meeting_number: Number(data.meeting_number), session_date: data.session_date, starts_at: data.starts_at || null, title: data.title, delivery_mode: data.delivery_mode, join_url: data.join_url || null, location: data.location || null, created_by: state.session.user.id }), 'Class register created.');
      else if (form.classList.contains('note-form')) { if (!state.participantId) throw new Error('Participant profile not found.'); await save(state.client.from('m_private_notes').upsert({ participant_id: state.participantId, resource_id: form.dataset.resource, note: data.note || '', updated_at: new Date().toISOString() }, { onConflict: 'participant_id,resource_id' }), 'Private notes saved.'); return; }
      else if (form.id === 'quiz-form') { const answers = {}; new FormData(form).forEach((value, key) => { answers[key] = Number(value); }); const { data: result, error } = await state.client.rpc('m_submit_quiz', { target_module: form.dataset.module, submitted_answers: answers }); if (error) throw error; const attempt = result?.[0]; $('quiz-result').innerHTML = `<div class="quiz-result"><strong>${attempt?.score ?? 0}%</strong> · ${attempt?.passed ? 'Passed' : 'Not passed yet — review and try again.'}</div>`; return; }
      else return;
      form.closest('dialog')?.close(); await loadPage();
    } catch (error) { console.error(error); toast(error.message || 'Action failed.'); if ($('login-message') && ['password-login', 'magic-login'].includes(form.id)) { $('login-message').textContent = error.message; $('login-message').className = 'login-message error'; } }
    finally { if (button) button.disabled = false; }
  });

  async function start() {
    const cfg = window.PORTAL_CONFIG || {}; if (!cfg.supabaseUrl || !cfg.supabasePublishableKey) throw new Error('Supabase configuration missing.');
    state.client = window.supabase.createClient(cfg.supabaseUrl, cfg.supabasePublishableKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } });
    const { data, error } = await state.client.auth.getSession(); if (error) return renderLogin(error.message, 'error'); state.session = data.session;
    if (!state.session) renderLogin(); else await loadMembership();
    state.client.auth.onAuthStateChange(async (event, session) => { if (['SIGNED_IN', 'SIGNED_OUT', 'USER_UPDATED'].includes(event)) { state.session = session; state.member = null; if (!session) renderLogin(); else await loadMembership(); } });
  }

  start().catch(error => { console.error(error); $('content').innerHTML = `<section class="card setup-card"><h1>Portal could not start</h1><p>${esc(error.message)}</p></section>`; });
})();
