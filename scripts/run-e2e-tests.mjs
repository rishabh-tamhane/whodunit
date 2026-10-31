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
const tsxBinary = localBinary("tsx");
const playwrightBinary = localBinary("playwright");

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
      if (apiUrl && publishableKey && serviceRoleKey)
        return { apiUrl, publishableKey, serviceRoleKey };
      lastError = new Error(
        "Local Supabase status is missing required values.",
      );
    } catch (error) {
      lastError = error;
    }
    if (attempt < 5) await delay(2_000);
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
    throw new Error("Could not reserve a loopback port for E2E tests.");
  }
  await new Promise((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
  return address.port;
}

async function waitForUrl(url, child, label) {
  let lastError;
  for (let attempt = 1; attempt <= 180; attempt += 1) {
    if (child.exitCode !== null)
      throw new Error(
        `${label} exited before becoming ready (${child.exitCode}).`,
      );
    try {
      const response = await fetch(url);
      if (response.ok) return;
      lastError = new Error(`${label} returned HTTP ${response.status}.`);
    } catch (error) {
      lastError = error;
    }
    await delay(250);
  }
  throw new Error(`${label} did not become ready within 45 seconds.`, {
    cause: lastError,
  });
}

async function runPlaywright(environment) {
  const arguments_ = ["test", ...process.argv.slice(2)];
  const child = spawn(playwrightBinary, arguments_, {
    cwd: projectRoot,
    env: environment,
    stdio: "inherit",
  });
  const exitCode = await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => resolve(code ?? 1));
  });
  if (exitCode !== 0)
    throw new Error(`Playwright tests failed with exit code ${exitCode}.`);
}

async function runCommand(command, arguments_, environment, label) {
  const child = spawn(command, arguments_, {
    cwd: projectRoot,
    env: environment,
    stdio: "inherit",
  });
  const exitCode = await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => resolve(code ?? 1));
  });
  if (exitCode !== 0)
    throw new Error(`${label} failed with exit code ${exitCode}.`);
}

async function stopChild(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await Promise.race([
    new Promise((resolve) => child.once("exit", resolve)),
    delay(5_000),
  ]);
  if (child.exitCode === null) child.kill("SIGKILL");
}

async function main() {
  const status = await readSupabaseStatus();
  const appPort = await reserveLoopbackPort();
  const mockPort = await reserveLoopbackPort();
  const baseUrl = `http://127.0.0.1:${appPort}`;
  const mockUrl = `http://127.0.0.1:${mockPort}`;
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
    OPENAI_API_KEY: "e2e-openai-key-not-real-123",
    OPENAI_BASE_URL: `${mockUrl}/v1`,
    OPENAI_WEBHOOK_SECRET: "e2e-webhook-secret-not-real",
    HOST_RECOVERY_TOKEN_PEPPER: "e2e-recovery-pepper-not-real-123456789",
    SAFETY_IDENTIFIER_HMAC_SECRET: "e2e-safety-secret-not-real-1234567890",
    CRON_SECRET: "e2e-cron-secret-not-real-1234567890123456",
    STORY_MODEL: "gpt-6.1-sol",
    STORY_ESCALATION_MODEL: "gpt-6-astra",
    INTERVENTION_MODEL: "gpt-6.1-sol",
    E2E_BASE_URL: baseUrl,
  };
  await runCommand(
    nextBinary,
    ["build", "--webpack"],
    environment,
    "Next.js build",
  );
  const mock = spawn(
    tsxBinary,
    ["scripts/openai-mock-server.ts", String(mockPort)],
    {
      cwd: projectRoot,
      env: environment,
      stdio: "inherit",
    },
  );
  const next = spawn(
    nextBinary,
    ["start", "--hostname", "127.0.0.1", "--port", String(appPort)],
    { cwd: projectRoot, env: environment, stdio: "inherit" },
  );
  try {
    await Promise.all([
      waitForUrl(`${mockUrl}/health`, mock, "OpenAI mock"),
      waitForUrl(`${baseUrl}/api/v1/health`, next, "Next.js"),
    ]);
    await runPlaywright(environment);
  } finally {
    await Promise.all([stopChild(next), stopChild(mock)]);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
