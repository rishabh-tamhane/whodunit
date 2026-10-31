import { describe, expect, it } from "vitest";

import { createApiTestClient } from "../support/api-client";
import { getIntegrationEnv } from "../support/integration-env";

type Api = ReturnType<typeof createApiTestClient>;

function cookieHeader(headers: Headers) {
  return headers
    .getSetCookie()
    .map((cookie) => cookie.split(";", 1)[0])
    .join("; ");
}

async function startGuestSession(api: Api) {
  const response = await api.request<{ status: string }>("/api/v1/session", {
    method: "POST",
  });
  expect(response.status).toBe(201);
  return cookieHeader(response.headers);
}

async function createRoom(api: Api, hostCookie: string) {
  const response = await api.request<{
    roomId: string;
    roomCode: string;
    stateVersion: string;
    recoveryPath: string;
  }>("/api/v1/rooms", {
    method: "POST",
    headers: { cookie: hostCookie },
  });
  expect(response.status).toBe(201);
  return {
    ...response.body,
    recoveryToken: decodeURIComponent(
      response.body.recoveryPath.split("#token=")[1] ?? "",
    ),
  };
}

const configuration = {
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
} as const;

async function openLobby(api: Api, hostCookie: string) {
  const created = await createRoom(api, hostCookie);
  const configured = await api.request<{
    stateVersion: string;
  }>(`/api/v1/rooms/${created.roomId}/configuration`, {
    method: "PUT",
    headers: { cookie: hostCookie, "content-type": "application/json" },
    body: JSON.stringify({
      expectedStateVersion: created.stateVersion,
      configuration,
    }),
  });
  expect(configured.status).toBe(200);
  const opened = await api.request<{ stateVersion: string }>(
    `/api/v1/rooms/${created.roomId}/open-lobby`,
    {
      method: "POST",
      headers: { cookie: hostCookie, "content-type": "application/json" },
      body: JSON.stringify({
        expectedStateVersion: configured.body.stateVersion,
      }),
    },
  );
  expect(opened.status).toBe(200);
  const hostView = await getHostView(api, created.roomId, hostCookie);
  return { ...created, hostView };
}

async function getHostView(api: Api, roomId: string, cookie: string) {
  const response = await api.request<{
    actor: "GAME_MASTER";
    room: { stateVersion: string };
    players: Array<{
      playerId: string;
      claimStatus: string;
      activeMembershipId?: string;
    }>;
    claims: Array<{
      claimId: string;
      playerId: string;
      requestKind: string;
    }>;
  }>(`/api/v1/rooms/${roomId}/onboarding`, {
    headers: { cookie },
  });
  expect(response.status).toBe(200);
  return response.body;
}

async function requestClaim(
  api: Api,
  roomId: string,
  playerId: string,
  cookie: string,
  requestKind: "INITIAL_CLAIM" | "RECONNECT",
) {
  return api.request<{ claimId: string; status: string }>(
    `/api/v1/rooms/${roomId}/claims`,
    {
      method: "POST",
      headers: { cookie, "content-type": "application/json" },
      body: JSON.stringify({ playerId, requestKind }),
    },
  );
}

