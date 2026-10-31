import "server-only";

import { z } from "zod";

import { AppEnvironmentSchema } from "@/lib/env/public";

const ServerEnvSchema = z
  .strictObject({
    NODE_ENV: z.enum(["development", "test", "production"]),
    APP_ENV: AppEnvironmentSchema,
    NEXT_PUBLIC_APP_ENV: AppEnvironmentSchema,
    NEXT_PUBLIC_SUPABASE_URL: z.url(),
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(16),
    SUPABASE_PROJECT_REF: z.string().min(1),
    PRODUCTION_SUPABASE_PROJECT_REF: z.string().min(1),
    SERVER_CREDENTIAL_SCOPE: AppEnvironmentSchema,
    VERCEL_REGION: z.string().min(1).default("bom1"),
    SUPABASE_SERVICE_ROLE_KEY: z.string().min(20),
    OPENAI_API_KEY: z.string().min(20),
    OPENAI_BASE_URL: z.url().default("https://api.openai.com/v1"),
    OPENAI_WEBHOOK_SECRET: z.string().min(16),
    HOST_RECOVERY_TOKEN_PEPPER: z.string().min(32),
    SAFETY_IDENTIFIER_HMAC_SECRET: z.string().min(32),
    CRON_SECRET: z.string().min(32),
    STORY_MODEL: z.string().min(1).default("gpt-6.1-sol"),
    STORY_ESCALATION_MODEL: z.string().min(1).default("gpt-6-astra"),
    INTERVENTION_MODEL: z.string().min(1).default("gpt-6.1-sol"),
  })
  .superRefine((environment, context) => {
    if (environment.APP_ENV !== environment.NEXT_PUBLIC_APP_ENV) {
      context.addIssue({
        code: "custom",
        path: ["NEXT_PUBLIC_APP_ENV"],
        message: "Public and server deployment environments must match.",
      });
    }

    if (environment.APP_ENV !== environment.SERVER_CREDENTIAL_SCOPE) {
      context.addIssue({
        code: "custom",
        path: ["SERVER_CREDENTIAL_SCOPE"],
        message:
          "Server credentials must be scoped to this deployment environment.",
      });
    }

    if (
      environment.APP_ENV === "production" &&
      new URL(environment.OPENAI_BASE_URL).origin !== "https://api.openai.com"
    ) {
      context.addIssue({
        code: "custom",
        path: ["OPENAI_BASE_URL"],
        message: "Production OpenAI requests must use the official API origin.",
      });
    }

    const usesProductionProject =
      environment.SUPABASE_PROJECT_REF ===
      environment.PRODUCTION_SUPABASE_PROJECT_REF;
    if (environment.APP_ENV === "production" && !usesProductionProject) {
      context.addIssue({
        code: "custom",
        path: ["SUPABASE_PROJECT_REF"],
        message:
          "Production must use the configured production Supabase project.",
      });
    }
    if (environment.APP_ENV !== "production" && usesProductionProject) {
      context.addIssue({
        code: "custom",
        path: ["SUPABASE_PROJECT_REF"],
        message:
          "Non-production deployments cannot use the production Supabase project.",
      });
    }

    if (environment.APP_ENV !== "local") {
      const projectHost = new URL(environment.NEXT_PUBLIC_SUPABASE_URL)
        .hostname;
      if (projectHost !== `${environment.SUPABASE_PROJECT_REF}.supabase.co`) {
        context.addIssue({
          code: "custom",
          path: ["NEXT_PUBLIC_SUPABASE_URL"],
          message: "Supabase URL must match SUPABASE_PROJECT_REF.",
        });
      }
    }
  });

export type ServerEnv = z.infer<typeof ServerEnvSchema>;

let cachedServerEnv: ServerEnv | undefined;

function readServerEnv(): Record<string, string | undefined> {
  return {
    NODE_ENV: process.env.NODE_ENV,
    APP_ENV: process.env.APP_ENV,
    NEXT_PUBLIC_APP_ENV: process.env.NEXT_PUBLIC_APP_ENV,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    SUPABASE_PROJECT_REF: process.env.SUPABASE_PROJECT_REF,
    PRODUCTION_SUPABASE_PROJECT_REF:
      process.env.PRODUCTION_SUPABASE_PROJECT_REF,
    SERVER_CREDENTIAL_SCOPE: process.env.SERVER_CREDENTIAL_SCOPE,
    VERCEL_REGION: process.env.VERCEL_REGION,
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    OPENAI_BASE_URL: process.env.OPENAI_BASE_URL,
    OPENAI_WEBHOOK_SECRET: process.env.OPENAI_WEBHOOK_SECRET,
    HOST_RECOVERY_TOKEN_PEPPER: process.env.HOST_RECOVERY_TOKEN_PEPPER,
    SAFETY_IDENTIFIER_HMAC_SECRET: process.env.SAFETY_IDENTIFIER_HMAC_SECRET,
    CRON_SECRET: process.env.CRON_SECRET,
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
