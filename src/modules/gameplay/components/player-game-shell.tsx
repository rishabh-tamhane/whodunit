"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import type { z } from "zod";

import {
  Alert,
  Button,
  Card,
  EvidenceCard,
  MissionCard,
  SecretPanel,
  StatusBadge,
  Textarea,
} from "@/components/ui";
import {
  EndgameCommandResultSchema,
  FinalAccusationSaveResultSchema,
  GameplayCommandResultSchema,
  NotebookSaveResultSchema,
  PlayerViewSchema,
} from "@/contracts";
import { createIdempotencyKey, requestJson } from "@/lib/api/request";
import {
  useActorProjection,
  type ActorView,
} from "@/modules/gameplay/use-actor-projection";

type PlayerView = z.infer<typeof PlayerViewSchema>;
type Surface =
  | "waiting"
  | "dossier"
  | "mission"
  | "evidence"
  | "notebook"
  | "accuse"
  | "reveal";
function records(input: unknown): Record<string, unknown>[] {
  return Array.isArray(input)
    ? input.filter(
        (item): item is Record<string, unknown> =>
          typeof item === "object" && item !== null,
      )
    : [];
}
function value(
  record: Record<string, unknown> | undefined | null,
  key: string,
): string {
  const item = record?.[key];
  return typeof item === "string" ? item : "";
}

function nestedValue(
  record: Record<string, unknown> | undefined | null,
  key: string,
  nestedKey: string,
): string {
  const item = record?.[key];
  return typeof item === "object" && item !== null
    ? value(item as Record<string, unknown>, nestedKey)
    : "";
}

