# F0-CREDENCIALES — Cutover DRAFT / NOT APPROVED (2026-10-09)

## Safety
This document is **NOT** an activation. Do not merge until the operator has populated environment secrets and performed independent dry checks. No existing PR or workflow modified. Verified means source inspected; runtime behavior remains unverified.

## 1.1 Key conclusion: do the two active validators write?
| Consumer | Result | Evidence |
|---|---|---|
| Independent change admission | **NO direct persistent DB writes observed**; function-side write effects **PENDING** | `contract_check_self_change_admission/lf_independent_change_admission_carrier_v1.py:325-363`: only `SELECT` incl. `public.get_lf_repository_governance_bundle_v4()`; `:251-272` authenticates postgres; `.github/workflows/lf-independent-change-admission.yml:27,59-64` |
| IG runtime candidate judge | **YES** — executes candidate SQL from PR, possible DDL/DML, and calls stateful Curator/Validator RPCs, although rolls back | `input_governance_runtime_candidate_judge/ig_runtime_candidate_judge_request_v1.py:115-156` loads PR candidate and invokes judge; `ig_runtime_candidate_judge_v1.py:203-253,425-447`: `cur.execute(candidate_sql)`, dispatcher, curator materialize and validator functions, savepoints/rollback. `:465-474` postgres over 6543. |

**Admission guard:** do not migrate to role A until `get_lf_repository_governance_bundle_v4()` body and permissions are verified; any nested DML => NOT read-only. Judge must **not** get role A. An environment secret restricted to `main` remains privileged.

## 1.2 Six workflow dependency matrix
| Workflow/job | Trigger; code trust | Current DB identity | Evidence of queries/effects | Target Monday | Readonly compatibility |
|---|---|---|---|---|---|
| `lf-migration-merge-train/lf-migration-merge-train` and `lf-migration-merge` | pull_request_target; trusted main checkout | postgres, DB_PASSWORD, App ID/KEY | Train `:327,603,623` and apply `:611`; writes migrations | Environment `lf-merge-train` | NO |
| `lf-independent-change-admission/independent-change-admission` | pull_request_target; base.sha | postgres DB_PASSWORD | carrier `:325-363`, SELECT/readback and governance bundle RPC | role A only after function body qualified, otherwise privileged Environment | CONDITIONAL |
| `lf-ig-runtime-candidate-judge/ig-runtime-candidate-judge` | pull_request_target; base.sha, PR SQL data | postgres DB_PASSWORD | judge `:203-253,425-447` PR candidate SQL, stateful RPC, rollback | privileged Environment pending isolated DB redesign | NO |
| `pase-merge-gate/pase-merge-gate` | pull_request_target, if:false | postgres DB_PASSWORD | workflow `:19,69`; PASE carrier requires review | leave off, no environment secret | UNKNOWN, not activated |
| `lf-migration-source-parity-core/migration-source-parity` | workflow_call from `pase.yml:248-259`, if:false; **PR head checkout** | postgres DB_PASSWORD | core `:55-67`; parity `run_migration_source_parity_flow_v1.py:331-343` SELECT ledger | leave off, no secret; on reactivation trusted checkout + read-only | SELECT portion only |
| `ig-m93-shadow-readonly/m93-readonly` | workflow_dispatch (main only by operating practice) | postgres DB_PASSWORD | `:83-91` and `full_pipeline_shadow_runner.py:108-132,138-146,182-280`: SELECT + materialize/validator + temp DDL inside rollback | privileged Environment, main-only dispatch verified by context gate | NO for rollback E2E |

Objects directly read: admission `public.lf_operation_execution`, `public.lf_operation_execution_steps`, `public.v_lf_operation_execution_judge`, function `public.get_lf_repository_governance_bundle_v4()`; parity `supabase_migrations.schema_migrations`; judge `programacion.input_family_assessments`, `programacion.input_readiness_runs`, `programacion.input_validator_chunk_timings` and RPC `fn_input_governance_execute`, `fn_input_governance_curator_materialize_v1`, `fn_input_governance_validator_validate_v1`; M93 additionally `programacion.v_input_governance_representative_cohort_v1`. See corresponding source locations above.

