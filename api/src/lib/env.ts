function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

export const env = {
  get supabaseUrl() {
    return required('SUPABASE_URL');
  },
  get serviceRoleKey() {
    return required('SUPABASE_SERVICE_ROLE_KEY');
  },
  get corsOrigins(): string[] {
    const raw = process.env.CORS_ORIGINS ?? '*';
    return raw.split(',').map((s) => s.trim()).filter(Boolean);
  },
  get port(): number {
    return Number(process.env.PORT ?? 3001);
  },
};
