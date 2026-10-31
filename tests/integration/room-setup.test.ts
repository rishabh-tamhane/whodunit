import { describe, expect, it } from "vitest";

import { createApiTestClient } from "../support/api-client";
import { getIntegrationEnv } from "../support/integration-env";

function cookieHeader(headers: Headers) {
  return headers
    .getSetCookie()
    .map((cookie) => cookie.split(";", 1)[0])
    .join("; ");
}

async function startGuestSession(api: ReturnType<typeof createApiTestClient>) {
  const response = await api.request<{ status: string }>("/api/v1/session", {
    method: "POST",
  });
  expect(response.status).toBe(201);
  return cookieHeader(response.headers);
}

describe("room setup journey", () => {
  it("creates an anonymous Game Master session and opens a configured lobby", async () => {
    const env = getIntegrationEnv();
    const api = createApiTestClient(env.TEST_APP_BASE_URL);
    const cookie = await startGuestSession(api);
    expect(cookie).toContain("sb-");

    const restored = await api.request<{ status: string }>("/api/v1/session", {
      method: "POST",
      headers: { cookie },
    });
    expect(restored.status).toBe(200);
    expect(restored.body.status).toBe("restored");

    const created = await api.request<{
      roomId: string;
      roomCode: string;
      stateVersion: string;
      recoveryPath: string;
      joinPath: string;
    }>("/api/v1/rooms", {
      method: "POST",
      headers: { cookie },
    });
    expect(created.status).toBe(201);
    expect(created.body.roomCode).toMatch(/^[A-F0-9]{8}$/);
    expect(created.body.recoveryPath).toContain("#token=");
    expect(created.body.joinPath).toContain(created.body.roomCode);
    expect(created.headers.get("cache-control")).toContain("no-store");

    const configured = await api.request<{
      stateVersion: string;
      playerCount: number;
    }>(`/api/v1/rooms/${created.body.roomId}/configuration`, {
      method: "PUT",
      headers: { cookie, "content-type": "application/json" },
      body: JSON.stringify({
        expectedStateVersion: created.body.stateVersion,
        configuration: {
          durationProfileVersion: "duration-v1",
          factionProfileVersion: "factions-v1",
          durationMinutes: 30,
          murdererCount: 1,
          accompliceCount: 0,
          innocentCount: 3,
          murdererAware: true,
          playerSlots: [
            { displayName: "Aarav", costume: "Pirate" },
            { displayName: "Aarav", costume: "Vampire" },
            { displayName: "Isha", costume: "Ghost" },
            { displayName: "Kabir", costume: "Detective" },
          ],
        },
      }),
    });
    expect(configured.status).toBe(200);
    expect(configured.body.playerCount).toBe(4);

    const opened = await api.request<{
      status: string;
      stateVersion: string;
    }>(`/api/v1/rooms/${created.body.roomId}/open-lobby`, {
      method: "POST",
      headers: { cookie, "content-type": "application/json" },
      body: JSON.stringify({
        expectedStateVersion: configured.body.stateVersion,
      }),
    });
    expect(opened.status).toBe(200);
    expect(opened.body.status).toBe("LOBBY");

    const playerCookie = await startGuestSession(api);
    const lookup = await api.request<{
      roomId: string;
      slots: Array<{ playerId: string; slotStatus: string }>;
    }>("/api/v1/lobbies/lookup", {
      method: "POST",
      headers: { cookie: playerCookie, "content-type": "application/json" },
      body: JSON.stringify({ roomCode: created.body.roomCode }),
    });
    expect(lookup.status).toBe(200);
    expect(lookup.body.slots).toHaveLength(4);
    const firstSlot = lookup.body.slots[0];
    expect(firstSlot?.slotStatus).toBe("AVAILABLE");

    const claim = await api.request<{ claimId: string; status: string }>(
      `/api/v1/rooms/${created.body.roomId}/claims`,
      {
        method: "POST",
        headers: { cookie: playerCookie, "content-type": "application/json" },
        body: JSON.stringify({
          playerId: firstSlot?.playerId,
          requestKind: "INITIAL_CLAIM",
        }),
      },
    );
    expect(claim.status).toBe(201);
    expect(claim.body.status).toBe("PENDING");

    const hostView = await api.request<{
      room: { stateVersion: string };
      claims: Array<{ claimId: string }>;
    }>(`/api/v1/rooms/${created.body.roomId}/onboarding`, {
      headers: { cookie },
    });
    expect(hostView.status).toBe(200);
    expect(hostView.body.claims).toHaveLength(1);

    const approved = await api.request<{ status: string }>(
      `/api/v1/rooms/${created.body.roomId}/claims/${claim.body.claimId}`,
      {
        method: "PATCH",
        headers: { cookie, "content-type": "application/json" },
        body: JSON.stringify({
          expectedStateVersion: hostView.body.room.stateVersion,
          decision: "APPROVE",
        }),
      },
    );
    expect(approved.status).toBe(200);
    expect(approved.body.status).toBe("ACTIVE");

    const playerView = await api.request<{ actor: string }>(
      `/api/v1/rooms/${created.body.roomId}/onboarding`,
      { headers: { cookie: playerCookie } },
    );
    expect(playerView.status).toBe(200);
    expect(playerView.body.actor).toBe("PLAYER");

    const recoveryToken = decodeURIComponent(
      created.body.recoveryPath.split("#token=")[1] ?? "",
    );
    const recoveryCookie = await startGuestSession(api);
    const recovered = await api.request<{
      roomId: string;
      recoveryPath: string;
    }>("/api/v1/host-recovery", {
      method: "POST",
      headers: {
        cookie: recoveryCookie,
        "content-type": "application/json",
      },
      body: JSON.stringify({ token: recoveryToken }),
    });
    expect(recovered.status).toBe(200);
    expect(recovered.body.roomId).toBe(created.body.roomId);
    expect(recovered.body.recoveryPath).toContain("#token=");

    const oldHostView = await api.request(
      `/api/v1/rooms/${created.body.roomId}/onboarding`,
      { headers: { cookie } },
    );
    expect(oldHostView.status).toBe(403);
    const recoveredHostView = await api.request<{ actor: string }>(
      `/api/v1/rooms/${created.body.roomId}/onboarding`,
      { headers: { cookie: recoveryCookie } },
    );
    expect(recoveredHostView.status).toBe(200);
    expect(recoveredHostView.body.actor).toBe("GAME_MASTER");
  });
});
