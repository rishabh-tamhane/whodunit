# Halloween Murder Mystery — Master Game Plan

**Product:** Mobile-first, multiplayer murder mystery party game

**Format:** In-person social deduction, supported by a mobile website

**Game progression:** Host-controlled

**Story generation:** Bounded generation and repair may occur before lock; exactly one validated canonical story is then atomically and permanently locked for the room

## 1. Core Concept

A personalized murder mystery for 4–12 players, run by a separate non-playing host, where players use their phones to receive roles, secrets, clues, and missions while solving the crime through real-life conversations.

The murder victim is always a fictional non-player character. No participating player is assigned as the victim or removed from play.

The storyline is generated using:
- Player names and Halloween costumes entered by the host.
- Optional background details entered by the host.
- Private descriptions of each player submitted by their friends.
- The host's selected duration and role configuration.

**Core principle:** Players have freedom to lie, investigate, accuse, and improvise, but every round gives them clear, achievable things to do.

The website drives the story forward without replacing in-person interaction.

### MVP Audience and Cultural Safety

The MVP is designed for private friend groups. The interface is English-first, but names and player-provided text must be Unicode-safe. Story generation must handle Indian names and contexts naturally without stereotyping, anglicizing names, or inferring a person's culture from their name.

Hosts and players must be warned not to enter real secrets, medical or financial information, caste or religion claims, allegations, or other sensitive personal information. Generated fiction must not use protected or sensitive real-world traits as motives for the crime.

Each player must acknowledge the fictional-use and sensitive-input guidance before submitting descriptions, and the host must acknowledge the host guidance and confirm room consent before generation begins.

---

## 2. Before the Game — Host Setup

The host creates a room and configures the game.

### Player Details
For each player, the host enters:
- Name
- Halloween costume
- Optional additional information

The host is a dedicated non-playing Game Master. The host is outside the player count, never receives or claims a player slot, and is never assigned a faction, personal dossier, mission, clue inventory, notebook, theory, accusation, or player score.

### Game Configuration

| Setting | Options |
|---|---|
| Player count | 4–12 players, excluding the host |
| Duration | 30, 45, 60, 90, 120 minutes |
| Murderers | Host chooses number |
| Accomplices | Host chooses number |
| Innocents | Host chooses number |
| Murderer awareness | Murderers know / don't know |
| Progression | Host-controlled |

The host is separate from and does not count toward the 4–12-player limit.

The number of murderers, accomplices, and innocents must equal the total player count; the host is never assigned a faction. Every game must have at least one murderer and one innocent. The website recommends balanced distributions based on party size.

The selected duration determines the planned number of rounds, missions, and evidence events. It is a target, not a forced countdown.

### Player Onboarding

The host's player list creates the room's player slots. Each slot has a unique internal player ID plus its display name, costume, and optional information. Display names are never used as database identifiers, so players with the same name can still be represented as separate slots and distinguished by costume.

Every player joins through a QR code or room code. The host instead uses the separate host session and recovery credential created with the room. A room code allows the website to locate the room and display safe lobby information, but it does not grant access to any role, secret, clue, mission, or theory.

Before requesting a player slot, the join screen must state that the host is a dedicated non-playing Game Master who can see all generated roles, secrets, missions, evidence, submitted theories, submitted final accusations, and the canonical solution. It must also distinguish owner-only notebook drafts, unsubmitted prose, and final-accusation drafts from gameplay state submitted to the Game Master.

Joining uses **player claiming with host approval**:

1. The website creates or restores a persistent guest session on the joining device.
2. The player enters the room code and sees all host-created player slots, showing only safe lobby data: names, costumes, and whether each slot is available or already occupied.
3. The player selects their own slot and requests either an initial claim for an available slot or a reconnect for an occupied slot.
4. The website creates a pending claim linking that guest session to the selected internal player ID and claim type.
5. The host sees the requested name and costume and approves or rejects the claim.
6. Approval binds the guest session to that player ID until the host revokes it or approves a replacement device.
7. Only an approved player can submit descriptions or access that player's player-facing private view. Separately, the authenticated Game Master can access all generated game information and submitted gameplay state after story lock under the host policy below.

A player slot can have only one active guest session. Other players cannot complete an initial claim for an occupied slot. A new device may submit a reconnect request, but it receives no private access unless the host approves replacement of the active device. If multiple devices request the same available slot, host approval of one request must cause conflicting requests to fail or be rejected.

Showing that a slot is occupied does not expose the occupying session, the player's role, or any other private data.

The approved mapping is:

**Guest session → room membership → internal player ID → displayed name and costume → generated dossier, role, clues, and missions.**

