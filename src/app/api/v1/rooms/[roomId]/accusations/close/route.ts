import {
  CloseFinalAccusationsInputSchema,
  EndgameCommandResultSchema,
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
  context: RouteContext<"/api/v1/rooms/[roomId]/accusations/close">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const parsed = await parseJsonBody(request, CloseFinalAccusationsInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc("close_final_accusations", {
    target_room_id: roomId.data,
    expected_state_version: parsed.data.expectedStateVersion,
    idempotency_key: parsed.data.idempotencyKey,
    confirmed_missing_player_ids: parsed.data.confirmedMissingPlayerIds,
    confirm_zero_submissions: parsed.data.confirmZeroSubmissions,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(EndgameCommandResultSchema.parse(data));
}
