import { ActorViewSchema, RoomIdSchema } from "@/contracts";
import {
  apiError,
  databaseError,
  noStoreJson,
  requireUser,
} from "@/lib/api/route.server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET(
  request: Request,
  context: RouteContext<"/api/v1/rooms/[roomId]/view">,
) {
  const roomId = RoomIdSchema.safeParse((await context.params).roomId);
  if (!roomId.success)
    return apiError(request, 404, "NOT_FOUND", "Room not found.");
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;
  const { data, error } = await supabase.rpc("get_actor_view", {
    target_room_id: roomId.data,
  });
  if (error) return databaseError(request, error);
  const view = ActorViewSchema.safeParse(data);
  if (!view.success)
    return apiError(
      request,
      500,
      "INTERNAL_ERROR",
      "The authorized room view is invalid.",
    );
  return noStoreJson(view.data);
}
