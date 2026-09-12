# Judge — Quality Pack 25-Point Score Rubric

Status: CANDIDATE_READ_ONLY / SANDBOX

## Rule
No score can be assigned without evidence. Claims without evidence score 0.

## Criteria

### 1. Contract and schema compliance — 5 points
- 5: contract and schema fully satisfied.
- 3: minor omissions that do not block next gate.
- 1: mostly generic alignment.
- 0: missing contract/schema evidence.

### 2. Evidence integrity — 5 points
- 5: every PASS/true claim has developed evidence.
- 3: most claims have evidence but some are partial.
- 1: evidence is mostly implied.
- 0: claims without evidence.

### 3. LF safety and governance — 5 points
- 5: LF visual/product safety explicitly respected.
- 3: no obvious violation but weak LF anchoring.
- 1: generic safety only.
- 0: dark pattern, pressure, shame, fake urgency or unsafe debt cue.

### 4. Handoff readiness — 5 points
- 5: next worker can proceed without inventing structure.
- 3: next worker can proceed with minor interpretation.
- 1: handoff is vague.
- 0: not usable by next worker.

### 5. Leakage and scope control — 5 points
- 5: no internal metadata, extra sections or off-scope elements can leak.
- 3: minor risk with explicit mitigation.
- 1: risk exists and mitigation is weak.
- 0: internal metadata/off-scope elements present or likely.

## Gates
- 23-25: PASS or PASS_WITH_RESTRICTIONS depending on remaining risk.
- 20-22: PASS_WITH_RESTRICTIONS only.
- 10-19: RETURN_TO_WORKER_FOR_SELF_REPAIR or RETURN_TO_ORCHESTRATOR.
- 0-9: BLOCK_PIPELINE.

Any hard LF safety violation blocks regardless of total score.
