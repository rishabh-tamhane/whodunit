import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
      "server-only": fileURLToPath(
        new URL("./tests/mocks/server-only.ts", import.meta.url),
      ),
    },
  },
  test: {
    environment: "node",
    fileParallelism: false,
    include: ["tests/story-evals/live-story-evaluation.test.ts"],
    maxWorkers: 1,
    restoreMocks: true,
    testTimeout: 60 * 60 * 1_000,
  },
});
