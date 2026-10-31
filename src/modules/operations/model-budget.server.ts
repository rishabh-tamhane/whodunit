import "server-only";

import { z } from "zod";

import { callSupabaseAdminRpc } from "@/lib/supabase/admin";
import {
  estimateModelCostMicrousd,
  maximumModelCallCostMicrousd,
} from "@/modules/operations/model-cost";

const ReservationSchema = z.discriminatedUnion("allowed", [
  z.strictObject({
    allowed: z.literal(true),
    reservationId: z.string().uuid(),
    reservedCostMicrousd: z.number().int().positive(),
  }),
  z.strictObject({
    allowed: z.literal(false),
    reason: z.enum([
      "MONTHLY_HARD_CAP",
      "ROOM_HARD_CAP",
      "STORY_CONCURRENCY_CAP",
    ]),
  }),
]);

export type ModelCallKind = "STORY" | "INTERVENTION";
export type ModelCallReservation = z.infer<typeof ReservationSchema>;

export async function reserveModelCall(input: {
  roomId: string;
  correlationId: string;
  callKind: ModelCallKind;
  modelId: string;
}): Promise<ModelCallReservation> {
  const maximumCostMicrousd = maximumModelCallCostMicrousd(
    input.modelId,
    input.callKind,
  );
  const { data, error } = await callSupabaseAdminRpc("reserve_ai_call", {
    target_room_id: input.roomId,
    request_correlation_id: input.correlationId,
    requested_call_kind: input.callKind,
    requested_model_id: input.modelId,
    maximum_cost_microusd: maximumCostMicrousd,
  });
  if (error)
    throw new Error("MODEL_BUDGET_RESERVATION_FAILED", { cause: error });
  return ReservationSchema.parse(data);
}

export async function settleModelCall(input: {
  reservation: Extract<ModelCallReservation, { allowed: true }>;
  modelId: string;
  inputTokens: number;
  outputTokens: number;
  providerResponseId: string | null;
  status: "COMPLETED" | "FAILED";
  conservativelyChargeReservation?: boolean;
}): Promise<void> {
  const actualCostMicrousd = input.conservativelyChargeReservation
    ? input.reservation.reservedCostMicrousd
    : estimateModelCostMicrousd(
        input.modelId,
        input.inputTokens,
        input.outputTokens,
      );
  const { error } = await callSupabaseAdminRpc("settle_ai_call", {
    target_reservation_id: input.reservation.reservationId,
    provider_response_id: input.providerResponseId,
    final_input_tokens: input.inputTokens,
    final_output_tokens: input.outputTokens,
    actual_cost_microusd: actualCostMicrousd,
    final_status: input.status,
  });
  if (error)
    throw new Error("MODEL_BUDGET_SETTLEMENT_FAILED", { cause: error });
}
