import 'dotenv/config';
import { serve } from '@hono/node-server';
import { app } from './app.js';
import { env, validateEnv } from './lib/env.js';

const { warnings } = validateEnv();
for (const w of warnings) console.warn(`[config] ${w}`);

serve({ fetch: app.fetch, port: env.port }, (info) => {
  console.log(`ACME Control API listening on http://localhost:${info.port}/api`);
});
