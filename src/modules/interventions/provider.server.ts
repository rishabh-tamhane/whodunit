import "server-only";

import { getServerEnv } from "@/lib/env/server";
import { getModelPolicy, getOpenAIClient } from "@/lib/openai/client";
import { createOpenAIInterventionProvider } from "@/modules/interventions/provider";

export function getInterventionProvider() {
  const models = getModelPolicy();
  return createOpenAIInterventionProvider(getOpenAIClient(), {
    allowedModelIds: [models.intervention],
    safetyIdentifierSecret: getServerEnv().SAFETY_IDENTIFIER_HMAC_SECRET,
    timeoutMs: 10_000,
  });
}
