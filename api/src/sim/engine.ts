/**
 * ACME Control - process simulation engine.
 *
 * Pure, deterministic-enough model of a small water treatment plant:
 *   intake -> P1 -> V1 -> T1 (raw water) -> P2 -> V2 -> treatment -> T2 (treated) -> P3 -> V3 -> network
 *
 * The engine mutates the EngineContext in place for one time step (dt seconds) and returns
 * the alarm conditions and events produced during that step. Persistence lives in service.ts.
 */
import type {
  AlarmCondition,
  EngineContext,
  EquipmentRow,
  SimEvent,
  StepResult,
  TankState,
} from './types.js';

const PUMP_START_SECONDS = 4;
const PUMP_STOP_SECONDS = 3;
/** Running pump trips (dry-run protection) when its source tank goes below this level. */
const TRIP_LEVEL_PCT = 3;
/** A pump may not be started when its source tank is at or below this level. */
const EMPTY_LEVEL_PCT = 5;
const NETWORK_LOW_PRESSURE_BAR = 2.5;

export const MANAGED_ALARM_PREFIXES = ['T1_', 'T2_', 'P1_TRIP', 'P2_TRIP', 'P3_TRIP', 'INTAKE_', 'NET_', 'TU1_', 'CL1_'];

export function isPumpActive(p: EquipmentRow): boolean {
  return p.actual_state === 'running' || p.actual_state === 'starting' || p.actual_state === 'stopping';
}

export function isPumpEngaged(p: EquipmentRow): boolean {
  return p.actual_state === 'running' || p.actual_state === 'starting';
}

function round(v: number, decimals: number): number {
  const f = Math.pow(10, decimals);
  return Math.round(v * f) / f;
}

function noise(amplitude: number): number {
  return (Math.random() * 2 - 1) * amplitude;
}

function clamp(v: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, v));
}

export function equipmentByTag(equipment: EquipmentRow[]): Map<string, EquipmentRow> {
  return new Map(equipment.map((e) => [e.tag, e]));
}

/** Diurnal demand profile: peaks early evening, lowest around 3 am. */
export function diurnalFactor(simTime: Date): number {
  const hour = simTime.getUTCHours() + simTime.getUTCMinutes() / 60;
  return 1 + 0.35 * Math.sin(((hour - 7) / 24) * 2 * Math.PI);
}

/** Evaluate the interlock that would block a start. Returns null when the pump may start. */
export function startInterlock(pump: EquipmentRow, ctx: EngineContext): string | null {
  const eq = equipmentByTag(ctx.equipment);
  const source = pump.params.source as string;
  const sink = pump.params.sink as string;
  if (pump.under_maintenance) return `${pump.tag} is under maintenance`;
  if (pump.actual_state === 'tripped') return `${pump.tag} is tripped - reset required`;
  if (source === 'intake') {
    if (!ctx.state.conditions.source_available) return 'Intake source unavailable';
  } else {
    const tank = ctx.state.tanks[source];
    if (tank && tank.level <= EMPTY_LEVEL_PCT) return `${source} empty (${tank.level.toFixed(1)} %)`;
  }
  if (sink !== 'network') {
    const tank = ctx.state.tanks[sink];
    if (tank && tank.level >= 99.5) return `${sink} full (${tank.level.toFixed(1)} %)`;
  }
  const valve = eq.get(pump.params.valve as string);
  if (valve?.under_maintenance) return `${valve.tag} is under maintenance`;
  return null;
}

function tripPump(p: EquipmentRow, reason: string, events: SimEvent[]) {
  p.actual_state = 'tripped';
  p.requested_state = 'stop';
  p.position = 0;
  p.fault = reason;
  events.push({
    category: 'simulation',
    level: 'error',
    message: `${p.tag} ${p.name} tripped: ${reason}`,
    actor: 'simulation',
    data: { tag: p.tag, reason },
  });
}

