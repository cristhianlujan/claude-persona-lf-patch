# GATE_CHECK_OBSERVABILITY

Canonical LF transversal capability: `GATE_CHECK_OBSERVABILITY` / `TRANSVERSAL_GATE_CHECK_OBSERVABILITY`.

This package provides deterministic check-level diagnostics for reusable LF gates. It is intentionally capability-agnostic: consumers declare their checks in a manifest; this package must not contain hardcoded Profile Runtime, Currentness, Parity or other capability semantics.

## Components

- `run_gate_checks_v1.py` — existing deterministic check runner. Produces `LF_GATE_ERROR_V1` with exact source path, command, exit code, stdout/stderr hashes, assertion/error, traceback, trace ids and source/tested commit.
- `run_gate_groups_v1.py` — groups deterministic checks into stable subprocesses while continuing to delegate every individual check to `run_gate_checks_v1.py`.
- `persist_gate_failures_to_ekb_v1.py` — side-effect adapter. Reads durable diagnostics and, only in `--write` mode, calls the canonical `public.lf_write_pipeline_ekb_v1` writer. It never writes EKB tables directly.

## Group manifest contract

A consumer manifest uses `schema_version=lf-gate-group-manifest/v1` and must declare:

- one `consumer_code`, `gate_id`, `owner` and `discover_glob`;
- `expected_total_checks`;
- stable ordered `groups`;
- every group must be `execution_class=DETERMINISTIC`;
- every discovered test must belong to exactly one group;
- no stale, missing or duplicate test assignment is accepted.

The grouped runner fails closed when the manifest and the discovered filesystem differ. This prevents a new `test_*.py` from silently escaping the gate.

## Execution policy

Normal/final execution selects all groups. Every check inside a group is executed in `COLLECT_ALL` mode. If a group fails, later groups are not run. This gives exact local diagnosis without paying for unrelated downstream groups after a known failure.

A repair may run one or more groups with `--group`. A targeted green run is useful for repair feedback but is **not** closure evidence: `full_coverage=false`, `claim_ready=false` and `excel_ready=false`.

Only a full execution in which every declared group and every declared check passes produces:

- `full_coverage=true`;
- `claim_ready=true`;
- `excel_ready=true`.

The summary preserves the two LF proof views:

- `prueba_a_nivel_general`: overall gate/coverage counts;
- `prueba_paso_a_paso`: ordered group results with child diagnostic references.

## EKB behavior

Deterministic runners never mutate LF operational state. Failure persistence is a separate adapter so control evidence is reproducible.

`persist_gate_failures_to_ekb_v1.py` creates a stable error code from gate + group + source path + error class. A repeated failure therefore becomes a recurrence in canonical EKB instead of creating a new row each run.

For new automatic failures the bridge deliberately uses `root_cause_family=UNCLASSIFIED_WITH_REASON`; detection is evidence, not a root-cause diagnosis. The bridge records the exact failing test, error/assertion, trace, failure digest, run and source/tested commit.

`--emit-only` validates/serializes candidates without a database write. `--write` requires the encrypted database credential and `psql`, then invokes only `public.lf_write_pipeline_ekb_v1`. Missing writer transport is persisted as `EKB_PERSISTENCE_BLOCKED`; it is never reported as successful EKB persistence.

## Consumer example

Profile Runtime V3 consumes this capability through `profile_runtime_v3_gate_manifest.json`. That manifest is a consumer declaration only; the grouping engine remains transversal and reusable by other LF gates.
