# GATE_CHECK_OBSERVABILITY

Canonical LF transversal capability: `GATE_CHECK_OBSERVABILITY` / `TRANSVERSAL_GATE_CHECK_OBSERVABILITY`.

## Propósito

Proveer diagnóstico determinístico y reutilizable a nivel de check, con identidad estable, evidencia exacta y descomposición por subproceso, sin incorporar semántica específica del consumer.

This package provides deterministic check-level diagnostics for reusable LF gates. It is intentionally capability-agnostic: consumers declare their checks in a manifest; this package must not contain hardcoded Profile Runtime, Currentness, Parity or other capability semantics.

## Components

- `run_gate_checks_v1.py` — existing deterministic check runner. Produces `LF_GATE_ERROR_V1` with exact source path, command, exit code, stdout/stderr hashes, assertion/error, traceback, trace ids and source/tested commit.
- `run_gate_groups_v1.py` — groups deterministic checks into stable subprocesses while continuing to delegate every individual check to `run_gate_checks_v1.py`.
- `persist_gate_failures_to_ekb_v1.py` — compatibility translator/test adapter. It is emit-only and has no productive database-write path. Productive failures must enter `public.lf_operation_gate_check_results` through `public.lf_record_gate_checks_v1`; `PRE_EKB_GATE` then owns persistence to EKB.

## Group manifest contract

A consumer manifest uses `schema_version=lf-gate-group-manifest/v1` and must declare:

- one `consumer_code`, `gate_id`, `owner` and `discover_glob`;
- `expected_total_checks`;
- stable ordered `groups`;
- every group must be `execution_class=DETERMINISTIC`;
- every group declares exactly one check carrier: `tests` or explicit `commands`;
- explicit commands use the same non-shell `argv/source_path/critical` contract already consumed by `run_gate_checks_v1.py`;
- every discovered check source must belong to exactly one group;
- no stale, missing or duplicate check assignment is accepted.

The grouped runner fails closed when the manifest and the discovered filesystem differ. This prevents a new deterministic check source from silently escaping the gate. Explicit commands do not create a second executor: the orchestrator still delegates every check to `run_gate_checks_v1.py`.

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

Deterministic runners never mutate LF operational state. `GATE_CHECK_OBSERVABILITY` detects and explains failures; it is not a `PRE_EKB_GATE` consumer. The consumer is the real `operation_code` whose execution failed.

The productive route is singular:

```text
real operation
  -> GATE_CHECK_OBSERVABILITY
  -> public.lf_operation_gate_check_results
  -> PRE_EKB_GATE
  -> ACT-0001 / governed child dispatch
  -> EJECUCION_SKILL_LF
  -> ACT-0057
  -> ESCRITURA_BASE_CONOCIMIENTO_LF
  -> public.lf_write_pipeline_ekb_v1
  -> EKB receipt/readback
```

`persist_gate_failures_to_ekb_v1.py` remains only as an emit-only compatibility translator for diagnostics and tests. It serializes candidate identity/evidence and explicitly declares:

- productive target: `public.lf_operation_gate_check_results`;
- productive ingress: `public.lf_record_gate_checks_v1`;
- EKB governance: `PRE_EKB_GATE`;
- direct EKB write: forbidden.

The legacy `--write` path is intentionally unsupported. The adapter does not accept database credentials, does not invoke `psql`, and does not call the canonical EKB writer.

Stable candidate identity is still useful for diagnostics and regression, but recurrence authority belongs downstream to the durable ledger plus `PRE_EKB_GATE`, not to this adapter.

## Consumer example

Profile Runtime V3 consumes this capability through `profile_runtime_v3_gate_manifest.json`. `lf-contract-check` may consume the same engine through a consumer manifest whose stable group IDs are selected by its Router `required_controls`; applicability remains Router-owned and must not be reimplemented in the manifest. Consumer manifests are declarations only; the grouping engine remains transversal and reusable by other LF gates.

## Cuándo consumirlo

Cuando una operación o pipeline necesita ejecutar checks determinísticos, producir diagnóstico exacto y exponer evidencia reusable para Claim/Excel sin hardcodear semántica del consumer.

## Cómo consumirlo

1. Resolver `GATE_CHECK_OBSERVABILITY` en `public.lf_activos` y confirmar `ACTIVO / ACTIVE_SHARED_ENFORCEMENT`.
2. Consumir únicamente sus superficies canónicas y conservar operation/consumer identity, source revision y evidencia.
3. No crear una implementación paralela.
4. Cerrar con readback durable y currentness suficiente.

## Superficies canónicas

- `public.lf_operation_gate_check_results`
- `sandbox/lf_contract_gate_test/gate_check_observability/run_gate_checks_v1.py`
- `sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py`

## Fail-closed / límites

Si falta currentness, binding, autoridad o evidencia requerida, bloquear. Este README documenta consumo; no concede permisos ni sustituye contratos/runtime.

## Validación y readback

Ejecutar los gates propios de la capability y del consumer, conservar evidencia exacta y verificar el resultado desde la superficie durable correspondiente.

## No duplicación

Extender esta capability por su owner cuando haga falta; no crear una segunda ruta que resuelva la misma responsabilidad.

## Currentness

Consultar `public.lf_activos` y la superficie runtime vigente antes de cada decisión material. El README debe actualizarse si cambia el contrato de consumo.
