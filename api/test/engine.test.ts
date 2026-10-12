import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { isPumpEngaged, startInterlock, stepSimulation } from '../src/sim/engine.js';
import { findScenario } from '../src/sim/scenarios.js';
import { advance } from '../src/sim/service.js';
import type { EngineContext, EquipmentRow } from '../src/sim/types.js';
import { applyCommand, validateCommand } from '../src/routes/commands.js';

const PLANT = '11111111-1111-4111-8111-111111111111';

function row(tag: string, name: string, type: EquipmentRow['type'], params: Record<string, unknown>, extra: Partial<EquipmentRow> = {}): EquipmentRow {
  return {
    id: `id-${tag}`,
    plant_id: PLANT,
    tag,
    name,
    type,
    area: null,
    mode: 'auto',
    requested_state: type === 'pump' ? 'stop' : type === 'valve' ? 'close' : 'n/a',
    actual_state: type === 'pump' ? 'stopped' : type === 'valve' ? 'closed' : 'ok',
    position: 0,
    under_maintenance: false,
    fault: null,
    interlock: null,
    runtime_hours: 0,
    starts_count: 0,
    params,
    sort_order: 0,
    ...extra,
  };
}

function makeContext(t1Level = 60, t2Level = 70): EngineContext {
  const equipment: EquipmentRow[] = [
    row('T1', 'Raw Water Tank', 'tank', { capacity_m3: 600, hh: 95, h: 88, l: 25, ll: 10 }, { position: t1Level }),
    row('T2', 'Treated Water Tank', 'tank', { capacity_m3: 800, hh: 95, h: 90, l: 30, ll: 15 }, { position: t2Level }),
    row('P1', 'Intake Pump', 'pump', { rated_flow_m3h: 150, rated_pressure_bar: 3.2, source: 'intake', sink: 'T1', valve: 'V1' }),
    row('V1', 'Inlet Valve', 'valve', { travel_time_s: 12, pump: 'P1' }),
    row('P2', 'Transfer Pump', 'pump', { rated_flow_m3h: 130, rated_pressure_bar: 2.8, source: 'T1', sink: 'T2', valve: 'V2' }, { requested_state: 'run', actual_state: 'running', position: 100 }),
    row('V2', 'Transfer Valve', 'valve', { travel_time_s: 15, pump: 'P2' }, { requested_state: 'open', actual_state: 'open', position: 100 }),
    row('P3', 'Distribution Pump', 'pump', { rated_flow_m3h: 140, rated_pressure_bar: 4.5, source: 'T2', sink: 'network', valve: 'V3' }, { requested_state: 'run', actual_state: 'running', position: 100 }),
    row('V3', 'Outlet Valve', 'valve', { travel_time_s: 10, pump: 'P3' }, { requested_state: 'open', actual_state: 'open', position: 100 }),
    row('LT1', 'Raw Water Level', 'sensor', { kind: 'level', unit: '%' }),
    row('LT2', 'Treated Water Level', 'sensor', { kind: 'level', unit: '%' }),
    row('FT2', 'Transfer Flow', 'sensor', { kind: 'flow', unit: 'm³/h' }),
    row('PT3', 'Network Pressure', 'sensor', { kind: 'pressure', unit: 'bar' }),
    row('TU1', 'Turbidity', 'sensor', { kind: 'turbidity', unit: 'NTU' }),
    row('CL1', 'Chlorine', 'sensor', { kind: 'chlorine', unit: 'mg/L' }),
  ];
  return {
    equipment,
    setpoints: { T1_START: 40, T1_STOP: 85, T2_START: 45, T2_STOP: 90, NET_PRESSURE: 4.0, CL_TARGET: 1.2, TURB_MAX: 1.0 },
    state: {
      plant_id: PLANT,
      scenario: 'normal',
      sim_time: '2026-10-11T12:00:00.000Z',
      last_tick_at: '2026-10-11T12:00:00.000Z',
      speed: 1,
      running: true,
      values: { LT1: t1Level, LT2: t2Level, FT1: 0, FT2: 130, FT3: 110, PT1: 0, PT2: 2.8, PT3: 4.0, TU1: 0.4, CL1: 1.2 },
      tanks: {
        T1: { level: t1Level, volume: (600 * t1Level) / 100, capacity: 600, inflow: 0, outflow: 0 },
        T2: { level: t2Level, volume: (800 * t2Level) / 100, capacity: 800, inflow: 0, outflow: 0 },
      },
      conditions: { source_available: true, demand_factor: 1, demand_nominal: 110, demand_m3h: 110, sensor_faults: [] },
    },
  };
}

const get = (ctx: EngineContext, tag: string) => ctx.equipment.find((e) => e.tag === tag)!;

