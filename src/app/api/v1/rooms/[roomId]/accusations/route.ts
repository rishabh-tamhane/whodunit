import {
  EndgameCommandResultSchema,
  FinalAccusationSaveResultSchema,
  RoomIdSchema,
  SaveFinalAccusationInputSchema,
  SubmitFinalAccusationInputSchema,
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

async function authorizedRoom(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/accusations">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return { response: apiError(request, 404, "NOT_FOUND", "Room not found.") };
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return { response: authorization.response };
  return { roomId: roomId.data, supabase };
}

export async function PUT(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/accusations">,
) {
  const parsed = await parseJsonBody(request, SaveFinalAccusationInputSchema);
  if (!parsed.success) return parsed.response;
  const authorized = await authorizedRoom(request, context);
  if ("response" in authorized) return authorized.response;
  const { data, error } = await authorized.supabase.rpc(
    "save_final_accusation",
    {
      target_room_id: authorized.roomId,
      expected_revision: parsed.data.expectedRevision,
      structured_case: parsed.data.structuredCase,
      explanation_text: parsed.data.explanationText,
    },
  );
  if (error) return databaseError(request, error);
  return noStoreJson(FinalAccusationSaveResultSchema.parse(data));
}

export async function POST(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/accusations">,
) {
  const parsed = await parseJsonBody(request, SubmitFinalAccusationInputSchema);
  if (!parsed.success) return parsed.response;
  const authorized = await authorizedRoom(request, context);
  if ("response" in authorized) return authorized.response;
  const { data, error } = await authorized.supabase.rpc(
    "submit_final_accusation",
    {
      target_room_id: authorized.roomId,
      expected_state_version: parsed.data.expectedStateVersion,
      idempotency_key: parsed.data.idempotencyKey,
    },
  );
  if (error) return databaseError(request, error);
  return noStoreJson(EndgameCommandResultSchema.parse(data));
}