## 1.3 Secrets classification (names only; admin state supplied by owner, NOT verified through GitHub Secrets API)
| Secret | Capability | Consumer | Proposed scope | Open validation |
|---|---|---|---|---|
| LF_SUPABASE_DB_PASSWORD | privileged PostgreSQL postgres: DDL/DML/ledger | Train, admission, judge, inactive PASE/parity, manual M93; possibly VPS workers via own env | only environment `lf-merge-train` | confirm all consumers and test Train |
| LF_MIGRATION_TRAIN_APP_ID / LF_MIGRATION_TRAIN_APP_PRIVATE_KEY | GitHub App installation auth: git merge/status/write depending actual grants | train `:80-91,136-137,731-732` | same environment | confirm App permissions and egress |
| LF_RUNTIME_READBACK_SSH_PRIVATE_KEY + KNOWN_HOSTS | SSH authentication to VPS; command scope depends authorized Unix user | `lf-runtime-independent-readback.yml`, `lf-runtime-independent-readback-dispatch.yml` | dedicated main-restricted environment, NOT automatically Train | inspect remote authorized_keys/ForceCommand, filesystem permissions, sudo; **ability to read DB password UNKNOWN** |
| S30_BROKER_DEPLOY_KEY | Git deploy key, likely push via S30 broker | `profile-driven-screen-generation.yml`; governance contract `s30_self_governance_gate_v1.json` | dedicated broker-only environment, allow protected ref(s) on proof | check `GET /repos/{owner}/{repo}/keys` `read_only` flag and exact key ID (historical references 162872002); verify authorized broker trigger |

Do not confuse known_hosts (host pin; nonsecret) with SSH private key. A deploy key with write can alter git refs within its repository privileges; do not assume read-only.

## 1.4 Outside-Action consumers / scope
Verified sources: `services/profile_runtime_api/scripts/hetzner_queue_worker.py` (`_connect`; VPS worker), `services/profile_runtime_api/scripts/mark_live_reverified.py`, `services/profile_runtime_api/deploy/profile-runtime-worker.env.example` (template only), `sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_queue_worker.py` (Actions queue worker), `sandbox/lf_contract_gate_test/profile_execution_runtime/evaluate_profile_strategy_ab.py`, `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_pooler_fallback.py`, `sandbox/lf_contract_gate_test/pase_merge_gate/pase_merge_gate_carrier_v1.py`, `sandbox/lf_contract_gate_test/migration_source_parity/run_migration_source_parity_flow_v1.py`, `sandbox/lf_contract_gate_test/transversal_assets/test_coverage_debt_guard/test_coverage_debt_guard_v1.py`, `sandbox/lf_contract_gate_test/db_write_transport/lf_migration_exact_apply.py`. Several are libraries/tests; **actual execution environment unknown**, and the supplied estimate of ~24 consumers is not independently exhaustive. Run local grep with scoped outputs before cutover; do not open or print .env values.

## Role B — reversible validation (design only)
Never grant production postgres to untrusted PR SQL. Candidate SQL may contain DDL/DML even if wrapped in rollback. Preferred: ephemeral independent test DB or Supabase branch with isolated credentials, no production secrets or network access. Alternatively a narrow ephemeral schema role only after semantic validation, but it cannot safely test migrations affecting arbitrary schemas. Keep N9 judge in protected Environment as an interim risk acceptance only if owner approves; restrict PR SQL and prevent escape. Do not call it read-only.

## Role C — runtime workers (design only)
Separate identity for `hetzner_queue_worker` and `github_actions_queue_worker`; grant only SELECT/INSERT/UPDATE per identified tables and EXECUTE required by production runtime. Avoid table ownership, schema CREATE, or Supabase migration ledger access. Credentials managed separately from Train, with staged rotation after consumers prove clean. No SQL in this work.

## Environments & events — official behavior
Official GitHub Docs `actions/reference/workflows-and-actions/deployments-and-environments` says deployment branch rule matches `GITHUB_REF`, NOT solely workflow source location. `pull_request_target`: ref is base branch (main when targeted main), hence **can access main environment** from PR event even if submitted by untrusted PR actor, subject to event policy and job code integrity. `push` nonmain blocked by selected main; `push` main allowed; `pull_request` normally uses `refs/pull/N/merge`, blocked by main-only rule; `workflow_dispatch` uses selected branch, so main allowed, other branch blocked; `workflow_call` depends on **caller run GITHUB_REF**, not reusable workflow location. Verification on real repo is PENDING. Restricting to main DOES NOT prevent privileged `pull_request_target` if base=main. Never execute fetched PR code with these secrets. Built-in protection for public repositories regarding pull_request_target may be enforced from 2026-11-02 and must be separately planned.

