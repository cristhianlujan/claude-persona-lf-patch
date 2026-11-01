# Profiles LF — automation runbook

## Scope
Operate Profiles LF in this repository and the authorized LF Supabase sandbox. Non-production only. Reconstruct current state from GitHub, Supabase and EKB on every run; conversation context is not operational evidence.

## Evidence
Evidence is tool output produced during the current run. Report unqueried fields as `NO_EJECUTADO`. Record identifiers, receipts, SHAs, CI states and query results only when observed in current-run tool output.

## 1. Connectivity
First operation: run `SELECT now(), current_database(), current_user;` against the configured LF Supabase sandbox.

Classify the result:
- `OK`: PostgreSQL returned a result; continue.
- `SQL_ERROR`: PostgreSQL returned a query/schema/constraint error; inspect schema/source, correct minimally, retry the affected operation and continue.
- `CONNECTOR_DENIED`: the connector rejected the request before PostgreSQL; record the literal response and time, retry once with a minimal probe, then continue independent GitHub work if still unavailable.
- `PROVIDER_BLOCKED`: classify by the literal sender; do not attribute an OpenAI safety block to GitHub, Supabase or Router. For an **explicit OpenAI tool safety block only**, follow [`lf-openai-tool-safety-review-v1.md`](lf-openai-tool-safety-review-v1.md): preserve exact error, prepare an evidence-backed legitimacy explanation, and use official support review when appropriate. Do not retry the same blocked payload in a loop or bypass platform controls; resume only after normal authorization and successful readback. Record `PROMPT_BLOCKED_BY_PROVIDER` and `PROVIDER_BLOCKED_PENDING_REVIEW` when unresolved. Other providers' errors retain their own diagnosis.

**Mandatory LF internal-agent context on an explicit OpenAI safety rejection:** after verifying the exact error is emitted by OpenAI, state in the current trace that this is an **internal LF agent**, identify the authorized action, prove why that action is necessary to operate/verify the system, and describe why the requested effects are bounded and do not seek to circumvent security. Record `OPENAI_SAFETY_BLOCK_REVIEW`; attach only verifiable references (operation/PR/asset, no tokens). Distinguish `POSSIBLE_FALSE_POSITIVE` from cleared/approved. **Do not declare the rejected call executed, do not invent a safety exemption, and never bypass a real block.** Follow the existing [safety review protocol](lf-openai-tool-safety-review-v1.md) for retries or official review; this is not a new Router/IG stage.

A single failed invocation does not establish a Supabase outage. A PostgreSQL response establishes that the database route is reachable for that invocation.

## 2. Run continuity
Record `INICIO — <hora Lima> — <prioridad>/<gate>/<tarea>/<subtarea>`.
Locate the Profiles LF run-report mechanism schema-first. If a valid RUNNING execution updated within 24 hours exists for the same scope without a concurrent owner, resume that execution and read back its cursor. Otherwise use the canonical run-opening mechanism. Keep one run report updated with cursor, backlog, waits and next subtask. Never report a finished run without durable evidence.

## 3. EKB
Read focal EKB entries before governed mutations. Search using the observed error/scope/operation/root-cause family/consumer role as applicable; apply current prevention and best-practice records and read back the relevant state. If Supabase access is unavailable, continue independent safe GitHub work rather than making EKB an impossible prerequisite.

Error recovery: observed error -> focal EKB when reachable -> schema/source inspection -> cause -> minimal authorized reversible correction -> targeted retry -> readback -> continue.

## 4. Work priority
### P0 — Input Governance
Read the live `INPUT_GOVERNANCE_EXECUTION_CONTRACT`. Establish CURRENT input readiness for ONB_002, ONB_003, ONB_004 and HOME_002 through the canonical mechanism. Use `MANUAL` only when allowed by the live contract. CURATING/VALIDATING blocks only that unit; execute another safe unit and recheck later.

### P0b — Pilot
As soon as all four screens are CURRENT, reread `public.lf_activos_demo` for `CLIENT_SCREEN_FACTORY_PILOT_001` and advance the pilot with existing profiles and adapters resolved from the live chain. Do not infer new profiles for the pilot and do not wait for lower-priority work.

### P1 — Throughput
Work differentially from the durable cursor and freshness delta. Reuse stable snapshots and batch safe work. Revalidate unchanged gates only when necessary. For C3/PR341 perform only the freshness needed for the current decision. Prefer units that reduce real backlog.

### P2 — Durable continuity
Inspect the live run/closure contract. Use its canonical checkpoint mechanism when it supports backlog and cursor persistence. Otherwise persist the identified gap and continue safe work.

### P3 — Runtime dispatch
When higher priorities have no immediately executable unit, advance `PROFILE-RUNTIME-DISPATCH-001` through its canonical lifecycle and observe queue-to-comment, comment-to-workflow, runner preparation and execution timing when available. Primary outcome is SUCCEEDED. Compute distribution metrics only with a real denominator. Reopen prior regressions only with new reproducible evidence.

### P4 — New-profile inventory and active deferred work
Reconstruct the canonical inventory of required/new profiles from Supabase and GitHub rather than from conversation context.

For every identified profile record:
- canonical profile id/code and name
- originating requirement
- current state
- required adapter and adapter state
- applicable creator/executor
- pending gates
- tests completed/pending
- applicable benchmark state
- observed blocker, if any
- next safe material unit
- current-run evidence

Use one state: `NOT_STARTED | IN_PROGRESS | WAITING | READY_FOR_TEST | TESTING | READY | QUARANTINED`.

Do not collapse multiple profiles into a generic “new profiles” entry. Keep other deferred items individually visible, including parity/F05, Gate0, benchmark work and noncritical debt. Changes to quarantined creator paths must follow their live governance contract.

