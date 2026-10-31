import { z } from "zod";

import { DomainCommandMetadataSchema } from "@/contracts/api/command";

const ActorRoomSchema = z.object({
  id: z.string().uuid(),
  roomCode: z.string(),
  status: z.string(),
  stateVersion: z.union([z.string(), z.number()]).transform(String),
  currentRoundId: z.string().uuid().nullable().optional(),
});

export const GameMasterViewSchema = z.object({
  actor: z.literal("GAME_MASTER"),
  room: ActorRoomSchema,
  players: z.array(z.record(z.string(), z.unknown())),
  claims: z.array(z.record(z.string(), z.unknown())),
  generation: z.array(z.record(z.string(), z.unknown())),
  story: z
    .object({
      id: z.string().uuid(),
      package: z.record(z.string(), z.unknown()),
      solution: z.record(z.string(), z.unknown()),
    })
    .optional(),
  runtime: z.record(z.string(), z.unknown()).optional(),
  submittedState: z.record(z.string(), z.unknown()).optional(),
  results: z.record(z.string(), z.unknown()).optional(),
});

export const PlayerViewSchema = z.object({
  actor: z.literal("PLAYER"),
  room: ActorRoomSchema,
  self: z.object({
    playerId: z.string().uuid(),
    displayName: z.string(),
    costume: z.string(),
    seatOrder: z.number().int(),
  }),
  lobby: z.array(z.record(z.string(), z.unknown())),
  dossier: z.record(z.string(), z.unknown()).optional(),
  missions: z.array(z.record(z.string(), z.unknown())).optional(),
  evidence: z.array(z.record(z.string(), z.unknown())).optional(),
  releasedConsequences: z.array(z.record(z.string(), z.unknown())).optional(),
  releasedInterventions: z.array(z.record(z.string(), z.unknown())).optional(),
  personalRevelations: z.array(z.record(z.string(), z.unknown())).optional(),
  events: z.array(z.record(z.string(), z.unknown())).optional(),
  notebook: z.record(z.string(), z.unknown()).nullable().optional(),
  submittedTheories: z.array(z.record(z.string(), z.unknown())).optional(),
  finalAccusation: z.record(z.string(), z.unknown()).nullable().optional(),
  reveal: z.unknown().optional(),
});

export const ActorViewSchema = z.discriminatedUnion("actor", [
  GameMasterViewSchema,
  PlayerViewSchema,
]);

export const NotebookSuspectSchema = z.strictObject({
  playerId: z.string().uuid(),
  suspectedRole: z.enum(["MURDERER", "ACCOMPLICE"]),
});
export const SaveNotebookInputSchema = z.strictObject({
  expectedRevision: z.number().int().nonnegative(),
  notesText: z.string().max(10_000),
  suspects: z.array(NotebookSuspectSchema).max(11),
});
export const NotebookSaveResultSchema = z.strictObject({
  noteId: z.string().uuid(),
  revision: z.number().int().nonnegative(),
  updatedAt: z.string(),
});

export const SubmitTheoryInputSchema = DomainCommandMetadataSchema.extend({
  structuredClaim: z.strictObject({
    suspects: z.array(NotebookSuspectSchema).max(11),
    evidenceIds: z.array(z.string().uuid()).max(50),
  }),
  submittedExplanation: z.string().max(2_000),
});

export const RoomCommandInputSchema = DomainCommandMetadataSchema;
export const MissionCommandInputSchema = DomainCommandMetadataSchema.extend({
  action: z.enum([
    "ACCEPT",
    "REQUEST_COMPLETION",
    "APPROVE",
    "REJECT",
    "FAIL",
    "WAIVE",
    "EXTEND",
  ]),
  extensionMinutes: z.number().int().min(1).max(60).nullable().optional(),
});
export const CanonicalReleaseInputSchema = DomainCommandMetadataSchema.extend({
  objectKind: z.enum(["EVIDENCE", "CONSEQUENCE"]),
  decision: z.enum(["RELEASE", "WAIVE"]),
});
export const GameplayCommandResultSchema = z.object({
  stateVersion: z.string(),
  replayed: z.boolean(),
  status: z.string().optional(),
  missionId: z.string().uuid().optional(),
  currentRoundId: z.string().uuid().nullable().optional(),
});

export const RequestInterventionInputSchema = DomainCommandMetadataSchema;
export const ResolveInterventionInputSchema =
  DomainCommandMetadataSchema.extend({
    decision: z.enum(["APPROVE", "REJECT"]),
  });
export const InterventionPreviewResultSchema = z.object({
  requestId: z.string().uuid(),
  previewId: z.string().uuid().optional(),
  status: z.enum(["PREVIEW_READY", "FAILED"]),
  selectionSource: z.enum(["LIVE_AI", "PREPARED_FALLBACK"]).optional(),
  candidateKind: z
    .enum([
      "DIRECTED_QUESTION",
      "RELEASE_EVIDENCE",
      "RELEASE_CONSEQUENCE",
      "ACTIVATE_MISSION",
    ])
    .optional(),
  sourceSpecId: z.string().uuid().nullable().optional(),
  effect: z.record(z.string(), z.unknown()).optional(),
  audience: z.record(z.string(), z.unknown()).optional(),
  preview: z
    .object({
      text: z.string(),
      style: z.enum(["GENTLE", "DIRECT", "URGENT"]),
      effect: z.record(z.string(), z.unknown()),
      targetPlayerId: z.string().uuid().optional(),
    })
    .optional(),
  failureCode: z.string().optional(),
  stateVersion: z.string(),
});
