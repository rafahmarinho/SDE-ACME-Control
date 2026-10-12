/**
 * Cross-cutting HTTP security middleware: request ids, hardened response
 * headers, method allow-list, body size limit and input sanitisation helpers.
 */
import type { Context, MiddlewareHandler } from 'hono';
import { z } from 'zod';
import { ApiError } from './errors.js';

export const MAX_BODY_BYTES = 16 * 1024;
export const ALLOWED_METHODS = ['GET', 'HEAD', 'POST', 'OPTIONS'] as const;

/** Attach a request id (reuse a well-formed incoming one, otherwise generate). */
export const requestIdMiddleware: MiddlewareHandler = async (c, next) => {
  const incoming = c.req.header('x-request-id') ?? '';
  const id = /^[A-Za-z0-9._-]{8,64}$/.test(incoming) ? incoming : crypto.randomUUID();
  c.set('requestId' as never, id as never);
  c.header('X-Request-Id', id);
  await next();
};

/** Security headers for an API that only serves JSON. */
export const securityHeaders: MiddlewareHandler = async (c, next) => {
  await next();
  c.header('X-Content-Type-Options', 'nosniff');
  c.header('X-Frame-Options', 'DENY');
  c.header('Referrer-Policy', 'no-referrer');
  c.header('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
  c.header('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
  c.header('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=()');
  c.header('Cross-Origin-Resource-Policy', 'cross-origin');
  c.header('Cache-Control', 'no-store');
  c.header('Pragma', 'no-cache');
  c.header('X-Permitted-Cross-Domain-Policies', 'none');
};

/** Only the verbs the API actually uses are accepted. */
export const methodAllowList: MiddlewareHandler = async (c, next) => {
  if (!(ALLOWED_METHODS as readonly string[]).includes(c.req.method)) {
    c.header('Allow', ALLOWED_METHODS.join(', '));
    throw new ApiError(405, `Method ${c.req.method} is not allowed`, 'method_not_allowed');
  }
  await next();
};

/** Reject oversized or non-JSON request bodies before they are parsed. */
export const bodyGuard: MiddlewareHandler = async (c, next) => {
  if (c.req.method === 'POST') {
    const length = Number(c.req.header('content-length') ?? '0');
    if (Number.isFinite(length) && length > MAX_BODY_BYTES) {
      throw new ApiError(413, `Request body must not exceed ${MAX_BODY_BYTES} bytes`, 'payload_too_large');
    }
    const type = (c.req.header('content-type') ?? '').toLowerCase();
    if (type && !type.startsWith('application/json')) {
      throw new ApiError(415, 'Request body must be application/json', 'unsupported_media_type');
    }
  }
  await next();
};

/**
 * Parse a JSON body with a hard size limit and a zod schema. Unknown keys are
 * rejected (schemas are `.strict()`), control characters are refused by
 * `safeText`, and parse errors never echo the raw payload back.
 */
export async function parseJson<T extends z.ZodTypeAny>(c: Context, schema: T): Promise<z.infer<T>> {
  let raw = '';
  try {
    raw = await c.req.text();
  } catch {
    throw new ApiError(400, 'Request body could not be read', 'bad_request');
  }
  if (raw.length > MAX_BODY_BYTES) {
    throw new ApiError(413, `Request body must not exceed ${MAX_BODY_BYTES} bytes`, 'payload_too_large');
  }
  let json: unknown = {};
  if (raw.trim().length) {
    try {
      json = JSON.parse(raw);
    } catch {
      throw new ApiError(400, 'Request body is not valid JSON', 'bad_request');
    }
  }
  const parsed = schema.safeParse(json);
  if (!parsed.success) {
    throw new ApiError(400, 'Invalid request payload', 'bad_request', parsed.error.flatten().fieldErrors);
  }
  return parsed.data;
}

// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/;

/** Free text: trimmed, bounded, printable (newlines and tabs allowed). */
export function safeText(max: number, min = 0) {
  return z
    .string()
    .trim()
    .min(min)
    .max(max)
    .refine((v) => !CONTROL_CHARS.test(v), { message: 'Control characters are not allowed' });
}

export const uuid = z.string().uuid();

/** Short identifier such as an equipment tag or scenario code. */
export const shortCode = z.string().trim().min(1).max(40).regex(/^[A-Za-z0-9_.-]+$/, 'Invalid identifier');
