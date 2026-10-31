import "server-only";

import { getServerEnv } from "@/lib/env/server";
import { getModelPolicy, getOpenAIClient } from "@/lib/openai/client";
import { createOpenAIStoryProvider } from "@/modules/generation/provider";

export function getStoryProvider() {
  const models = getModelPolicy();
  return createOpenAIStoryProvider(getOpenAIClient(), {
    allowedModelIds: [models.story, models.escalation],
    safetyIdentifierSecret: getServerEnv().SAFETY_IDENTIFIER_HMAC_SECRET,
  });
}
