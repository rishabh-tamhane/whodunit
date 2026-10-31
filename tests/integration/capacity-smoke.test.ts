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
  it("serves 120 concurrent reads and creates ten rooms within local budgets over three warmed runs", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);

    // Warm route compilation before measuring application latency.
    expect((await api.request("/api/v1/health")).status).toBe(200);
    const readDurations: number[] = [];
    const commandDurations: number[] = [];

    for (let run = 1; run <= 3; run += 1) {
      const reads = await Promise.all(
        Array.from({ length: 120 }, () =>
          timed(() => api.request("/api/v1/health")),
        ),
      );
      expect(reads.every(({ result }) => result.status === 200)).toBe(true);
      const runReadDurations = reads.map(({ durationMs }) => durationMs);
      readDurations.push(...runReadDurations);
      expect(percentile(runReadDurations, 0.95)).toBeLessThan(500);

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
      const runCommandDurations = rooms.map(({ durationMs }) => durationMs);
      commandDurations.push(...runCommandDurations);
      expect(percentile(runCommandDurations, 0.95)).toBeLessThan(750);

      console.info(
        `Local capacity run ${run}: reads p95=${Math.round(percentile(runReadDurations, 0.95))}ms; room commands p95=${Math.round(percentile(runCommandDurations, 0.95))}ms.`,
      );
    }

    const summarize = (values: readonly number[]) => ({
      max: Math.max(...values),
      p50: percentile(values, 0.5),
      p95: percentile(values, 0.95),
    });
    const reads = summarize(readDurations);
    const commands = summarize(commandDurations);
    console.info(
      `Local capacity aggregate: reads p50=${Math.round(reads.p50)}ms p95=${Math.round(reads.p95)}ms max=${Math.round(reads.max)}ms; room commands p50=${Math.round(commands.p50)}ms p95=${Math.round(commands.p95)}ms max=${Math.round(commands.max)}ms.`,
    );
  });
});
