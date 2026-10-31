import type OpenAI from "openai";

import {
  STORY_PACKAGE_JSON_SCHEMA,
  StoryPackageSchema,
  type StoryPackage,
} from "@/contracts";

export type StoryProviderStatus = "QUEUED" | "RUNNING" | "COMPLETED" | "FAILED";

export type StoryProviderResult = Readonly<{
  providerResponseId: string;
  status: StoryProviderStatus;
  modelId: string;
  story: StoryPackage | null;
  inputTokens: number;
  outputTokens: number;
  errorCode: string | null;
}>;

export type StartStoryGeneration = Readonly<{
  prompt: string;
  roomId: string;
  modelId: string;
  maxOutputTokens: number;
}>;

export interface StoryProvider {
  start(input: StartStoryGeneration): Promise<StoryProviderResult>;
  retrieve(providerResponseId: string): Promise<StoryProviderResult>;
}

export type StoryProviderPolicy = Readonly<{
  allowedModelIds: readonly string[];
  safetyIdentifierSecret: string;
}>;

export class StoryProviderError extends Error {
  constructor(
    readonly code:
      "MODEL_NOT_ALLOWED" | "PROVIDER_UNAVAILABLE" | "INVALID_PROVIDER_OUTPUT",
    options?: ErrorOptions,
  ) {
    super(code, options);
    this.name = "StoryProviderError";
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

function normalizedStatus(status: string | undefined): StoryProviderStatus {
  if (status === "completed") return "COMPLETED";
  if (["failed", "cancelled", "incomplete"].includes(status ?? ""))
    return "FAILED";
  if (status === "queued") return "QUEUED";
  return "RUNNING";
}

function mapResponse(
  response: Awaited<ReturnType<OpenAI["responses"]["retrieve"]>>,
): StoryProviderResult {
  const status = normalizedStatus(response.status);
  let story: StoryPackage | null = null;
  if (status === "COMPLETED") {
    try {
      story = StoryPackageSchema.parse(JSON.parse(response.output_text));
    } catch (error) {
      throw new StoryProviderError("INVALID_PROVIDER_OUTPUT", { cause: error });
    }
  }
  return {
    providerResponseId: response.id,
    status,
    modelId: response.model,
    story,
    inputTokens: response.usage?.input_tokens ?? 0,
    outputTokens: response.usage?.output_tokens ?? 0,
    errorCode:
      response.error?.code ??
      (status === "FAILED" ? "PROVIDER_RESPONSE_FAILED" : null),
  };
}

export function createOpenAIStoryProvider(
  client: OpenAI,
  policy: StoryProviderPolicy,
): StoryProvider {
  const ensureModelAllowed = (modelId: string) => {
    if (!policy.allowedModelIds.includes(modelId))
      throw new StoryProviderError("MODEL_NOT_ALLOWED");
  };
  return {
    async start(input) {
      ensureModelAllowed(input.modelId);
      try {
        const response = await client.responses.create({
          model: input.modelId,
          background: true,
          store: false,
          safety_identifier: await hmacSha256Hex(
            policy.safetyIdentifierSecret,
            `story-room:${input.roomId}`,
          ),
          max_output_tokens: input.maxOutputTokens,
          input: [{ role: "developer", content: input.prompt }],
          text: {
            format: {
              type: "json_schema",
              name: "whodunit_story_package_v0_1",
              description: "A complete, validated Whodunit mystery package.",
              strict: true,
              schema: STORY_PACKAGE_JSON_SCHEMA,
            },
          },
        });
        return mapResponse(response);
      } catch (error) {
        if (error instanceof StoryProviderError) throw error;
        throw new StoryProviderError("PROVIDER_UNAVAILABLE", { cause: error });
      }
    },
    async retrieve(providerResponseId) {
      try {
        return mapResponse(await client.responses.retrieve(providerResponseId));
      } catch (error) {
        if (error instanceof StoryProviderError) throw error;
        throw new StoryProviderError("PROVIDER_UNAVAILABLE", { cause: error });
      }
    },
  };
}

export class FakeStoryProvider implements StoryProvider {
  readonly starts: StartStoryGeneration[] = [];
  constructor(private readonly results: StoryProviderResult[]) {}
  async start(input: StartStoryGeneration): Promise<StoryProviderResult> {
    this.starts.push(input);
    return this.next();
  }
  async retrieve(): Promise<StoryProviderResult> {
    return this.next();
  }
  private next(): StoryProviderResult {
    const result = this.results.shift();
    if (!result) throw new StoryProviderError("PROVIDER_UNAVAILABLE");
    return result;
  }
}
