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
- `PROVIDER_BLOCKED`: the literal response says the tool call was blocked by provider safety checks or equivalent provider policy wording. Record literal response and time. Do not retry the same payload. Continue independent GitHub work and report `PROMPT_BLOCKED_BY_PROVIDER` plus `REQUIERE_INTERVENCION_HUMANA`.

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

## 8. Report
Persist and show:
`FIN — <hora Lima> — duración real — SUPABASE=<OK|SQL_ERROR|CONNECTOR_DENIED|PROVIDER_BLOCKED>`

Report `NO_EJECUTADO` for fields without a current-run tool call. Include priority, pilot CURRENT x/4, profiles/adapters used, P0/P0b/P1/P2/P3/P4 state, completed artifact IDs, benchmark, WAITING/RESUMED, EKB reads/writes, observed errors and recovery, PR/HEAD/CI, safe backlog, remaining safe-work count when observable, cursor, next subtask, and stop classification. Include execution-limit evidence only when an actual limit signal was observed.

Mandatory `PERFILES NUEVOS` section: one line per discovered profile:
`<profile_code> — <estado> — adapter=<estado> — pruebas=<x/y o NO_EJECUTADO> — siguiente=<unidad>`

Use percentages only with an observable denominator. Do not claim global completion without one.