Any new profile with an executable safe unit enters the selector when higher-priority work has no executable unit. The final remaining-work scan must inspect each profile individually. Profiles LF is not closable while a profile required by current scope is missing from the authoritative inventory assessment.

## 5. Work loop
While a safe material unit is executable:
1. select the highest-priority unit;
2. execute it;
3. verify/read back;
4. update durable cursor/state when supported;
5. scan remaining work;
6. select the next unit.

A wait blocks only its own unit. Measure progress by verifiable artifact IDs and durable state changes, not by an arbitrary batch count. Continue while a safe material unit remains executable in the current run.

## 6. Benchmark and merge
Preserve the benchmark split and do not use the holdout/hard-repeat sets before the stable set is ready. Report `160 x/160 | 40 x/40 | 20 x/20` only from current evidence. Merge only when applicable reproducible gates are green for the exact head, applicable High/Critical findings are clear, and the expected head SHA has been verified. Non-production only.

## 7. Closure
Before ending, scan P0, P0b, P1, P2, P3, every P4 profile/deferred item, waits, CI, EKB and backlog. If a safe material unit remains executable, execute it and repeat the scan.

Allowed stop classifications:
- `NO_SAFE_WORK_REMAINING`
- `NONDELEGABLE_AUTHORITY_ONLY`
- `TOOL_ACCESS_DENIED` with the observed connector literal
- `PROMPT_BLOCKED_BY_PROVIDER` with the observed provider-block literal
- `EXECUTION_LIMIT_REACHED` only with an observed runtime/tool limit signal
- `PARTIAL_RUN` when real progress was made and the execution window ended before remaining safe work could be completed

## 7.1. Canonical certification — profile semantic judge (70) and report (80)

**Required for `EJECUCION_PERFIL_LF` closures, even when GitHub Actions reports SUCCESS.** Apply [the approved Supabase accreditation procedure](../docs/profile-execution/ACREDITACION_JUEZ_V3_SUPABASE_RUTA_GOBERNADA_20261101.md). Do not invent a separate reviewer, transport, gate or external certification receipt. The accepted operational certificate is the **live readback in Supabase**, for the same `execution_id` and the already registered V3 result.

1. Check that the producer RAW and deterministic validation are already persisted at steps `execute_profile` (50) and `output_validate` (60) with `STEP_PASS_WITH_EVIDENCE`.
2. Read `public.lf_operation_execution_steps` where `step_id='semantic_judge'` (70). Require `STEP_PASS_WITH_EVIDENCE`, `evidence_ref` pointing to the governed Actions artifact, `recorded_by_rpc=lf_record_profile_execution_step_v1`, `trust_validation.valid=true`, and `candidate_sha256` / `scope_packet_sha256` equal to the original hashes in steps 50/40. Inspect the V3 receipt, including the 12 checks and the `NOT_TESTED/not_applicable/ROUTER_ONLY` exception for check 11 when appropriate.
3. Read step `report_output` (80) and the run. Require step 80 `STEP_PASS_WITH_EVIDENCE`, run `COMPLETED`, **11/11 clean steps** and the existing terminal authority receipt `READY`. If any is absent, keep `IN_PROGRESS / NOT_CERTIFIED` and continue only through the governed procedure. Do not ask for an authorization already granted.
4. Report separately (a) **verified operational registration/closure** versus (b) a claimed underlying model/provider call. The accepted `model_call_count=1` / `producer_independence_proven=true` fields in the V3 receipt are part of the governed record; Supabase is not a network trace to the model provider. Do not require an extra external log to certify operational closure, and do not fabricate a new V3 result.

Read-only reference query, replace `<EXECUTION_ID>` with the run actually verified:

```sql
select e.execution_id, e.status as run_status, s.step_order, s.step_id,
       s.status as step_status, s.evidence_ref,
       s.evidence_payload->>'recorded_by_rpc' as recorded_by_rpc,
       s.evidence_payload#>>'{trust_validation,valid}' as trust_valid,
       s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}' as candidate_sha256,
       s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}' as scope_packet_sha256,
       s.evidence_payload#>>'{semantic_judge_result,model_call_count}' as declared_model_call_count,
       s.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}' as declared_independence
from public.lf_operation_execution e
join public.lf_operation_execution_steps s using (execution_id)
where e.execution_id = '<EXECUTION_ID>'
  and s.step_id in ('semantic_judge', 'report_output')
order by s.step_order;
```

Read this together with steps 40, 50 and all 11 step statuses; check the `lf_profile_execution_terminal_authority_receipt_v1` result through its authorized read path. Failing EKB `PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001` remains independent of a successful single-run closeout.

## 8. Report
Persist and show:
`FIN — <hora Lima> — duración real — SUPABASE=<OK|SQL_ERROR|CONNECTOR_DENIED|PROVIDER_BLOCKED>`

Report `NO_EJECUTADO` for fields without a current-run tool call. Include priority, pilot CURRENT x/4, profiles/adapters used, P0/P0b/P1/P2/P3/P4 state, completed artifact IDs, benchmark, WAITING/RESUMED, EKB reads/writes, observed errors and recovery, PR/HEAD/CI, safe backlog, remaining safe-work count when observable, cursor, next subtask, and stop classification. Include execution-limit evidence only when an actual limit signal was observed.

Mandatory `PERFILES NUEVOS` section: one line per discovered profile:
`<profile_code> — <estado> — adapter=<estado> — pruebas=<x/y o NO_EJECUTADO> — siguiente=<unidad>`

Use percentages only with an observable denominator. Do not claim global completion without one.
