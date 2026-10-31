import { RoomIdSchema } from "@/contracts";
import {
  apiError,
  databaseError,
  noStoreJson,
  requireUser,
} from "@/lib/api/route.server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/heartbeat">,
) {
  const { roomId: roomIdParam } = await context.params;
  const roomId = RoomIdSchema.safeParse(roomIdParam);
  if (!roomId.success) {
    return apiError(request, 404, "NOT_FOUND", "That room does not exist.");
  }
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc("record_player_heartbeat", {
    target_room_id: roomId.data,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(data);
}
