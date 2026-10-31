import "server-only";

import { ActorViewSchema } from "@/contracts";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function loadActorView(roomId: string) {
  const supabase = await createSupabaseServerClient();
  const user = await supabase.auth.getUser();
  if (!user.data.user) return null;
  const { data, error } = await supabase.rpc("get_actor_view", {
    target_room_id: roomId,
  });
  if (error) return null;
  const parsed = ActorViewSchema.safeParse(data);
  return parsed.success ? parsed.data : null;
}

export function defaultPlayerSurface(
  status: string,
): "waiting" | "dossier" | "mission" | "accuse" | "reveal" {
  if (["LOBBY", "GENERATING"].includes(status)) return "waiting";
  if (status === "READY_TO_START") return "dossier";
  if (status === "IN_PROGRESS") return "mission";
  if (status === "FINAL_ACCUSATIONS") return "accuse";
  return "reveal";
}

export function playerSurfaceAllowed(status: string, surface: string): boolean {
  if (["LOBBY", "GENERATING"].includes(status)) return surface === "waiting";
  if (status === "READY_TO_START")
    return ["dossier", "evidence", "notebook"].includes(surface);
  if (status === "IN_PROGRESS")
    return ["dossier", "mission", "evidence", "notebook"].includes(surface);
  if (status === "FINAL_ACCUSATIONS")
    return ["dossier", "evidence", "notebook", "accuse"].includes(surface);
  if (["REVEAL", "COMPLETED"].includes(status))
    return ["dossier", "evidence", "notebook", "reveal"].includes(surface);
  return false;
}
