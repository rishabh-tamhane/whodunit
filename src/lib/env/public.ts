import { z } from "zod";

export const AppEnvironmentSchema = z.enum([
  "local",
  "preview",
  "staging",
  "production",
]);

const PublicEnvSchema = z.strictObject({
  NEXT_PUBLIC_APP_ENV: AppEnvironmentSchema,
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(16),
});

export type PublicEnv = z.infer<typeof PublicEnvSchema>;

let cachedPublicEnv: PublicEnv | undefined;

function readPublicEnv(): Record<string, string | undefined> {
  return {
    NEXT_PUBLIC_APP_ENV: process.env.NEXT_PUBLIC_APP_ENV,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  };
}

export function getPublicEnv(
  source?: Record<string, string | undefined>,
): PublicEnv {
  if (source) {
    return PublicEnvSchema.parse(source);
  }

  cachedPublicEnv ??= PublicEnvSchema.parse(readPublicEnv());
  return cachedPublicEnv;
}
