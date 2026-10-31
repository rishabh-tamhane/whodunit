import type { StoryPackage } from "@/contracts/story/package";
import type { GenerationSnapshot } from "@/modules/generation/snapshot";
import type { StoryValidationContext } from "@/modules/generation/validators";

const names = [
  "Aarav",
  "Aditi",
  "Ishaan",
  "Kavya",
  "Meera",
  "Nikhil",
  "Priya",
  "Rahul",
  "Saanvi",
  "Vihaan",
  "Zoya",
  "Arjun",
] as const;
const costumes = [
  "Astronaut",
  "Detective",
  "Magician",
  "Vampire",
  "Pirate",
  "Witch",
  "Robot",
  "Ghost",
  "Knight",
  "Scientist",
  "Phantom",
  "Explorer",
] as const;
const profile = {
  4: { murderer: 1, accomplice: 0 },
  5: { murderer: 1, accomplice: 1 },
  6: { murderer: 1, accomplice: 1 },
  7: { murderer: 2, accomplice: 0 },
  8: { murderer: 2, accomplice: 1 },
  9: { murderer: 2, accomplice: 1 },
  10: { murderer: 2, accomplice: 2 },
  11: { murderer: 3, accomplice: 1 },
  12: { murderer: 3, accomplice: 2 },
} as const;
const duration = {
  4: 30,
  5: 45,
  6: 60,
  7: 60,
  8: 90,
  9: 90,
  10: 90,
  11: 120,
  12: 120,
} as const;
const pacing = {
  30: [9, 9],
  45: [9, 9, 9],
  60: [12, 12, 12],
  90: [15, 15, 15, 15],
  120: [17, 17, 17, 17, 17],
} as const;

function id(value: number): string {
  return `00000000-0000-4000-8000-${value.toString().padStart(12, "0")}`;
}

