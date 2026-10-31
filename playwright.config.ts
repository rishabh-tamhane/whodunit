import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI === "true" ? 1 : 0,
  reporter: "line",
  timeout: 15 * 60 * 1_000,
  expect: { timeout: 15_000 },
  use: {
    baseURL: process.env.E2E_BASE_URL,
    headless: true,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "off",
  },
  projects: [
    {
      name: "multi-actor-chromium",
      testMatch: /multi-actor-journeys\.spec\.ts/,
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "accessibility-desktop-chromium",
      testMatch: /accessibility\.spec\.ts/,
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "accessibility-mobile-chromium",
      testMatch: /accessibility\.spec\.ts/,
      use: { ...devices["Pixel 7"] },
    },
    {
      name: "accessibility-desktop-webkit",
      testMatch: /accessibility\.spec\.ts/,
      use: { ...devices["Desktop Safari"] },
    },
  ],
});
