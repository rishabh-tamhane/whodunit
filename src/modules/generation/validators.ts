import {
  StoryPackageSchema,
  type StoryPackage,
} from "@/contracts/story/package";

export const STORY_VALIDATOR_VERSION = "story-validator-v1" as const;

export type StoryDiagnostic = Readonly<{
  severity: "ERROR" | "WARNING";
  category:
    | "STRUCTURE"
    | "PLAYER_SET"
    | "DURATION"
    | "REFERENCE"
    | "INFORMATION_FLOW"
    | "MISSION"
    | "EVIDENCE"
    | "SOLVABILITY"
    | "SAFETY"
    | "RAW_INPUT_COPY";
  affectedIds: readonly string[];
  explanation: string;
  repairConstraint: string;
}>;

export type StoryValidationContext = Readonly<{
  configuredPlayerIds: readonly string[];
  scoringProfileVersion: string;
  durationMinutes: 30 | 45 | 60 | 90 | 120;
  roundCount: number;
  murdererCount: number;
  accompliceCount: number;
  innocentCount: number;
  murdererAware: boolean;
  rawDescriptionTexts?: readonly string[];
}>;

const profileByDuration = {
  30: { rounds: 2, roundMinutes: [9, 9], evidenceMin: 4 },
  45: { rounds: 3, roundMinutes: [9, 9, 9], evidenceMin: 6 },
  60: { rounds: 3, roundMinutes: [12, 12, 12], evidenceMin: 7 },
  90: { rounds: 4, roundMinutes: [15, 15, 15, 15], evidenceMin: 10 },
  120: { rounds: 5, roundMinutes: [17, 17, 17, 17, 17], evidenceMin: 13 },
} as const;

function diagnostic(
  category: StoryDiagnostic["category"],
  affectedIds: readonly string[],
  explanation: string,
  repairConstraint: string,
): StoryDiagnostic {
  return {
    severity: "ERROR",
    category,
    affectedIds,
    explanation,
    repairConstraint,
  };
}

function sameSet(left: readonly string[], right: readonly string[]): boolean {
  return (
    left.length === right.length &&
    new Set(left).size === left.length &&
    left.every((id) => right.includes(id))
  );
}

