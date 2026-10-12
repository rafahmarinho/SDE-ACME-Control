/**
 * Applies the SQL migrations in ../supabase/migrations and runs ../supabase/seed.sql
 * against DATABASE_URL. Usage:
 *   pnpm db:setup          # migrations + seed
 *   pnpm db:seed           # seed only (re-creates demo users if missing, reloads demo data)
 */
import 'dotenv/config';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const here = dirname(fileURLToPath(import.meta.url));
const supabaseDir = resolve(here, '../../supabase');
const seedOnly = process.argv.includes('--seed-only');

async function main() {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('DATABASE_URL is not set. Copy .env.example to .env and fill in the Supabase connection string.');
    process.exit(1);
  }
  const isLocal = /localhost|127\.0\.0\.1/.test(url);
  const client = new pg.Client({ connectionString: url, ssl: isLocal ? undefined : { rejectUnauthorized: false } });
  await client.connect();
  try {
    if (!seedOnly) {
      await client.query('create table if not exists public._acme_migrations (name text primary key, applied_at timestamptz not null default now())');
      const applied = new Set((await client.query('select name from public._acme_migrations')).rows.map((r) => r.name as string));
      const files = readdirSync(join(supabaseDir, 'migrations')).filter((f) => f.endsWith('.sql')).sort();
      for (const file of files) {
        if (applied.has(file)) {
          console.log(`skip     ${file} (already applied)`);
          continue;
        }
        const sql = readFileSync(join(supabaseDir, 'migrations', file), 'utf8');
        console.log(`migrate  ${file}`);
        await client.query('begin');
        try {
          await client.query(sql);
          await client.query('insert into public._acme_migrations (name) values ($1)', [file]);
          await client.query('commit');
        } catch (e) {
          await client.query('rollback');
          throw e;
        }
      }
    }
    const seed = readFileSync(join(supabaseDir, 'seed.sql'), 'utf8');
    console.log('seed     seed.sql');
    await client.query(seed);
    console.log('done. Demo accounts: operator@acme.demo, engineer@acme.demo, supervisor@acme.demo, maintenance@acme.demo (password Acme1234!)');
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
