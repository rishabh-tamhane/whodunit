import { z } from "zod";

const IntegrationEnvSchema = z.strictObject({
  TEST_APP_BASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
});

export type IntegrationEnv = z.infer<typeof IntegrationEnvSchema>;

export function getIntegrationEnv(
  source: Record<string, string | undefined> = process.env,
): IntegrationEnv {
  return IntegrationEnvSchema.parse({
    TEST_APP_BASE_URL: source.TEST_APP_BASE_URL,
    NEXT_PUBLIC_SUPABASE_URL: source.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
      source.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    SUPABASE_SERVICE_ROLE_KEY: source.SUPABASE_SERVICE_ROLE_KEY,
  });
}
