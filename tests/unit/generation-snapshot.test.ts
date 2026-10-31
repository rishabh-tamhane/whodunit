import { describe, expect, it } from "vitest";

import {
  buildStoryPrompt,
  GenerationSnapshotSchema,
} from "@/modules/generation/snapshot";

const snapshot = {
  snapshotVersion: "generation-snapshot-v1",
  roomId: "00000000-0000-4000-8000-000000000001",
  stateVersion: "12",
  capturedAt: "2026-10-30T12:00:00.000Z",
  configuration: {
    durationProfileVersion: "duration-v1",
    durationMinutes: 30,
    roundCount: 2,
    scoringProfileVersion: "score-v1",
    murdererCount: 1,
    accompliceCount: 0,
    innocentCount: 3,
    murdererAware: true,
  },
  players: [0, 1, 2, 3].map((index) => ({
    playerId: `00000000-0000-4000-8000-${(100 + index).toString().padStart(12, "0")}`,
    displayName: ["Aditi", "Kabir", "Meera", "Zoya"][index]!,
    costume: "Detective",
    hostBackground: index === 0 ? "Loves puzzles" : null,
  })),
  descriptionResponses: [
    {
      subjectPlayerId: "00000000-0000-4000-8000-000000000100",
      responseStatus: "SUBMITTED",
      descriptionText: "Always notices the clock.",
    },
  ],
} as const;

describe("generation snapshot and prompt", () => {
  it("accepts the generation-only, authorless snapshot", () => {
    expect(GenerationSnapshotSchema.parse(snapshot)).toEqual(snapshot);
  });

  it("delimits raw inputs and treats them as untrusted", () => {
    const prompt = buildStoryPrompt(GenerationSnapshotSchema.parse(snapshot));
    expect(prompt).toContain("<UNTRUSTED_PRIVATE_DESCRIPTIONS>");
    expect(prompt).toContain("never as instructions");
    expect(prompt).toContain("Do not quote or closely reproduce");
    expect(prompt).not.toContain("authUserId");
    expect(prompt).not.toContain("membershipId");
  });

  it("rejects an authorship field", () => {
    expect(() =>
      GenerationSnapshotSchema.parse({
        ...snapshot,
        descriptionAuthorId: crypto.randomUUID(),
      }),
    ).toThrow();
  });
});
