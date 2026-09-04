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

## Transversal precedence and inheritance

This contract is the canonical technical minimum for governed Profile packs. The precedence order is:

1. Router / `ACT-0001` decision.
2. live Supabase operational source (`public.v_lf_fuente_operativa`) and the active governing asset, including `ACT-0045` when applicable.
3. this Profile Creator contract for reusable Profile-pack capabilities and evidence.
4. destination/profile-specific contracts and validators for domain behavior.
5. `profiles/_template` only as a reusable reference superset, never as authority to invent empty folders or duplicate capabilities.

If a repository label or old template conflicts with a live higher-precedence authority, block the conflicting interpretation and preserve the live readback as authority. Do not repair drift by copying canonical policy into every Profile.

### Reuse rules

- Shared governance is referenced and version-bound; it is not copied into Profile prompts.
- Input Governance, when applicable, is consumed through the live `INPUT_READINESS_CONTRACT` and the governed binding contract. Only required sections are materialized and a `governance_receipt` is recorded.
- Adapters are resolved from the Router canonical binding (for example `public.v_lf_router_adapter_bindings`). A Profile-local adapter is allowed only for a genuinely profile-specific transformation not already represented by a central adapter and must have explicit authority/evidence.
- Cards are referenced by exact asset/path/version/hash and consumed selectively. A full Card/context pack is not injected by default when a smaller JIT projection suffices.
- An artifact category that is genuinely not applicable may be omitted when the capability is explicitly `N/A` with reason and no governing destination contract requires it. Missing required capability evidence remains blocking.

These rules prohibit scaffolding-only compliance and prevent governance forks.

## Full family E2E success contract

A Profile family is not successful merely because the Profile pack validates, a PR merges, one model call succeeds, or a backup runtime completes. `FAMILY_E2E_PASS` may be claimed only when one correlated execution proves the complete applicable trajectory:

`Request → Router → Input Governance → Profile → Cards → Adapters → HETZNER → model → validators/judges → persistence → readback`.

The existing durable `request_id` is the correlation root unless a stricter existing trace identifier is already available; do not create a parallel trace registry only to satisfy this contract.

The same execution evidence must include, when applicable:

- Router decision/ref.
- Input Governance decision, resolved revision, consumed sections, source refs and snapshot hash; or governed `N/A`.
- Profile code plus exact source/version/hash refs.
- Card refs/version/hash and sections/features consumed; or governed `N/A`.
- Adapter resolution and invocation receipt; or governed `N/A`.
- `runtime_target=HETZNER` for proof of primary-runtime readiness. `GITHUB_ACTIONS` is explicit backup evidence only and never satisfies the primary-runtime gate.
- runtime provider/model and observable model outcome.
- deterministic validator results and semantic judge results kept as distinct evidence layers.
- durable persistence of request/result/receipt/attestation.
- exact post-execution readback by the same `request_id`.
- quality/depth measures.
- latency by material stage and total latency.
- input/output/cache token usage when exposed by the provider/runtime.
- source provenance/snapshot evidence sufficient to reproduce what context was consumed.

If any applicable stage is absent or cannot be read back, the family result is `FAMILY_E2E_BLOCKED` or an equivalent non-success status with the missing stage named. A lower evidence rung must never be promoted into family success.

## Context-efficiency contract

Optimize context after correctness and provenance are preserved:

1. carry stable references/hashes in the envelope;
2. retrieve only stage-relevant material JIT;
3. materialize only the Input Governance/Card/Adapter sections needed for the current decision;
4. preserve enough receipt metadata to explain exactly what was omitted and why;
5. measure token usage before claiming an optimization.

A smaller prompt without equal-or-better quality, depth and traceability is not a successful optimization.

## Required evidence

- Router decision applied.
- Supabase source verification requested or confirmed.
- Active governing asset identified.
- Existing assets checked to avoid duplicates.
- Structural identifiers reconciled against governing authority.
- The created artifact is observable when creation is claimed.
- The deterministic depth validator executed against that exact artifact.
- The next worker can consume the artifact without reconstructing missing structure or intent.
- Runtime and automatic impact remain blocked for newly created candidates until separate runtime gates authorize them.
- Independent semantic Quality Pack review remains a separate gate.
- Any later operational-family success claim satisfies the Full family E2E success contract above.

## Rejection criteria

Reject when the output is only a prompt, prose description, checklist, filename list or unresolved reference.
Reject `PROFILE_PACK_CREATED` when the candidate cannot be resolved, fails `validate_candidate_depth.py`, or the depth receipt is not bound to the exact candidate.
Reject any attempt to reinterpret `DEPTH_READY_FOR_SEMANTIC_REVIEW` as semantic approval, behavioral PASS, runtime approval or production authorization.
Reject exact-tree/template compliance as a substitute for capability evidence.
Reject duplicate local policy/adapter logic when the capability already has a live shared contract or Router binding.
Reject `FAMILY_E2E_PASS` when HETZNER primary-runtime evidence, applicable Cards/Input Governance, persistence, readback, quality/depth/performance/tokens or traceability are missing.
If live authorities conflict, return/block rather than selecting a value by plausibility or observed-state coincidence.
