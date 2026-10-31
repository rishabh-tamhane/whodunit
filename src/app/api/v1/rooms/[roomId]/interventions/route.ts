import { z } from "zod";

import {
  InterventionPreviewResultSchema,
  RequestInterventionInputSchema,
  RoomIdSchema,
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
import {
  InterventionProviderError,
  type InterventionProviderResult,
} from "@/modules/interventions/provider";
import { getInterventionProvider } from "@/modules/interventions/provider.server";

export const dynamic = "force-dynamic";

const RequestedInterventionSchema = z.object({
  requestId: z.string().uuid(),
  status: z.literal("REQUESTED"),
  stateVersion: z.string(),
  context: z.unknown(),
});

export async function POST(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/interventions">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const parsed = await parseJsonBody(request, RequestInterventionInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const requested = await supabase.rpc("request_intervention", {
    target_room_id: roomId.data,
    expected_state_version: parsed.data.expectedStateVersion,
    idempotency_key: parsed.data.idempotencyKey,
  });
  if (requested.error) return databaseError(request, requested.error);
  const requestState = RequestedInterventionSchema.safeParse(requested.data);
  if (!requestState.success)
    return apiError(
      request,
      500,
      "INTERNAL_ERROR",
      "The intervention request could not be prepared.",
    );

  let providerResult: InterventionProviderResult | undefined;
  let failureCode: string | undefined;
  const attemptStartedAt = performance.now();
  try {
    providerResult = await getInterventionProvider().select({
      roomId: roomId.data,
      modelId: getModelPolicy().intervention,
      context: requestState.data.context,
    });
  } catch (error) {
    failureCode =
      error instanceof InterventionProviderError
        ? error.code
        : "PROVIDER_UNAVAILABLE";
  }
  const staged = await supabase.rpc("stage_intervention_preview", {
    target_room_id: roomId.data,
    target_request_id: requestState.data.requestId,
    selected_candidate_id: providerResult?.selection.candidateId ?? null,
    selected_target_player_id: providerResult?.selection.targetPlayerId ?? null,
    presentation_style: providerResult?.selection.presentationStyle ?? "GENTLE",
    reason_code:
      providerResult?.selection.reasonCode ??
      failureCode ??
      "PREPARED_FALLBACK",
    provider_model_id: providerResult?.modelId ?? null,
    provider_response_id: providerResult?.providerResponseId ?? null,
    attempt_input_tokens: providerResult?.inputTokens ?? 0,
    attempt_output_tokens: providerResult?.outputTokens ?? 0,
    attempt_latency_ms:
      providerResult?.latencyMs ??
      Math.round(performance.now() - attemptStartedAt),
    provider_failure_code: failureCode ?? null,
  });
  if (staged.error) return databaseError(request, staged.error);
  const preview = InterventionPreviewResultSchema.safeParse(staged.data);
  if (!preview.success)
    return apiError(
      request,
      500,
      "INTERNAL_ERROR",
      "The intervention preview is unavailable.",
    );
  return noStoreJson(preview.data, { status: 201 });
}