function autoControl(ctx: EngineContext, events: SimEvent[]) {
  const eq = equipmentByTag(ctx.equipment);
  const { state, setpoints } = ctx;
  const sp = (key: string, fallback: number) => setpoints[key] ?? fallback;
  const T1 = state.tanks.T1;
  const T2 = state.tanks.T2;
  const faults = new Set(state.conditions.sensor_faults ?? []);
  const t1Params = eq.get('T1')?.params ?? {};
  const t2Params = eq.get('T2')?.params ?? {};

  const request = (pump: EquipmentRow, wanted: 'run' | 'stop', why: string) => {
    if (pump.requested_state !== wanted) {
      pump.requested_state = wanted;
      events.push({
        category: 'control',
        level: 'info',
        message: `Auto control: ${pump.tag} ${wanted === 'run' ? 'start' : 'stop'} requested (${why})`,
        actor: 'auto-control',
        data: { tag: pump.tag, requested: wanted },
      });
    }
  };

  const dependsOn: Record<string, string[]> = { P1: ['LT1'], P2: ['LT1', 'LT2'], P3: ['LT2'] };

  for (const pump of ctx.equipment.filter((e) => e.type === 'pump')) {
    if (pump.mode !== 'auto') continue;
    const faulted = (dependsOn[pump.tag] ?? []).find((s) => faults.has(s));
    if (faulted) {
      pump.mode = 'manual';
      events.push({
        category: 'control',
        level: 'warning',
        message: `${pump.tag} switched to manual: ${faulted} signal fault - automatic control unavailable`,
        actor: 'auto-control',
        data: { tag: pump.tag, sensor: faulted },
      });
      continue;
    }
    if (pump.actual_state === 'tripped' || pump.under_maintenance) continue;

    switch (pump.tag) {
      case 'P1': {
        if (!state.conditions.source_available) {
          request(pump, 'stop', 'intake source unavailable');
        } else if (T1.level < sp('T1_START', 40)) {
          request(pump, 'run', `LT1 ${T1.level.toFixed(1)} % < ${sp('T1_START', 40)} %`);
        } else if (T1.level > sp('T1_STOP', 85)) {
          request(pump, 'stop', `LT1 ${T1.level.toFixed(1)} % > ${sp('T1_STOP', 85)} %`);
        }
        break;
      }
      case 'P2': {
        const t1ll = Number(t1Params.ll ?? 10);
        if (T1.level <= t1ll) {
          request(pump, 'stop', `LT1 ${T1.level.toFixed(1)} % at low-low limit`);
        } else if (T2.level < sp('T2_START', 45)) {
          request(pump, 'run', `LT2 ${T2.level.toFixed(1)} % < ${sp('T2_START', 45)} %`);
        } else if (T2.level > sp('T2_STOP', 90)) {
          request(pump, 'stop', `LT2 ${T2.level.toFixed(1)} % > ${sp('T2_STOP', 90)} %`);
        }
        break;
      }
      case 'P3': {
        const t2ll = Number(t2Params.ll ?? 15);
        if (T2.level <= t2ll) {
          request(pump, 'stop', `LT2 ${T2.level.toFixed(1)} % at low-low limit`);
        } else if (T2.level > t2ll + 5) {
          request(pump, 'run', 'network demand');
        }
        break;
      }
    }
  }

  // Valves in auto follow their pump
  for (const valve of ctx.equipment.filter((e) => e.type === 'valve')) {
    if (valve.mode !== 'auto') continue;
    const pump = eq.get(valve.params.pump as string);
    if (!pump) continue;
    const wanted = pump.requested_state === 'run' || isPumpEngaged(pump) ? 'open' : 'close';
    valve.requested_state = wanted;
  }
}

function updateValve(v: EquipmentRow, dt: number, events: SimEvent[]) {
  if (v.under_maintenance) {
    v.actual_state = 'maintenance';
    return;
  }
  const target = v.requested_state === 'open' ? 100 : 0;
  const travel = Number(v.params.travel_time_s ?? 12);
  const rate = (100 / Math.max(1, travel)) * dt;
  const before = v.actual_state;
  if (Math.abs(v.position - target) < 1e-6) {
    v.actual_state = target === 100 ? 'open' : 'closed';
  } else if (v.position < target) {
    v.position = Math.min(target, v.position + rate);
    v.actual_state = v.position >= target ? 'open' : 'opening';
  } else {
    v.position = Math.max(target, v.position - rate);
    v.actual_state = v.position <= target ? 'closed' : 'closing';
  }
  v.position = round(v.position, 1);
  if (before !== v.actual_state && (v.actual_state === 'open' || v.actual_state === 'closed')) {
    events.push({
      category: 'simulation',
      level: 'info',
      message: `${v.tag} ${v.name} ${v.actual_state}`,
      actor: 'simulation',
      data: { tag: v.tag, state: v.actual_state },
    });
  }
}

