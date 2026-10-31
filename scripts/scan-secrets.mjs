import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ignoredDirectories = new Set([
  ".git",
  ".next",
  ".supabase",
  "node_modules",
  ".temp",
]);
const ignoredFiles = new Set(["package-lock.json"]);
const patterns = [
  { name: "OpenAI API key", expression: /sk-(?:proj-)?[A-Za-z0-9_-]{20,}/ },
  { name: "Supabase secret key", expression: /sb_secret_[A-Za-z0-9_-]{20,}/ },
  {
    name: "private key",
    expression: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  },
];

async function files(directory) {
  const output = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && ignoredDirectories.has(entry.name)) continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...(await files(absolute)));
    else if (
      !ignoredFiles.has(entry.name) &&
      (!entry.name.startsWith(".env") || entry.name === ".env.example")
    )
      output.push(absolute);
  }
  return output;
}

const findings = [];
for (const filename of await files(root)) {
  let content;
  try {
    content = await readFile(filename, "utf8");
  } catch {
    continue;
  }
  for (const pattern of patterns) {
    if (pattern.expression.test(content))
      findings.push(
        `${path.relative(root, filename)}: possible ${pattern.name}`,
      );
  }
}

if (findings.length > 0) {
  console.error(findings.join("\n"));
  process.exitCode = 1;
} else {
  console.log("Secret scan passed.");
}
