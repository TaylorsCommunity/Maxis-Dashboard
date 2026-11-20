-- eKelas Usahawan function permissions
-- Run after 006_learning_player.sql. Idempotent. Changes permissions only; no data is touched.
--
-- Supabase grants new public functions to anon and authenticated directly, so "revoke ... from public"
-- in 004 and 006 did not remove those grants. This migration:
-- 1. Makes internal helpers private. They take any participant's id, so callers could otherwise ask
--    whether another participant finished an item or how many attempts they used. They are only
--    called from inside other security-definer functions, which run as the owner.
-- 2. Removes anonymous (signed-out) access from the learning functions; they need a signed-in user.
-- Signup functions (m_validate_signup_code, m_validate_staff_invite) stay available to anon on purpose.

revoke execute on function public.m_set_item_position() from anon, authenticated;
revoke execute on function public.m_module_items(uuid, boolean) from anon, authenticated;
revoke execute on function public.m_item_done(uuid, text, uuid) from anon, authenticated;
revoke execute on function public.m_attempts_used(uuid, uuid) from anon, authenticated;
revoke execute on function public.m_module_complete_for(uuid, uuid) from anon, authenticated;

revoke execute on function public.m_item_unlocked(text, uuid) from anon;
revoke execute on function public.m_participant_can_read_questions(uuid) from anon;
revoke execute on function public.m_can_start_assessment(uuid) from anon;
revoke execute on function public.m_start_assessment(uuid) from anon;
revoke execute on function public.m_submit_assessment(uuid, jsonb) from anon;
revoke execute on function public.m_course_outline(uuid) from anon;
revoke execute on function public.m_move_module_item(text, uuid, text) from anon;
