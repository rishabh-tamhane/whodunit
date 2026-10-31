import "server-only";

import { createHmac, randomBytes } from "node:crypto";

import { getServerEnv } from "@/lib/env/server";

export function createRecoveryCredential(now = new Date()) {
  const token = randomBytes(32).toString("base64url");
  const expiresAt = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1_000);

  return {
    token,
    digestForDatabase: digestRecoveryToken(token),
    expiresAt,
  } as const;
}

export function digestRecoveryToken(token: string) {
  const digest = createHmac("sha256", getServerEnv().HOST_RECOVERY_TOKEN_PEPPER)
    .update(token, "utf8")
    .digest("hex");
  return `\\x${digest}`;
}
