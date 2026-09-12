# Score Rubric — LF Profile Creator

## PRODUCER ACCEPTANCE

- Router/source authority is explicit and conflicts are not silently resolved.
- The created candidate is exact and resolvable.
- The candidate passes `skills/profile_creator/validators/validate_candidate_depth.py`.
- `depth_gate.status` is `DEPTH_READY_FOR_SEMANTIC_REVIEW` and is bound to the same artifact reference.
- Core contract, schema, judge, evals, evidence and handoff are developed enough for review rather than stub-only.
- Positive and negative eval cases contain assertions.
- User-facing candidates protect internal orchestration metadata; internal-only candidates do not invent a user boundary.
- Runtime and automatic impact remain blocked.

## RETURN_TO_WORKER

- A required semantic-depth component is missing, nominal, untyped, unsupported by evidence, or not actionable.
- Evals lack negative coverage/assertions.
- Handoff forces Quality Pack to reconstruct artifact identity, evidence, schema/rubric or failure routing.
- Depth gate was not executed against the exact deliverable.

## BLOCK

- Authority is contradictory and a value is selected anyway.
- Evidence is fabricated or only asserted generically.
- Internal metadata leaks into a declared user-facing payload.
- Runtime, production or automatic impact is enabled.
- Producer depth is presented as independent semantic approval.

`DEPTH_READY_FOR_SEMANTIC_REVIEW` is only a deterministic producer gate. Independent semantic Quality Pack review remains required before any semantic PASS or promotion.
