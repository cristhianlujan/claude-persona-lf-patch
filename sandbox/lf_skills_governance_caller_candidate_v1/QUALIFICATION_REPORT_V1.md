# LF Skills Native Caller — Qualification Report V1

**Lote:** RPCs (4), OIDC, RUN step 0, and native judge coverage. **Scope: candidate-only.** No source-official edits, no GitHub workflow under `.github/`, no DDL, no GRANT, no deploy, no Router changes, no skill admission or A3 execution.

## Exact live sources queried (Supabase, 2026-11-06)

| Source | Observed | Qualification |
|---|---|---|
| `lf_profile_execution_begin_v1` | `fn_lf_operation_reserve_execution_v1` + immediate immutable step 0 on newly reserved profile RUN. MD5 `7a9129c31fd11443c2ed92107bcb7d8b` | Pattern reused, not copied wholesale |
| `fn_lf_operation_reserve_execution_v1` | Validates exact destination/idempotency/request; **does not compare input execution_id, business or full manifest when replaying existing idempotency key**. MD5 `311a0377c43c0698ec12826c1a7f6a78` | Explicit post-reservation reconciliation mandatory, fail with full transaction rollback |
| `lf_record_profile_execution_step_v1` | Calls its own trust validator and delegates to `lf_record_operation_step_core_v1`. MD5 `7cf717887006e278356a716f3fd80182` | Skill-specific wrapper and server trust required |
| `lf_record_operation_step_core_v1` | Shared ordered-step enforcement, judge binding, retry and terminal close. MD5 `fe08a25c8e3c023d7181194d2dfdee0d` | Do not fork; do not let self-reported trust authorize |
| `lf_operation_judges` for `EJECUCION_SKILL_LF` | `JUDGE-EJECUCION-SKILL-LF-v0.1`, `ACTIVE_ENFORCEMENT`, **pass_if=[] and fail_if=[]** | **P0: judge coverage not qualified**; empty pass list can yield a vacuous clean result |
| `lf_operation_step_contracts` + bindings | 9 steps 0..80 all active, but most resolver_refs are `GPT_RUNTIME_WITH_SUPABASE_CONTEXT` | Descriptive rather than native RPC bindings |
| Existing catalog/authority | Zero READY skills with `required_operation=EJECUCION_SKILL_LF`; zero active profile-to-operation authority | **P0:** runtime admission impossible |
| Proposed RPCs | All four absent from `pg_proc` by exact names | **P0:** native execution not installed |
| PR #3624 | A2 Golden independent, DRAFT | Must stay separate from generic caller |

EKB read: `GOV-JUDGE-SCHEMA-FIRST-001`, `PROFILE-JUDGE-INVARIANT-COVERAGE-001`, `PROFILE-UPDATE-SHARED-ENFORCEMENT-REBASELINE-001`, `PROGRAMMING-ANALYSIS-STAGE-SOURCE-ATTESTATION-GAP-001`. Follow schema-first, deterministic-first and evidence lineage.

## Scope and RPC contracts

Machine-readable, *non-executable* qualification: [RPC_CONTRACT_QUALIFICATION_V1.json](./RPC_CONTRACT_QUALIFICATION_V1.json). The handler's RPC names, request keys, status discriminators, and mandatory server checks are enumerated for:

| Proposed function | Purpose | Current state |
|---|---|---|
| `lf_skill_native_preflight_v1` | Server authority: parent, business, Router receipt, skill, catalog, operation, judge, source path | NOT INSTALLED |
| `lf_skill_execution_begin_from_handoff_v1` | Transactional idempotent reserve, invocation pending, immutable step 0, post-write readback | NOT INSTALLED |
| `lf_record_skill_execution_step_v1` | Trust wrapper over existing shared core; no parallel engine | NOT INSTALLED |
| `lf_skill_execution_status_v1` | Actor-scoped readback of parent, invocation, child RUN, source, steps | NOT INSTALLED |

### **Begin** and replay invariant