function updatePump(p: EquipmentRow, ctx: EngineContext, dt: number, events: SimEvent[]) {
  const source = p.params.source as string;
  const wasEngaged = isPumpEngaged(p);
  p.interlock = null;

  if (p.under_maintenance) {
    if (p.actual_state !== 'maintenance') {
      p.actual_state = 'maintenance';
      p.position = 0;
    }
    return;
  }
  if (p.actual_state === 'maintenance') {
    p.actual_state = 'stopped';
    p.position = 0;
  }
  if (p.actual_state === 'tripped') {
    p.position = 0;
    p.interlock = 'Reset required';
    return;
  }

  const sourceTank = source === 'intake' ? undefined : ctx.state.tanks[source];
  const sourceEmpty = source === 'intake' ? !ctx.state.conditions.source_available : (sourceTank?.level ?? 100) <= TRIP_LEVEL_PCT;
  if (wasEngaged && sourceEmpty) {
    tripPump(
      p,
      source === 'intake' ? 'Dry-run protection - intake source unavailable' : `Dry-run protection - ${source} empty`,
      events,
    );
    return;
  }

  const wantsRun = p.requested_state === 'run';
  if (wantsRun && !wasEngaged) {
    p.interlock = startInterlock(p, ctx);
  }

  switch (p.actual_state) {
    case 'stopped':
      if (wantsRun && !p.interlock) {
        p.actual_state = 'starting';
        p.position = Math.min(100, (100 / PUMP_START_SECONDS) * dt);
        p.starts_count += 1;
        events.push({ category: 'simulation', level: 'info', message: `${p.tag} ${p.name} starting`, actor: 'simulation', data: { tag: p.tag } });
      }
      break;
    case 'starting':
      if (!wantsRun) {
        p.actual_state = 'stopping';
      } else {
        p.position = Math.min(100, p.position + (100 / PUMP_START_SECONDS) * dt);
        if (p.position >= 100) {
          p.actual_state = 'running';
          events.push({ category: 'simulation', level: 'info', message: `${p.tag} ${p.name} running`, actor: 'simulation', data: { tag: p.tag } });
        }
      }
      break;
    case 'running':
      if (!wantsRun) {
        p.actual_state = 'stopping';
        events.push({ category: 'simulation', level: 'info', message: `${p.tag} ${p.name} stopping`, actor: 'simulation', data: { tag: p.tag } });
      }
      break;
    case 'stopping':
      p.position = Math.max(0, p.position - (100 / PUMP_STOP_SECONDS) * dt);
      if (p.position <= 0) {
        p.actual_state = 'stopped';
        p.position = 0;
        events.push({ category: 'simulation', level: 'info', message: `${p.tag} ${p.name} stopped`, actor: 'simulation', data: { tag: p.tag } });
      }
      break;
    default:
      p.actual_state = 'stopped';
      p.position = 0;
  }
  p.position = round(p.position, 1);
  if (isPumpActive(p)) {
    p.runtime_hours = round(p.runtime_hours + dt / 3600, 4);
  }
}

function pumpFlow(p: EquipmentRow, eq: Map<string, EquipmentRow>, ctx: EngineContext): number {
  if (!isPumpActive(p)) return 0;
  const valve = eq.get(p.params.valve as string);
  const valvePos = valve ? valve.position / 100 : 1;
  const rated = Number(p.params.rated_flow_m3h ?? 100);
  const source = p.params.source as string;
  if (source === 'intake' && !ctx.state.conditions.source_available) return 0;
  return rated * (p.position / 100) * valvePos;
}

