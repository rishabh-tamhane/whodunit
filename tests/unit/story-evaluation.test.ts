import { describe, expect, it } from "vitest";

import { STORY_EVALUATION_CORPUS } from "@/modules/generation/fixtures";
import { evaluateStory } from "@/modules/generation/evaluation";

describe("story evaluation rubric", () => {
  it("gates every fixed party-size and awareness scenario", () => {
    for (const fixture of STORY_EVALUATION_CORPUS) {
      expect(
        evaluateStory(fixture.story, fixture.context, {
          latencyMs: 120_000,
          inputTokens: 8_000,
          outputTokens: 16_000,
          estimatedCostUsd: 1.5,
        }),
      ).toMatchObject({ passed: true, total: 100 });
    }
  });

  it("fails an adversarial raw-description overlap regression", () => {
    const fixture = structuredClone(STORY_EVALUATION_CORPUS[0]!);
    const context = {
      ...fixture.context,
      rawDescriptionTexts: [fixture.story.fullCaseNarrative],
    };
    const result = evaluateStory(fixture.story, context, {
      latencyMs: 120_000,
      inputTokens: 8_000,
      outputTokens: 16_000,
      estimatedCostUsd: 1.5,
    });
    expect(result.passed).toBe(false);
    expect(result.scores.rawInputNonCopying).toBe(0);
  });
});
