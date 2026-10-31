import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { GameMasterDashboard } from "@/modules/gameplay/components/game-master-dashboard";
import {
  defaultPlayerSurface,
  loadActorView,
} from "@/modules/gameplay/route.server";
import { HostLobbyDashboard } from "@/modules/identity/components/host-lobby-dashboard";

export const metadata: Metadata = { title: "Lobby control" };

export default async function HostRoomPage({
  params,
}: {
  params: Promise<{ roomId: string }>;
}) {
  const { roomId } = await params;
  const actorView = await loadActorView(roomId);
  if (!actorView) redirect("/join");
  if (actorView.actor === "PLAYER") {
    redirect(`/room/${roomId}/${defaultPlayerSurface(actorView.room.status)}`);
  }
  return (
    <main className="mx-auto min-h-screen w-full max-w-5xl px-5 py-10">
      <HostLobbyDashboard roomId={roomId} />
      <GameMasterDashboard roomId={roomId} initialView={actorView} />
    </main>
  );
}
