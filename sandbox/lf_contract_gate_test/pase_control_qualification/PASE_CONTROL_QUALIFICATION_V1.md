# PASE_CONTROL_QUALIFICATION_V1

## Purpose
Qualify a candidate control, control replacement/refactor, owner-runner change, or binding change by its own declared responsibility without using the legacy carrier being replaced as final qualification authority.

This contract qualifies a candidate only. `CANDIDATE_QUALIFIED` does not mean ACTIVE, CUTOVER, REBIND, DEPLOY, production mutation, or legacy retirement.

## Applicability authority
Changeset Governance remains the single authority that identifies a control-system changeset and routes it to this qualification lane. This contract MUST NOT reclassify changed paths or create a second applicability authority.

Allowed `qualification_type` values:
- `NEW_CONTROL`
- `CONTROL_REPLACEMENT`
- `CONTROL_REFACTOR`
- `OWNER_RUNNER_CHANGE`
- `BINDING_CHANGE`

## Qualification authority and separation
The qualification verdict MUST be produced by an independent qualifier using exact-head evidence.

Forbidden final authorities:
1. the candidate itself;
2. candidate-owned self-test output by itself;
3. the legacy carrier being replaced;
4. an unrelated domain control;
5. a second Changeset Governance implementation.

Owner-local executable tests are mandatory evidence, but are inputs to independent qualification, not the verdict authority.

## Required input
```json
{
  "schema_version": "lf-pase-control-qualification/v1",
  "qualification_type": "NEW_CONTROL|CONTROL_REPLACEMENT|CONTROL_REFACTOR|OWNER_RUNNER_CHANGE|BINDING_CHANGE",
  "repository": "owner/repo",
  "base_sha": "40-hex",
  "head_sha": "40-hex",
  "observed_main_sha": "40-hex",
  "candidate_id": "non-empty",
  "declared_owner": "non-empty",
  "scope_paths": ["exact/path/or/prefix"],
  "owner_local_tests": ["executable locator"],
  "boundary_invariants": ["machine-checkable invariant id"],
  "expected_coverage": ["responsibility id"],
  "replacement": {
    "legacy_id": "required for replacement when applicable",
    "replay_required": true
  }
}
```

## Required qualification checks
Q01 exact identity: `base_sha` and `head_sha` exist and evidence is tied to exact `head_sha`.

Q02 exact scope: candidate diff is attributable to declared scope. Unexpected out-of-scope mutation fails unless explicitly part of qualification infrastructure and separated from candidate responsibility.

Q03 declared owner: owner is present before qualification and candidate cannot act as verdict authority.

Q04 owner-local executable tests: executable candidate-local tests exist and pass on exact head.

Q05 boundary/ownership invariants: candidate performs only its declared responsibility and does not absorb foreign domain behavior.

Q06 negative/adversarial tests: malformed/unknown ownership, drift, incomplete coverage, cycles, duplicate delegation or equivalent candidate-specific failure modes fail closed when applicable.

Q07 absence of out-of-scope effects: no mutation/execution of unrelated control domains is introduced by candidate.

Q08 determinism/idempotence: where responsibility is deterministic or retryable, same governed input yields equivalent output and retries do not create duplicated effects.

Q09 old-vs-new replay: mandatory for behavior replacement. Compare equivalent governed inputs and classify intentional deltas. Replay is not cutover.

Q10 coverage preserved: all responsibilities claimed as preserved/replaced are accounted for; missing coverage fails.

Q11 exact-head evidence/readback: every material PASS claim cites evidence generated/read against exact head. Stale/head-mismatched evidence blocks qualification.

## Scenario-aware qualification overlay

`PASE_SCENARIO_QUALIFICATION_MATRIX_V1` is mandatory before terminal control-set qualification and before ACTIVE_BLOCKING transition. It is an evidence/coverage overlay for Q06, Q10 and activation readiness; it does **not** change this contract's input/result schema and it does not become a second applicability authority.

Scenario selection is derived only from:

