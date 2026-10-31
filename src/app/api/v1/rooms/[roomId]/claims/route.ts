import { RequestClaimInputSchema, RoomIdSchema } from "@/contracts";
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
  context: RouteContext<"/api/v1/rooms/[roomId]/claims">,
) {
  const { roomId: roomIdParam } = await context.params;
  const roomId = RoomIdSchema.safeParse(roomIdParam);
  if (!roomId.success) {
    return apiError(request, 404, "NOT_FOUND", "That room does not exist.");
  }
  const parsed = await parseJsonBody(request, RequestClaimInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase, "PLAYER_CLAIM");
  if (!authorization.success) return authorization.response;

  const { data, error } = await supabase.rpc("request_player_claim", {
    target_room_id: roomId.data,
    target_player_id: parsed.data.playerId,
    requested_kind: parsed.data.requestKind,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(data, { status: 201 });
}
