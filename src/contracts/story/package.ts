import { z } from "zod";

import { STORY_SCHEMA_VERSION } from "@/contracts/story/version";

const IdSchema = z.string().uuid();
const TextSchema = z.string().trim().min(1).max(2_000);
const ShortTextSchema = z.string().trim().min(1).max(300);

export const FactionSchema = z.enum(["MURDERER", "ACCOMPLICE", "INNOCENT"]);
export const MissionActionKindSchema = z.enum([
  "ASK_PLAYER",
  "SHARE_FACT",
  "MAKE_PUBLIC_CLAIM",
  "PRESENT_EVIDENCE",
  "SUBMIT_PRIVATE_THEORY",
  "COMPARE_ALIBIS",
  "REQUEST_INFORMATION",
]);
export const InterventionCandidateKindSchema = z.enum([
  "DIRECTED_QUESTION",
  "RELEASE_EVIDENCE",
  "RELEASE_CONSEQUENCE",
  "ACTIVATE_MISSION",
]);

export const StoryAudienceSchema = z.discriminatedUnion("kind", [
  z.strictObject({ kind: z.literal("PUBLIC") }),
  z.strictObject({ kind: z.literal("GAME_MASTER") }),
  z.strictObject({
    kind: z.literal("PLAYERS"),
    playerIds: z.array(IdSchema).min(1),
  }),
  z.strictObject({
    kind: z.literal("FACTIONS"),
    factions: z.array(FactionSchema).min(1),
  }),
]);

export const ReleaseRuleSchema = z.discriminatedUnion("kind", [
  z.strictObject({ kind: z.literal("ROUND_START"), roundId: IdSchema }),
  z.strictObject({ kind: z.literal("MISSION_SUCCESS"), missionId: IdSchema }),
  z.strictObject({ kind: z.literal("MISSION_FAILURE"), missionId: IdSchema }),
  z.strictObject({
    kind: z.literal("GAME_MASTER_MANUAL"),
    earliestRoundId: IdSchema,
  }),
  z.strictObject({
    kind: z.literal("FINAL_ROUND_FALLBACK"),
    roundId: IdSchema,
  }),
]);

const FictionalConsequenceSchema = z.strictObject({
  id: IdSchema,
  severity: z.number().int().min(1).max(3),
  title: ShortTextSchema,
  description: TextSchema,
  fictionalOnly: z.literal(true),
  eligibility: z.strictObject({
    roundIds: z.array(IdSchema).min(1),
    afterFailedMission: z.boolean(),
  }),
});

const CanonicalEffectSchema = z.discriminatedUnion("kind", [
  z.strictObject({
    kind: z.literal("ASK_QUESTION"),
    question: ShortTextSchema,
  }),
  z.strictObject({ kind: z.literal("RELEASE_EVIDENCE"), evidenceId: IdSchema }),
  z.strictObject({
    kind: z.literal("RELEASE_CONSEQUENCE"),
    consequenceId: IdSchema,
  }),
  z.strictObject({ kind: z.literal("ACTIVATE_MISSION"), missionId: IdSchema }),
]);

