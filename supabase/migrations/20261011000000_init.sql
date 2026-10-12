-- =============================================================================
-- ACME Control - initial schema
-- Water treatment supervisory system: plants, equipment, process state,
-- alarms, commands, setpoints, maintenance, shift handover, events.
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
create type public.user_role as enum ('operator', 'engineer', 'supervisor', 'maintenance');
create type public.equipment_type as enum ('pump', 'valve', 'tank', 'sensor');
create type public.equipment_mode as enum ('manual', 'auto');
create type public.alarm_severity as enum ('low', 'medium', 'high', 'critical');
create type public.alarm_state as enum ('active', 'acknowledged', 'cleared');
create type public.command_status as enum ('pending', 'accepted', 'rejected', 'executed', 'failed');
create type public.setpoint_request_status as enum ('pending', 'approved', 'rejected');
create type public.maintenance_status as enum ('open', 'in_progress', 'done', 'cancelled');
create type public.maintenance_priority as enum ('low', 'medium', 'high', 'critical');
create type public.handover_status as enum ('draft', 'submitted', 'acknowledged');

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.plants (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  location text not null,
  timezone text not null default 'UTC',
  description text,
  status text not null default 'online',
  design_capacity_m3h numeric not null default 100,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text not null default '',
  role public.user_role not null default 'operator',
  avatar_url text,
  phone text,
  default_plant_id uuid references public.plants (id) on delete set null,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.equipment (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants (id) on delete cascade,
  tag text not null,
  name text not null,
  type public.equipment_type not null,
  area text,
  mode public.equipment_mode not null default 'auto',
  requested_state text not null default 'stop',
  actual_state text not null default 'stopped',
  position numeric not null default 0,
  under_maintenance boolean not null default false,
  fault text,
  interlock text,
  runtime_hours numeric not null default 0,
  starts_count integer not null default 0,
  params jsonb not null default '{}'::jsonb,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  unique (plant_id, tag)
);
create index equipment_plant_idx on public.equipment (plant_id, sort_order);

create table public.process_state (
  plant_id uuid primary key references public.plants (id) on delete cascade,
  scenario text not null default 'normal',
  sim_time timestamptz not null default now(),
  last_tick_at timestamptz not null default now(),
  speed numeric not null default 1,
  running boolean not null default true,
  "values" jsonb not null default '{}'::jsonb,
  tanks jsonb not null default '{}'::jsonb,
  conditions jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.trend_samples (
  id bigint generated always as identity primary key,
  plant_id uuid not null references public.plants (id) on delete cascade,
  tag text not null,
  ts timestamptz not null,
  value numeric not null
);
create index trend_samples_idx on public.trend_samples (plant_id, tag, ts desc);

create table public.alarms (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants (id) on delete cascade,
  equipment_id uuid references public.equipment (id) on delete set null,
  code text not null,
  tag text,
  severity public.alarm_severity not null default 'medium',
  message text not null,
  state public.alarm_state not null default 'active',
  value numeric,
  raised_at timestamptz not null default now(),
  acked_at timestamptz,
  acked_by uuid references public.profiles (id) on delete set null,
  acked_by_name text,
  cleared_at timestamptz,
  updated_at timestamptz not null default now()
);
create index alarms_plant_state_idx on public.alarms (plant_id, state, raised_at desc);
create unique index alarms_open_code_idx on public.alarms (plant_id, code) where state <> 'cleared';

create table public.commands (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants (id) on delete cascade,
  equipment_id uuid references public.equipment (id) on delete set null,
  equipment_tag text,
  user_id uuid references public.profiles (id) on delete set null,
  user_name text,
  type text not null,
  value jsonb,
  status public.command_status not null default 'pending',
  reason text,
  created_at timestamptz not null default now(),
  executed_at timestamptz
);
create index commands_plant_idx on public.commands (plant_id, created_at desc);

create table public.setpoints (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants (id) on delete cascade,
  key text not null,
  label text not null,
  description text,
  value numeric not null,
  unit text not null default '',
  min_value numeric not null default 0,
  max_value numeric not null default 100,
  group_name text not null default 'Process',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null,
  unique (plant_id, key)
);

create table public.setpoint_requests (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants (id) on delete cascade,
  setpoint_id uuid not null references public.setpoints (id) on delete cascade,
  setpoint_key text not null,
  setpoint_label text not null,
  requested_by uuid references public.profiles (id) on delete set null,
  requested_by_name text,
  current_value numeric not null,
  proposed_value numeric not null,
  justification text not null default '',
  status public.setpoint_request_status not null default 'pending',
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_by_name text,
  review_note text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index setpoint_requests_plant_idx on public.setpoint_requests (plant_id, status, created_at desc);

create sequence if not exists public.maintenance_code_seq start 1040;
create or replace function public.next_maintenance_code()
returns text language sql as $$
  select 'WO-' || lpad(nextval('public.maintenance_code_seq')::text, 5, '0');
$$;

create table public.maintenance_orders (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants (id) on delete cascade,
  equipment_id uuid references public.equipment (id) on delete set null,
  equipment_tag text,
  code text not null default public.next_maintenance_code(),
  title text not null,
  description text not null default '',
  priority public.maintenance_priority not null default 'medium',
  status public.maintenance_status not null default 'open',
  assigned_to uuid references public.profiles (id) on delete set null,
  assigned_to_name text,
  scheduled_for timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  work_notes text,
  attachments jsonb not null default '[]'::jsonb,
  created_by uuid references public.profiles (id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index maintenance_orders_plant_idx on public.maintenance_orders (plant_id, status, created_at desc);

create table public.shift_handovers (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants (id) on delete cascade,
  shift text not null,
  shift_date date not null default current_date,
  from_user uuid references public.profiles (id) on delete set null,
  from_user_name text,
  to_user uuid references public.profiles (id) on delete set null,
  to_user_name text,
  summary text not null default '',
  open_issues jsonb not null default '[]'::jsonb,
  checklist jsonb not null default '{}'::jsonb,
  status public.handover_status not null default 'draft',
  submitted_at timestamptz,
  acknowledged_at timestamptz,
  acknowledged_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index shift_handovers_plant_idx on public.shift_handovers (plant_id, created_at desc);

create table public.events (
  id bigint generated always as identity primary key,
  plant_id uuid references public.plants (id) on delete cascade,
  ts timestamptz not null default now(),
  category text not null,
  level text not null default 'info',
  message text not null,
  actor text,
  data jsonb not null default '{}'::jsonb
);
create index events_plant_ts_idx on public.events (plant_id, ts desc);

-- -----------------------------------------------------------------------------
-- Helper functions and triggers
-- -----------------------------------------------------------------------------
create or replace function public.acme_role()
returns public.user_role
language sql stable security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger equipment_updated_at before update on public.equipment for each row execute function public.set_updated_at();
create trigger process_state_updated_at before update on public.process_state for each row execute function public.set_updated_at();
create trigger alarms_updated_at before update on public.alarms for each row execute function public.set_updated_at();
create trigger setpoints_updated_at before update on public.setpoints for each row execute function public.set_updated_at();
create trigger maintenance_updated_at before update on public.maintenance_orders for each row execute function public.set_updated_at();
create trigger handovers_updated_at before update on public.shift_handovers for each row execute function public.set_updated_at();

-- Create a profile row for each new auth user. Role and name can be passed in user metadata.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role := 'operator';
begin
  begin
    v_role := coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'operator');
  exception when others then
    v_role := 'operator';
  end;
  insert into public.profiles (id, email, full_name, role)
  values (new.id, new.email, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)), v_role)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Only supervisors may change roles from the client (service role bypasses this).
create or replace function public.protect_profile_role()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role <> old.role and auth.uid() is not null and coalesce(public.acme_role(), 'operator') <> 'supervisor' then
    raise exception 'Only supervisors can change roles';
  end if;
  return new;
end $$;
create trigger profiles_protect_role before update on public.profiles for each row execute function public.protect_profile_role();

-- Atomically claim a simulation tick. Returns elapsed seconds since the last tick,
-- or null when the minimum interval has not elapsed yet (another client just ticked).
create or replace function public.claim_tick(p_plant_id uuid, p_min_interval_ms integer default 800)
returns double precision
language plpgsql security definer set search_path = public as $$
declare
  v_prev timestamptz;
  v_now timestamptz := clock_timestamp();
begin
  select last_tick_at into v_prev from public.process_state where plant_id = p_plant_id for update;
  if v_prev is null then
    return null;
  end if;
  if v_now - v_prev < make_interval(secs => p_min_interval_ms / 1000.0) then
    return null;
  end if;
  update public.process_state set last_tick_at = v_now where plant_id = p_plant_id;
  return extract(epoch from (v_now - v_prev));
end $$;
revoke all on function public.claim_tick(uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_tick(uuid, integer) to service_role;

-- -----------------------------------------------------------------------------
-- Row level security
-- -----------------------------------------------------------------------------
alter table public.plants enable row level security;
alter table public.profiles enable row level security;
alter table public.equipment enable row level security;
alter table public.process_state enable row level security;
alter table public.trend_samples enable row level security;
alter table public.alarms enable row level security;
alter table public.commands enable row level security;
alter table public.setpoints enable row level security;
alter table public.setpoint_requests enable row level security;
alter table public.maintenance_orders enable row level security;
alter table public.shift_handovers enable row level security;
alter table public.events enable row level security;

-- Everything is readable by signed-in users
create policy "plants read" on public.plants for select to authenticated using (true);
create policy "profiles read" on public.profiles for select to authenticated using (true);
create policy "equipment read" on public.equipment for select to authenticated using (true);
create policy "process_state read" on public.process_state for select to authenticated using (true);
create policy "trend_samples read" on public.trend_samples for select to authenticated using (true);
create policy "alarms read" on public.alarms for select to authenticated using (true);
create policy "commands read" on public.commands for select to authenticated using (true);
create policy "setpoints read" on public.setpoints for select to authenticated using (true);
create policy "setpoint_requests read" on public.setpoint_requests for select to authenticated using (true);
create policy "maintenance read" on public.maintenance_orders for select to authenticated using (true);
create policy "handovers read" on public.shift_handovers for select to authenticated using (true);
create policy "events read" on public.events for select to authenticated using (true);

-- Profiles: users edit their own profile, supervisors can edit anyone
create policy "profiles update" on public.profiles for update to authenticated
  using (id = auth.uid() or public.acme_role() = 'supervisor')
  with check (id = auth.uid() or public.acme_role() = 'supervisor');

-- Alarms: operators, engineers and supervisors acknowledge
create policy "alarms acknowledge" on public.alarms for update to authenticated
  using (public.acme_role() in ('operator', 'engineer', 'supervisor'))
  with check (public.acme_role() in ('operator', 'engineer', 'supervisor'));

-- Setpoint requests: proposals by operators, engineers and supervisors. Review goes through the API.
create policy "setpoint_requests insert" on public.setpoint_requests for insert to authenticated
  with check (requested_by = auth.uid() and public.acme_role() in ('operator', 'engineer', 'supervisor'));

-- Maintenance orders: maintenance, engineers and supervisors manage them
create policy "maintenance insert" on public.maintenance_orders for insert to authenticated
  with check (created_by = auth.uid() and public.acme_role() in ('maintenance', 'engineer', 'supervisor'));
create policy "maintenance update" on public.maintenance_orders for update to authenticated
  using (public.acme_role() in ('maintenance', 'engineer', 'supervisor'))
  with check (public.acme_role() in ('maintenance', 'engineer', 'supervisor'));

-- Shift handovers: created by the outgoing operator, acknowledged by the incoming one or a supervisor
create policy "handovers insert" on public.shift_handovers for insert to authenticated
  with check (from_user = auth.uid() and public.acme_role() in ('operator', 'engineer', 'supervisor'));
create policy "handovers update" on public.shift_handovers for update to authenticated
  using (from_user = auth.uid() or to_user = auth.uid() or public.acme_role() = 'supervisor')
  with check (from_user = auth.uid() or to_user = auth.uid() or public.acme_role() = 'supervisor');

-- Events: clients may append audit events (e.g. sign-in), never edit them
create policy "events insert" on public.events for insert to authenticated with check (true);

-- -----------------------------------------------------------------------------
-- Realtime
-- -----------------------------------------------------------------------------
alter table public.process_state replica identity full;
alter table public.equipment replica identity full;
alter table public.alarms replica identity full;
alter table public.commands replica identity full;
alter table public.setpoints replica identity full;
alter table public.setpoint_requests replica identity full;
alter table public.maintenance_orders replica identity full;
alter table public.shift_handovers replica identity full;
alter table public.events replica identity full;
alter table public.plants replica identity full;
alter table public.profiles replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
alter publication supabase_realtime add table
  public.process_state, public.equipment, public.alarms, public.commands,
  public.setpoints, public.setpoint_requests, public.maintenance_orders,
  public.shift_handovers, public.events, public.plants, public.profiles;

-- -----------------------------------------------------------------------------
-- Storage: attachments bucket (avatars, maintenance photos, handover files)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', true, 10485760, array['image/png', 'image/jpeg', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

create policy "attachments public read" on storage.objects for select using (bucket_id = 'attachments');
create policy "attachments authenticated upload" on storage.objects for insert to authenticated with check (bucket_id = 'attachments');
create policy "attachments owner update" on storage.objects for update to authenticated using (bucket_id = 'attachments' and owner = auth.uid());
create policy "attachments owner delete" on storage.objects for delete to authenticated using (bucket_id = 'attachments' and owner = auth.uid());
