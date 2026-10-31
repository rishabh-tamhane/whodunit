import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const executableSuffix = process.platform === "win32" ? ".cmd" : "";
const supabaseBinary = path.join(
  projectRoot,
  "node_modules",
  ".bin",
  "supabase" + executableSuffix,
);
const npmBinary = process.platform === "win32" ? "npm.cmd" : "npm";
const commandEnvironment = {
  ...process.env,
  SUPABASE_TELEMETRY_DISABLED: "1",
};

async function run(command, arguments_, { hideStdout = false } = {}) {
  const child = spawn(command, arguments_, {
    cwd: projectRoot,
    env: commandEnvironment,
    stdio: hideStdout ? ["ignore", "ignore", "inherit"] : "inherit",
  });

  const exitCode = await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => resolve(code ?? 1));
  });

  if (exitCode !== 0) {
    throw new Error(
      `${path.basename(command)} ${arguments_.join(" ")} failed with exit code ${exitCode}.`,
    );
  }
}

async function main() {
  let startAttempted = false;
  let failure;

  try {
    startAttempted = true;
    // `supabase start` prints disposable local API keys to stdout. The
    // integration runner reads them directly from `supabase status` instead.
    await run(supabaseBinary, ["start"], { hideStdout: true });
    await run(supabaseBinary, ["db", "reset", "--local"]);
    await run(supabaseBinary, ["test", "db", "--local"]);
    await run(npmBinary, ["run", "test:integration"]);
    await run(npmBinary, ["run", "test:e2e"]);
  } catch (error) {
    failure = error;
  } finally {
    if (process.env.CI === "true" && startAttempted) {
      try {
        await run(supabaseBinary, ["stop", "--no-backup"], {
          hideStdout: true,
        });
      } catch (cleanupError) {
        if (failure) {
          console.error(
            "Local Supabase cleanup also failed:",
            cleanupError instanceof Error ? cleanupError.message : cleanupError,
          );
        } else {
          failure = cleanupError;
        }
      }
    }
  }

  if (failure) {
    throw failure;
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
