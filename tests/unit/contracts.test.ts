import { describe, expect, it } from "vitest";

import {
  ApiErrorEnvelopeSchema,
  DomainCommandMetadataSchema,
  MembershipStatusSchema,
  MissionStatusSchema,
  RoomIdSchema,
  ROOM_STATE_TRANSITIONS,
  RoomStateSchema,
  StateVersionSchema,
  canTransitionRoomState,
} from "@/contracts";

const UUID = "67e55044-10b1-426f-9247-bb680e5fe0c8";

describe("domain contracts", () => {
  it("validates branded UUIDs and decimal state versions", () => {
    expect(RoomIdSchema.parse(UUID)).toBe(UUID);
    expect(() => RoomIdSchema.parse("not-a-uuid")).toThrow();
    expect(StateVersionSchema.parse("42")).toBe("42");
    expect(() => StateVersionSchema.parse("-1")).toThrow();
  });

  it("encodes the room lifecycle without regeneration after lock", () => {
    expect(canTransitionRoomState("LOBBY", "GENERATING")).toBe(true);
    expect(canTransitionRoomState("GENERATING", "READY_TO_START")).toBe(true);
    expect(canTransitionRoomState("READY_TO_START", "GENERATING")).toBe(false);
    expect(canTransitionRoomState("COMPLETED", "DRAFT")).toBe(false);

    for (const from of RoomStateSchema.options) {
      for (const to of RoomStateSchema.options) {
        expect(canTransitionRoomState(from, to)).toBe(
          (ROOM_STATE_TRANSITIONS[from] as readonly string[]).includes(to),
        );
      }
    }
  });

  it("exposes exact membership and mission states", () => {
    expect(MembershipStatusSchema.parse("ACTIVE")).toBe("ACTIVE");
    expect(MissionStatusSchema.parse("CONSEQUENCE_PENDING")).toBe(
      "CONSEQUENCE_PENDING",
    );
  });

  it("validates command metadata", () => {
    expect(
      DomainCommandMetadataSchema.parse({
        idempotencyKey: UUID,
        expectedStateVersion: "7",
      }),
    ).toEqual({
      idempotencyKey: UUID,
      expectedStateVersion: "7",
    });
  });

  it("uses a safe, stable API error envelope", () => {
    expect(
      ApiErrorEnvelopeSchema.parse({
        error: {
          code: "STALE_STATE_VERSION",
          message: "The room changed. Refresh and try again.",
          requestId: "request-123",
          currentStateVersion: "8",
        },
      }),
    ).toMatchObject({
      error: {
        code: "STALE_STATE_VERSION",
      },
    });
  });
});
