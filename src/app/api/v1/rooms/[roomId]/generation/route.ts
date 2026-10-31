import {
  GenerationStatusViewSchema,
  RoomIdSchema,
  StartedGenerationSchema,
  StartGenerationInputSchema,
} from "@/contracts";
import {
  apiError,
  databaseError,
  noStoreJson,
  parseJsonBody,
  requireUser,
} from "@/lib/api/route.server";
import { getModelPolicy } from "@/lib/openai/client";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { advanceGenerationJob } from "@/modules/generation/orchestrator.server";
import { STORY_PROMPT_VERSION } from "@/modules/generation/snapshot";
import { STORY_VALIDATOR_VERSION } from "@/modules/generation/validators";
import { STORY_SCHEMA_VERSION } from "@/contracts/story/version";

export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/generation">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const parsed = await parseJsonBody(request, StartGenerationInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const models = getModelPolicy();
  const { data, error } = await supabase.rpc("start_story_generation", {
    target_room_id: roomId.data,
    expected_state_version: parsed.data.expectedStateVersion,
    idempotency_key: parsed.data.idempotencyKey,
    requested_model_id: models.story,
    requested_escalation_model_id: models.escalation,
    requested_prompt_version: STORY_PROMPT_VERSION,
    requested_story_schema_version: STORY_SCHEMA_VERSION,
    requested_validator_version: STORY_VALIDATOR_VERSION,
  });
  if (error) return databaseError(request, error);
  const started = StartedGenerationSchema.safeParse(data);
  if (!started.success)
    return apiError(
      request,
      500,
      "INTERNAL_ERROR",
      "Generation could not be started.",
    );
  if (!started.data.replayed && started.data.status === "PENDING") {
    try {
      await advanceGenerationJob(started.data.jobId);
    } catch {
      /* Durable status exposes the normalized worker failure. */
    }
  }
  return noStoreJson(started.data, { status: 202 });
}

export async function GET(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/generation">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  let result = await supabase.rpc("get_generation_status", {
    target_room_id: roomId.data,
  });
  if (result.error) return databaseError(request, result.error);
  let view = GenerationStatusViewSchema.safeParse(result.data);
  if (view.success && view.data.job?.status === "RUNNING") {
    try {
      await advanceGenerationJob(view.data.job.jobId);
    } catch {
      /* Status remains the source of truth. */
    }
    result = await supabase.rpc("get_generation_status", {
      target_room_id: roomId.data,
    });
    if (result.error) return databaseError(request, result.error);
    view = GenerationStatusViewSchema.safeParse(result.data);
  }
  if (!view.success)
    return apiError(
      request,
      500,
      "INTERNAL_ERROR",
      "Generation status is unavailable.",
    );
  return noStoreJson(view.data);
}
