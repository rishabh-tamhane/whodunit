import { redirect } from "next/navigation";

import {
  defaultPlayerSurface,
  loadActorView,
} from "@/modules/gameplay/route.server";

export default async function RoomResolverPage({
  params,
}: {
  params: Promise<{ roomId: string }>;
}) {
  const { roomId } = await params;
  const view = await loadActorView(roomId);
  if (!view) redirect("/join");
  if (view.actor === "GAME_MASTER") redirect(`/host/rooms/${roomId}`);
  redirect(`/room/${roomId}/${defaultPlayerSurface(view.room.status)}`);
}
