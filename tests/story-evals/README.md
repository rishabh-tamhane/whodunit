# Story evaluation corpus

The executable corpus is generated deterministically by
`src/modules/generation/fixtures.ts`. It covers every supported party size from
4 through 12, aware and unaware murderer modes, recommended multiple-murderer
configurations, Unicode-safe Indian names and contexts, and adversarial private
description overlap.

The rubric is a 100-point gate: coherence, solvability, mission achievability,
information flow, cultural safety, reveal quality, latency, estimated cost,
fictional consequence escalation, and raw-input non-copying each contribute ten
points. A candidate must score at least 90 and have no deterministic validator
errors. Model or prompt changes are not approved merely because their average
score passes: every fixed scenario must pass.