The mapping persists across refreshes and temporary disconnections. A returning player should resume their existing character and current game state without selecting their name again.

If a player changes devices or loses their guest session, they can request to reconnect as their existing player. The host must approve the replacement. Approval revokes the previous device's room membership and binds the new guest session to the same internal player ID without losing the player's clues, missions, notes, theories, or progress.

Player identity and story role are separate:

- The claimed player ID answers, “Which participant and phone is this?”
- The generated role answers, “What fictional character, faction, secrets, and objectives does this participant receive?”
- Murderer, accomplice, and innocent assignments happen only when the mystery is generated and locked.
- Claiming a name must not reveal or predetermine a faction.

Host authority is never a player identity. A current or former host session cannot request, approve for itself, hold, or reconnect to a player slot in that room. This invariant applies throughout the room lifecycle and survives host recovery; recovery transfers only Game Master authority.

After approval, each player privately describes the other players.

Descriptions are stored only for story generation. Their raw text and authorship are never shown to the Game Master or other players and are never copied into generated output.

Every ordered author/other-player prompt must be answered with 1–500 characters or an explicit “Prefer not to answer” decline. A decline stores no reason. Unanswered prompts remain pending and block generation, so a 4-player room requires 12 terminal responses and a 12-player room requires 132. The Game Master sees completion counts only.

Once every player has one active approved claim, all acknowledgements and room consent are complete, and every description prompt is submitted or declined, the host can generate the mystery.

---

## 3. Three Player Factions

### Murderers
The people responsible for the crime.

Their goals are to conceal their involvement, defend their alibis, mislead investigators, and avoid identification.

Depending on the game settings, murderers may know their identity immediately or discover the truth only during the final reveal.

### Accomplices
Secret allies whose objective is to protect the murderers.

They begin without knowing the murderers' identities. At a predetermined point during the game, they receive a private revelation identifying the murderers.

After that, their missions involve questioning damaging evidence, presenting alternative theories, and redirecting suspicion.

When murderers are unaware of their own identities, accomplices can possess knowledge the murderers themselves lack.

### Innocents
Investigators trying to solve the crime.

They receive their own backgrounds, secrets, motives, clues, and missions. Innocent characters may appear suspicious, but their secrets must remain consistent with the true storyline.

**No player is eliminated from the game**, regardless of accusations or revealed secrets.

---

## 4. AI Story Generation

The AI must generate an entire playable mystery, not just a story synopsis.

Generation follows this order:

1. Establish the crime, responsible characters, motives, and method.
2. Develop character relationships and backstories using the submitted descriptions and costumes.
3. Construct a consistent timeline and alibis.
4. Distribute public and private evidence.
5. Create achievable individual missions for every round.
6. Prepare mission success/failure consequences.
7. Prepare an eligible catalog of hints, clues, emergency events, and fallback interventions for safe context-aware use during play.
8. Define delayed accomplice revelations and faction objectives.
9. Generate the complete final narrative.
10. Validate that the mystery is coherent, fair, and solvable.

### One Room, One Story

Exactly one validated canonical story may be stored and atomically locked for a room.

All players share the same public events, timeline, crime, and solution. Players receive different private information.

Success, failure, and host intervention can change which prepared information becomes visible, but never change what actually happened.

Refreshing, reconnecting, or joining an existing room does not regenerate the mystery.

Before the first successful lock, failed validation may trigger bounded automatic repair or retry. Failed, invalid, or partial output never becomes playable. After a successful lock, the room can never regenerate or replace its story. A host who wants a different mystery must create a new room.

---

## 5. Gameplay — Example 60-Minute Session

| Round | Target time | Gameplay |
|---|---|---|
| 1. Introductions | 10 min | Players learn their characters, secrets, and initial objectives |
| 2. The Murder | 10 min | Murder announced, first evidence released, interrogations begin |
| 3. Investigation | 15 min | New missions, evidence, consequences, delayed accomplice revelation |
| 4. Plot Twist | 15 min | Major revelations, final interrogations, new theories |
| 5. Accusations | 5 min | Players submit their complete case theories |
| 6. Final Reveal | 5 min | Murderers, accomplices, motives, and outcomes revealed |

The host manually advances each round. The website synchronizes the current round across everyone's phones.

Each investigation round contains:
- A public narrative event.
- At least one individual objective per player.
- New information or a reason for discussion.
- Possible success/failure consequences.
- Optional interventions if the group becomes stuck.

---

## 6. Individual Missions

Players receive actionable objectives with clear success criteria.

**Every mission must be achievable through the player's own actions.**

