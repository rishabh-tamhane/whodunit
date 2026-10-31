import { describe, expect, it } from "vitest";

import {
  STORY_PACKAGE_JSON_SCHEMA,
  StoryPackageSchema,
  canonicalSerialize,
  checksumStoryPackage,
} from "@/contracts";
import {
  createStoryFixture,
  STORY_EVALUATION_CORPUS,
} from "@/modules/generation/fixtures";
import { validateStoryPackage } from "@/modules/generation/validators";

describe("StoryPackage", () => {
  it("accepts the fixed 4–12 player corpus in both awareness modes", () => {
    for (const fixture of STORY_EVALUATION_CORPUS) {
      expect(StoryPackageSchema.safeParse(fixture.story).success).toBe(true);
      expect(validateStoryPackage(fixture.story, fixture.context)).toEqual([]);
    }
  });

  it("publishes a strict JSON Schema", () => {
    expect(STORY_PACKAGE_JSON_SCHEMA).toMatchObject({
      type: "object",
      additionalProperties: false,
    });
  });

  it("rejects unknown model fields", () => {
    const { story } = createStoryFixture(4);
    expect(
      StoryPackageSchema.safeParse({
        ...story,
        authUserId: crypto.randomUUID(),
      }).success,
    ).toBe(false);
  });

  it("serializes independent of object insertion order and checksums deterministically", async () => {
    const { story } = createStoryFixture(4);
    expect(canonicalSerialize({ b: 2, a: { d: 4, c: 3 } })).toBe(
      '{"a":{"c":3,"d":4},"b":2}',
    );
    await expect(checksumStoryPackage(story)).resolves.toMatch(
      /^[a-f0-9]{64}$/,
    );
    await expect(checksumStoryPackage(story)).resolves.toBe(
      await checksumStoryPackage(story),
    );
  });
});

describe("deterministic validators", () => {
  it("reports invented players and a player victim", () => {
    const fixture = createStoryFixture(4);
    fixture.story.characters[0]!.playerId = crypto.randomUUID();
    fixture.story.victim.id = fixture.context.configuredPlayerIds[0]!;
    const categories = validateStoryPackage(fixture.story, fixture.context).map(
      (item) => item.category,
    );
    expect(categories).toContain("PLAYER_SET");
  });

  it("rejects a package that changes the configured scoring profile", () => {
    const fixture = createStoryFixture(4);
    fixture.story.scoringProfileVersion = "unknown-score-profile";
    expect(
      validateStoryPackage(fixture.story, fixture.context).map(
        (item) => item.category,
      ),
    ).toContain("STRUCTURE");
  });

  it("reports premature knowledge and impossible mission coverage", () => {
    const fixture = createStoryFixture(5, false);
    fixture.story.dossiers[0]!.knownMurdererPlayerIds = [
      fixture.story.solution.murdererPlayerIds[0]!,
    ];
    fixture.story.missions.pop();
    const categories = validateStoryPackage(fixture.story, fixture.context).map(
      (item) => item.category,
    );
    expect(categories).toContain("INFORMATION_FLOW");
    expect(categories).toContain("MISSION");
  });

  it("reports unsolvable evidence, unsafe motives, and copied raw input", () => {
    const fixture = createStoryFixture(4);
    fixture.story.evidence.forEach((item) => {
      item.provesPlayerIds = [];
    });
    fixture.story.solution.motive =
      "A caste grievance and debt were the motive.";
    fixture.context = {
      ...fixture.context,
      rawDescriptionTexts: [fixture.story.fullCaseNarrative],
    };
    const categories = validateStoryPackage(fixture.story, fixture.context).map(
      (item) => item.category,
    );
    expect(categories).toContain("SOLVABILITY");
    expect(categories).toContain("SAFETY");
    expect(categories).toContain("RAW_INPUT_COPY");
  });
});
