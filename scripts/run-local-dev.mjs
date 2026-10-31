import { execFile, spawn } from "node:child_process";
import { existsSync } from "node:fs";
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

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

async function runSupabaseStart() {
  try {
    await execFileAsync(supabaseBinary, ["start"], {
      cwd: projectRoot,
      env: { ...process.env, SUPABASE_TELEMETRY_DISABLED: "1" },
      maxBuffer: 2 * 1024 * 1024,
    });
  } catch {
    throw new Error(
      "Local Supabase could not start. Confirm Docker Desktop is running.",
    );
  }
}

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

      lastError = new Error("Local Supabase status is incomplete.");
    } catch (error) {
      lastError = error;
    }

    if (attempt < 5) await delay(2_000);
  }

  throw new Error("Local Supabase did not become ready in time.", {
    cause: lastError,
  });
}

async function main() {
  if (
    !existsSync(path.join(projectRoot, ".env.local")) &&
    !process.env.OPENAI_API_KEY
  ) {
    throw new Error(
      "Create .env.local with OPENAI_API_KEY before starting local development.",
    );
  }

  await runSupabaseStart();
  const status = await readSupabaseStatus();
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
    OPENAI_BASE_URL: "https://api.openai.com/v1",
    OPENAI_WEBHOOK_SECRET: "local-webhook-secret-not-production",
    HOST_RECOVERY_TOKEN_PEPPER: "local-recovery-pepper-never-use-in-production",
    SAFETY_IDENTIFIER_HMAC_SECRET:
      "local-safety-identifier-secret-never-production",
    CRON_SECRET: "local-cron-secret-never-use-in-production",
    STORY_MODEL: "gpt-6.1-sol",
    STORY_ESCALATION_MODEL: "gpt-6-astra",
    INTERVENTION_MODEL: "gpt-6.1-sol",
  };

  console.info(
    "Local Supabase is ready. Starting Whodunit at http://127.0.0.1:3000",
  );
  console.info("Press Ctrl+C to stop Next.js; run npm run db:stop when done.");

  const next = spawn(
    nextBinary,
    ["dev", "--webpack", "--hostname", "127.0.0.1", "--port", "3000"],
    {
      cwd: projectRoot,
      env: environment,
      stdio: "inherit",
    },
  );

  const exitCode = await new Promise((resolve, reject) => {
    next.once("error", reject);
    next.once("exit", (code, signal) =>
      resolve(signal === "SIGINT" || signal === "SIGTERM" ? 0 : (code ?? 1)),
    );
  });
  process.exitCode = exitCode;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
