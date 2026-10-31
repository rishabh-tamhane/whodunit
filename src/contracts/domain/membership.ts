import { z } from "zod";

export const MembershipStatusSchema = z.enum(["PENDING", "ACTIVE", "REVOKED"]);

export type MembershipStatus = z.infer<typeof MembershipStatusSchema>;

export const ClaimKindSchema = z.enum(["INITIAL_CLAIM", "RECONNECT"]);

export type ClaimKind = z.infer<typeof ClaimKindSchema>;