function evaluateAlarms(ctx: EngineContext, overflow: number): AlarmCondition[] {
  const eq = equipmentByTag(ctx.equipment);
  const { state, setpoints } = ctx;
  const alarms: AlarmCondition[] = [];
  const faults = new Set(state.conditions.sensor_faults ?? []);

  const tankAlarms = (tag: string) => {
    const t = state.tanks[tag];
    const e = eq.get(tag);
    if (!t || !e) return;
    const p = e.params;
    const name = e.name;
    const lvl = t.level;
    alarms.push({ code: `${tag}_HH`, tag, severity: 'critical', message: `${name} level high-high (${lvl.toFixed(1)} %)`, active: lvl >= Number(p.hh ?? 95), value: lvl });
    alarms.push({ code: `${tag}_H`, tag, severity: 'medium', message: `${name} level high (${lvl.toFixed(1)} %)`, active: lvl >= Number(p.h ?? 88), value: lvl });
    alarms.push({ code: `${tag}_L`, tag, severity: 'medium', message: `${name} level low (${lvl.toFixed(1)} %)`, active: lvl <= Number(p.l ?? 25), value: lvl });
    alarms.push({ code: `${tag}_LL`, tag, severity: 'critical', message: `${name} level low-low (${lvl.toFixed(1)} %)`, active: lvl <= Number(p.ll ?? 10), value: lvl });
  };
  tankAlarms('T1');
  tankAlarms('T2');

  alarms.push({ code: 'T1_OVERFLOW', tag: 'T1', severity: 'critical', message: `Raw water tank overflowing (${overflow.toFixed(1)} m³/h)`, active: overflow > 0.5, value: overflow });

  for (const p of ctx.equipment.filter((e) => e.type === 'pump')) {
    alarms.push({
      code: `${p.tag}_TRIP`,
      tag: p.tag,
      severity: 'high',
      message: `${p.tag} ${p.name} tripped - ${p.fault ?? 'protection'}`,
      active: p.actual_state === 'tripped',
    });
  }

  alarms.push({ code: 'INTAKE_UNAVAILABLE', tag: 'P1', severity: 'high', message: 'Raw water intake unavailable - no source flow', active: !state.conditions.source_available });

  const pt3 = state.values.PT3 ?? 0;
  const p3 = eq.get('P3');
  alarms.push({
    code: 'NET_PRESSURE_LOW',
    tag: 'PT3',
    severity: 'high',
    message: `Network pressure low (${pt3.toFixed(2)} bar)`,
    active: pt3 < NETWORK_LOW_PRESSURE_BAR && (p3 ? p3.requested_state === 'run' : true),
    value: pt3,
  });

  const tu = state.values.TU1 ?? 0;
  const turbMax = setpoints.TURB_MAX ?? 1.0;
  alarms.push({ code: 'TU1_H', tag: 'TU1', severity: 'medium', message: `Treated water turbidity high (${tu.toFixed(2)} NTU > ${turbMax} NTU)`, active: tu > turbMax, value: tu });

  const cl = state.values.CL1 ?? 0;
  const clTarget = setpoints.CL_TARGET ?? 1.2;
  alarms.push({ code: 'CL1_L', tag: 'CL1', severity: 'medium', message: `Chlorine residual low (${cl.toFixed(2)} mg/L)`, active: cl < clTarget - 0.4, value: cl });
  alarms.push({ code: 'CL1_H', tag: 'CL1', severity: 'medium', message: `Chlorine residual high (${cl.toFixed(2)} mg/L)`, active: cl > clTarget + 0.8, value: cl });

  for (const s of ctx.equipment.filter((e) => e.type === 'sensor')) {
    alarms.push({ code: `${s.tag}_FAULT`, tag: s.tag, severity: 'medium', message: `${s.tag} ${s.name} signal fault - value frozen`, active: faults.has(s.tag) });
  }
  return alarms;
}

/**
 * Advance the plant by dt seconds.
 */
