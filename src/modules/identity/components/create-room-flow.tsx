"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { z } from "zod";

import {
  Alert,
  Button,
  Card,
  FormField,
  Input,
  StatusBadge,
  StickyActionBar,
} from "@/components/ui";
import {
  CreatedRoomSchema,
  RoomConfigurationSchema,
  RoomMutationResultSchema,
} from "@/contracts";
import {
  ApiClientError,
  createIdempotencyKey,
  requestJson,
} from "@/lib/api/request";

const SessionResultSchema = z.strictObject({
  status: z.enum(["created", "restored"]),
});

const SetupProfilesSchema = z.strictObject({
  durationProfileVersion: z.literal("duration-v1"),
  durations: z.array(
    z.object({
      durationMinutes: z.number().int(),
      roundCount: z.number().int(),
    }),
  ),
  factionProfileVersion: z.literal("factions-v1"),
  factionRecommendations: z.array(
    z.object({
      playerCount: z.number().int(),
      murderers: z.number().int(),
      accomplices: z.number().int(),
      innocents: z.number().int(),
      rationale: z.string(),
    }),
  ),
});

type CreatedRoom = z.infer<typeof CreatedRoomSchema>;
type Profiles = z.infer<typeof SetupProfilesSchema>;
type Slot = {
  key: string;
  displayName: string;
  costume: string;
  hostBackground: string;
};

const fallbackRecommendation = {
  playerCount: 4,
  murderers: 1,
  accomplices: 0,
  innocents: 3,
  rationale: "One hidden threat keeps a small group readable.",
};

function errorMessage(error: unknown) {
  return error instanceof ApiClientError
    ? error.message
    : "Something went wrong. Try again.";
}

function initialSlots(count: number, startAt = 0): Slot[] {
  return Array.from({ length: count }, (_, index) => ({
    displayName: "",
    costume: "",
    hostBackground: "",
    key: `slot-${startAt + index}`,
  }));
}

