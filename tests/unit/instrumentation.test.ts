import { afterEach, describe, expect, it, vi } from "vitest";

import { register } from "@/instrumentation";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("server startup", () => {
  it("fails closed without exposing secret values", async () => {
    vi.stubEnv("NEXT_RUNTIME", "nodejs");
    vi.stubEnv("OPENAI_API_KEY", "");
    vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", "");

    await expect(register()).rejects.toThrow(
      "Whodunit cannot start because its server configuration is missing or malformed.",
    );
  });
});