`control maturity + declared control traits + deterministic scenario catalog predicates`.

For every scenario in the canonical catalog:
- selected -> terminal disposition must be `TESTED` or `BLOCKED_EXPLICITLY`, backed by bounded exact-head evidence;
- unselected -> `NOT_APPLICABLE` with machine-derived predicate reason;
- selected without evidence/assertion -> `BLOCK_SCENARIO_SELECTED_UNKNOWN`;
- selected `UNKNOWN` is forbidden.

The resolver MUST deduplicate shared evidence probes and execute only selected scenario evidence. It MUST NOT infer a universal mega-suite or historical broad scan.

Maturity transitions are material. A scenario that is `NOT_APPLICABLE` during BUILD/QUALIFICATION/CUTOVER may become selected during ACTIVE. Therefore the activation gate must re-resolve the scenario matrix against ACTIVE maturity before any `ACTIVE_BLOCKING` transition.

This is the enforcement form of `NO_FIRST_DISCOVERY_IN_PRODUCTION`: every realistic reachable state represented by the canonical catalog is either proven, explicitly fail-closed, or deterministically not applicable before activation.

## External findings
Every external finding MUST be represented as:
```json
{
  "finding_id": "stable id",
  "source_control": "control/carrier",
  "observed_failure": "fact",
  "candidate_causality": "PROVEN|DISPROVEN|UNRESOLVED",
  "causal_evidence": ["evidence locator"],
  "owner": "real owner when known",
  "effect_on_candidate_verdict": "FAIL|NONE|BLOCKED"
}
```

Rules:
- `PROVEN`: evidence demonstrates candidate introduced the failure or violated its own contract -> candidate may FAIL.
- `DISPROVEN`: route finding to real owner; effect on candidate verdict = NONE.
- `UNRESOLVED`: MUST NOT be converted to candidate FAIL. It may BLOCK only when the unresolved causal question prevents a mandatory qualification check.
- A legacy carrier failure is never causal evidence by itself.
- Qualification MUST NOT repair the external control inside the candidate PR.

## Verdict
Only:
- `CANDIDATE_QUALIFIED`: Q01-Q11 applicable checks pass, no candidate-caused failing finding, required evidence complete.
- `FAIL`: candidate violates its own contract or a causal external finding is PROVEN against candidate.
- `BLOCKED`: mandatory qualification evidence/check cannot be completed without guessing; includes unresolved causality only when material to a mandatory check.

No other verdict is allowed.

## Output
```json
{
  "schema_version": "lf-pase-control-qualification-result/v1",
  "candidate_id": "...",
  "base_sha": "...",
  "head_sha": "...",
  "declared_owner": "...",
  "checks": [{"id":"Q01","status":"PASS|FAIL|BLOCKED|NA","evidence":[]}],
  "external_findings": [],
  "coverage_complete": true,
  "verdict": "CANDIDATE_QUALIFIED|FAIL|BLOCKED",
  "qualified_only": true,
  "activation_authorized": false,
  "cutover_authorized": false,
  "rebind_authorized": false,
  "legacy_retirement_authorized": false
}
```

## Mandatory post-qualification sequence
`OWNER NUEVO PROBADO -> REPLAY OLD vs NEW -> BINDING / REBIND -> READBACK -> RETIRAR LEGACY`

Legacy MUST NOT be retired before destination behavior is demonstrated.

## First candidate: PR #1170 / PASE_ORCHESTRATOR_V1
Candidate responsibility only:
- consume `lf-ci-execution-plan/v2`;
- do not decide applicability;
- respect canonical owner/carrier;
- delegate every required control exactly once;
- preserve dependency order;
- block unknown control/owner representation, carrier drift, incomplete coverage and cycles as representable by its canonical inputs;
- execute no Contract Check, Migration Parity, Assurance, E16, S36, Profile Runtime, DB Regression, or other domain logic.

Inherited failures from those domains are external findings unless causality to PR #1170 is demonstrated.
