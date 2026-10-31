import {
  MembershipIdSchema,
  RoomIdSchema,
  RoomMutationInputSchema,
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

export async function DELETE(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/memberships/[membershipId]">,
) {
  const params = await context.params;
  const roomId = RoomIdSchema.safeParse(params.roomId);
  const membershipId = MembershipIdSchema.safeParse(params.membershipId);
  if (!roomId.success || !membershipId.success) {
    return apiError(
      request,
      404,
      "NOT_FOUND",
      "That device binding does not exist.",
    );
  }
  const parsed = await parseJsonBody(
    request,
    RoomMutationInputSchema.omit({ roomId: true }),
  );
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;

  const { data, error } = await supabase.rpc("revoke_player_membership", {
    target_room_id: roomId.data,
    target_membership_id: membershipId.data,
    expected_state_version: parsed.data.expectedStateVersion,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(data);
}
