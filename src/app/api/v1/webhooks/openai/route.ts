import { apiError, noStoreJson } from "@/lib/api/route.server";
import { getOpenAIClient } from "@/lib/openai/client";
import { callSupabaseAdminRpc } from "@/lib/supabase/admin";
import { sha256Hex } from "@/contracts";
import { advanceGenerationJob } from "@/modules/generation/orchestrator.server";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const payload = await request.text();
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
  const responseId = event.data.id;
  if (!responseId || !event.type.startsWith("response."))
    return noStoreJson({ received: true });
  const { data, error } = await callSupabaseAdminRpc(
    "record_generation_webhook",
    {
      provider_event_id: event.id,
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
    try {
      await advanceGenerationJob(receipt.jobId);
    } catch {
      /* Polling reconciliation retries durable work. */
    }
  }
  return noStoreJson({ received: true });
}
