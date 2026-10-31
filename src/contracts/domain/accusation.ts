import { z } from "zod";

export const AccusationStatusSchema = z.enum(["DRAFT", "SUBMITTED"]);

export type AccusationStatus = z.infer<typeof AccusationStatusSchema>;
