import { randomUUID } from "node:crypto";
import { createServer } from "node:http";

import { StoryPackageSchema, type StoryPackage } from "../src/contracts/index";
import { createStoryFixture } from "../src/modules/generation/fixtures";

const port = Number(process.argv[2]);
if (!Number.isInteger(port) || port < 1 || port > 65_535)
  throw new Error("Pass a valid loopback port to the OpenAI E2E mock.");

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type RosterPlayer = Readonly<{
  playerId: string;
  displayName: string;
  costume: string;
}>;

function extractJson<T>(prompt: string, prefix: string, suffix?: string): T {
  const start = prompt.indexOf(prefix);
  if (start < 0) throw new Error(`Missing ${prefix}`);
  const contentStart = start + prefix.length;
  const end = suffix
    ? prompt.indexOf(suffix, contentStart)
    : prompt.indexOf("\n", contentStart);
  if (end < 0) throw new Error(`Missing terminator for ${prefix}`);
  return JSON.parse(prompt.slice(contentStart, end).trim()) as T;
}

function remapIds(value: unknown, ids: Map<string, string>): unknown {
  if (typeof value === "string" && UUID_PATTERN.test(value)) {
    const mapped = ids.get(value) ?? randomUUID();
    ids.set(value, mapped);
    return mapped;
  }
  if (Array.isArray(value)) return value.map((item) => remapIds(item, ids));
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, remapIds(item, ids)]),
    );
  return value;
}

function storyFromPrompt(prompt: string): StoryPackage {
  const configuration = extractJson<{
    murdererAware: boolean;
    durationMinutes: number;
    murdererCount: number;
    accompliceCount: number;
  }>(prompt, "Trusted configuration: ");
  const roster = extractJson<RosterPlayer[]>(
    prompt,
    "<UNTRUSTED_PLAYER_ROSTER>\n",
    "\n</UNTRUSTED_PLAYER_ROSTER>",
  );
  if (roster.length < 4 || roster.length > 12)
    throw new Error("Unsupported E2E roster size");
  const fixture = createStoryFixture(
    roster.length as 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12,
    configuration.murdererAware,
  ).story;
  if (
    fixture.durationProfile.durationMinutes !== configuration.durationMinutes ||
    fixture.solution.murdererPlayerIds.length !== configuration.murdererCount ||
    fixture.solution.accomplicePlayerIds.length !==
      configuration.accompliceCount
  )
    throw new Error("E2E configuration must use the recommended fixed profile");

  const ids = new Map(
    fixture.characters.map((character, index) => [
      character.playerId,
      roster[index]!.playerId,
    ]),
  );
  const story = remapIds(fixture, ids) as StoryPackage;
  for (const [index, character] of story.characters.entries()) {
    character.displayName = roster[index]!.displayName;
    character.costume = roster[index]!.costume;
  }
  return StoryPackageSchema.parse(story);
}

function responsePayload(model: string, story: StoryPackage) {
  const responseId = `resp_e2e_${randomUUID().replaceAll("-", "")}`;
  return {
    id: responseId,
    object: "response",
    created_at: Math.floor(Date.now() / 1_000),
    completed_at: Math.floor(Date.now() / 1_000),
    status: "completed",
    error: null,
    incomplete_details: null,
    instructions: null,
    max_output_tokens: 24_000,
    model,
    output: [
      {
        id: `msg_${randomUUID().replaceAll("-", "")}`,
        type: "message",
        status: "completed",
        role: "assistant",
        content: [
          {
            type: "output_text",
            text: JSON.stringify(story),
            annotations: [],
            logprobs: [],
          },
        ],
      },
    ],
    parallel_tool_calls: false,
    previous_response_id: null,
    prompt_cache_key: null,
    reasoning: { effort: null, summary: null },
    safety_identifier: null,
    service_tier: "default",
    store: false,
    temperature: 1,
    text: { format: { type: "json_object" }, verbosity: "medium" },
    tool_choice: "auto",
    tools: [],
    top_logprobs: 0,
    top_p: 1,
    truncation: "disabled",
    usage: {
      input_tokens: 4_000,
      input_tokens_details: { cached_tokens: 0 },
      output_tokens: 12_000,
      output_tokens_details: { reasoning_tokens: 0 },
      total_tokens: 16_000,
    },
    user: null,
    metadata: {},
  };
}

const server = createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/health") {
    response.writeHead(200, { "content-type": "application/json" });
    response.end('{"ok":true}');
    return;
  }
  if (request.method !== "POST" || request.url !== "/v1/responses") {
    response.writeHead(404, { "content-type": "application/json" });
    response.end('{"error":{"message":"not found"}}');
    return;
  }
  try {
    const chunks: Buffer[] = [];
    let size = 0;
    for await (const chunk of request) {
      const bytes = Buffer.from(chunk);
      size += bytes.length;
      if (size > 2 * 1024 * 1024) throw new Error("request too large");
      chunks.push(bytes);
    }
    const body = JSON.parse(Buffer.concat(chunks).toString("utf8")) as {
      model?: string;
      input?: Array<{ role?: string; content?: string }>;
    };
    const prompt = body.input?.find(
      (item) => item.role === "developer",
    )?.content;
    if (!body.model || !prompt) throw new Error("invalid response request");
    const story = storyFromPrompt(prompt);
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify(responsePayload(body.model, story)));
  } catch (error) {
    console.error(
      `OpenAI E2E mock rejected request: ${error instanceof Error ? error.message : "unknown failure"}`,
    );
    response.writeHead(400, { "content-type": "application/json" });
    response.end(
      JSON.stringify({
        error: {
          message: error instanceof Error ? error.message : "mock failure",
          type: "invalid_request_error",
          code: "e2e_mock_rejected",
        },
      }),
    );
  }
});

server.listen(port, "127.0.0.1", () => {
  console.info(`OpenAI E2E mock listening on 127.0.0.1:${port}`);
});

for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.on(signal, () => server.close(() => process.exit(0)));
