-- Run only after creating the first administrator in Supabase Authentication > Users.
-- Replace the two placeholders before running.

insert into public.m_memberships (user_id, display_name, role, active)
select id, 'ADMIN DISPLAY NAME', 'admin'::public.m_role, true
from auth.users
where lower(email) = lower('ADMIN EMAIL ADDRESS')
on conflict (user_id) do update
set display_name = excluded.display_name,
    role = excluded.role,
    active = true,
    updated_at = now();
