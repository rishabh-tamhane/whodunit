"use client";

import { useCallback, useEffect, useState } from "react";
import { z } from "zod";

import { Alert, Button, Card, PlayerCard, StatusBadge } from "@/components/ui";
import {
  GenerationStatusViewSchema,
  GameMasterOnboardingViewSchema,
  MembershipIdSchema,
  RoomIdSchema,
  StartedGenerationSchema,
} from "@/contracts";
import {
  ApiClientError,
  createIdempotencyKey,
  requestJson,
} from "@/lib/api/request";

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
  const [generation, setGeneration] =
    useState<z.infer<typeof GenerationStatusViewSchema>>();

  const refresh = useCallback(async () => {
    const loaded = await requestJson({
      url: `/api/v1/rooms/${validatedRoomId}/onboarding`,
      outputSchema: GameMasterOnboardingViewSchema,
    });
    setView(loaded);
    const generationStatus = await requestJson({
      url: `/api/v1/rooms/${validatedRoomId}/generation`,
      outputSchema: GenerationStatusViewSchema,
    });
    setGeneration(generationStatus);
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

  async function generateMystery() {
    if (!view || !view.readiness.ready || generation?.locked) return;
    await run(() =>
      requestJson({
        url: `/api/v1/rooms/${validatedRoomId}/generation`,
        method: "POST",
        input: {
          expectedStateVersion: view.room.stateVersion,
          idempotencyKey: createIdempotencyKey(),
        },
        outputSchema: StartedGenerationSchema,
      }),
    );
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
        <div className="mt-6 border-t border-white/10 pt-5">
          {generation?.locked ? (
            <Alert title="Mystery locked" tone="success">
              The one canonical story is ready. It can never regenerate or be
              replaced; all generated content is now available to you as Game
              Master.
            </Alert>
          ) : generation?.job?.status === "RUNNING" ||
            generation?.job?.status === "PENDING" ? (
            <div role="status" aria-live="polite">
              <StatusBadge tone="violet">
                {generation.job.phase.replaceAll("_", " ")}
              </StatusBadge>
              <p className="mt-3 font-bold">Building the mystery…</p>
              <p className="mt-2 text-sm leading-6 text-stone-400">
                Validation, repair, and locking may take several minutes. You
                can safely leave this page or refresh; no partial story is ever
                shown.
              </p>
              <p className="mt-2 text-xs text-stone-500">
                Attempt {generation.job.attemptCount} · repairs{" "}
                {generation.job.repairCount}/2
              </p>
            </div>
          ) : generation?.job?.status === "FAILED" ? (
            <Alert title="Generation did not lock" tone="danger">
              No partial story was saved. Private source text was purged. Ask
              players to resubmit their descriptions, then generate again.
            </Alert>
          ) : (
            <>
              <p className="text-sm leading-6 text-stone-300">
                Once started, the system validates and may repair the mystery
                before one atomic lock. After lock there is no regenerate
                button; create a new room for a different story.
              </p>
              <Button
                className="mt-4 w-full sm:w-auto"
                disabled={busy || !view.readiness.ready}
                onClick={generateMystery}
              >
                {busy ? "Starting…" : "Generate and lock mystery"}
              </Button>
              {!view.readiness.ready ? (
                <p className="mt-2 text-xs text-amber-200">
                  Complete every readiness item before generation.
                </p>
              ) : null}
            </>
          )}
        </div>
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
