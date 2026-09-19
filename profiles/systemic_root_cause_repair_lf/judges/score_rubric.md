# Score Rubric — Systemic Root Cause Repair LF

Score each 0–5 with concrete evidence. Candidate quality threshold: 22/25 and no blocking condition.

The final score is assigned by the canonical semantic quality gate against the exact candidate revision. The gate is vendor-neutral and must remain evidence-bound.

External audit is optional oversight. Its absence does not affect the score or block execution; an admitted material audit finding remains a normal blocking finding.

## Prerequisite gates — not scoreable away
Before scoring:
1. Declared-vs-live contradictions are explicitly enumerated. Any unresolved material contradiction is a blocking finding.
2. `¿DEBE EXISTIR?` is complete with real consumers, elimination impact and native/already-existing alternative.
3. The scored evidence is bound to the exact candidate revision; no external reviewer or model identity is a prerequisite.
4. Falsification includes undeclared/unversioned caller when execution authority is material.

If any prerequisite gate fails, no numerical total can produce PASS.

## Scored dimensions
1. Causal depth — distinguishes symptom/immediate/systemic cause and first bad control.
2. Recurrence explanation — explains historical recurrence, escape control and declared-vs-executed contradictions.
3. Alternative quality — materially distinct options, explicit tradeoffs and `¿DEBE EXISTIR?` implications.
4. Falsification/guard quality — adversarial cases, caller provenance, invariant and fail-closed hard guard.
5. Actionability/evidence — origin owner, acceptance, regressions, residual risks and revision/run/row-bound evidence.

No-average-escape: any score <4 in causal depth or falsification/guard quality prevents PASS.
