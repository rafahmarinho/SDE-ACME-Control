/**
 * Security audit log. Every authentication failure, authorization denial,
 * rejected/accepted control action and administrative operation is written to
 * public.security_events with the service role. Supervisors can read the log
 * from the app (Security page); clients can never write to it.
 */
import type { Context } from 'hono';
import { supabaseAdmin } from './supabase.js';
import type { AuthUser } from './auth.js';

export type AuditOutcome = 'success' | 'denied' | 'error' | 'rejected';

export interface AuditEntry {
  action: string;
  outcome: AuditOutcome;
  status?: number;
  details?: Record<string, unknown>;
  user?: AuthUser | null;
}

/** Best-effort client address: Vercel sets x-forwarded-for / x-real-ip. */
export function clientIp(c: Context): string | null {
  const forwarded = c.req.header('x-forwarded-for');
  if (forwarded) return forwarded.split(',')[0]!.trim().slice(0, 64);
  const real = c.req.header('x-real-ip');
  return real ? real.slice(0, 64) : null;
}

export function requestId(c: Context): string {
  return c.get('requestId' as never) ?? c.req.header('x-request-id') ?? '';
}

/** Never let an audit write break the request; failures are logged to stderr. */
export async function audit(c: Context, entry: AuditEntry): Promise<void> {
  const user = entry.user === undefined ? (c.get('user' as never) as AuthUser | undefined) : entry.user;
  const row = {
    actor_id: user?.id ?? null,
    actor_email: user?.email ?? null,
    actor_role: user?.role ?? null,
    action: entry.action.slice(0, 80),
    outcome: entry.outcome,
    status: entry.status ?? null,
    path: `${c.req.method} ${c.req.path}`.slice(0, 200),
    ip: clientIp(c),
    user_agent: (c.req.header('user-agent') ?? '').slice(0, 200) || null,
    request_id: requestId(c).slice(0, 64) || null,
    details: entry.details ?? {},
  };
  try {
    const { error } = await supabaseAdmin().from('security_events').insert(row);
    if (error) console.error('[audit] insert failed', { code: error.code, message: error.message });
  } catch (err) {
    console.error('[audit] insert threw', err instanceof Error ? err.message : err);
  }
}
