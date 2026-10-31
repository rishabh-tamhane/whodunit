import type { AuthUserId, PlayerId, RoomId } from "@/contracts/domain/ids";

declare const roomId: RoomId;
declare const playerId: PlayerId;
declare const authUserId: AuthUserId;

const acceptsRoomId = (value: RoomId) => void value;
const acceptsPlayerId = (value: PlayerId) => void value;

acceptsRoomId(roomId);
acceptsPlayerId(playerId);

// @ts-expect-error Player IDs and room IDs must remain incompatible.
acceptsRoomId(playerId);

// @ts-expect-error Auth users are not generated player identities.
acceptsPlayerId(authUserId);