export function createStoryFixture(
  playerCount: keyof typeof profile,
  murdererAware = true,
): { story: StoryPackage; context: StoryValidationContext } {
  const counts = profile[playerCount];
  const durationMinutes = duration[playerCount];
  const roundMinutes = pacing[durationMinutes];
  const playerIds = Array.from({ length: playerCount }, (_, index) =>
    id(100 + index),
  );
  const murdererIds = playerIds.slice(0, counts.murderer);
  const accompliceIds = playerIds.slice(
    counts.murderer,
    counts.murderer + counts.accomplice,
  );
  const innocentIds = playerIds.slice(counts.murderer + counts.accomplice);
  const roundIds = roundMinutes.map((_, index) => id(200 + index));
  const consequenceIds = [id(300), id(301), id(302)];
  const characters = playerIds.map((playerId, index) => ({
    playerId,
    displayName: names[index]!,
    costume: costumes[index]!,
    faction: murdererIds.includes(playerId)
      ? ("MURDERER" as const)
      : accompliceIds.includes(playerId)
        ? ("ACCOMPLICE" as const)
        : ("INNOCENT" as const),
    publicPersona: `${names[index]} is the keeper of an eccentric exhibit at the fictional Moonlit Museum.`,
  }));
  const missions = roundIds.flatMap((roundId, roundIndex) =>
    playerIds.map((playerId, playerIndex) => ({
      id: id(1_000 + roundIndex * 20 + playerIndex),
      roundId,
      assignedPlayerId: playerId,
      actionKind: "ASK_PLAYER" as const,
      objective: `Ask ${names[(playerIndex + 1) % playerCount]} where they were during chapter ${roundIndex + 1}.`,
      completionRule:
        "Complete the named question aloud while the Game Master can observe it.",
      observableByGameMaster: true as const,
      stakes: "Success earns a useful fictional museum detail.",
      hostConfirmationGuidance: "Confirm after hearing the complete question.",
      successEffect: null,
      failureConsequenceId: consequenceIds[roundIndex % consequenceIds.length]!,
    })),
  );
  const evidenceCount = Math.max(
    roundIds.length * 3,
    murdererIds.length * 2 + 2,
  );
  const evidence = Array.from({ length: evidenceCount }, (_, index) => {
    const murdererId = murdererIds[index % murdererIds.length]!;
    const kind =
      index === 0
        ? ("MOTIVE" as const)
        : index === 1
          ? ("METHOD" as const)
          : ("TIMELINE" as const);
    return {
      id: id(400 + index),
      roundId: roundIds[index % roundIds.length]!,
      kind,
      title: `Museum clue ${index + 1}`,
      description: `A fictional catalog mark links exhibit detail ${index + 1} to the hidden museum timeline.`,
      isRequired: index < murdererIds.length * 2 + 2,
      provesPlayerIds: [murdererId],
      audience: { kind: "PUBLIC" as const },
      releaseRule:
        index < roundIds.length
          ? { kind: "ROUND_START" as const, roundId: roundIds[index]! }
          : {
              kind: "FINAL_ROUND_FALLBACK" as const,
              roundId: roundIds.at(-1)!,
            },
      redHerringExplanation: null,
    };
  });
  const story: StoryPackage = {
    schemaVersion: "0.1.0",
    storyId: id(1),
    title: "The Moonlit Museum Mystery",
    premise:
      "At a fictional Diwali-eve costume gathering in the Moonlit Museum, its imaginary curator is found missing from the grand gallery.",
    durationProfile: {
      version: "duration-v1",
      durationMinutes,
      roundCount: roundIds.length,
    },
    scoringProfileVersion: "score-v1",
    murdererAware,
    victim: {
      id: id(2),
      name: "Dr. Leela Varman",
      biography:
        "The fictional curator of the imaginary Moonlit Museum and guardian of its clockwork moon.",
      isNpc: true,
    },
    solution: {
      murdererPlayerIds: murdererIds,
      accomplicePlayerIds: accompliceIds,
      innocentPlayerIds: innocentIds,
      motive:
        "The culprit wanted sole credit for discovering the fictional clockwork moon.",
      method:
        "A harmless stage illusion concealed the curator's exit through a theatrical passage.",
      location: "Moonlit Museum grand gallery",
      occurredAt: "Just before the costume toast",
      explanation:
        "Catalog marks, the stage mechanism, and the reconstructed timeline expose the complete fictional scheme.",
    },
    characters,
    relationships: playerIds.map((playerId, index) => ({
      id: id(600 + index),
      sourcePlayerId: playerId,
      targetPlayerId: playerIds[(index + 1) % playerCount]!,
      publicSummary: "They jointly catalogued a curious fictional exhibit.",
      privateTruth:
        "They disagreed over which harmless exhibit clue deserved attention.",
    })),
    timeline: [1, 2, 3].map((sequence) => ({
      id: id(700 + sequence),
      sequence,
      timeLabel: `Chapter ${sequence}`,
      description: `A staged museum bell marks fictional timeline chapter ${sequence}.`,
      involvedPlayerIds: playerIds.slice(
        (sequence - 1) % playerCount,
        ((sequence - 1) % playerCount) + 1,
      ),
      isCanonicalTruth: true,
    })),
    rounds: roundIds.map((roundId, index) => ({
      id: roundId,
      sequence: index + 1,
      title: `The ${["Arrival", "Alibis", "Clockwork", "Confrontation", "Last Bell"][index]}`,
      targetDurationSeconds: roundMinutes[index]! * 60,
      publicEvent: `The museum bell reveals a new fictional event for round ${index + 1}.`,
    })),
    dossiers: characters.map((character, index) => ({
      id: id(800 + index),
      playerId: character.playerId,
      faction: character.faction,
      characterGoal:
        "Reconstruct the museum timeline while protecting a harmless personal secret.",
      publicBackground: character.publicPersona,
      privateSecrets: ["You once misplaced a replica museum key."],
      startingKnowledge: [
        "The curator scheduled a costume toast before the final bell.",
      ],
      knownMurdererPlayerIds:
        character.faction === "MURDERER" && murdererAware ? murdererIds : [],
    })),
    evidence,
    evidenceDependencies: [],
    consequences: consequenceIds.map((consequenceId, index) => ({
      id: consequenceId,
      severity: index + 1,
      title: `Fictional complication ${index + 1}`,
      description: `For one discussion beat, announce a harmless imaginary museum mix-up at level ${index + 1}.`,
      fictionalOnly: true,
      eligibility: { roundIds, afterFailedMission: true },
    })),
    missions,
    interventions: roundIds.map((roundId, index) => ({
      id: id(1_400 + index),
      roundId,
      strength: Math.min(index + 1, 3),
      candidateKind: "RELEASE_EVIDENCE",
      canonicalEffect: {
        kind: "RELEASE_EVIDENCE",
        evidenceId: evidence[Math.min(index, evidence.length - 1)]!.id,
      },
      presentation: `The Game Master may reveal museum clue ${index + 1}.`,
      eligibleAfterSeconds: 120,
    })),
    accompliceRevelations: accompliceIds.map((playerId, index) => ({
      id: id(1_500 + index),
      accomplicePlayerId: playerId,
      roundId: roundIds[1]!,
      murdererPlayerIds: murdererIds,
      text: "A sealed fictional note now identifies the conspirators.",
    })),
    finalReveal: [
      "VICTIM",
      "TIMELINE",
      "MURDERERS",
      "MOTIVE",
      "METHOD",
      "EVIDENCE",
      "EPILOGUE",
    ].map((kind, index) => ({
      id: id(1_600 + index),
      sequence: index + 1,
      kind: kind as StoryPackage["finalReveal"][number]["kind"],
      title: `Reveal: ${kind.toLocaleLowerCase("en")}`,
      body: `The Game Master reveals the complete fictional ${kind.toLocaleLowerCase("en")} chapter.`,
    })),
    fullCaseNarrative:
      "The complete fictional case follows the clockwork moon from the costume toast through the harmless stage illusion, with every required clue resolving in the final explanation.",
  };
  return {
    story,
    context: {
      configuredPlayerIds: playerIds,
      scoringProfileVersion: story.scoringProfileVersion,
      durationMinutes,
      roundCount: roundIds.length,
      murdererCount: counts.murderer,
      accompliceCount: counts.accomplice,
      innocentCount: playerCount - counts.murderer - counts.accomplice,
      murdererAware,
      rawDescriptionTexts: [
        "A private description deliberately unlike all generated museum prose.",
      ],
    },
  };
}

