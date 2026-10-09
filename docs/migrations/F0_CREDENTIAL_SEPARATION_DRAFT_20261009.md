# F0-CREDENCIALES — Cutover DRAFT / NOT APPROVED (2026-10-09)

## Safety
This document is **NOT** an activation. Do not merge until the operator has populated environment secrets and performed independent dry checks. No existing PR or workflow modified. Verified means source inspected; runtime behavior remains unverified.

## 1.1 Key conclusion: do the two active validators write?
| Consumer | Result | Evidence |
|---|---|---|
| Independent change admission | **NO DB writes via reviewed source**: governance bundle is SQL STABLE SECURITY DEFINER; live identity/hash validation **PENDING** | `contract_check_self_change_admission/lf_independent_change_admission_carrier_v1.py:325-363`: only `SELECT` incl. `public.get_lf_repository_governance_bundle_v4()`; `:251-272` authenticates postgres; `.github/workflows/lf-independent-change-admission.yml:27,59-64` |
| IG runtime candidate judge | **YES** — executes candidate SQL from PR, possible DDL/DML, and calls stateful Curator/Validator RPCs, although rolls back | `input_governance_runtime_candidate_judge/ig_runtime_candidate_judge_request_v1.py:115-156` loads PR candidate and invokes judge; `ig_runtime_candidate_judge_v1.py:203-253,425-447`: `cur.execute(candidate_sql)`, dispatcher, curator materialize and validator functions, savepoints/rollback. `:465-474` postgres over 6543. |

**Admission guard:** repo source `supabase/migrations/20260929195705_lf_repository_governance_tombstone_readmodel_v1.sql` defines `get_lf_repository_governance_bundle_v4()` as `LANGUAGE SQL STABLE SECURITY DEFINER`, with SELECT from `private.lf_repository_governance_bundle_v4`. Target Monday = `lf_ci_readonly` + narrowly scoped EXECUTE. **STOP** until live pg_proc `provolatile='s'`, `prosecdef=true`, `md5(prosrc)` equals hash of reviewed repo body and EXECUTE scope is qualified. The live read was attempted 2026-10-09 but DB returned connection timeout. Judge must **not** get role A. A main-restricted Environment with reviewers is a human gate, not a sandbox for PR SQL.

## 1.2 Six workflow dependency matrix
| Workflow/job | Trigger; code trust | Current DB identity | Evidence of queries/effects | Target Monday | Readonly compatibility |
|---|---|---|---|---|---|
| `lf-migration-merge-train/lf-migration-merge-train` and `lf-migration-merge` | pull_request_target; trusted main checkout | postgres, DB_PASSWORD, App ID/KEY | Train `:327,603,623` and apply `:611`; writes migrations | Environment `lf-merge-train` | NO |
| `lf-independent-change-admission/independent-change-admission` | pull_request_target; base.sha | postgres DB_PASSWORD | carrier `:325-363`, SELECT/readback and governance bundle RPC | role A + EXECUTE on verified SQL STABLE governance function; STOP on pg_proc/hash mismatch | CONDITIONAL |
| `lf-ig-runtime-candidate-judge/ig-runtime-candidate-judge` | pull_request_target; base.sha, PR SQL data | postgres DB_PASSWORD | judge `:203-253,425-447` PR candidate SQL, stateful RPC, rollback | own `lf-ig-judge` Environment with required reviewers Cristhian/Paulo and main-only deployment branch; restricted role B or ephemeral DB C later | NO |
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
- Admission: source confirms governance bundle `LANGUAGE SQL STABLE SECURITY DEFINER`; add `environment: lf-merge-train` with only the readonly password available there (or dedicated readonly environment), change secret to `LF_SUPABASE_DB_READONLY_PASSWORD`, PGUSER in `_pg_env()` to `lf_ci_readonly.<project>`, and `lf_ci_db_target_v1.py:39` contract. **Only after live pg_proc provolatile/prosecdef/md5 check; STOP on mismatch.**
- Judge: **separate** `environment: lf-ig-judge` (deployment branch main, required reviewers @cristhianlujan and @paulozterra); retain postgres provisionally, `_connect()` uses port 6543. Reviewer approval is per deployment job and never proves candidate SQL safe. A PR-targeted run still has access after approval; protect approval against self-review and untrusted ref drift. Longer-term B: scoped non-superuser role only for IG schema operations; C: ephemeral Postgres or isolated Supabase branch. Do not put judge key in general Train environment.
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
| 4 Create environments `lf-merge-train` + `lf-ig-judge` (required reviewers), and readonly secret | authorized admin, **selected branch main** | dry run of eligible caller + secret precedence | environment fails to authorize train pull_request_target or permits off-main | remove new environment secrets/disable job |
| 5 Populate privileged environment secrets | admin verifies exact consumers, retain old secrets temporarily | authorized Train App token/readback and M93; separate `lf-ig-judge` reviewer approval for judge | any claimant outside main trust boundary | keep old repo secrets, STOP |
| 6 Merge separate activation workflow PR | owner approval and protected exact HEAD | CI PASS / no new untrusted checkout | any new triggered secret path | revert activation PR |
| 7 Run canary Train + admission + judge + M93 | isolated version and approval | exact-head Train, validation receipts | missed check, privilege drift, SQL failure | revert workflow PR, keep prior secret temporarily |
| 8 Remove repo-level privileged secrets | all active consumers proved working | no repo scope secrets, controlled environment reads | unknown dependency | restore prior repo secret only under incident process, accept exposure window |

