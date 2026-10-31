import { z } from "zod";

import { RoomCodeSchema, SafeLobbySchema } from "@/contracts";
import {
  apiError,
  databaseError,
  noStoreJson,
  parseJsonBody,
  requireUser,
} from "@/lib/api/route.server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const LookupInputSchema = z.strictObject({ roomCode: RoomCodeSchema });
const LobbyRowSchema = z.strictObject({
  room_id: z.string().uuid(),
  room_code: RoomCodeSchema,
  room_status: z.string(),
  player_id: z.string().uuid(),
  display_name: z.string(),
  costume: z.string(),
  seat_order: z.number().int(),
  slot_status: z.enum(["AVAILABLE", "PENDING", "OCCUPIED"]),
});

export async function POST(request: Request) {
  const parsed = await parseJsonBody(request, LookupInputSchema);
  if (!parsed.success) return parsed.response;
  const supabase = await createSupabaseServerClient();
  const authorization = await requireUser(request, supabase, "ROOM_DISCOVERY");
  if (!authorization.success) return authorization.response;

  const { data, error } = await supabase.rpc("lookup_room_lobby", {
    submitted_room_code: parsed.data.roomCode,
  });
  if (error) return databaseError(request, error);
  const rows = z.array(LobbyRowSchema).safeParse(data);
  if (!rows.success || rows.data.length === 0) {
    return apiError(
      request,
      404,
      "NOT_FOUND",
      "We could not find a joinable room with that code.",
    );
  }
  const first = rows.data[0];
  if (!first) {
    return apiError(request, 404, "NOT_FOUND", "That lobby is unavailable.");
  }
  const lobby = SafeLobbySchema.parse({
    roomId: first.room_id,
    roomCode: first.room_code,
    roomStatus: first.room_status,
    slots: rows.data.map((row) => ({
      playerId: row.player_id,
      displayName: row.display_name,
      costume: row.costume,
      seatOrder: row.seat_order,
      slotStatus: row.slot_status,
    })),
  });
  return noStoreJson(lobby);
}
