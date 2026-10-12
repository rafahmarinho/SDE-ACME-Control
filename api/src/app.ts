import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import { requireAuth, type AppEnv } from './lib/auth.js';
import { env } from './lib/env.js';
import { ApiError } from './lib/errors.js';
import { commandsRoute } from './routes/commands.js';
import { equipmentRoute } from './routes/equipment.js';
import { setpointsRoute } from './routes/setpoints.js';
import { simRoute } from './routes/sim.js';

export const app = new Hono<AppEnv>().basePath('/api');

app.use(
  '*',
  cors({
    origin: (origin) => {
      const allowed = env.corsOrigins;
      if (allowed.includes('*')) return origin || '*';
      return allowed.includes(origin) ? origin : '';
    },
    allowHeaders: ['Authorization', 'Content-Type'],
    allowMethods: ['GET', 'POST', 'OPTIONS'],
    maxAge: 600,
  }),
);

app.onError((err, c) => {
  if (err instanceof ApiError) {
    return c.json(err.toJSON(), err.status as ContentfulStatusCode);
  }
  console.error('[api] unhandled error', err);
  const message = err instanceof Error ? err.message : 'Unexpected error';
  return c.json({ error: 'internal', message }, 500);
});

app.notFound((c) => c.json({ error: 'not_found', message: `No route for ${c.req.method} ${c.req.path}` }, 404));

app.get('/', (c) => c.json({ name: 'ACME Control API', version: '1.0.0', time: new Date().toISOString() }));
app.get('/health', (c) => c.json({ ok: true, time: new Date().toISOString() }));
app.get('/me', requireAuth, (c) => c.json({ user: c.get('user') }));

app.route('/commands', commandsRoute);
app.route('/sim', simRoute);
app.route('/setpoints', setpointsRoute);
app.route('/equipment', equipmentRoute);

export type App = typeof app;
