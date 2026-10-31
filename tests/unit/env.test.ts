import { describe, expect, it } from "vitest";

import { getPublicEnv } from "@/lib/env/public";
import { getServerEnv } from "@/lib/env/server";

const base = {
  NODE_ENV: "test",
  NEXT_PUBLIC_SUPABASE_URL: "https://example.supabase.co",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "publishable-key-for-tests",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-key-for-tests",
  OPENAI_API_KEY: "openai-key-for-tests-123",
  OPENAI_WEBHOOK_SECRET: "webhook-secret-for-tests",
  HOST_RECOVERY_TOKEN_PEPPER: "r".repeat(32),
  SAFETY_IDENTIFIER_HMAC_SECRET: "s".repeat(32),
  STORY_MODEL: "gpt-6.1-sol",
  STORY_ESCALATION_MODEL: "gpt-6-astra",
  INTERVENTION_MODEL: "gpt-6.1-sol",
} as const;

describe("environment validation", () => {
  it("fails closed when a server secret is missing", () => {
    const missingOpenAI: Record<string, string | undefined> = { ...base };
    delete missingOpenAI.OPENAI_API_KEY;
    expect(() => getServerEnv(missingOpenAI)).toThrow();
  });

  it("returns an explicit model policy configuration", () => {
    expect(getServerEnv(base)).toMatchObject({
      STORY_MODEL: "gpt-6.1-sol",
      STORY_ESCALATION_MODEL: "gpt-6-astra",
      INTERVENTION_MODEL: "gpt-6.1-sol",
    });
  });

  it("limits browser configuration to publishable values", () => {
    const publicEnv = getPublicEnv({
      NEXT_PUBLIC_SUPABASE_URL: base.NEXT_PUBLIC_SUPABASE_URL,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
        base.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    });
    expect(publicEnv).toEqual({
      NEXT_PUBLIC_SUPABASE_URL: base.NEXT_PUBLIC_SUPABASE_URL,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
        base.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    });
    expect("OPENAI_API_KEY" in publicEnv).toBe(false);
    expect(() => getPublicEnv(base)).toThrow();
  });
});
