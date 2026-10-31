# Whodunit v0.1 MVP — Privacy, Consent, and Gameplay Copy

**Status:** Approved English MVP copy contract

Copy may be shortened for a constrained surface only when the same meaning remains available through adjacent help text or an accessible description.

## Room Code

**Title:** A room code finds the party. It does not unlock the mystery.

**Body:** Anyone with this code can see the player names, costumes, and whether a slot is available. The code never reveals roles, clues, missions, notes, theories, or the solution. A player gets private access only after the Game Master approves their device.

**Share action:** Share room code

**Error:** We could not find a joinable room with that code. Check the code and try again.

## Dedicated Game Master Disclosure

**Title:** The Game Master runs the mystery and does not play a character.

**Body:** After the story is locked, the Game Master can see the solution, every generated role and secret, all missions and evidence, and gameplay state that players explicitly submit. The Game Master cannot see raw friend descriptions, notebook drafts, unsubmitted theory prose, or final-case drafts.

**Acknowledgement:** I understand what the Game Master can and cannot see.

## Claim Request

**Player title:** Request this player slot?

**Player body:** You are asking the Game Master to connect this device to **{name} — {costume}**. Selecting a name does not reveal or assign a faction.

**Player action:** Send request

**Pending:** Request sent. Keep this page open or return later on this device. You will not receive private game information until the Game Master approves you.

**Game Master title:** Approve this device as {name}?

**Game Master body:** Approval connects this guest session to {name}'s stable player identity. It does not change that player's later story role.

**Approve action:** Approve device

**Reject action:** Reject request

**Conflict:** This request is no longer current. Refresh the room to see the latest player binding.

## Reconnect and Device Replacement

**Player title:** Reconnect as {name}?

**Player body:** The Game Master must approve this replacement. Approval signs out the previous device from this room and keeps {name}'s dossier, clues, missions, notes, theories, accusation, and progress.

**Game Master title:** Replace {name}'s active device?

**Game Master body:** The old device will lose access on its next request. This cannot move progress to a different player slot.

**Approve action:** Replace device

**Warning:** Only approve when {name} has asked to reconnect in person.

## Private Descriptions

**Title:** Describe {name} for the mystery generator.

**Body:** Write a light, party-safe detail that can inspire fictional story material. The Game Master and other players will never see this raw text or who wrote it. It is sent only to the generation service and deleted after the story locks.

**Safety help:** Do not include caste, religion, medical or financial information, trauma, intimate details, or anything you would not want used in party fiction.

**Decline action:** Prefer not to answer

**Decline confirmation:** This prompt will count as complete without storing a reason. You can change your response before generation begins.

**Pending validation:** Submit a description or choose “Prefer not to answer” for every other player.

## Consent and Fictional Use

**Player acknowledgement:** I understand that submitted details may inspire fictional mystery content, and I have avoided sensitive or harmful personal information.

**Game Master acknowledgement:** I have told everyone this is fictional party entertainment, reviewed the privacy boundaries, and confirmed that every participant consents to generation.

**Room consent action:** Confirm room consent

## Notebook and Submission Boundary

**Notebook label:** Private to you

**Notebook help:** Notes, suspect selections, and unsubmitted theory prose stay private from every other player and the Game Master.

**Theory submit title:** Submit this theory to the Game Master?

**Theory submit body:** Submission creates a permanent snapshot of the selected suspects, cited evidence, and explanation. You can keep editing your private notebook, but the submitted snapshot cannot be changed or removed.

**Final-case draft label:** Draft — private to you

**Final-case submit body:** After submission, this fixed case becomes visible to the Game Master. Other players cannot see it until the reveal.

## AI Generation

**Before generation:** Whodunit uses AI to create one fictional mystery from the approved room setup and safe generation inputs. Deterministic checks validate player coverage, clues, missions, timing, safety, and the fixed solution before anything becomes playable.

**Generating title:** Building one locked mystery

**Generating body:** This usually takes under 90 seconds. You can leave this screen and return. No player can see a partial story.

**Repair status:** The first draft needs repair. We are checking it again before lock.

**Failure title:** No mystery was locked

**Failure body:** Generation stopped safely before any story became playable. Your room is still editable and the Game Master can retry.

**Locked:** Mystery locked. It can no longer be regenerated or changed in this room.

## Live AI Interventions

**Game Master help:** A live suggestion may select and phrase only unused facts, evidence, missions, or questions from the locked mystery. It cannot invent or change the solution. You see the complete canonical source and effect before approval.

**Loading:** Preparing a context-aware suggestion…

**Fallback:** The live suggestion took too long, so Whodunit prepared a validated fallback from the locked story.

**Approve action:** Release to players

**Reject action:** Keep it hidden

## Early Verdict and Final Intake

**Early Verdict title:** End the investigation rounds?

**Body:** Players will move to private final cases. The mystery and solution will not change, and no correctness feedback appears before reveal.

**Close with missing players:** {count} player(s) have not submitted. Closing now gives each named player zero points and no faction vote. Their draft remains private and is not included in the case file.

**Zero-submit confirmation:** No final cases have been submitted. Closing now produces zero player scores and a murderer/accomplice faction win. Confirm again to publish the prepared reveal.

## Retention and Expiration

**Completed room:** This completed mystery remains available for 30 days after completion, then the room and all of its data are permanently deleted.

**Incomplete warning:** This inactive room will be permanently deleted on {date}. Complete a valid game action to keep it active; simply opening the page does not reset the timer.

**Expired:** This room has expired and its data has been deleted. Create a new room to play again.

## Connectivity and Conflict

**Offline:** You are offline. Your last synchronized game state remains visible, but actions are paused until connection returns.

**Reconnecting:** Reconnecting and checking the latest room version…

**Stale action:** The room changed before this action completed. We refreshed the latest state; review it and try again.

**Revoked device:** This device is no longer connected to that player. Ask the Game Master to approve a reconnect request.
