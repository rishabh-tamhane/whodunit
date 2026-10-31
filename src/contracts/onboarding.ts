import { z } from "zod";

import {
  MembershipIdSchema,
  PlayerIdSchema,
  RoomIdSchema,
  StateVersionSchema,
} from "@/contracts/domain/ids";
import { RoomStateSchema } from "@/contracts/domain/lifecycle";
import {
  ClaimKindSchema,
  MembershipStatusSchema,
} from "@/contracts/domain/membership";

export const RoomCodeSchema = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z0-9]{4,12}$/);

export const PlayerSlotInputSchema = z.strictObject({
  displayName: z.string().trim().min(1).max(100),
  costume: z.string().trim().min(1).max(200),
  hostBackground: z.string().trim().max(1_000).optional(),
});

export const RoomConfigurationSchema = z
  .strictObject({
    durationProfileVersion: z.literal("duration-v1"),
    factionProfileVersion: z.literal("factions-v1"),
    durationMinutes: z.union([
      z.literal(30),
      z.literal(45),
      z.literal(60),
      z.literal(90),
      z.literal(120),
    ]),
    murdererCount: z.number().int().min(1).max(4),
    accompliceCount: z.number().int().min(0).max(4),
    innocentCount: z.number().int().min(1).max(11),
    murdererAware: z.boolean(),
    playerSlots: z.array(PlayerSlotInputSchema).min(4).max(12),
  })
  .superRefine((configuration, context) => {
    const factionTotal =
      configuration.murdererCount +
      configuration.accompliceCount +
      configuration.innocentCount;
    if (factionTotal !== configuration.playerSlots.length) {
      context.addIssue({
        code: "custom",
        path: ["innocentCount"],
        message: "Faction counts must equal the number of players.",
      });
    }
  });

export const RoomMutationInputSchema = z.strictObject({
  roomId: RoomIdSchema,
  expectedStateVersion: StateVersionSchema,
});

export const SaveRoomConfigurationInputSchema = RoomMutationInputSchema.extend({
  configuration: RoomConfigurationSchema,
});

export const RoomMutationResultSchema = z.strictObject({
  roomId: RoomIdSchema,
  roomCode: RoomCodeSchema,
  status: RoomStateSchema,
  stateVersion: StateVersionSchema,
  playerCount: z.number().int().min(4).max(12).optional(),
});

export const CreatedRoomSchema = RoomMutationResultSchema.extend({
  recoveryExpiresAt: z.iso.datetime({ offset: true }),
  recoveryPath: z.string().startsWith("/host/recover#token="),
  joinPath: z.string().startsWith("/join?code="),
});

export const SafeLobbySlotSchema = z.strictObject({
  playerId: PlayerIdSchema,
  displayName: z.string(),
  costume: z.string(),
  seatOrder: z.number().int(),
  slotStatus: z.enum(["AVAILABLE", "PENDING", "OCCUPIED"]),
});

export const SafeLobbySchema = z.strictObject({
  roomId: RoomIdSchema,
  roomCode: RoomCodeSchema,
  roomStatus: RoomStateSchema,
  slots: z.array(SafeLobbySlotSchema),
});

export const RequestClaimInputSchema = z.strictObject({
  playerId: PlayerIdSchema,
  requestKind: ClaimKindSchema,
});

export const ReviewClaimInputSchema = z.strictObject({
  expectedStateVersion: StateVersionSchema,
  decision: z.enum(["APPROVE", "REJECT"]),
});

export const ClaimResultSchema = z.strictObject({
  claimId: MembershipIdSchema,
  roomId: RoomIdSchema,
  playerId: PlayerIdSchema,
  status: MembershipStatusSchema,
  requestKind: ClaimKindSchema,
  stateVersion: StateVersionSchema,
  replayed: z.boolean().optional(),
});

