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

`npm run test:story-evals` runs the free deterministic gate. The paid live
gate uses the production prompt, strict JSON Schema, provider adapter,
validator, and rubric across all 18 party-size/awareness cases:

```sh
STORY_EVAL_ACKNOWLEDGE_COST=YES npm run eval:story:live
```

The command loads `OPENAI_API_KEY` from the ignored root `.env.local` when it
exists. It refuses to run without both the key and explicit cost
acknowledgement. It writes a mode-0600 report under the operating-system
temporary directory by default. Reports contain only case dimensions,
versions, scores, latency, token counts, estimated cost, and normalized failure
codes—never prompts, roster content, private descriptions, generated stories,
or provider payloads. Set `STORY_EVAL_REPORT_PATH` only to an ignored path if a
durable local report is needed.

The workflow follows OpenAI's evaluation guidance: use task-specific cases,
define success criteria and metrics first, automate scoring where possible,
run comparisons for every prompt/model/schema change, and calibrate automated
results with human playtest judgment. The accepted baseline is not replaced
until every fixed case passes and a reviewer approves the safe report.
See OpenAI's
[evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices)
for the upstream methodology.
