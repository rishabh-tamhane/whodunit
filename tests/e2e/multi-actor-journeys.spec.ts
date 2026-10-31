import { randomUUID } from "node:crypto";

import {
  expect,
  test,
  type Browser,
  type BrowserContext,
} from "@playwright/test";

type JsonRecord = Record<string, unknown>;
type Scenario = Readonly<{
  name: string;
  playerCount: 4 | 12;
  durationMinutes: 30 | 120;
  murdererCount: 1 | 3;
  accompliceCount: 0 | 2;
  murdererAware: boolean;
  exerciseRecovery: boolean;
}>;

const scenarios: readonly Scenario[] = [
  {
    name: "four players with an aware murderer",
    playerCount: 4,
    durationMinutes: 30,
    murdererCount: 1,
    accompliceCount: 0,
    murdererAware: true,
    exerciseRecovery: true,
  },
  {
    name: "twelve players with unaware murderers and accomplices",
    playerCount: 12,
    durationMinutes: 120,
    murdererCount: 3,
    accompliceCount: 2,
    murdererAware: false,
    exerciseRecovery: false,
  },
];

const names = [
  "Aarav",
  "Aarav",
  "Isha",
  "Kabir",
  "Meera",
  "Nikhil",
  "Priya",
  "Rahul",
  "Saanvi",
  "Vihaan",
  "Zoya",
  "ऋतु चट्टोपाध्याय-श्रीनिवासन 🎃",
] as const;
const costumes = [
  "Pirate",
  "Vampire",
  "Ghost",
  "Detective",
  "Witch",
  "Robot",
  "Astronaut",
  "Magician",
  "Knight",
  "Scientist",
  "Phantom",
  "Explorer",
] as const;

function baseUrl(): string {
  const value = process.env.E2E_BASE_URL;
  if (!value) throw new Error("E2E_BASE_URL is required.");
  return value;
}

async function expectNoHorizontalPageOverflow(
  page: Awaited<ReturnType<BrowserContext["newPage"]>>,
) {
  const metrics = await page.evaluate(() => {
    const clientWidth = document.documentElement.clientWidth;
    const offenders = Array.from(document.querySelectorAll("body *"))
      .filter(
        (element) => element.getBoundingClientRect().right > clientWidth + 1,
      )
      .slice(0, 5)
      .map((element) => ({
        className: element.getAttribute("class") ?? "",
        right: Math.round(element.getBoundingClientRect().right),
        tag: element.tagName,
      }));
    return {
      clientWidth,
      offenders,
      scrollWidth: document.documentElement.scrollWidth,
    };
  });
  expect(
    metrics.scrollWidth,
    `Horizontal overflow offenders: ${JSON.stringify(metrics.offenders)}`,
  ).toBeLessThanOrEqual(metrics.clientWidth + 1);
}

async function api<T extends JsonRecord>(
  context: BrowserContext,
  method: string,
  path: string,
  data: JsonRecord | undefined,
  expectedStatus: number | readonly number[] = 200,
): Promise<T> {
  const response = await context.request.fetch(
    new URL(path, baseUrl()).toString(),
    {
      method,
      data,
      failOnStatusCode: false,
    },
  );
  const text = await response.text();
  const statuses = Array.isArray(expectedStatus)
    ? expectedStatus
    : [expectedStatus];
  expect(
    statuses,
    `${method} ${path} returned ${response.status()}: ${text}`,
  ).toContain(response.status());
  return (text ? JSON.parse(text) : {}) as T;
}

async function actorContext(
  browser: Browser,
  ordinal: number,
): Promise<BrowserContext> {
  const context = await browser.newContext({
    extraHTTPHeaders: { "x-forwarded-for": `198.51.100.${ordinal}` },
  });
  await api(context, "POST", "/api/v1/session", undefined, [200, 201]);
  return context;
}

async function onboarding(context: BrowserContext, roomId: string) {
  return api<{
    actor: string;
    room: { stateVersion: string; status: string };
    players?: Array<JsonRecord>;
    claims?: Array<JsonRecord>;
    readiness?: JsonRecord;
    self?: { playerId: string };
  }>(context, "GET", `/api/v1/rooms/${roomId}/onboarding`, undefined);
}

