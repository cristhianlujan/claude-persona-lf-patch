# Contract — Quality Pack Deterministic Intake

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: `profiles/quality_pack/validators/run_handoff_intake.py`

## Purpose

Provide a real executable pre-check for producer→Quality Pack continuity without pretending to execute Quality Pack's semantic judgment.

This gate answers only:

> Does the receiver have enough explicit context and a materialized upstream artifact to begin its normal review without reconstructing producer state?

## Deterministic checks

The intake gate must verify:

1. required Quality Pack intake context is present;
2. upstream output is machine-readable;
3. upstream evidence is explicitly delivered;
4. if a created deliverable is claimed, an observable materialized artifact is delivered either by exact reference plus artifact payload or as an explicit embedded `candidate_artifact`;
5. artifact identity matches the producer claim;
6. every component claimed in `files_created` exists with non-empty developed content.

## Outputs

Allowed `intake_status` values:

- `QUALITY_INTAKE_READY`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

When `QUALITY_INTAKE_READY` is emitted, `next_gate` must be `SEMANTIC_QUALITY_REVIEW`.

## Non-claims

This gate must never emit or imply:

- `PASS_TO_COMPOSER`;
- `PASS_WITH_RESTRICTIONS`;
- a Quality Pack score;
- LF safety judgment;
- leakage/scope semantic judgment;
- general Quality Pack behavioral PASS.

`semantic_quality_review_status` must remain `NOT_EXECUTED`.

## Routing

- Missing receiver context → `RETURN_TO_ORCHESTRATOR`.
- Producer claims a created artifact but fails to deliver an observable materialized artifact, or fails to deliver claimed components → `RETURN_TO_WORKER_FOR_SELF_REPAIR`.
- Deterministic intake satisfied → `QUALITY_INTAKE_READY` then `SEMANTIC_QUALITY_REVIEW`.

## Promotion rule

The intake capability may be promoted from capability eval to regression only after actual-vs-expected execution of preserved fixtures and exact-head CI. That promotion protects intake continuity only; it does not promote semantic Quality Pack behavior.
