import { RoomIdSchema } from "@/contracts";
import {
  apiError,
  databaseError,
  noStoreJson,
  requireUser,
} from "@/lib/api/route.server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createRecoveryCredential } from "@/modules/identity/recovery.server";

export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/recovery">,
) {
  const { roomId: roomIdParam } = await context.params;
  const roomId = RoomIdSchema.safeParse(roomIdParam);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const replacement = createRecoveryCredential();
  const { data, error } = await supabase.rpc("rotate_game_master_recovery", {
    target_room_id: roomId.data,
    replacement_token_digest: replacement.digestForDatabase,
    replacement_expires_at: replacement.expiresAt.toISOString(),
  });
  if (error) return databaseError(request, error);
  return noStoreJson({
    ...(data as object),
    recoveryPath: `/host/recover#token=${encodeURIComponent(replacement.token)}`,
  });
}
