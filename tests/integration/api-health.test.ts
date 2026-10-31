import { describe, expect, it } from "vitest";

import { createApiTestClient } from "../support/api-client";
import { getIntegrationEnv } from "../support/integration-env";

describe("application health", () => {
  it("serves the versioned health response over real HTTP", async () => {
    const env = getIntegrationEnv();
    const api = createApiTestClient(env.TEST_APP_BASE_URL);

    const response = await api.request<{ status: string; version: string }>(
      "/api/v1/health",
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toContain("no-store");
    expect(response.body).toEqual({ status: "ok", version: "0.1-mvp" });
  });
});
