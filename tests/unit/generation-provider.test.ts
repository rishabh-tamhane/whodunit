import { describe, expect, it, vi } from "vitest";

import { createStoryFixture } from "@/modules/generation/fixtures";
import {
  createOpenAIStoryProvider,
  StoryProviderError,
} from "@/modules/generation/provider";

function response(story = createStoryFixture(4).story) {
  return {
    id: "resp_private_123",
    status: "completed",
    model: "gpt-6.1-sol",
    output_text: JSON.stringify(story),
    usage: { input_tokens: 100, output_tokens: 200 },
    error: null,
  };
}

describe("OpenAI story provider boundary", () => {
  it("uses background Structured Outputs, store false, and a pseudonymous safety ID", async () => {
    const create = vi.fn().mockResolvedValue(response());
    const provider = createOpenAIStoryProvider(
      { responses: { create, retrieve: vi.fn() } } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
      },
    );
    await expect(
      provider.start({
        prompt: "safe prompt",
        roomId: "00000000-0000-4000-8000-000000000001",
        modelId: "gpt-6.1-sol",
        maxOutputTokens: 20_000,
      }),
    ).resolves.toMatchObject({
      status: "COMPLETED",
      providerResponseId: "resp_private_123",
      inputTokens: 100,
      outputTokens: 200,
    });
    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        background: true,
        store: false,
        model: "gpt-6.1-sol",
        safety_identifier: expect.stringMatching(/^[a-f0-9]{64}$/),
        text: {
          format: expect.objectContaining({
            type: "json_schema",
            strict: true,
          }),
        },
      }),
    );
    const request = create.mock.calls[0]![0];
    expect(request.safety_identifier).not.toContain("00000000-0000");
  });

  it("rejects unapproved model IDs before a provider call", async () => {
    const create = vi.fn();
    const provider = createOpenAIStoryProvider(
      { responses: { create, retrieve: vi.fn() } } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
      },
    );
    await expect(
      provider.start({
        prompt: "x",
        roomId: crypto.randomUUID(),
        modelId: "unapproved",
        maxOutputTokens: 1_000,
      }),
    ).rejects.toMatchObject<Partial<StoryProviderError>>({
      code: "MODEL_NOT_ALLOWED",
    });
    expect(create).not.toHaveBeenCalled();
  });

  it("normalizes malformed provider output without exposing it", async () => {
    const retrieve = vi
      .fn()
      .mockResolvedValue({ ...response(), output_text: "not-json" });
    const provider = createOpenAIStoryProvider(
      { responses: { create: vi.fn(), retrieve } } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
      },
    );
    await expect(provider.retrieve("resp_private_123")).rejects.toMatchObject<
      Partial<StoryProviderError>
    >({ code: "INVALID_PROVIDER_OUTPUT" });
  });

  it("normalizes a refusal with no schema output as invalid provider output", async () => {
    const retrieve = vi.fn().mockResolvedValue({
      ...response(),
      output_text: "",
      output: [
        {
          type: "message",
          content: [{ type: "refusal", refusal: "Cannot comply" }],
        },
      ],
    });
    const provider = createOpenAIStoryProvider(
      { responses: { create: vi.fn(), retrieve } } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
      },
    );
    await expect(provider.retrieve("resp_private_123")).rejects.toMatchObject<
      Partial<StoryProviderError>
    >({ code: "INVALID_PROVIDER_OUTPUT" });
  });

  it.each(["failed", "cancelled", "incomplete"])(
    "maps %s responses to a bounded terminal failure",
    async (status) => {
      const retrieve = vi.fn().mockResolvedValue({
        ...response(),
        status,
        output_text: "",
        error: { code: "provider_terminal" },
      });
      const provider = createOpenAIStoryProvider(
        { responses: { create: vi.fn(), retrieve } } as never,
        {
          allowedModelIds: ["gpt-6.1-sol"],
          safetyIdentifierSecret: "s".repeat(32),
        },
      );
      await expect(
        provider.retrieve("resp_private_123"),
      ).resolves.toMatchObject({
        status: "FAILED",
        story: null,
        errorCode: "provider_terminal",
      });
    },
  );

  it("normalizes provider transport errors without leaking their message", async () => {
    const retrieve = vi
      .fn()
      .mockRejectedValue(new Error("private provider response body"));
    const provider = createOpenAIStoryProvider(
      { responses: { create: vi.fn(), retrieve } } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
      },
    );
    await expect(provider.retrieve("resp_private_123")).rejects.toMatchObject<
      Partial<StoryProviderError>
    >({ code: "PROVIDER_UNAVAILABLE", message: "PROVIDER_UNAVAILABLE" });
  });
});
