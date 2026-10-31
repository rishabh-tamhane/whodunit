import { execFile, spawn } from "node:child_process";
import { createServer } from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const executableSuffix = process.platform === "win32" ? ".cmd" : "";
const localBinary = (name) =>
  path.join(projectRoot, "node_modules", ".bin", name + executableSuffix);
const supabaseBinary = localBinary("supabase");
const nextBinary = localBinary("next");
const vitestBinary = localBinary("vitest");

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

async function readSupabaseStatus() {
  let lastError;

  for (let attempt = 1; attempt <= 5; attempt += 1) {
    try {
      const { stdout } = await execFileAsync(
        supabaseBinary,
        ["status", "-o", "json"],
        {
          cwd: projectRoot,
          env: { ...process.env, SUPABASE_TELEMETRY_DISABLED: "1" },
          maxBuffer: 1024 * 1024,
        },
      );
      const status = JSON.parse(stdout);
      const apiUrl = status.API_URL;
      const publishableKey = status.PUBLISHABLE_KEY ?? status.ANON_KEY;
      const serviceRoleKey = status.SERVICE_ROLE_KEY;

      if (apiUrl && publishableKey && serviceRoleKey) {
        return { apiUrl, publishableKey, serviceRoleKey };
      }

      lastError = new Error(
        "Supabase status did not include its API URL and local API keys.",
      );
    } catch (error) {
      lastError = error;
    }

    if (attempt < 5) {
      await delay(2_000);
    }
  }

  throw new Error("The local Supabase stack did not become ready in time.", {
    cause: lastError,
  });
}

async function reserveLoopbackPort() {
  const server = createServer();

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });

  const address = server.address();
  if (!address || typeof address === "string") {
    server.close();
    throw new Error("Could not reserve a loopback port for integration tests.");
  }

  await new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });

  return address.port;
}

async function waitForHealth(baseUrl, child) {
  let lastError;

  for (let attempt = 1; attempt <= 120; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(
        `Next.js exited before becoming ready (exit ${child.exitCode}).`,
      );
    }

    try {
      const response = await fetch(new URL("/api/v1/health", baseUrl));
      if (response.ok) {
        return;
      }
      lastError = new Error(`Health check returned HTTP ${response.status}.`);
    } catch (error) {
      lastError = error;
    }

    await delay(250);
  }

  throw new Error("Next.js did not become healthy within 30 seconds.", {
    cause: lastError,
  });
}

async function runVitest(environment) {
  const child = spawn(
    vitestBinary,
    ["run", "--config", "vitest.integration.config.ts"],
    {
      cwd: projectRoot,
      env: environment,
      stdio: "inherit",
    },
  );

  const exitCode = await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => resolve(code ?? 1));
  });

  if (exitCode !== 0) {
    throw new Error(`Integration tests failed with exit code ${exitCode}.`);
  }
}

async function stopChild(child) {
  if (child.exitCode !== null) {
    return;
  }

  child.kill("SIGTERM");
  await Promise.race([
    new Promise((resolve) => child.once("exit", resolve)),
    delay(5_000),
  ]);

  if (child.exitCode === null) {
    child.kill("SIGKILL");
  }
}

async function main() {
  const status = await readSupabaseStatus();
  const port = await reserveLoopbackPort();
  const baseUrl = `http://127.0.0.1:${port}`;
  const environment = {
    ...process.env,
    APP_ENV: "local",
    NEXT_PUBLIC_APP_ENV: "local",
    NEXT_PUBLIC_SUPABASE_URL: status.apiUrl,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: status.publishableKey,
    SUPABASE_PROJECT_REF: "local",
    PRODUCTION_SUPABASE_PROJECT_REF: "production-not-local",
    SERVER_CREDENTIAL_SCOPE: "local",
    VERCEL_REGION: "bom1",
    SUPABASE_SERVICE_ROLE_KEY: status.serviceRoleKey,
    OPENAI_API_KEY: "integration-openai-key-not-real-123",
    OPENAI_WEBHOOK_SECRET: "integration-webhook-secret-not-real",
    HOST_RECOVERY_TOKEN_PEPPER: "integration-recovery-pepper-not-real-123456",
    SAFETY_IDENTIFIER_HMAC_SECRET: "integration-safety-secret-not-real-1234567",
    STORY_MODEL: "gpt-6.1-sol",
    STORY_ESCALATION_MODEL: "gpt-6-astra",
    INTERVENTION_MODEL: "gpt-6.1-sol",
    TEST_APP_BASE_URL: baseUrl,
  };

  const next = spawn(
    nextBinary,
    ["dev", "--webpack", "--hostname", "127.0.0.1", "--port", String(port)],
    {
      cwd: projectRoot,
      env: environment,
      stdio: "inherit",
    },
  );

  try {
    await waitForHealth(baseUrl, next);
    await runVitest(environment);
  } finally {
    await stopChild(next);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