export function CreateRoomFlow() {
  const router = useRouter();
  const [phase, setPhase] = useState<
    "bootstrapping" | "create" | "save-recovery" | "configure" | "invite"
  >("bootstrapping");
  const [room, setRoom] = useState<CreatedRoom>();
  const [profiles, setProfiles] = useState<Profiles>();
  const [recoverySaved, setRecoverySaved] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [slots, setSlots] = useState(() => initialSlots(4));
  const [durationMinutes, setDurationMinutes] = useState<
    30 | 45 | 60 | 90 | 120
  >(60);
  const [murdererCount, setMurdererCount] = useState(1);
  const [accompliceCount, setAccompliceCount] = useState(0);
  const [innocentCount, setInnocentCount] = useState(3);
  const [murdererAware, setMurdererAware] = useState(true);

  useEffect(() => {
    void (async () => {
      try {
        await requestJson({
          url: "/api/v1/session",
          method: "POST",
          outputSchema: SessionResultSchema,
        });
        const loadedProfiles = await requestJson({
          url: "/api/v1/setup-profiles",
          outputSchema: SetupProfilesSchema,
        });
        setProfiles(loadedProfiles);
        setPhase("create");
      } catch (caught) {
        setError(errorMessage(caught));
      }
    })();
  }, []);

  const recommendation = useMemo(
    () =>
      profiles?.factionRecommendations.find(
        (candidate) => candidate.playerCount === slots.length,
      ) ?? fallbackRecommendation,
    [profiles, slots.length],
  );

  function resizeSlots(count: number) {
    setSlots((current) => {
      if (current.length === count) return current;
      if (current.length > count) return current.slice(0, count);
      return [
        ...current,
        ...initialSlots(count - current.length, current.length),
      ];
    });
    const nextRecommendation =
      profiles?.factionRecommendations.find(
        (candidate) => candidate.playerCount === count,
      ) ?? fallbackRecommendation;
    setMurdererCount(nextRecommendation.murderers);
    setAccompliceCount(nextRecommendation.accomplices);
    setInnocentCount(nextRecommendation.innocents);
  }

  async function createRoom() {
    setBusy(true);
    setError(undefined);
    try {
      const created = await requestJson({
        url: "/api/v1/rooms",
        method: "POST",
        outputSchema: CreatedRoomSchema,
      });
      setRoom(created);
      setPhase("save-recovery");
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setBusy(false);
    }
  }

  async function copy(value: string) {
    await navigator.clipboard.writeText(
      new URL(value, window.location.origin).href,
    );
  }

  async function saveConfiguration() {
    if (!room) return;
    const configuration = RoomConfigurationSchema.safeParse({
      durationProfileVersion: "duration-v1",
      factionProfileVersion: "factions-v1",
      durationMinutes,
      murdererCount,
      accompliceCount,
      innocentCount,
      murdererAware,
      playerSlots: slots.map((slot) => ({
        displayName: slot.displayName,
        costume: slot.costume,
        hostBackground: slot.hostBackground,
      })),
    });
    if (!configuration.success) {
      setError(configuration.error.issues[0]?.message ?? "Review the setup.");
      return;
    }

    setBusy(true);
    setError(undefined);
    try {
      const saved = await requestJson({
        url: `/api/v1/rooms/${room.roomId}/configuration`,
        method: "PUT",
        input: {
          expectedStateVersion: room.stateVersion,
          configuration: configuration.data,
        },
        outputSchema: RoomMutationResultSchema,
        metadata: {
          idempotencyKey: createIdempotencyKey(),
          expectedStateVersion: room.stateVersion,
        },
      });
      const opened = await requestJson({
        url: `/api/v1/rooms/${room.roomId}/open-lobby`,
        method: "POST",
        input: { expectedStateVersion: saved.stateVersion },
        outputSchema: RoomMutationResultSchema,
        metadata: {
          idempotencyKey: createIdempotencyKey(),
          expectedStateVersion: saved.stateVersion,
        },
      });
      setRoom({ ...room, ...opened });
      setPhase("invite");
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setBusy(false);
    }
  }

  if (phase === "bootstrapping") {
    return (
      <Card elevated>
        <p role="status" className="text-sm text-stone-300">
          Starting your private Game Master session…
        </p>
        {error ? (
          <div className="mt-4">
            <Alert title="Session unavailable" tone="danger">
              {error}
            </Alert>
          </div>
        ) : null}
      </Card>
    );
  }

  if (phase === "create") {
    return (
      <Card elevated>
        <h2 className="text-2xl font-black">Create a new mystery room</h2>
        <p className="mt-3 leading-7 text-stone-300">
          You are the dedicated Game Master. You will not receive a player slot,
          and after lock you can see and control the complete generated game.
        </p>
        {error ? (
          <div className="mt-5">
            <Alert title="Room not created" tone="danger">
              {error}
            </Alert>
          </div>
        ) : null}
        <Button
          className="mt-6 w-full sm:w-auto"
          onClick={createRoom}
          disabled={busy}
        >
          {busy ? "Creating…" : "Create room"}
        </Button>
      </Card>
    );
  }

  if (!room) return null;

  if (phase === "save-recovery") {
    return (
      <Card elevated>
        <StatusBadge tone="warning">Save before continuing</StatusBadge>
        <h2 className="mt-4 text-2xl font-black">Save your recovery link</h2>
        <p className="mt-3 leading-7 text-stone-300">
          This private link restores Game Master control on a replacement
          device. It is separate from the public room code and is shown only
          now.
        </p>
        <div className="mt-5 break-all rounded-xl border border-white/10 bg-black/25 p-4 font-mono text-sm text-orange-200">
          {new URL(room.recoveryPath, window.location.origin).href}
        </div>
        <Button
          className="mt-4"
          variant="secondary"
          onClick={() => copy(room.recoveryPath)}
        >
          Copy recovery link
        </Button>
        <label className="mt-6 flex min-h-11 items-center gap-3 text-sm font-bold">
          <input
            type="checkbox"
            className="size-5"
            checked={recoverySaved}
            onChange={(event) => setRecoverySaved(event.target.checked)}
          />
          I saved the private recovery link somewhere safe.
        </label>
        <Button
          className="mt-5 w-full sm:w-auto"
          disabled={!recoverySaved}
          onClick={() => setPhase("configure")}
        >
          Configure players
        </Button>
      </Card>
    );
  }

  if (phase === "invite") {
    const inviteUrl = new URL(room.joinPath, window.location.origin).href;
    return (
      <Card elevated>
        <StatusBadge tone="success">Lobby open</StatusBadge>
        <h2 className="mt-4 text-3xl font-black">Room {room.roomCode}</h2>
        <p className="mt-3 leading-7 text-stone-300">
          Share only this public player invitation. The room code finds the safe
          lobby; every device still needs your approval.
        </p>
        <div className="mt-5 break-all rounded-xl border border-white/10 bg-black/25 p-4 font-mono text-sm">
          {inviteUrl}
        </div>
        <div className="mt-4 flex flex-col gap-2 sm:flex-row">
          <Button variant="secondary" onClick={() => copy(room.joinPath)}>
            Copy invitation
          </Button>
          <Button
            onClick={() =>
              navigator.share?.({
                title: `Whodunit room ${room.roomCode}`,
                text: `Join our Whodunit mystery with code ${room.roomCode}`,
                url: inviteUrl,
              })
            }
          >
            Share invitation
          </Button>
          <Button
            onClick={() => {
              router.push(`/host/rooms/${room.roomId}`);
            }}
          >
            Manage lobby
          </Button>
        </div>
      </Card>
    );
  }

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        void saveConfiguration();
      }}
      className="grid gap-6"
    >
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="text-sm font-bold text-orange-300">
              Room {room.roomCode}
            </p>
            <h2 className="mt-1 text-2xl font-black">Game setup</h2>
          </div>
          <StatusBadge>NPC victim</StatusBadge>
        </div>
        <div className="mt-6 grid gap-5 sm:grid-cols-2">
          <FormField
            id="player-count"
            label="Players"
            hint="The Game Master is not included."
          >
            <select
              id="player-count"
              className="min-h-11 w-full rounded-xl border border-white/15 bg-black/20 px-3 text-base"
              value={slots.length}
              onChange={(event) => resizeSlots(Number(event.target.value))}
            >
              {Array.from({ length: 9 }, (_, index) => index + 4).map(
                (count) => (
                  <option key={count} value={count}>
                    {count}
                  </option>
                ),
              )}
            </select>
          </FormField>
          <FormField id="duration" label="Planned duration">
            <select
              id="duration"
              className="min-h-11 w-full rounded-xl border border-white/15 bg-black/20 px-3 text-base"
              value={durationMinutes}
              onChange={(event) =>
                setDurationMinutes(
                  Number(event.target.value) as typeof durationMinutes,
                )
              }
            >
              {(profiles?.durations ?? []).map((duration) => (
                <option
                  key={duration.durationMinutes}
                  value={duration.durationMinutes}
                >
                  {duration.durationMinutes} minutes · {duration.roundCount}{" "}
                  rounds
                </option>
              ))}
            </select>
          </FormField>
        </div>
      </Card>

      <Card>
        <h2 className="text-xl font-black">Players</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">
          Duplicate names are fine; costumes and seat numbers help players
          choose correctly.
        </p>
        <div className="mt-5 grid gap-4">
          {slots.map((slot, index) => (
            <fieldset
              key={slot.key}
              className="grid gap-3 rounded-xl border border-white/10 p-4 sm:grid-cols-2"
            >
              <legend className="px-2 text-sm font-black">
                Player {index + 1}
              </legend>
              <FormField id={`name-${slot.key}`} label="Name">
                <Input
                  id={`name-${slot.key}`}
                  required
                  maxLength={100}
                  value={slot.displayName}
                  onChange={(event) =>
                    setSlots((current) =>
                      current.map((item, itemIndex) =>
                        itemIndex === index
                          ? { ...item, displayName: event.target.value }
                          : item,
                      ),
                    )
                  }
                />
              </FormField>
              <FormField id={`costume-${slot.key}`} label="Costume">
                <Input
                  id={`costume-${slot.key}`}
                  required
                  maxLength={200}
                  value={slot.costume}
                  onChange={(event) =>
                    setSlots((current) =>
                      current.map((item, itemIndex) =>
                        itemIndex === index
                          ? { ...item, costume: event.target.value }
                          : item,
                      ),
                    )
                  }
                />
              </FormField>
              <div className="sm:col-span-2">
                <FormField
                  id={`detail-${slot.key}`}
                  label="Optional setup detail"
                >
                  <Input
                    id={`detail-${slot.key}`}
                    maxLength={1_000}
                    value={slot.hostBackground}
                    onChange={(event) =>
                      setSlots((current) =>
                        current.map((item, itemIndex) =>
                          itemIndex === index
                            ? { ...item, hostBackground: event.target.value }
                            : item,
                        ),
                      )
                    }
                  />
                </FormField>
              </div>
            </fieldset>
          ))}
        </div>
      </Card>

      <Card>
        <h2 className="text-xl font-black">Faction balance</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">
          Suggested for {slots.length} players: {recommendation.murderers}{" "}
          murderer(s), {recommendation.accomplices} accomplice(s), and{" "}
          {recommendation.innocents} innocent(s). {recommendation.rationale}
        </p>
        <div className="mt-5 grid gap-4 sm:grid-cols-3">
          <FormField id="murderers" label="Murderers">
            <Input
              id="murderers"
              type="number"
              min={1}
              max={12}
              value={murdererCount}
              onChange={(event) => setMurdererCount(Number(event.target.value))}
            />
          </FormField>
          <FormField id="accomplices" label="Accomplices">
            <Input
              id="accomplices"
              type="number"
              min={0}
              max={12}
              value={accompliceCount}
              onChange={(event) =>
                setAccompliceCount(Number(event.target.value))
              }
            />
          </FormField>
          <FormField id="innocents" label="Innocents">
            <Input
              id="innocents"
              type="number"
              min={1}
              max={12}
              value={innocentCount}
              onChange={(event) => setInnocentCount(Number(event.target.value))}
            />
          </FormField>
        </div>
        <label className="mt-5 flex min-h-11 items-center gap-3 text-sm font-bold">
          <input
            type="checkbox"
            className="size-5"
            checked={murdererAware}
            onChange={(event) => setMurdererAware(event.target.checked)}
          />
          Murderers know their faction from the start
        </label>
      </Card>

      {error ? (
        <Alert title="Setup not saved" tone="danger">
          {error}
        </Alert>
      ) : null}
      <StickyActionBar>
        <Button type="submit" disabled={busy} className="w-full sm:w-auto">
          {busy ? "Opening lobby…" : "Save and open lobby"}
        </Button>
      </StickyActionBar>
    </form>
  );
}
