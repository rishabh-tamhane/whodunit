import { describe, expect, it, vi } from "vitest";

import {
  createOpenAIInterventionProvider,
  InterventionProviderError,
} from "@/modules/interventions/provider";

const candidateId = "10000000-0000-4000-8000-000000000001";

function response(output: unknown) {
  return {
    id: "resp_intervention_private_123",
    status: "completed",
    model: "gpt-6.1-sol",
    output_text: JSON.stringify(output),
    usage: { input_tokens: 50, output_tokens: 12 },
  };
}

describe("OpenAI intervention provider boundary", () => {
  it("uses synchronous stateless Structured Outputs with a pseudonymous safety ID", async () => {
    const create = vi.fn().mockResolvedValue(
      response({
        candidateId,
        targetPlayerId: null,
        presentationStyle: "GENTLE",
        reasonCode: "UNBLOCK_DISCUSSION",
      }),
    );
    const provider = createOpenAIInterventionProvider(
      { responses: { create } } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
        timeoutMs: 10_000,
      },
    );
    await expect(
      provider.select({
        roomId: "00000000-0000-4000-8000-000000000001",
        modelId: "gpt-6.1-sol",
        context: { candidates: [{ candidateId }] },
      }),
    ).resolves.toMatchObject({
      providerResponseId: "resp_intervention_private_123",
      selection: { candidateId },
      inputTokens: 50,
      outputTokens: 12,
    });
    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        model: "gpt-6.1-sol",
        store: false,
        safety_identifier: expect.stringMatching(/^[a-f0-9]{64}$/),
        text: {
          format: expect.objectContaining({
            type: "json_schema",
            strict: true,
          }),
        },
      }),
      expect.objectContaining({ timeout: 10_000, maxRetries: 0 }),
    );
    expect(create.mock.calls[0]![0].safety_identifier).not.toContain(
      "00000000-0000",
    );
  });

  it("rejects an unapproved model before the API call", async () => {
    const create = vi.fn();
    const provider = createOpenAIInterventionProvider(
      { responses: { create } } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
        timeoutMs: 10_000,
      },
    );
    await expect(
      provider.select({
        roomId: crypto.randomUUID(),
        modelId: "other",
        context: {},
      }),
    ).rejects.toMatchObject<Partial<InterventionProviderError>>({
      code: "MODEL_NOT_ALLOWED",
    });
    expect(create).not.toHaveBeenCalled();
  });

  it("normalizes non-schema output instead of displaying model text", async () => {
    const provider = createOpenAIInterventionProvider(
      {
        responses: {
          create: vi.fn().mockResolvedValue(response({ inventedClue: "No" })),
        },
      } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
        timeoutMs: 10_000,
      },
    );
    await expect(
      provider.select({
        roomId: crypto.randomUUID(),
        modelId: "gpt-6.1-sol",
        context: {},
      }),
    ).rejects.toMatchObject<Partial<InterventionProviderError>>({
      code: "INVALID_PROVIDER_OUTPUT",
    });
  });

  it("normalizes an incomplete or refused response", async () => {
    const provider = createOpenAIInterventionProvider(
      {
        responses: {
          create: vi
            .fn()
            .mockResolvedValue({ ...response({}), status: "incomplete" }),
        },
      } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
        timeoutMs: 10_000,
      },
    );
    await expect(
      provider.select({
        roomId: crypto.randomUUID(),
        modelId: "gpt-6.1-sol",
        context: {},
      }),
    ).rejects.toMatchObject<Partial<InterventionProviderError>>({
      code: "INVALID_PROVIDER_OUTPUT",
    });
  });

  it("normalizes a provider timeout without exposing its message", async () => {
    const provider = createOpenAIInterventionProvider(
      {
        responses: {
          create: vi
            .fn()
            .mockRejectedValue(new Error("private timeout detail")),
        },
      } as never,
      {
        allowedModelIds: ["gpt-6.1-sol"],
        safetyIdentifierSecret: "s".repeat(32),
        timeoutMs: 10_000,
      },
    );
    await expect(
      provider.select({
        roomId: crypto.randomUUID(),
        modelId: "gpt-6.1-sol",
        context: {},
      }),
    ).rejects.toMatchObject<Partial<InterventionProviderError>>({
      code: "PROVIDER_UNAVAILABLE",
      message: "PROVIDER_UNAVAILABLE",
    });
  });
});
