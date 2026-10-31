import type { Metadata } from "next";

import { HostLobbyDashboard } from "@/modules/identity/components/host-lobby-dashboard";

export const metadata: Metadata = { title: "Lobby control" };

export default async function HostRoomPage({
  params,
}: {
  params: Promise<{ roomId: string }>;
}) {
  const { roomId } = await params;
  return (
    <main className="mx-auto min-h-screen w-full max-w-5xl px-5 py-10">
      <HostLobbyDashboard roomId={roomId} />
    </main>
  );
}
