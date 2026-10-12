import { Hono } from 'hono';
import { z } from 'zod';
import { assertRole, OPERATE_ROLES, requireAuth, REVIEW_ROLES, type AppEnv } from '../lib/auth.js';
import { audit } from '../lib/audit.js';
import { conflict, notFound } from '../lib/errors.js';
import { supervisorEmail } from '../lib/integrations.js';
import { RATE_LIMITS, rateLimit } from '../lib/ratelimit.js';
import { parseJson, safeText, uuid } from '../lib/security.js';
import { supabaseAdmin } from '../lib/supabase.js';
import { insertEvents } from '../sim/service.js';

export const setpointsRoute = new Hono<AppEnv>();
setpointsRoute.use('*', requireAuth);
setpointsRoute.use('*', rateLimit(RATE_LIMITS.setpoints));

const proposalSchema = z
  .object({
    plantId: uuid,
    setpointId: uuid,
    proposedValue: z.number().finite(),
    justification: safeText(1000, 5),
  })
  .strict();

const reviewSchema = z
  .object({
    decision: z.enum(['approve', 'reject']),
    note: safeText(1000).optional(),
  })
  .strict();

setpointsRoute.post('/requests', async (c) => {
  const user = assertRole(c, OPERATE_ROLES, 'propose setpoint changes');
  const { plantId, setpointId, proposedValue, justification } = await parseJson(c, proposalSchema);
  const db = supabaseAdmin();

  const { data: sp, error } = await db.from('setpoints').select('*').eq('id', setpointId).eq('plant_id', plantId).maybeSingle();
  if (error) throw error;
  if (!sp) throw notFound('Setpoint not found');
  const min = Number(sp.min_value);
  const max = Number(sp.max_value);
  if (proposedValue < min || proposedValue > max) {
    throw conflict(`Proposed value must be between ${min} and ${max} ${sp.unit}`.trim());
  }
  if (Number(sp.value) === proposedValue) throw conflict('Proposed value is equal to the current value');

  const { data: pending } = await db.from('setpoint_requests').select('id').eq('setpoint_id', setpointId).eq('status', 'pending').limit(1);
  if (pending && pending.length) throw conflict('There is already a pending request for this setpoint');

  const { data: request, error: insErr } = await db
    .from('setpoint_requests')
    .insert({
      plant_id: plantId,
      setpoint_id: setpointId,
      setpoint_key: sp.key,
      setpoint_label: sp.label,
      requested_by: user.id,
      requested_by_name: user.fullName,
      current_value: sp.value,
      proposed_value: proposedValue,
      justification,
      status: 'pending',
    })
    .select()
    .single();
  if (insErr) throw insErr;

  await insertEvents(plantId, [
    { category: 'setpoint', level: 'info', message: `Setpoint change proposed: ${sp.key} ${sp.value} -> ${proposedValue} ${sp.unit}`.trim(), actor: user.fullName, data: { key: sp.key, request_id: request.id } },
    supervisorEmail(`Setpoint change ${sp.key} awaiting review`, 'supervisor@acme.demo', 'system'),
  ]);
  await audit(c, { action: 'setpoint.propose', outcome: 'success', status: 201, details: { plantId, key: sp.key, from: sp.value, to: proposedValue, requestId: request.id } });
  return c.json({ request }, 201);
});

setpointsRoute.post('/requests/:id/review', async (c) => {
  const user = assertRole(c, REVIEW_ROLES, 'review setpoint changes');
  const parsed = await parseJson(c, reviewSchema);
  const id = c.req.param('id');
  if (!uuid.safeParse(id).success) throw notFound('Setpoint request not found');
  const db = supabaseAdmin();

  const { data: request, error } = await db.from('setpoint_requests').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  if (!request) throw notFound('Setpoint request not found');
  if (request.status !== 'pending') throw conflict(`This request was already ${request.status}`);

  // Separation of duties: nobody reviews their own proposal.
  if (request.requested_by === user.id) {
    await audit(c, { action: 'setpoint.review', outcome: 'denied', status: 403, details: { requestId: id, reason: 'self_review' } });
    throw conflict('You cannot review your own setpoint proposal. Ask another supervisor.');
  }

  const now = new Date().toISOString();
  const approved = parsed.decision === 'approve';
  if (approved) {
    const { data: sp } = await db.from('setpoints').select('min_value, max_value').eq('id', request.setpoint_id).maybeSingle();
    if (!sp) throw notFound('Setpoint no longer exists');
    const value = Math.min(Number(sp.max_value), Math.max(Number(sp.min_value), Number(request.proposed_value)));
    const { error: spErr } = await db.from('setpoints').update({ value, updated_by: user.id }).eq('id', request.setpoint_id);
    if (spErr) throw spErr;
  }

  const { data: updated, error: updErr } = await db
    .from('setpoint_requests')
    .update({
      status: approved ? 'approved' : 'rejected',
      reviewed_by: user.id,
      reviewed_by_name: user.fullName,
      review_note: parsed.note ?? null,
      reviewed_at: now,
    })
    .eq('id', id)
    .eq('status', 'pending')
    .select()
    .maybeSingle();
  if (updErr) throw updErr;
  if (!updated) throw conflict('This request was reviewed by someone else a moment ago');

  await insertEvents(request.plant_id, [
    {
      category: 'setpoint',
      level: approved ? 'info' : 'warning',
      message: approved
        ? `Setpoint ${request.setpoint_key} changed ${request.current_value} -> ${request.proposed_value} (approved by ${user.fullName})`
        : `Setpoint change ${request.setpoint_key} rejected by ${user.fullName}`,
      actor: user.fullName,
      data: { key: request.setpoint_key, request_id: id, decision: parsed.decision },
    },
  ]);
  await audit(c, { action: 'setpoint.review', outcome: 'success', status: 200, details: { requestId: id, key: request.setpoint_key, decision: parsed.decision } });
  return c.json({ request: updated });
});
