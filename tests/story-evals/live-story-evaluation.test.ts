import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import OpenAI from "openai";
import { describe, expect, it } from "vitest";

import { STORY_SCHEMA_VERSION } from "@/contracts/story/version";
import { evaluateStory } from "@/modules/generation/evaluation";
import { createGenerationSnapshotFixture } from "@/modules/generation/fixtures";
import { createOpenAIStoryProvider } from "@/modules/generation/provider";
import {
  buildStoryPrompt,
  STORY_PROMPT_VERSION,
} from "@/modules/generation/snapshot";
import {
  STORY_VALIDATOR_VERSION,
  type StoryValidationContext,
} from "@/modules/generation/validators";
import { estimateModelCostMicrousd } from "@/modules/operations/model-cost";

type CaseResult = Readonly<{
  caseId: string;
  playerCount: number;
  murdererAware: boolean;
  modelId: string;
  passed: boolean;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
  total: number | null;
  scores: Record<string, number> | null;
  failureCode: string | null;
}>;

const cases = ([4, 5, 6, 7, 8, 9, 10, 11, 12] as const).flatMap(
  (playerCount) => [
    { playerCount, murdererAware: true },
    { playerCount, murdererAware: false },
  ],
);

function validationContext(
  snapshot: ReturnType<typeof createGenerationSnapshotFixture>,
): StoryValidationContext {
  return {
    configuredPlayerIds: snapshot.players.map((player) => player.playerId),
    scoringProfileVersion: snapshot.configuration.scoringProfileVersion,
    durationMinutes: snapshot.configuration.durationMinutes,
    roundCount: snapshot.configuration.roundCount,
    murdererCount: snapshot.configuration.murdererCount,
    accompliceCount: snapshot.configuration.accompliceCount,
    innocentCount: snapshot.configuration.innocentCount,
    murdererAware: snapshot.configuration.murdererAware,
    rawDescriptionTexts: snapshot.descriptionResponses.flatMap((response) =>
      response.descriptionText ? [response.descriptionText] : [],
    ),
  };
}

async function waitForResult(
  provider: ReturnType<typeof createOpenAIStoryProvider>,
  initial: Awaited<ReturnType<typeof provider.start>>,
) {
  let result = initial;
  const deadline = Date.now() + 10 * 60 * 1_000;
  while (result.status === "QUEUED" || result.status === "RUNNING") {
    if (Date.now() >= deadline) throw new Error("EVAL_PROVIDER_TIMEOUT");
    await new Promise((resolve) => setTimeout(resolve, 2_000));
    result = await provider.retrieve(result.providerResponseId);
  }
  return result;
}

describe("live story model gate", () => {
  it("passes every supported party-size and awareness case", async () => {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey)
      throw new Error(
        "OPENAI_API_KEY is required. Put it in ignored .env.local; never commit it.",
      );
    if (process.env.STORY_EVAL_ACKNOWLEDGE_COST !== "YES")
      throw new Error(
        "Set STORY_EVAL_ACKNOWLEDGE_COST=YES to confirm this paid 18-case evaluation.",
      );
    const modelId = process.env.STORY_EVAL_MODEL ?? "gpt-6.1-sol";
    const provider = createOpenAIStoryProvider(new OpenAI({ apiKey }), {
      allowedModelIds: [modelId],
      safetyIdentifierSecret:
        "whodunit-non-production-story-evaluation-safety-id-v1",
    });
    const results: CaseResult[] = [];

    for (const evalCase of cases) {
      const caseId = `${evalCase.playerCount}-${evalCase.murdererAware ? "aware" : "unaware"}`;
      const snapshot = createGenerationSnapshotFixture(
        evalCase.playerCount,
        evalCase.murdererAware,
      );
      const startedAt = performance.now();
      try {
        const result = await waitForResult(
          provider,
          await provider.start({
            prompt: buildStoryPrompt(snapshot),
            roomId: snapshot.roomId,
            modelId,
            maxOutputTokens: 24_000,
          }),
        );
        const latencyMs = Math.round(performance.now() - startedAt);
        if (result.status !== "COMPLETED" || !result.story)
          throw new Error(result.errorCode ?? "EVAL_PROVIDER_FAILED");
        const estimatedCostUsd =
          estimateModelCostMicrousd(
            result.modelId,
            result.inputTokens,
            result.outputTokens,
          ) / 1_000_000;
        const evaluation = evaluateStory(
          result.story,
          validationContext(snapshot),
          {
            latencyMs,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
            estimatedCostUsd,
          },
        );
        results.push({
          caseId,
          playerCount: evalCase.playerCount,
          murdererAware: evalCase.murdererAware,
          modelId: result.modelId,
          passed: evaluation.passed,
          latencyMs,
          inputTokens: result.inputTokens,
          outputTokens: result.outputTokens,
          estimatedCostUsd,
          total: evaluation.total,
          scores: evaluation.scores,
          failureCode: null,
        });
      } catch (error) {
        results.push({
          caseId,
          playerCount: evalCase.playerCount,
          murdererAware: evalCase.murdererAware,
          modelId,
          passed: false,
          latencyMs: Math.round(performance.now() - startedAt),
          inputTokens: 0,
          outputTokens: 0,
          estimatedCostUsd: 0,
          total: null,
          scores: null,
          failureCode: error instanceof Error ? error.message : "UNKNOWN",
        });
      }
    }

    const reportPath =
      process.env.STORY_EVAL_REPORT_PATH ??
      path.join(tmpdir(), `whodunit-story-eval-${Date.now()}.json`);
    const report = {
      reportVersion: "story-eval-report-v1",
      generatedAt: new Date().toISOString(),
      modelId,
      promptVersion: STORY_PROMPT_VERSION,
      storySchemaVersion: STORY_SCHEMA_VERSION,
      validatorVersion: STORY_VALIDATOR_VERSION,
      containsPrivateContent: false,
      passed: results.every((result) => result.passed),
      results,
    };
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, {
      mode: 0o600,
    });
    console.info(
      `Story evaluation: ${results.filter((result) => result.passed).length}/${results.length} passed. Safe report: ${reportPath}`,
    );
    expect(report.passed).toBe(true);
  });
});
