import { describe, expect, it } from "vitest";

import {
  estimateModelCostMicrousd,
  maximumModelCallCostMicrousd,
} from "@/modules/operations/model-cost";

describe("model cost guardrails", () => {
  it("estimates configured model usage in integer microdollars", () => {
    expect(estimateModelCostMicrousd("gpt-6.1-sol", 1_000, 2_000)).toBe(22_000);
    expect(estimateModelCostMicrousd("gpt-6-astra", 1_000, 2_000)).toBe(
      110_000,
    );
  });

  it("reserves conservatively for unknown models and bounded call shapes", () => {
    expect(estimateModelCostMicrousd("future-model", 1_000, 2_000)).toBe(
      110_000,
    );
    expect(maximumModelCallCostMicrousd("gpt-6.1-sol", "STORY")).toBe(340_000);
    expect(maximumModelCallCostMicrousd("gpt-6-astra", "STORY")).toBe(
      1_700_000,
    );
    expect(maximumModelCallCostMicrousd("gpt-6.1-sol", "INTERVENTION")).toBe(
      12_000,
    );
  });
});
