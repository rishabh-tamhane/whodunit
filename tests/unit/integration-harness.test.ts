import { describe, expect, it, vi } from "vitest";

import { createApiTestClient } from "../support/api-client";
import { getIntegrationEnv } from "../support/integration-env";

const environment = {
  TEST_APP_BASE_URL: "http://127.0.0.1:3100",
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "publishable-test-key",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",
};

describe("integration harness", () => {
  it("validates the complete local test environment", () => {
    expect(getIntegrationEnv(environment)).toEqual(environment);
    expect(() =>
      getIntegrationEnv({ ...environment, SUPABASE_SERVICE_ROLE_KEY: "" }),
    ).toThrow();
  });

  it("invokes a relative API route with JSON negotiation", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (input, init) => {
      expect(String(input)).toBe("http://127.0.0.1:3100/api/v1/health");
      expect(new Headers(init?.headers).get("accept")).toBe("application/json");

      return Response.json({ status: "ok" }, { status: 200 });
    });
    const api = createApiTestClient(
      environment.TEST_APP_BASE_URL,
      fetchImplementation,
    );

    await expect(api.request("/api/v1/health")).resolves.toMatchObject({
      body: { status: "ok" },
      status: 200,
    });
  });
});
