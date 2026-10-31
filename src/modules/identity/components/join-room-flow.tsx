"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { z } from "zod";

import {
  Alert,
  Button,
  Card,
  FormField,
  Input,
  PlayerCard,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import {
  ClaimResultSchema,
  OnboardingViewSchema,
  RoomCodeSchema,
  SafeLobbySchema,
  type PlayerId,
} from "@/contracts";
import { ApiClientError, requestJson } from "@/lib/api/request";

const SessionResultSchema = z.strictObject({
  status: z.enum(["created", "restored"]),
});
const VersionResultSchema = z.object({ stateVersion: z.string() });

function message(error: unknown) {
  return error instanceof ApiClientError
    ? error.message
    : "The request could not be completed.";
}

export function JoinRoomFlow({ initialCode = "" }: { initialCode?: string }) {
  const router = useRouter();
  const [code, setCode] = useState(initialCode.toUpperCase());
  const [lobby, setLobby] = useState<z.infer<typeof SafeLobbySchema>>();
  const [view, setView] = useState<z.infer<typeof OnboardingViewSchema>>();
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string>();
  const [drafts, setDrafts] = useState<Record<string, string>>({});

  const loadView = useCallback(async (roomId: string) => {
    const loaded = await requestJson({
      url: `/api/v1/rooms/${roomId}/onboarding`,
      outputSchema: OnboardingViewSchema,
    });
    setView(loaded);
    return loaded;
  }, []);

  const lookup = useCallback(async (submittedCode: string) => {
    const normalized = RoomCodeSchema.parse(submittedCode);
    const found = await requestJson({
      url: "/api/v1/lobbies/lookup",
      method: "POST",
      input: { roomCode: normalized },
      outputSchema: SafeLobbySchema,
    });
    setLobby(found);
  }, []);

  useEffect(() => {
    void (async () => {
      try {
        await requestJson({
          url: "/api/v1/session",
          method: "POST",
          outputSchema: SessionResultSchema,
        });
        if (initialCode) await lookup(initialCode);
      } catch (caught) {
        setError(message(caught));
      } finally {
        setBusy(false);
      }
    })();
  }, [initialCode, lookup]);

  useEffect(() => {
    if (!lobby || view?.actor !== "PENDING_PLAYER") return;
    const interval = window.setInterval(() => {
      void loadView(lobby.roomId).catch(() => undefined);
    }, 3_000);
    return () => window.clearInterval(interval);
  }, [loadView, lobby, view?.actor]);

  useEffect(() => {
    if (!lobby || view?.actor !== "PLAYER") return;
    const heartbeat = () =>
      requestJson({
        url: `/api/v1/rooms/${lobby.roomId}/heartbeat`,
        method: "POST",
        outputSchema: z.object({ lastSeenAt: z.string().nullable() }),
      }).catch(() => undefined);
    void heartbeat();
    const interval = window.setInterval(heartbeat, 30_000);
    return () => window.clearInterval(interval);
  }, [lobby, view?.actor]);

  useEffect(() => {
    if (lobby && view?.actor === "PLAYER" && view.room.status !== "LOBBY") {
      router.replace(`/room/${lobby.roomId}`);
    }
  }, [lobby, router, view]);

  const completedSubjects = useMemo(
    () =>
      new Set(
        view?.actor === "PLAYER"
          ? view.descriptionResponses.map((response) =>
              response.subjectPlayerId.toString(),
            )
          : [],
      ),
    [view],
  );

  async function requestClaim(playerId: PlayerId, occupied: boolean) {
    if (!lobby) return;
    setBusy(true);
    setError(undefined);
    try {
      await requestJson({
        url: `/api/v1/rooms/${lobby.roomId}/claims`,
        method: "POST",
        input: {
          playerId,
          requestKind: occupied ? "RECONNECT" : "INITIAL_CLAIM",
        },
        outputSchema: ClaimResultSchema,
      });
      await loadView(lobby.roomId);
    } catch (caught) {
      setError(message(caught));
    } finally {
      setBusy(false);
    }
  }

  async function acknowledge() {
    if (!lobby || view?.actor !== "PLAYER") return;
    setBusy(true);
    try {
      await requestJson({
        url: `/api/v1/rooms/${lobby.roomId}/acknowledgements/player`,
        method: "POST",
        input: { expectedStateVersion: view.room.stateVersion },
        outputSchema: VersionResultSchema,
      });
      await loadView(lobby.roomId);
    } catch (caught) {
      setError(message(caught));
    } finally {
      setBusy(false);
    }
  }

  async function saveDescription(
    subjectPlayerId: PlayerId,
    responseStatus: "SUBMITTED" | "DECLINED",
  ) {
    if (!lobby || view?.actor !== "PLAYER") return;
    setBusy(true);
    try {
      await requestJson({
        url: `/api/v1/rooms/${lobby.roomId}/descriptions`,
        method: "PUT",
        input: {
          expectedStateVersion: view.room.stateVersion,
          subjectPlayerId,
          responseStatus,
          descriptionText:
            responseStatus === "SUBMITTED"
              ? (drafts[subjectPlayerId] ?? "")
              : null,
        },
        outputSchema: VersionResultSchema,
      });
      await loadView(lobby.roomId);
    } catch (caught) {
      setError(message(caught));
    } finally {
      setBusy(false);
    }
  }

  if (busy && !lobby && !view) {
    return (
      <Card>
        <p role="status">Starting a private guest session…</p>
      </Card>
    );
  }

  if (view?.actor === "PENDING_PLAYER") {
    return (
      <Card elevated>
        <StatusBadge tone="warning">Waiting for approval</StatusBadge>
        <h2 className="mt-4 text-2xl font-black">Request sent</h2>
        <p className="mt-3 leading-7 text-stone-300">
          The Game Master must approve this device before it receives any
          private game information. You can safely refresh this page.
        </p>
      </Card>
    );
  }

  if (view?.actor === "PLAYER") {
    const otherPlayers = view.players.filter(
      (player) => player.playerId !== view.self.playerId,
    );
    const allDescriptionsComplete = otherPlayers.every((player) =>
      completedSubjects.has(player.playerId),
    );
    return (
      <div className="grid gap-6">
        <Card elevated>
          <StatusBadge tone="success">Connected</StatusBadge>
          <h2 className="mt-4 text-2xl font-black">
            {view.self.displayName} · {view.self.costume}
          </h2>
          <p className="mt-3 text-sm leading-6 text-stone-300">
            Your identity is connected. Your secret faction is assigned only
            when the one mystery is generated and locked.
          </p>
        </Card>

        {!view.self.acknowledged ? (
          <Card>
            <h2 className="text-xl font-black">
              Fictional-use acknowledgement
            </h2>
            <p className="mt-3 text-sm leading-6 text-stone-300">
              I understand that submitted details may inspire fictional mystery
              content, and I have avoided sensitive or harmful personal
              information.
            </p>
            <Button className="mt-5" onClick={acknowledge} disabled={busy}>
              I understand
            </Button>
          </Card>
        ) : null}

        {view.self.acknowledged ? (
          <Card>
            <h2 className="text-xl font-black">Private descriptions</h2>
            <p className="mt-2 text-sm leading-6 text-stone-400">
              The raw text and who wrote it are never shown to the Game Master
              or other players. Avoid caste, religion, health, finances, trauma,
              or intimate details.
            </p>
            <div className="mt-5 grid gap-5">
              {otherPlayers.map((player) => {
                const existing = view.descriptionResponses.find(
                  (response) => response.subjectPlayerId === player.playerId,
                );
                return (
                  <section
                    key={player.playerId}
                    className="rounded-xl border border-white/10 p-4"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <h3 className="font-black">
                        {player.displayName} · {player.costume}
                      </h3>
                      {existing ? (
                        <StatusBadge tone="success">Complete</StatusBadge>
                      ) : null}
                    </div>
                    <FormField
                      id={`description-${player.playerId}`}
                      label="Party-safe detail"
                    >
                      <Textarea
                        id={`description-${player.playerId}`}
                        maxLength={500}
                        value={
                          drafts[player.playerId] ??
                          existing?.descriptionText ??
                          ""
                        }
                        onChange={(event) =>
                          setDrafts((current) => ({
                            ...current,
                            [player.playerId]: event.target.value,
                          }))
                        }
                      />
                    </FormField>
                    <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                      <Button
                        disabled={busy}
                        onClick={() =>
                          saveDescription(player.playerId, "SUBMITTED")
                        }
                      >
                        Save description
                      </Button>
                      <Button
                        disabled={busy}
                        variant="ghost"
                        onClick={() =>
                          saveDescription(player.playerId, "DECLINED")
                        }
                      >
                        Prefer not to answer
                      </Button>
                    </div>
                  </section>
                );
              })}
            </div>
          </Card>
        ) : null}

        {allDescriptionsComplete ? (
          <Alert title="You are ready" tone="success">
            Your private setup is complete. Keep this device connected while the
            Game Master waits for everyone else.
          </Alert>
        ) : null}
        {error ? (
          <Alert title="Action not saved" tone="danger">
            {error}
          </Alert>
        ) : null}
      </div>
    );
  }

  if (lobby) {
    return (
      <div className="grid gap-5">
        <Alert title="The Game Master runs the mystery" tone="violet">
          After lock, the Game Master sees the solution, generated roles,
          secrets, missions, evidence, and gameplay you explicitly submit.
          Notebook and unsubmitted drafts remain private.
        </Alert>
        <Card>
          <p className="text-sm font-bold text-violet-200">
            Room {lobby.roomCode}
          </p>
          <h2 className="mt-1 text-2xl font-black">Who are you?</h2>
          <div className="mt-5 grid gap-3">
            {lobby.slots.map((slot) => (
              <PlayerCard
                key={slot.playerId}
                name={slot.displayName}
                costume={`${slot.costume} · Seat ${slot.seatOrder}`}
                status={
                  slot.slotStatus === "OCCUPIED"
                    ? "Reconnect"
                    : slot.slotStatus === "PENDING"
                      ? "Pending"
                      : "Available"
                }
                statusTone={
                  slot.slotStatus === "AVAILABLE" ? "success" : "warning"
                }
                action={
                  <Button
                    variant="ghost"
                    disabled={busy}
                    onClick={() =>
                      requestClaim(
                        slot.playerId,
                        slot.slotStatus === "OCCUPIED",
                      )
                    }
                  >
                    {slot.slotStatus === "OCCUPIED"
                      ? "Request reconnect"
                      : "Choose"}
                  </Button>
                }
              />
            ))}
          </div>
        </Card>
        {error ? (
          <Alert title="Could not request this slot" tone="danger">
            {error}
          </Alert>
        ) : null}
      </div>
    );
  }

  return (
    <Card elevated>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          setBusy(true);
          setError(undefined);
          void lookup(code)
            .catch((caught) => setError(message(caught)))
            .finally(() => setBusy(false));
        }}
      >
        <h2 className="text-2xl font-black">Enter the room code</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">
          A code finds the party. It never unlocks private game information.
        </p>
        <div className="mt-5">
          <FormField id="room-code" label="Room code">
            <Input
              id="room-code"
              autoComplete="off"
              inputMode="text"
              required
              value={code}
              onChange={(event) => setCode(event.target.value.toUpperCase())}
            />
          </FormField>
        </div>
        <Button className="mt-5 w-full" type="submit" disabled={busy}>
          {busy ? "Finding room…" : "Find room"}
        </Button>
      </form>
      {error ? (
        <div className="mt-4">
          <Alert title="Room not found" tone="danger">
            {error}
          </Alert>
        </div>
      ) : null}
    </Card>
  );
}
