import type { Clock } from "@/lib/time/clock";

export interface FixedClock extends Clock {
  advanceBy(milliseconds: number): void;
  set(instant: Date | string): void;
}

function epochMilliseconds(instant: Date | string): number {
  const value = new Date(instant).getTime();
  if (!Number.isFinite(value)) {
    throw new Error("Fixed clock requires a valid instant.");
  }
  return value;
}

export function createFixedClock(initial: Date | string): FixedClock {
  let current = epochMilliseconds(initial);

  return {
    now: () => new Date(current),
    advanceBy: (milliseconds) => {
      if (!Number.isFinite(milliseconds)) {
        throw new Error("Clock advancement must be finite.");
      }
      current += milliseconds;
    },
    set: (instant) => {
      current = epochMilliseconds(instant);
    },
  };
}
