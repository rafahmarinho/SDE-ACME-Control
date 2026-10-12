import { Hono } from 'hono';
import { z } from 'zod';
import { assertRole, requireAuth, SIMULATE_ROLES, type AppEnv } from '../lib/auth.js';
import { badRequest } from '../lib/errors.js';
import { SCENARIOS } from '../sim/scenarios.js';
import { loadScenario, resetDemoData, runSimulation, setRunning, tick } from '../sim/service.js';

export const simRoute = new Hono<AppEnv>();
simRoute.use('*', requireAuth);

const plantSchema = z.object({ plantId: z.string().uuid() });
const advanceSchema = plantSchema.extend({ seconds: z.number().int().min(1).max(4 * 3600) });
const scenarioSchema = plantSchema.extend({ scenario: z.string().min(1) });
const controlSchema = plantSchema.extend({ running: z.boolean(), speed: z.number().min(0.5).max(60).optional() });
const resetSchema = z.object({ plantId: z.string().uuid().optional() });

function describeDuration(seconds: number): string {
  if (seconds % 3600 === 0) return `${seconds / 3600} h`;
  if (seconds % 60 === 0) return `${seconds / 60} min`;
  return `${seconds} s`;
}

simRoute.get('/scenarios', (c) => {
  return c.json({ scenarios: SCENARIOS.map(({ apply: _apply, ...rest }) => rest) });
});

/** Called by connected clients every couple of seconds while a process screen is open. */
simRoute.post('/tick', async (c) => {
  const parsed = plantSchema.safeParse(await c.req.json().catch(() => ({})));
  if (!parsed.success) throw badRequest('plantId is required');
  const result = await tick(parsed.data.plantId);
  if (!result) return c.json({ ticked: false });
  return c.json({
    ticked: true,
    simulatedSeconds: result.simulatedSeconds,
    simTime: result.state.sim_time,
    raised: result.raised.map((a) => a.code),
    cleared: result.cleared,
  });
});

simRoute.post('/advance', async (c) => {
  const user = assertRole(c, SIMULATE_ROLES, 'advance the simulation');
  const parsed = advanceSchema.safeParse(await c.req.json().catch(() => ({})));
  if (!parsed.success) throw badRequest('Invalid payload', parsed.error.flatten());
  const { plantId, seconds } = parsed.data;
  const result = await runSimulation(plantId, seconds, {
    actor: user.fullName,
    summary: `Simulation advanced by ${describeDuration(seconds)}`,
  });
  return c.json({
    simulatedSeconds: result.simulatedSeconds,
    steps: result.steps,
    simTime: result.state.sim_time,
    raised: result.raised.map((a) => ({ code: a.code, message: a.message, severity: a.severity })),
    cleared: result.cleared,
    events: result.eventCount,
    tanks: result.state.tanks,
  });
});

simRoute.post('/scenario', async (c) => {
  const user = assertRole(c, SIMULATE_ROLES, 'load scenarios');
  const parsed = scenarioSchema.safeParse(await c.req.json().catch(() => ({})));
  if (!parsed.success) throw badRequest('Invalid payload', parsed.error.flatten());
  const result = await loadScenario(parsed.data.plantId, parsed.data.scenario, user.fullName);
  return c.json({ scenario: result.state.scenario, simTime: result.state.sim_time, tanks: result.state.tanks });
});

simRoute.post('/control', async (c) => {
  const user = assertRole(c, SIMULATE_ROLES, 'pause or resume the simulation');
  const parsed = controlSchema.safeParse(await c.req.json().catch(() => ({})));
  if (!parsed.success) throw badRequest('Invalid payload', parsed.error.flatten());
  await setRunning(parsed.data.plantId, parsed.data.running, parsed.data.speed, user.fullName);
  return c.json({ ok: true });
});

simRoute.post('/reset', async (c) => {
  const user = assertRole(c, SIMULATE_ROLES, 'reset the demo data');
  const parsed = resetSchema.safeParse(await c.req.json().catch(() => ({})));
  if (!parsed.success) throw badRequest('Invalid payload', parsed.error.flatten());
  await resetDemoData(user.fullName, parsed.data.plantId);
  return c.json({ ok: true });
});