function normalizedWords(value: string): string {
  return value
    .normalize("NFKC")
    .toLocaleLowerCase("en")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function validateReferences(
  story: StoryPackage,
  playerIds: readonly string[],
  diagnostics: StoryDiagnostic[],
): void {
  const players = new Set(playerIds);
  const rounds = new Set(story.rounds.map((round) => round.id));
  const evidence = new Set(story.evidence.map((item) => item.id));
  const missions = new Set(story.missions.map((mission) => mission.id));
  const consequences = new Set(story.consequences.map((item) => item.id));

  const requireRef = (
    exists: boolean,
    id: string,
    ownerId: string,
    kind: string,
  ) => {
    if (!exists)
      diagnostics.push(
        diagnostic(
          "REFERENCE",
          [ownerId, id],
          `${kind} reference does not resolve.`,
          `Use only a generated ${kind} ID from this package.`,
        ),
      );
  };

  for (const relationship of story.relationships) {
    requireRef(
      players.has(relationship.sourcePlayerId),
      relationship.sourcePlayerId,
      relationship.id,
      "player",
    );
    requireRef(
      players.has(relationship.targetPlayerId),
      relationship.targetPlayerId,
      relationship.id,
      "player",
    );
    if (relationship.sourcePlayerId === relationship.targetPlayerId) {
      diagnostics.push(
        diagnostic(
          "REFERENCE",
          [relationship.id],
          "A relationship cannot target the same player.",
          "Choose two distinct configured players.",
        ),
      );
    }
  }
  for (const event of story.timeline)
    for (const id of event.involvedPlayerIds)
      requireRef(players.has(id), id, event.id, "player");
  for (const item of story.evidence) {
    requireRef(rounds.has(item.roundId), item.roundId, item.id, "round");
    for (const id of item.provesPlayerIds)
      requireRef(players.has(id), id, item.id, "player");
    if (item.audience.kind === "PLAYERS")
      for (const id of item.audience.playerIds)
        requireRef(players.has(id), id, item.id, "audience player");
    if ("roundId" in item.releaseRule)
      requireRef(
        rounds.has(item.releaseRule.roundId),
        item.releaseRule.roundId,
        item.id,
        "round",
      );
    if ("earliestRoundId" in item.releaseRule)
      requireRef(
        rounds.has(item.releaseRule.earliestRoundId),
        item.releaseRule.earliestRoundId,
        item.id,
        "round",
      );
    if ("missionId" in item.releaseRule)
      requireRef(
        missions.has(item.releaseRule.missionId),
        item.releaseRule.missionId,
        item.id,
        "mission",
      );
  }
  for (const edge of story.evidenceDependencies) {
    requireRef(
      evidence.has(edge.sourceEvidenceId),
      edge.sourceEvidenceId,
      edge.id,
      "evidence",
    );
    requireRef(
      evidence.has(edge.targetEvidenceId),
      edge.targetEvidenceId,
      edge.id,
      "evidence",
    );
  }
  for (const mission of story.missions) {
    requireRef(
      rounds.has(mission.roundId),
      mission.roundId,
      mission.id,
      "round",
    );
    requireRef(
      players.has(mission.assignedPlayerId),
      mission.assignedPlayerId,
      mission.id,
      "player",
    );
    if (mission.failureConsequenceId)
      requireRef(
        consequences.has(mission.failureConsequenceId),
        mission.failureConsequenceId,
        mission.id,
        "consequence",
      );
  }
  for (const item of story.interventions) {
    requireRef(rounds.has(item.roundId), item.roundId, item.id, "round");
    const effect = item.canonicalEffect;
    if (effect.kind === "RELEASE_EVIDENCE")
      requireRef(
        evidence.has(effect.evidenceId),
        effect.evidenceId,
        item.id,
        "evidence",
      );
    if (effect.kind === "RELEASE_CONSEQUENCE")
      requireRef(
        consequences.has(effect.consequenceId),
        effect.consequenceId,
        item.id,
        "consequence",
      );
    if (effect.kind === "ACTIVATE_MISSION")
      requireRef(
        missions.has(effect.missionId),
        effect.missionId,
        item.id,
        "mission",
      );
  }
}

function validateInformationFlow(
  story: StoryPackage,
  context: StoryValidationContext,
  diagnostics: StoryDiagnostic[],
): void {
  const murdererIds = story.solution.murdererPlayerIds;
  for (const dossier of story.dossiers) {
    const expectedKnown =
      dossier.faction === "MURDERER" && context.murdererAware
        ? murdererIds
        : [];
    if (!sameSet(dossier.knownMurdererPlayerIds, expectedKnown)) {
      diagnostics.push(
        diagnostic(
          "INFORMATION_FLOW",
          [dossier.id],
          "Starting murderer knowledge violates the configured awareness policy.",
          context.murdererAware
            ? "Only murderer dossiers may list every murderer at start."
            : "No dossier may list a murderer at start; reveal identities only through configured revelations.",
        ),
      );
    }
  }
  const accomplices = new Set(story.solution.accomplicePlayerIds);
  if (
    !sameSet(
      story.accompliceRevelations.map((item) => item.accomplicePlayerId),
      [...accomplices],
    )
  ) {
    diagnostics.push(
      diagnostic(
        "INFORMATION_FLOW",
        story.solution.accomplicePlayerIds,
        "Every accomplice needs exactly one delayed murderer revelation.",
        "Create one revelation per accomplice, after round one, listing all murderer IDs.",
      ),
    );
  }
  const firstRoundId = [...story.rounds].sort(
    (a, b) => a.sequence - b.sequence,
  )[0]?.id;
  for (const revelation of story.accompliceRevelations) {
    if (
      revelation.roundId === firstRoundId ||
      !sameSet(revelation.murdererPlayerIds, murdererIds)
    ) {
      diagnostics.push(
        diagnostic(
          "INFORMATION_FLOW",
          [revelation.id],
          "Accomplice revelation is premature or incomplete.",
          "Reveal every murderer to this accomplice only after the first round.",
        ),
      );
    }
  }
}

function validateMissions(
  story: StoryPackage,
  playerIds: readonly string[],
  diagnostics: StoryDiagnostic[],
): void {
  for (const round of story.rounds) {
    for (const playerId of playerIds) {
      const matching = story.missions.filter(
        (mission) =>
          mission.roundId === round.id && mission.assignedPlayerId === playerId,
      );
      if (matching.length !== 1)
        diagnostics.push(
          diagnostic(
            "MISSION",
            [round.id, playerId, ...matching.map((item) => item.id)],
            "Each player must have exactly one achievable mission in every round.",
            "Add or remove missions so this round/player pair has exactly one observable mission.",
          ),
        );
    }
  }
  for (const mission of story.missions) {
    if (
      !mission.observableByGameMaster ||
      mission.objective.length > 500 ||
      /physically|steal|destroy|threaten|touch\s+someone/iu.test(
        mission.objective,
      )
    ) {
      diagnostics.push(
        diagnostic(
          "MISSION",
          [mission.id],
          "Mission is not safely and objectively adjudicable.",
          "Use a brief verbal or in-app action observable by the Game Master.",
        ),
      );
    }
  }
}

function validateEvidence(
  story: StoryPackage,
  profile: (typeof profileByDuration)[keyof typeof profileByDuration],
  diagnostics: StoryDiagnostic[],
): void {
  const guaranteed = story.evidence.filter(
    (item) =>
      item.audience.kind === "PUBLIC" &&
      ["ROUND_START", "FINAL_ROUND_FALLBACK"].includes(item.releaseRule.kind),
  );
  if (story.evidence.length < profile.evidenceMin)
    diagnostics.push(
      diagnostic(
        "EVIDENCE",
        story.evidence.map((item) => item.id),
        "The story has too few evidence events for the duration profile.",
        `Generate at least ${profile.evidenceMin} evidence items.`,
      ),
    );
  for (const murdererId of story.solution.murdererPlayerIds) {
    const paths = guaranteed.filter((item) =>
      item.provesPlayerIds.includes(murdererId),
    );
    if (paths.length < 2)
      diagnostics.push(
        diagnostic(
          "SOLVABILITY",
          [murdererId, ...paths.map((item) => item.id)],
          "A murderer lacks two independent guaranteed evidence paths.",
          "Provide at least two public, guaranteed clues that independently point to this murderer.",
        ),
      );
  }
  for (const kind of ["MOTIVE", "METHOD"] as const) {
    if (!guaranteed.some((item) => item.kind === kind))
      diagnostics.push(
        diagnostic(
          "SOLVABILITY",
          [],
          `No guaranteed ${kind.toLowerCase()} clue reaches players.`,
          `Add a public ${kind} clue released at round start or by final-round fallback.`,
        ),
      );
  }
  for (const item of story.evidence.filter(
    (candidate) => candidate.kind === "RED_HERRING",
  )) {
    if (
      !item.redHerringExplanation ||
      !story.evidenceDependencies.some(
        (edge) =>
          edge.sourceEvidenceId === item.id &&
          edge.kind === "RED_HERRING_EXPLAINED_BY",
      )
    )
      diagnostics.push(
        diagnostic(
          "EVIDENCE",
          [item.id],
          "Red herring has no canonical explanation path.",
          "Add an explanation and a RED_HERRING_EXPLAINED_BY edge.",
        ),
      );
  }
}

function validateSafety(
  story: StoryPackage,
  rawDescriptions: readonly string[],
  diagnostics: StoryDiagnostic[],
): void {
  const serialized = JSON.stringify(story);
  const unsafe =
    /\b(caste|dalit|brahmin|hindu|muslim|christian|autis(?:m|tic)|schizophren|cancer|hiv|bankruptcy|debt|infertility)\b/iu;
  if (unsafe.test(`${story.solution.motive} ${story.fullCaseNarrative}`))
    diagnostics.push(
      diagnostic(
        "SAFETY",
        [story.storyId],
        "A protected or sensitive real-world trait is used in the crime rationale.",
        "Replace it with a fictional, non-sensitive motive such as rivalry over an invented object or event.",
      ),
    );
  for (const consequence of story.consequences) {
    if (
      !consequence.fictionalOnly ||
      /injur|poison|weapon|money|payment|humiliat|threat/iu.test(
        consequence.description,
      )
    )
      diagnostics.push(
        diagnostic(
          "SAFETY",
          [consequence.id],
          "Consequence could imply real harm, money, or humiliation.",
          "Use a reversible fictional social complication with no real-world harm.",
        ),
      );
  }
  if (
    !new Set(story.consequences.map((item) => item.severity)).has(3) ||
    !new Set(story.consequences.map((item) => item.severity)).has(1)
  )
    diagnostics.push(
      diagnostic(
        "SAFETY",
        story.consequences.map((item) => item.id),
        "Consequences do not form a visible fictional escalation.",
        "Include safe fictional consequences at severity 1, 2, and 3.",
      ),
    );
  for (const raw of rawDescriptions) {
    const normalized = normalizedWords(raw);
    if (
      normalized.length >= 24 &&
      normalizedWords(serialized).includes(normalized)
    )
      diagnostics.push(
        diagnostic(
          "RAW_INPUT_COPY",
          [story.storyId],
          "Generated output reproduces a raw private description.",
          "Use only abstract inspiration; do not quote or closely reproduce source wording.",
        ),
      );
  }
}

export function validateStoryPackage(
  input: unknown,
  context: StoryValidationContext,
): StoryDiagnostic[] {
  const parsed = StoryPackageSchema.safeParse(input);
  if (!parsed.success)
    return parsed.error.issues.map((issue) =>
      diagnostic(
        "STRUCTURE",
        [],
        issue.message,
        `Correct StoryPackage field ${issue.path.join(".") || "root"}.`,
      ),
    );
  const story = parsed.data;
  const diagnostics: StoryDiagnostic[] = [];
  if (story.scoringProfileVersion !== context.scoringProfileVersion)
    diagnostics.push(
      diagnostic(
        "STRUCTURE",
        [story.storyId],
        "The story scoring profile does not match the configured room profile.",
        `Use scoringProfileVersion ${context.scoringProfileVersion}.`,
      ),
    );
  const configured = [...context.configuredPlayerIds];
  const characters = story.characters.map((item) => item.playerId);
  const dossiers = story.dossiers.map((item) => item.playerId);
  const factions = {
    MURDERER: story.characters
      .filter((item) => item.faction === "MURDERER")
      .map((item) => item.playerId),
    ACCOMPLICE: story.characters
      .filter((item) => item.faction === "ACCOMPLICE")
      .map((item) => item.playerId),
    INNOCENT: story.characters
      .filter((item) => item.faction === "INNOCENT")
      .map((item) => item.playerId),
  };
  if (!sameSet(characters, configured) || !sameSet(dossiers, configured))
    diagnostics.push(
      diagnostic(
        "PLAYER_SET",
        [...characters, ...dossiers],
        "Characters or dossiers do not match the exact configured player set.",
        "Use every configured opaque player ID exactly once and invent no players.",
      ),
    );
  if (!story.victim.isNpc || configured.includes(story.victim.id))
    diagnostics.push(
      diagnostic(
        "PLAYER_SET",
        [story.victim.id],
        "The victim must be a fictional NPC, never a player.",
        "Use a fresh NPC ID outside the configured player set.",
      ),
    );
  if (
    !sameSet(factions.MURDERER, story.solution.murdererPlayerIds) ||
    !sameSet(factions.ACCOMPLICE, story.solution.accomplicePlayerIds) ||
    !sameSet(factions.INNOCENT, story.solution.innocentPlayerIds) ||
    factions.MURDERER.length !== context.murdererCount ||
    factions.ACCOMPLICE.length !== context.accompliceCount ||
    factions.INNOCENT.length !== context.innocentCount
  )
    diagnostics.push(
      diagnostic(
        "PLAYER_SET",
        configured,
        "Faction assignments do not match configured counts or canonical solution lists.",
        "Partition the exact player set once using the configured faction counts.",
      ),
    );
  const profile = profileByDuration[context.durationMinutes];
  if (
    context.roundCount !== profile.rounds ||
    story.durationProfile.durationMinutes !== context.durationMinutes ||
    story.durationProfile.roundCount !== profile.rounds ||
    story.rounds.length !== profile.rounds ||
    story.rounds.some(
      (round, index) =>
        round.sequence !== index + 1 ||
        round.targetDurationSeconds !== profile.roundMinutes[index]! * 60,
    )
  )
    diagnostics.push(
      diagnostic(
        "DURATION",
        story.rounds.map((round) => round.id),
        "Round structure does not match the immutable duration profile.",
        `Use ${profile.rounds} rounds with targets ${profile.roundMinutes.join(", ")} minutes.`,
      ),
    );
  validateReferences(story, configured, diagnostics);
  validateInformationFlow(story, context, diagnostics);
  validateMissions(story, configured, diagnostics);
  validateEvidence(story, profile, diagnostics);
  validateSafety(story, context.rawDescriptionTexts ?? [], diagnostics);
  return diagnostics;
}

export function assertValidStoryPackage(
  input: unknown,
  context: StoryValidationContext,
): StoryPackage {
  const parsed = StoryPackageSchema.parse(input);
  const diagnostics = validateStoryPackage(parsed, context);
  if (diagnostics.length > 0) throw new StoryValidationError(diagnostics);
  return parsed;
}

export class StoryValidationError extends Error {
  constructor(readonly diagnostics: readonly StoryDiagnostic[]) {
    super("StoryPackage failed deterministic validation.");
    this.name = "StoryValidationError";
  }
}
