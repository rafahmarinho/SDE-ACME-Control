/**
 * Alternative to the SQL user seed: creates the four demo accounts through the
 * Supabase Auth admin API (useful when you cannot write to auth.users directly)
 * and then loads the demo data. Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.
 *   pnpm seed:users
 */
import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const DEMO_USERS = [
  { email: 'operator@acme.demo', full_name: 'Dana Reyes', role: 'operator', phone: '+1 555 0101' },
  { email: 'engineer@acme.demo', full_name: 'Marcus Chen', role: 'engineer', phone: '+1 555 0102' },
  { email: 'supervisor@acme.demo', full_name: 'Priya Natarajan', role: 'supervisor', phone: '+1 555 0103' },
  { email: 'maintenance@acme.demo', full_name: 'Tom Okafor', role: 'maintenance', phone: '+1 555 0104' },
];
const PASSWORD = 'Acme1234!';

async function main() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set');
    process.exit(1);
  }
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: existing, error: listErr } = await db.auth.admin.listUsers({ perPage: 1000 });
  if (listErr) throw listErr;
  const byEmail = new Map(existing.users.map((u) => [u.email?.toLowerCase(), u]));

  for (const u of DEMO_USERS) {
    let id = byEmail.get(u.email)?.id;
    if (!id) {
      const { data, error } = await db.auth.admin.createUser({
        email: u.email,
        password: PASSWORD,
        email_confirm: true,
        user_metadata: { full_name: u.full_name, role: u.role },
      });
      if (error) throw error;
      id = data.user.id;
      console.log(`created  ${u.email}`);
    } else {
      console.log(`exists   ${u.email}`);
    }
    const { error: profErr } = await db
      .from('profiles')
      .upsert({ id, email: u.email, full_name: u.full_name, role: u.role, phone: u.phone }, { onConflict: 'id' });
    if (profErr) throw profErr;
  }

  const { error: seedErr } = await db.rpc('seed_demo_data');
  if (seedErr) throw seedErr;
  console.log(`done. Password for all demo accounts: ${PASSWORD}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
