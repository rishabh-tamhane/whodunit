import "server-only";

import OpenAI from "openai";

import { getServerEnv } from "@/lib/env/server";

let openAIClient: OpenAI | undefined;

export function getOpenAIClient(): OpenAI {
  if (openAIClient) {
    return openAIClient;
  }

  openAIClient = new OpenAI({ apiKey: getServerEnv().OPENAI_API_KEY });
  return openAIClient;
}

export function getModelPolicy() {
  const env = getServerEnv();
  return {
    story: env.STORY_MODEL,
    escalation: env.STORY_ESCALATION_MODEL,
    intervention: env.INTERVENTION_MODEL,
  } as const;
}
