import { beforeEach, describe, expect, it, vi } from "vitest";

import type { StoryPackage } from "@/contracts";
import { createStoryFixture } from "@/modules/generation/fixtures";
import type { StoryProviderResult } from "@/modules/generation/provider";

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  start: vi.fn(),
  retrieve: vi.fn(),
}));

vi.mock("@/lib/supabase/admin", () => ({
  callSupabaseAdminRpc: mocks.rpc,
}));
vi.mock("@/modules/generation/provider.server", () => ({
  getStoryProvider: () => ({
    start: mocks.start,
    retrieve: mocks.retrieve,
  }),
}));

import { advanceGenerationJob } from "@/modules/generation/orchestrator.server";

const fixture = createStoryFixture(4);
const roomId = "00000000-0000-4000-8000-000000000001";
const jobId = "00000000-0000-4000-8000-000000000002";
const snapshot = {
  snapshotVersion: "generation-snapshot-v1" as const,
  roomId,
  stateVersion: "12",
  capturedAt: "2026-10-30T12:00:00.000Z",
  configuration: {
    durationProfileVersion: "duration-v1" as const,
    durationMinutes: 30 as const,
    roundCount: 2,
    scoringProfileVersion: "scoring-v1",
    murdererCount: 1,
    accompliceCount: 0,
    innocentCount: 3,
    murdererAware: true,
  },
  players: fixture.story.characters.map((character) => ({
    playerId: character.playerId,
    displayName: character.displayName,
    costume: character.costume,
    hostBackground: null,
  })),
  descriptionResponses: [],
};

function claim(providerResponseIds: Record<string, string> = {}) {
  return {
    jobId,
    roomId,
    inputSnapshot: snapshot,
    modelId: "gpt-6.1-sol",
    escalationModelId: "gpt-6-astra",
    attemptCount: 1,
    repairCount: 0,
    escalationCount: 0,
    providerResponseIds,
  };
}

function result(
  story: StoryPackage | null,
  status: StoryProviderResult["status"] = "COMPLETED",
): StoryProviderResult {
  return {
    providerResponseId: crypto.randomUUID(),
    status,
    modelId: "gpt-6.1-sol",
    story,
    inputTokens: 100,
    outputTokens: 200,
    errorCode: status === "FAILED" ? "PROVIDER_FAILED" : null,
  };
}

function invalidStory() {
  const story = structuredClone(fixture.story);
  story.victim.id = story.characters[0]!.playerId;
  return story;
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.rpc.mockImplementation(async (name: string) => {
    if (name === "claim_generation_job") return { data: claim(), error: null };
    return { data: {}, error: null };
  });
});

describe("durable generation orchestration", () => {
  it("locks one valid provider package", async () => {
    mocks.start.mockResolvedValueOnce(result(fixture.story));
    await advanceGenerationJob(jobId);
    expect(mocks.start).toHaveBeenCalledOnce();
    expect(
      mocks.rpc.mock.calls.filter(([name]) => name === "lock_generated_story"),
    ).toHaveLength(1);
    expect(
      mocks.rpc.mock.calls.filter(([name]) => name === "fail_generation_job"),
    ).toHaveLength(0);
  });

  it("repairs invalid output and locks only the replacement package", async () => {
    mocks.start
      .mockResolvedValueOnce(result(invalidStory()))
      .mockResolvedValueOnce(result(fixture.story));
    await advanceGenerationJob(jobId);
    expect(mocks.start).toHaveBeenCalledTimes(2);
    expect(mocks.start.mock.calls.map(([input]) => input.modelId)).toEqual([
      "gpt-6.1-sol",
      "gpt-6.1-sol",
    ]);
    expect(
      mocks.rpc.mock.calls.filter(([name]) => name === "lock_generated_story"),
    ).toHaveLength(1);
  });

  it("uses the escalation model only after two bounded repairs", async () => {
    mocks.start
      .mockResolvedValueOnce(result(invalidStory()))
      .mockResolvedValueOnce(result(invalidStory()))
      .mockResolvedValueOnce(result(invalidStory()))
      .mockResolvedValueOnce(result(fixture.story));
    await advanceGenerationJob(jobId);
    expect(mocks.start.mock.calls.map(([input]) => input.modelId)).toEqual([
      "gpt-6.1-sol",
      "gpt-6.1-sol",
      "gpt-6.1-sol",
      "gpt-6-astra",
    ]);
    expect(
      mocks.rpc.mock.calls.filter(([name]) => name === "lock_generated_story"),
    ).toHaveLength(1);
  });

  it("fails safely after a terminal provider response", async () => {
    mocks.start.mockResolvedValueOnce(result(null, "FAILED"));
    await advanceGenerationJob(jobId);
    expect(
      mocks.rpc.mock.calls.filter(([name]) => name === "fail_generation_job"),
    ).toHaveLength(1);
    expect(
      mocks.rpc.mock.calls.filter(([name]) => name === "lock_generated_story"),
    ).toHaveLength(0);
  });

  it("releases queued work and later retrieves its durable provider response", async () => {
    mocks.rpc.mockImplementation(async (name: string) => {
      if (name === "claim_generation_job")
        return {
          data: claim({ story: "resp-durable-1" }),
          error: null,
        };
      return { data: {}, error: null };
    });
    mocks.retrieve.mockResolvedValueOnce(result(null, "RUNNING"));
    await advanceGenerationJob(jobId);
    expect(mocks.start).not.toHaveBeenCalled();
    expect(mocks.retrieve).toHaveBeenCalledWith("resp-durable-1");
    expect(
      mocks.rpc.mock.calls.filter(
        ([name]) => name === "release_generation_lease",
      ),
    ).toHaveLength(1);
  });
});
