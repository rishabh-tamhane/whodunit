import {
  MembershipIdSchema,
  ReviewClaimInputSchema,
  RoomIdSchema,
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

export async function PATCH(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/claims/[claimId]">,
) {
  const params = await context.params;
  const roomId = RoomIdSchema.safeParse(params.roomId);
  const claimId = MembershipIdSchema.safeParse(params.claimId);
  if (!roomId.success || !claimId.success) {
    return apiError(request, 404, "NOT_FOUND", "That claim does not exist.");
  }
  const parsed = await parseJsonBody(request, ReviewClaimInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;

  const { data, error } = await supabase.rpc("review_player_claim", {
    target_room_id: roomId.data,
    target_claim_id: claimId.data,
    expected_state_version: parsed.data.expectedStateVersion,
    decision: parsed.data.decision,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(data);
}
