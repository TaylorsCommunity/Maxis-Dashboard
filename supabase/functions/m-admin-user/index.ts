import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authHeader = request.headers.get('Authorization');
  if (!supabaseUrl || !serviceKey || !authHeader) return json({ error: 'Function configuration is incomplete' }, 500);

  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const token = authHeader.replace(/^Bearer\s+/i, '');
  const { data: authData, error: authError } = await adminClient.auth.getUser(token);
  if (authError || !authData.user) return json({ error: 'Valid administrator session required' }, 401);

  const { data: caller } = await adminClient
    .from('m_memberships')
    .select('role,active')
    .eq('user_id', authData.user.id)
    .maybeSingle();
  if (!caller?.active || caller.role !== 'admin') return json({ error: 'Administrator access required' }, 403);

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const email = String(payload.email || '').trim().toLowerCase();
  const displayName = String(payload.display_name || '').trim();
  const role = String(payload.role || 'participant');
  const validRoles = ['admin', 'mentor', 'stakeholder', 'participant'];
  if (!email.includes('@') || displayName.length < 2 || !validRoles.includes(role)) {
    return json({ error: 'A valid email, display name and role are required' }, 400);
  }
  const cohortId = payload.cohort_id ? String(payload.cohort_id) : null;
  if (role === 'participant' && !cohortId) return json({ error: 'Participants require a cohort' }, 400);

  let userId = '';
  let invited = false;
  const { data: inviteData, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email, {
    data: { display_name: displayName, portal: 'eKelas Usahawan' },
  });

  if (inviteData.user) {
    userId = inviteData.user.id;
    invited = true;
  } else if (inviteError) {
    const { data: usersData, error: listError } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (listError) return json({ error: inviteError.message }, 400);
    const existing = usersData.users.find(user => user.email?.toLowerCase() === email);
    if (!existing) return json({ error: inviteError.message }, 400);
    userId = existing.id;
  }

  const { error: membershipError } = await adminClient.from('m_memberships').upsert({
    user_id: userId,
    display_name: displayName,
    role,
    active: true,
  }, { onConflict: 'user_id' });
  if (membershipError) return json({ error: membershipError.message }, 400);

  const mentorUserId = payload.mentor_user_id ? String(payload.mentor_user_id) : null;
  if (role === 'participant') {
    const { error: participantError } = await adminClient.from('m_participants').upsert({
      user_id: userId,
      cohort_id: cohortId,
      mentor_user_id: mentorUserId,
      full_name: displayName,
      email,
      business_name: payload.business_name ? String(payload.business_name) : null,
      state: payload.state ? String(payload.state) : null,
      active: true,
    }, { onConflict: 'user_id' });
    if (participantError) return json({ error: participantError.message }, 400);
  }

  if ((role === 'mentor' || role === 'stakeholder') && cohortId) {
    const { error: accessError } = await adminClient.from('m_cohort_access').upsert({
      user_id: userId,
      cohort_id: cohortId,
    }, { onConflict: 'user_id,cohort_id' });
    if (accessError) return json({ error: accessError.message }, 400);
  }

  return json({ user_id: userId, invited, role });
});
