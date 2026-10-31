import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const SOURCE_EXTENSIONS = new Set([".ts", ".tsx", ".js", ".jsx", ".mjs"]);

const CLIENT_FORBIDDEN_IMPORTS = [
  "server-only",
  "@/lib/env/server",
  "@/lib/openai/",
  "@/lib/supabase/admin",
  "/server",
  ".server",
];

const CONTRACT_FORBIDDEN_IMPORTS = [
  "next",
  "next/",
  "openai",
  "@supabase/",
  "@/lib/",
  "@/modules/",
];

function importedSpecifiers(source) {
  return [
    ...source.matchAll(
      /(?:import|export)\s+(?:[\s\S]*?\s+from\s+)?["']([^"']+)["']/g,
    ),
  ].map((match) => match[1]);
}

function hasServerOnlyDirective(source) {
  return /^\s*import\s+["']server-only["'];/.test(source);
}

function isClientModule(source) {
  return /^\s*["']use client["'];/.test(source);
}

export function checkSourceBoundaries(relativePath, source) {
  const normalizedPath = relativePath.split(path.sep).join("/");
  const imports = importedSpecifiers(source);
  const violations = [];

  if (isClientModule(source)) {
    for (const specifier of imports) {
      if (CLIENT_FORBIDDEN_IMPORTS.some((value) => specifier.includes(value))) {
        violations.push(
          normalizedPath + ": client module imports server-only " + specifier,
        );
      }
    }
  }

  if (normalizedPath.startsWith("src/contracts/")) {
    for (const specifier of imports) {
      if (
        CONTRACT_FORBIDDEN_IMPORTS.some(
          (value) => specifier === value || specifier.startsWith(value),
        )
      ) {
        violations.push(
          normalizedPath + ": contract imports infrastructure " + specifier,
        );
      }
    }
  }

  if (normalizedPath.startsWith("src/modules/gameplay/")) {
    for (const specifier of imports) {
      if (specifier === "openai" || specifier.startsWith("@/lib/openai/")) {
        violations.push(
          normalizedPath + ": gameplay imports model provider " + specifier,
        );
      }
    }
  }

  if (
    normalizedPath.startsWith("src/") &&
    !normalizedPath.startsWith("src/lib/env/") &&
    source.includes("process.env") &&
    !(
      normalizedPath === "src/instrumentation.ts" &&
      [...source.matchAll(/process\.env\.([A-Z0-9_]+)/g)].every(
        (match) => match[1] === "NEXT_RUNTIME",
      ) &&
      !source.includes("process.env[")
    )
  ) {
    violations.push(
      normalizedPath + ": process.env access must stay in src/lib/env",
    );
  }

  const requiresServerOnly =
    normalizedPath === "src/lib/env/server.ts" ||
    normalizedPath === "src/lib/supabase/admin.ts" ||
    normalizedPath.startsWith("src/lib/openai/") ||
    normalizedPath.includes(".server.");

  if (requiresServerOnly && !hasServerOnlyDirective(source)) {
    violations.push(
      normalizedPath + ': server module must begin with import "server-only"',
    );
  }

  return violations;
}

async function sourceFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        return sourceFiles(entryPath);
      }
      return SOURCE_EXTENSIONS.has(path.extname(entry.name)) ? [entryPath] : [];
    }),
  );
  return nested.flat();
}

export async function checkRepositoryBoundaries(rootDirectory) {
  const sourceDirectory = path.join(rootDirectory, "src");
  const files = await sourceFiles(sourceDirectory);
  const violations = [];

  for (const file of files) {
    const source = await readFile(file, "utf8");
    violations.push(
      ...checkSourceBoundaries(path.relative(rootDirectory, file), source),
    );
  }

  return violations;
}

async function main() {
  const rootDirectory = process.cwd();
  const violations = await checkRepositoryBoundaries(rootDirectory);
  if (violations.length > 0) {
    console.error(violations.join("\n"));
    process.exitCode = 1;
    return;
  }
  console.log("Module boundary checks passed.");
}

const executedPath = process.argv[1]
  ? pathToFileURL(path.resolve(process.argv[1])).href
  : undefined;

if (executedPath === import.meta.url) {
  await main();
}
