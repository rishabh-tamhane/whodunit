import { describe, expect, it } from "vitest";

import { systemClock } from "@/lib/time/clock";
import { createFixedClock } from "../support/clock";

describe("clocks", () => {
  it("returns defensive Date values from a fixed instant", () => {
    const clock = createFixedClock("2026-10-30T12:00:00.000Z");
    const first = clock.now();
    first.setUTCFullYear(2000);

    expect(clock.now().toISOString()).toBe("2026-10-30T12:00:00.000Z");

    clock.advanceBy(1_000);
    expect(clock.now().toISOString()).toBe("2026-10-30T12:00:01.000Z");
  });

  it("returns a fresh Date from the system clock", () => {
    expect(systemClock.now()).not.toBe(systemClock.now());
  });
});
