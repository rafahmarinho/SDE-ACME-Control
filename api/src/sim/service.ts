/**
 * Simulation service: loads a plant from Supabase, runs the engine, persists the
 * result (equipment, process state, trend samples, alarms, events).
 */
import { supabaseAdmin } from '../lib/supabase.js';
import { badRequest, notFound } from '../lib/errors.js';
import { historianJournal, onCallSms } from '../lib/integrations.js';
import { equipmentByTag, stepSimulation } from './engine.js';
import { findScenario } from './scenarios.js';
import {
  TREND_TAGS,
  type AlarmCondition,
  type EngineContext,
  type EquipmentRow,
  type ProcessStateRow,
  type SimEvent,
} from './types.js';

const TREND_INTERVAL_SECONDS = 60;
const MAX_STEP_SECONDS = 5;

export interface TrendRow {
  plant_id: string;
  tag: string;
  ts: string;
  value: number;
}

export interface AdvanceResult {
  alarms: AlarmCondition[];
  events: SimEvent[];
  trends: TrendRow[];
  steps: number;
}

export interface RunResult {
  simulatedSeconds: number;
  steps: number;
  raised: AlarmCondition[];
  cleared: string[];
  eventCount: number;
  state: ProcessStateRow;
  equipment: EquipmentRow[];
}

function num(v: unknown, fallback = 0): number {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : fallback;
}

export function normalizeEquipment(r: any): EquipmentRow {
  return {
    id: r.id,
    plant_id: r.plant_id,
    tag: r.tag,
    name: r.name,
    type: r.type,
    area: r.area ?? null,
    mode: r.mode,
    requested_state: r.requested_state,
    actual_state: r.actual_state,
    position: num(r.position),
    under_maintenance: Boolean(r.under_maintenance),
    fault: r.fault ?? null,
    interlock: r.interlock ?? null,
    runtime_hours: num(r.runtime_hours),
    starts_count: num(r.starts_count),
    params: r.params ?? {},
    sort_order: num(r.sort_order),
  };
}

export function normalizeState(r: any): ProcessStateRow {
  const tanks: ProcessStateRow['tanks'] = {};
  for (const [tag, t] of Object.entries<any>(r.tanks ?? {})) {
    tanks[tag] = {
      level: num(t.level),
      volume: num(t.volume),
      capacity: num(t.capacity, 1),
      inflow: num(t.inflow),
      outflow: num(t.outflow),
    };
  }
  const values: Record<string, number> = {};
  for (const [tag, v] of Object.entries<any>(r.values ?? {})) values[tag] = num(v);
  const c = r.conditions ?? {};
  return {
    plant_id: r.plant_id,
    scenario: r.scenario ?? 'normal',
    sim_time: r.sim_time ?? new Date().toISOString(),
    last_tick_at: r.last_tick_at ?? new Date().toISOString(),
    speed: num(r.speed, 1),
    running: r.running !== false,
    values,
    tanks,
    conditions: {
      source_available: c.source_available !== false,
      demand_factor: num(c.demand_factor, 1),
      demand_nominal: num(c.demand_nominal, 100),
      demand_m3h: num(c.demand_m3h, 100),
      sensor_faults: Array.isArray(c.sensor_faults) ? c.sensor_faults : [],
      overflow_m3h: num(c.overflow_m3h),
      last_trend_at: c.last_trend_at,
    },
  };
}

export async function loadContext(plantId: string): Promise<EngineContext> {
  const db = supabaseAdmin();
  const [eqRes, spRes, stRes] = await Promise.all([
    db.from('equipment').select('*').eq('plant_id', plantId).order('sort_order'),
    db.from('setpoints').select('key, value').eq('plant_id', plantId),
    db.from('process_state').select('*').eq('plant_id', plantId).maybeSingle(),
  ]);
  if (eqRes.error) throw eqRes.error;
  if (spRes.error) throw spRes.error;
  if (stRes.error) throw stRes.error;
  if (!stRes.data) throw notFound('Plant has no process state. Load the demo data first.');

  const equipment = (eqRes.data ?? []).map(normalizeEquipment);
  if (!equipment.length) throw notFound('Plant has no equipment. Load the demo data first.');
  const setpoints = Object.fromEntries((spRes.data ?? []).map((r: any) => [r.key, num(r.value)]));
  return { equipment, setpoints, state: normalizeState(stRes.data) };
}

