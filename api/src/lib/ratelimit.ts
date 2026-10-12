/**
 * Request throttling. The counter lives in Postgres (public.consume_rate_limit)
 * so that every Vercel function instance shares the same window; an in-memory
 * fallback protects the function when the database is unreachable.
 */
import type { MiddlewareHandler } from 'hono';
import { supabaseAdmin } from './supabase.js';
import { ApiError } from './errors.js';
import { audit, clientIp } from './audit.js';
import type { AppEnv } from './auth.js';

export interface RateLimitRule {
  /** Logical bucket name, e.g. "commands". */
  name: string;
  /** Allowed requests per window. */
  limit: number;
  /** Window length in seconds. */
  windowSeconds: number;
}

export const RATE_LIMITS = {
  /** Authentication attempts per IP (invalid/missing tokens). */
  auth: { name: 'auth', limit: 30, windowSeconds: 60 },
  /** Control commands per user. */
  commands: { name: 'commands', limit: 40, windowSeconds: 60 },
  /** Simulation control (advance, scenario, pause, reset) per user. */
  simulation: { name: 'simulation', limit: 20, windowSeconds: 60 },
  /** Ticks per user (one connected client ticks at most every second). */
  tick: { name: 'tick', limit: 120, windowSeconds: 60 },
  /** Setpoint proposals and reviews per user. */
  setpoints: { name: 'setpoints', limit: 30, windowSeconds: 60 },
  /** Maintenance lockout changes per user. */
  maintenance: { name: 'maintenance', limit: 30, windowSeconds: 60 },
} as const satisfies Record<string, RateLimitRule>;

export class RateLimitError extends ApiError {
  constructor(public readonly resetAt: Date) {
    super(429, 'Too many requests. Please slow down and try again shortly.', 'rate_limited', { resetAt: resetAt.toISOString() });
  }
}

interface Decision {
  allowed: boolean;
  remaining: number;
  resetAt: Date;
}

const memory = new Map<string, { windowStart: number; hits: number }>();

function consumeInMemory(key: string, rule: RateLimitRule, now = Date.now()): Decision {
  const windowMs = rule.windowSeconds * 1000;
  let entry = memory.get(key);
  if (!entry || entry.windowStart + windowMs <= now) {
    entry = { windowStart: now, hits: 0 };
    memory.set(key, entry);
  }
  const resetAt = new Date(entry.windowStart + windowMs);
  if (entry.hits >= rule.limit) return { allowed: false, remaining: 0, resetAt };
  entry.hits += 1;
  if (memory.size > 5000) {
    for (const [k, v] of memory) if (v.windowStart + windowMs <= now) memory.delete(k);
  }
  return { allowed: true, remaining: rule.limit - entry.hits, resetAt };
}

/** Exported for tests. */
export const _memoryLimiter = { consume: consumeInMemory, reset: () => memory.clear() };

export async function consume(key: string, rule: RateLimitRule): Promise<Decision> {
  try {
    const { data, error } = await supabaseAdmin().rpc('consume_rate_limit', {
      p_key: key,
      p_limit: rule.limit,
      p_window_seconds: rule.windowSeconds,
    });
    if (error) throw error;
    const d = data as { allowed: boolean; remaining: number; reset_at: string };
    return { allowed: Boolean(d.allowed), remaining: Number(d.remaining), resetAt: new Date(d.reset_at) };
  } catch (err) {
    console.error('[ratelimit] database limiter unavailable, using in-memory fallback', err instanceof Error ? err.message : err);
    return consumeInMemory(key, rule);
  }
}

/**
 * Hono middleware. Keys by the authenticated user when available, otherwise by
 * client IP. Must run after requireAuth for per-user buckets.
 */
export function rateLimit(rule: RateLimitRule): MiddlewareHandler<AppEnv> {
  return async (c, next) => {
    const user = c.get('user');
    const subject = user ? `u:${user.id}` : `ip:${clientIp(c) ?? 'unknown'}`;
    const decision = await consume(`${rule.name}:${subject}`, rule);
    c.header('X-RateLimit-Limit', String(rule.limit));
    c.header('X-RateLimit-Remaining', String(Math.max(0, decision.remaining)));
    c.header('X-RateLimit-Reset', String(Math.ceil(decision.resetAt.getTime() / 1000)));
    if (!decision.allowed) {
      c.header('Retry-After', String(Math.max(1, Math.ceil((decision.resetAt.getTime() - Date.now()) / 1000))));
      await audit(c, { action: `rate_limit.${rule.name}`, outcome: 'denied', status: 429, details: { subject } });
      throw new RateLimitError(decision.resetAt);
    }
    await next();
  };
}