export const ReadinessSchema = z.strictObject({
  ready: z.boolean(),
  playerCount: z.number().int(),
  activeMembershipCount: z.number().int(),
  acknowledgedPlayerCount: z.number().int(),
  completedDescriptionCount: z.number().int(),
  requiredDescriptionCount: z.number().int(),
  hostGuidanceAcknowledged: z.boolean(),
  roomConsentConfirmed: z.boolean(),
  configurationValid: z.boolean(),
  missing: z.strictObject({
    claims: z.number().int(),
    playerAcknowledgements: z.number().int(),
    descriptions: z.number().int(),
    hostGuidance: z.boolean(),
    roomConsent: z.boolean(),
  }),
});

const OnboardingRoomSchema = z.strictObject({
  id: RoomIdSchema,
  roomCode: RoomCodeSchema,
  status: RoomStateSchema,
  stateVersion: StateVersionSchema,
});

const OnboardingPlayerSummarySchema = z.strictObject({
  playerId: PlayerIdSchema,
  displayName: z.string(),
  costume: z.string(),
  seatOrder: z.number().int(),
});

export const GameMasterOnboardingViewSchema = z.strictObject({
  actor: z.literal("GAME_MASTER"),
  room: OnboardingRoomSchema.extend({
    config: z.record(z.string(), z.unknown()),
  }),
  players: z.array(
    OnboardingPlayerSummarySchema.extend({
      acknowledged: z.boolean(),
      claimStatus: z.enum([
        "UNCLAIMED",
        "PENDING",
        "CONNECTED",
        "DISCONNECTED",
      ]),
      activeMembershipId: MembershipIdSchema.nullable(),
    }),
  ),
  claims: z.array(
    z.strictObject({
      claimId: MembershipIdSchema,
      playerId: PlayerIdSchema,
      requestKind: ClaimKindSchema,
      status: MembershipStatusSchema,
      createdAt: z.string(),
    }),
  ),
  readiness: ReadinessSchema,
});

export const PlayerOnboardingViewSchema = z.strictObject({
  actor: z.literal("PLAYER"),
  room: OnboardingRoomSchema,
  self: z.strictObject({
    playerId: PlayerIdSchema,
    displayName: z.string(),
    costume: z.string(),
    acknowledged: z.boolean(),
  }),
  players: z.array(OnboardingPlayerSummarySchema),
  descriptionResponses: z.array(
    z.strictObject({
      subjectPlayerId: PlayerIdSchema,
      responseStatus: z.enum(["SUBMITTED", "DECLINED"]),
      descriptionText: z.string().nullable(),
    }),
  ),
});

export const PendingOnboardingViewSchema = z.strictObject({
  actor: z.literal("PENDING_PLAYER"),
  roomId: RoomIdSchema,
  claim: z.strictObject({
    claimId: MembershipIdSchema,
    playerId: PlayerIdSchema,
    requestKind: ClaimKindSchema,
    status: z.literal("PENDING"),
  }),
});

export const OnboardingViewSchema = z.discriminatedUnion("actor", [
  GameMasterOnboardingViewSchema,
  PlayerOnboardingViewSchema,
  PendingOnboardingViewSchema,
]);

export const SaveDescriptionInputSchema = z
  .strictObject({
    expectedStateVersion: StateVersionSchema,
    subjectPlayerId: PlayerIdSchema,
    responseStatus: z.enum(["SUBMITTED", "DECLINED"]),
    descriptionText: z.string().max(500).nullable(),
  })
  .superRefine((response, context) => {
    if (
      response.responseStatus === "SUBMITTED" &&
      !response.descriptionText?.trim()
    ) {
      context.addIssue({
        code: "custom",
        path: ["descriptionText"],
        message: "Enter a description or choose Prefer not to answer.",
      });
    }
  });

export const RecoverHostInputSchema = z.strictObject({
  token: z.string().min(40).max(100),
});

export const RecoveredHostSchema = RoomMutationResultSchema.extend({
  recoveryExpiresAt: z.iso.datetime({ offset: true }),
  recoveryPath: z.string().startsWith("/host/recover#token="),
});
