import {
  NotebookSaveResultSchema,
  RoomIdSchema,
  SaveNotebookInputSchema,
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
export async function PUT(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/notebook">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const parsed = await parseJsonBody(request, SaveNotebookInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc("save_player_notebook", {
    target_room_id: roomId.data,
    expected_revision: parsed.data.expectedRevision,
    notes_text: parsed.data.notesText,
    suspects: parsed.data.suspects,
  });
  if (error) return databaseError(request, error);
  const result = NotebookSaveResultSchema.safeParse(data);
  if (!result.success)
    return apiError(
      request,
      500,
      "INTERNAL_ERROR",
      "Notebook save response was invalid.",
    );
  return noStoreJson(result.data);
}
