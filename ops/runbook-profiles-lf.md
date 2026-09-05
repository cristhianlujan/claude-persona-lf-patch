# Profiles LF — automation runbook

## Scope
Operate Profiles LF in this repository and the authorized LF Supabase sandbox. Non-production only. Reconstruct current state from GitHub, Supabase and EKB on every run; conversation context is not operational evidence.

## Evidence
Evidence is tool output produced during the current run. Report unqueried fields as `NO_EJECUTADO`. Record identifiers, receipts, SHAs, CI states and query results only when observed in current-run tool output.

For every technical error, persist or report the exact evidence tuple before classification:
- `target_connection`: provider/project/repository/branch or equivalent observable target, without secrets;
- `raw_request`: exact SQL, command or tool request sent;
- `raw_response`: exact returned error/response text;
- `failure_layer`: `LOCAL_TOOL | CONNECTOR | AUTH | SQL | SCHEMA | DATA | LF_CONTRACT | PROVIDER | UNKNOWN`;
- `recovery_route`: route attempted next and its disposition.

Never replace the literal request/response with a paraphrase when diagnosing a failure.

## 1. Connectivity
First operation: run `SELECT now(), current_database(), current_user;` against the configured LF Supabase sandbox.

Classify the result:
- `OK`: PostgreSQL returned a result; continue.
- `SQL_ERROR`: PostgreSQL returned a query/schema/constraint error; inspect schema/source, correct minimally, retry the affected operation and continue.
- `CONNECTOR_DENIED`: the connector rejected the request before PostgreSQL; record the literal response and time, retry once with a minimal probe, then continue independent GitHub work if still unavailable.
- `PROVIDER_BLOCKED`: the literal response says the tool call was blocked by provider safety checks or equivalent provider policy wording. Record literal response and time. Do not retry the same payload unchanged. Continue through an independent applicable route and independent safe work.

A single failed invocation does not establish a Supabase outage. A PostgreSQL response establishes that the database route is reachable for that invocation.

### 1.1 ERROR_RECOVERY_AND_EVIDENCE_LADDER_V1
This ladder is mandatory for recoverable read/write/tool failures. `ONE_ROUTE_FAILURE != BLOCKER`.

Before any recovery write, run `CANONICAL_TARGET_CHECK` using live source evidence: determine whether the target is current, deprecated, superseded, read-only, or has a `canonical_override`. Do not repair or write a deprecated/non-canonical target when a live canonical target is observable.

Recovery routes are ordered but may be skipped only with a recorded `NOT_APPLICABLE` reason:

**Route A — ORIGINAL**
1. Capture `target_connection`, exact `raw_request`, exact `raw_response`.
2. Classify the failure layer without converting a local/tool rejection into a database outage.
3. Do not retry the identical payload blindly.

**Route B — FOCAL_MINIMAL**
1. Reduce to the smallest equivalent safe probe against the same target/capability.
2. Remove broad search, optional clauses or assumed fields one at a time when that preserves diagnostic value.
3. A successful PostgreSQL response disproves connectivity outage for that invocation.

**Route C — CANONICAL_EQUIVALENT**
1. Read a known-good row/event/view/contract of the same family.
2. Reuse observed schema, registered event type, evidence envelope, canonical view/API or equivalent existing mechanism.
3. Never invent enum/event types, columns, evidence schemas or acceptance fields.

**Route D — INDEPENDENT_AUTHORIZED**
1. Use an independent already-authorized route when available: Supabase CLI/psql/API, GitHub source/readback, catalog/function definition, or another existing canonical interface.
2. Do not introduce credentials, DDL, new tables, deploys, merges or production changes merely to obtain a fallback.
3. If Route D is unavailable, record its exact unavailability rather than pretending it ran.

A unit may become `BLOCKED_CAUSAL` only after every applicable route A-D is `DONE | FAILED_WITH_EVIDENCE | NOT_APPLICABLE` and the causal chain contains exhaustion evidence. `NEXT_ROUTE_IDENTIFIED`, `SCHEMA_READ_PENDING`, `RETRY_PENDING`, `READBACK_PENDING` and `PERSISTENCE_PENDING` are non-terminal.

After a correction:
1. repeat the original operation or the closest semantically equivalent operation if the original was provider-blocked;
2. perform readback;
3. persist the recovery evidence in the canonical durable mechanism (`lf_eventos` when it is the observed Strategy/Profile authority);
4. quick-rescan for the next safe unit and return to the executor if one exists.

