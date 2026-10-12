import { Hono } from 'hono';
import { z } from 'zod';
import { assertRole, requireAuth, SIMULATE_ROLES, type AppEnv } from '../lib/auth.js';
import { audit } from '../lib/audit.js';
import { RATE_LIMITS, rateLimit } from '../lib/ratelimit.js';
import { parseJson, shortCode, uuid } from '../lib/security.js';
import { SCENARIOS } from '../sim/scenarios.js';
import { loadScenario, resetDemoData, runSimulation, setRunning, tick } from '../sim/service.js';

export const simRoute = new Hono<AppEnv>();
simRoute.use('*', requireAuth);

const plantSchema = z.object({ plantId: uuid }).strict();
const advanceSchema = plantSchema.extend({ seconds: z.number().int().min(1).max(4 * 3600) }).strict();
const scenarioSchema = plantSchema.extend({ scenario: shortCode }).strict();
const controlSchema = plantSchema.extend({ running: z.boolean(), speed: z.number().min(0.5).max(60).optional() }).strict();
const resetSchema = z.object({ plantId: uuid.optional() }).strict();

function describeDuration(seconds: number): string {
  if (seconds % 3600 === 0) return `${seconds / 3600} h`;
  if (seconds % 60 === 0) return `${seconds / 60} min`;
  return `${seconds} s`;
}

simRoute.get('/scenarios', (c) => {
  return c.json({ scenarios: SCENARIOS.map(({ apply: _apply, ...rest }) => rest) });
});

/** Called by connected clients every couple of seconds while a process screen is open. */
simRoute.post('/tick', rateLimit(RATE_LIMITS.tick), async (c) => {
  const parsed = await parseJson(c, plantSchema);
  const result = await tick(parsed.plantId);
  if (!result) return c.json({ ticked: false });
  return c.json({
    ticked: true,
    simulatedSeconds: result.simulatedSeconds,
    simTime: result.state.sim_time,
    raised: result.raised.map((a) => a.code),
    cleared: result.cleared,
  });
});

simRoute.post('/advance', rateLimit(RATE_LIMITS.simulation), async (c) => {
  const user = assertRole(c, SIMULATE_ROLES, 'advance the simulation');
  const { plantId, seconds } = await parseJson(c, advanceSchema);
  const result = await runSimulation(plantId, seconds, {
    actor: user.fullName,
    summary: `Simulation advanced by ${describeDuration(seconds)}`,
  });
  await audit(c, { action: 'sim.advance', outcome: 'success', status: 200, details: { plantId, seconds } });
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

simRoute.post('/scenario', rateLimit(RATE_LIMITS.simulation), async (c) => {
  const user = assertRole(c, SIMULATE_ROLES, 'load scenarios');
  const parsed = await parseJson(c, scenarioSchema);
  const result = await loadScenario(parsed.plantId, parsed.scenario, user.fullName);
  await audit(c, { action: 'sim.scenario', outcome: 'success', status: 200, details: { plantId: parsed.plantId, scenario: parsed.scenario } });
  return c.json({ scenario: result.state.scenario, simTime: result.state.sim_time, tanks: result.state.tanks });
});

simRoute.post('/control', rateLimit(RATE_LIMITS.simulation), async (c) => {
  const user = assertRole(c, SIMULATE_ROLES, 'pause or resume the simulation');
  const parsed = await parseJson(c, controlSchema);
  await setRunning(parsed.plantId, parsed.running, parsed.speed, user.fullName);
  await audit(c, { action: 'sim.control', outcome: 'success', status: 200, details: { plantId: parsed.plantId, running: parsed.running, speed: parsed.speed ?? null } });
  return c.json({ ok: true });
});

simRoute.post('/reset', rateLimit(RATE_LIMITS.simulation), async (c) => {
  const user = assertRole(c, SIMULATE_ROLES, 'reset the demo data');
  const parsed = await parseJson(c, resetSchema);
  await resetDemoData(user.fullName, parsed.plantId);
  await audit(c, { action: 'sim.reset', outcome: 'success', status: 200, details: { plantId: parsed.plantId ?? 'all' } });
  return c.json({ ok: true });
});
