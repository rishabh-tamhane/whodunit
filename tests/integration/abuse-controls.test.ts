import { describe, expect, it } from "vitest";

import { createApiTestClient } from "../support/api-client";
import { getIntegrationEnv } from "../support/integration-env";

type ErrorBody = {
  error?: { code?: string; message?: string; requestId?: string };
};

function cookieHeader(headers: Headers) {
  return headers
    .getSetCookie()
    .map((cookie) => cookie.split(";", 1)[0])
    .join("; ");
}

async function startGuestSession(api: ReturnType<typeof createApiTestClient>) {
  const response = await api.request("/api/v1/session", { method: "POST" });
  expect(response.status).toBe(201);
  return cookieHeader(response.headers);
}

async function createRoom(
  api: ReturnType<typeof createApiTestClient>,
  cookie: string,
) {
  const response = await api.request<{
    roomId: string;
    roomCode: string;
    stateVersion: string;
    recoveryPath: string;
  }>("/api/v1/rooms", { method: "POST", headers: { cookie } });
  expect(response.status).toBe(201);
  return response.body;
}

function publicError(body: ErrorBody) {
  return {
    code: body.error?.code,
    message: body.error?.message,
  };
}

async function expectThrottled({
  attempts,
  challenge,
  request,
}: {
  attempts: number;
  challenge: boolean;
  request: () => Promise<{
    body: ErrorBody;
    headers: Headers;
    status: number;
  }>;
}) {
  let response: Awaited<ReturnType<typeof request>> | undefined;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    response = await request();
    if (attempt < attempts) expect(response.status).not.toBe(429);
  }

  expect(response?.status).toBe(429);
  expect(response?.body.error).toMatchObject({
    code: "RATE_LIMITED",
    message: "Too many requests. Wait briefly and try again.",
  });
  expect(Number(response?.headers.get("retry-after"))).toBeGreaterThan(0);
  expect(response?.headers.get("x-whodunit-abuse-action")).toBe(
    challenge ? "turnstile-challenge" : null,
  );
}

describe("HTTP abuse and enumeration controls", () => {
  it("uses one unavailable response for missing and non-joinable room codes", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);
    const hostCookie = await startGuestSession(api);
    const room = await createRoom(api, hostCookie);
    const playerCookie = await startGuestSession(api);
    const headers = {
      cookie: playerCookie,
      "content-type": "application/json",
      "x-forwarded-for": "203.0.113.10",
    };

    const existingButUnavailable = await api.request<ErrorBody>(
      "/api/v1/lobbies/lookup",
      {
        method: "POST",
        headers,
        body: JSON.stringify({ roomCode: room.roomCode }),
      },
    );
    const missing = await api.request<ErrorBody>("/api/v1/lobbies/lookup", {
      method: "POST",
      headers,
      body: JSON.stringify({ roomCode: "ZZZZZZZZ" }),
    });

    expect(existingButUnavailable.status).toBe(404);
    expect(missing.status).toBe(404);
    expect(publicError(existingButUnavailable.body)).toEqual(
      publicError(missing.body),
    );
  });

  it("does not distinguish a used recovery token from an unknown token", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);
    const hostCookie = await startGuestSession(api);
    const room = await createRoom(api, hostCookie);
    const recoveredHostCookie = await startGuestSession(api);
    const token = decodeURIComponent(
      room.recoveryPath.split("#token=")[1] ?? "",
    );
    const headers = {
      cookie: recoveredHostCookie,
      "content-type": "application/json",
      "x-forwarded-for": "203.0.113.11",
    };

    const recovered = await api.request("/api/v1/host-recovery", {
      method: "POST",
      headers,
      body: JSON.stringify({ token }),
    });
    expect(recovered.status).toBe(200);

    const reused = await api.request<ErrorBody>("/api/v1/host-recovery", {
      method: "POST",
      headers,
      body: JSON.stringify({ token }),
    });
    const unknown = await api.request<ErrorBody>("/api/v1/host-recovery", {
      method: "POST",
      headers,
      body: JSON.stringify({ token: "x".repeat(48) }),
    });

    expect(reused.status).toBe(404);
    expect(unknown.status).toBe(404);
    expect(publicError(reused.body)).toEqual(publicError(unknown.body));
  });

  it("throttles discovery, claim, recovery, generation, and command abuse", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);

    const discoveryCookie = await startGuestSession(api);
    await expectThrottled({
      attempts: 31,
      challenge: true,
      request: () =>
        api.request<ErrorBody>("/api/v1/lobbies/lookup", {
          method: "POST",
          headers: {
            cookie: discoveryCookie,
            "content-type": "application/json",
            "x-forwarded-for": "203.0.113.20",
          },
          body: JSON.stringify({ roomCode: "NOEXIST1" }),
        }),
    });

    const claimCookie = await startGuestSession(api);
    const missingRoomId = "b0000000-0000-4000-8000-000000000001";
    await expectThrottled({
      attempts: 31,
      challenge: true,
      request: () =>
        api.request<ErrorBody>(`/api/v1/rooms/${missingRoomId}/claims`, {
          method: "POST",
          headers: {
            cookie: claimCookie,
            "content-type": "application/json",
            "x-forwarded-for": "203.0.113.21",
          },
          body: JSON.stringify({
            playerId: "b0000000-0000-4000-8000-000000000002",
            requestKind: "INITIAL_CLAIM",
          }),
        }),
    });

    const recoveryCookie = await startGuestSession(api);
    await expectThrottled({
      attempts: 13,
      challenge: true,
      request: () =>
        api.request<ErrorBody>("/api/v1/host-recovery", {
          method: "POST",
          headers: {
            cookie: recoveryCookie,
            "content-type": "application/json",
            "x-forwarded-for": "203.0.113.22",
          },
          body: JSON.stringify({ token: "y".repeat(48) }),
        }),
    });

    const generationCookie = await startGuestSession(api);
    const generationRoom = await createRoom(api, generationCookie);
    await expectThrottled({
      attempts: 7,
      challenge: false,
      request: () =>
        api.request<ErrorBody>(
          `/api/v1/rooms/${generationRoom.roomId}/generation`,
          {
            method: "POST",
            headers: {
              cookie: generationCookie,
              "content-type": "application/json",
              "x-forwarded-for": "203.0.113.23",
            },
            body: JSON.stringify({
              expectedStateVersion: generationRoom.stateVersion,
              idempotencyKey: crypto.randomUUID(),
            }),
          },
        ),
    });

    const commandCookie = await startGuestSession(api);
    const commandRoom = await createRoom(api, commandCookie);
    await expectThrottled({
      attempts: 61,
      challenge: false,
      request: () =>
        api.request<ErrorBody>(
          `/api/v1/rooms/${commandRoom.roomId}/commands/start`,
          {
            method: "POST",
            headers: {
              cookie: commandCookie,
              "content-type": "application/json",
              "x-forwarded-for": "203.0.113.24",
            },
            body: JSON.stringify({
              expectedStateVersion: commandRoom.stateVersion,
              idempotencyKey: crypto.randomUUID(),
            }),
          },
        ),
    });
  }, 60_000);
});
