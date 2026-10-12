-- =============================================================================
-- ACME Control - security controls (SD Elements threat model follow-up)
--
-- 1. acme_role() no longer runs as SECURITY DEFINER (Supabase linter 0029)
-- 2. Sign-in tracking on profiles (previous login notification)
-- 3. Client-side column protection on profiles, alarms, maintenance orders,
--    shift handovers (state-machine + ownership rules enforced in the database)
-- 4. Restricted client event logging (category allow-list, actor must be self)
-- 5. Private storage bucket with path-based ownership policies
-- 6. security_events audit table (written by the API, readable by supervisors)
-- 7. Server-side rate limiting helper for the API
-- 8. Data retention (purge_history) scheduled with pg_cron when available
-- 9. Least privilege: demo-data functions and tables are not callable by
--    anonymous or signed-in users through the REST API
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. acme_role(): SECURITY INVOKER is enough because profiles are readable by
--    every signed-in user; this removes a SECURITY DEFINER function from the
--    public RPC surface.
-- -----------------------------------------------------------------------------
alter function public.acme_role() security invoker;
revoke execute on function public.acme_role() from public, anon;
grant execute on function public.acme_role() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Sign-in tracking (previous login notification)
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists last_sign_in_at timestamptz,
  add column if not exists previous_sign_in_at timestamptz;

create or replace function public.track_sign_in()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.last_sign_in_at is distinct from old.last_sign_in_at then
    update public.profiles
      set previous_sign_in_at = old.last_sign_in_at,
          last_sign_in_at = new.last_sign_in_at
      where id = new.id;
  end if;
  return new;
end $$;
revoke execute on function public.track_sign_in() from public, anon, authenticated;

drop trigger if exists on_auth_user_sign_in on auth.users;
create trigger on_auth_user_sign_in
  after update of last_sign_in_at on auth.users
  for each row execute function public.track_sign_in();

-- -----------------------------------------------------------------------------
-- 3. Column protection for client updates (auth.uid() is null for the API's
--    service role, so server-side writes are not restricted)
-- -----------------------------------------------------------------------------
create or replace function public.protect_profile_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role;
begin
  if auth.uid() is null then
    return new;
  end if;
  v_role := coalesce(public.acme_role(), 'operator');

  if new.role <> old.role and v_role <> 'supervisor' then
    raise exception 'Only supervisors can change roles' using errcode = '42501';
  end if;
  if new.email <> old.email
     or new.last_sign_in_at is distinct from old.last_sign_in_at
     or new.previous_sign_in_at is distinct from old.previous_sign_in_at
     or new.created_at <> old.created_at then
    raise exception 'This profile field is managed by the server' using errcode = '42501';
  end if;
  if new.avatar_url is distinct from old.avatar_url
     and new.avatar_url is not null
     and new.avatar_url !~ ('^avatars/' || new.id::text || '\.[A-Za-z0-9]{1,5}$') then
    raise exception 'avatar_url must be a storage path of the form avatars/<user id>.<ext>' using errcode = '22023';
  end if;
  if length(new.full_name) > 80 or length(coalesce(new.phone, '')) > 30 then
    raise exception 'Profile text is too long' using errcode = '22023';
  end if;
  return new;
end $$;
revoke execute on function public.protect_profile_update() from public, anon, authenticated;

drop trigger if exists profiles_protect_role on public.profiles;
drop trigger if exists profiles_protect_update on public.profiles;
create trigger profiles_protect_update before update on public.profiles
  for each row execute function public.protect_profile_update();
drop function if exists public.protect_profile_role();

-- Alarms: clients may only acknowledge an active alarm, nothing else.
create or replace function public.protect_alarm_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if not (old.state = 'active' and new.state = 'acknowledged') then
    raise exception 'Clients may only acknowledge active alarms' using errcode = '42501';
  end if;
  if new.plant_id <> old.plant_id or new.code <> old.code or new.message <> old.message
     or new.severity <> old.severity or new.raised_at <> old.raised_at
     or new.cleared_at is distinct from old.cleared_at or new.value is distinct from old.value
     or new.equipment_id is distinct from old.equipment_id or new.tag is distinct from old.tag then
    raise exception 'Alarm data is managed by the process engine' using errcode = '42501';
  end if;
  new.acked_by := auth.uid();
  new.acked_at := coalesce(new.acked_at, now());
  new.acked_by_name := coalesce((select full_name from public.profiles where id = auth.uid()), new.acked_by_name);
  return new;
end $$;
revoke execute on function public.protect_alarm_update() from public, anon, authenticated;
drop trigger if exists alarms_protect_update on public.alarms;
create trigger alarms_protect_update before update on public.alarms
  for each row execute function public.protect_alarm_update();

