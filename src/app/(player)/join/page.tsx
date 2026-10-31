import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Join",
};

export default function JoinEntryPage() {
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
      <div className="mt-8 rounded-2xl border border-white/10 bg-white/5 p-5 text-sm leading-6 text-stone-300">
        Player claiming and Game Master approval will be implemented after the
        identity and room authorization foundation.
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
