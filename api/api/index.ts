import { handle } from 'hono/vercel';
import { app } from '../src/app.js';

// Vercel Function entry point. vercel.json rewrites /api/* to this file.
//
// Only named HTTP-method exports are declared on purpose: the Vercel Node.js
// runtime treats a default export as a classic `(req, res)` handler and ignores
// the Response it returns, which makes every request time out. Named method
// exports select the Web-standard `(Request) => Response` signature that Hono uses.
const handler = handle(app);

export const GET = handler;
export const HEAD = handler;
export const POST = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
export const OPTIONS = handler;
