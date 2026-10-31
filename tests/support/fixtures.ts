import {
  AuthUserIdSchema,
  DomainCommandMetadataSchema,
  IdempotencyKeySchema,
  MembershipIdSchema,
  PlayerIdSchema,
  RoomIdSchema,
  StateVersionSchema,
  StoryIdSchema,
} from "@/contracts";
import type { DomainCommandMetadata } from "@/contracts";

type Cleanup = () => Promise<void> | void;

function deterministicUuid(sequence: number): string {
  if (!Number.isSafeInteger(sequence) || sequence < 0) {
    throw new Error("Fixture sequence must be a non-negative safe integer.");
  }

  const suffix = sequence.toString(16).padStart(12, "0");
  return `00000000-0000-4000-8000-${suffix}`;
}

export function createFixtureFactory(seed = 1) {
  let sequence = seed;
  const cleanups: Cleanup[] = [];
  const nextUuid = () => deterministicUuid(sequence++);

  return {
    authUserId: () => AuthUserIdSchema.parse(nextUuid()),
    membershipId: () => MembershipIdSchema.parse(nextUuid()),
    playerId: () => PlayerIdSchema.parse(nextUuid()),
    roomId: () => RoomIdSchema.parse(nextUuid()),
    storyId: () => StoryIdSchema.parse(nextUuid()),
    commandMetadata: (
      overrides: Partial<DomainCommandMetadata> = {},
    ): DomainCommandMetadata =>
      DomainCommandMetadataSchema.parse({
        idempotencyKey: IdempotencyKeySchema.parse(nextUuid()),
        expectedStateVersion: StateVersionSchema.parse("0"),
        ...overrides,
      }),
    onCleanup: (cleanup: Cleanup) => {
      cleanups.push(cleanup);
    },
    cleanup: async () => {
      for (const cleanup of cleanups.reverse()) {
        await cleanup();
      }
      cleanups.length = 0;
    },
  };
}
