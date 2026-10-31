import {
  GameplayCommandResultSchema,
  RoomIdSchema,
  SubmitTheoryInputSchema,
} from "@/contracts";
import {
  apiError,
  databaseError,
  noStoreJson,
  parseJsonBody,
  requireUser,
} from "@/lib/api/route.server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
export const dynamic = "force-dynamic";
export async function POST(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/theories">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const parsed = await parseJsonBody(request, SubmitTheoryInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc("submit_player_theory", {
    target_room_id: roomId.data,
    expected_state_version: parsed.data.expectedStateVersion,
    idempotency_key: parsed.data.idempotencyKey,
    structured_claim: parsed.data.structuredClaim,
    submitted_explanation: parsed.data.submittedExplanation,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(GameplayCommandResultSchema.passthrough().parse(data), {
    status: 201,
  });
}
