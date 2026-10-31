import "server-only";

import { z } from "zod";

const ServerEnvSchema = z.strictObject({
  NODE_ENV: z.enum(["development", "test", "production"]),
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(16),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(20),
  OPENAI_API_KEY: z.string().min(20),
  OPENAI_WEBHOOK_SECRET: z.string().min(16),
  HOST_RECOVERY_TOKEN_PEPPER: z.string().min(32),
  SAFETY_IDENTIFIER_HMAC_SECRET: z.string().min(32),
  STORY_MODEL: z.string().min(1).default("gpt-6.1-sol"),
  STORY_ESCALATION_MODEL: z.string().min(1).default("gpt-6-astra"),
  INTERVENTION_MODEL: z.string().min(1).default("gpt-6.1-sol"),
});

export type ServerEnv = z.infer<typeof ServerEnvSchema>;

let cachedServerEnv: ServerEnv | undefined;

function readServerEnv(): Record<string, string | undefined> {
  return {
    NODE_ENV: process.env.NODE_ENV,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    OPENAI_WEBHOOK_SECRET: process.env.OPENAI_WEBHOOK_SECRET,
    HOST_RECOVERY_TOKEN_PEPPER: process.env.HOST_RECOVERY_TOKEN_PEPPER,
    SAFETY_IDENTIFIER_HMAC_SECRET: process.env.SAFETY_IDENTIFIER_HMAC_SECRET,
    STORY_MODEL: process.env.STORY_MODEL,
    STORY_ESCALATION_MODEL: process.env.STORY_ESCALATION_MODEL,
    INTERVENTION_MODEL: process.env.INTERVENTION_MODEL,
  };
}

export function getServerEnv(
  source?: Record<string, string | undefined>,
): ServerEnv {
  if (source) {
    return ServerEnvSchema.parse(source);
  }

  cachedServerEnv ??= ServerEnvSchema.parse(readServerEnv());
  return cachedServerEnv;
}
