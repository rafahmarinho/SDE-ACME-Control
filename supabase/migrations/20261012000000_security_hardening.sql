-- Security hardening suggested by the Supabase database linter.
-- Pin the search_path of helper functions and keep SECURITY DEFINER helpers
-- out of the public RPC surface.

alter function public.next_maintenance_code() set search_path = public;
alter function public.set_updated_at() set search_path = public;

-- Trigger functions are executed by the table owner; nobody needs to call them through the API.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.protect_profile_role() from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;

-- acme_role() backs the RLS policies, so signed-in users must keep EXECUTE; anonymous users do not.
revoke execute on function public.acme_role() from public, anon;
grant execute on function public.acme_role() to authenticated, service_role;

-- next_maintenance_code() is only used as a column default.
revoke execute on function public.next_maintenance_code() from public, anon;