describe("serialized identity and command races", () => {
  it("allows exactly one contender to consume a host recovery credential", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);
    const oldHostCookie = await startGuestSession(api);
    const room = await createRoom(api, oldHostCookie);
    const contenderCookies = await Promise.all([
      startGuestSession(api),
      startGuestSession(api),
    ]);

    const results = await Promise.all(
      contenderCookies.map((cookie) =>
        api.request<{ roomId?: string }>("/api/v1/host-recovery", {
          method: "POST",
          headers: { cookie, "content-type": "application/json" },
          body: JSON.stringify({ token: room.recoveryToken }),
        }),
      ),
    );

    expect(results.map((result) => result.status).sort()).toEqual([200, 404]);
    const winnerIndex = results.findIndex((result) => result.status === 200);
    const loserIndex = winnerIndex === 0 ? 1 : 0;
    expect(results[winnerIndex]?.body.roomId).toBe(room.roomId);

    const oldHostView = await api.request(
      `/api/v1/rooms/${room.roomId}/onboarding`,
      { headers: { cookie: oldHostCookie } },
    );
    const loserView = await api.request(
      `/api/v1/rooms/${room.roomId}/onboarding`,
      { headers: { cookie: contenderCookies[loserIndex]! } },
    );
    const winnerView = await api.request<{ actor: string }>(
      `/api/v1/rooms/${room.roomId}/onboarding`,
      { headers: { cookie: contenderCookies[winnerIndex]! } },
    );
    expect(oldHostView.status).toBe(403);
    expect(loserView.status).toBe(403);
    expect(winnerView.status).toBe(200);
    expect(winnerView.body.actor).toBe("GAME_MASTER");
  });

  it("serializes recovery against an old-host mutation", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);
    const oldHostCookie = await startGuestSession(api);
    const room = await createRoom(api, oldHostCookie);
    const newHostCookie = await startGuestSession(api);

    const [command, recovery] = await Promise.all([
      api.request(`/api/v1/rooms/${room.roomId}/configuration`, {
        method: "PUT",
        headers: {
          cookie: oldHostCookie,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          expectedStateVersion: room.stateVersion,
          configuration,
        }),
      }),
      api.request<{ roomId?: string }>("/api/v1/host-recovery", {
        method: "POST",
        headers: {
          cookie: newHostCookie,
          "content-type": "application/json",
        },
        body: JSON.stringify({ token: room.recoveryToken }),
      }),
    ]);

    expect(recovery.status).toBe(200);
    expect([200, 403]).toContain(command.status);
    const oldHostAfter = await api.request(
      `/api/v1/rooms/${room.roomId}/onboarding`,
      { headers: { cookie: oldHostCookie } },
    );
    const newHostAfter = await api.request<{ actor: string }>(
      `/api/v1/rooms/${room.roomId}/onboarding`,
      { headers: { cookie: newHostCookie } },
    );
    expect(oldHostAfter.status).toBe(403);
    expect(newHostAfter.status).toBe(200);
    expect(newHostAfter.body.actor).toBe("GAME_MASTER");
  });

  it("prevents one principal from winning both a player claim and host recovery", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);
    const hostCookie = await startGuestSession(api);
    const room = await openLobby(api, hostCookie);
    const contenderCookie = await startGuestSession(api);
    const playerId = room.hostView.players[0]!.playerId;

    const [claim, recovery] = await Promise.all([
      requestClaim(
        api,
        room.roomId,
        playerId,
        contenderCookie,
        "INITIAL_CLAIM",
      ),
      api.request<{ roomId?: string }>("/api/v1/host-recovery", {
        method: "POST",
        headers: {
          cookie: contenderCookie,
          "content-type": "application/json",
        },
        body: JSON.stringify({ token: room.recoveryToken }),
      }),
    ]);

    expect(Number(claim.status === 201) + Number(recovery.status === 200)).toBe(
      1,
    );
    if (recovery.status === 200) {
      expect(claim.status).toBe(403);
      const view = await api.request<{ actor: string }>(
        `/api/v1/rooms/${room.roomId}/onboarding`,
        { headers: { cookie: contenderCookie } },
      );
      expect(view.body.actor).toBe("GAME_MASTER");
    } else {
      expect(claim.status).toBe(201);
      expect(recovery.status).toBe(404);
      const view = await api.request<{ actor: string }>(
        `/api/v1/rooms/${room.roomId}/onboarding`,
        { headers: { cookie: contenderCookie } },
      );
      expect(view.body.actor).toBe("PENDING_PLAYER");
    }
  });

  it("gives duplicate approval and reconnect-versus-revoke races one winner", async () => {
    const api = createApiTestClient(getIntegrationEnv().TEST_APP_BASE_URL);
    const hostCookie = await startGuestSession(api);
    const room = await openLobby(api, hostCookie);
    const playerId = room.hostView.players[0]!.playerId;
    const originalCookie = await startGuestSession(api);
    const initialClaim = await requestClaim(
      api,
      room.roomId,
      playerId,
      originalCookie,
      "INITIAL_CLAIM",
    );
    expect(initialClaim.status).toBe(201);
    const initialReviewView = await getHostView(api, room.roomId, hostCookie);
    const approveInitial = () =>
      api.request(
        `/api/v1/rooms/${room.roomId}/claims/${initialClaim.body.claimId}`,
        {
          method: "PATCH",
          headers: { cookie: hostCookie, "content-type": "application/json" },
          body: JSON.stringify({
            expectedStateVersion: initialReviewView.room.stateVersion,
            decision: "APPROVE",
          }),
        },
      );
    const duplicateResults = await Promise.all([
      approveInitial(),
      approveInitial(),
    ]);
    expect(
      duplicateResults.map((result) => result.status).sort((a, b) => a - b),
    ).toEqual([200, 409]);

    const replacementCookie = await startGuestSession(api);
    const reconnectClaim = await requestClaim(
      api,
      room.roomId,
      playerId,
      replacementCookie,
      "RECONNECT",
    );
    expect(reconnectClaim.status).toBe(201);
    const raceView = await getHostView(api, room.roomId, hostCookie);
    const activeMembershipId = raceView.players.find(
      (player) => player.playerId === playerId,
    )?.activeMembershipId;
    expect(activeMembershipId).toBeTruthy();

    const [approveReconnect, revokeOriginal] = await Promise.all([
      api.request(
        `/api/v1/rooms/${room.roomId}/claims/${reconnectClaim.body.claimId}`,
        {
          method: "PATCH",
          headers: { cookie: hostCookie, "content-type": "application/json" },
          body: JSON.stringify({
            expectedStateVersion: raceView.room.stateVersion,
            decision: "APPROVE",
          }),
        },
      ),
      api.request(
        `/api/v1/rooms/${room.roomId}/memberships/${activeMembershipId}`,
        {
          method: "DELETE",
          headers: { cookie: hostCookie, "content-type": "application/json" },
          body: JSON.stringify({
            expectedStateVersion: raceView.room.stateVersion,
          }),
        },
      ),
    ]);
    expect(
      [approveReconnect.status, revokeOriginal.status].sort((a, b) => a - b),
    ).toEqual([200, 409]);

    const finalView = await getHostView(api, room.roomId, hostCookie);
    const finalPlayer = finalView.players.find(
      (player) => player.playerId === playerId,
    );
    if (approveReconnect.status === 200) {
      expect(finalPlayer?.claimStatus).toMatch(/CONNECTED|DISCONNECTED/);
      expect(finalPlayer?.activeMembershipId).toBe(reconnectClaim.body.claimId);
    } else {
      expect(finalPlayer?.claimStatus).toBe("PENDING");
      expect(finalView.claims).toHaveLength(1);
    }
  });
});
