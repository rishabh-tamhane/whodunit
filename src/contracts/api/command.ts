import { z } from "zod";

import {
  IdempotencyKeySchema,
  StateVersionSchema,
} from "@/contracts/domain/ids";

export const DomainCommandMetadataSchema = z.strictObject({
  idempotencyKey: IdempotencyKeySchema,
  expectedStateVersion: StateVersionSchema,
});

export type DomainCommandMetadata = z.infer<typeof DomainCommandMetadataSchema>;
