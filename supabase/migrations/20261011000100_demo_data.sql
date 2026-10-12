-- =============================================================================
-- ACME Control - demo data generator
-- seed_demo_data() is idempotent: it keeps plants and users and rebuilds all
-- operational data (equipment, setpoints, process state, alarms, maintenance
-- orders, handovers, commands, events and 24 h of trend history).
-- It is called by supabase/seed.sql and by the API "Reset demo data" action.
-- =============================================================================

create or replace function public.seed_plant_demo(
  p_plant_id uuid,
  p_t1_capacity numeric,
  p_t2_capacity numeric,
  p_p1_flow numeric,
  p_p2_flow numeric,
  p_p3_flow numeric,
  p_demand numeric,
  p_t1_level numeric,
  p_t2_level numeric
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_operator uuid;
  v_engineer uuid;
  v_supervisor uuid;
  v_maintenance uuid;
  v_operator_name text;
  v_engineer_name text;
  v_supervisor_name text;
  v_maintenance_name text;
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_v1 uuid; v_v2 uuid; v_v3 uuid; v_t1 uuid; v_t2 uuid; v_lt2 uuid;
  v_sp_t2_start uuid;
  v_code text;
begin
  select id, full_name into v_operator, v_operator_name from public.profiles where email = 'operator@acme.demo';
  select id, full_name into v_engineer, v_engineer_name from public.profiles where email = 'engineer@acme.demo';
  select id, full_name into v_supervisor, v_supervisor_name from public.profiles where email = 'supervisor@acme.demo';
  select id, full_name into v_maintenance, v_maintenance_name from public.profiles where email = 'maintenance@acme.demo';
  select code into v_code from public.plants where id = p_plant_id;

  -- wipe operational data for this plant
  delete from public.trend_samples where plant_id = p_plant_id;
  delete from public.events where plant_id = p_plant_id;
  delete from public.commands where plant_id = p_plant_id;
  delete from public.alarms where plant_id = p_plant_id;
  delete from public.setpoint_requests where plant_id = p_plant_id;
  delete from public.maintenance_orders where plant_id = p_plant_id;
  delete from public.shift_handovers where plant_id = p_plant_id;
  delete from public.setpoints where plant_id = p_plant_id;
  delete from public.equipment where plant_id = p_plant_id;
  delete from public.process_state where plant_id = p_plant_id;

  -- ---------------------------------------------------------------- equipment
  insert into public.equipment (plant_id, tag, name, type, area, mode, requested_state, actual_state, position, params, sort_order, runtime_hours, starts_count)
  values
    (p_plant_id, 'T1', 'Raw Water Tank', 'tank', 'Intake', 'auto', 'n/a', 'ok', p_t1_level,
      jsonb_build_object('capacity_m3', p_t1_capacity, 'height_m', 6.0, 'hh', 95, 'h', 88, 'l', 25, 'll', 10), 10, 0, 0),
    (p_plant_id, 'T2', 'Treated Water Tank', 'tank', 'Storage', 'auto', 'n/a', 'ok', p_t2_level,
      jsonb_build_object('capacity_m3', p_t2_capacity, 'height_m', 7.5, 'hh', 95, 'h', 90, 'l', 30, 'll', 15), 20, 0, 0),
    (p_plant_id, 'P1', 'Intake Pump', 'pump', 'Intake', 'auto', 'stop', 'stopped', 0,
      jsonb_build_object('rated_flow_m3h', p_p1_flow, 'rated_pressure_bar', 3.2, 'source', 'intake', 'sink', 'T1', 'valve', 'V1', 'power_kw', 22), 30, 1842.5, 612),
    (p_plant_id, 'V1', 'Inlet Valve', 'valve', 'Intake', 'auto', 'close', 'closed', 0,
      jsonb_build_object('travel_time_s', 12, 'pump', 'P1'), 40, 0, 0),
    (p_plant_id, 'P2', 'Transfer Pump', 'pump', 'Treatment', 'auto', 'run', 'running', 100,
      jsonb_build_object('rated_flow_m3h', p_p2_flow, 'rated_pressure_bar', 2.8, 'source', 'T1', 'sink', 'T2', 'valve', 'V2', 'power_kw', 18.5), 50, 2210.0, 488),
    (p_plant_id, 'V2', 'Transfer Valve', 'valve', 'Treatment', 'auto', 'open', 'open', 100,
      jsonb_build_object('travel_time_s', 15, 'pump', 'P2'), 60, 0, 0),
    (p_plant_id, 'P3', 'Distribution Pump', 'pump', 'Distribution', 'auto', 'run', 'running', 100,
      jsonb_build_object('rated_flow_m3h', p_p3_flow, 'rated_pressure_bar', 4.5, 'source', 'T2', 'sink', 'network', 'valve', 'V3', 'power_kw', 30), 70, 3105.2, 301),
    (p_plant_id, 'V3', 'Outlet Valve', 'valve', 'Distribution', 'auto', 'open', 'open', 100,
      jsonb_build_object('travel_time_s', 10, 'pump', 'P3'), 80, 0, 0),
    (p_plant_id, 'LT1', 'Raw Water Level', 'sensor', 'Intake', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'level', 'unit', '%', 'min', 0, 'max', 100, 'tank', 'T1'), 90, 0, 0),
    (p_plant_id, 'LT2', 'Treated Water Level', 'sensor', 'Storage', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'level', 'unit', '%', 'min', 0, 'max', 100, 'tank', 'T2'), 91, 0, 0),
    (p_plant_id, 'FT1', 'Intake Flow', 'sensor', 'Intake', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'flow', 'unit', 'm³/h', 'min', 0, 'max', p_p1_flow * 1.2, 'pump', 'P1'), 92, 0, 0),
    (p_plant_id, 'FT2', 'Transfer Flow', 'sensor', 'Treatment', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'flow', 'unit', 'm³/h', 'min', 0, 'max', p_p2_flow * 1.2, 'pump', 'P2'), 93, 0, 0),
    (p_plant_id, 'FT3', 'Distribution Flow', 'sensor', 'Distribution', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'flow', 'unit', 'm³/h', 'min', 0, 'max', p_p3_flow * 1.2, 'pump', 'P3'), 94, 0, 0),
    (p_plant_id, 'PT1', 'Intake Pressure', 'sensor', 'Intake', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'pressure', 'unit', 'bar', 'min', 0, 'max', 6, 'pump', 'P1'), 95, 0, 0),
    (p_plant_id, 'PT2', 'Transfer Pressure', 'sensor', 'Treatment', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'pressure', 'unit', 'bar', 'min', 0, 'max', 6, 'pump', 'P2'), 96, 0, 0),
    (p_plant_id, 'PT3', 'Network Pressure', 'sensor', 'Distribution', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'pressure', 'unit', 'bar', 'min', 0, 'max', 8, 'pump', 'P3'), 97, 0, 0),
    (p_plant_id, 'TU1', 'Treated Water Turbidity', 'sensor', 'Treatment', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'turbidity', 'unit', 'NTU', 'min', 0, 'max', 5), 98, 0, 0),
    (p_plant_id, 'CL1', 'Chlorine Residual', 'sensor', 'Treatment', 'auto', 'n/a', 'ok', 0,
      jsonb_build_object('kind', 'chlorine', 'unit', 'mg/L', 'min', 0, 'max', 4), 99, 0, 0);

  select id into v_p1 from public.equipment where plant_id = p_plant_id and tag = 'P1';
  select id into v_p2 from public.equipment where plant_id = p_plant_id and tag = 'P2';
  select id into v_p3 from public.equipment where plant_id = p_plant_id and tag = 'P3';
  select id into v_v1 from public.equipment where plant_id = p_plant_id and tag = 'V1';
  select id into v_v2 from public.equipment where plant_id = p_plant_id and tag = 'V2';
  select id into v_v3 from public.equipment where plant_id = p_plant_id and tag = 'V3';
  select id into v_t1 from public.equipment where plant_id = p_plant_id and tag = 'T1';
  select id into v_t2 from public.equipment where plant_id = p_plant_id and tag = 'T2';
  select id into v_lt2 from public.equipment where plant_id = p_plant_id and tag = 'LT2';

  -- ---------------------------------------------------------------- setpoints
  insert into public.setpoints (plant_id, key, label, description, value, unit, min_value, max_value, group_name, updated_by)
  values
    (p_plant_id, 'T1_START', 'Raw tank - start intake pump', 'Intake pump P1 starts (auto mode) when raw water level drops below this value.', 40, '%', 15, 80, 'Level control', v_engineer),
    (p_plant_id, 'T1_STOP', 'Raw tank - stop intake pump', 'Intake pump P1 stops (auto mode) when raw water level rises above this value.', 85, '%', 50, 94, 'Level control', v_engineer),
    (p_plant_id, 'T2_START', 'Treated tank - start transfer pump', 'Transfer pump P2 starts (auto mode) when treated water level drops below this value.', 45, '%', 20, 80, 'Level control', v_engineer),
    (p_plant_id, 'T2_STOP', 'Treated tank - stop transfer pump', 'Transfer pump P2 stops (auto mode) when treated water level rises above this value.', 90, '%', 50, 94, 'Level control', v_engineer),
    (p_plant_id, 'NET_PRESSURE', 'Network pressure target', 'Target discharge pressure of distribution pump P3.', 4.0, 'bar', 2.5, 6.0, 'Distribution', v_engineer),
    (p_plant_id, 'CL_TARGET', 'Chlorine residual target', 'Target free chlorine residual at the outlet of the treatment stage.', 1.2, 'mg/L', 0.5, 2.5, 'Water quality', v_engineer),
    (p_plant_id, 'TURB_MAX', 'Turbidity alarm limit', 'Turbidity above this limit raises a water quality alarm.', 1.0, 'NTU', 0.3, 4.0, 'Water quality', v_engineer);

  select id into v_sp_t2_start from public.setpoints where plant_id = p_plant_id and key = 'T2_START';

  -- ---------------------------------------------------------------- process state
  insert into public.process_state (plant_id, scenario, sim_time, last_tick_at, speed, running, "values", tanks, conditions)
  values (
    p_plant_id, 'normal', now(), now(), 1, true,
    jsonb_build_object(
      'LT1', p_t1_level, 'LT2', p_t2_level,
      'FT1', 0, 'FT2', p_p2_flow, 'FT3', p_demand,
      'PT1', 0, 'PT2', 2.8, 'PT3', 4.0,
      'TU1', 0.42, 'CL1', 1.18
    ),
    jsonb_build_object(
      'T1', jsonb_build_object('level', p_t1_level, 'volume', round(p_t1_capacity * p_t1_level / 100, 1), 'capacity', p_t1_capacity, 'inflow', 0, 'outflow', p_p2_flow),
      'T2', jsonb_build_object('level', p_t2_level, 'volume', round(p_t2_capacity * p_t2_level / 100, 1), 'capacity', p_t2_capacity, 'inflow', p_p2_flow, 'outflow', p_demand)
    ),
    jsonb_build_object('source_available', true, 'demand_factor', 1.0, 'demand_nominal', p_demand, 'demand_m3h', p_demand, 'sensor_faults', '[]'::jsonb)
  );

  -- ---------------------------------------------------------------- trend history (24 h, every 10 min)
  insert into public.trend_samples (plant_id, tag, ts, value)
  select p_plant_id, s.tag, g.ts,
    case s.tag
      when 'LT1' then round((p_t1_level + 18 * sin(extract(epoch from g.ts) / 5400.0) + 4 * sin(extract(epoch from g.ts) / 700.0))::numeric, 1)
      when 'LT2' then round((p_t2_level + 12 * sin(extract(epoch from g.ts) / 9000.0 + 1.2) + 3 * sin(extract(epoch from g.ts) / 500.0))::numeric, 1)
      when 'FT1' then round(greatest(0, p_p1_flow * (0.55 + 0.45 * sign(sin(extract(epoch from g.ts) / 5400.0))))::numeric, 1)
      when 'FT2' then round(greatest(0, p_p2_flow * (0.92 + 0.08 * sin(extract(epoch from g.ts) / 1300.0)))::numeric, 1)
      when 'FT3' then round(greatest(0, p_demand * (1 + 0.35 * sin((extract(hour from g.ts) + extract(minute from g.ts) / 60.0 - 7) / 24.0 * 2 * pi())))::numeric, 1)
      when 'PT3' then round((4.0 + 0.25 * sin(extract(epoch from g.ts) / 2300.0))::numeric, 2)
      when 'TU1' then round((0.4 + 0.15 * sin(extract(epoch from g.ts) / 4100.0) + 0.05 * sin(extract(epoch from g.ts) / 300.0))::numeric, 2)
      when 'CL1' then round((1.2 + 0.12 * sin(extract(epoch from g.ts) / 3600.0))::numeric, 2)
    end
  from generate_series(now() - interval '24 hours', now(), interval '10 minutes') as g(ts)
  cross join (values ('LT1'), ('LT2'), ('FT1'), ('FT2'), ('FT3'), ('PT3'), ('TU1'), ('CL1')) as s(tag);

  -- ---------------------------------------------------------------- alarms
  insert into public.alarms (plant_id, equipment_id, code, tag, severity, message, state, value, raised_at, acked_at, acked_by, acked_by_name, cleared_at)
  values
    (p_plant_id, v_t2, 'T2_L', 'T2', 'medium', 'Treated water tank level low (28.4 %)', 'cleared', 28.4, now() - interval '7 hours', now() - interval '6 hours 50 minutes', v_operator, v_operator_name, now() - interval '5 hours 30 minutes'),
    (p_plant_id, v_p2, 'P2_VIBRATION', 'P2', 'medium', 'High vibration on transfer pump P2 (7.2 mm/s)', 'acknowledged', 7.2, now() - interval '3 hours', now() - interval '2 hours 40 minutes', v_operator, v_operator_name, null),
    (p_plant_id, v_lt2, 'LT2_CAL_DUE', 'LT2', 'low', 'Level transmitter LT2 calibration due', 'active', null, now() - interval '45 minutes', null, null, null, null);

  -- ---------------------------------------------------------------- maintenance orders
  insert into public.maintenance_orders (plant_id, equipment_id, equipment_tag, title, description, priority, status, assigned_to, assigned_to_name, scheduled_for, started_at, completed_at, work_notes, created_by, created_by_name, created_at)
  values
    (p_plant_id, v_p1, 'P1', 'Replace mechanical seal on intake pump', 'Seal leak detected during weekly round. Replace seal kit and check alignment.', 'high', 'done', v_maintenance, v_maintenance_name, now() - interval '4 days', now() - interval '3 days 6 hours', now() - interval '3 days 2 hours', 'Seal replaced, alignment within 0.05 mm. Test run 30 min OK.', v_engineer, v_engineer_name, now() - interval '5 days'),
    (p_plant_id, v_p2, 'P2', 'Transfer pump vibration inspection', 'Vibration alarm P2_VIBRATION. Check bearings, coupling and foundation bolts.', 'high', 'in_progress', v_maintenance, v_maintenance_name, now() - interval '2 hours', now() - interval '1 hour 30 minutes', null, 'Coupling inspected, slight misalignment found. Bearing temperature normal.', v_supervisor, v_supervisor_name, now() - interval '2 hours 50 minutes'),
    (p_plant_id, v_lt2, 'LT2', 'Calibrate treated water level transmitter', 'Annual calibration of LT2 against manual dip measurement.', 'medium', 'open', v_maintenance, v_maintenance_name, now() + interval '2 days', null, null, null, v_engineer, v_engineer_name, now() - interval '1 day'),
    (p_plant_id, v_v3, 'V3', 'Outlet valve actuator lubrication', 'Quarterly lubrication of V3 actuator gearbox and stem.', 'low', 'open', null, null, now() + interval '9 days', null, null, null, v_maintenance, v_maintenance_name, now() - interval '3 hours');

  -- ---------------------------------------------------------------- shift handovers
  insert into public.shift_handovers (plant_id, shift, shift_date, from_user, from_user_name, to_user, to_user_name, summary, open_issues, checklist, status, submitted_at, acknowledged_at, acknowledged_by, created_at)
  values
    (p_plant_id, 'night', current_date - 1, v_operator, v_operator_name, v_supervisor, v_supervisor_name,
      'Quiet night. T2 low level alarm around 02:00 cleared after P2 restarted in auto. Chlorine dosing stable.',
      '["Monitor P2 vibration trend", "LT2 calibration scheduled"]'::jsonb,
      '{"alarms_reviewed": true, "levels_checked": true, "chemicals_checked": true, "logbook_updated": true}'::jsonb,
      'acknowledged', now() - interval '16 hours', now() - interval '15 hours 40 minutes', v_supervisor, now() - interval '16 hours 10 minutes'),
    (p_plant_id, 'day', current_date, v_operator, v_operator_name, null, null,
      'P2 vibration acknowledged, maintenance on site. Intake flow normal, no water quality deviations.',
      '["WO on P2 in progress - do not run P2 above 90 % speed"]'::jsonb,
      '{"alarms_reviewed": true, "levels_checked": true, "chemicals_checked": false, "logbook_updated": true}'::jsonb,
      'submitted', now() - interval '25 minutes', null, null, now() - interval '40 minutes');

  -- ---------------------------------------------------------------- setpoint requests
  insert into public.setpoint_requests (plant_id, setpoint_id, setpoint_key, setpoint_label, requested_by, requested_by_name, current_value, proposed_value, justification, status, reviewed_by, reviewed_by_name, review_note, reviewed_at, created_at)
  values
    (p_plant_id, v_sp_t2_start, 'T2_START', 'Treated tank - start transfer pump', v_engineer, v_engineer_name, 45, 50,
      'Evening demand peaks are draining T2 faster than P2 can recover. Starting P2 earlier keeps a safer reserve.', 'pending', null, null, null, null, now() - interval '55 minutes'),
    (p_plant_id, (select id from public.setpoints where plant_id = p_plant_id and key = 'CL_TARGET'), 'CL_TARGET', 'Chlorine residual target', v_operator, v_operator_name, 1.0, 1.2,
      'Residual at the far end of the network was below 0.3 mg/L during the last sampling campaign.', 'approved', v_supervisor, v_supervisor_name, 'Approved. Keep an eye on DBP formation.', now() - interval '2 days', now() - interval '2 days 3 hours');

  -- ---------------------------------------------------------------- commands
  insert into public.commands (plant_id, equipment_id, equipment_tag, user_id, user_name, type, value, status, reason, created_at, executed_at)
  values
    (p_plant_id, v_p2, 'P2', v_operator, v_operator_name, 'set_mode', '"manual"'::jsonb, 'executed', null, now() - interval '5 hours', now() - interval '5 hours'),
    (p_plant_id, v_p2, 'P2', v_operator, v_operator_name, 'start', null, 'executed', null, now() - interval '4 hours 58 minutes', now() - interval '4 hours 58 minutes'),
    (p_plant_id, v_p2, 'P2', v_operator, v_operator_name, 'set_mode', '"auto"'::jsonb, 'executed', null, now() - interval '4 hours 20 minutes', now() - interval '4 hours 20 minutes'),
    (p_plant_id, v_p1, 'P1', v_maintenance, v_maintenance_name, 'start', null, 'rejected', 'Role maintenance is not allowed to operate pumps', now() - interval '3 hours 10 minutes', null);

  -- ---------------------------------------------------------------- events
  insert into public.events (plant_id, ts, category, level, message, actor, data)
  values
    (p_plant_id, now() - interval '7 hours', 'alarm', 'warning', 'Alarm raised: Treated water tank level low (28.4 %)', 'simulation', '{"code": "T2_L"}'::jsonb),
    (p_plant_id, now() - interval '6 hours 50 minutes', 'alarm', 'info', 'Alarm T2_L acknowledged', v_operator_name, '{"code": "T2_L"}'::jsonb),
    (p_plant_id, now() - interval '5 hours 30 minutes', 'alarm', 'info', 'Alarm T2_L cleared', 'simulation', '{"code": "T2_L"}'::jsonb),
    (p_plant_id, now() - interval '5 hours', 'command', 'info', 'P2 mode set to manual', v_operator_name, '{"tag": "P2", "type": "set_mode"}'::jsonb),
    (p_plant_id, now() - interval '4 hours 58 minutes', 'command', 'info', 'Start command accepted for P2', v_operator_name, '{"tag": "P2", "type": "start"}'::jsonb),
    (p_plant_id, now() - interval '3 hours', 'alarm', 'warning', 'Alarm raised: High vibration on transfer pump P2 (7.2 mm/s)', 'simulation', '{"code": "P2_VIBRATION"}'::jsonb),
    (p_plant_id, now() - interval '2 hours 55 minutes', 'integration', 'info', 'Simulated SMS sent to on-call maintenance: P2 vibration alarm', 'system', '{"channel": "sms", "to": "+1 555 0100"}'::jsonb),
    (p_plant_id, now() - interval '2 hours 50 minutes', 'maintenance', 'info', 'Work order created: Transfer pump vibration inspection', v_supervisor_name, '{"tag": "P2"}'::jsonb),
    (p_plant_id, now() - interval '2 hours 49 minutes', 'integration', 'info', 'Simulated CMMS sync: work order exported', 'system', '{"system": "CMMS"}'::jsonb),
    (p_plant_id, now() - interval '55 minutes', 'setpoint', 'info', 'Setpoint change proposed: T2_START 45 -> 50 %', v_engineer_name, '{"key": "T2_START"}'::jsonb),
    (p_plant_id, now() - interval '25 minutes', 'handover', 'info', 'Day shift handover submitted', v_operator_name, '{}'::jsonb),
    (p_plant_id, now(), 'simulation', 'info', 'Demo data loaded for plant ' || coalesce(v_code, ''), 'system', '{"scenario": "normal"}'::jsonb);
