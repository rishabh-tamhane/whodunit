export type SupportedModelId = "gpt-6.1-sol" | "gpt-6-astra";

type TokenRates = Readonly<{
  inputMicrousdPerToken: number;
  outputMicrousdPerToken: number;
}>;

const MODEL_RATES: Readonly<Record<SupportedModelId, TokenRates>> = {
  "gpt-6.1-sol": {
    inputMicrousdPerToken: 2,
    outputMicrousdPerToken: 10,
  },
  "gpt-6-astra": {
    inputMicrousdPerToken: 10,
    outputMicrousdPerToken: 50,
  },
};

const CONSERVATIVE_UNKNOWN_MODEL_RATE = MODEL_RATES["gpt-6-astra"];

export function estimateModelCostMicrousd(
  modelId: string,
  inputTokens: number,
  outputTokens: number,
): number {
  const rates =
    MODEL_RATES[modelId as SupportedModelId] ?? CONSERVATIVE_UNKNOWN_MODEL_RATE;
  return Math.ceil(
    Math.max(0, inputTokens) * rates.inputMicrousdPerToken +
      Math.max(0, outputTokens) * rates.outputMicrousdPerToken,
  );
}

export function maximumModelCallCostMicrousd(
  modelId: string,
  callKind: "STORY" | "INTERVENTION",
): number {
  return estimateModelCostMicrousd(
    modelId,
    callKind === "STORY" ? 50_000 : 5_000,
    callKind === "STORY" ? 24_000 : 200,
  );
}
