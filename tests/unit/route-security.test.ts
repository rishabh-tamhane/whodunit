import { describe, expect, it } from "vitest";
import { z } from "zod";

import { parseJsonBody } from "@/lib/api/route.server";

const Schema = z.strictObject({ action: z.string() });

describe("request boundary defenses", () => {
  it("rejects a cross-site JSON mutation", async () => {
    const result = await parseJsonBody(
      new Request("https://game.example/api/v1/rooms/id", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          origin: "https://attacker.example",
          "sec-fetch-site": "cross-site",
        },
        body: JSON.stringify({ action: "ADVANCE" }),
      }),
      Schema,
    );
    expect(result.success).toBe(false);
    if (!result.success) expect(result.response.status).toBe(403);
  });

  it("rejects an oversized body before parsing", async () => {
    const result = await parseJsonBody(
      new Request("https://game.example/api/v1/rooms/id", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "content-length": String(70 * 1024),
        },
        body: JSON.stringify({ action: "ADVANCE" }),
      }),
      Schema,
    );
    expect(result.success).toBe(false);
    if (!result.success) expect(result.response.status).toBe(413);
  });

  it("accepts a bounded same-origin JSON mutation", async () => {
    const result = await parseJsonBody(
      new Request("https://game.example/api/v1/rooms/id", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          origin: "https://game.example",
          "sec-fetch-site": "same-origin",
        },
        body: JSON.stringify({ action: "ADVANCE" }),
      }),
      Schema,
    );
    expect(result).toMatchObject({
      success: true,
      data: { action: "ADVANCE" },
    });
  });
});
