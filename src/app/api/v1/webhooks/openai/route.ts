import { after } from "next/server";

import { apiError, noStoreJson } from "@/lib/api/route.server";
import { getOpenAIClient } from "@/lib/openai/client";
import { callSupabaseAdminRpc } from "@/lib/supabase/admin";
import { sha256Hex } from "@/contracts";
import { advanceGenerationJob } from "@/modules/generation/orchestrator.server";

export const dynamic = "force-dynamic";
const MAX_WEBHOOK_BYTES = 1024 * 1024;

export async function POST(request: Request) {
  if (
    !(request.headers.get("content-type") ?? "")
      .toLowerCase()
      .includes("application/json")
  )
    return apiError(
      request,
      400,
      "VALIDATION_ERROR",
      "Webhook content type is invalid.",
    );
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_WEBHOOK_BYTES)
    return apiError(
      request,
      413,
      "VALIDATION_ERROR",
      "Webhook payload is too large.",
    );
  const payload = await request.text();
  if (new TextEncoder().encode(payload).byteLength > MAX_WEBHOOK_BYTES)
    return apiError(
      request,
      413,
      "VALIDATION_ERROR",
      "Webhook payload is too large.",
    );
  let event: { id: string; type: string; data: { id?: string } };
  try {
    event = (await getOpenAIClient().webhooks.unwrap(
      payload,
      request.headers,
    )) as typeof event;
  } catch {
    return apiError(
      request,
      400,
      "VALIDATION_ERROR",
      "Invalid webhook signature.",
    );
  }
  const deliveryId = request.headers.get("webhook-id");
  if (!deliveryId)
    return apiError(
      request,
      400,
      "VALIDATION_ERROR",
      "Webhook delivery identifier is missing.",
    );
  const responseId = event.data.id;
  if (!responseId || !event.type.startsWith("response."))
    return noStoreJson({ received: true });
  const { data, error } = await callSupabaseAdminRpc(
    "record_generation_webhook",
    {
      provider_event_id: deliveryId,
      provider_response_id: responseId,
      provider_event_type: event.type,
      payload_checksum_hex: await sha256Hex(payload),
    },
  );
  if (error)
    return apiError(
      request,
      503,
      "SERVICE_UNAVAILABLE",
      "Webhook processing is temporarily unavailable.",
    );
  const receipt = data as {
    known?: boolean;
    duplicate?: boolean;
    jobId?: string;
  };
  if (receipt.known && !receipt.duplicate && receipt.jobId) {
    const jobId = receipt.jobId;
    after(async () => {
      try {
        await advanceGenerationJob(jobId);
      } catch {
        /* Scheduled reconciliation retries durable work. */
      }
    });
  }
  return noStoreJson({ received: true });
}
