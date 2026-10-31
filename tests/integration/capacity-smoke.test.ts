import { describe, expect, it } from "vitest";

import { createApiTestClient } from "../support/api-client";
import { getIntegrationEnv } from "../support/integration-env";

function cookieHeader(headers: Headers) {
  return headers
    .getSetCookie()
    .map((cookie) => cookie.split(";", 1)[0])
    .join("; ");
}

function percentile(values: readonly number[], value: number) {
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.max(0, Math.ceil(sorted.length * value) - 1);
  return sorted[index] ?? Number.POSITIVE_INFINITY;
}

async function timed<T>(operation: () => Promise<T>) {
  const startedAt = performance.now();
  const result = await operation();
  return { result, durationMs: performance.now() - startedAt };
}

describe("local capacity regression smoke", () => {
  it("serves 120 concurrent reads and creates ten rooms within local budgets", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);

    // Warm route compilation before measuring application latency.
    expect((await api.request("/api/v1/health")).status).toBe(200);

    const reads = await Promise.all(
      Array.from({ length: 120 }, () =>
        timed(() => api.request("/api/v1/health")),
      ),
    );
    expect(reads.every(({ result }) => result.status === 200)).toBe(true);
    const readP95 = percentile(
      reads.map(({ durationMs }) => durationMs),
      0.95,
    );
    expect(readP95).toBeLessThan(500);

    const rooms = await Promise.all(
      Array.from({ length: 10 }, async () => {
        const session = await api.request("/api/v1/session", {
          method: "POST",
        });
        expect(session.status).toBe(201);
        const cookie = cookieHeader(session.headers);
        return timed(() =>
          api.request("/api/v1/rooms", {
            method: "POST",
            headers: { cookie },
          }),
        );
      }),
    );
    expect(rooms.every(({ result }) => result.status === 201)).toBe(true);
    const commandP95 = percentile(
      rooms.map(({ durationMs }) => durationMs),
      0.95,
    );
    expect(commandP95).toBeLessThan(750);

    console.info(
      `Local capacity smoke: reads p95=${Math.round(readP95)}ms; room commands p95=${Math.round(commandP95)}ms.`,
    );
  });
});
