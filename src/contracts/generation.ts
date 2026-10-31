import { z } from "zod";

import {
  IdempotencyKeySchema,
  RoomIdSchema,
  StateVersionSchema,
} from "@/contracts/domain/ids";

export const StartGenerationInputSchema = z.strictObject({
  expectedStateVersion: StateVersionSchema,
  idempotencyKey: IdempotencyKeySchema,
});

export const GenerationPhaseSchema = z.enum([
  "SNAPSHOT",
  "BLUEPRINT",
  "PLAYABLE_CONTENT",
  "VALIDATION",
  "CRITIC",
  "REPAIR",
  "LOCKING",
  "COMPLETE",
]);

export const GenerationStatusSchema = z.enum([
  "PENDING",
  "RUNNING",
  "SUCCEEDED",
  "FAILED",
  "CANCELLED",
]);

export const GenerationJobViewSchema = z.strictObject({
  jobId: z.string().uuid(),
  status: GenerationStatusSchema,
  phase: GenerationPhaseSchema,
  attemptCount: z.number().int().positive(),
  repairCount: z.number().int().nonnegative(),
  escalationCount: z.number().int().nonnegative(),
  sanitizedErrorCode: z.string().nullable(),
  createdAt: z.string(),
  startedAt: z.string().nullable(),
  finishedAt: z.string().nullable(),
});

export const GenerationStatusViewSchema = z.strictObject({
  roomId: RoomIdSchema,
  roomStatus: z.string(),
  stateVersion: StateVersionSchema,
  locked: z.boolean(),
  job: GenerationJobViewSchema.nullable(),
});

export const StartedGenerationSchema = z.strictObject({
  jobId: z.string().uuid(),
  roomId: RoomIdSchema,
  status: GenerationStatusSchema,
  phase: GenerationPhaseSchema,
  stateVersion: StateVersionSchema.optional(),
  replayed: z.boolean(),
});
