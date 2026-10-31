import { z } from "zod";

export const RoomStateSchema = z.enum([
  "DRAFT",
  "LOBBY",
  "GENERATING",
  "READY_TO_START",
  "IN_PROGRESS",
  "FINAL_ACCUSATIONS",
  "REVEAL",
  "COMPLETED",
]);

export type RoomState = z.infer<typeof RoomStateSchema>;

export const ROOM_STATE_TRANSITIONS = {
  DRAFT: ["LOBBY"],
  LOBBY: ["GENERATING"],
  GENERATING: ["LOBBY", "READY_TO_START"],
  READY_TO_START: ["IN_PROGRESS"],
  IN_PROGRESS: ["FINAL_ACCUSATIONS"],
  FINAL_ACCUSATIONS: ["REVEAL"],
  REVEAL: ["COMPLETED"],
  COMPLETED: [],
} as const satisfies Record<RoomState, readonly RoomState[]>;

export function canTransitionRoomState(
  from: RoomState,
  to: RoomState,
): boolean {
  return (ROOM_STATE_TRANSITIONS[from] as readonly RoomState[]).includes(to);
}
