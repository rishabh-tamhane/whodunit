import { z } from "zod";

import { RoomMutationResultSchema } from "@/contracts/onboarding";
import {
  apiError,
  databaseError,
  noStoreJson,
  requireUser,
} from "@/lib/api/route.server";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createRecoveryCredential } from "@/modules/identity/recovery.server";

export const dynamic = "force-dynamic";

const DatabaseCreatedRoomSchema = RoomMutationResultSchema.extend({
  recoveryExpiresAt: z.iso.datetime({ offset: true }),
});

export async function POST(request: Request) {
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase);
  if (!authorization.success) return authorization.response;

  const recovery = createRecoveryCredential();
  const { data, error } = await supabase.rpc("create_game_room", {
    recovery_token_digest: recovery.digestForDatabase,
    recovery_expires_at: recovery.expiresAt.toISOString(),
  });
  if (error) return databaseError(request, error);

  const room = DatabaseCreatedRoomSchema.safeParse(data);
  if (!room.success) {
    return apiError(
      request,
      500,
      "INTERNAL_ERROR",
      "The room was created but its response was invalid.",
    );
  }

  return noStoreJson(
    {
      ...room.data,
      recoveryPath: `/host/recover#token=${encodeURIComponent(recovery.token)}`,
      joinPath: `/join?code=${encodeURIComponent(room.data.roomCode)}`,
    },
    { status: 201 },
  );
}
