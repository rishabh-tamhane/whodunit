import { after } from "next/server";

import {
  apiError,
  getRequestCorrelationId,
  noStoreJson,
} from "@/lib/api/route.server";
import { getOpenAIClient } from "@/lib/openai/client";
import { callSupabaseAdminRpc } from "@/lib/supabase/admin";
import { sha256Hex } from "@/contracts";
import { advanceGenerationJob } from "@/modules/generation/orchestrator.server";
import { recordOperationalEvent } from "@/modules/operations/telemetry.server";

export const dynamic = "force-dynamic";
const MAX_WEBHOOK_BYTES = 1024 * 1024;

async function rejectedWebhook(
  request: Request,
  correlationId: string,
  status: number,
  message: string,
) {
  await recordOperationalEvent({
    correlationId,
    eventType: "WEBHOOK_REJECTED",
    severity: "WARNING",
    routeCode: "OPENAI_WEBHOOK",
    statusCode: status,
    errorCode: "WEBHOOK_REJECTED",
    metadata: { source: "OPENAI_WEBHOOK", count: 1 },
  });
  return apiError(request, status, "VALIDATION_ERROR", message);
}

export async function POST(request: Request) {
  const correlationId = getRequestCorrelationId(request);
  if (
    !(request.headers.get("content-type") ?? "")
      .toLowerCase()
      .includes("application/json")
  )
    return rejectedWebhook(
      request,
      correlationId,
      400,
      "Webhook content type is invalid.",
    );
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_WEBHOOK_BYTES)
    return rejectedWebhook(
      request,
      correlationId,
      413,
      "Webhook payload is too large.",
    );
  const payload = await request.text();
  if (new TextEncoder().encode(payload).byteLength > MAX_WEBHOOK_BYTES)
    return rejectedWebhook(
      request,
      correlationId,
      413,
      "Webhook payload is too large.",
    );
  let event: { id: string; type: string; data: { id?: string } };
  try {
    event = (await getOpenAIClient().webhooks.unwrap(
      payload,
      request.headers,
    )) as typeof event;
  } catch {
    return rejectedWebhook(
      request,
      correlationId,
      400,
      "Invalid webhook signature.",
    );
  }
  const deliveryId = request.headers.get("webhook-id");
  if (!deliveryId)
    return rejectedWebhook(
      request,
      correlationId,
      400,
      "Webhook delivery identifier is missing.",
    );
  const responseId = event.data.id;
  if (!responseId || !event.type.startsWith("response.")) {
    await recordOperationalEvent({
      correlationId,
      eventType: "WEBHOOK_ACCEPTED",
      routeCode: "OPENAI_WEBHOOK",
      statusCode: 200,
      metadata: { source: "OPENAI_WEBHOOK", count: 0 },
    });
    return noStoreJson({ received: true });
  }
  const { data, error } = await callSupabaseAdminRpc(
    "record_generation_webhook",
    {
      provider_event_id: deliveryId,
      provider_response_id: responseId,
      provider_event_type: event.type,
      payload_checksum_hex: await sha256Hex(payload),
    },
  );
  if (error) {
    await recordOperationalEvent({
      correlationId,
      eventType: "WEBHOOK_PROCESSING_FAILED",
      severity: "ERROR",
      routeCode: "OPENAI_WEBHOOK",
      statusCode: 503,
      errorCode: "WEBHOOK_RECEIPT_UNAVAILABLE",
      metadata: { source: "OPENAI_WEBHOOK", count: 1 },
    });
    return apiError(
      request,
      503,
      "SERVICE_UNAVAILABLE",
      "Webhook processing is temporarily unavailable.",
    );
  }
  const receipt = data as {
    known?: boolean;
    duplicate?: boolean;
    jobId?: string;
  };
  let flowCorrelationId = correlationId;
  const resolved = await callSupabaseAdminRpc("resolve_ai_call_correlation", {
    provider_response_id: responseId,
  });
  if (
    !resolved.error &&
    typeof resolved.data === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      resolved.data,
    )
  )
    flowCorrelationId = resolved.data;
  await recordOperationalEvent({
    correlationId: flowCorrelationId,
    eventType: "WEBHOOK_ACCEPTED",
    routeCode: "OPENAI_WEBHOOK",
    statusCode: 200,
    metadata: {
      source: "OPENAI_WEBHOOK",
      count: receipt.duplicate ? 0 : 1,
    },
  });
  if (receipt.known && !receipt.duplicate && receipt.jobId) {
    const jobId = receipt.jobId;
    after(async () => {
      try {
        await advanceGenerationJob(jobId, flowCorrelationId);
      } catch {
        /* Scheduled reconciliation retries durable work. */
      }
    });
  }
  return noStoreJson({ received: true });
}