/** Run the engine for `seconds` of simulated time in small sub-steps. Pure, no persistence. */
export function advance(ctx: EngineContext, seconds: number): AdvanceResult {
  const events: SimEvent[] = [];
  const trends: TrendRow[] = [];
  let alarms: AlarmCondition[] = [];
  let remaining = Math.max(0, seconds);
  let steps = 0;
  let lastTrend = ctx.state.conditions.last_trend_at ? new Date(ctx.state.conditions.last_trend_at).getTime() : 0;

  while (remaining > 1e-6) {
    const dt = Math.min(MAX_STEP_SECONDS, remaining);
    const result = stepSimulation(ctx, dt);
    alarms = result.alarms;
    events.push(...result.events);
    remaining -= dt;
    steps += 1;

    const simMs = new Date(ctx.state.sim_time).getTime();
    if (simMs - lastTrend >= TREND_INTERVAL_SECONDS * 1000) {
      lastTrend = simMs;
      for (const tag of TREND_TAGS) {
        const v = ctx.state.values[tag];
        if (v !== undefined) trends.push({ plant_id: ctx.state.plant_id, tag, ts: ctx.state.sim_time, value: v });
      }
    }
  }
  if (steps > 0) ctx.state.conditions.last_trend_at = new Date(lastTrend || new Date(ctx.state.sim_time).getTime()).toISOString();
  return { alarms, events, trends, steps };
}

export function snapshotEquipment(equipment: EquipmentRow[]): Map<string, string> {
  return new Map(equipment.map((e) => [e.id, JSON.stringify(e)]));
}

export async function persistEquipment(equipment: EquipmentRow[], before?: Map<string, string>) {
  const db = supabaseAdmin();
  const changed = equipment.filter((e) => !before || before.get(e.id) !== JSON.stringify(e));
  await Promise.all(
    changed.map((e) =>
      db
        .from('equipment')
        .update({
          mode: e.mode,
          requested_state: e.requested_state,
          actual_state: e.actual_state,
          position: e.position,
          under_maintenance: e.under_maintenance,
          fault: e.fault,
          interlock: e.interlock,
          runtime_hours: e.runtime_hours,
          starts_count: e.starts_count,
        })
        .eq('id', e.id)
        .then(({ error }) => {
          if (error) throw error;
        }),
    ),
  );
  return changed.length;
}

export async function persistState(state: ProcessStateRow) {
  const db = supabaseAdmin();
  const { error } = await db
    .from('process_state')
    .update({
      scenario: state.scenario,
      sim_time: state.sim_time,
      speed: state.speed,
      running: state.running,
      values: state.values,
      tanks: state.tanks,
      conditions: state.conditions,
    })
    .eq('plant_id', state.plant_id);
  if (error) throw error;
}

export async function insertEvents(plantId: string, events: SimEvent[], ts?: string, maxEvents = 40) {
  if (!events.length) return 0;
  const db = supabaseAdmin();
  let rows = events;
  if (rows.length > maxEvents) {
    const dropped = rows.length - maxEvents;
    rows = [
      ...rows.slice(0, maxEvents),
      { category: 'simulation', level: 'info', message: `... and ${dropped} more events during this run`, actor: 'simulation' },
    ];
  }
  const { error } = await db.from('events').insert(
    rows.map((e) => ({
      plant_id: plantId,
      ts: ts ?? new Date().toISOString(),
      category: e.category,
      level: e.level,
      message: e.message,
      actor: e.actor,
      data: e.data ?? {},
    })),
  );
  if (error) throw error;
  return rows.length;
}

export async function reconcileAlarms(plantId: string, ctx: EngineContext, conditions: AlarmCondition[]) {
  const db = supabaseAdmin();
  const { data: open, error } = await db.from('alarms').select('id, code, state').eq('plant_id', plantId).neq('state', 'cleared');
  if (error) throw error;
  const openByCode = new Map((open ?? []).map((a: any) => [a.code as string, a]));
  const eq = equipmentByTag(ctx.equipment);
  const raised: AlarmCondition[] = [];
  const clearedIds: string[] = [];
  const clearedCodes: string[] = [];

  for (const cnd of conditions) {
    const existing = openByCode.get(cnd.code);
    if (cnd.active && !existing) raised.push(cnd);
    if (!cnd.active && existing) {
      clearedIds.push(existing.id);
      clearedCodes.push(cnd.code);
    }
  }

  const simTime = ctx.state.sim_time;
  if (raised.length) {
    const { error: insErr } = await db.from('alarms').insert(
      raised.map((a) => ({
        plant_id: plantId,
        equipment_id: eq.get(a.tag)?.id ?? null,
        code: a.code,
        tag: a.tag,
        severity: a.severity,
        message: a.message,
        state: 'active',
        value: a.value ?? null,
        raised_at: simTime,
      })),
    );
    // 23505 = another tick raised the same alarm concurrently; safe to ignore
    if (insErr && insErr.code !== '23505') throw insErr;
  }
  if (clearedIds.length) {
    const { error: updErr } = await db.from('alarms').update({ state: 'cleared', cleared_at: simTime }).in('id', clearedIds);
    if (updErr) throw updErr;
  }
  return { raised, cleared: clearedCodes };
}

export interface RunOptions {
  actor: string;
  /** Write a summary event for the run (used by "advance" from the simulation page). */
  summary?: string;
}

