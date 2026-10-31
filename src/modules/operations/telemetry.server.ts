import "server-only";

import { callSupabaseAdminRpc } from "@/lib/supabase/admin";

export type OperationalMetadata = Readonly<
  Partial<{
    attempt: number;
    count: number;
    phase: string;
    source: string;
    fallback: boolean;
    deletedCount: number;
    remainingCount: number;
    inputTokens: number;
    outputTokens: number;
    latencyMs: number;
    estimatedCostMicrousd: number;
    budgetReason: string;
  }>
>;

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export async function recordOperationalEvent(input: {
  correlationId: string;
  eventType: string;
  severity?: "INFO" | "WARNING" | "ERROR";
  routeCode?: string | null;
  roomId?: string | null;
  durationMs?: number | null;
  statusCode?: number | null;
  errorCode?: string | null;
  metadata?: OperationalMetadata;
}): Promise<boolean> {
  const { error } = await callSupabaseAdminRpc("record_operational_event", {
    correlation_id: input.correlationId,
    event_type: input.eventType,
    severity: input.severity ?? "INFO",
    route_code: input.routeCode ?? null,
    room_hash: input.roomId ? await sha256(input.roomId) : null,
    duration_ms: input.durationMs ?? null,
    status_code: input.statusCode ?? null,
    error_code: input.errorCode ?? null,
    metadata_json: input.metadata ?? {},
  });
  return !error;
}
