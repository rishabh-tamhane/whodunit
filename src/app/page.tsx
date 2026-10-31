import Link from "next/link";

const pillars = [
  [
    "One locked mystery",
    "The canonical solution never changes after generation.",
  ],
  [
    "A dedicated Game Master",
    "The host sees the full game and controls its pace.",
  ],
  [
    "Phones support the party",
    "The product keeps friends talking, bluffing, and accusing.",
  ],
] as const;

export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-6xl flex-col px-5 py-8 sm:px-8 lg:py-14">
      <nav className="flex items-center justify-between" aria-label="Primary">
        <Link
          href="/"
          className="text-lg font-black tracking-[0.18em] uppercase"
        >
          Whodunit
        </Link>
        <span className="rounded-full border border-white/15 px-3 py-1 text-xs text-stone-300">
          v0.1 MVP
        </span>
      </nav>

      <section className="grid flex-1 items-center gap-12 py-16 lg:grid-cols-[1.1fr_0.9fr]">
        <div>
          <p className="mb-4 text-sm font-bold tracking-[0.2em] text-orange-400 uppercase">
            Your friends. One impossible crime.
          </p>
          <h1 className="max-w-3xl text-5xl leading-[0.95] font-black tracking-tight sm:text-7xl">
            Make the party a mystery.
          </h1>
          <p className="mt-7 max-w-2xl text-lg leading-8 text-stone-300">
            Create a private, personalized murder mystery for 4–12 players. A
            separate Game Master knows the truth, runs every round, and keeps
            the story moving.
          </p>
          <div className="mt-9 flex flex-col gap-3 sm:flex-row">
            <Link
              href="/host"
              className="inline-flex min-h-12 items-center justify-center rounded-xl bg-orange-500 px-6 py-3 font-bold text-stone-950 transition hover:bg-orange-400"
            >
              Create a mystery
            </Link>
            <Link
              href="/join"
              className="inline-flex min-h-12 items-center justify-center rounded-xl border border-white/20 bg-white/5 px-6 py-3 font-bold transition hover:bg-white/10"
            >
              Join with a room code
            </Link>
          </div>
        </div>

        <aside className="rounded-3xl border border-white/10 bg-[var(--surface)] p-6 shadow-2xl shadow-black/40 sm:p-8">
          <p className="text-xs font-bold tracking-[0.2em] text-stone-400 uppercase">
            The promise
          </p>
          <div className="mt-6 space-y-6">
            {pillars.map(([title, description], index) => (
              <div key={title} className="grid grid-cols-[2rem_1fr] gap-3">
                <span className="pt-0.5 text-sm font-black text-orange-400">
                  0{index + 1}
                </span>
                <div>
                  <h2 className="font-bold">{title}</h2>
                  <p className="mt-1 text-sm leading-6 text-stone-400">
                    {description}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </aside>
      </section>
    </main>
  );
}
