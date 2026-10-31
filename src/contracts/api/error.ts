import { z } from "zod";

import { StateVersionSchema } from "@/contracts/domain/ids";

export const ApiErrorCodeSchema = z.enum([
  "VALIDATION_ERROR",
  "AUTHENTICATION_REQUIRED",
  "FORBIDDEN",
  "NOT_FOUND",
  "CONFLICT",
  "STALE_STATE_VERSION",
  "IDEMPOTENCY_CONFLICT",
  "INVALID_ROOM_STATE",
  "RATE_LIMITED",
  "SERVICE_UNAVAILABLE",
  "INTERNAL_ERROR",
]);

export type ApiErrorCode = z.infer<typeof ApiErrorCodeSchema>;

export const ApiErrorEnvelopeSchema = z.strictObject({
  error: z.strictObject({
    code: ApiErrorCodeSchema,
    message: z.string().min(1),
    requestId: z.string().min(1),
    fieldErrors: z.record(z.string(), z.array(z.string())).optional(),
    currentStateVersion: StateVersionSchema.optional(),
  }),
});

export type ApiErrorEnvelope = z.infer<typeof ApiErrorEnvelopeSchema>;
