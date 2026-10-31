import {
  EndgameCommandResultSchema,
  RoomCommandInputSchema,
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

export async function POST(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/early-verdict">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const parsed = await parseJsonBody(request, RoomCommandInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc("open_final_accusations", {
    target_room_id: roomId.data,
    expected_state_version: parsed.data.expectedStateVersion,
    idempotency_key: parsed.data.idempotencyKey,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(EndgameCommandResultSchema.parse(data));
}
