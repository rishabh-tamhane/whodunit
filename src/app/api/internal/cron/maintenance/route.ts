import { timingSafeEqual } from "node:crypto";

import { noStoreJson } from "@/lib/api/route.server";
import { getServerEnv } from "@/lib/env/server";
import { callSupabaseAdminRpc } from "@/lib/supabase/admin";
import { advanceGenerationJob } from "@/modules/generation/orchestrator.server";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function authorized(request: Request): boolean {
  const supplied = request.headers
    .get("authorization")
    ?.replace(/^Bearer /, "");
  const expected = getServerEnv().CRON_SECRET;
  if (!supplied || supplied.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(supplied), Buffer.from(expected));
}

export async function GET(request: Request) {
  if (!authorized(request))
    return noStoreJson({ error: "unauthorized" }, { status: 401 });
  const correlationId = crypto.randomUUID();
  const reconciled = await callSupabaseAdminRpc(
    "reconcile_stale_generation_jobs",
  );
  if (reconciled.error)
    return noStoreJson(
      { error: "reconciliation unavailable" },
      { status: 503 },
    );
  const recovery = reconciled.data as {
    recoverableJobIds?: string[];
    failedCount?: number;
  };
  let recoveredCount = 0;
  for (const jobId of recovery.recoverableJobIds ?? []) {
    try {
      await advanceGenerationJob(jobId);
      recoveredCount += 1;
    } catch {
      // The durable job remains safely retryable or transitions to FAILED.
    }
  }
  const [purged, cleanup] = await Promise.all([
    callSupabaseAdminRpc("purge_terminal_generation_sources"),
    callSupabaseAdminRpc("cleanup_expired_rooms", { batch_size: 25 }),
  ]);
  if (purged.error || cleanup.error)
    return noStoreJson({ error: "maintenance incomplete" }, { status: 503 });
  const cleanupResult = cleanup.data as {
    deletedCount?: number;
    remainingEligible?: number;
  };
  await callSupabaseAdminRpc("record_operational_event", {
    correlation_id: correlationId,
    event_type: "MAINTENANCE_COMPLETED",
    severity: cleanupResult.remainingEligible ? "WARNING" : "INFO",
    route_code: "CRON_MAINTENANCE",
    room_hash: null,
    duration_ms: null,
    status_code: 200,
    error_code: null,
    metadata_json: {
      count: recoveredCount,
      deletedCount: cleanupResult.deletedCount ?? 0,
      remainingCount: cleanupResult.remainingEligible ?? 0,
    },
  });
  return noStoreJson({
    correlationId,
    recoveredCount,
    failedCount: recovery.failedCount ?? 0,
    purgedCount: Number(purged.data ?? 0),
    deletedCount: cleanupResult.deletedCount ?? 0,
    remainingEligible: cleanupResult.remainingEligible ?? 0,
  });
}
