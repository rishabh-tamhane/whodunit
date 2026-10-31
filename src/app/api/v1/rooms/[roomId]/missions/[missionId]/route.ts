import {
  GameplayCommandResultSchema,
  MissionCommandInputSchema,
  MissionIdSchema,
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
  context: RouteContext<"/api/v1/rooms/[roomId]/missions/[missionId]">,
) {
  const params = await context.params;
  const roomId = RoomIdSchema.safeParse(params.roomId);
  const missionId = MissionIdSchema.safeParse(params.missionId);
  if (!roomId.success || !missionId.success)
    return apiError(request, 404, "NOT_FOUND", "Mission not found.");
  const parsed = await parseJsonBody(request, MissionCommandInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const playerAction = ["ACCEPT", "REQUEST_COMPLETION"].includes(
    parsed.data.action,
  );
  const { data, error } = playerAction
    ? await supabase.rpc("player_mission_command", {
        target_room_id: roomId.data,
        target_mission_id: missionId.data,
        expected_state_version: parsed.data.expectedStateVersion,
        idempotency_key: parsed.data.idempotencyKey,
        requested_action: parsed.data.action,
      })
    : await supabase.rpc("adjudicate_mission", {
        target_room_id: roomId.data,
        target_mission_id: missionId.data,
        expected_state_version: parsed.data.expectedStateVersion,
        idempotency_key: parsed.data.idempotencyKey,
        decision: parsed.data.action,
        extension_minutes: parsed.data.extensionMinutes ?? null,
      });
  if (error) return databaseError(request, error);
  return noStoreJson(GameplayCommandResultSchema.parse(data));
}
