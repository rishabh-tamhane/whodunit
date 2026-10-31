import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  after: vi.fn(),
  advance: vi.fn(),
  rpc: vi.fn(),
  unwrap: vi.fn(),
}));

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  after: mocks.after,
}));
vi.mock("@/lib/openai/client", () => ({
  getOpenAIClient: () => ({ webhooks: { unwrap: mocks.unwrap } }),
}));
vi.mock("@/lib/supabase/admin", () => ({
  callSupabaseAdminRpc: mocks.rpc,
}));
vi.mock("@/modules/generation/orchestrator.server", () => ({
  advanceGenerationJob: mocks.advance,
}));

import { POST } from "@/app/api/v1/webhooks/openai/route";

function webhookRequest(body: string, headers: Record<string, string> = {}) {
  return new Request("https://game.example/api/v1/webhooks/openai", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.rpc.mockResolvedValue({ data: null, error: null });
});

describe("OpenAI webhook trust boundary", () => {
  it("rejects the wrong content type before signature processing", async () => {
    const response = await POST(
      new Request("https://game.example/api/v1/webhooks/openai", {
        method: "POST",
        headers: { "content-type": "text/plain" },
        body: "{}",
      }),
    );
    expect(response.status).toBe(400);
    expect(mocks.unwrap).not.toHaveBeenCalled();
  });

  it("rejects an oversized declared or actual body", async () => {
    const declared = await POST(
      webhookRequest("{}", { "content-length": String(1024 * 1024 + 1) }),
    );
    const actual = await POST(webhookRequest("x".repeat(1024 * 1024 + 1)));
    expect(declared.status).toBe(413);
    expect(actual.status).toBe(413);
    expect(mocks.unwrap).not.toHaveBeenCalled();
  });

  it("returns a sanitized error when raw-body signature verification fails", async () => {
    mocks.unwrap.mockRejectedValueOnce(new Error("private signature detail"));
    const response = await POST(
      webhookRequest('{"type":"response.completed"}', {
        "webhook-id": "event-invalid",
      }),
    );
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({
      error: {
        code: "VALIDATION_ERROR",
        message: "Invalid webhook signature.",
      },
    });
    expect(mocks.rpc).toHaveBeenCalledWith(
      "record_operational_event",
      expect.objectContaining({ event_type: "WEBHOOK_REJECTED" }),
    );
  });

  it("deduplicates by durable webhook-id and does not schedule a replay", async () => {
    const rawBody =
      '{"id":"evt-payload","type":"response.completed","data":{"id":"resp-1"}}';
    mocks.unwrap.mockResolvedValueOnce({
      id: "evt-payload",
      type: "response.completed",
      data: { id: "resp-1" },
    });
    mocks.rpc.mockResolvedValueOnce({
      data: { known: true, duplicate: true, jobId: crypto.randomUUID() },
      error: null,
    });

    const response = await POST(
      webhookRequest(rawBody, {
        "webhook-id": "delivery-1",
        "webhook-signature": "verified-by-sdk",
        "webhook-timestamp": "1234567890",
      }),
    );
    expect(response.status).toBe(200);
    expect(mocks.unwrap).toHaveBeenCalledWith(rawBody, expect.any(Headers));
    expect(mocks.rpc).toHaveBeenCalledWith(
      "record_generation_webhook",
      expect.objectContaining({
        provider_event_id: "delivery-1",
        provider_response_id: "resp-1",
      }),
    );
    expect(mocks.after).not.toHaveBeenCalled();
  });

  it("acknowledges a fresh delivery quickly and schedules durable work after the response", async () => {
    const jobId = crypto.randomUUID();
    const flowCorrelationId = crypto.randomUUID();
    mocks.unwrap.mockResolvedValueOnce({
      id: "evt-payload",
      type: "response.completed",
      data: { id: "resp-2" },
    });
    mocks.rpc.mockImplementation(async (name: string) => {
      if (name === "record_generation_webhook")
        return {
          data: { known: true, duplicate: false, jobId },
          error: null,
        };
      if (name === "resolve_ai_call_correlation")
        return { data: flowCorrelationId, error: null };
      return { data: null, error: null };
    });
    const response = await POST(
      webhookRequest(
        '{"id":"evt-payload","type":"response.completed","data":{"id":"resp-2"}}',
        { "webhook-id": "delivery-2" },
      ),
    );
    expect(response.status).toBe(200);
    expect(mocks.after).toHaveBeenCalledOnce();
    const scheduled = mocks.after.mock.calls[0]?.[0] as
      (() => Promise<void>) | undefined;
    expect(scheduled).toBeTypeOf("function");
    await scheduled?.();
    expect(mocks.advance).toHaveBeenCalledWith(jobId, flowCorrelationId);
  });
});
