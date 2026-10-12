/**
 * Security control tests for the HTTP layer. They run without a database:
 * every request below is rejected (or answered) before Supabase is needed.
 */
import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

// An unreachable local address makes the database-backed limiter and audit log fall back fast.
process.env.SUPABASE_URL ??= 'http://127.0.0.1:9';
process.env.SUPABASE_SERVICE_ROLE_KEY ??= 'test-service-role-key';
process.env.CORS_ORIGINS ??= 'https://acme-control.vercel.app';

const { app } = await import('../src/app.js');
const { _memoryLimiter, RATE_LIMITS } = await import('../src/lib/ratelimit.js');
const { MAX_BODY_BYTES, safeText } = await import('../src/lib/security.js');

const BASE = 'http://localhost/api';

describe('http security controls', () => {
  it('sends hardened headers and a request id on every response', async () => {
    const res = await app.request(`${BASE}/health`);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('x-frame-options'), 'DENY');
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('referrer-policy'), 'no-referrer');
    assert.match(res.headers.get('strict-transport-security') ?? '', /max-age=63072000/);
    assert.match(res.headers.get('content-security-policy') ?? '', /default-src 'none'/);
    assert.match(res.headers.get('x-request-id') ?? '', /^[0-9a-f-]{36}$/);
  });

  it('reuses a well-formed incoming request id and ignores a malformed one', async () => {
    const good = await app.request(`${BASE}/health`, { headers: { 'x-request-id': 'req-1234567890' } });
    assert.equal(good.headers.get('x-request-id'), 'req-1234567890');
    const bad = await app.request(`${BASE}/health`, { headers: { 'x-request-id': '<script>alert(1)</script>' } });
    assert.notEqual(bad.headers.get('x-request-id'), '<script>alert(1)</script>');
  });

  it('rejects HTTP verbs the API does not use', async () => {
    for (const method of ['PUT', 'PATCH', 'DELETE']) {
      const res = await app.request(`${BASE}/health`, { method });
      assert.equal(res.status, 405, method);
      assert.equal(res.headers.get('allow'), 'GET, HEAD, POST, OPTIONS');
    }
  });

  it('refuses requests without a bearer token with a generic message', async () => {
    const res = await app.request(`${BASE}/me`);
    assert.equal(res.status, 401);
    const body = (await res.json()) as { error: string; message: string };
    assert.equal(body.error, 'unauthorized');
    assert.doesNotMatch(body.message, /token|jwt|expired/i);
  });

  it('refuses malformed bearer tokens before touching the database', async () => {
    const res = await app.request(`${BASE}/commands`, {
      method: 'POST',
      headers: { authorization: 'Bearer not a token!!', 'content-type': 'application/json' },
      body: '{}',
    });
    assert.equal(res.status, 401);
  });

  it('limits the request body size', async () => {
    const res = await app.request(`${BASE}/commands`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': String(MAX_BODY_BYTES + 1) },
      body: '{}',
    });
    assert.equal(res.status, 413);
  });

  it('only accepts JSON bodies', async () => {
    const res = await app.request(`${BASE}/commands`, {
      method: 'POST',
      headers: { 'content-type': 'text/plain' },
      body: 'start P1',
    });
    assert.equal(res.status, 415);
  });

  it('only allows configured CORS origins', async () => {
    const allowed = await app.request(`${BASE}/health`, { headers: { origin: 'https://acme-control.vercel.app' } });
    assert.equal(allowed.headers.get('access-control-allow-origin'), 'https://acme-control.vercel.app');
    const denied = await app.request(`${BASE}/health`, { headers: { origin: 'https://evil.example' } });
    assert.equal(denied.headers.get('access-control-allow-origin'), null);
  });

  it('answers unknown routes with JSON and no stack traces', async () => {
    const res = await app.request(`${BASE}/does-not-exist`);
    assert.equal(res.status, 404);
    const body = (await res.json()) as { error: string; message: string };
    assert.equal(body.error, 'not_found');
    assert.doesNotMatch(body.message, /does-not-exist/);
  });
});

describe('input sanitisation', () => {
  it('refuses control characters and overlong text', () => {
    assert.equal(safeText(20).safeParse('hello world').success, true);
    assert.equal(safeText(20).safeParse('bad\u0000text').success, false);
    assert.equal(safeText(5).safeParse('too long text').success, false);
    assert.equal(safeText(50).safeParse('  trimmed  ').data, 'trimmed');
    assert.equal(safeText(50).safeParse('line1\nline2\ttab').success, true);
  });
});

describe('rate limiter (in-memory fallback)', () => {
  beforeEach(() => _memoryLimiter.reset());

  it('allows up to the limit inside a window and blocks afterwards', () => {
    const rule = { name: 'test', limit: 3, windowSeconds: 60 };
    const now = Date.now();
    assert.equal(_memoryLimiter.consume('k', rule, now).allowed, true);
    assert.equal(_memoryLimiter.consume('k', rule, now).allowed, true);
    const third = _memoryLimiter.consume('k', rule, now);
    assert.equal(third.allowed, true);
    assert.equal(third.remaining, 0);
    assert.equal(_memoryLimiter.consume('k', rule, now).allowed, false);
    // a new window resets the counter
    assert.equal(_memoryLimiter.consume('k', rule, now + 61_000).allowed, true);
  });

  it('keeps separate buckets per key', () => {
    const rule = { name: 'test', limit: 1, windowSeconds: 60 };
    assert.equal(_memoryLimiter.consume('a', rule).allowed, true);
    assert.equal(_memoryLimiter.consume('b', rule).allowed, true);
    assert.equal(_memoryLimiter.consume('a', rule).allowed, false);
  });

  it('declares sensible limits for every protected route group', () => {
    for (const rule of Object.values(RATE_LIMITS)) {
      assert.ok(rule.limit > 0 && rule.limit <= 200, rule.name);
      assert.equal(rule.windowSeconds, 60, rule.name);
    }
  });
});
