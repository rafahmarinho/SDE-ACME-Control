function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

function isHttpsUrl(value: string): boolean {
  try {
    const u = new URL(value);
    return u.protocol === 'https:' || u.hostname === 'localhost' || u.hostname === '127.0.0.1';
  } catch {
    return false;
  }
}

export const env = {
  get supabaseUrl() {
    const value = required('SUPABASE_URL');
    if (!isHttpsUrl(value)) throw new Error('SUPABASE_URL must be an https URL');
    return value;
  },
  /** Service role / secret key. Server side only; never logged, never returned. */
  get serviceRoleKey() {
    return required('SUPABASE_SERVICE_ROLE_KEY');
  },
  /**
   * Browser origins allowed by CORS. Defaults to localhost development origins;
   * "*" is accepted for quick demos but logged as a warning at startup.
   */
  get corsOrigins(): string[] {
    const raw = process.env.CORS_ORIGINS ?? 'http://localhost:3000,http://127.0.0.1:3000';
    return raw.split(',').map((s) => s.trim()).filter(Boolean);
  },
  get port(): number {
    return Number(process.env.PORT ?? 3001);
  },
  get isProduction(): boolean {
    return process.env.NODE_ENV === 'production' || process.env.VERCEL_ENV === 'production';
  },
};

/** Validate configuration once at startup; throws with a clear message. */
export function validateEnv(): { warnings: string[] } {
  const warnings: string[] = [];
  void env.supabaseUrl;
  void env.serviceRoleKey;
  if (env.corsOrigins.includes('*')) {
    warnings.push('CORS_ORIGINS is "*": any website may call this API with a valid token. Set it to the web app origin in production.');
  }
  return { warnings };
}
