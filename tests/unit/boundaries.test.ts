import { describe, expect, it } from "vitest";

import { checkSourceBoundaries } from "../../scripts/check-boundaries.mjs";

describe("module boundary checks", () => {
  it("rejects a server-only client import", () => {
    const violations = checkSourceBoundaries(
      "src/app/example.tsx",
      '"use client";\nimport { getOpenAIClient } from "@/lib/openai/client";',
    );

    expect(violations).toHaveLength(1);
  });

  it("rejects model-provider imports from gameplay", () => {
    const violations = checkSourceBoundaries(
      "src/modules/gameplay/server/example.ts",
      'import OpenAI from "openai";',
    );

    expect(violations).toContain(
      "src/modules/gameplay/server/example.ts: gameplay imports model provider openai",
    );
  });

  it("keeps contracts infrastructure-independent", () => {
    const violations = checkSourceBoundaries(
      "src/contracts/example.ts",
      'import { cookies } from "next/headers";',
    );

    expect(violations).toHaveLength(1);
  });

  it("allows only the Next.js runtime discriminator in instrumentation", () => {
    expect(
      checkSourceBoundaries(
        "src/instrumentation.ts",
        'if (process.env.NEXT_RUNTIME === "nodejs") {}',
      ),
    ).toEqual([]);

    expect(
      checkSourceBoundaries(
        "src/instrumentation.ts",
        "void process.env.OPENAI_API_KEY;",
      ),
    ).toHaveLength(1);
  });
});
