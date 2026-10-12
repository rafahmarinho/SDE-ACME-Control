import { Hono } from 'hono';
import { z } from 'zod';
import { OPERATE_ROLES, requireAuth, requireRole, type AppEnv } from '../lib/auth.js';
import { audit } from '../lib/audit.js';
import { conflict, notFound } from '../lib/errors.js';
import { RATE_LIMITS, rateLimit } from '../lib/ratelimit.js';
import { parseJson, shortCode, uuid } from '../lib/security.js';
import { supabaseAdmin } from '../lib/supabase.js';
import { startInterlock } from '../sim/engine.js';
import { insertEvents, loadContext, persistEquipment, runSimulation } from '../sim/service.js';
import type { EngineContext, EquipmentRow, UserRole } from '../sim/types.js';

const commandSchema = z
  .object({
    plantId: uuid,
    equipmentId: uuid.optional(),
    tag: shortCode.optional(),
    type: z.enum(['start', 'stop', 'open', 'close', 'set_mode', 'reset']),
    value: z.union([z.enum(['manual', 'auto']), z.number().finite(), z.boolean()]).optional(),
  })
  .strict()
  .refine((v) => v.equipmentId || v.tag, { message: 'equipmentId or tag is required' });

type CommandType = z.infer<typeof commandSchema>['type'];

const LABELS: Record<CommandType, string> = {
  start: 'Start',
  stop: 'Stop',
  open: 'Open',
  close: 'Close',
  set_mode: 'Mode change',
  reset: 'Reset',
};

/** Returns a rejection reason, or null when the command may be applied. */
export function validateCommand(role: UserRole, eq: EquipmentRow, type: CommandType, value: unknown, ctx: EngineContext): string | null {
  if (!OPERATE_ROLES.includes(role)) return `Role ${role} is not allowed to operate equipment`;
  if (eq.type !== 'pump' && eq.type !== 'valve') return `${eq.tag} does not accept commands`;
  const pumpTypes: CommandType[] = ['start', 'stop', 'reset', 'set_mode'];
  const valveTypes: CommandType[] = ['open', 'close', 'set_mode'];
  if (eq.type === 'pump' && !pumpTypes.includes(type)) return `"${type}" is not a valid pump command`;
  if (eq.type === 'valve' && !valveTypes.includes(type)) return `"${type}" is not a valid valve command`;
  if (eq.under_maintenance) return `${eq.tag} is under maintenance - commands are blocked`;

  if (type === 'set_mode') {
    if (value !== 'manual' && value !== 'auto') return 'Mode must be "manual" or "auto"';
    if (eq.mode === value) return `${eq.tag} is already in ${value} mode`;
    return null;
  }
  if (type === 'reset') {
    if (eq.actual_state !== 'tripped') return `${eq.tag} is not tripped`;
    return null;
  }
  if (eq.mode === 'auto') return `${eq.tag} is in automatic mode - switch it to manual to operate it`;

  if (type === 'start') {
    if (eq.requested_state === 'run') return `${eq.tag} start is already requested`;
    const interlock = startInterlock(eq, ctx);
    if (interlock) return `Interlock: ${interlock}`;
  }
  if (type === 'stop' && eq.requested_state === 'stop' && eq.actual_state === 'stopped') return `${eq.tag} is already stopped`;
  if (type === 'open' && eq.requested_state === 'open') return `${eq.tag} open is already requested`;
  if (type === 'close' && eq.requested_state === 'close') return `${eq.tag} close is already requested`;
  return null;
}

export function applyCommand(eq: EquipmentRow, type: CommandType, value: unknown) {
  switch (type) {
    case 'start':
      eq.requested_state = 'run';
      break;
    case 'stop':
      eq.requested_state = 'stop';
      break;
    case 'open':
      eq.requested_state = 'open';
      break;
    case 'close':
      eq.requested_state = 'close';
      break;
    case 'set_mode':
      eq.mode = value as 'manual' | 'auto';
      break;
    case 'reset':
      eq.actual_state = 'stopped';
      eq.requested_state = 'stop';
      eq.position = 0;
      eq.fault = null;
      eq.interlock = null;
      break;
  }
}

export const commandsRoute = new Hono<AppEnv>();
commandsRoute.use('*', requireAuth);
commandsRoute.use('*', requireRole(OPERATE_ROLES, 'operate equipment'));
commandsRoute.use('*', rateLimit(RATE_LIMITS.commands));

commandsRoute.post('/', async (c) => {
  const user = c.get('user');
  const cmd = await parseJson(c, commandSchema);

  const ctx = await loadContext(cmd.plantId);
  const eq = ctx.equipment.find((e) => (cmd.equipmentId ? e.id === cmd.equipmentId : e.tag === cmd.tag));
  if (!eq) throw notFound('Equipment not found in this plant');

  const reason = validateCommand(user.role, eq, cmd.type, cmd.value, ctx);
  const db = supabaseAdmin();
  const { data: inserted, error } = await db
    .from('commands')
    .insert({
      plant_id: cmd.plantId,
      equipment_id: eq.id,
      equipment_tag: eq.tag,
      user_id: user.id,
      user_name: user.fullName,
      type: cmd.type,
      value: cmd.value ?? null,
      status: reason ? 'rejected' : 'accepted',
      reason,
    })
    .select()
    .single();
  if (error) throw error;

  const label = cmd.type === 'set_mode' ? `Mode change to ${cmd.value}` : LABELS[cmd.type];
  if (reason) {
    await insertEvents(cmd.plantId, [
      { category: 'command', level: 'warning', message: `${label} rejected for ${eq.tag}: ${reason}`, actor: user.fullName, data: { tag: eq.tag, type: cmd.type, command_id: inserted.id } },
    ]);
    await audit(c, { action: `command.${cmd.type}`, outcome: 'rejected', status: 409, details: { plantId: cmd.plantId, tag: eq.tag, reason, commandId: inserted.id } });
    throw conflict(reason, { commandId: inserted.id });
  }

  applyCommand(eq, cmd.type, cmd.value);
  await persistEquipment([eq]);
  await insertEvents(cmd.plantId, [
    { category: 'command', level: 'info', message: `${label} accepted for ${eq.tag} ${eq.name}`, actor: user.fullName, data: { tag: eq.tag, type: cmd.type, command_id: inserted.id } },
  ]);

  // Let the process react immediately so the caller sees the actual state start to move.
  const run = await runSimulation(cmd.plantId, 1, { actor: user.fullName });
  const { data: executed, error: updErr } = await db
    .from('commands')
    .update({ status: 'executed', executed_at: new Date().toISOString() })
    .eq('id', inserted.id)
    .select()
    .single();
  if (updErr) throw updErr;

  await audit(c, { action: `command.${cmd.type}`, outcome: 'success', status: 200, details: { plantId: cmd.plantId, tag: eq.tag, value: cmd.value ?? null, commandId: inserted.id } });
  return c.json({ command: executed, equipment: run.equipment.find((e) => e.id === eq.id) ?? eq });
});