/** Load, advance, persist. Used by ticks, advance and after commands. */
export async function runSimulation(plantId: string, seconds: number, opts: RunOptions): Promise<RunResult> {
  const ctx = await loadContext(plantId);
  if (!ctx.state.running) {
    return { simulatedSeconds: 0, steps: 0, raised: [], cleared: [], eventCount: 0, state: ctx.state, equipment: ctx.equipment };
  }
  const before = snapshotEquipment(ctx.equipment);
  const result = advance(ctx, seconds);
  return finishRun(plantId, ctx, before, result, seconds, opts);
}

export async function finishRun(
  plantId: string,
  ctx: EngineContext,
  before: Map<string, string> | undefined,
  result: AdvanceResult,
  seconds: number,
  opts: RunOptions,
): Promise<RunResult> {
  const db = supabaseAdmin();
  await Promise.all([persistEquipment(ctx.equipment, before), persistState(ctx.state)]);

  if (result.trends.length) {
    const { error } = await db.from('trend_samples').insert(result.trends);
    if (error) throw error;
  }

  const { raised, cleared } = await reconcileAlarms(plantId, ctx, result.alarms);
  const events: SimEvent[] = [];
  if (opts.summary) {
    events.push({ category: 'simulation', level: 'info', message: opts.summary, actor: opts.actor });
  }
  events.push(...result.events);
  for (const a of raised) {
    events.push({ category: 'alarm', level: a.severity === 'critical' || a.severity === 'high' ? 'error' : 'warning', message: `Alarm raised: ${a.message}`, actor: 'simulation', data: { code: a.code, severity: a.severity } });
    if (a.severity === 'critical' || a.severity === 'high') events.push(onCallSms(a));
  }
  for (const code of cleared) {
    events.push({ category: 'alarm', level: 'info', message: `Alarm ${code} cleared`, actor: 'simulation', data: { code } });
  }
  if (result.trends.length >= 50) events.push(historianJournal(result.trends.length, ctx.state.sim_time));

  const eventCount = await insertEvents(plantId, events, ctx.state.sim_time);
  return { simulatedSeconds: seconds, steps: result.steps, raised, cleared, eventCount, state: ctx.state, equipment: ctx.equipment };
}

/** Tick driven by connected clients. Returns null when another client already ticked. */
export async function tick(plantId: string): Promise<RunResult | null> {
  const db = supabaseAdmin();
  const { data, error } = await db.rpc('claim_tick', { p_plant_id: plantId, p_min_interval_ms: 800 });
  if (error) throw error;
  if (data === null || data === undefined) return null;
  const elapsed = Math.min(Number(data), 30);
  const ctx = await loadContext(plantId);
  if (!ctx.state.running) return null;
  const simSeconds = elapsed * ctx.state.speed;
  const before = snapshotEquipment(ctx.equipment);
  const result = advance(ctx, simSeconds);
  return finishRun(plantId, ctx, before, result, simSeconds, { actor: 'simulation' });
}

export async function loadScenario(plantId: string, code: string, actor: string): Promise<RunResult> {
  const scenario = findScenario(code);
  if (!scenario) throw badRequest(`Unknown scenario "${code}"`);
  const ctx = await loadContext(plantId);
  const db = supabaseAdmin();

  scenario.apply(ctx);
  ctx.state.scenario = scenario.code;
  ctx.state.sim_time = new Date().toISOString();
  ctx.state.conditions.last_trend_at = undefined;

  // Scenario changes invalidate the open process alarms; they are re-evaluated on the first step.
  await db.from('alarms').update({ state: 'cleared', cleared_at: new Date().toISOString() }).eq('plant_id', plantId).neq('state', 'cleared');
  await db.from('process_state').update({ last_tick_at: new Date().toISOString() }).eq('plant_id', plantId);

  const result = advance(ctx, 1);
  return finishRun(plantId, ctx, undefined, result, 1, {
    actor,
    summary: `Scenario loaded: ${scenario.name}`,
  });
}

export async function setRunning(plantId: string, running: boolean, speed: number | undefined, actor: string) {
  const db = supabaseAdmin();
  const patch: Record<string, unknown> = { running, last_tick_at: new Date().toISOString() };
  if (speed !== undefined) patch.speed = speed;
  const { error } = await db.from('process_state').update(patch).eq('plant_id', plantId);
  if (error) throw error;
  await insertEvents(plantId, [
    {
      category: 'simulation',
      level: 'info',
      message: running ? `Simulation resumed${speed ? ` at ${speed}x` : ''}` : 'Simulation paused',
      actor,
      data: { running, speed },
    },
  ]);
}

export async function resetDemoData(actor: string, plantId?: string) {
  const db = supabaseAdmin();
  const { error } = await db.rpc('seed_demo_data');
  if (error) throw error;
  const { data: plants } = await db.from('plants').select('id');
  for (const p of plants ?? []) {
    if (plantId && p.id !== plantId) continue;
    await insertEvents(p.id, [{ category: 'system', level: 'warning', message: 'Demo data reset to defaults', actor }]);
  }
}
