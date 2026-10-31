import { z } from "zod";

import {
  GameplayCommandResultSchema,
  ResolveInterventionInputSchema,
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
  context: RouteContext<"/api/v1/rooms/[roomId]/interventions/[requestId]">,
) {
  const params = await context.params;
  const roomId = RoomIdSchema.safeParse(params.roomId);
  const requestId = z.string().uuid().safeParse(params.requestId);
  if (!roomId.success || !requestId.success)
    return apiError(request, 404, "NOT_FOUND", "Intervention not found.");
  const parsed = await parseJsonBody(request, ResolveInterventionInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc("resolve_intervention", {
    target_room_id: roomId.data,
    target_request_id: requestId.data,
    expected_state_version: parsed.data.expectedStateVersion,
    idempotency_key: parsed.data.idempotencyKey,
    decision: parsed.data.decision,
  });
  if (error) return databaseError(request, error);
  return noStoreJson(GameplayCommandResultSchema.passthrough().parse(data));
}