function notebookSuspects(
  note: Record<string, unknown> | undefined | null,
): string[] {
  return Array.isArray(note?.suspects)
    ? note.suspects.flatMap((item) =>
        typeof item === "object" && item !== null
          ? [value(item as Record<string, unknown>, "playerId")].filter(Boolean)
          : [],
      )
    : [];
}
export function PlayerGameShell({
  roomId,
  surface,
  initialView,
}: {
  roomId: string;
  surface: Surface;
  initialView: PlayerView;
}) {
  const { view, error, connection, refresh } = useActorProjection(
    roomId,
    initialView as ActorView,
  );
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string>();
  const player = view?.actor === "PLAYER" ? view : undefined;
  const note = player?.notebook;
  const [notes, setNotes] = useState(() => value(note, "notesText"));
  const [revision, setRevision] = useState(() => Number(note?.revision ?? 0));
  const [dirty, setDirty] = useState(false);
  const [saveState, setSaveState] = useState<"SAVED" | "SAVING" | "FAILED">(
    "SAVED",
  );
  const [theoryText, setTheoryText] = useState("");
  const [suspects, setSuspects] = useState<string[]>(() =>
    notebookSuspects(note),
  );
  const [evidenceIds, setEvidenceIds] = useState<string[]>([]);
  const initialAccusation = initialView.finalAccusation;
  const initialFinalCase =
    typeof initialAccusation?.case === "object" &&
    initialAccusation.case !== null
      ? (initialAccusation.case as Record<string, unknown>)
      : {};
  const initialIds = (key: string) =>
    Array.isArray(initialFinalCase[key])
      ? initialFinalCase[key].filter(
          (item): item is string => typeof item === "string",
        )
      : [];
  const [finalMurderers, setFinalMurderers] = useState<string[]>(() =>
    initialIds("murdererPlayerIds"),
  );
  const [finalAccomplices, setFinalAccomplices] = useState<string[]>(() =>
    initialIds("accomplicePlayerIds"),
  );
  const [finalEvidence, setFinalEvidence] = useState<string[]>(() =>
    initialIds("evidenceIds"),
  );
  const [finalMotive, setFinalMotive] = useState(() =>
    value(initialFinalCase, "motive"),
  );
  const [finalMethod, setFinalMethod] = useState(() =>
    value(initialFinalCase, "method"),
  );
  const [finalExplanation, setFinalExplanation] = useState(() =>
    value(initialAccusation, "explanation"),
  );
  const [finalRevision, setFinalRevision] = useState(() =>
    Number(initialAccusation?.revision ?? 0),
  );
  const [finalDirty, setFinalDirty] = useState(false);
  const [finalSaveState, setFinalSaveState] = useState<
    "SAVED" | "SAVING" | "FAILED"
  >("SAVED");
  const [finalSubmitted, setFinalSubmitted] = useState(
    value(initialAccusation, "status") === "SUBMITTED",
  );
  const [initiallyVisibleEvidence] = useState(
    () =>
      new Set((initialView.evidence ?? []).map((item) => value(item, "id"))),
  );
  const saveNotebook = useCallback(async () => {
    setSaveState("SAVING");
    try {
      const result = await requestJson({
        url: `/api/v1/rooms/${roomId}/notebook`,
        method: "PUT",
        input: {
          expectedRevision: revision,
          notesText: notes,
          suspects: suspects.map((id) => ({
            playerId: id,
            suspectedRole: "MURDERER",
          })),
        },
        outputSchema: NotebookSaveResultSchema,
      });
      setRevision(result.revision);
      setDirty(false);
      setSaveState("SAVED");
    } catch {
      setSaveState("FAILED");
    }
  }, [notes, revision, roomId, suspects]);
  useEffect(() => {
    if (!dirty) return;
    const timer = window.setTimeout(() => {
      void saveNotebook();
    }, 900);
    return () => window.clearTimeout(timer);
  }, [dirty, notes, saveNotebook]);
  const saveFinalCase = useCallback(async (): Promise<boolean> => {
    if (
      finalSubmitted ||
      player?.room.status !== "FINAL_ACCUSATIONS" ||
      finalMurderers.length === 0 ||
      !finalMotive.trim() ||
      !finalMethod.trim()
    )
      return false;
    setFinalSaveState("SAVING");
    try {
      const result = await requestJson({
        url: `/api/v1/rooms/${roomId}/accusations`,
        method: "PUT",
        input: {
          expectedRevision: finalRevision,
          structuredCase: {
            murdererPlayerIds: finalMurderers,
            accomplicePlayerIds: finalAccomplices,
            motive: finalMotive,
            method: finalMethod,
            evidenceIds: finalEvidence,
          },
          explanationText: finalExplanation,
        },
        outputSchema: FinalAccusationSaveResultSchema,
      });
      setFinalRevision(result.revision);
      setFinalDirty(false);
      setFinalSaveState("SAVED");
      return true;
    } catch {
      setFinalSaveState("FAILED");
      return false;
    }
  }, [
    finalAccomplices,
    finalEvidence,
    finalExplanation,
    finalMethod,
    finalMotive,
    finalMurderers,
    finalRevision,
    finalSubmitted,
    player?.room.status,
    roomId,
  ]);
  useEffect(() => {
    if (!finalDirty || finalSubmitted) return;
    const timer = window.setTimeout(() => {
      void saveFinalCase();
    }, 900);
    return () => window.clearTimeout(timer);
  }, [finalDirty, finalSubmitted, saveFinalCase]);
  const missions = player?.missions ?? [];
  const evidence = player?.evidence ?? [];
  const currentMissions = missions.filter(
    (item) => value(item, "roundId") === player?.room.currentRoundId,
  );
  if (!player)
    return (
      <Alert title="Player access moved" tone="danger">
        This device no longer has an active player binding. Return to Join and
        request a reconnect.
      </Alert>
    );
  const activePlayer = player;
  const reveal =
    typeof player.reveal === "object" && player.reveal !== null
      ? (player.reveal as Record<string, unknown>)
      : undefined;
  const revealSolution =
    typeof reveal?.solution === "object" && reveal.solution !== null
      ? (reveal.solution as Record<string, unknown>)
      : undefined;
  const canonicalSolution =
    typeof revealSolution?.canonicalSolution === "object" &&
    revealSolution.canonicalSolution !== null
      ? (revealSolution.canonicalSolution as Record<string, unknown>)
      : undefined;
  async function run(action: () => Promise<unknown>) {
    setBusy(true);
    setActionError(undefined);
    try {
      await action();
      await refresh();
    } catch (caught) {
      await refresh().catch(() => undefined);
      setActionError(
        caught instanceof Error ? caught.message : "Action failed.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function recoverNotebook() {
    setSaveState("SAVING");
    try {
      const latest = await refresh();
      if (latest.actor !== "PLAYER") throw new Error("Player access moved.");
      setNotes(value(latest.notebook, "notesText"));
      setRevision(Number(latest.notebook?.revision ?? 0));
      setSuspects(notebookSuspects(latest.notebook));
      setDirty(false);
      setSaveState("SAVED");
    } catch {
      setSaveState("FAILED");
    }
  }
  async function mission(id: string, action: "ACCEPT" | "REQUEST_COMPLETION") {
    await run(() =>
      requestJson({
        url: `/api/v1/rooms/${roomId}/missions/${id}`,
        method: "POST",
        input: {
          expectedStateVersion: activePlayer.room.stateVersion,
          idempotencyKey: createIdempotencyKey(),
          action,
        },
        outputSchema: GameplayCommandResultSchema,
      }),
    );
  }
  async function submitTheory() {
    if (
      !window.confirm(
        "Submit this theory to the Game Master? It becomes immutable and gives no correctness feedback.",
      )
    )
      return;
    await run(() =>
      requestJson({
        url: `/api/v1/rooms/${roomId}/theories`,
        method: "POST",
        input: {
          expectedStateVersion: activePlayer.room.stateVersion,
          idempotencyKey: createIdempotencyKey(),
          structuredClaim: {
            suspects: suspects.map((id) => ({
              playerId: id,
              suspectedRole: "MURDERER",
            })),
            evidenceIds,
          },
          submittedExplanation: theoryText,
        },
        outputSchema: GameplayCommandResultSchema.passthrough(),
      }),
    );
    setTheoryText("");
  }
  async function submitFinalCase() {
    if (
      !window.confirm(
        "Submit this final case? It becomes immutable and immediately visible to the Game Master.",
      )
    )
      return;
    const saved = finalDirty ? await saveFinalCase() : true;
    if (!saved) return;
    await run(() =>
      requestJson({
        url: `/api/v1/rooms/${roomId}/accusations`,
        method: "POST",
        input: {
          expectedStateVersion: activePlayer.room.stateVersion,
          idempotencyKey: createIdempotencyKey(),
        },
        outputSchema: EndgameCommandResultSchema,
      }),
    );
    setFinalSubmitted(true);
  }
  const nav: [Surface, string][] = [
    ["dossier", "Dossier"],
    ["mission", "Mission"],
    ["evidence", "Evidence"],
    ["notebook", "Notebook"],
    ["accuse", "Final case"],
    ["reveal", "Reveal"],
  ];
  return (
    <div className="grid gap-5">
      {connection !== "CONNECTED" ? (
        <Alert
          title={connection === "OFFLINE" ? "You are offline" : "Reconnecting"}
          tone="warning"
        >
          Your last authorized view remains visible. Failed commands never
          masquerade as saved and will not duplicate when retried.
        </Alert>
      ) : null}
      {player.room.retentionDeadline ? (
        <Alert title="Room retention deadline" tone="warning">
          This room is scheduled for deletion after{" "}
          {player.room.retentionDeadline}. A successful game action extends an
          incomplete room; simply viewing the page does not.
        </Alert>
      ) : null}
      <Card elevated>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-sm font-bold text-orange-300">
              {player.self.displayName} · {player.self.costume}
            </p>
            <h1 className="mt-1 text-3xl font-black">
              {surface === "waiting"
                ? "Waiting room"
                : nav.find(([id]) => id === surface)?.[1]}
            </h1>
          </div>
          <StatusBadge tone="violet">
            {player.room.status.replaceAll("_", " ")}
          </StatusBadge>
        </div>
        {player.room.status !== "LOBBY" ? (
          <nav
            aria-label="Player game"
            className="mt-5 flex gap-2 overflow-x-auto pb-1"
          >
            {nav.map(([id, label]) => (
              <Link
                key={id}
                href={`/room/${roomId}/${id}`}
                aria-current={surface === id ? "page" : undefined}
                className={`min-h-10 shrink-0 rounded-lg px-3 py-2 text-sm font-bold ${surface === id ? "bg-orange-400 text-black" : "bg-white/5 text-stone-300"}`}
              >
                {label}
              </Link>
            ))}
          </nav>
        ) : null}
      </Card>
      {surface === "waiting" ? (
        <Card>
          <h2 className="text-xl font-black">Your setup is complete</h2>
          <p className="mt-3 leading-7 text-stone-300">
            The Game Master is preparing and locking one mystery. Refreshing or
            changing to an approved replacement device keeps your player
            identity.
          </p>
        </Card>
      ) : null}
      {surface === "dossier" && player.dossier ? (
        <>
          <SecretPanel
            title={
              value(player.dossier, "faction") ||
              "Identity concealed until reveal"
            }
            eyebrow="Your faction"
          >
            <p>{value(player.dossier, "content")}</p>
          </SecretPanel>
          <Card>
            <h2 className="text-xl font-black">Private dossier</h2>
            <pre className="mt-4 whitespace-pre-wrap text-sm leading-6 text-stone-300">
              {JSON.stringify(
                player.dossier.content ?? player.dossier,
                null,
                2,
              )}
            </pre>
          </Card>
        </>
      ) : null}
      {surface === "mission" ? (
        <section>
          <h2 className="text-xl font-black">Current objective</h2>
          <div className="mt-4 grid gap-4">
            {currentMissions.length === 0 ? (
              <Alert title="No active mission">
                Wait for the Game Master to start or advance the round.
              </Alert>
            ) : (
              currentMissions.map((item) => {
                const id = value(item, "id"),
                  status = value(item, "status");
                return (
                  <MissionCard
                    key={id}
                    status={status}
                    title="Private mission"
                    objective={value(item, "objective")}
                    successCriteria={nestedValue(
                      item,
                      "completionRule",
                      "description",
                    )}
                    stakes={value(item, "stakes")}
                    action={
                      status === "ASSIGNED" ? (
                        <Button
                          disabled={busy}
                          onClick={() => mission(id, "ACCEPT")}
                        >
                          Accept mission
                        </Button>
                      ) : status === "ACCEPTED" ? (
                        <Button
                          disabled={busy}
                          onClick={() => mission(id, "REQUEST_COMPLETION")}
                        >
                          Request completion
                        </Button>
                      ) : status === "COMPLETION_REQUESTED" ? (
                        <StatusBadge tone="warning">
                          Waiting for Game Master
                        </StatusBadge>
                      ) : undefined
                    }
                  />
                );
              })
            )}
          </div>
          {(player.releasedConsequences ?? []).length > 0 ? (
            <Card className="mt-4">
              <h2 className="text-xl font-black">Released consequences</h2>
              <div className="mt-4 grid gap-3">
                {(player.releasedConsequences ?? []).map((item) => {
                  const content =
                    typeof item.content === "object" && item.content !== null
                      ? (item.content as Record<string, unknown>)
                      : {};
                  return (
                    <Alert
                      key={value(item, "id")}
                      title={value(content, "title") || "Consequence"}
                      tone="warning"
                    >
                      {value(content, "description")}
                    </Alert>
                  );
                })}
              </div>
            </Card>
          ) : null}
        </section>
      ) : null}
      {surface === "evidence" ? (
        <section>
          <h2 className="text-xl font-black">Released evidence</h2>
          <div className="mt-4 grid gap-4">
            {evidence.length === 0 ? (
              <Alert title="No released evidence">
                Only evidence released to your authorized audience appears here.
              </Alert>
            ) : (
              evidence.map((item) => {
                const content =
                  typeof item.content === "object" && item.content !== null
                    ? (item.content as Record<string, unknown>)
                    : {};
                const isNew = !initiallyVisibleEvidence.has(value(item, "id"));
                return (
                  <EvidenceCard
                    key={value(item, "id")}
                    kind={`${isNew ? "NEW · " : ""}${value(item, "kind")} · Round ${String(item.roundSequence ?? "—")}`}
                    title={value(content, "title") || "Evidence"}
                    audience={`${value(item, "releaseReason").replaceAll("_", " ") || "Released"} · ${value(item, "releasedAt")}`}
                  >
                    {value(content, "description") || JSON.stringify(content)}
                  </EvidenceCard>
                );
              })
            )}
          </div>
          {(player.releasedInterventions ?? []).length > 0 ? (
            <Card className="mt-4">
              <h2 className="text-xl font-black">Game Master prompts</h2>
              <div className="mt-4 grid gap-3">
                {(player.releasedInterventions ?? []).map((item) => {
                  const presentation =
                    typeof item.presentation === "object" &&
                    item.presentation !== null
                      ? (item.presentation as Record<string, unknown>)
                      : {};
                  return (
                    <Alert
                      key={value(item, "id")}
                      title={value(item, "kind").replaceAll("_", " ")}
                      tone="violet"
                    >
                      {value(presentation, "text")}
                    </Alert>
                  );
                })}
              </div>
            </Card>
          ) : null}
        </section>
      ) : null}
      {surface === "notebook" ? (
        <>
          <Card>
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-xl font-black">Detective Notebook</h2>
              <StatusBadge
                tone={
                  saveState === "FAILED"
                    ? "danger"
                    : saveState === "SAVING"
                      ? "warning"
                      : "success"
                }
              >
                {saveState}
              </StatusBadge>
            </div>
            <p className="mt-2 text-sm text-stone-400">
              Owner-only. The Game Master, other players, model prompts, logs,
              and case file cannot read this draft.
            </p>
            <Textarea
              className="mt-4"
              value={notes}
              onChange={(event) => {
                setNotes(event.target.value);
                setDirty(true);
                setSaveState("SAVING");
              }}
              maxLength={10000}
            />
            <div className="mt-4">
              <h3 className="font-black">Suspects</h3>
              <div className="mt-2 flex flex-wrap gap-2">
                {player.lobby
                  .filter(
                    (item) => value(item, "playerId") !== player.self.playerId,
                  )
                  .map((item) => {
                    const id = value(item, "playerId"),
                      active = suspects.includes(id);
                    return (
                      <Button
                        key={id}
                        variant={active ? "primary" : "secondary"}
                        onClick={() => {
                          setSuspects((current) =>
                            active
                              ? current.filter((value) => value !== id)
                              : [...current, id],
                          );
                          setDirty(true);
                          setSaveState("SAVING");
                        }}
                      >
                        {value(item, "displayName")}
                      </Button>
                    );
                  })}
              </div>
            </div>
            {saveState === "FAILED" ? (
              <Alert title="Draft not saved" tone="danger">
                <p>
                  Recover the last server revision, or retry this save. A failed
                  save never appears as successful.
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <Button onClick={() => void saveNotebook()}>
                    Retry save
                  </Button>
                  <Button
                    variant="secondary"
                    onClick={() => void recoverNotebook()}
                  >
                    Recover server copy
                  </Button>
                </div>
              </Alert>
            ) : null}
          </Card>
          <Card>
            <h2 className="text-xl font-black">Submit a theory snapshot</h2>
            <p className="mt-2 text-sm text-stone-400">
              This separate snapshot is visible to you and the Game Master,
              becomes immutable, and never returns whether you are correct.
            </p>
            <Textarea
              className="mt-4"
              value={theoryText}
              onChange={(event) => setTheoryText(event.target.value)}
              maxLength={2000}
            />
            <div className="mt-3 flex flex-wrap gap-2">
              {evidence.map((item) => {
                const id = value(item, "id"),
                  active = evidenceIds.includes(id);
                return (
                  <Button
                    key={id}
                    variant={active ? "primary" : "ghost"}
                    onClick={() =>
                      setEvidenceIds((current) =>
                        active
                          ? current.filter((value) => value !== id)
                          : [...current, id],
                      )
                    }
                  >
                    {value(item, "kind") || "Evidence"}
                  </Button>
                );
              })}
            </div>
            <Button
              className="mt-4"
              disabled={busy || player.room.status !== "IN_PROGRESS"}
              onClick={submitTheory}
            >
              Review and submit theory
            </Button>
            <div className="mt-5 grid gap-2">
              {(player.submittedTheories ?? []).map((item) => (
                <Alert
                  key={value(item, "id")}
                  title="Submitted theory"
                  tone="success"
                >
                  Immutable snapshot recorded. No correctness feedback is
                  provided.
                </Alert>
              ))}
            </div>
          </Card>
        </>
      ) : null}
      {surface === "accuse" ? (
        player.room.status !== "FINAL_ACCUSATIONS" && !finalSubmitted ? (
          <Alert title="Final-case intake is not open">
            The Game Master opens final accusations after the investigation or
            by calling an Early Verdict.
          </Alert>
        ) : (
          <Card elevated>
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-xl font-black">Your final case</h2>
                <p className="mt-2 text-sm text-stone-400">
                  Drafts are owner-only. Submission is permanent and becomes
                  visible to the Game Master immediately.
                </p>
              </div>
              <StatusBadge
                tone={
                  finalSubmitted
                    ? "success"
                    : finalSaveState === "FAILED"
                      ? "danger"
                      : finalSaveState === "SAVING"
                        ? "warning"
                        : "neutral"
                }
              >
                {finalSubmitted ? "SUBMITTED" : finalSaveState}
              </StatusBadge>
            </div>
            <div className="mt-6 grid gap-6">
              <div>
                <h3 className="font-black">Suspected murderer(s)</h3>
                <div className="mt-2 flex flex-wrap gap-2">
                  {player.lobby.map((item) => {
                    const id = value(item, "playerId");
                    const active = finalMurderers.includes(id);
                    return (
                      <Button
                        key={`murderer-${id}`}
                        disabled={finalSubmitted}
                        variant={active ? "danger" : "secondary"}
                        onClick={() => {
                          setFinalMurderers((current) =>
                            active
                              ? current.filter((candidate) => candidate !== id)
                              : [...current, id],
                          );
                          if (!active)
                            setFinalAccomplices((current) =>
                              current.filter((candidate) => candidate !== id),
                            );
                          setFinalDirty(true);
                          setFinalSaveState("SAVING");
                        }}
                      >
                        {value(item, "displayName")}
                      </Button>
                    );
                  })}
                </div>
              </div>
              <div>
                <h3 className="font-black">Suspected accomplice(s)</h3>
                <div className="mt-2 flex flex-wrap gap-2">
                  {player.lobby.map((item) => {
                    const id = value(item, "playerId");
                    const active = finalAccomplices.includes(id);
                    return (
                      <Button
                        key={`accomplice-${id}`}
                        disabled={finalSubmitted}
                        variant={active ? "primary" : "secondary"}
                        onClick={() => {
                          setFinalAccomplices((current) =>
                            active
                              ? current.filter((candidate) => candidate !== id)
                              : [...current, id],
                          );
                          if (!active)
                            setFinalMurderers((current) =>
                              current.filter((candidate) => candidate !== id),
                            );
                          setFinalDirty(true);
                          setFinalSaveState("SAVING");
                        }}
                      >
                        {value(item, "displayName")}
                      </Button>
                    );
                  })}
                </div>
              </div>
              <label className="grid gap-2 text-sm font-bold">
                Motive
                <Textarea
                  disabled={finalSubmitted}
                  value={finalMotive}
                  maxLength={1000}
                  onChange={(event) => {
                    setFinalMotive(event.target.value);
                    setFinalDirty(true);
                    setFinalSaveState("SAVING");
                  }}
                />
              </label>
              <label className="grid gap-2 text-sm font-bold">
                Method
                <Textarea
                  disabled={finalSubmitted}
                  value={finalMethod}
                  maxLength={1000}
                  onChange={(event) => {
                    setFinalMethod(event.target.value);
                    setFinalDirty(true);
                    setFinalSaveState("SAVING");
                  }}
                />
              </label>
              <div>
                <h3 className="font-black">Supporting released evidence</h3>
                <div className="mt-2 flex flex-wrap gap-2">
                  {evidence.map((item) => {
                    const id = value(item, "id");
                    const active = finalEvidence.includes(id);
                    const content =
                      typeof item.content === "object" && item.content !== null
                        ? (item.content as Record<string, unknown>)
                        : {};
                    return (
                      <Button
                        key={`final-evidence-${id}`}
                        disabled={finalSubmitted}
                        variant={active ? "primary" : "ghost"}
                        onClick={() => {
                          setFinalEvidence((current) =>
                            active
                              ? current.filter((candidate) => candidate !== id)
                              : [...current, id],
                          );
                          setFinalDirty(true);
                          setFinalSaveState("SAVING");
                        }}
                      >
                        {value(content, "title") || value(item, "kind")}
                      </Button>
                    );
                  })}
                </div>
              </div>
              <label className="grid gap-2 text-sm font-bold">
                Explanation (optional)
                <Textarea
                  disabled={finalSubmitted}
                  value={finalExplanation}
                  maxLength={4000}
                  onChange={(event) => {
                    setFinalExplanation(event.target.value);
                    setFinalDirty(true);
                    setFinalSaveState("SAVING");
                  }}
                />
              </label>
              {finalSaveState === "FAILED" ? (
                <Alert title="Final-case draft not saved" tone="danger">
                  Your last server copy is still safe. Retry before submitting.
                </Alert>
              ) : null}
              {!finalSubmitted ? (
                <div className="flex flex-wrap gap-2">
                  <Button
                    variant="secondary"
                    disabled={busy || finalSaveState === "SAVING"}
                    onClick={() => void saveFinalCase()}
                  >
                    Save draft
                  </Button>
                  <Button
                    disabled={
                      busy ||
                      finalMurderers.length === 0 ||
                      !finalMotive.trim() ||
                      !finalMethod.trim() ||
                      finalSaveState === "FAILED"
                    }
                    onClick={() => void submitFinalCase()}
                  >
                    Review and submit permanently
                  </Button>
                </div>
              ) : (
                <Alert title="Final case submitted" tone="success">
                  This snapshot is immutable, visible to the Game Master, and
                  safely retained if this device reconnects.
                </Alert>
              )}
            </div>
          </Card>
        )
      ) : null}
      {surface === "reveal" ? (
        reveal ? (
          <div className="grid gap-5">
            <Card elevated>
              <p className="text-sm font-bold text-orange-300">The truth</p>
              <h2 className="mt-1 text-3xl font-black">
                {records(reveal.sections)[0]
                  ? value(records(reveal.sections)[0], "title") ||
                    "The mystery revealed"
                  : "The mystery revealed"}
              </h2>
              <p className="mt-4 text-stone-300">
                <strong>Motive:</strong> {value(canonicalSolution, "motive")}
              </p>
              <p className="mt-2 text-stone-300">
                <strong>Method:</strong> {value(canonicalSolution, "method")}
              </p>
            </Card>
            {records(reveal.sections).map((section) => {
              const content =
                typeof section.content === "object" && section.content !== null
                  ? (section.content as Record<string, unknown>)
                  : {};
              return (
                <Card key={value(section, "id")}>
                  <StatusBadge tone="violet">
                    {value(section, "kind")}
                  </StatusBadge>
                  <h3 className="mt-3 text-xl font-black">
                    {value(content, "title")}
                  </h3>
                  <p className="mt-2 leading-7 text-stone-300">
                    {value(content, "body") || JSON.stringify(content)}
                  </p>
                </Card>
              );
            })}
            <Card>
              <h2 className="text-xl font-black">Results</h2>
              <div className="mt-4 grid gap-3">
                {records(reveal.playerScores).map((score) => (
                  <Alert
                    key={value(score, "playerId")}
                    title={`${value(score, "displayName")} · ${String(score.totalPoints ?? 0)} points`}
                    tone={
                      value(score, "playerId") === player.self.playerId
                        ? "orange"
                        : "neutral"
                    }
                  >
                    Rank {String(score.rank ?? "—")}.{" "}
                    {value(score, "explanation")}
                  </Alert>
                ))}
              </div>
            </Card>
            {records(reveal.awards).length > 0 ? (
              <Card>
                <h2 className="text-xl font-black">Awards</h2>
                <div className="mt-4 grid gap-3">
                  {records(reveal.awards).map((award) => (
                    <Alert
                      key={value(award, "code")}
                      title={`${value(award, "title")} · ${value(award, "displayName")}`}
                      tone="success"
                    >
                      {value(award, "description")}
                    </Alert>
                  ))}
                </div>
              </Card>
            ) : null}
          </div>
        ) : (
          <Alert title="Shared reveal is locked">
            The Game Master has not published the canonical truth and results.
          </Alert>
        )
      ) : null}
      {actionError || error ? (
        <Alert title="Update did not complete" tone="danger">
          {actionError ?? error}
        </Alert>
      ) : null}
    </div>
  );
}