For example, "Ask Maya about her argument with Victor" is valid. "Convince Maya to confess" is not, because Maya may refuse.

Players can request mission completion, and the host can confirm it.

### Failure Consequences

If a mission is not completed before its round deadline, the host can mark it failed, waive it, or extend it. A failed mission can make a pre-generated consequence eligible for release.

Examples:
- Reveal a fictional secret about the player.
- Release evidence contradicting an alibi.
- Expose a previously hidden relationship.
- Create a new reason for another player to investigate.

Consequences should escalate in severity as the game progresses.

Players must understand the stakes before accepting their missions. The host can extend a deadline or waive a consequence if needed.

Only fictional in-game secrets can be exposed, never real descriptions submitted by friends.

---

## 7. Host Dashboard — Game Master

The host sees:
- Current round and story progress.
- Pending initial and reconnect player claims.
- Which player slots are unclaimed, pending, active and connected, or active but disconnected.
- Mission confirmation criteria and status.
- Pending and triggered consequences.
- Previously released public events.
- Controls to advance rounds or call an Early Verdict.

The host has sole control over game management: approving or rejecting claims, revoking or replacing player bindings, starting generation and the game, deciding mission outcomes, releasing eligible consequences and evidence, approving interventions, advancing rounds, calling an Early Verdict, closing final submissions, and publishing the reveal. Full control never permits changing the canonical mystery after story lock.

After story lock, the host is the full Game Master and the dashboard must show the complete generated mystery: the canonical solution, every faction and dossier, all generated secrets and missions, released and unreleased evidence, intervention content, submitted gameplay theories and submitted final accusations, and the prepared ending. No generated game information or submitted gameplay state is hidden from the host.

Game Master visibility covers generated game content and submitted gameplay state. Raw friend descriptions, description authorship, recovery or authentication secrets, personal notebook drafts, unsubmitted theory prose, and final-accusation drafts remain outside the Game Master view because they are source, security, or unsubmitted draft data.

Connected or disconnected is a best-effort presence indicator, not an authorization state. A temporarily disconnected player keeps their active room membership and can resume on the same device.

---

## 8. Stalled Discussion Mechanic

The host can press **Discussion Stalled** whenever conversation slows down.

Pressing the button requests a context-aware suggestion. The backend builds a fresh, room-scoped snapshot containing the current round, released events, mission outcomes, previously used interventions, and eligible unused canonical content. It may also include bounded aggregate suspicion patterns, but never private notebook or theory prose, correctness feedback, or author attribution.

The live AI may select eligible prepared content, direct a question grounded in known facts, and adapt non-factual presentation or tone. It must not create a new clue, relationship, alibi, role, motive, method, timeline fact, or solution, and it never writes game state directly.

The system validates the structured suggestion and stages it for host approval. The host receives the complete intervention preview, its canonical source content, and its typed effect. The intervention is released only after host approval.

| Level | Intervention |
|---|---|
| 1. Gentle Nudge | Conversation starter, suggested question, or directed interaction |
| 2. New Evidence | Release a prepared clue that opens a new line of inquiry |
| 3. Emergency Event | Trigger a secret message, revelation, or urgent personal mission |

Interventions are progressively stronger, limited per round, and never change the canonical story. An emergency intervention may activate only a pre-generated mission or release another pre-generated canonical effect.

If live AI is slow, unavailable, over budget, or returns invalid output, the system deterministically stages an eligible unused pre-generated intervention instead. The game never depends on a successful live model call.

The next round can always progress even if nobody completes their missions.

---

## 9. Early Murderer Discovery

Players may identify one or more murderers before the game ends.

This is allowed and should be rewarded rather than prevented.

### Rules

- Suspected murderers remain active participants.
- Public accusations never trigger an automatic identity confirmation.
- Murderers can defend themselves and challenge evidence.
- Accomplices can protect suspected murderers after learning their identities.
- The investigation continues without changing the canonical story.

### Build the Entire Case

Solving the mystery means more than naming the murderer.

Players investigate five questions:

1. Who committed the murder?
2. What was the motive?
3. How was the murder carried out?
4. Who helped the murderers?
5. What evidence supports the explanation?

This ensures the game remains interesting even when someone identifies a culprit early.

### Private Theories and Early Deduction Bonuses

Players can submit private suspicions during investigation rounds.

They receive no immediate correctness feedback.

Notebook drafts, suspect selections, and unsubmitted theory prose are stored server-side against the internal player ID, remain private to that player for the lifetime of the room, survive refresh and an approved device replacement, and are never sent to the live-intervention model. A separately submitted theory snapshot may be used for endgame scoring and is visible during play to its owner and the Game Master; it remains hidden from other players and never returns correctness feedback.