```text
Edge (verified dedicated OIDC) → server PRE-FLIGHT:
  profile RUN + ACT-0001 receipt + exact business + permitted skill + source
      ↓
Exact Github Main commit/blob; server REVALIDATES before reserve
      ↓
fn_lf_operation_reserve_execution_v1 (existing)
      ├─ NEW → invocation IN_PROGRESS + immutable step 0 in one transaction
      └─ REPLAY → DO NOT INSERT duplicate invocation/step 0
      ↓
Both branches: check returned execution_id, target, parent, input_sha,
caller identity, business, source commit/blob and full manifest;
allow only canonical policy snapshot added by triggers.
      ↓
Transactional readback; any mismatch → rollback + BLOCKED
      ↓
RUN_OPENED_PENDING_EXECUTION (NOT COMPLETED; a3_allowed=false)
```

The default SQL invoker `lf_skill_invoke_v1` remains untouched for existing synchronous SQL skills; **do not** reclassify a business READ_ONLY skill as `WRITE_GOVERNED` to obtain a child RUN.

## OIDC workflow candidate

`OIDC_WORKFLOW_CANDIDATE.yml.txt` is a **non-runnable sandbox template** with `if: false`. It is NOT installed under `.github/workflows/`, does not mint or transmit a token, and must not be used for deployment. Required trust after independent approval: issuer, exact audience, repository ID, Main ref, exact workflow_ref, protected environment, actor/run ID and reviewed workflow SHA; signed JWT verified by Jose at Edge. Caller attributes passed to SQL are **not** self-authenticating DB receipts. Workflow registration must follow the canonical PASE entrypoint policy; do not add a second standard `pull_request` entrypoint.

## Judge qualification — requirement → risk → invariant → evidence → tests

| Requirement/invariant | Risk if missing | Evidence required | Positive | Negative |
|---|---|---|---|---|
| P01 Parent actor+profile exact | Cross-RUN execution | DB readback exact ids | Same actor | Different actor |
| P02 Root business and ACT-0001 receipt agree | LF/SALY mixing | DB parent, handoff, receipt | Same business | Missing or changed business |
| P03 Skill READY/effect binding | Unapproved execution | Catalog and asset + approval | Current accepted asset | Candidate/archived |
| P04 Profile-to-SKILL authority | Privilege escalation | Active authority record | Admitted pair | No authority |
| P05 Main source path and immutable digest | Stale/wrong code | Github Main commit+blob | Exact file | Hash/path drift |
| P06 Idempotency / replay manifest | Reuse wrong context | Reservation and committed RUN | Same digest/replay | Same key, other manifest |
| P07 Step 0 immutable, clean, same RUN | False launch | Step DB row 0 + binding | New+valid replay | Missing/foreign step0 |
| P08 Ordered 10..80 | Skipped gate | Existing core/step readback | Clean predecessors | Step 70 before 60 |
| P09 Deterministic gate precedence | Fake semantic PASS | Server trust with hard fail | All gates clean | Deterministic FAIL + claimed PASS |
| P10 Judge independent source/sha | Fabricated model pass | Native judge receipt, provider/model provenance, exact output hash | Real independent review | Consumer says PASS |
| P11 A2 internal judge before A3 | Incorrect research handoff | Same skill RUN and versioned internal receipt | A2 PASS → A3 | A2 FAIL 3 times |
| P12 Step 80 terminal after all clean | Premature completion | RUN, nine steps, judge and report evidence | Exact PASS closure | Early COMPLETED |

**Gate rule:** catalog `ACTIVE_ENFORCEMENT` with empty `pass_if`/`fail_if` does **not** satisfy coverage. Build the actual invariant-to-evidence matrix, qualify its current judge binding and prove positive/negative tests. A deterministic FAIL must block semantic review; native model/independent judge must be demonstrated, not synthetic.

## Evidence & remaining work

- Local PR candidate handler `node --test handler.test.mjs`: **40/40 PASS**, matching Git blob of published file.
- RPC contract JSON pre-publication structural checks: **26/26 PASS** (these are static checks, not DB integration or native judgment).
- Source-only document and disabled workflow have GitHub readbacks; PASE on the new HEAD must be separately checked.
- **Zero genuine RUNs opened, zero step-0 receipts and zero judge outputs** for `PROGRAMMING_ANALYSIS_LF`.

**BLOCKED** until approved official migrations, OIDC workflow/environment admission, least-privilege RPC EXECUTE grants and genuine exact-HEAD acceptance checks are authorized through existing governance. No deployment and no schema changes in this lot.
