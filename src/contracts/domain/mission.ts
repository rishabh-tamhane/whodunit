import { z } from "zod";

export const MissionStatusSchema = z.enum([
  "ASSIGNED",
  "ACCEPTED",
  "COMPLETION_REQUESTED",
  "COMPLETED",
  "FAILED",
  "CONSEQUENCE_PENDING",
  "CONSEQUENCE_RELEASED",
  "WAIVED",
]);

export type MissionStatus = z.infer<typeof MissionStatusSchema>;
