# Main Contract — LF Profile Creator

## Contract

Given a governed request to create a profile, the Profile Creator must produce a complete profile pack candidate and route it to review gates. It must not bypass governance or create final operational profiles directly.

A created-state claim is an outcome claim, not a label. `PROFILE_PACK_CREATED` requires both an exact materialized candidate and deterministic evidence that the candidate is developed enough to enter independent semantic review.

## Acceptance criteria

A valid output must include:

- `status`.
- `profile_pack_id`.
- `source_authority`.
- `deliverable_created`.
- `files_created`.
- `evidence_map`.
- `blocking_codes`.
- `next_gate`.

When `status=PROFILE_PACK_CREATED`, it must additionally include:

- `deliverable_artifact_ref`, resolving to the exact candidate;
- `depth_gate.status=DEPTH_READY_FOR_SEMANTIC_REVIEW`;
- `depth_gate.validator_ref=skills/profile_creator/validators/validate_candidate_depth.py`;
- `depth_gate.candidate_ref` equal to `deliverable_artifact_ref`;
- `depth_gate.validation_scope=DETERMINISTIC_DEPTH_ONLY`;
- `depth_gate.semantic_quality_review=NOT_EXECUTED`;
- empty `depth_gate.blocking_codes`.

## Candidate depth contract

The materialized candidate must contain developed, reviewable content rather than nominal files or stubs. The deterministic gate requires:

1. a developed `SKILL.md` with role, inputs/source authority, trajectory, failure behavior and authority limits;
2. a developed main contract with input, evidence, scope, output and failure-routing rules;
3. a typed output schema whose required fields are actually defined;
4. judge/rubric material with explicit acceptance and failure conditions;
5. a non-empty evidence map with exact source references and supported claims;
6. positive and negative eval cases, each with observable expected status and assertions;
7. an actionable Quality Pack handoff carrying artifact identity, evidence, schema/contract, rubric/judge, blocking/risk context and failure routing;
8. governance boundaries preserving CANDIDATO / READ_ONLY / NO_HABILITADO / BLOQUEADO;
9. for user-facing profiles only, an explicit `user_payload` / `internal_envelope` or equivalent protected boundary.

These are deterministic reviewability invariants, not a semantic score. Length or file presence alone is insufficient.

## Required evidence

- Router decision applied.
- Supabase source verification requested or confirmed.
- Active governing asset identified.
- Existing assets checked to avoid duplicates.
- Structural identifiers reconciled against governing authority.
- The created artifact is observable when creation is claimed.
- The deterministic depth validator executed against that exact artifact.
- The next worker can consume the artifact without reconstructing missing structure or intent.
- Runtime and automatic impact remain blocked.
- Independent semantic Quality Pack review remains a separate gate.

## Rejection criteria

Reject when the output is only a prompt, prose description, checklist, filename list or unresolved reference.
Reject `PROFILE_PACK_CREATED` when the candidate cannot be resolved, fails `validate_candidate_depth.py`, or the depth receipt is not bound to the exact candidate.
Reject any attempt to reinterpret `DEPTH_READY_FOR_SEMANTIC_REVIEW` as semantic approval, behavioral PASS, runtime approval or production authorization.
If live authorities conflict, return/block rather than selecting a value by plausibility or observed-state coincidence.
