import { describe, expect, it, vi } from "vitest";

import { createFixtureFactory } from "../support/fixtures";

describe("fixture factory", () => {
  it("creates deterministic, type-validated values per test context", () => {
    const first = createFixtureFactory(7);
    const second = createFixtureFactory(7);

    expect(first.roomId()).toBe(second.roomId());
    expect(first.playerId()).toBe(second.playerId());
    expect(first.commandMetadata()).toEqual(second.commandMetadata());
  });

  it("runs cleanup callbacks in reverse registration order", async () => {
    const events: string[] = [];
    const fixtures = createFixtureFactory();
    fixtures.onCleanup(() => {
      events.push("first");
    });
    fixtures.onCleanup(() => {
      events.push("second");
    });

    await fixtures.cleanup();

    expect(events).toEqual(["second", "first"]);
    await expect(fixtures.cleanup()).resolves.toBeUndefined();
    expect(vi.isMockFunction(fixtures.cleanup)).toBe(false);
  });
});