async function actorView(context: BrowserContext, roomId: string) {
  return api<{
    actor: "GAME_MASTER" | "PLAYER";
    room: {
      stateVersion: string;
      status: string;
      completedAt?: string | null;
      expiresAt?: string | null;
    };
    self?: { playerId: string };
    claims?: Array<JsonRecord>;
    story?: {
      package: JsonRecord;
      solution: { canonicalSolution: JsonRecord };
    };
    dossier?: JsonRecord;
    submittedState?: JsonRecord;
    results?: JsonRecord;
    reveal?: JsonRecord;
  }>(context, "GET", `/api/v1/rooms/${roomId}/view`, undefined);
}

function hasKey(value: unknown, forbidden: ReadonlySet<string>): boolean {
  if (Array.isArray(value))
    return value.some((item) => hasKey(item, forbidden));
  if (!value || typeof value !== "object") return false;
  return Object.entries(value).some(
    ([key, item]) => forbidden.has(key) || hasKey(item, forbidden),
  );
}

async function runJourney(browser: Browser, scenario: Scenario): Promise<void> {
  const contexts: BrowserContext[] = [];
  const createActor = async (ordinal: number) => {
    const context = await actorContext(browser, ordinal);
    contexts.push(context);
    return context;
  };

  try {
    let host = await createActor(scenario.playerCount === 4 ? 10 : 110);
    const created = await api<{
      roomId: string;
      roomCode: string;
      stateVersion: string;
      recoveryPath: string;
    }>(host, "POST", "/api/v1/rooms", undefined, 201);
    const roomId = created.roomId;

    const configured = await api<{ stateVersion: string }>(
      host,
      "PUT",
      `/api/v1/rooms/${roomId}/configuration`,
      {
        expectedStateVersion: created.stateVersion,
        configuration: {
          durationProfileVersion: "duration-v1",
          factionProfileVersion: "factions-v1",
          durationMinutes: scenario.durationMinutes,
          murdererCount: scenario.murdererCount,
          accompliceCount: scenario.accompliceCount,
          innocentCount:
            scenario.playerCount -
            scenario.murdererCount -
            scenario.accompliceCount,
          murdererAware: scenario.murdererAware,
          playerSlots: names
            .slice(0, scenario.playerCount)
            .map((displayName, index) => ({
              displayName,
              costume: costumes[index],
            })),
        },
      },
    );
    await api(host, "POST", `/api/v1/rooms/${roomId}/open-lobby`, {
      expectedStateVersion: configured.stateVersion,
    });

    const players: BrowserContext[] = [];
    const playerIds: string[] = [];
    const claimIds: string[] = [];
    for (let index = 0; index < scenario.playerCount; index += 1) {
      const player = await createActor(
        (scenario.playerCount === 4 ? 20 : 120) + index,
      );
      players.push(player);
      const lobby = await api<{
        roomId: string;
        slots: Array<{
          playerId: string;
          seatOrder: number;
          displayName: string;
          slotStatus: string;
        }>;
      }>(player, "POST", "/api/v1/lobbies/lookup", {
        roomCode: created.roomCode,
      });
      const slot = lobby.slots.find(
        (candidate) => candidate.seatOrder === index + 1,
      );
      expect(slot, `Seat ${index} must exist`).toBeDefined();
      if (!slot) throw new Error(`Seat ${index} was not returned.`);
      expect(slot.displayName).toBe(names[index]);
      const claim = await api<{ claimId: string }>(
        player,
        "POST",
        `/api/v1/rooms/${roomId}/claims`,
        { playerId: slot.playerId, requestKind: "INITIAL_CLAIM" },
        201,
      );
      playerIds.push(slot.playerId);
      claimIds.push(claim.claimId);
    }

    for (const claimId of claimIds) {
      const current = await onboarding(host, roomId);
      await api(host, "PATCH", `/api/v1/rooms/${roomId}/claims/${claimId}`, {
        expectedStateVersion: current.room.stateVersion,
        decision: "APPROVE",
      });
    }

    if (scenario.exerciseRecovery) {
      const replacement = await createActor(40);
      const lobby = await api<{
        slots: Array<{ playerId: string; slotStatus: string }>;
      }>(replacement, "POST", "/api/v1/lobbies/lookup", {
        roomCode: created.roomCode,
      });
      const occupied = lobby.slots.find(
        (slot) => slot.playerId === playerIds[0],
      );
      expect(occupied?.slotStatus).toBe("OCCUPIED");
      const reconnect = await api<{ claimId: string }>(
        replacement,
        "POST",
        `/api/v1/rooms/${roomId}/claims`,
        { playerId: playerIds[0], requestKind: "RECONNECT" },
        201,
      );
      const current = await onboarding(host, roomId);
      await api(
        host,
        "PATCH",
        `/api/v1/rooms/${roomId}/claims/${reconnect.claimId}`,
        {
          expectedStateVersion: current.room.stateVersion,
          decision: "APPROVE",
        },
      );
      await api(
        players[0]!,
        "GET",
        `/api/v1/rooms/${roomId}/onboarding`,
        undefined,
        403,
      );
      players[0] = replacement;

      const recoveredHost = await createActor(41);
      const recoveryToken = decodeURIComponent(
        created.recoveryPath.split("#token=")[1] ?? "",
      );
      await api(recoveredHost, "POST", "/api/v1/host-recovery", {
        token: recoveryToken,
      });
      await api(
        host,
        "GET",
        `/api/v1/rooms/${roomId}/onboarding`,
        undefined,
        403,
      );
      host = recoveredHost;
    }

    let currentHost = await onboarding(host, roomId);
    await api(host, "POST", `/api/v1/rooms/${roomId}/consent`, {
      expectedStateVersion: currentHost.room.stateVersion,
    });
    currentHost = await onboarding(host, roomId);
    await api(host, "POST", `/api/v1/rooms/${roomId}/acknowledgements/host`, {
      expectedStateVersion: currentHost.room.stateVersion,
    });

    for (const player of players) {
      const current = await onboarding(player, roomId);
      expect(current.actor).toBe("PLAYER");
      await api(
        player,
        "POST",
        `/api/v1/rooms/${roomId}/acknowledgements/player`,
        {
          expectedStateVersion: current.room.stateVersion,
        },
      );
    }

    const privateMarkers: string[] = [];
    for (let authorIndex = 0; authorIndex < players.length; authorIndex += 1) {
      for (
        let subjectIndex = 0;
        subjectIndex < playerIds.length;
        subjectIndex += 1
      ) {
        if (authorIndex === subjectIndex) continue;
        const marker = `PRIVATE-E2E-${scenario.playerCount}-${authorIndex}-${subjectIndex}`;
        privateMarkers.push(marker);
        const current = await onboarding(players[authorIndex]!, roomId);
        await api(
          players[authorIndex]!,
          "PUT",
          `/api/v1/rooms/${roomId}/descriptions`,
          {
            expectedStateVersion: current.room.stateVersion,
            subjectPlayerId: playerIds[subjectIndex],
            responseStatus: "SUBMITTED",
            descriptionText: `${marker}: calm, observant, and fond of harmless puzzles.`,
          },
        );
      }
    }

    currentHost = await onboarding(host, roomId);
    expect(currentHost.readiness?.ready).toBe(true);
    await api(
      host,
      "POST",
      `/api/v1/rooms/${roomId}/generation`,
      {
        expectedStateVersion: currentHost.room.stateVersion,
        idempotencyKey: randomUUID(),
      },
      202,
    );

    let generation: {
      locked: boolean;
      roomStatus: string;
      job: { status: string; sanitizedErrorCode: string | null } | null;
    } | null = null;
    for (let attempt = 0; attempt < 10; attempt += 1) {
      generation = await api(
        host,
        "GET",
        `/api/v1/rooms/${roomId}/generation`,
        undefined,
      );
      if (generation.locked || generation.job?.status === "FAILED") break;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    expect(generation?.job?.sanitizedErrorCode).toBeNull();
    expect(generation?.locked).toBe(true);
    expect(generation?.roomStatus).toBe("READY_TO_START");

    let hostView = await actorView(host, roomId);
    expect(hostView.actor).toBe("GAME_MASTER");
    expect(hostView.room.status).toBe("READY_TO_START");
    expect(hostView.story).toBeDefined();
    const storyPackage = hostView.story!.package as {
      murdererAware: boolean;
      solution: {
        murdererPlayerIds: string[];
        accomplicePlayerIds: string[];
        innocentPlayerIds: string[];
        motive: string;
        method: string;
      };
    };
    expect(storyPackage.murdererAware).toBe(scenario.murdererAware);
    expect(storyPackage.solution.murdererPlayerIds).toHaveLength(
      scenario.murdererCount,
    );
    expect(storyPackage.solution.accomplicePlayerIds).toHaveLength(
      scenario.accompliceCount,
    );
    const hostSerialization = JSON.stringify(hostView);
    for (const marker of privateMarkers)
      expect(hostSerialization).not.toContain(marker);

    for (let index = 0; index < players.length; index += 1) {
      const view = await actorView(players[index]!, roomId);
      expect(view.actor).toBe("PLAYER");
      expect(view.self?.playerId).toBe(playerIds[index]);
      expect(view.dossier).toBeDefined();
      expect(hasKey(view, new Set(["solution", "canonicalSolution"]))).toBe(
        false,
      );
      const serialization = JSON.stringify(view);
      for (const marker of privateMarkers)
        expect(serialization).not.toContain(marker);
      if (storyPackage.solution.murdererPlayerIds.includes(playerIds[index]!)) {
        expect((view.dossier as { faction?: string }).faction).toBe(
          scenario.murdererAware ? "MURDERER" : undefined,
        );
        if (!scenario.murdererAware)
          expect(hasKey(view.dossier, new Set(["faction"]))).toBe(false);
      }
    }

    const browserErrors: string[] = [];
    const captureBrowserErrors = (
      page: Awaited<ReturnType<BrowserContext["newPage"]>>,
    ) => {
      page.on("pageerror", (error) => browserErrors.push(error.message));
      page.on("console", (message) => {
        if (
          message.type() === "error" &&
          /hydration failed|state update|router action/i.test(message.text())
        )
          browserErrors.push(message.text());
      });
    };
    const hostPage = await host.newPage();
    captureBrowserErrors(hostPage);
    await hostPage.goto(`/host/rooms/${roomId}`);
    await expect(
      hostPage.getByRole("heading", {
        name: "Canonical solution — Game Master only",
      }),
    ).toBeVisible();
    if (scenario.playerCount === 12) {
      await expect(
        hostPage.getByText(names[11], { exact: false }).first(),
      ).toBeVisible();
    }
    await hostPage.setViewportSize({ width: 360, height: 640 });
    await expectNoHorizontalPageOverflow(hostPage);
    const playerPage = await players[0]!.newPage();
    captureBrowserErrors(playerPage);
    await playerPage.goto(`/room/${roomId}`);
    await expect(
      playerPage.getByRole("heading", { name: "Private dossier" }),
    ).toBeVisible();
    await expect(
      playerPage.getByText("Canonical solution — Game Master only"),
    ).toHaveCount(0);
    await playerPage.setViewportSize({ width: 360, height: 640 });
    await expectNoHorizontalPageOverflow(playerPage);

    await api(host, "POST", `/api/v1/rooms/${roomId}/commands/start`, {
      expectedStateVersion: hostView.room.stateVersion,
      idempotencyKey: randomUUID(),
    });

    const theoryView = await actorView(players.at(-1)!, roomId);
    const theory = await api<JsonRecord>(
      players.at(-1)!,
      "POST",
      `/api/v1/rooms/${roomId}/theories`,
      {
        expectedStateVersion: theoryView.room.stateVersion,
        idempotencyKey: randomUUID(),
        structuredClaim: {
          suspects: [
            {
              playerId: storyPackage.solution.innocentPlayerIds[0],
              suspectedRole: "MURDERER",
            },
          ],
          evidenceIds: [],
        },
        submittedExplanation: "An early suspicion, not a confirmed identity.",
      },
      201,
    );
    expect(theory.correctness ?? null).toBeNull();
    hostView = await actorView(host, roomId);
    expect(hostView.room.status).toBe("IN_PROGRESS");
    expect(
      hostView.claims?.filter((claim) => claim.status === "ACTIVE"),
    ).toHaveLength(scenario.playerCount);

    await api(host, "POST", `/api/v1/rooms/${roomId}/early-verdict`, {
      expectedStateVersion: hostView.room.stateVersion,
      idempotencyKey: randomUUID(),
    });

    for (let index = 0; index < players.length; index += 1) {
      const view = await actorView(players[index]!, roomId);
      expect(view.room.status).toBe("FINAL_ACCUSATIONS");
      const correct = index === 0;
      await api(players[index]!, "PUT", `/api/v1/rooms/${roomId}/accusations`, {
        expectedRevision: 0,
        structuredCase: {
          murdererPlayerIds: correct
            ? storyPackage.solution.murdererPlayerIds
            : [storyPackage.solution.innocentPlayerIds[0]],
          accomplicePlayerIds: correct
            ? storyPackage.solution.accomplicePlayerIds
            : [],
          motive: correct
            ? storyPackage.solution.motive
            : "A harmless false motive",
          method: correct
            ? storyPackage.solution.method
            : "A harmless false method",
          evidenceIds: [],
        },
        explanationText: `Final case submitted by seat ${index + 1}.`,
      });
      const afterSave = await actorView(players[index]!, roomId);
      await api(
        players[index]!,
        "POST",
        `/api/v1/rooms/${roomId}/accusations`,
        {
          expectedStateVersion: afterSave.room.stateVersion,
          idempotencyKey: randomUUID(),
        },
      );
    }

    hostView = await actorView(host, roomId);
    const submitted = hostView.submittedState?.finalAccusations;
    expect(Array.isArray(submitted) ? submitted : []).toHaveLength(
      scenario.playerCount,
    );
    const closed = await api<{
      scoringSnapshotId?: string;
      submissionCount?: number;
    }>(host, "POST", `/api/v1/rooms/${roomId}/accusations/close`, {
      expectedStateVersion: hostView.room.stateVersion,
      idempotencyKey: randomUUID(),
      confirmedMissingPlayerIds: [],
      confirmZeroSubmissions: false,
    });
    expect(closed.scoringSnapshotId).toMatch(/[0-9a-f-]{36}/i);
    expect(closed.submissionCount).toBe(scenario.playerCount);

    hostView = await actorView(host, roomId);
    await api(host, "POST", `/api/v1/rooms/${roomId}/reveal/publish`, {
      expectedStateVersion: hostView.room.stateVersion,
      idempotencyKey: randomUUID(),
    });
    const revealed = await actorView(players[0]!, roomId);
    expect(revealed.room.status).toBe("REVEAL");
    expect(revealed.reveal).toBeDefined();
    expect(
      (revealed.reveal as { solution?: { canonicalSolution?: JsonRecord } })
        .solution?.canonicalSolution,
    ).toMatchObject({
      murdererPlayerIds: storyPackage.solution.murdererPlayerIds,
      accomplicePlayerIds: storyPackage.solution.accomplicePlayerIds,
    });

    hostView = await actorView(host, roomId);
    const completed = await api<{
      completedAt: string;
      expiresAt: string;
      caseFileId: string;
    }>(host, "POST", `/api/v1/rooms/${roomId}/completion`, {
      expectedStateVersion: hostView.room.stateVersion,
      idempotencyKey: randomUUID(),
    });
    expect(completed.caseFileId).toMatch(/[0-9a-f-]{36}/i);
    expect(
      new Date(completed.expiresAt).getTime() -
        new Date(completed.completedAt).getTime(),
    ).toBe(30 * 24 * 60 * 60 * 1_000);
    const completedView = await actorView(host, roomId);
    expect(completedView.room.status).toBe("COMPLETED");
    expect(completedView.results?.caseFile).toBeDefined();
    expect(browserErrors).toEqual([]);
  } finally {
    await Promise.allSettled(contexts.map((context) => context.close()));
  }
}

test.describe("isolated multi-actor journeys", () => {
  for (const scenario of scenarios) {
    test(scenario.name, async ({ browser }) => runJourney(browser, scenario));
  }
});