describe('engine', () => {
  it('a manual start ramps the pump to running and fills the tank', () => {
    const ctx = makeContext(50, 70);
    const p1 = get(ctx, 'P1');
    const v1 = get(ctx, 'V1');
    p1.mode = 'manual';
    v1.mode = 'manual';
    v1.requested_state = 'open';
    assert.equal(validateCommand('operator', p1, 'start', undefined, ctx), null);
    applyCommand(p1, 'start', undefined);
    const before = ctx.state.tanks.T1.volume;
    advance(ctx, 60);
    assert.equal(p1.actual_state, 'running');
    assert.equal(p1.requested_state, 'run');
    assert.equal(v1.actual_state, 'open');
    assert.ok(ctx.state.values.FT1 > 100, `expected intake flow, got ${ctx.state.values.FT1}`);
    assert.ok(ctx.state.tanks.T1.volume > before, 'raw tank should fill');
  });

  it('shows requested and actual state separately while starting', () => {
    const ctx = makeContext(50, 70);
    const p1 = get(ctx, 'P1');
    p1.mode = 'manual';
    get(ctx, 'V1').mode = 'manual';
    get(ctx, 'V1').requested_state = 'open';
    applyCommand(p1, 'start', undefined);
    stepSimulation(ctx, 1);
    assert.equal(p1.requested_state, 'run');
    assert.equal(p1.actual_state, 'starting');
    assert.ok(p1.position > 0 && p1.position < 100);
  });

  it('refuses to start a pump when its source tank is empty', () => {
    const ctx = makeContext(2, 70);
    const p2 = get(ctx, 'P2');
    p2.mode = 'manual';
    p2.actual_state = 'stopped';
    p2.requested_state = 'stop';
    p2.position = 0;
    const reason = validateCommand('operator', p2, 'start', undefined, ctx);
    assert.match(reason ?? '', /Interlock: T1 empty/);
    assert.match(startInterlock(p2, ctx) ?? '', /T1 empty/);
  });

  it('trips a running pump when the tank runs dry and keeps it tripped until reset', () => {
    const ctx = makeContext(4, 70);
    const p2 = get(ctx, 'P2');
    p2.mode = 'manual';
    get(ctx, 'V2').mode = 'manual';
    get(ctx, 'P1').mode = 'manual';
    // P1 stopped in manual, P2 drains T1
    advance(ctx, 600);
    assert.equal(p2.actual_state, 'tripped');
    assert.match(p2.fault ?? '', /Dry-run/);
    assert.ok(ctx.state.tanks.T1.level <= 3.5);
    const trip = advance(ctx, 5).alarms.find((a) => a.code === 'P2_TRIP');
    assert.ok(trip?.active, 'P2_TRIP alarm should be active');
    assert.equal(validateCommand('operator', p2, 'start', undefined, ctx), 'Interlock: P2 is tripped - reset required');
    applyCommand(p2, 'reset', undefined);
    assert.equal(p2.actual_state, 'stopped');
  });

  it('blocks commands on equipment under maintenance', () => {
    const ctx = makeContext(60, 70);
    const p1 = get(ctx, 'P1');
    p1.mode = 'manual';
    p1.under_maintenance = true;
    assert.match(validateCommand('operator', p1, 'start', undefined, ctx) ?? '', /under maintenance/);
    p1.requested_state = 'run';
    advance(ctx, 30);
    assert.equal(p1.actual_state, 'maintenance');
    assert.equal(ctx.state.values.FT1, 0);
  });

  it('rejects commands from the maintenance role and in auto mode', () => {
    const ctx = makeContext(60, 70);
    const p1 = get(ctx, 'P1');
    assert.match(validateCommand('maintenance', p1, 'start', undefined, ctx) ?? '', /not allowed/);
    assert.match(validateCommand('operator', p1, 'start', undefined, ctx) ?? '', /automatic mode/);
    assert.equal(validateCommand('operator', p1, 'set_mode', 'manual', ctx), null);
  });

  it('auto control starts the intake pump below the start setpoint and stops above the stop setpoint', () => {
    const ctx = makeContext(38, 70);
    const p1 = get(ctx, 'P1');
    const res = advance(ctx, 30);
    assert.equal(p1.requested_state, 'run');
    assert.ok(isPumpEngaged(p1));
    assert.ok(res.events.some((e) => e.message.includes('Auto control: P1 start requested')));
    ctx.state.tanks.T1.level = 90;
    ctx.state.tanks.T1.volume = 540;
    advance(ctx, 30);
    assert.equal(p1.requested_state, 'stop');
  });

  it('raises tank level alarms and overflow when the raw tank is over-filled in manual', () => {
    const ctx = makeContext(94, 80);
    const p1 = get(ctx, 'P1');
    const v1 = get(ctx, 'V1');
    const p2 = get(ctx, 'P2');
    p1.mode = 'manual';
    v1.mode = 'manual';
    p2.mode = 'manual';
    p2.requested_state = 'stop';
    v1.requested_state = 'open';
    applyCommand(p1, 'start', undefined);
    const res = advance(ctx, 20 * 60);
    const codes = res.alarms.filter((a) => a.active).map((a) => a.code);
    assert.ok(codes.includes('T1_HH'), `expected T1_HH in ${codes}`);
    assert.ok(codes.includes('T1_OVERFLOW'), `expected T1_OVERFLOW in ${codes}`);
    assert.equal(ctx.state.tanks.T1.level, 100);
  });

  it('samples trends once per simulated minute', () => {
    const ctx = makeContext();
    const res = advance(ctx, 10 * 60);
    const lt1 = res.trends.filter((t) => t.tag === 'LT1');
    assert.equal(lt1.length, 10);
  });

  it('scenario: intake failure trips P1 and raises INTAKE_UNAVAILABLE', () => {
    const ctx = makeContext();
    findScenario('intake_failure')!.apply(ctx);
    const res = advance(ctx, 10);
    const active = res.alarms.filter((a) => a.active).map((a) => a.code);
    assert.ok(active.includes('INTAKE_UNAVAILABLE'));
    assert.ok(active.includes('P1_TRIP'));
    assert.equal(get(ctx, 'P1').actual_state, 'tripped');
  });

  it('scenario: sensor fault switches dependent pumps to manual', () => {
    const ctx = makeContext();
    findScenario('sensor_fault')!.apply(ctx);
    const res = advance(ctx, 5);
    assert.equal(get(ctx, 'P2').mode, 'manual');
    assert.equal(get(ctx, 'P3').mode, 'manual');
    assert.ok(res.alarms.find((a) => a.code === 'LT2_FAULT')?.active);
    assert.equal(ctx.state.values.LT2, 52);
  });
});