export const StoryPackageSchema = z.strictObject({
  schemaVersion: z.literal(STORY_SCHEMA_VERSION),
  storyId: IdSchema,
  title: ShortTextSchema,
  premise: TextSchema,
  durationProfile: z.strictObject({
    version: z.literal("duration-v1"),
    durationMinutes: z.union([
      z.literal(30),
      z.literal(45),
      z.literal(60),
      z.literal(90),
      z.literal(120),
    ]),
    roundCount: z.number().int().min(2).max(5),
  }),
  scoringProfileVersion: z.string().trim().min(1).max(50),
  murdererAware: z.boolean(),
  victim: z.strictObject({
    id: IdSchema,
    name: ShortTextSchema,
    biography: TextSchema,
    isNpc: z.literal(true),
  }),
  solution: z.strictObject({
    murdererPlayerIds: z.array(IdSchema).min(1),
    accomplicePlayerIds: z.array(IdSchema),
    innocentPlayerIds: z.array(IdSchema).min(1),
    motive: TextSchema,
    method: TextSchema,
    location: ShortTextSchema,
    occurredAt: ShortTextSchema,
    explanation: TextSchema,
  }),
  characters: z
    .array(
      z.strictObject({
        playerId: IdSchema,
        displayName: ShortTextSchema,
        costume: ShortTextSchema,
        faction: FactionSchema,
        publicPersona: TextSchema,
      }),
    )
    .min(4)
    .max(12),
  relationships: z.array(
    z.strictObject({
      id: IdSchema,
      sourcePlayerId: IdSchema,
      targetPlayerId: IdSchema,
      publicSummary: TextSchema,
      privateTruth: TextSchema,
    }),
  ),
  timeline: z
    .array(
      z.strictObject({
        id: IdSchema,
        sequence: z.number().int().positive(),
        timeLabel: ShortTextSchema,
        description: TextSchema,
        involvedPlayerIds: z.array(IdSchema),
        isCanonicalTruth: z.boolean(),
      }),
    )
    .min(3),
  rounds: z
    .array(
      z.strictObject({
        id: IdSchema,
        sequence: z.number().int().positive(),
        title: ShortTextSchema,
        targetDurationSeconds: z.number().int().positive(),
        publicEvent: TextSchema,
      }),
    )
    .min(2)
    .max(5),
  dossiers: z
    .array(
      z.strictObject({
        id: IdSchema,
        playerId: IdSchema,
        faction: FactionSchema,
        characterGoal: TextSchema,
        publicBackground: TextSchema,
        privateSecrets: z.array(TextSchema).min(1),
        startingKnowledge: z.array(TextSchema).min(1),
        knownMurdererPlayerIds: z.array(IdSchema),
      }),
    )
    .min(4)
    .max(12),
  evidence: z
    .array(
      z.strictObject({
        id: IdSchema,
        roundId: IdSchema,
        kind: z.enum([
          "MOTIVE",
          "METHOD",
          "TIMELINE",
          "ALIBI",
          "RELATIONSHIP",
          "RED_HERRING",
        ]),
        title: ShortTextSchema,
        description: TextSchema,
        isRequired: z.boolean(),
        provesPlayerIds: z.array(IdSchema),
        audience: StoryAudienceSchema,
        releaseRule: ReleaseRuleSchema,
        redHerringExplanation: TextSchema.nullable(),
      }),
    )
    .min(4),
  evidenceDependencies: z.array(
    z.strictObject({
      id: IdSchema,
      sourceEvidenceId: IdSchema,
      targetEvidenceId: IdSchema,
      kind: z.enum([
        "SUPPORTS",
        "CONTRADICTS",
        "REQUIRES",
        "RED_HERRING_EXPLAINED_BY",
      ]),
    }),
  ),
  consequences: z.array(FictionalConsequenceSchema).min(3),
  missions: z
    .array(
      z.strictObject({
        id: IdSchema,
        roundId: IdSchema,
        assignedPlayerId: IdSchema,
        actionKind: MissionActionKindSchema,
        objective: TextSchema,
        completionRule: TextSchema,
        observableByGameMaster: z.literal(true),
        stakes: TextSchema,
        hostConfirmationGuidance: TextSchema,
        successEffect: CanonicalEffectSchema.nullable(),
        failureConsequenceId: IdSchema.nullable(),
      }),
    )
    .min(8),
  interventions: z
    .array(
      z.strictObject({
        id: IdSchema,
        roundId: IdSchema,
        strength: z.number().int().min(1).max(3),
        candidateKind: InterventionCandidateKindSchema,
        canonicalEffect: CanonicalEffectSchema,
        presentation: TextSchema,
        eligibleAfterSeconds: z.number().int().nonnegative(),
      }),
    )
    .min(2),
  accompliceRevelations: z.array(
    z.strictObject({
      id: IdSchema,
      accomplicePlayerId: IdSchema,
      roundId: IdSchema,
      murdererPlayerIds: z.array(IdSchema).min(1),
      text: TextSchema,
    }),
  ),
  finalReveal: z
    .array(
      z.strictObject({
        id: IdSchema,
        sequence: z.number().int().positive(),
        kind: z.enum([
          "VICTIM",
          "TIMELINE",
          "MURDERERS",
          "MOTIVE",
          "METHOD",
          "EVIDENCE",
          "EPILOGUE",
        ]),
        title: ShortTextSchema,
        body: TextSchema,
      }),
    )
    .min(5),
  fullCaseNarrative: TextSchema,
});

export type StoryPackage = z.infer<typeof StoryPackageSchema>;
export type StoryAudience = z.infer<typeof StoryAudienceSchema>;
export type CanonicalEffect = z.infer<typeof CanonicalEffectSchema>;

export const STORY_PACKAGE_JSON_SCHEMA = z.toJSONSchema(StoryPackageSchema, {
  target: "draft-2020-12",
  unrepresentable: "throw",
});
