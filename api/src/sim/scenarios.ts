import type { EngineContext, EquipmentRow } from './types.js';
import { equipmentByTag } from './engine.js';

export interface ScenarioDefinition {
  code: string;
  name: string;
  description: string;
  /** What to watch for after loading the scenario. */
  expected: string;
  apply: (ctx: EngineContext) => void;
}

interface BaselineOptions {
  t1Level: number;
  t2Level: number;
}

function setPump(p: EquipmentRow | undefined, requested: 'run' | 'stop', mode: 'auto' | 'manual' = 'auto') {
  if (!p) return;
  p.mode = mode;
  p.requested_state = requested;
  p.actual_state = requested === 'run' ? 'running' : 'stopped';
  p.position = requested === 'run' ? 100 : 0;
  p.fault = null;
  p.interlock = null;
  p.under_maintenance = false;
}

function setValve(v: EquipmentRow | undefined, requested: 'open' | 'close', mode: 'auto' | 'manual' = 'auto') {
  if (!v) return;
  v.mode = mode;
  v.requested_state = requested;
  v.actual_state = requested === 'open' ? 'open' : 'closed';
  v.position = requested === 'open' ? 100 : 0;
  v.fault = null;
  v.interlock = null;
  v.under_maintenance = false;
}

function baseline(ctx: EngineContext, opts: BaselineOptions) {
  const eq = equipmentByTag(ctx.equipment);
  const { state } = ctx;
  for (const tag of ['T1', 'T2']) {
    const tank = state.tanks[tag];
    const row = eq.get(tag);
    if (!tank || !row) continue;
    const level = tag === 'T1' ? opts.t1Level : opts.t2Level;
    tank.capacity = Number(row.params.capacity_m3 ?? tank.capacity);
    tank.level = level;
    tank.volume = Math.round(tank.capacity * level) / 100;
    tank.inflow = 0;
    tank.outflow = 0;
    row.position = level;
    row.under_maintenance = false;
    row.fault = null;
    row.interlock = null;
  }
  for (const s of ctx.equipment.filter((e) => e.type === 'sensor')) {
    s.under_maintenance = false;
    s.fault = null;
    s.actual_state = 'ok';
  }
  setPump(eq.get('P1'), 'stop');
  setValve(eq.get('V1'), 'close');
  setPump(eq.get('P2'), 'run');
  setValve(eq.get('V2'), 'open');
  setPump(eq.get('P3'), 'run');
  setValve(eq.get('V3'), 'open');

  state.conditions = {
    ...state.conditions,
    source_available: true,
    demand_factor: 1.0,
    demand_m3h: state.conditions.demand_nominal,
    sensor_faults: [],
    overflow_m3h: 0,
  };
  state.values = {
    ...state.values,
    LT1: opts.t1Level,
    LT2: opts.t2Level,
    FT1: 0,
    FT2: 0,
    FT3: 0,
    PT1: 0,
    PT2: 0.4,
    PT3: 1.0,
    TU1: 0.4,
    CL1: ctx.setpoints.CL_TARGET ?? 1.2,
  };
  state.running = true;
}

export const SCENARIOS: ScenarioDefinition[] = [
  {
    code: 'normal',
    name: 'Normal operation',
    description: 'Both tanks at mid level, all equipment in automatic mode, nominal network demand.',
    expected: 'Levels drift slowly with demand; P1 cycles on the raw tank start/stop setpoints.',
    apply: (ctx) => baseline(ctx, { t1Level: 62, t2Level: 71 }),
  },
  {
    code: 'intake_failure',
    name: 'Intake failure',
    description: 'The river intake is lost. P1 trips on dry-run protection and the raw water tank starts draining.',
    expected: 'INTAKE_UNAVAILABLE and P1_TRIP alarms, T1 level falls, P2 stops in auto at the T1 low-low limit.',
    apply: (ctx) => {
      baseline(ctx, { t1Level: 34, t2Level: 58 });
      const eq = equipmentByTag(ctx.equipment);
      setPump(eq.get('P1'), 'run');
      setValve(eq.get('V1'), 'open');
      ctx.state.conditions.source_available = false;
    },
  },
  {
    code: 'high_demand',
    name: 'High network demand',
    description: 'Evening peak with 180 % of nominal demand. Treated water storage drops faster than the transfer pump can refill it.',
    expected: 'T2 level falls, P1 and P2 run continuously, T2_L alarm within a few simulated minutes.',
    apply: (ctx) => {
      baseline(ctx, { t1Level: 55, t2Level: 38 });
      ctx.state.conditions.demand_factor = 1.8;
    },
  },
  {
    code: 'maintenance_p2',
    name: 'Transfer pump under maintenance',
    description: 'P2 is locked out for maintenance while the treated water tank is already low.',
    expected: 'P2 cannot be started (interlock), T2 keeps draining, P3 stops in auto at the low-low limit.',
    apply: (ctx) => {
      baseline(ctx, { t1Level: 70, t2Level: 33 });
      const eq = equipmentByTag(ctx.equipment);
      const p2 = eq.get('P2');
      if (p2) {
        setPump(p2, 'stop');
        p2.under_maintenance = true;
        p2.actual_state = 'maintenance';
      }
      setValve(eq.get('V2'), 'close');
    },
  },
  {
    code: 'overflow_risk',
    name: 'Raw tank overflow risk',
    description: 'Intake pump left running in manual with the raw water tank almost full and the transfer pump stopped.',
    expected: 'T1_H then T1_HH alarms, then T1_OVERFLOW. Stop P1 or switch it back to auto to recover.',
    apply: (ctx) => {
      baseline(ctx, { t1Level: 93, t2Level: 80 });
      const eq = equipmentByTag(ctx.equipment);
      setPump(eq.get('P1'), 'run', 'manual');
      setValve(eq.get('V1'), 'open', 'manual');
      setPump(eq.get('P2'), 'stop', 'manual');
      setValve(eq.get('V2'), 'close', 'manual');
    },
  },
  {
    code: 'sensor_fault',
    name: 'Level transmitter fault',
    description: 'LT2 freezes at its last value. Automatic control that depends on it is no longer safe.',
    expected: 'LT2_FAULT alarm, P2 and P3 switch to manual and must be operated by hand until the sensor is repaired.',
    apply: (ctx) => {
      baseline(ctx, { t1Level: 60, t2Level: 52 });
      ctx.state.conditions.sensor_faults = ['LT2'];
    },
  },
];

export function findScenario(code: string): ScenarioDefinition | undefined {
  return SCENARIOS.find((s) => s.code === code);
}
