import { z } from "zod";
import { describe, expect, it, vi } from "vitest";

import {
  ApiClientError,
  recoverMutationFailure,
  requestJson,
} from "@/lib/api/request";
import { parseSchemaForm } from "@/lib/forms/schema-form";
import {
  IdempotencyKeySchema,
  StateVersionSchema,
} from "@/contracts/domain/ids";

const InputSchema = z.strictObject({ action: z.string().min(1) });
const OutputSchema = z.strictObject({
  stateVersion: z.number().int(),
  replayed: z.boolean(),
});

function jsonResponse(payload: unknown, status = 200, headers?: HeadersInit) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

describe("typed API mutation infrastructure", () => {
  it("rejects invalid input before sending a request", async () => {
    const fetcher = vi.fn<typeof fetch>();
    await expect(
      requestJson({
        url: "/api/v1/example",
        method: "POST",
        input: { action: "" },
        inputSchema: InputSchema,
        outputSchema: OutputSchema,
        fetcher,
      }),
    ).rejects.toBeInstanceOf(z.ZodError);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("retries a transient failure with the same idempotency and version headers", async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse({ unavailable: true }, 503))
      .mockResolvedValueOnce(
        jsonResponse({ stateVersion: 8, replayed: false }),
      );
    const wait = vi.fn(async () => undefined);

    const result = await requestJson({
      url: "/api/v1/example",
      method: "POST",
      input: { action: "ADVANCE" },
      inputSchema: InputSchema,
      outputSchema: OutputSchema,
      metadata: {
        idempotencyKey: IdempotencyKeySchema.parse(
          "11111111-1111-4111-8111-111111111111",
        ),
        expectedStateVersion: StateVersionSchema.parse("7"),
      },
      fetcher,
      wait,
    });

    expect(result).toEqual({ stateVersion: 8, replayed: false });
    expect(fetcher).toHaveBeenCalledTimes(2);
    for (const [, init] of fetcher.mock.calls) {
      const headers = new Headers(init?.headers);
      expect(headers.get("Idempotency-Key")).toBe(
        "11111111-1111-4111-8111-111111111111",
      );
      expect(headers.get("X-Expected-State-Version")).toBe("7");
    }
    expect(wait).toHaveBeenCalledOnce();
  });

  it("accepts an idempotent replay as an ordinary successful result", async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockImplementation(async () =>
        jsonResponse({ stateVersion: 8, replayed: true }),
      );
    const metadata = {
      idempotencyKey: IdempotencyKeySchema.parse(
        "22222222-2222-4222-8222-222222222222",
      ),
      expectedStateVersion: StateVersionSchema.parse("7"),
    };

    const first = await requestJson({
      url: "/api/v1/example",
      method: "POST",
      input: { action: "ADVANCE" },
      inputSchema: InputSchema,
      outputSchema: OutputSchema,
      metadata,
      fetcher,
    });
    const replay = await requestJson({
      url: "/api/v1/example",
      method: "POST",
      input: { action: "ADVANCE" },
      inputSchema: InputSchema,
      outputSchema: OutputSchema,
      metadata,
      fetcher,
    });

    expect(first).toEqual(replay);
    expect(replay.replayed).toBe(true);
  });

  it("surfaces a stale-version conflict without retrying", async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(
      jsonResponse(
        {
          error: {
            code: "STALE_STATE_VERSION",
            message: "The room changed.",
            requestId: "req-conflict",
            currentStateVersion: "9",
          },
        },
        409,
      ),
    );

    const error = await requestJson({
      url: "/api/v1/example",
      method: "POST",
      input: { action: "ADVANCE" },
      inputSchema: InputSchema,
      outputSchema: OutputSchema,
      metadata: {
        idempotencyKey: IdempotencyKeySchema.parse(
          "33333333-3333-4333-8333-333333333333",
        ),
        expectedStateVersion: StateVersionSchema.parse("7"),
      },
      fetcher,
    }).catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(ApiClientError);
    expect(error).toMatchObject({
      code: "STALE_STATE_VERSION",
      status: 409,
      currentStateVersion: "9",
    });
    expect(fetcher).toHaveBeenCalledOnce();

    const refetch = vi.fn(async () => ({ stateVersion: 9, replayed: false }));
    const state = await recoverMutationFailure(error, refetch);
    expect(refetch).toHaveBeenCalledOnce();
    expect(state).toEqual({
      status: "conflict",
      data: { stateVersion: 9, replayed: false },
      currentStateVersion: "9",
    });
  });

  it("normalizes a non-JSON server failure", async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValue(new Response("upstream failed", { status: 502 }));
    const error = await requestJson({
      url: "/api/v1/example",
      outputSchema: OutputSchema,
      fetcher,
    }).catch((caught: unknown) => caught);
    expect(error).toMatchObject({ code: "SERVICE_UNAVAILABLE", status: 502 });
    const state = await recoverMutationFailure(error, async () => {
      throw new Error("server failures must not trigger a conflict refetch");
    });
    expect(state).toMatchObject({ status: "error", error });
  });
});

describe("schema-backed form parsing", () => {
  it("collects repeated fields and maps validation issues by path", () => {
    const formData = new FormData();
    formData.append("name", "");
    formData.append("evidence", "one");
    formData.append("evidence", "two");
    const schema = z.strictObject({
      name: z.string().min(1, "Enter a name."),
      evidence: z.array(z.string()).min(1),
    });

    const result = parseSchemaForm(schema, formData);
    expect(result).toEqual({
      success: false,
      fieldErrors: { name: ["Enter a name."] },
    });
  });

  it("returns typed form data on success", () => {
    const formData = new FormData();
    formData.set("roomCode", "HALLOW7");
    const result = parseSchemaForm(
      z.strictObject({ roomCode: z.string().regex(/^[A-Z0-9]{4,12}$/) }),
      formData,
    );
    expect(result).toEqual({
      success: true,
      data: { roomCode: "HALLOW7" },
      fieldErrors: {},
    });
  });
});
