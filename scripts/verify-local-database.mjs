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

async function run(command, arguments_) {
  const child = spawn(command, arguments_, {
    cwd: projectRoot,
    env: commandEnvironment,
    stdio: "inherit",
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
    await run(supabaseBinary, ["start"]);
    await run(supabaseBinary, ["db", "reset", "--local"]);
    await run(supabaseBinary, ["test", "db", "--local"]);
    await run(npmBinary, ["run", "test:integration"]);
  } catch (error) {
    failure = error;
  } finally {
    if (process.env.CI === "true" && startAttempted) {
      try {
        await run(supabaseBinary, ["stop", "--no-backup"]);
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
