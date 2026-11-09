(() => {
  'use strict';

  const $ = id => document.getElementById(id);
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[character]);

  const roleNavigation = {
    admin: [
      ['overview', 'Programme overview', 'overview'],
      ['people', 'People & access', 'people'],
      ['learning', 'Learning content', 'learning'],
      ['attendance', 'Live attendance', 'attendance'],
      ['reports', 'Reports', 'reports']
    ],
    mentor: [
      ['overview', 'Cohort overview', 'overview'],
      ['people', 'Participants', 'people'],
      ['attendance', 'Live attendance', 'attendance'],
      ['reports', 'Reports', 'reports']
    ],
    stakeholder: [
      ['overview', 'Programme overview', 'overview'],
      ['reports', 'Reports', 'reports']
    ],
    participant: [
      ['learning', 'My learning', 'learning'],
      ['business', 'My business', 'business'],
      ['profile', 'My profile', 'people']
    ]
  };

  const state = {
    client: null,
    session: null,
    membership: null,
    page: 'overview',
    loading: false
  };

  function icon(name) {
    const paths = {
      overview: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>',
      people: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
      learning: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
      attendance: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M8 15l2 2 5-5"/>',
      reports: '<path d="M3 3v18h18"/><path d="M7 16l4-4 3 3 5-7"/>',
      business: '<rect x="3" y="7" width="18" height="14" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12h18M10 12v2h4v-2"/>'
    };
    return `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.overview}</svg>`;
  }

  function toast(message) {
    const element = $('toast');
    element.textContent = message;
    element.classList.add('show');
    window.setTimeout(() => element.classList.remove('show'), 3200);
  }

  function setConnection(label, type = '') {
    const element = $('connection-status');
    element.textContent = label;
    element.className = `connection-chip ${type}`.trim();
  }

  function initials(name) {
    return String(name || 'TC').split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('').toUpperCase();
  }

  function pageHead(title, description, eyebrow = 'PORTAL') {
    return `<div class="page-head"><div><div class="eyebrow">${escapeHtml(eyebrow)}</div><h1>${escapeHtml(title)}</h1><p>${escapeHtml(description)}</p></div></div>`;
  }

  function emptyState(title, description, iconName = 'overview') {
    return `<section class="empty-product">${icon(iconName)}<h2>${escapeHtml(title)}</h2><p>${escapeHtml(description)}</p></section>`;
  }

  function renderSetup() {
    $('sidebar').hidden = true;
    document.querySelector('.shell').style.marginLeft = '0';
    $('sign-out').hidden = true;
    setConnection('Setup required', 'error');
    $('content').innerHTML = `<section class="card setup-card">
      <div class="eyebrow">SUPABASE CONNECTION</div>
      <h1>Connect the portal database</h1>
      <p>The interface contains no demonstration users or programme records. Complete these two configuration steps to connect the live database.</p>
      <ol class="setup-list">
        <li>Run <b>supabase/migrations/001_portal_foundation.sql</b> in the selected Supabase project.</li>
        <li>Add the project URL and publishable key to the local or Vercel environment.</li>
      </ol>
      <div class="code-block">SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co<br>SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY</div>
      <p class="help-text" style="margin-top:16px">Never place a service-role key in browser or Vercel client configuration.</p>
    </section>`;
  }

  function renderLogin(message = '', type = '') {
    $('sidebar').hidden = true;
    document.querySelector('.shell').style.marginLeft = '0';
    $('sign-out').hidden = true;
    $('account-name').textContent = '';
    $('account-avatar').textContent = 'TC';
    setConnection('Secure sign-in');
    $('content').innerHTML = `<div class="auth-layout"><section class="auth-card">
      <div class="eyebrow">LEARNING & IMPACT PORTAL</div>
      <h1>Welcome back</h1>
      <p>Sign in using the email address registered by the programme administrator.</p>
      <form id="password-login">
        <label class="field">Email address<input type="email" name="email" autocomplete="email" required></label>
        <label class="field">Password<input type="password" name="password" autocomplete="current-password" required minlength="8"></label>
        <button class="primary" type="submit">Sign in</button>
      </form>
      <div class="auth-divider">OR</div>
      <form id="magic-login">
        <label class="field">Email address<input type="email" name="email" autocomplete="email" required></label>
        <button class="secondary" type="submit" style="width:100%;margin-top:14px">Send a magic link</button>
      </form>
      <div class="login-message ${escapeHtml(type)}" id="login-message">${escapeHtml(message)}</div>
    </section></div>`;
  }

  function renderNoAccess() {
    $('sidebar').hidden = true;
    document.querySelector('.shell').style.marginLeft = '0';
    $('sign-out').hidden = false;
    setConnection('Signed in', 'connected');
    const email = state.session?.user?.email || '';
    $('account-name').textContent = email;
    $('account-avatar').textContent = initials(email);
    $('content').innerHTML = `<section class="card access-card">
      <span class="account-avatar">${escapeHtml(initials(email))}</span>
      <div class="eyebrow">ACCESS PENDING</div>
      <h1>Your account is not assigned to this portal</h1>
      <p>Your sign-in is valid, but an administrator must create an active portal membership and assign the appropriate role before you can access programme data.</p>
      <button class="secondary" id="retry-access" type="button">Check access again</button>
    </section>`;
  }

  function renderShell() {
    const role = state.membership.role;
    const displayName = state.membership.display_name || state.session.user.email;
    const nav = roleNavigation[role] || [];
    if (!nav.some(item => item[0] === state.page)) state.page = nav[0]?.[0] || 'overview';

    $('sidebar').hidden = false;
    document.querySelector('.shell').style.marginLeft = '';
    $('sign-out').hidden = false;
    $('account-name').textContent = displayName;
    $('account-avatar').textContent = initials(displayName);
    setConnection('Database connected', 'connected');
    $('nav').innerHTML = nav.map(([id, label, iconName]) => `<button type="button" data-page="${id}" class="${state.page === id ? 'active' : ''}" ${state.page === id ? 'aria-current="page"' : ''}>${icon(iconName)}${escapeHtml(label)}</button>`).join('');
    $('crumb').textContent = nav.find(item => item[0] === state.page)?.[1] || 'Portal';
  }

  function stat(label, value, note) {
    return `<div class="stat"><span class="label">${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong><small>${escapeHtml(note)}</small></div>`;
  }

  async function countRows(table, configure = query => query) {
    const query = configure(state.client.from(table).select('*', { count: 'exact', head: true }));
    const { count, error } = await query;
    if (error) throw error;
    return count || 0;
  }

  async function overviewPage() {
    const [participants, modules, finalizedSessions, monthlyRecords] = await Promise.all([
      countRows('portal_participants'),
      countRows('portal_modules', query => query.eq('published', true)),
      countRows('portal_attendance_sessions', query => query.eq('finalized', true)),
      countRows('portal_business_checkins')
    ]);
    const role = state.membership.role;
    return `${pageHead(role === 'participant' ? 'My programme overview' : 'Programme overview', 'Live information is loaded from Supabase and limited by your assigned role and cohorts.', `${role.toUpperCase()} WORKSPACE`)}
      <div class="stats">${stat('Participants', participants, 'Visible in your access scope')}${stat('Published modules', modules, 'Available learning content')}${stat('Finalized classes', finalizedSessions, 'Attendance registers')}${stat('Business records', monthlyRecords, 'Monthly submissions in scope')}</div>
      <div class="data-grid">
        <section class="card"><div class="card-head"><div><h2>Live database status</h2><p>No demonstration records are loaded.</p></div><span class="role-badge">${escapeHtml(role)}</span></div><dl class="definition-list"><dt>Signed-in account</dt><dd>${escapeHtml(state.session.user.email)}</dd><dt>Portal role</dt><dd>${escapeHtml(role)}</dd><dt>Access enforcement</dt><dd>Supabase Row Level Security</dd></dl></section>
        <section class="card">${emptyState('Ready for programme data', 'Once administrators create programmes, cohorts and participants, approved analytics will appear here.', 'reports')}</section>
      </div>`;
  }

  async function peoplePage() {
    const { data, error } = await state.client.from('portal_participants').select('id,full_name,business_name,state,active').order('full_name').limit(100);
    if (error) throw error;
    const rows = data || [];
    return `${pageHead(state.membership.role === 'mentor' ? 'Participants' : 'People & access', 'Participant records visible within your authorised cohorts.', 'SECURE RECORDS')}
      <section class="card">${rows.length ? `<div class="table-wrap"><table><thead><tr><th>Participant</th><th>Business</th><th>State</th><th>Status</th></tr></thead><tbody>${rows.map(person => `<tr><td>${escapeHtml(person.full_name)}</td><td>${escapeHtml(person.business_name || '—')}</td><td>${escapeHtml(person.state || '—')}</td><td><span class="pill ${person.active ? '' : 'gray'}">${person.active ? 'Active' : 'Inactive'}</span></td></tr>`).join('')}</tbody></table></div>` : emptyState('No participants yet', 'An administrator can enrol the first participant after the database connection and admin account are configured.', 'people')}</section>`;
  }

  async function learningPage() {
    const role = state.membership.role;
    let query = state.client.from('portal_modules').select('id,title,description,published,created_at').order('created_at', { ascending: false });
    if (role !== 'admin') query = query.eq('published', true);
    const { data, error } = await query.limit(100);
    if (error) throw error;
    const modules = data || [];
    return `${pageHead(role === 'participant' ? 'My learning' : 'Learning content', role === 'participant' ? 'Your assigned modules and learning progress.' : 'Create and publish programme learning content.', 'LEARNING')}
      <section class="card">${modules.length ? `<div class="grid-3">${modules.map(module => `<article class="card module-card"><div class="module-cover"><span class="module-number">MODULE</span>${icon('learning')}</div><div class="module-body"><span class="pill ${module.published ? '' : 'gray'}">${module.published ? 'Published' : 'Draft'}</span><h2>${escapeHtml(module.title)}</h2><p>${escapeHtml(module.description || 'No description provided.')}</p></div></article>`).join('')}</div>` : emptyState('No learning modules yet', 'The portal is connected and ready for administrators to add the first module, video, reading or workbook.', 'learning')}</section>`;
  }

  async function attendancePage() {
    const { data, error } = await state.client.from('portal_attendance_sessions').select('id,title,session_date,meeting_number,finalized').order('session_date', { ascending: false }).limit(100);
    if (error) throw error;
    const sessions = data || [];
    return `${pageHead('Live attendance', 'Create class registers and record attendance against each participant profile.', 'ATTENDANCE')}
      <section class="card">${sessions.length ? `<div class="table-wrap"><table><thead><tr><th>Date</th><th>Meeting</th><th>Title</th><th>Status</th></tr></thead><tbody>${sessions.map(session => `<tr><td>${escapeHtml(session.session_date)}</td><td>${escapeHtml(session.meeting_number)}</td><td>${escapeHtml(session.title)}</td><td><span class="pill ${session.finalized ? '' : 'amber'}">${session.finalized ? 'Finalized' : 'Draft'}</span></td></tr>`).join('')}</tbody></table></div>` : emptyState('No attendance sessions yet', 'Administrators and mentors will be able to create the first live class register here.', 'attendance')}</section>`;
  }

  async function businessPage() {
    const { data, error } = await state.client.from('portal_business_checkins').select('id,reporting_month,sales,operating_costs,mentor_reviewed').order('reporting_month', { ascending: false }).limit(24);
    if (error) throw error;
    const records = data || [];
    return `${pageHead('My business', 'Submit and review your monthly business performance.', 'BUSINESS MONITORING')}
      <section class="card">${records.length ? `<div class="table-wrap"><table><thead><tr><th>Month</th><th>Sales</th><th>Operating costs</th><th>Net income</th><th>Review</th></tr></thead><tbody>${records.map(record => `<tr><td>${escapeHtml(record.reporting_month)}</td><td>RM ${Number(record.sales || 0).toLocaleString('en-MY')}</td><td>RM ${Number(record.operating_costs || 0).toLocaleString('en-MY')}</td><td>RM ${Number((record.sales || 0) - (record.operating_costs || 0)).toLocaleString('en-MY')}</td><td><span class="pill ${record.mentor_reviewed ? '' : 'gray'}">${record.mentor_reviewed ? 'Reviewed' : 'Self-reported'}</span></td></tr>`).join('')}</tbody></table></div>` : emptyState('No monthly records yet', 'Your first submitted business check-in will appear here.', 'business')}</section>`;
  }

  function reportsPage() {
    return `${pageHead('Reports', 'Generate stakeholder-ready programme reports from approved live records.', 'REPORTING')}
      <section class="card">${emptyState('No reportable data yet', 'Reports will become available after programmes, participants, learning progress, attendance and business records are entered.', 'reports')}</section>`;
  }

  function profilePage() {
    const membership = state.membership;
    return `${pageHead('My profile', 'Your portal account and access information.', 'ACCOUNT')}
      <section class="card"><dl class="definition-list"><dt>Name</dt><dd>${escapeHtml(membership.display_name || 'Not provided')}</dd><dt>Email</dt><dd>${escapeHtml(state.session.user.email)}</dd><dt>Role</dt><dd>${escapeHtml(membership.role)}</dd><dt>Status</dt><dd>${membership.active ? 'Active' : 'Inactive'}</dd></dl></section>`;
  }

  async function loadPage() {
    renderShell();
    $('content').innerHTML = '<div class="loading-card">Loading live data…</div>';
    try {
      let html;
      if (state.page === 'overview') html = await overviewPage();
      else if (state.page === 'people') html = await peoplePage();
      else if (state.page === 'learning') html = await learningPage();
      else if (state.page === 'attendance') html = await attendancePage();
      else if (state.page === 'business') html = await businessPage();
      else if (state.page === 'profile') html = profilePage();
      else html = reportsPage();
      $('content').innerHTML = html;
    } catch (error) {
      console.error(error);
      $('content').innerHTML = `${pageHead('Database setup incomplete', 'The portal connected to Supabase but could not load the required portal tables.', 'ACTION REQUIRED')}<section class="notice amber">${escapeHtml(error.message || 'Unknown database error')}</section>${emptyState('Run the portal migration', 'Apply supabase/migrations/001_portal_foundation.sql, then refresh this page.', 'overview')}`;
      setConnection('Database action required', 'error');
    }
  }

  async function loadMembership() {
    const { data, error } = await state.client.from('portal_memberships').select('user_id,display_name,role,active').eq('user_id', state.session.user.id).eq('active', true).maybeSingle();
    if (error) throw error;
    state.membership = data;
    if (!data) renderNoAccess();
    else await loadPage();
  }

  async function handleSession(session) {
    state.session = session;
    state.membership = null;
    if (!session) {
      renderLogin();
      return;
    }
    setConnection('Checking access');
    try {
      await loadMembership();
    } catch (error) {
      console.error(error);
      $('sidebar').hidden = true;
      document.querySelector('.shell').style.marginLeft = '0';
      $('sign-out').hidden = false;
      setConnection('Connection error', 'error');
      $('content').innerHTML = `<section class="card setup-card"><div class="eyebrow">DATABASE ERROR</div><h1>Portal access could not be checked</h1><p>${escapeHtml(error.message || 'Please confirm the migration and environment configuration.')}</p></section>`;
    }
  }

  async function initialise() {
    const config = window.PORTAL_CONFIG || {};
    if (!config.supabaseUrl || !config.supabasePublishableKey) {
      renderSetup();
      return;
    }
    if (!window.supabase?.createClient) {
      $('content').innerHTML = `<section class="card setup-card"><h1>Supabase client could not load</h1><p>Check the browser connection and content-security settings, then refresh.</p></section>`;
      setConnection('Client unavailable', 'error');
      return;
    }
    state.client = window.supabase.createClient(config.supabaseUrl, config.supabasePublishableKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });
    const { data, error } = await state.client.auth.getSession();
    if (error) {
      renderLogin(error.message, 'error');
      return;
    }
    await handleSession(data.session);
    state.client.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'USER_UPDATED') handleSession(session);
    });
  }

  document.addEventListener('click', async event => {
    const pageButton = event.target.closest('[data-page]');
    if (pageButton && state.membership) {
      event.preventDefault();
      state.page = pageButton.dataset.page;
      await loadPage();
      $('main').focus();
      return;
    }
    if (event.target.closest('#sign-out') && state.client) {
      await state.client.auth.signOut();
      return;
    }
    if (event.target.closest('#retry-access')) await loadMembership();
  });

  document.addEventListener('submit', async event => {
    if (!state.client) return;
    if (event.target.id === 'password-login') {
      event.preventDefault();
      const form = new FormData(event.target);
      const button = event.target.querySelector('button');
      button.disabled = true;
      const { error } = await state.client.auth.signInWithPassword({ email: form.get('email'), password: form.get('password') });
      button.disabled = false;
      if (error) {
        const message = $('login-message');
        message.textContent = error.message;
        message.className = 'login-message error';
      }
    }
    if (event.target.id === 'magic-login') {
      event.preventDefault();
      const form = new FormData(event.target);
      const button = event.target.querySelector('button');
      button.disabled = true;
      const { error } = await state.client.auth.signInWithOtp({
        email: form.get('email'),
        options: { emailRedirectTo: window.location.origin }
      });
      button.disabled = false;
      const message = $('login-message');
      message.textContent = error ? error.message : 'Magic link sent. Check your inbox.';
      message.className = `login-message ${error ? 'error' : 'success'}`;
    }
  });

  initialise().catch(error => {
    console.error(error);
    setConnection('Startup error', 'error');
    $('content').innerHTML = `<section class="card setup-card"><h1>Portal could not start</h1><p>${escapeHtml(error.message || 'Unknown error')}</p></section>`;
  });
})();