end $$;

create or replace function public.seed_demo_data()
returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.plants (id, code, name, location, timezone, description, status, design_capacity_m3h)
  values
    ('11111111-1111-4111-8111-111111111111', 'NR-01', 'North River WTP', 'Portland, Oregon, USA', 'America/Los_Angeles',
      'Surface water treatment plant on the North River intake. Two-stage storage with chlorination.', 'online', 150),
    ('22222222-2222-4222-8222-222222222222', 'LS-02', 'Lakeside WTP', 'Austin, Texas, USA', 'America/Chicago',
      'Compact lake intake plant serving the Lakeside district. Night-time reservoir filling.', 'online', 90)
  on conflict (code) do update set name = excluded.name, location = excluded.location, timezone = excluded.timezone,
    description = excluded.description, status = excluded.status, design_capacity_m3h = excluded.design_capacity_m3h;

  perform public.seed_plant_demo('11111111-1111-4111-8111-111111111111', 600, 800, 150, 130, 140, 110, 62, 71);
  perform public.seed_plant_demo('22222222-2222-4222-8222-222222222222', 350, 450, 90, 80, 85, 65, 48, 66);

  update public.profiles set default_plant_id = '11111111-1111-4111-8111-111111111111' where default_plant_id is null;
end $$;

revoke all on function public.seed_demo_data() from public, anon, authenticated;
revoke all on function public.seed_plant_demo(uuid, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;
grant execute on function public.seed_demo_data() to service_role;
