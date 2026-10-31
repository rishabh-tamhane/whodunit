import "server-only";

import { z } from "zod";

import { checksumStoryPackage, checksumStorySolution } from "@/contracts";
import { callSupabaseAdminRpc } from "@/lib/supabase/admin";
import { getStoryProvider } from "@/modules/generation/provider.server";
import type { StoryProviderResult } from "@/modules/generation/provider";
import {
  buildStoryPrompt,
  GenerationSnapshotSchema,
} from "@/modules/generation/snapshot";
import {
  validateStoryPackage,
  type StoryDiagnostic,
} from "@/modules/generation/validators";

const ClaimSchema = z.strictObject({
  jobId: z.string().uuid(),
  roomId: z.string().uuid(),
  inputSnapshot: GenerationSnapshotSchema,
  modelId: z.string(),
  escalationModelId: z.string(),
  attemptCount: z.number().int(),
  repairCount: z.number().int(),
  escalationCount: z.number().int(),
  providerResponseIds: z.record(z.string(), z.string()),
});

const MAX_REPAIRS = 2;
const MAX_ESCALATIONS = 1;
const MAX_OUTPUT_TOKENS = 24_000;

function contextFromSnapshot(
  snapshot: z.infer<typeof GenerationSnapshotSchema>,
) {
  return {
    configuredPlayerIds: snapshot.players.map((player) => player.playerId),
    durationMinutes: snapshot.configuration.durationMinutes,
    roundCount: snapshot.configuration.roundCount,
    murdererCount: snapshot.configuration.murdererCount,
    accompliceCount: snapshot.configuration.accompliceCount,
    innocentCount: snapshot.configuration.innocentCount,
    murdererAware: snapshot.configuration.murdererAware,
    rawDescriptionTexts: snapshot.descriptionResponses.flatMap((response) =>
      response.descriptionText ? [response.descriptionText] : [],
    ),
  } as const;
}

function repairPrompt(
  snapshot: z.infer<typeof GenerationSnapshotSchema>,
  diagnostics: readonly StoryDiagnostic[],
): string {
  return `${buildStoryPrompt(snapshot)}\n\nThe previous candidate was rejected. Produce a complete replacement package. Repair every constraint below; do not discuss the errors:\n${diagnostics.map((item) => `- ${item.category}: ${item.repairConstraint}`).join("\n")}`;
}

async function checkpoint(
  jobId: string,
  workerId: string,
  input: {
    phase: string;
    providerResponseId?: string | null;
    content?: unknown;
    diagnostics?: readonly StoryDiagnostic[];
    result?: StoryProviderResult;
    repairIncrement?: number;
    escalationIncrement?: number;
  },
) {
  const { error } = await callSupabaseAdminRpc("checkpoint_generation_job", {
    target_job_id: jobId,
    expected_lease_owner: workerId,
    next_phase: input.phase,
    provider_response_id: input.providerResponseId ?? null,
    generated_content: input.content ?? null,
    validation_issues: input.diagnostics ?? null,
    added_input_tokens: input.result?.inputTokens ?? 0,
    added_output_tokens: input.result?.outputTokens ?? 0,
    added_latency_ms: 0,
    repair_increment: input.repairIncrement ?? 0,
    escalation_increment: input.escalationIncrement ?? 0,
  });
  if (error) throw new Error("GENERATION_CHECKPOINT_FAILED", { cause: error });
}

async function release(jobId: string, workerId: string): Promise<void> {
  const { error } = await callSupabaseAdminRpc("release_generation_lease", {
    target_job_id: jobId,
    expected_lease_owner: workerId,
  });
  if (error)
    throw new Error("GENERATION_LEASE_RELEASE_FAILED", { cause: error });
}

async function fail(
  jobId: string,
  workerId: string,
  code: string,
  diagnostics: readonly StoryDiagnostic[] = [],
): Promise<void> {
  const { error } = await callSupabaseAdminRpc("fail_generation_job", {
    target_job_id: jobId,
    expected_lease_owner: workerId,
    failure_code: code,
    validation_issues: diagnostics,
  });
  if (error)
    throw new Error("GENERATION_FAILURE_TRANSITION_FAILED", { cause: error });
}

