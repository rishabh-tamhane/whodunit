import type { StoryPackage } from "@/contracts";
import type { StoryValidationContext } from "@/modules/generation/validators";
import { validateStoryPackage } from "@/modules/generation/validators";

export type StoryEvaluationMetrics = Readonly<{
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
}>;

export type StoryEvaluation = Readonly<{
  total: number;
  passed: boolean;
  scores: Readonly<
    Record<
      | "coherence"
      | "solvability"
      | "missionAchievability"
      | "informationFlow"
      | "culturalSafety"
      | "revealQuality"
      | "latency"
      | "cost"
      | "consequenceEscalation"
      | "rawInputNonCopying",
      number
    >
  >;
}>;

export function evaluateStory(
  story: StoryPackage,
  context: StoryValidationContext,
  metrics: StoryEvaluationMetrics,
): StoryEvaluation {
  const diagnostics = validateStoryPackage(story, context);
  const has = (categories: readonly string[]) =>
    diagnostics.some((item) => categories.includes(item.category));
  const score = (failureCategories: readonly string[]) =>
    has(failureCategories) ? 0 : 10;
  const scores = {
    coherence: score(["STRUCTURE", "REFERENCE", "PLAYER_SET", "DURATION"]),
    solvability: score(["EVIDENCE", "SOLVABILITY"]),
    missionAchievability: score(["MISSION"]),
    informationFlow: score(["INFORMATION_FLOW"]),
    culturalSafety: score(["SAFETY"]),
    revealQuality:
      story.finalReveal.length >= 5 && story.fullCaseNarrative.length >= 100
        ? 10
        : 0,
    latency:
      metrics.latencyMs <= 180_000 ? 10 : metrics.latencyMs <= 300_000 ? 5 : 0,
    cost:
      metrics.estimatedCostUsd <= 2
        ? 10
        : metrics.estimatedCostUsd <= 4
          ? 5
          : 0,
    consequenceEscalation:
      story.consequences.some((item) => item.severity === 1) &&
      story.consequences.some((item) => item.severity === 3) &&
      !has(["SAFETY"])
        ? 10
        : 0,
    rawInputNonCopying: score(["RAW_INPUT_COPY"]),
  } as const;
  const total = Object.values(scores).reduce<number>(
    (sum, value) => sum + value,
    0,
  );
  return { total, passed: total >= 90 && diagnostics.length === 0, scores };
}