**NO postgres password rotation Monday.** Future rotation only after VPS/runtime/local consumers audited and drained.

## Open dependencies
1. Function body and inherited EXECUTE of governance bundle not yet audited.
2. Supabase pooler login custom role and RLS on views not tested.
3. Judge and M93 remain privileged until isolated. Judge receives **separate reviewer-gated environment** and requires owner acknowledgement of residual SQL-from-PR risk.
4. Actual GitHub environment policies and bypass actors require admin/API readback.
5. SSH remote identity, sudo and DB password file permissions not verified.
6. S30 deploy key write permission unverified.
7. Broader local/.env and 24 consumers need a bounded inventory before deletion.
8. Train exact-head safety and PR-triggered privilege must be assessed separately.


## 2026-10-09 owner correction — enforcement and live probes

**VERIFIED REPO SOURCE:** `supabase/migrations/20260929195705_lf_repository_governance_tombstone_readmodel_v1.sql` defines `public.get_lf_repository_governance_bundle_v4()` as `LANGUAGE SQL STABLE SECURITY DEFINER`, `SET search_path='pg_catalog','private'`, selecting the latest active records from `private.lf_repository_governance_bundle_v4`. This source contains no writes in the function body. Note: the migration's standalone `DO` block is unrelated to function execution.

**LIVE PENDING:** attempted `execute_sql` SELECT against pg_proc and pg_extension, but Supabase returned `Connection terminated due to connection timeout`. No live SQL result, no PASS. Operator reruns read-only queries:

```sql
SELECT p.oid::regprocedure, p.provolatile, p.prosecdef, md5(p.prosrc) AS md5_prosrc
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='get_lf_repository_governance_bundle_v4';

SELECT extname FROM pg_extension WHERE extname IN ('dblink','pg_net','http') ORDER BY extname;
```

The expected MD5 must be calculated from **exact SQL dollar-quoted function body in reviewed Git source**, including newlines; do not hash the entire migration, and do not use a stored hash from prior database snapshots. Compare the function signature too (no overload ambiguity). STOP if absent, multiple overloads, `provolatile <> 's'`, `prosecdef IS DISTINCT FROM true`, or MD5 mismatch. `STABLE` disallows normal DML but SECURITY DEFINER needs owner and function privileges reviewed.

**Judge threat model:** `pull_request_target` receives secrets when job reaches the environment after approval; it reads candidate SQL from PR and executes as postgres inside rollback. FORBIDDEN_SQL/FORBIDDEN_SERVER_IO regex and rollback are not an isolation boundary (SQL identifier quoting/evasion possible). Public-repo logs can expose output; enforce redaction and do not log credentials/SQL secrets. Immediate containment: dedicated `lf-ig-judge` Environment, branch policy `main`, required reviewers `cristhianlujan` and `paulozterra`, `prevent self-review` if supported, and inspect actor/head prior to deployment. No claim of risk elimination.

**Next-phase B:** a non-superuser Postgres login limited to IG schema objects, without CREATE in sensitive schemas, no server/file/network functions and scoped EXECUTE; assess feasibility for dynamic candidate DDL before granting anything. **Next-phase C:** ephemeral Postgres instance or isolated Supabase branch containing fixture/snapshot test data; execute untrusted candidate SQL there, never connected to sandbox privileged secrets. Neither design is implemented here.

### Revised Monday matrix
| Consumer | Monday credential location/identity | Decision |
|---|---|---|
| Merge Train | `lf-merge-train` Environment; existing postgres + App | maintain authorized migration apply |
| Independent admission | read-only secret + `lf_ci_readonly`; grant EXECUTE only after pg_proc signature/MD5 live match | STOP on mismatch |
| IG runtime judge | **`lf-ig-judge` Environment**, postgres provisional, required reviewers Cristhian/Paulo, main branch | explicit reviewer approval, risk remains |
| M93 shadow | `lf-merge-train` Environment, postgres provisional | main-only dispatch guard |
| PASE merge gate / parity-core | disabled `if:false`, no repo-level privileged secret after cutover | fix before reactivation |
| SSH readback and S30 broker | own qualified Environments | do not conflate with Train |
| Hetzner + github_actions_queue_worker | unchanged | rotation deferred |

### Revised Monday stop gates
1. Before admission migration: compare `pg_proc` signature, `provolatile`, `prosecdef`, `md5(prosrc)` against reviewed repo body; **STOP if mismatched or DB connection unavailable**.
2. Before judge deployment: `lf-ig-judge` required reviewers and branch policy proven, including whether job can reach approval from untrusted PR; **STOP** if bypass, self-review or secret outside gate. This is temporary procedural risk reduction only.
3. Extension readback: check `pg_extension` for `dblink`, `pg_net`, `http`; **STOP and review** if present, especially possible network exfiltration paths, rather than assuming absence implies safety.
4. Probe selected jobs before deleting repository secrets; keep rollback via workflow revert and previously authorized secret restoration procedure. Never rotate postgres Monday.
