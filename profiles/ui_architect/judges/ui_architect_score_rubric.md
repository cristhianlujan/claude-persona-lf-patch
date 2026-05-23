# Judge — UI Architect 25-Point Score Rubric

Status: CANDIDATE_READ_ONLY / SANDBOX

## Rule
No score can be assigned without evidence. If evidence is missing, that criterion scores 0 even when the worker claims compliance.

## Criteria

### 1. Layout precision — 5 points
- 5: zones, proportions, grid, content placement and restrictions are explicit.
- 3: zones exist but proportions or placement are partial.
- 1: only general layout language.
- 0: no layout evidence.

### 2. Visual hierarchy — 5 points
- 5: ranked elements, visual weight and rationale are explicit.
- 3: hierarchy is implied but not fully ranked.
- 1: generic statement about clarity/premium.
- 0: no hierarchy evidence.

### 3. LF system fidelity — 5 points
- 5: LF tokens, debt-context safety, no dark patterns and accompaniment tone are explicit.
- 3: some LF tokens are named but not mapped.
- 1: generic brand alignment.
- 0: no LF fidelity evidence.

### 4. State mapping — 5 points
- 5: active/secondary/disabled/hover/informational states are explicit where relevant.
- 3: states are partially listed.
- 1: claims states exist without details.
- 0: no state evidence.

### 5. Handoff quality — 5 points
- 5: composer can generate prompt or next artifact without inventing structure.
- 3: useful but still requires interpretation.
- 1: mostly recommendations.
- 0: not actionable.

## Passing gates
- 20/25 minimum to continue to composer.
- Any 0 in Layout precision or Handoff quality blocks the flow.
- Any dark pattern or LF safety failure blocks the flow regardless of total score.