export const STORY_EVALUATION_CORPUS = (
  [4, 5, 6, 7, 8, 9, 10, 11, 12] as const
).flatMap((count) => [
  createStoryFixture(count, true),
  createStoryFixture(count, false),
]);

export function createGenerationSnapshotFixture(
  playerCount: keyof typeof profile,
  murdererAware: boolean,
): GenerationSnapshot {
  const fixture = createStoryFixture(playerCount, murdererAware);
  const story = fixture.story;
  return {
    snapshotVersion: "generation-snapshot-v1",
    roomId: id(9_000 + playerCount + (murdererAware ? 100 : 0)),
    stateVersion: "1",
    capturedAt: "2026-10-30T12:00:00.000Z",
    configuration: {
      durationProfileVersion: "duration-v1",
      durationMinutes: story.durationProfile.durationMinutes,
      roundCount: story.durationProfile.roundCount,
      scoringProfileVersion: story.scoringProfileVersion,
      murdererCount: story.solution.murdererPlayerIds.length,
      accompliceCount: story.solution.accomplicePlayerIds.length,
      innocentCount: story.solution.innocentPlayerIds.length,
      murdererAware,
    },
    players: story.characters.map((character, index) => ({
      playerId: character.playerId,
      displayName: character.displayName,
      costume: character.costume,
      hostBackground: `Player ${index + 1} enjoys collaborative fictional puzzles and inclusive party games.`,
    })),
    descriptionResponses: story.characters.map((character, index) => ({
      subjectPlayerId: character.playerId,
      responseStatus: "SUBMITTED" as const,
      descriptionText: `Private eval description ${index + 1}: calm, observant, and fond of harmless wordplay.`,
    })),
  };
}
