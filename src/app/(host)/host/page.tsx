import type { Metadata } from "next";
import Link from "next/link";

import { CreateRoomFlow } from "@/modules/identity/components/create-room-flow";

export const metadata: Metadata = {
  title: "Game Master",
};

export default function HostEntryPage() {
  return (
    <main className="mx-auto min-h-screen w-full max-w-4xl px-5 py-12">
      <p className="text-sm font-bold tracking-[0.2em] text-orange-400 uppercase">
        Game Master
      </p>
      <h1 className="mt-3 text-4xl font-black tracking-tight sm:text-5xl">
        You run the game. You never play a character.
      </h1>
      <p className="mt-5 text-lg leading-8 text-stone-300">
        The Game Master creates the room, approves player devices, sees the
        complete locked mystery, and controls every release and transition.
      </p>
      <div className="mt-10">
        <CreateRoomFlow />
      </div>
      <Link
        href="/"
        className="mt-8 font-bold text-orange-400 hover:text-orange-300"
      >
        Back to home
      </Link>
    </main>
  );
}