-- Maintenance orders: ownership columns are immutable; attachments must be
-- storage paths inside the plant folder.
create or replace function public.validate_attachments(p jsonb)
returns boolean language sql immutable as $$
  select p is not null and jsonb_typeof(p) = 'array' and jsonb_array_length(p) <= 10
     and not exists (
       select 1 from jsonb_array_elements(p) a
       where jsonb_typeof(a) <> 'object'
          or length(coalesce(a ->> 'name', '')) not between 1 and 200
          or (a ->> 'path' is null and a ->> 'url' is null)
          or (a ->> 'path' is not null and a ->> 'path' !~ '^maintenance/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,200}$')
     );
$$;

create or replace function public.protect_maintenance_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if not public.validate_attachments(new.attachments) then
    raise exception 'Invalid attachments list' using errcode = '22023';
  end if;
  if length(new.title) not between 1 and 200 or length(new.description) > 2000 or length(coalesce(new.work_notes, '')) > 2000 then
    raise exception 'Work order text is too long' using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' then
    if new.plant_id <> old.plant_id or new.created_by is distinct from old.created_by
       or new.created_by_name is distinct from old.created_by_name or new.code <> old.code
       or new.created_at <> old.created_at then
      raise exception 'Work order ownership fields are immutable' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.protect_maintenance_write() from public, anon, authenticated;
drop trigger if exists maintenance_protect_write on public.maintenance_orders;
create trigger maintenance_protect_write before insert or update on public.maintenance_orders
  for each row execute function public.protect_maintenance_write();

-- Shift handovers: explicit state machine and ownership.
create or replace function public.protect_handover_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role;
begin
  if auth.uid() is null then
    return new;
  end if;
  v_role := coalesce(public.acme_role(), 'operator');
  if length(new.summary) > 2000 or jsonb_array_length(coalesce(new.open_issues, '[]'::jsonb)) > 50 then
    raise exception 'Handover text is too long' using errcode = '22023';
  end if;
  if tg_op = 'INSERT' then
    if new.status = 'acknowledged' then
      raise exception 'A handover cannot be created as acknowledged' using errcode = '42501';
    end if;
    if new.status = 'submitted' then
      new.submitted_at := coalesce(new.submitted_at, now());
    end if;
    return new;
  end if;
  if new.plant_id <> old.plant_id or new.from_user is distinct from old.from_user or new.created_at <> old.created_at then
    raise exception 'Handover ownership fields are immutable' using errcode = '42501';
  end if;
  if old.status = 'acknowledged' then
    raise exception 'An acknowledged handover cannot be changed' using errcode = '42501';
  end if;
  if old.status = 'submitted' and new.status = 'draft' then
    raise exception 'A submitted handover cannot go back to draft' using errcode = '42501';
  end if;
  if new.status = 'submitted' and old.status = 'draft' then
    if old.from_user <> auth.uid() and v_role <> 'supervisor' then
      raise exception 'Only the outgoing operator can submit this handover' using errcode = '42501';
    end if;
    new.submitted_at := coalesce(new.submitted_at, now());
  end if;
  if new.status = 'acknowledged' then
    if old.status <> 'submitted' then
      raise exception 'Only submitted handovers can be acknowledged' using errcode = '42501';
    end if;
    if old.to_user is distinct from auth.uid() and v_role <> 'supervisor' then
      raise exception 'Only the incoming operator or a supervisor can acknowledge' using errcode = '42501';
    end if;
    new.acknowledged_by := auth.uid();
    new.acknowledged_at := coalesce(new.acknowledged_at, now());
  end if;
  return new;
end $$;
revoke execute on function public.protect_handover_write() from public, anon, authenticated;
drop trigger if exists handovers_protect_write on public.shift_handovers;
create trigger handovers_protect_write before insert or update on public.shift_handovers
  for each row execute function public.protect_handover_write();

-- -----------------------------------------------------------------------------
-- 4. Client event logging: allow-listed categories, actor must be the caller
-- -----------------------------------------------------------------------------
drop policy if exists "events insert" on public.events;
create policy "events insert" on public.events for insert to authenticated
  with check (
    category in ('auth', 'handover', 'maintenance', 'integration', 'ui')
    and level in ('info', 'warning', 'error')
    and length(message) between 1 and 500
    and (
      actor = (select full_name from public.profiles where id = auth.uid())
      or actor = (select email from public.profiles where id = auth.uid())
      or (category = 'integration' and actor = 'system')
    )
  );

-- -----------------------------------------------------------------------------
-- 5. Private storage with ownership rules
-- -----------------------------------------------------------------------------
update storage.buckets
  set public = false,
      file_size_limit = 10485760,
      allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp', 'application/pdf']
  where id = 'attachments';

drop policy if exists "attachments public read" on storage.objects;
drop policy if exists "attachments authenticated upload" on storage.objects;
drop policy if exists "attachments owner update" on storage.objects;
drop policy if exists "attachments owner delete" on storage.objects;

create policy "attachments authenticated read" on storage.objects for select to authenticated
  using (bucket_id = 'attachments');

create policy "attachments scoped upload" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'attachments'
    and (
      name ~ ('^avatars/' || auth.uid()::text || '\.[A-Za-z0-9]{1,5}$')
      or (name ~ '^maintenance/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,200}$'
          and public.acme_role() in ('maintenance', 'engineer', 'supervisor'))
    )
  );