At the end, early accurate deductions supported by evidence may earn bonus points. Random guesses should not receive the same reward.

### Early Verdict

If the group believes it has solved the mystery, the host can select **Call Early Verdict**.

This closes the investigation and moves all players into final case submission, followed by the reveal.

The system gives players no automatic correctness verdict before this transition. The Game Master may infer or compare correctness from the authorized full view, but the system does not automatically judge the group's theory.

---

## 10. Final Accusations and Winning

Every player submits a final case identifying the suspected murderers, accomplices, motive, method, and supporting evidence. A saved draft is owner-only. Upon submission, the fixed snapshot becomes visible to the Game Master immediately while remaining private from other players until the reveal.

MVP faction victory conditions:

| Faction | Victory condition |
|---|---|
| Innocents | Correctly identify every murderer |
| Murderers | At least one murderer escapes identification |
| Accomplices | Share the murderers' victory |

Identifying accomplices, explaining the motive, and presenting strong evidence can award bonus points.

The game may also recognize the best detective or earliest justified deduction.

The scoring system should accommodate multiple murderers without making correct partial deductions feel worthless.

For the MVP faction outcome, a murderer is identified only when a strict majority of all configured innocent players name that murderer in their submitted final cases. Every murderer must cross that threshold for the innocents to win. A missing final case contributes no vote; murderer and accomplice cases do not count toward the innocent threshold. If no one submits, the murderer and accomplice factions win and every player receives zero points.

The Game Master may close final-case intake after every player submits, or may close it early after a confirmation that names every missing player and states that each non-submitter receives zero points and no faction vote. A disconnected player receives no automatic case; the Game Master may wait for reconnection or use the same early-close confirmation. Closing with zero submissions requires a second explicit confirmation before the reveal proceeds.

---

## 11. Final Story and Game Master Case File

**Every significant event should connect to one gripping narrative.**

The ending has two parts.

### Part A — Dramatic Reveal

Everyone experiences a shared final chapter revealing:
- Who the murderers were.
- Who protected them.
- The crime's motive and method.
- The decisive clues.
- How the conspiracy unfolded.

The reveal should feel like the conclusion of a detective movie, not simply a results screen.

### Part B — Game Master's Complete Case File

After the reveal, the system finalizes the host's case file by combining the already-visible canonical story with the events, mission outcomes, interventions, submitted theory snapshots, accusations, scores, and results that actually occurred.

It includes:
- The complete chronological narrative.
- Every character's backstory and secrets.
- All murderers' and accomplices' roles.
- The full crime timeline and alibis.
- Every important clue and its explanation.
- All generated missions and possible consequences.
- Which events and consequences actually occurred.
- Every submitted theory snapshot, including its structured selections, cited evidence, optional submitted explanation, timestamp, and score.
- Players' submitted final accusations and the final outcome.

Raw descriptions and their authorship, notebook drafts, suspect drafts, unsubmitted theory prose, and unsubmitted final-accusation drafts never enter the case file.

The canonical explanation is created before gameplay. The final presentation incorporates the choices and events that actually occurred without rewriting the crime.

### Postgame Access and Expiration

A completed room, including its generated story, event history, accusations, results, and case file, remains available for 30 days after completion. The room and all room-scoped data are then deleted.

Incomplete rooms expire after inactivity: DRAFT and LOBBY after 7 days; READY_TO_START, IN_PROGRESS, FINAL_ACCUSATIONS, and REVEAL after 30 days. A stale GENERATING job is recovered or failed safely back to LOBBY rather than deleted mid-job. Only successful authenticated mutations reset inactivity; page views and heartbeats do not. The product warns authorized users before deletion.

---

## 12. Website Screens

| Screen | Function |
|---|---|
| Create Room | Start a new game |
| Player Setup | Names, costumes, additional information |
| Game Configuration | Duration, faction counts, murderer awareness |
| Join Room | Enter a room code, select a host-created name/costume slot, and request access |
| Player Claim Approval | Host approves initial or reconnect requests and manages occupied slots |
| Describe Players | Submit private descriptions |
| Waiting Room | Track arrivals and submissions |
| Character Dossier | Private role, background, and secrets |
| Active Mission | Objectives, success criteria, consequences |
| Evidence Board | Public and private clues |
| Detective Notebook | Personal notes, suspects, and theories |
| Host Dashboard | Full Game Master view: solution, all roles and dossiers, secrets, missions, released and unreleased evidence, submitted theory snapshots and final accusations, ending, progress, and every game-control action |
| Final Accusations | Submit a complete case theory |
| Final Reveal | Shared cinematic-style conclusion |
| Game Master Case File | Game Master-only postgame narrative, submitted theory snapshots, accusations, scores, runtime outcomes, and explanations |

