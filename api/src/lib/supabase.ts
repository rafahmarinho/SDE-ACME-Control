import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { env } from './env.js';

let client: SupabaseClient | undefined;

/** Service-role client. Bypasses RLS - only ever used server side. */
export function supabaseAdmin(): SupabaseClient {
  if (!client) {
    client = createClient(env.supabaseUrl, env.serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { headers: { 'x-application-name': 'acme-control-api' } },
    });
  }
  return client;
}
