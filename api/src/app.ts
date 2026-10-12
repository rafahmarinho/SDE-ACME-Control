import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import { requireAuth, type AppEnv } from './lib/auth.js';
import { env } from './lib/env.js';
import { ApiError } from './lib/errors.js';
import { bodyGuard, methodAllowList, requestIdMiddleware, securityHeaders } from './lib/security.js';
import { commandsRoute } from './routes/commands.js';
import { equipmentRoute } from './routes/equipment.js';
import { setpointsRoute } from './routes/setpoints.js';
import { simRoute } from './routes/sim.js';

export const app = new Hono<AppEnv>().basePath('/api');

app.use('*', requestIdMiddleware);
app.use('*', securityHeaders);
app.use('*', methodAllowList);
app.use(
  '*',
  cors({
    origin: (origin) => {
      const allowed = env.corsOrigins;
      if (allowed.includes('*')) return origin || '*';
      return allowed.includes(origin) ? origin : '';
    },
    allowHeaders: ['Authorization', 'Content-Type', 'X-Request-Id'],
    exposeHeaders: ['X-Request-Id', 'X-RateLimit-Limit', 'X-RateLimit-Remaining', 'X-RateLimit-Reset', 'Retry-After'],
    allowMethods: ['GET', 'POST', 'OPTIONS'],
    maxAge: 600,
  }),
);
app.use('*', bodyGuard);

app.onError((err, c) => {
  const requestId = c.get('requestId');
  if (err instanceof ApiError) {
    return c.json({ ...err.toJSON(), requestId }, err.status as ContentfulStatusCode);
  }
  // Internal details stay on the server; the client gets a correlation id only.
  console.error('[api] unhandled error', { requestId, path: c.req.path, error: err instanceof Error ? err.stack ?? err.message : String(err) });
  return c.json({ error: 'internal', message: 'Unexpected error. Please try again or contact support with the request id.', requestId }, 500);
});

app.notFound((c) => c.json({ error: 'not_found', message: 'No such endpoint', requestId: c.get('requestId') }, 404));

app.get('/', (c) => c.json({ name: 'ACME Control API', time: new Date().toISOString() }));
app.get('/health', (c) => c.json({ ok: true, time: new Date().toISOString() }));
app.get('/me', requireAuth, (c) => c.json({ user: c.get('user') }));

app.route('/commands', commandsRoute);
app.route('/sim', simRoute);
app.route('/setpoints', setpointsRoute);
app.route('/equipment', equipmentRoute);

export type App = typeof app;
