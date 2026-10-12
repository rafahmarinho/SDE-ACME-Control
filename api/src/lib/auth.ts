import type { Context, MiddlewareHandler } from 'hono';
import { supabaseAdmin } from './supabase.js';
import { forbidden, unauthorized } from './errors.js';
import type { UserRole } from '../sim/types.js';

export interface AuthUser {
  id: string;
  email: string;
  fullName: string;
  role: UserRole;
}

export type AppEnv = { Variables: { user: AuthUser } };

/** Verifies the Supabase access token sent by the app and loads the caller's profile. */
export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const header = c.req.header('authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : '';
  if (!token) throw unauthorized();

  const db = supabaseAdmin();
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw unauthorized('Invalid or expired session. Please sign in again.');

  const { data: profile } = await db
    .from('profiles')
    .select('id, email, full_name, role')
    .eq('id', data.user.id)
    .maybeSingle();
  if (!profile) throw unauthorized('No profile found for this account');

  c.set('user', {
    id: profile.id,
    email: profile.email,
    fullName: profile.full_name || profile.email,
    role: profile.role as UserRole,
  });
  await next();
};

export function assertRole(c: Context<AppEnv>, roles: UserRole[], action: string): AuthUser {
  const user = c.get('user');
  if (!roles.includes(user.role)) {
    throw forbidden(`Role "${user.role}" is not allowed to ${action}`);
  }
  return user;
}

export const OPERATE_ROLES: UserRole[] = ['operator', 'engineer', 'supervisor'];
export const MAINTAIN_ROLES: UserRole[] = ['maintenance', 'engineer', 'supervisor'];
export const SIMULATE_ROLES: UserRole[] = ['engineer', 'supervisor'];
export const REVIEW_ROLES: UserRole[] = ['supervisor'];
