import type OpenAI from "openai";
import { z } from "zod";

export const InterventionSelectionSchema = z.strictObject({
  candidateId: z.string().uuid(),
  targetPlayerId: z.string().uuid().nullable(),
  presentationStyle: z.enum(["GENTLE", "DIRECT", "URGENT"]),
  reasonCode: z.enum([
    "UNBLOCK_DISCUSSION",
    "REBALANCE_PARTICIPATION",
    "ESCALATE_EVIDENCE",
    "CLARIFY_TIMELINE",
  ]),
});

export type InterventionSelection = z.infer<typeof InterventionSelectionSchema>;

export type InterventionProviderResult = Readonly<{
  providerResponseId: string;
  modelId: string;
  selection: InterventionSelection;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
}>;

export class InterventionProviderError extends Error {
  constructor(
    readonly code:
      "MODEL_NOT_ALLOWED" | "PROVIDER_UNAVAILABLE" | "INVALID_PROVIDER_OUTPUT",
    options?: ErrorOptions,
  ) {
    super(code, options);
    this.name = "InterventionProviderError";
  }
}

async function hmacSha256Hex(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(signature), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

const INTERVENTION_SELECTION_JSON_SCHEMA = z.toJSONSchema(
  InterventionSelectionSchema,
  { target: "draft-2020-12", unrepresentable: "throw" },
);

export function createOpenAIInterventionProvider(
  client: OpenAI,
  policy: Readonly<{
    allowedModelIds: readonly string[];
    safetyIdentifierSecret: string;
    timeoutMs: number;
  }>,
) {
  return {
    async select(input: {
      roomId: string;
      modelId: string;
      context: unknown;
    }): Promise<InterventionProviderResult> {
      if (!policy.allowedModelIds.includes(input.modelId))
        throw new InterventionProviderError("MODEL_NOT_ALLOWED");
      const startedAt = performance.now();
      try {
        const response = await client.responses.create(
          {
            model: input.modelId,
            store: false,
            safety_identifier: await hmacSha256Hex(
              policy.safetyIdentifierSecret,
              `intervention-room:${input.roomId}`,
            ),
            max_output_tokens: 200,
            input: [
              {
                role: "developer",
                content:
                  "Select exactly one candidate from the supplied allowlist. Return only its candidate ID, an optional target player from permittedTargetPlayerIds, a presentation style, and a non-spoiler reason code. Never create or rewrite facts, roles, motives, methods, alibis, relationships, evidence, or solution details. Do not judge whether a suspicion is correct.",
              },
              {
                role: "user",
                content: JSON.stringify(input.context),
              },
            ],
            text: {
              format: {
                type: "json_schema",
                name: "whodunit_intervention_selection_v0_1",
                description:
                  "A selection from the application-provided canonical intervention allowlist.",
                strict: true,
                schema: INTERVENTION_SELECTION_JSON_SCHEMA,
              },
            },
          },
          { timeout: policy.timeoutMs, maxRetries: 0 },
        );
        if (response.status !== "completed")
          throw new InterventionProviderError("INVALID_PROVIDER_OUTPUT");
        let selection: InterventionSelection;
        try {
          selection = InterventionSelectionSchema.parse(
            JSON.parse(response.output_text),
          );
        } catch (error) {
          throw new InterventionProviderError("INVALID_PROVIDER_OUTPUT", {
            cause: error,
          });
        }
        return {
          providerResponseId: response.id,
          modelId: response.model,
          selection,
          inputTokens: response.usage?.input_tokens ?? 0,
          outputTokens: response.usage?.output_tokens ?? 0,
          latencyMs: Math.round(performance.now() - startedAt),
        };
      } catch (error) {
        if (error instanceof InterventionProviderError) throw error;
        throw new InterventionProviderError("PROVIDER_UNAVAILABLE", {
          cause: error,
        });
      }
    },
  };
}