## Proposed diffs — NOT applied to active workflows
- Train jobs `lf-migration-merge-train` and `lf-migration-merge`: add `environment: lf-merge-train`; keep `LF_SUPABASE_DB_PASSWORD` and App key names, resolved only from environment (repository-level secrets must be removed at final stage).
- `ig-m93-shadow-readonly.yml` job `m93-readonly`: `environment: lf-merge-train`; keep postgres until redesign. Avoid adding Environment on job `prepare` unless it consumes secrets.
- Admission: only after governance bundle function is proved read-only, add `environment: lf-merge-train` or dedicated read-only environment (do **not** assume role A works by merely replacing secret); change password secret to `LF_SUPABASE_DB_READONLY_PASSWORD` and PGUSER in `_pg_env()` to `lf_ci_readonly.<project>`; update `lf_ci_db_target_v1.py:39` contract.
- Judge: `environment: lf-merge-train`; keep postgres, `_connect()` uses port 6543, not 5432; owner must accept risk or isolate candidate SQL off sandbox before enabling further privileged PR runs.
- `pase-merge-gate` and `pase.yml`: preserve `if: false` unchanged, **never give environment**. With repo-level secret deleted, disabled jobs no longer have credentials.
- `lf-migration-source-parity-core`: preserve caller disabled; on future reactivation checkout trusted base/main for executable scripts; checkout candidate into `path: .lf_candidate_data` with credentials disabled, no commands executed inside candidate path, and use read-only account. A bare ref swap is insufficient; parity must compare exact PR blobs as input.
- `lf-runtime-independent-readback`: add dedicated `environment: lf-runtime-readback` at the **consuming job**, review reusable workflow propagation and permissions. Do not route SSH key into unrelated Train.
- `profile-driven-screen-generation`: deploy key to `lf-s30-broker` Environment only when caller/event refs and policy qualified. Changing `environment` on a job using `pull_request` may prevent access as designed.
- **No edits to active workflow YAMLs in draft branch**: this ensures draft push/PR itself cannot trigger newly privileged paths. Implement proposed diffs in a separate activation PR after admin prerequisites.

## Monday 12 execution plan with STOP / rollback
| Step | Preconditions | Pass | STOP | Rollback |
|---|---|---|---|---|
| 1 Inventory live | latest main SHA, secrets names, consumers and deploy SSH audited | matrix signed | unknown privileged consumer | stop, no writes |
| 2 Create role A | approved GRANT SQL + function review | catalog privileges checked | unintended role inheritance | NOLOGIN/revoke |
| 3 Pooler connect | role secret in operator vault | SELECT ledger and privilege readback | auth/permission failure | NOLOGIN + revisit SQL |
| 4 Create environment and readonly secret | authorized admin, **selected branch main** | dry run of eligible caller + secret precedence | environment fails to authorize train pull_request_target or permits off-main | remove new environment secrets/disable job |
| 5 Populate privileged environment secrets | admin verifies exact consumers, retain old secrets temporarily | authorized Train App token/readback, judge & M93 check | any claimant outside main trust boundary | keep old repo secrets, STOP |
| 6 Merge separate activation workflow PR | owner approval and protected exact HEAD | CI PASS / no new untrusted checkout | any new triggered secret path | revert activation PR |
| 7 Run canary Train + admission + judge + M93 | isolated version and approval | exact-head Train, validation receipts | missed check, privilege drift, SQL failure | revert workflow PR, keep prior secret temporarily |
| 8 Remove repo-level privileged secrets | all active consumers proved working | no repo scope secrets, controlled environment reads | unknown dependency | restore prior repo secret only under incident process, accept exposure window |

**NO postgres password rotation Monday.** Future rotation only after VPS/runtime/local consumers audited and drained.

## Open dependencies
1. Function body and inherited EXECUTE of governance bundle not yet audited.
2. Supabase pooler login custom role and RLS on views not tested.
3. Judge and M93 remain privileged until isolated.
4. Actual GitHub environment policies and bypass actors require admin/API readback.
5. SSH remote identity, sudo and DB password file permissions not verified.
6. S30 deploy key write permission unverified.
7. Broader local/.env and 24 consumers need a bounded inventory before deletion.
8. Train exact-head safety and PR-triggered privilege must be assessed separately.