export function stepSimulation(ctx: EngineContext, dt: number): StepResult {
  const events: SimEvent[] = [];
  const eq = equipmentByTag(ctx.equipment);
  const { state, setpoints } = ctx;
  const simTime = new Date(new Date(state.sim_time).getTime() + dt * 1000);
  state.sim_time = simTime.toISOString();
  const cond = state.conditions;
  const faults = new Set(cond.sensor_faults ?? []);

  const T1 = state.tanks.T1;
  const T2 = state.tanks.T2;
  if (!T1 || !T2) {
    throw new Error('Process state is missing tank definitions');
  }

  cond.demand_m3h = round(Math.max(0, cond.demand_nominal * cond.demand_factor * diurnalFactor(simTime)), 1);

  autoControl(ctx, events);

  for (const v of ctx.equipment.filter((e) => e.type === 'valve')) updateValve(v, dt, events);
  for (const p of ctx.equipment.filter((e) => e.type === 'pump')) updatePump(p, ctx, dt, events);

  const P1 = eq.get('P1');
  const P2 = eq.get('P2');
  const P3 = eq.get('P3');
  const V1 = eq.get('V1');
  const V2 = eq.get('V2');
  const V3 = eq.get('V3');
  const hours = dt / 3600;

  // Flows (m³/h)
  let f1 = P1 ? pumpFlow(P1, eq, ctx) : 0;
  let f2 = P2 ? pumpFlow(P2, eq, ctx) : 0;
  let f3 = P3 ? Math.min(pumpFlow(P3, eq, ctx), cond.demand_m3h) : 0;

  // Limit by available volume
  f2 = Math.min(f2, T1.volume / Math.max(hours, 1e-9));
  f3 = Math.min(f3, T2.volume / Math.max(hours, 1e-9));

  // Tank balances
  let overflow = 0;
  let t1Volume = T1.volume + (f1 - f2) * hours;
  if (t1Volume > T1.capacity) {
    overflow = (t1Volume - T1.capacity) / Math.max(hours, 1e-9);
    t1Volume = T1.capacity;
  }
  T1.volume = round(clamp(t1Volume, 0, T1.capacity), 3);
  T1.level = round((T1.volume / T1.capacity) * 100, 2);
  T1.inflow = round(f1, 1);
  T1.outflow = round(f2, 1);

  let t2Volume = T2.volume + (f2 - f3) * hours;
  if (t2Volume > T2.capacity) {
    // transfer pump pushing into a full tank: flow is throttled by the full tank
    const excess = (t2Volume - T2.capacity) / Math.max(hours, 1e-9);
    f2 = Math.max(0, f2 - excess);
    t2Volume = T2.capacity;
  }
  T2.volume = round(clamp(t2Volume, 0, T2.capacity), 3);
  T2.level = round((T2.volume / T2.capacity) * 100, 2);
  T2.inflow = round(f2, 1);
  T2.outflow = round(f3, 1);
  cond.overflow_m3h = round(overflow, 1);

  // Pressures (bar)
  const p1Rated = Number(P1?.params.rated_pressure_bar ?? 3.2);
  const p2Rated = Number(P2?.params.rated_pressure_bar ?? 2.8);
  const netTarget = setpoints.NET_PRESSURE ?? 4.0;
  const pt1 = P1 && isPumpActive(P1) ? p1Rated * (0.85 + 0.3 * (1 - (V1?.position ?? 100) / 100)) * (P1.position / 100) : 0;
  const pt2 = (P2 && isPumpActive(P2) ? p2Rated * (0.85 + 0.3 * (1 - (V2?.position ?? 100) / 100)) * (P2.position / 100) : 0) + 0.1 + (T1.level / 100) * 0.5;
  const staticHead = 0.3 + (T2.level / 100) * 0.7;
  const p3Rated = Number(P3?.params.rated_flow_m3h ?? 100);
  const pt3 = P3 && isPumpActive(P3)
    ? staticHead + (netTarget - staticHead) * (0.95 + 0.1 * (1 - Math.min(1, f3 / p3Rated))) * (P3.position / 100) * ((V3?.position ?? 100) / 100)
    : staticHead;

  // Water quality
  const prevTu = state.values.TU1 ?? 0.4;
  let tuTarget = P2 && isPumpActive(P2) ? 0.35 + 0.1 * (f2 / Math.max(1, Number(P2.params.rated_flow_m3h ?? 100))) : 0.3;
  if (!cond.source_available || T1.level < 15) tuTarget += 0.45;
  if (cond.demand_factor > 1.4) tuTarget += 0.2;
  const tu = clamp(prevTu + (tuTarget - prevTu) * Math.min(1, dt / 120) + noise(0.015), 0, 5);

  const prevCl = state.values.CL1 ?? 1.2;
  const clTarget = P2 && isPumpActive(P2) ? (setpoints.CL_TARGET ?? 1.2) : 0.6;
  const cl = clamp(prevCl + (clTarget - prevCl) * Math.min(1, dt / 300) + noise(0.01), 0, 4);

  const prev = state.values;
  const next: Record<string, number> = {
    LT1: round(T1.level, 1),
    LT2: round(T2.level, 1),
    FT1: round(f1 + (f1 > 0 ? noise(0.4) : 0), 1),
    FT2: round(f2 + (f2 > 0 ? noise(0.4) : 0), 1),
    FT3: round(f3 + (f3 > 0 ? noise(0.4) : 0), 1),
    PT1: round(Math.max(0, pt1 + (pt1 > 0 ? noise(0.02) : 0)), 2),
    PT2: round(Math.max(0, pt2 + noise(0.02)), 2),
    PT3: round(Math.max(0, pt3 + noise(0.03)), 2),
    TU1: round(tu, 2),
    CL1: round(cl, 2),
  };
  // Faulted sensors keep their last value
  for (const tag of faults) {
    if (prev[tag] !== undefined) next[tag] = prev[tag];
  }
  state.values = next;

  // Tank equipment rows mirror the level for the equipment list
  const t1Row = eq.get('T1');
  const t2Row = eq.get('T2');
  if (t1Row) t1Row.position = round(T1.level, 1);
  if (t2Row) t2Row.position = round(T2.level, 1);

  const alarms = evaluateAlarms(ctx, overflow);
  return { alarms, events };
}
