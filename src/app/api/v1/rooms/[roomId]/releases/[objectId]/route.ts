import {
  CanonicalReleaseInputSchema,
  GameplayCommandResultSchema,
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
import { z } from "zod";
export const dynamic = "force-dynamic";
const ObjectIdSchema = z.string().uuid();
export async function POST(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/releases/[objectId]">,
) {
  const params = await context.params;
  const roomId = RoomIdSchema.safeParse(params.roomId);
  const objectId = ObjectIdSchema.safeParse(params.objectId);
  if (!roomId.success || !objectId.success)
    return apiError(request, 404, "NOT_FOUND", "Canonical object not found.");
  const parsed = await parseJsonBody(request, CanonicalReleaseInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc("resolve_canonical_release", {
    target_room_id: roomId.data,
    target_object_id: objectId.data,
    expected_state_version: parsed.data.expectedStateVersion,
    idempotency_key: parsed.data.idempotencyKey,
    object_kind: parsed.data.objectKind,
    decision: parsed.data.decision,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(GameplayCommandResultSchema.passthrough().parse(data));
}
