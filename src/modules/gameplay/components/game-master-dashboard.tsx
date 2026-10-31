"use client";

import { useState } from "react";

import {
  Alert,
  Button,
  Card,
  EvidenceCard,
  Input,
  MissionCard,
  StatusBadge,
  Timeline,
} from "@/components/ui";
import {
  GameplayCommandResultSchema,
  InterventionPreviewResultSchema,
  StoryPackageSchema,
  type GameMasterViewSchema,
} from "@/contracts";
import { createIdempotencyKey, requestJson } from "@/lib/api/request";
import {
  useActorProjection,
  type ActorView,
} from "@/modules/gameplay/use-actor-projection";
import type { z } from "zod";

function records(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.filter(
        (item): item is Record<string, unknown> =>
          typeof item === "object" && item !== null,
      )
    : [];
}

function stringValue(
  record: Record<string, unknown>,
  ...keys: string[]
): string {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string") return value;
  }
  return "";
}

export function GameMasterDashboard({
  roomId,
  initialView,
}: {
  roomId: string;
  initialView?: z.infer<typeof GameMasterViewSchema>;
}) {
  const { view, error, connection, refresh } = useActorProjection(
    roomId,
    initialView as ActorView | undefined,
  );
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string>();
  const [interventionPreview, setInterventionPreview] = useState<
    ReturnType<typeof InterventionPreviewResultSchema.parse> | undefined
  >();
  const [caseFileQuery, setCaseFileQuery] = useState("");
  if (!view || view.actor !== "GAME_MASTER" || !view.story) return null;
  const activeView = view;
  const story = StoryPackageSchema.safeParse(view.story.package);
  if (!story.success)
    return (
      <Alert title="Locked story unavailable" tone="danger">
        The canonical story projection did not match this application version.
      </Alert>
    );
  const runtimeMissions = records(view.runtime?.missions);
  const evidenceReleases = records(view.runtime?.evidenceReleases);
  const consequenceStates = records(view.runtime?.consequences);
  const interventionRequests = records(view.runtime?.interventionRequests);
  const interventionPreviews = records(view.runtime?.interventionPreviews);
  const interventionReleases = records(view.runtime?.interventionReleases);
  const submittedAccusations = records(view.submittedState?.finalAccusations);
  const scoringSnapshot =
    typeof view.results?.scoringSnapshot === "object" &&
    view.results.scoringSnapshot !== null
      ? (view.results.scoringSnapshot as Record<string, unknown>)
      : undefined;
  const caseFile =
    typeof view.results?.caseFile === "object" && view.results.caseFile !== null
      ? (view.results.caseFile as Record<string, unknown>)
      : undefined;
  const missingAccusationPlayers = view.players.filter(
    (player) =>
      !submittedAccusations.some(
        (accusation) =>
          stringValue(accusation, "player_id", "playerId") ===
          stringValue(player, "id"),
      ),
  );
  const missionStatus = new Map(
    runtimeMissions.map((item) => [
      String(item.mission_spec_id),
      String(item.status),
    ]),
  );
  const players = new Map(
    story.data.characters.map((character) => [
      character.playerId,
      character.displayName,
    ]),
  );
  const releasedEvidenceIds = new Set(
    evidenceReleases.map((item) =>
      stringValue(item, "evidence_id", "evidenceId"),
    ),
  );
  const roundSequence = new Map(
    story.data.rounds.map((round) => [round.id, round.sequence]),
  );
  const currentRoundSequence = view.room.currentRoundId
    ? (roundSequence.get(view.room.currentRoundId) ?? 0)
    : 0;
  const currentRoundReleasedInterventions = interventionReleases.filter(
    (release) => {
      const request = interventionRequests.find(
        (item) =>
          stringValue(item, "id") ===
          stringValue(release, "request_id", "requestId"),
      );
      return (
        stringValue(request ?? {}, "round_id", "roundId") ===
        view.room.currentRoundId
      );
    },
  ).length;
  const interventionCap = [30, 45].includes(
    story.data.durationProfile.durationMinutes,
  )
    ? 1
    : 2;
  const pendingRequest = [...interventionRequests]
    .reverse()
    .find((item) =>
      ["REQUESTED", "PREVIEW_READY"].includes(stringValue(item, "status")),
    );
  const persistedPreview = pendingRequest
    ? interventionPreviews.find(
        (item) =>
          stringValue(item, "request_id", "requestId") ===
          stringValue(pendingRequest, "id"),
      )
    : undefined;

  async function command(path: string, input: object) {
    setBusy(true);
    setActionError(undefined);
    try {
      await requestJson({
        url: `/api/v1/rooms/${roomId}/${path}`,
        method: "POST",
        input,
        outputSchema: GameplayCommandResultSchema,
      });
      await refresh();
    } catch (caught) {
      setActionError(
        caught instanceof Error ? caught.message : "Command failed.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function requestIntervention() {
    setBusy(true);
    setActionError(undefined);
    try {
      const result = await requestJson({
        url: `/api/v1/rooms/${roomId}/interventions`,
        method: "POST",
        input: metadata(),
        outputSchema: InterventionPreviewResultSchema,
      });
      setInterventionPreview(result);
      await refresh();
    } catch (caught) {
      setActionError(
        caught instanceof Error
          ? caught.message
          : "An intervention could not be prepared.",
      );
      await refresh().catch(() => undefined);
    } finally {
      setBusy(false);
    }
  }
  async function closeAccusations() {
    const missingNames = missingAccusationPlayers.map((player) =>
      stringValue(player, "displayName"),
    );
    const submittedCount = submittedAccusations.length;
    if (
      !window.confirm(
        missingNames.length > 0
          ? `Close final-case intake? Missing: ${missingNames.join(", ")}. Each receives zero points and no faction vote.`
          : "Every player submitted. Close intake and calculate deterministic results?",
      )
    )
      return;
    if (
      submittedCount === 0 &&
      !window.confirm(
        "No player submitted a final case. Confirm again: all players receive zero points and the murderer faction wins.",
      )
    )
      return;
    await command("accusations/close", {
      ...metadata(),
      confirmedMissingPlayerIds: missingAccusationPlayers.map((player) =>
        stringValue(player, "id"),
      ),
      confirmZeroSubmissions: submittedCount === 0,
    });
  }
  function metadata() {
    return {
      expectedStateVersion: activeView.room.stateVersion,
      idempotencyKey: createIdempotencyKey(),
    };
  }

  return (
    <div className="mt-8 grid gap-6">
      {connection !== "CONNECTED" ? (
        <Alert title="Updates delayed" tone="warning">
          Presence and updates are best effort. Commands remain disabled only
          while an action is in flight; stale versions safely refetch.
        </Alert>
      ) : null}
      {view.room.retentionDeadline ? (
        <Alert title="Room retention deadline" tone="warning">
          This room is scheduled for deletion after{" "}
          <time className="break-all">{view.room.retentionDeadline}</time>.
          Successful game actions extend incomplete-room inactivity deadlines;
          page views and presence heartbeats do not.
        </Alert>
      ) : null}
      <Card elevated>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-sm font-bold text-violet-200">
              Full Game Master view
            </p>
            <h2 className="mt-1 text-3xl font-black">{story.data.title}</h2>
          </div>
          <StatusBadge tone="success">
            {view.room.status.replaceAll("_", " ")}
          </StatusBadge>
        </div>
        <p className="mt-4 leading-7 text-stone-300">{story.data.premise}</p>
        <div className="mt-5 flex flex-wrap gap-2">
          {view.room.status === "READY_TO_START" ? (
            <Button
              disabled={busy}
              onClick={() => command("commands/start", metadata())}
            >
              Start game
            </Button>
          ) : null}
          {view.room.status === "IN_PROGRESS" ? (
            <>
              <Button
                disabled={busy}
                onClick={() => {
                  if (
                    window.confirm(
                      "Advance the round? Unfinished missions will be classified and waived.",
                    )
                  )
                    void command("commands/advance", metadata());
                }}
              >
                Advance round
              </Button>
              <Button
                disabled={busy}
                variant="danger"
                onClick={() => {
                  if (
                    window.confirm(
                      "Call Early Verdict? Investigation ends now, unfinished missions are waived, and all players move to final cases. No correctness signal is sent.",
                    )
                  )
                    void command("early-verdict", metadata());
                }}
              >
                Call Early Verdict
              </Button>
            </>
          ) : null}
        </div>
      </Card>
      {view.room.status === "FINAL_ACCUSATIONS" || scoringSnapshot ? (
        <Card elevated>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-xl font-black">Final-case intake</h2>
              <p className="mt-2 text-sm text-stone-400">
                {submittedAccusations.length}/{view.players.length} submitted.
                Drafts remain invisible; submitted snapshots are shown below.
              </p>
            </div>
            {scoringSnapshot ? (
              <StatusBadge tone="success">INPUTS FROZEN · SCORED</StatusBadge>
            ) : (
              <StatusBadge tone="warning">INTAKE OPEN</StatusBadge>
            )}
          </div>
          <div className="mt-4 grid gap-3">
            {view.players.map((player) => {
              const playerId = stringValue(player, "id");
              const accusation = submittedAccusations.find(
                (item) =>
                  stringValue(item, "player_id", "playerId") === playerId,
              );
              return (
                <Alert
                  key={playerId}
                  title={stringValue(player, "displayName")}
                  tone={accusation ? "success" : "neutral"}
                >
                  {accusation ? (
                    <pre className="max-h-52 overflow-auto whitespace-pre-wrap text-xs">
                      {JSON.stringify(
                        accusation.structured_case_json ?? accusation.case,
                        null,
                        2,
                      )}
                    </pre>
                  ) : (
                    "Waiting for submission. No draft content is visible."
                  )}
                </Alert>
              );
            })}
          </div>
          <div className="mt-5 flex flex-wrap gap-2">
            {!scoringSnapshot && view.room.status === "FINAL_ACCUSATIONS" ? (
              <Button disabled={busy} onClick={() => void closeAccusations()}>
                Close intake and score
              </Button>
            ) : null}
            {scoringSnapshot && view.room.status === "FINAL_ACCUSATIONS" ? (
              <Button
                disabled={busy}
                onClick={() => void command("reveal/publish", metadata())}
              >
                Publish shared reveal
              </Button>
            ) : null}
            {view.room.status === "REVEAL" ? (
              <Button
                disabled={busy}
                onClick={() => void command("completion", metadata())}
              >
                Finalize case file and complete
              </Button>
            ) : null}
          </div>
        </Card>
      ) : null}
      {caseFile ? (
        <Card elevated>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-xl font-black">Complete case file</h2>
              <p className="mt-2 text-sm text-stone-400">
                Immutable postgame record. Scheduled deletion:{" "}
                {String(view.room.expiresAt ?? "—")}.
              </p>
            </div>
            <StatusBadge tone="success">COMPLETED</StatusBadge>
          </div>
          <Input
            className="mt-5"
            aria-label="Search case file"
            placeholder="Search the case file"
            value={caseFileQuery}
            onChange={(event) => setCaseFileQuery(event.target.value)}
          />
          {JSON.stringify(caseFile.content ?? {})
            .toLocaleLowerCase()
            .includes(caseFileQuery.toLocaleLowerCase()) ? (
            <pre className="mt-4 max-h-[40rem] overflow-auto whitespace-pre-wrap text-xs text-stone-300">
              {JSON.stringify(caseFile.content ?? {}, null, 2)}
            </pre>
          ) : (
            <Alert className="mt-4" title="No case-file match">
              Try a player, clue, mission, or event name.
            </Alert>
          )}
        </Card>
      ) : null}
      <Alert title="Canonical solution — Game Master only" tone="violet">
        <p>
          <strong>Murderer(s):</strong>{" "}
          {story.data.solution.murdererPlayerIds
            .map((id) => players.get(id))
            .join(", ")}
        </p>
        <p>
          <strong>Motive:</strong> {story.data.solution.motive}
        </p>
        <p>
          <strong>Method:</strong> {story.data.solution.method}
        </p>
      </Alert>
      <Card>
        <h2 className="text-xl font-black">Pacing</h2>
        <div className="mt-4">
          <Timeline
            items={story.data.rounds.map((round) => ({
              id: round.id,
              title: `Round ${round.sequence}: ${round.title}`,
              detail: `${Math.round(round.targetDurationSeconds / 60)} minute target`,
              current: round.id === view.room.currentRoundId,
            }))}
          />
        </div>
      </Card>
      <Card elevated>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-xl font-black">Discussion intervention</h2>
            <p className="mt-2 text-sm text-stone-400">
              {currentRoundReleasedInterventions}/{interventionCap} released in
              this round. Suggestions select canonical content only and never
              reach players before your approval.
            </p>
          </div>
          <Button
            disabled={
              busy ||
              view.room.status !== "IN_PROGRESS" ||
              Boolean(pendingRequest) ||
              currentRoundReleasedInterventions >= interventionCap
            }
            onClick={() => void requestIntervention()}
          >
            {busy ? "Preparing…" : "Discussion stalled"}
          </Button>
        </div>
        {persistedPreview ? (
          <div className="mt-5 rounded-xl border border-violet-300/20 bg-violet-300/5 p-4">
            <div className="flex flex-wrap items-center gap-2">
              <StatusBadge tone="violet">
                {stringValue(
                  persistedPreview,
                  "selection_source",
                  "selectionSource",
                ).replaceAll("_", " ")}
              </StatusBadge>
              <StatusBadge tone="warning">
                {stringValue(
                  persistedPreview,
                  "candidate_kind",
                  "candidateKind",
                ).replaceAll("_", " ")}
              </StatusBadge>
            </div>
            <h3 className="mt-4 text-lg font-black">Complete preview</h3>
            <pre className="mt-2 max-h-72 overflow-auto whitespace-pre-wrap text-sm text-stone-300">
              {JSON.stringify(
                persistedPreview.preview_json ??
                  persistedPreview.preview ??
                  interventionPreview?.preview,
                null,
                2,
              )}
            </pre>
            <p className="mt-3 text-xs text-stone-400">
              Audience: {JSON.stringify(persistedPreview.audience_json)} ·
              Source spec:{" "}
              {stringValue(persistedPreview, "intervention_spec_id") ||
                "canonical object"}
            </p>
            <div className="mt-4 flex flex-wrap gap-2">
              <Button
                disabled={busy}
                onClick={() =>
                  command(
                    `interventions/${stringValue(pendingRequest ?? {}, "id")}`,
                    {
                      ...metadata(),
                      decision: "APPROVE",
                    },
                  )
                }
              >
                Approve and release
              </Button>
              <Button
                disabled={busy}
                variant="secondary"
                onClick={() =>
                  command(
                    `interventions/${stringValue(pendingRequest ?? {}, "id")}`,
                    {
                      ...metadata(),
                      decision: "REJECT",
                    },
                  )
                }
              >
                Reject
              </Button>
            </div>
          </div>
        ) : pendingRequest ? (
          <Alert title="Preparing canonical preview" tone="warning">
            The bounded model selection is running. A deterministic prepared
            fallback is used by 12 seconds.
          </Alert>
        ) : null}
      </Card>
      <Card>
        <h2 className="text-xl font-black">Victim and canonical timeline</h2>
        <p className="mt-3 text-stone-300">
          <strong>{story.data.victim.name}</strong> —{" "}
          {story.data.victim.biography}
        </p>
        <div className="mt-5">
          <Timeline
            items={story.data.timeline.map((item) => ({
              id: item.id,
              title: item.timeLabel,
              detail: item.description,
            }))}
          />
        </div>
      </Card>
      <section>
        <h2 className="text-2xl font-black">All dossiers</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          {story.data.dossiers.map((dossier) => (
            <Card key={dossier.id}>
              <StatusBadge
                tone={
                  dossier.faction === "MURDERER"
                    ? "danger"
                    : dossier.faction === "ACCOMPLICE"
                      ? "warning"
                      : "success"
                }
              >
                {dossier.faction}
              </StatusBadge>
              <h3 className="mt-3 text-lg font-black">
                {players.get(dossier.playerId)}
              </h3>
              <p className="mt-2 text-sm text-stone-300">
                {dossier.characterGoal}
              </p>
              <ul className="mt-3 list-disc pl-5 text-sm text-stone-400">
                {dossier.privateSecrets.map((secret) => (
                  <li key={secret}>{secret}</li>
                ))}
              </ul>
            </Card>
          ))}
        </div>
      </section>
      <section>
        <h2 className="text-2xl font-black">All missions</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          {story.data.missions.map((mission) => {
            const status = missionStatus.get(mission.id) ?? "ASSIGNED";
            return (
              <MissionCard
                key={mission.id}
                status={status}
                title={`${players.get(mission.assignedPlayerId)} · ${story.data.rounds.find((r) => r.id === mission.roundId)?.title ?? "Round"}`}
                objective={mission.objective}
                successCriteria={mission.completionRule}
                stakes={mission.stakes}
                action={
                  status === "COMPLETION_REQUESTED" ? (
                    <div className="flex flex-wrap gap-2">
                      <Button
                        disabled={busy}
                        onClick={() =>
                          command(`missions/${mission.id}`, {
                            ...metadata(),
                            action: "APPROVE",
                          })
                        }
                      >
                        Approve
                      </Button>
                      <Button
                        disabled={busy}
                        variant="secondary"
                        onClick={() =>
                          command(`missions/${mission.id}`, {
                            ...metadata(),
                            action: "REJECT",
                          })
                        }
                      >
                        Reject
                      </Button>
                      <Button
                        disabled={busy}
                        variant="ghost"
                        onClick={() =>
                          command(`missions/${mission.id}`, {
                            ...metadata(),
                            action: "EXTEND",
                            extensionMinutes: 5,
                          })
                        }
                      >
                        Extend 5 min
                      </Button>
                    </div>
                  ) : ["ASSIGNED", "ACCEPTED"].includes(status) ? (
                    <div className="flex flex-wrap gap-2">
                      <Button
                        disabled={busy}
                        variant="danger"
                        onClick={() =>
                          command(`missions/${mission.id}`, {
                            ...metadata(),
                            action: "FAIL",
                          })
                        }
                      >
                        Mark failed
                      </Button>
                      <Button
                        disabled={busy}
                        variant="ghost"
                        onClick={() =>
                          command(`missions/${mission.id}`, {
                            ...metadata(),
                            action: "WAIVE",
                          })
                        }
                      >
                        Waive
                      </Button>
                      {status === "ACCEPTED" ? (
                        <Button
                          disabled={busy}
                          variant="secondary"
                          onClick={() =>
                            command(`missions/${mission.id}`, {
                              ...metadata(),
                              action: "EXTEND",
                              extensionMinutes: 5,
                            })
                          }
                        >
                          Extend 5 min
                        </Button>
                      ) : null}
                    </div>
                  ) : undefined
                }
              />
            );
          })}
        </div>
      </section>
      <section>
        <h2 className="text-2xl font-black">All evidence</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          {story.data.evidence.map((item) => {
            const released = releasedEvidenceIds.has(item.id);
            const manual = item.releaseRule.kind === "GAME_MASTER_MANUAL";
            const manualEarliestSequence =
              item.releaseRule.kind === "GAME_MASTER_MANUAL"
                ? (roundSequence.get(item.releaseRule.earliestRoundId) ?? 0)
                : null;
            const manualEligible =
              manual &&
              manualEarliestSequence !== null &&
              currentRoundSequence >= manualEarliestSequence;
            return (
              <EvidenceCard
                key={item.id}
                kind={`${item.kind} · ${released ? "RELEASED" : "UNRELEASED"}`}
                title={item.title}
                audience={item.audience.kind}
              >
                <p>{item.description}</p>
                <p className="mt-2 text-xs text-stone-400">
                  Rule: {item.releaseRule.kind}
                </p>
                {!released && manual ? (
                  <Button
                    className="mt-3"
                    disabled={busy || !manualEligible}
                    onClick={() =>
                      command(`releases/${item.id}`, {
                        ...metadata(),
                        objectKind: "EVIDENCE",
                        decision: "RELEASE",
                      })
                    }
                  >
                    {manualEligible ? "Release evidence" : "Not eligible yet"}
                  </Button>
                ) : null}
              </EvidenceCard>
            );
          })}
        </div>
      </section>
      <section>
        <h2 className="text-2xl font-black">Failure consequences</h2>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          {story.data.consequences.map((item) => {
            const state = consequenceStates.find(
              (entry) =>
                stringValue(
                  entry,
                  "consequence_spec_id",
                  "consequenceSpecId",
                ) === item.id,
            );
            const status = state
              ? stringValue(state, "status")
              : "NOT_TRIGGERED";
            return (
              <Card key={item.id}>
                <StatusBadge tone={status === "PENDING" ? "warning" : "violet"}>
                  {status}
                </StatusBadge>
                <h3 className="mt-3 text-lg font-black">{item.title}</h3>
                <p className="mt-2 text-sm text-stone-300">
                  {item.description}
                </p>
                {status === "PENDING" ? (
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button
                      disabled={busy}
                      onClick={() =>
                        command(`releases/${item.id}`, {
                          ...metadata(),
                          objectKind: "CONSEQUENCE",
                          decision: "RELEASE",
                        })
                      }
                    >
                      Release consequence
                    </Button>
                    <Button
                      disabled={busy}
                      variant="ghost"
                      onClick={() =>
                        command(`releases/${item.id}`, {
                          ...metadata(),
                          objectKind: "CONSEQUENCE",
                          decision: "WAIVE",
                        })
                      }
                    >
                      Waive
                    </Button>
                  </div>
                ) : null}
              </Card>
            );
          })}
        </div>
      </section>
      <Card>
        <h2 className="text-xl font-black">Relationships and private truth</h2>
        <pre className="mt-4 max-h-80 overflow-auto whitespace-pre-wrap text-xs text-stone-400">
          {JSON.stringify(story.data.relationships, null, 2)}
        </pre>
      </Card>
      <Card>
        <h2 className="text-xl font-black">Prepared interventions</h2>
        <pre className="mt-4 max-h-80 overflow-auto whitespace-pre-wrap text-xs text-stone-400">
          {JSON.stringify(story.data.interventions, null, 2)}
        </pre>
      </Card>
      <Card>
        <h2 className="text-xl font-black">Accomplice revelations</h2>
        <pre className="mt-4 max-h-80 overflow-auto whitespace-pre-wrap text-xs text-stone-400">
          {JSON.stringify(story.data.accompliceRevelations, null, 2)}
        </pre>
      </Card>
      <Card>
        <h2 className="text-xl font-black">
          Prepared ending and case narrative
        </h2>
        <p className="mt-3 leading-7 text-stone-300">
          {story.data.fullCaseNarrative}
        </p>
        <pre className="mt-4 max-h-80 overflow-auto whitespace-pre-wrap text-xs text-stone-400">
          {JSON.stringify(story.data.finalReveal, null, 2)}
        </pre>
      </Card>
      <Card>
        <h2 className="text-xl font-black">Submitted gameplay state</h2>
        <pre className="mt-4 max-h-80 overflow-auto whitespace-pre-wrap text-xs text-stone-400">
          {JSON.stringify(view.submittedState ?? {}, null, 2)}
        </pre>
      </Card>
      {actionError || error ? (
        <Alert title="Dashboard update failed" tone="danger">
          {actionError ?? error}
        </Alert>
      ) : null}
    </div>
  );
}
