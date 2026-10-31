import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { PlayerGameShell } from "@/modules/gameplay/components/player-game-shell";
import {
  defaultPlayerSurface,
  loadActorView,
  playerSurfaceAllowed,
} from "@/modules/gameplay/route.server";

export const metadata: Metadata = { title: "Mystery room" };
const surfaces = [
  "waiting",
  "dossier",
  "mission",
  "evidence",
  "notebook",
  "accuse",
  "reveal",
] as const;

export default async function PlayerSurfacePage({
  params,
}: {
  params: Promise<{ roomId: string; surface: string }>;
}) {
  const { roomId, surface } = await params;
  if (!surfaces.includes(surface as (typeof surfaces)[number])) notFound();
  const view = await loadActorView(roomId);
  if (!view) redirect("/join");
  if (view.actor === "GAME_MASTER") redirect(`/host/rooms/${roomId}`);
  if (!playerSurfaceAllowed(view.room.status, surface))
    redirect(`/room/${roomId}/${defaultPlayerSurface(view.room.status)}`);
  return (
    <main className="mx-auto min-h-screen w-full max-w-4xl px-4 py-6 sm:px-5 sm:py-10">
      <PlayerGameShell
        roomId={roomId}
        surface={surface as (typeof surfaces)[number]}
        initialView={view}
      />
    </main>
  );
}