Mandatory recovery evidence fields when observable:
`error_id, unit_id, causal_chain_id, target_connection, raw_request, raw_response, failure_layer, canonical_target_check, route_a, route_b, route_c, route_d, correction, retry_request, retry_response, readback, disposition, disposition_evidence`.

Regression invariants:
- A provider/tool safety rejection before PostgreSQL is `LOCAL_TOOL`/`PROVIDER`, not `SUPABASE_OUTAGE`.
- PostgreSQL `42703` is a SQL/schema assumption failure, not connectivity failure.
- PostgreSQL `23514` from LF enforcement is an `LF_CONTRACT` rejection; inspect the live contract and reuse its registered envelope rather than weakening enforcement.
- Discovering a next recovery route is work discovered, not work completed.

## 2. Run continuity
Record `INICIO — <hora Lima> — <prioridad>/<gate>/<tarea>/<subtarea>`.
Locate the Profiles LF run-report mechanism schema-first. If a valid RUNNING execution updated within 24 hours exists for the same scope without a concurrent owner, resume that execution and read back its cursor. Otherwise use the canonical run-opening mechanism. Keep one run report updated with cursor, backlog, waits and next subtask. Never report a finished run without durable evidence.

## 3. EKB
Read focal EKB entries before governed mutations. Search using the observed error/scope/operation/root-cause family/consumer role as applicable; apply current prevention and best-practice records and read back the relevant state. If Supabase access is unavailable, continue independent safe GitHub work rather than making EKB an impossible prerequisite.

Error recovery follows `ERROR_RECOVERY_AND_EVIDENCE_LADDER_V1`: observed error -> literal capture -> failure-layer classification -> canonical-target check -> Route A/B/C/D as applicable -> cause -> minimal authorized reversible correction -> original/semantic retry -> readback -> durable evidence -> continue.

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

For error-recovery causal chains, the work loop does not return to reporting while an applicable Route A-D, retry, readback or persistence step remains pending.

## 6. Benchmark and merge
Preserve the benchmark split and do not use the holdout/hard-repeat sets before the stable set is ready. Report `160 x/160 | 40 x/40 | 20 x/20` only from current evidence. Merge only when applicable reproducible gates are green for the exact head, applicable High/Critical findings are clear, and the expected head SHA has been verified. Non-production only.

## 7. Closure
Before ending, scan P0, P0b, P1, P2, P3, every P4 profile/deferred item, waits, CI, EKB and backlog. If a safe material unit remains executable, execute it and repeat the scan.

For any error causal chain, closure is forbidden while `raw_request/raw_response` are missing for an observed failure, while an applicable recovery route is unattempted, or while retry/readback/persistence is pending. `ONE_ROUTE_FAILURE` and `NEXT_ROUTE_IDENTIFIED` are never stop conditions.

Allowed stop classifications:
- `NO_SAFE_WORK_REMAINING`
- `NONDELEGABLE_AUTHORITY_ONLY`
- `TOOL_ACCESS_DENIED` only after applicable independent recovery routes are exhausted with evidence
- `PROMPT_BLOCKED_BY_PROVIDER` only after applicable independent recovery routes are exhausted with evidence
- `EXECUTION_LIMIT_REACHED` only with an observed runtime/tool limit signal
- `PARTIAL_RUN` when real progress was made and the execution window ended before remaining safe work could be completed

## 8. Report
Persist and show:
`FIN — <hora Lima> — duración real — SUPABASE=<OK|SQL_ERROR|CONNECTOR_DENIED|PROVIDER_BLOCKED>`

Report `NO_EJECUTADO` for fields without a current-run tool call. Include priority, pilot CURRENT x/4, profiles/adapters used, P0/P0b/P1/P2/P3/P4 state, completed artifact IDs, benchmark, WAITING/RESUMED, EKB reads/writes, observed errors and recovery, PR/HEAD/CI, safe backlog, remaining safe-work count when observable, cursor, next subtask, and stop classification. Include execution-limit evidence only when an actual limit signal was observed.

For every observed technical error, include its exact `target_connection`, `raw_request`, `raw_response`, `failure_layer`, attempted routes and final disposition. Do not report a route as attempted without tool evidence.

Mandatory `PERFILES NUEVOS` section: one line per discovered profile:
`<profile_code> — <estado> — adapter=<estado> — pruebas=<x/y o NO_EJECUTADO> — siguiente=<unidad>`

Use percentages only with an observable denominator. Do not claim global completion without one.