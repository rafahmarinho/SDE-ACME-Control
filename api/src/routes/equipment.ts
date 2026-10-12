import { Hono } from 'hono';
import { z } from 'zod';
import { assertRole, MAINTAIN_ROLES, requireAuth, type AppEnv } from '../lib/auth.js';
import { badRequest, conflict, notFound } from '../lib/errors.js';
import { cmmsSync } from '../lib/integrations.js';
import { supabaseAdmin } from '../lib/supabase.js';
import { isPumpEngaged } from '../sim/engine.js';
import { insertEvents, normalizeEquipment, persistEquipment } from '../sim/service.js';

export const equipmentRoute = new Hono<AppEnv>();
equipmentRoute.use('*', requireAuth);

const maintenanceSchema = z.object({
  underMaintenance: z.boolean(),
  note: z.string().trim().max(500).optional(),
});

/** Lock out / release equipment for maintenance. */
equipmentRoute.post('/:id/maintenance', async (c) => {
  const user = assertRole(c, MAINTAIN_ROLES, 'change the maintenance status of equipment');
  const parsed = maintenanceSchema.safeParse(await c.req.json().catch(() => ({})));
  if (!parsed.success) throw badRequest('Invalid payload', parsed.error.flatten());
  const id = c.req.param('id');
  const db = supabaseAdmin();

  const { data: row, error } = await db.from('equipment').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  if (!row) throw notFound('Equipment not found');
  const eq = normalizeEquipment(row);
  const { underMaintenance, note } = parsed.data;

  if (eq.under_maintenance === underMaintenance) {
    throw conflict(underMaintenance ? `${eq.tag} is already under maintenance` : `${eq.tag} is not under maintenance`);
  }
  if (underMaintenance && eq.type === 'pump' && isPumpEngaged(eq)) {
    throw conflict(`Stop ${eq.tag} before placing it under maintenance`);
  }

  eq.under_maintenance = underMaintenance;
  if (underMaintenance) {
    if (eq.type === 'pump') {
      eq.requested_state = 'stop';
      eq.actual_state = 'maintenance';
      eq.position = 0;
    } else if (eq.type === 'valve') {
      eq.actual_state = 'maintenance';
    } else {
      eq.actual_state = 'maintenance';
    }
    eq.fault = null;
    eq.interlock = null;
  } else if (eq.type === 'pump') {
    eq.actual_state = 'stopped';
    eq.requested_state = 'stop';
    eq.position = 0;
  } else if (eq.type === 'valve') {
    eq.actual_state = eq.position >= 100 ? 'open' : eq.position <= 0 ? 'closed' : 'opening';
  } else {
    eq.actual_state = 'ok';
  }
  await persistEquipment([eq]);

  const action = underMaintenance ? 'placed under maintenance' : 'returned to service';
  await insertEvents(eq.plant_id, [
    {
      category: 'maintenance',
      level: underMaintenance ? 'warning' : 'info',
      message: `${eq.tag} ${eq.name} ${action}${note ? ` - ${note}` : ''}`,
      actor: user.fullName,
      data: { tag: eq.tag, under_maintenance: underMaintenance },
    },
    cmmsSync(underMaintenance ? 'lockout' : 'release', eq.tag, 'system'),
  ]);
  return c.json({ equipment: eq });
});
