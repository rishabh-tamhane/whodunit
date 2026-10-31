import { z } from "zod";

declare const brand: unique symbol;

export type Brand<Value, Name extends string> = Value & {
  readonly [brand]: Name;
};

function brandedUuid<Name extends string>() {
  return z
    .string()
    .uuid()
    .transform((value) => value as Brand<string, Name>);
}

export type AuthUserId = Brand<string, "AuthUserId">;
export type EvidenceId = Brand<string, "EvidenceId">;
export type IdempotencyKey = Brand<string, "IdempotencyKey">;
export type InterventionId = Brand<string, "InterventionId">;
export type MembershipId = Brand<string, "MembershipId">;
export type MissionId = Brand<string, "MissionId">;
export type PlayerId = Brand<string, "PlayerId">;
export type RoomId = Brand<string, "RoomId">;
export type RoundId = Brand<string, "RoundId">;
export type StoryId = Brand<string, "StoryId">;

export const AuthUserIdSchema = brandedUuid<"AuthUserId">();
export const EvidenceIdSchema = brandedUuid<"EvidenceId">();
export const IdempotencyKeySchema = brandedUuid<"IdempotencyKey">();
export const InterventionIdSchema = brandedUuid<"InterventionId">();
export const MembershipIdSchema = brandedUuid<"MembershipId">();
export const MissionIdSchema = brandedUuid<"MissionId">();
export const PlayerIdSchema = brandedUuid<"PlayerId">();
export const RoomIdSchema = brandedUuid<"RoomId">();
export const RoundIdSchema = brandedUuid<"RoundId">();
export const StoryIdSchema = brandedUuid<"StoryId">();

export type StateVersion = Brand<string, "StateVersion">;

export const StateVersionSchema = z
  .string()
  .regex(/^(0|[1-9]\d*)$/, "State version must be an unsigned decimal string.")
  .transform((value) => value as StateVersion);