---

## 13. Proposed Technical Architecture

**Frontend:** Next.js + Tailwind CSS, designed primarily for mobile browsers.

**Backend and database:** Supabase for room data, player sessions, stories, mission state, private information, and live updates.

**Hosting:** Deploy the Next.js application on Vercel and manage the public domain and DNS with Cloudflare. Cloudflare Workers are not required for the MVP.

**AI generation:** A bounded pre-game generation workflow returns structured story data, individual roles, missions, event dependencies, and a fixed solution. Validation and repair may run before the single successful atomic lock.

**AI interventions:** During gameplay, a bounded live workflow may select and adapt the presentation of eligible canonical interventions from fresh room state. Every suggestion is validated, requires host approval, and has a deterministic pre-generated fallback.

**LLM provider and model policy:** Use the OpenAI Responses API behind an application-owned provider interface. The default story and repair model is `gpt-6.1-sol`, configured by environment rather than hardcoded. After bounded validation and repair failures, the backend may use the separately configured and evaluation-approved `gpt-6-astra` escalation model. Model changes require the story evaluation suite before production rollout, and the system must never silently switch to an untested model.

### Technical Requirements

- Support 4–12 players plus one separate non-playing host, with exactly one fictional NPC victim.
- Persistent room and player identities without mandatory account registration.
- Host-approved mapping from a persistent guest session to exactly one internal player ID.
- Room codes used for discovery only, never as authorization to private information.
- A separate high-entropy host management and recovery link unrelated to the public room code. The credential itself contains no story data; after a successful exchange, the recovered host session receives the full Game Master view appropriate to the room state.
- Atomic prevention of two active devices claiming the same player slot.
- Host-approved reconnect flow that revokes the old device and preserves player progress.
- Strict separation between claimed player identity and later generated story role.
- Server-side access control for private information.
- One complete Game Master projection after story lock; a host principal can never hold a player claim or membership.
- Host-authorized game actions.
- Real-time synchronization of round transitions and event releases.
- Reconnection support without losing progress.
- Server-persisted player notebooks keyed by internal player ID and private from other players and the Game Master for the room lifetime; only explicitly submitted theory snapshots and final accusations enter Game Master-visible gameplay state.
- Best-effort connected/disconnected presence that does not change membership or authorization.
- Exactly one immutable canonical story after atomic lock; no regeneration or replacement in the same room.
- One-time event releases with safeguards against duplicate actions.
- The canonical solution is visible to the Game Master after story lock and hidden from every player until the final reveal.
- Support for branching information releases without changing the historical truth.
- Context-aware live interventions constrained to eligible canonical content, with validation, host approval, and deterministic fallback.
- Automatic deletion of completed room data 30 days after completion.
- English-only MVP interface and generated fiction with Unicode-safe names and culturally inclusive Indian contexts.
- Initial deployment in Mumbai: Supabase `ap-south-1` and Vercel Functions `bom1`.

---

## 14. MVP Scope

The first version should include the full playable experience:

**Pre-game:** Host setup, faction configuration, guest-session creation, player claiming and host approval, reconnect management, player descriptions, and AI story generation.

**During the game:** Synchronized rounds, private roles, achievable missions, host completion tracking, consequences, evidence board, and context-aware stalled-discussion interventions with pre-generated fallback.

**Endgame:** Early Verdict, final accusations, scoring, dramatic reveal, and complete Game Master case file.

More elaborate features such as anonymous chat, advanced animations, downloadable souvenirs, and reusable story libraries can come later.

## 15. Core Design Principles

**A. One consistent mystery.** The crime and solution never change after generation.

**B. Every player always has something to do.** Achievable objectives drive conversations and reveal information.

**C. Failure creates drama, not dead ends.** Missed missions can expose secrets, but the mystery must remain solvable.

**D. The host controls the game, not the truth.** The Game Master knows the locked solution and controls pacing, claims, missions, releases, interventions, and the reveal, but cannot alter the canonical story after lock.

**E. Good deductions are rewarded.** Identifying a culprit early does not eliminate them or end the game automatically.

**F. The ending must be satisfying.** Every major clue, event, motive, and betrayal should contribute to the complete narrative.

**G. Phones support the party.** The actual experience should revolve around friends talking, accusing, bluffing, and laughing together—not staring at screens.

---

**Product vision:** A personalized, interactive Halloween murder mystery where every player has secrets, every player has objectives, and a dedicated Game Master moves the group toward a dramatic, coherent conclusion.
