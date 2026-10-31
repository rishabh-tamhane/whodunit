import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Game Master",
};

export default function HostEntryPage() {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-2xl flex-col justify-center px-5 py-12">
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
      <div className="mt-8 rounded-2xl border border-white/10 bg-white/5 p-5 text-sm leading-6 text-stone-300">
        Room creation is the first product workflow scheduled after the
        foundation and database authorization layers.
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
