# Judge — Quality Pack Mini-Judge

Status: CANDIDATE_READ_ONLY / SANDBOX

## Purpose
Determine whether an upstream artifact can proceed to the next gate.

## Required checks
1. Upstream worker contract was identified.
2. Expected schema was identified.
3. Output satisfies required structure.
4. Evidence exists for every PASS/true claim.
5. Score breakdown follows rubric.
6. LF safety/governance controls pass.
7. Scope leakage controls pass.
8. Handoff is actionable.
9. Required repair actions are explicit when failing.

## Automatic FAIL conditions
- Score exists without evidence.
- Required field claimed but not developed.
- Internal metadata can leak into final user artifact.
- Dark pattern, debt pressure, fake urgency, shame, guarantee or red alarm cue appears.
- Composer would need to invent major structure.
- Output says approved/ready without evidence map.

## Verdict mapping
- `PASS_TO_COMPOSER`: evidence complete and no material risk.
- `PASS_WITH_RESTRICTIONS`: evidence sufficient, risk explicit, next gate can manage it.
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`: input sufficient but worker output incomplete.
- `RETURN_TO_ORCHESTRATOR`: wrong/missing upstream context.
- `BLOCK_PIPELINE`: unsafe, structurally invalid or high-risk.

## Required output
Quality Pack must produce:
- `verdict`
- `score_breakdown`
- `evidence_map`
- `blocking_codes`
- `repair_actions`
- `remaining_risks`
- `next_gate`
