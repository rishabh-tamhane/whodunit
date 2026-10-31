import type { Metadata } from "next";
import Link from "next/link";

import { JoinRoomFlow } from "@/modules/identity/components/join-room-flow";

export const metadata: Metadata = {
  title: "Join",
};

export default async function JoinEntryPage({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>;
}) {
  const { code = "" } = await searchParams;
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-xl flex-col justify-center px-5 py-12">
      <p className="text-sm font-bold tracking-[0.2em] text-violet-300 uppercase">
        Player entry
      </p>
      <h1 className="mt-3 text-4xl font-black tracking-tight sm:text-5xl">
        Join your mystery.
      </h1>
      <p className="mt-5 text-lg leading-8 text-stone-300">
        A room code finds the safe lobby. It never grants access to a role,
        clue, mission, or private player information.
      </p>
      <div className="mt-10">
        <JoinRoomFlow initialCode={code} />
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