create policy "attachments owner update" on storage.objects for update to authenticated
  using (bucket_id = 'attachments' and owner = auth.uid())
  with check (bucket_id = 'attachments' and owner = auth.uid());

create policy "attachments owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'attachments' and owner = auth.uid());

-- -----------------------------------------------------------------------------
-- 6. Security audit log (written by the API with the service role)
-- -----------------------------------------------------------------------------
create table if not exists public.security_events (
  id bigint generated always as identity primary key,
  ts timestamptz not null default now(),
  actor_id uuid,
  actor_email text,
  actor_role text,
  action text not null,
  outcome text not null check (outcome in ('success', 'denied', 'error', 'rejected')),
  status integer,
  path text,
  ip text,
  user_agent text,
  request_id text,
  details jsonb not null default '{}'::jsonb
);
create index if not exists security_events_ts_idx on public.security_events (ts desc);
create index if not exists security_events_actor_idx on public.security_events (actor_id, ts desc);

alter table public.security_events enable row level security;
drop policy if exists "security_events supervisor read" on public.security_events;
create policy "security_events supervisor read" on public.security_events for select to authenticated
  using (public.acme_role() = 'supervisor');
revoke all on public.security_events from anon;
revoke insert, update, delete on public.security_events from authenticated;

-- -----------------------------------------------------------------------------
-- 7. Rate limiting helper (fixed window, keyed by caller + route group)
-- -----------------------------------------------------------------------------
create table if not exists public.rate_limits (
  key text primary key,
  window_start timestamptz not null,
  hits integer not null default 0
);
alter table public.rate_limits enable row level security;
revoke all on public.rate_limits from anon, authenticated;

create or replace function public.consume_rate_limit(p_key text, p_limit integer, p_window_seconds integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := clock_timestamp();
  v_row public.rate_limits%rowtype;
  v_reset timestamptz;
begin
  insert into public.rate_limits (key, window_start, hits)
    values (p_key, v_now, 0)
    on conflict (key) do nothing;
  select * into v_row from public.rate_limits where key = p_key for update;
  if v_row.window_start + make_interval(secs => p_window_seconds) <= v_now then
    v_row.window_start := v_now;
    v_row.hits := 0;
  end if;
  v_reset := v_row.window_start + make_interval(secs => p_window_seconds);
  if v_row.hits >= p_limit then
    update public.rate_limits set window_start = v_row.window_start, hits = v_row.hits where key = p_key;
    return jsonb_build_object('allowed', false, 'remaining', 0, 'reset_at', v_reset);
  end if;
  update public.rate_limits set window_start = v_row.window_start, hits = v_row.hits + 1 where key = p_key;
  return jsonb_build_object('allowed', true, 'remaining', p_limit - v_row.hits - 1, 'reset_at', v_reset);
end $$;
revoke all on function public.consume_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_rate_limit(text, integer, integer) to service_role;

-- -----------------------------------------------------------------------------
-- 8. Data retention
-- -----------------------------------------------------------------------------
create or replace function public.purge_history(p_trend_days integer default 7, p_event_days integer default 90, p_security_days integer default 365)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_trends bigint; v_events bigint; v_security bigint; v_limits bigint;
begin
  delete from public.trend_samples where ts < now() - make_interval(days => p_trend_days);
  get diagnostics v_trends = row_count;
  delete from public.events where ts < now() - make_interval(days => p_event_days);
  get diagnostics v_events = row_count;
  delete from public.security_events where ts < now() - make_interval(days => p_security_days);
  get diagnostics v_security = row_count;
  delete from public.rate_limits where window_start < now() - interval '1 day';
  get diagnostics v_limits = row_count;
  return jsonb_build_object('trend_samples', v_trends, 'events', v_events, 'security_events', v_security, 'rate_limits', v_limits);
end $$;
revoke all on function public.purge_history(integer, integer, integer) from public, anon, authenticated;
grant execute on function public.purge_history(integer, integer, integer) to service_role;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'acme-control-purge-history';
  perform cron.schedule('acme-control-purge-history', '15 3 * * *', 'select public.purge_history()');
exception when others then
  raise notice 'pg_cron not available (%); run select public.purge_history() from an external scheduler', sqlerrm;
end $$;

-- -----------------------------------------------------------------------------
-- 9. Least privilege on the REST surface
-- -----------------------------------------------------------------------------
revoke execute on function public.seed_demo_data() from public, anon, authenticated;
grant execute on function public.seed_demo_data() to service_role;
revoke execute on function public.seed_plant_demo(uuid, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.seed_plant_demo(uuid, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) to service_role;
revoke execute on function public.validate_attachments(jsonb) from public, anon;

-- Anonymous clients have no business with any application table.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- Signed-in users never delete rows directly; the API and the demo reset do.
revoke delete on all tables in schema public from authenticated;

-- Pin the search_path of the new helper (Supabase linter 0011).
alter function public.validate_attachments(jsonb) set search_path = public;