async function submitCandidate(
  job: z.infer<typeof ClaimSchema>,
  workerId: string,
  modelId: string,
  prompt: string,
  increments: { repair: number; escalation: number },
): Promise<void> {
  const result = await getStoryProvider().start({
    prompt,
    roomId: job.roomId,
    modelId,
    maxOutputTokens: MAX_OUTPUT_TOKENS,
  });
  await checkpoint(job.jobId, workerId, {
    phase: increments.repair > 0 ? "REPAIR" : "PLAYABLE_CONTENT",
    providerResponseId: result.providerResponseId,
    ...(result.status === "COMPLETED" ? {} : { result }),
    repairIncrement: increments.repair,
    escalationIncrement: increments.escalation,
  });
  const updatedJob = {
    ...job,
    repairCount: job.repairCount + increments.repair,
    escalationCount: job.escalationCount + increments.escalation,
    attemptCount: job.attemptCount + increments.repair + increments.escalation,
  };
  if (result.status === "COMPLETED")
    await handleResult(updatedJob, workerId, result);
  else if (result.status === "FAILED")
    await fail(
      job.jobId,
      workerId,
      result.errorCode ?? "PROVIDER_RESPONSE_FAILED",
    );
  else await release(job.jobId, workerId);
}

async function handleResult(
  job: z.infer<typeof ClaimSchema>,
  workerId: string,
  result: StoryProviderResult,
): Promise<void> {
  if (result.status !== "COMPLETED" || !result.story) {
    if (result.status === "FAILED")
      await fail(
        job.jobId,
        workerId,
        result.errorCode ?? "PROVIDER_RESPONSE_FAILED",
      );
    else await release(job.jobId, workerId);
    return;
  }
  const diagnostics = validateStoryPackage(
    result.story,
    contextFromSnapshot(job.inputSnapshot),
  );
  await checkpoint(job.jobId, workerId, {
    phase: diagnostics.length === 0 ? "LOCKING" : "VALIDATION",
    content: result.story,
    diagnostics,
    result,
  });
  if (diagnostics.length === 0) {
    const { data, error } = await callSupabaseAdminRpc("lock_generated_story", {
      target_job_id: job.jobId,
      expected_lease_owner: workerId,
      story_package: result.story,
      package_checksum_hex: await checksumStoryPackage(result.story),
      solution_checksum_hex: await checksumStorySolution(result.story),
    });
    if (error) throw new Error("ATOMIC_STORY_LOCK_FAILED", { cause: error });
    void data;
    return;
  }
  if (job.repairCount < MAX_REPAIRS) {
    await submitCandidate(
      job,
      workerId,
      job.modelId,
      repairPrompt(job.inputSnapshot, diagnostics),
      { repair: 1, escalation: 0 },
    );
    return;
  }
  if (job.escalationCount < MAX_ESCALATIONS) {
    await submitCandidate(
      job,
      workerId,
      job.escalationModelId,
      repairPrompt(job.inputSnapshot, diagnostics),
      { repair: 0, escalation: 1 },
    );
    return;
  }
  await fail(job.jobId, workerId, "VALIDATION_EXHAUSTED", diagnostics);
}

export async function advanceGenerationJob(jobId: string): Promise<void> {
  const workerId = `generation-${crypto.randomUUID()}`;
  const { data, error } = await callSupabaseAdminRpc("claim_generation_job", {
    target_job_id: jobId,
    requested_lease_owner: workerId,
  });
  if (error) throw new Error("GENERATION_JOB_CLAIM_FAILED", { cause: error });
  const job = ClaimSchema.parse(data);
  const providerResponseId = job.providerResponseIds.story;
  try {
    if (!providerResponseId) {
      await submitCandidate(
        job,
        workerId,
        job.modelId,
        buildStoryPrompt(job.inputSnapshot),
        { repair: 0, escalation: 0 },
      );
      return;
    }
    const result = await getStoryProvider().retrieve(providerResponseId);
    if (["QUEUED", "RUNNING"].includes(result.status)) {
      await release(job.jobId, workerId);
      return;
    }
    await handleResult(job, workerId, result);
  } catch (error) {
    try {
      await fail(job.jobId, workerId, "GENERATION_WORKER_ERROR");
    } catch {
      /* Preserve the original normalized failure. */
    }
    throw error;
  }
}
