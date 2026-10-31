import { RoomIdSchema, RoomMutationInputSchema } from "@/contracts";
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
  context: RouteContext<"/api/v1/rooms/[roomId]/acknowledgements/player">,
) {
  const { roomId: roomIdParam } = await context.params;
  const roomId = RoomIdSchema.safeParse(roomIdParam);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const parsed = await parseJsonBody(
    request,
    RoomMutationInputSchema.omit({ roomId: true }),
  );
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc(
    "acknowledge_player_fictional_use",
    {
      target_room_id: roomId.data,
      expected_state_version: parsed.data.expectedStateVersion,
    },
  );
  if (error) return databaseError(request, error);
  return noStoreJson(data);
}
