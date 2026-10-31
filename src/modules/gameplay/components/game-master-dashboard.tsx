"use client";

import { useState } from "react";

import {
  Alert,
  Button,
  Card,
  EvidenceCard,
  MissionCard,
  StatusBadge,
  Timeline,
} from "@/components/ui";
import {
  GameplayCommandResultSchema,
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
  if (!view || view.actor !== "GAME_MASTER" || !view.story) return null;
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
  const metadata = () => ({
    expectedStateVersion: view.room.stateVersion,
    idempotencyKey: createIdempotencyKey(),
  });

  return (
    <div className="mt-8 grid gap-6">
      {connection !== "CONNECTED" ? (
        <Alert title="Updates delayed" tone="warning">
          Presence and updates are best effort. Commands remain disabled only
          while an action is in flight; stale versions safely refetch.
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
          ) : null}
        </div>
      </Card>
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
