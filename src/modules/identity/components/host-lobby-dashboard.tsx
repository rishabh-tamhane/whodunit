"use client";

import { useCallback, useEffect, useState } from "react";
import { z } from "zod";

import { Alert, Button, Card, PlayerCard, StatusBadge } from "@/components/ui";
import {
  GameMasterOnboardingViewSchema,
  MembershipIdSchema,
  RoomIdSchema,
} from "@/contracts";
import { ApiClientError, requestJson } from "@/lib/api/request";

const VersionResultSchema = z.object({ stateVersion: z.string() });

function errorMessage(error: unknown) {
  return error instanceof ApiClientError
    ? error.message
    : "The request could not be completed.";
}

export function HostLobbyDashboard({ roomId }: { roomId: string }) {
  const validatedRoomId = RoomIdSchema.parse(roomId);
  const [view, setView] =
    useState<z.infer<typeof GameMasterOnboardingViewSchema>>();
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [rotatedLink, setRotatedLink] = useState<string>();

  const refresh = useCallback(async () => {
    const loaded = await requestJson({
      url: `/api/v1/rooms/${validatedRoomId}/onboarding`,
      outputSchema: GameMasterOnboardingViewSchema,
    });
    setView(loaded);
  }, [validatedRoomId]);

  useEffect(() => {
    const initial = window.setTimeout(() => {
      void refresh().catch((caught) => setError(errorMessage(caught)));
    }, 0);
    const interval = window.setInterval(() => {
      void refresh().catch(() => undefined);
    }, 4_000);
    return () => {
      window.clearTimeout(initial);
      window.clearInterval(interval);
    };
  }, [refresh]);

  async function run(action: () => Promise<unknown>) {
    setBusy(true);
    setError(undefined);
    try {
      await action();
      await refresh();
    } catch (caught) {
      setError(errorMessage(caught));
      await refresh().catch(() => undefined);
    } finally {
      setBusy(false);
    }
  }

  async function review(claimId: string, decision: "APPROVE" | "REJECT") {
    if (!view) return;
    await run(() =>
      requestJson({
        url: `/api/v1/rooms/${validatedRoomId}/claims/${claimId}`,
        method: "PATCH",
        input: { expectedStateVersion: view.room.stateVersion, decision },
        outputSchema: VersionResultSchema,
      }),
    );
  }

  async function revoke(membershipId: string) {
    if (!view) return;
    await run(() =>
      requestJson({
        url: `/api/v1/rooms/${validatedRoomId}/memberships/${MembershipIdSchema.parse(membershipId)}`,
        method: "DELETE",
        input: { expectedStateVersion: view.room.stateVersion },
        outputSchema: VersionResultSchema,
      }),
    );
  }

  async function acknowledgeGuidance() {
    if (!view) return;
    await run(() =>
      requestJson({
        url: `/api/v1/rooms/${validatedRoomId}/acknowledgements/host`,
        method: "POST",
        input: { expectedStateVersion: view.room.stateVersion },
        outputSchema: VersionResultSchema,
      }),
    );
  }

  async function confirmConsent() {
    if (!view) return;
    await run(() =>
      requestJson({
        url: `/api/v1/rooms/${validatedRoomId}/consent`,
        method: "POST",
        input: { expectedStateVersion: view.room.stateVersion },
        outputSchema: VersionResultSchema,
      }),
    );
  }

  async function rotateRecovery() {
    setBusy(true);
    setError(undefined);
    try {
      const result = await requestJson({
        url: `/api/v1/rooms/${validatedRoomId}/recovery`,
        method: "POST",
        outputSchema: z.object({ recoveryPath: z.string() }),
      });
      setRotatedLink(new URL(result.recoveryPath, window.location.origin).href);
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setBusy(false);
    }
  }

  if (!view) {
    return (
      <Card elevated>
        <p role="status">Loading the Game Master lobby…</p>
        {error ? (
          <Alert title="Lobby unavailable" tone="danger">
            {error}
          </Alert>
        ) : null}
      </Card>
    );
  }

  return (
    <div className="grid gap-6">
      <Card elevated>
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="text-sm font-bold text-orange-300">
              Game Master · Room {view.room.roomCode}
            </p>
            <h1 className="mt-1 text-3xl font-black">Lobby control</h1>
          </div>
          <StatusBadge tone={view.readiness.ready ? "success" : "warning"}>
            {view.readiness.ready ? "Ready to generate" : "Setup in progress"}
          </StatusBadge>
        </div>
        <p className="mt-4 text-sm leading-6 text-stone-300">
          You are not a player. You approve devices, control the game, and see
          the complete generated mystery after it locks. Raw descriptions and
          player drafts remain private.
        </p>
      </Card>

      {view.claims.length > 0 ? (
        <Card>
          <h2 className="text-xl font-black">Pending device requests</h2>
          <div className="mt-4 grid gap-3">
            {view.claims.map((claim) => {
              const player = view.players.find(
                (candidate) => candidate.playerId === claim.playerId,
              );
              return (
                <section
                  key={claim.claimId}
                  className="rounded-xl border border-white/10 p-4"
                >
                  <p className="font-black">
                    {player?.displayName} · {player?.costume}
                  </p>
                  <p className="mt-1 text-sm text-stone-400">
                    {claim.requestKind === "RECONNECT"
                      ? "Replacement-device request"
                      : "First-device request"}
                  </p>
                  <div className="mt-3 flex gap-2">
                    <Button
                      disabled={busy}
                      onClick={() => review(claim.claimId, "APPROVE")}
                    >
                      Approve
                    </Button>
                    <Button
                      disabled={busy}
                      variant="ghost"
                      onClick={() => review(claim.claimId, "REJECT")}
                    >
                      Reject
                    </Button>
                  </div>
                </section>
              );
            })}
          </div>
        </Card>
      ) : null}

      <Card>
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-xl font-black">Players</h2>
          <span className="text-sm text-stone-400">
            {view.readiness.activeMembershipCount}/{view.readiness.playerCount}{" "}
            connected
          </span>
        </div>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          {view.players.map((player) => (
            <PlayerCard
              key={player.playerId}
              name={player.displayName}
              costume={player.costume}
              status={player.claimStatus}
              statusTone={
                player.claimStatus === "CONNECTED"
                  ? "success"
                  : player.claimStatus === "DISCONNECTED"
                    ? "danger"
                    : "warning"
              }
              action={
                player.activeMembershipId ? (
                  <Button
                    disabled={busy}
                    variant="ghost"
                    onClick={() => revoke(player.activeMembershipId!)}
                  >
                    Revoke
                  </Button>
                ) : undefined
              }
            />
          ))}
        </div>
      </Card>

      <Card>
        <h2 className="text-xl font-black">Generation readiness</h2>
        <div className="mt-4 grid gap-2 text-sm text-stone-300">
          <p>
            Approved claims: {view.readiness.activeMembershipCount}/
            {view.readiness.playerCount}
          </p>
          <p>
            Player acknowledgements: {view.readiness.acknowledgedPlayerCount}/
            {view.readiness.playerCount}
          </p>
          <p>
            Private responses complete:{" "}
            {view.readiness.completedDescriptionCount}/
            {view.readiness.requiredDescriptionCount}
          </p>
          <p>
            Room consent:{" "}
            {view.readiness.roomConsentConfirmed ? "Confirmed" : "Waiting"}
          </p>
        </div>
        {!view.readiness.hostGuidanceAcknowledged ? (
          <div className="mt-5">
            <p className="text-sm leading-6 text-stone-300">
              I understand the Game Master sees all generated content and
              submitted gameplay state after lock, but never raw descriptions or
              player-owned drafts.
            </p>
            <Button
              className="mt-3"
              disabled={busy}
              onClick={acknowledgeGuidance}
            >
              Acknowledge Game Master guidance
            </Button>
          </div>
        ) : null}
        {!view.readiness.roomConsentConfirmed ? (
          <div className="mt-5 border-t border-white/10 pt-5">
            <p className="text-sm leading-6 text-stone-300">
              I have told everyone this is fictional party entertainment and
              confirmed every participant consents to generation.
            </p>
            <Button className="mt-3" disabled={busy} onClick={confirmConsent}>
              Confirm room consent
            </Button>
          </div>
        ) : null}
      </Card>

      <Card>
        <h2 className="text-xl font-black">Recovery credential</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">
          Rotating immediately invalidates the previously saved recovery link.
        </p>
        <Button
          className="mt-4"
          variant="secondary"
          disabled={busy}
          onClick={rotateRecovery}
        >
          Rotate recovery link
        </Button>
        {rotatedLink ? (
          <div className="mt-4">
            <Alert title="Save this new link now" tone="warning">
              <span className="break-all font-mono">{rotatedLink}</span>
            </Alert>
          </div>
        ) : null}
      </Card>

      {error ? (
        <Alert title="Action did not complete" tone="danger">
          {error}
        </Alert>
      ) : null}
    </div>
  );
}
