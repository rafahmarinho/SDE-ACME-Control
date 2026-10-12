import type { Context, MiddlewareHandler } from 'hono';
import { supabaseAdmin } from './supabase.js';
import { forbidden, unauthorized } from './errors.js';
import type { UserRole } from '../sim/types.js';
import { audit } from './audit.js';
import { consume, RATE_LIMITS, RateLimitError } from './ratelimit.js';
import { clientIp } from './audit.js';

export interface AuthUser {
  id: string;
  email: string;
  fullName: string;
  role: UserRole;
}

export type AppEnv = { Variables: { user: AuthUser; requestId: string } };

const ROLES: UserRole[] = ['operator', 'engineer', 'supervisor', 'maintenance'];

/**
 * Verifies the Supabase access token sent by the app and loads the caller's
 * profile. Failed attempts are throttled per client IP and written to the
 * security log; the response never reveals whether the token was malformed,
 * expired or revoked.
 */
export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const header = c.req.header('authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : '';

  const fail = async (reason: string) => {
    const decision = await consume(`${RATE_LIMITS.auth.name}:ip:${clientIp(c) ?? 'unknown'}`, RATE_LIMITS.auth);
    await audit(c, { action: 'auth.token', outcome: 'denied', status: decision.allowed ? 401 : 429, user: null, details: { reason } });
    if (!decision.allowed) throw new RateLimitError(decision.resetAt);
    throw unauthorized('Authentication required. Please sign in again.');
  };

  if (!token || token.length > 4096 || !/^[A-Za-z0-9._~+/=-]+$/.test(token)) return fail('missing_or_malformed');

  const db = supabaseAdmin();
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) return fail('invalid_or_expired');

  const { data: profile } = await db.from('profiles').select('id, email, full_name, role').eq('id', data.user.id).maybeSingle();
  if (!profile || !ROLES.includes(profile.role as UserRole)) return fail('no_profile');

  c.set('user', {
    id: profile.id,
    email: profile.email,
    fullName: profile.full_name || profile.email,
    role: profile.role as UserRole,
  });
  await next();
};

/** Centralised function-level authorization. Denials are audited. */
export function assertRole(c: Context<AppEnv>, roles: UserRole[], action: string): AuthUser {
  const user = c.get('user');
  if (!roles.includes(user.role)) {
    void audit(c, { action: 'authz.role', outcome: 'denied', status: 403, details: { required: roles, action } });
    throw forbidden(`Role "${user.role}" is not allowed to ${action}`);
  }
  return user;
}

/** Middleware form of assertRole for whole route groups. */
export function requireRole(roles: UserRole[], action: string): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    assertRole(c, roles, action);
    await next();
  };
}

export const OPERATE_ROLES: UserRole[] = ['operator', 'engineer', 'supervisor'];
export const MAINTAIN_ROLES: UserRole[] = ['maintenance', 'engineer', 'supervisor'];
export const SIMULATE_ROLES: UserRole[] = ['engineer', 'supervisor'];
export const REVIEW_ROLES: UserRole[] = ['supervisor'];
