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


## Runbook lunes 12 — checklist ejecutable (NO EJECUTADO)

**Owner/operator:** Cristhian. `[ADMIN]` requires repository/organization admin or Supabase project administrator privileges. Execute strictly in order; record evidence and STOP on any failed gate. No secret value in chat, logs or PR.

- [ ] **0. DB health pre-check — Cristhian [Supabase SQL Editor / read-capable MCP].** Run read-only `SELECT pg_database_size(current_database()) AS bytes, pg_size_pretty(pg_database_size(current_database())) AS size;` and `SELECT 1 AS ping;`. Measure client wall time: must respond in **<5s** and size **<=490 MB** (490 * 1024 * 1024 bytes). **Success:** both pass; log time, size. **STOP:** timeout, >=5s, or >490 MiB. **Rollback:** none (queries only); postpone work and address quota/availability.
- [ ] **1. Catalog verification — Cristhian [read-only DB].** Run:
```sql
SELECT p.oid::regprocedure::text AS signature, p.provolatile, p.prosecdef, md5(p.prosrc) AS body_md5
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='get_lf_repository_governance_bundle_v4';
SELECT extname FROM pg_extension WHERE extname IN ('dblink','pg_net','http') ORDER BY extname;
```
**Success:** precisely one intended function, `provolatile='s'`, `prosecdef=true`, `body_md5` exactly matches MD5 calculated from the `AS $function$ ... $function$` body in `supabase/migrations/20260929195705_lf_repository_governance_tombstone_readmodel_v1.sql`; extension inventory recorded. **STOP:** absent/ambiguous function, mismatch, query failure, or unexpected extension requiring risk adjudication. **Rollback:** none. The previous live query timed out; **not PASS**.
- [ ] **2. Restrict Supabase MCP — Cristhian [admin/operator of each surface].** Configure **project-pinned read-only** MCP endpoint `https://mcp.supabase.com/mcp?project_ref=mhwmirqcgxxukpctffuv&read_only=true` separately in **Claude Code** (project/user MCP server config, `claude mcp list` and config editing), **Codex** (`codex mcp list`; edit selected MCP server URL in local config), **Cursor** (Settings → MCP → Supabase server → edit endpoint; reload), and **claude.ai** (Settings → Connectors → remove unrestricted Supabase connector; add Custom Connector with exact endpoint, reauthorize). Confirm the effective server URL after restart/reconnect; do not keep parallel unrestricted connector sessions. For each, request `apply_migration` against a clearly invalid **no-op probe** and require `TOOL_UNAVAILABLE` / read-only rejection **BEFORE sending any SQL**; do **not** supply executable DDL. **Success:** read-only SELECT succeeds, migration tool is absent or rejected on all 4. **STOP:** any surface can invoke write tool, refuses to pin project, or only relies on text instruction. **Rollback:** restore prior connector settings **only under explicit owner incident authorization**; otherwise STOP without enabling writes.
- [ ] **3a. Create scoped role — Cristhian [Supabase DB admin].** After step 1, review and execute `docs/migrations/f0_credential_separation_readonly_role_DRAFT.sql` **only after substituting password via secure channel and removing comments/placeholder**. Pre-audit inherited EXECUTE, role memberships and actual private schema access. **Success:** `current_user=lf_ci_readonly`, SELECT and governance RPC readback valid, `has_table_privilege(...,'INSERT'/'UPDATE'/'DELETE')=false`, no schema CREATE. **STOP:** role/GRANT conflict or unexpected privileges. **Rollback:** `ALTER ROLE lf_ci_readonly NOLOGIN` / REVOKE grants following approved recovery SQL.
- [ ] **3b. Pooler login — Cristhian [DB admin/operator].** In secure terminal (never print password): `PGHOST=aws-1-us-east-1.pooler.supabase.com PGPORT=5432 PGDATABASE=postgres PGUSER=lf_ci_readonly.mhwmirqcgxxukpctffuv PGSSLMODE=require psql -X -c 'SELECT current_user, current_setting(''default_transaction_read_only'');'` (set PGPASSWORD via secure secret injector, not command line). **Success:** authenticates and SELECT of `supabase_migrations.schema_migrations` works. **STOP:** login/permissions fail; no cutover. **Rollback:** no data change; block role login if needed.
- [ ] **3c. Configure Environments and secrets — Cristhian [GitHub repo ADMIN].** Repo → Settings → Environments → New environment: **`lf-merge-train`**, selected deployment branches **`main`**; create separate **`lf-ig-judge`**, selected `main`, Required reviewers **cristhianlujan** and **paulozterra**, prohibit self-review if available. Add scoped secrets via Environment → Environment secrets: Train postgres/App ID+key; Judge postgres password (separate scope); admission readonly secret in appropriately constrained environment. SSH readback/broker keys only in their own approved environments. **Success:** verify only intended jobs resolve secrets and reviewer gate is enforced (including `pull_request_target`). **STOP:** environment branch matching/required reviewers unavailable, or untrusted execution can bypass the gate. **Rollback:** delete only newly configured secrets/environments (keep existing repo secrets until migration passes).
- [ ] **3d. Activation PR — Cristhian [GitHub maintainer/admin].** Prepare **separate** PR modifying relevant job `environment:` and admission `PGUSER` and secret references, and trusted checkout. Run static tests on exact head; inspect changed workflows. **Success:** no workflow triggered on untrusted branch has a reachable privileged secret, and all existing `if:false` remain off. **STOP:** gate regression or new untrusted execution. **Rollback:** close PR before merge; if already merged, revert through approved normal PR. This Draft #2173 is documentation only.
- [ ] **3e. Merge activation PR — Cristhian [repo maintainer].** Merge **only after** Environment secret availability and protections tested on exact head. **Success:** new `main` has only intended changes. **STOP:** checks fail/pending or base/head drift. **Rollback:** revert PR via ordinary reviewed PR; no forced push.
- [ ] **3f. Consumer verification — Cristhian [repo maintainer + DB operator].** Train: owner-approved canary migration via normal `ready-to-merge` route (never raw MCP); admission: matching PR triggers and green verdict/readback with new role; Judge: manually approve `lf-ig-judge` deployment and verify bounded reversible test (inspect SQL first); M93: `workflow_dispatch` on `main` only with approved non-destructive mode. **Success:** exact-head statuses, no unexpected SQL failures, no secret printing. **STOP:** any check fails or reviewer bypass emerges. **Rollback:** revert activation PR while legacy repo secrets are still present, restore functional paths before deletion.
- [ ] **3g. Remove repo-level privileged secrets — Cristhian [GitHub repo ADMIN].** Settings → Secrets and variables → Actions → Repository secrets → remove old repo-wide privileged DB password, App key, SSH private key and S30 deploy key **only after** each scoped consumer is verified (different destinations). **Success:** no privileged repository-wide copies, Train/Judge/SSH/S30 still work. **STOP:** any unmigrated consumer, unclear deploy-key route or worker dependency. **Rollback:** admin-controlled restore from secret manager **only** after risk approval; never print secrets in PR.
- [ ] **3h. Rotation deferred — Cristhian [DB owner].** **DO NOT rotate postgres on Monday**. Future step requires inventory of Hetzner and other out-of-Actions consumers and approved credential migration.

### Judge weekend option
**Optional short-term containment for the weekend:** with owner approval, temporarily disable the `lf-ig-runtime-candidate-judge` workflow rather than continue executing PR-provided SQL as `postgres`; document checks affected and restore only behind `lf-ig-judge` required-reviewer gate or isolated validation. **Not executed**.


## Update 2026-10-12 — pre-cutover only

- **No cutover/freeze performed.** Supabase is now paid; reported 464 MB and responding. These figures are owner-supplied, not a pre-cutover gate result.
- **Admission LIVE:** `public.get_lf_repository_governance_bundle_v4()`: `provolatile=s`, `prosecdef=true`, `md5(prosrc)=655aafa96c3f4aec1be1f42c5f7bb8a2` (read-only pg_proc SELECT). Repository reference: `supabase/migrations/20260929195705_lf_repository_governance_tombstone_readmodel_v1.sql`. Source body comparison to be independently hashed against latest definition before cutover; do not infer MATCH purely from name.
- **M93 changed:** `.github/workflows/ig-m93-shadow-readonly.yml` on main now includes an additional `psql` step in `prepare` querying `programacion.v_input_governance_representative_cohort_v1`, authenticating as `postgres` with `LF_SUPABASE_DB_PASSWORD`. Both `prepare` and `m93-readonly` must bind `environment: lf-merge-train` if both use privileged secrets. A job environment is not inherited by another job. Proposed diff:
```diff
 jobs:
   prepare:
+    environment: lf-merge-train
     steps:
       # existing psql readback remains unchanged
   m93-readonly:
+    environment: lf-merge-train
```
 Keep `PGUSER=postgres.mhwmirqcgxxukpctffuv` during this cutover; no new role for M93 Monday. Do **not** change these workflows yet.
- **Role A:** `ALTER ROLE lf_ci_readonly SET default_transaction_read_only = on;` already present in proposed SQL. Before activation, verify with `SHOW default_transaction_read_only;` as the new role and `SELECT rolconfig FROM pg_roles WHERE rolname='lf_ci_readonly';`. Role config is defense-in-depth; privilege enforcement and inherited PUBLIC EXECUTE are separate.
- **Security risk:** live catalog SELECT found **26** VOLATILE SECURITY DEFINER functions callable via PUBLIC outside system schemas, all owned by postgres. Candidate action in later phase: inspect each `prosrc` and callers; propose selective `REVOKE EXECUTE ON FUNCTION <signature> FROM PUBLIC` plus role-specific grants in a separate migration, after dependency audit. No REVOKE today. A lexical scanner identified write-token candidates; token absence is **not** proof of no writes, because dynamic SQL and nested RPCs exist. This draft MUST NOT yet be considered a full privilege isolation boundary.

### New Runbook prerequisite before step 0 (documentation only)
- [ ] **0a Backup** — Cristhian [Supabase project admin]: Dashboard → project `mhwmirqcgxxukpctffuv` → Database → Backups. Confirm the **first successful daily backup** exists (timestamp, restoration point and retention); screenshot or record reference. **STOP** if absent/failed. **Rollback:** none; do not perform cutover.
- [ ] **0b Freeze** — Cristhian [GitHub maintainer + agent operators]: book **~1-hour freeze** immediately before credential cutover. Pause Claude/Codex/Cursor/other agents writing PRs/migrations; remove/avoid `ready-to-merge` and `ready-to-reconcile` labels **during the window only by authorized operator**, never from this draft. GitHub repo → Actions → review ongoing runs for LF Migration Merge Train, Independent Change Admission and IG Runtime Candidate Judge; verify **no queued/in_progress runs** for these workflows, and no agent already issuing migration PRs. **STOP** if any run active or unresolved; resume only when safely settled. **Rollback:** postpone cutover, unpause agents; preserve old credentials. The freeze is only documented here; no freeze now.

### Live list: 26 volatile SECURITY DEFINER functions inheriting PUBLIC EXECUTE

Heuristic `body_hint` checks SQL keywords in function source. It does not prove writes or their absence; dynamic SQL and called functions need manual inspection. Every function below has owner `postgres` in the live catalog.

| Schema | Function signature | Owner | Body indicator |
|---|---|---|---|
| lf_ops | `lf_ops.sync_b2b_admin_lf_permission_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_human_decision_authority_policy_guard_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_human_decision_receipt_close_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_human_decision_receipt_guard_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_human_decision_request_guard_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_human_decision_route_policy_guard_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_human_decision_rule_guard_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_human_escalation_policy_guard_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_p0_enforce_actionable_browser_review_v1()` | postgres | NO_WRITE_TOKEN_DETECTED |
| private | `private.fn_lf_p0_enforce_canonical_browser_review_v42_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_pre_ekb_clean_retry_guard_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_pre_ekb_gate_check_autopersist_v1()` | postgres | POTENTIAL_WRITE |
| private | `private.fn_lf_pre_ekb_step_failure_autopersist_v1()` | postgres | POTENTIAL_WRITE |
| programacion | `programacion.fn_guard_input_governance_continuation_currentness_v1()` | postgres | POTENTIAL_WRITE |
| programacion | `programacion.fn_guard_input_parameter_provenance_v1()` | postgres | POTENTIAL_WRITE |
| programacion | `programacion.fn_guard_test_contract_hidden_authority_v1()` | postgres | POTENTIAL_WRITE |
| programacion | `programacion.fn_ig_causal_lineage_receipts_emit_v1(bigint)` | postgres | NO_WRITE_TOKEN_DETECTED |
| programacion | `programacion.fn_ig_timing_receipts_emit_v1(bigint,jsonb,text)` | postgres | NO_WRITE_TOKEN_DETECTED |
| programacion | `programacion.fn_ig_validator_timing_receipt_emit_v1(bigint)` | postgres | NO_WRITE_TOKEN_DETECTED |
| programacion | `programacion.fn_input_archive_source_observation_v1(bigint,jsonb,text,text,text)` | postgres | NO_WRITE_TOKEN_DETECTED |
| programacion | `programacion.fn_input_build_source_manifest_safe_v1(bigint)` | postgres | NO_WRITE_TOKEN_DETECTED |
| programacion | `programacion.fn_input_governance_release_bundle_receipt_v1(text,jsonb)` | postgres | POTENTIAL_WRITE |
| programacion | `programacion.fn_input_stage_gate_summary_known_current_v1(bigint,boolean)` | postgres | NO_WRITE_TOKEN_DETECTED |
| public | `fn_lf_decision_context_asof_record_v1(jsonb,text)` | postgres | POTENTIAL_WRITE |
| public | `lf_router_downstream_authority_execution_insert_v1()` | postgres | NO_WRITE_TOKEN_DETECTED |
| public | `lf_router_downstream_authority_execution_update_guard_v1()` | postgres | NO_WRITE_TOKEN_DETECTED |

### 2026-10-12 final live admission proof

**MATCH VERIFIED** against the exact function body between `$function$` delimiters in `supabase/migrations/20260929195705_lf_repository_governance_tombstone_readmodel_v1.sql` (main): repo `md5=655aafa96c3f4aec1be1f42c5f7bb8a2`; live `pg_proc.prosrc` `md5=655aafa96c3f4aec1be1f42c5f7bb8a2`; `provolatile='s'`; `prosecdef=true`. Achieved by SELECT comparing literal Git source function body against live pg_proc, no DB write. Revalidate exact hash on cutover day in case production changes.

## 2026-10-12 — staged cutover WITHOUT judge (owner decision pending)

**PENDIENTE DE DECISIÓN DEL OWNER:** IG runtime candidate judge. Do not alter judge workflow, isolation design, secret location or reviewer policy in this stage.

**VERIFICADO source dependency:** Train, M93, admission, SSH readback and S30 can be prepared/migrated independently by consumer. However `lf-ig-runtime-candidate-judge` still references the repository-level `LF_SUPABASE_DB_PASSWORD` and **cannot be moved** without owner approval. Keeping this credential at repository level means the privileged lateral route remains open; consequently **F0 global credential isolation is NOT complete and the repository secret MUST NOT be deleted** until judge is resolved.

**Suggested order, not yet authorized for execution:** (1) setup `lf_ci_readonly` with SELECT and reviewed EXECUTE grants; (2) switch admission to that role; (3) isolate Train App/DB credentials to `lf-merge-train`; (4) move both M93 jobs' postgres credential to Train Environment; (5) isolate SSH and S30 keys into legitimate scoped environments after checking dispatch refs; (6) run exact-head functional checks; (7) leave judge unchanged and mark repo-wide postgres password as outstanding exposure; (8) seek separate Cristhian decision for judge and only then remove repo secret. No freeze, configuration change or merge in this document update.


## 2026-10-12 FINAL OWNER DECISION: JUDGE WITHOUT HUMAN REVIEW (supersedes earlier judge proposal)

**VERIFICADO — owner decision relayed in this request.** `lf-ig-judge` Environment: deployment branches `main`, **NO required reviewers**. The earlier reviewer-gated design and "judge pending" notes above are superseded. **No Environment or workflow was changed in this draft.**

**Required workflow two-job design (activation PR only):**
1. `classify-ig-n9-applicability`: no secrets/Environment; trusted base checkout; classify `sandbox/ig_cv/n9_requests/request.json` diff using PR base/head; write `applicable=true|false` and `result=NOT_APPLICABLE|APPLICABLE` as job outputs, fail on untrusted ref/stale base/invalid request. Job has a distinct check name.
2. `run-ig-n9-when-applicable`: `needs: classify-ig-n9-applicability`; `if: needs.classify-ig-n9-applicability.outputs.applicable == 'true'`; **only this job** gets `environment: lf-ig-judge`, `LF_SUPABASE_DB_PASSWORD` and temporary `postgres` login. Preserve existing rollback-only execution. Job may appear `skipped` on nonapplicable PR.
3. `ig-runtime-candidate-judge`: **the sole check-run with exact name `ig-runtime-candidate-judge`**, `needs: [classify-ig-n9-applicability, run-ig-n9-when-applicable]`, `if: always()`, **NO secrets and NO Environment**; return success and emit `RESULT=NOT_APPLICABLE` if classification completed successfully and applicable=false; return success and `RESULT=APPLICABLE_PASS` only if applicable=true and executor result=success; all failures/cancelled/unknown states => nonzero exit. The Train currently filters this exact check-run name at `lf-migration-merge-train.yml:509-514`; finalizer design preserves it for both paths (pending runtime verification).
4. **Never name the optional execution job `ig-runtime-candidate-judge`**. Its skipped conclusion must not replace the finalizer. No current `if:false` should be removed during preparation.

**IMPORTANT:** the finalizer's nonapplicable success is a positive eligibility result, not an unconditional `always()` PASS. Execution with postgres still handles untrusted PR SQL with regex + rollback, **not an isolation boundary**. This risk is explicitly retained temporarily by owner decision.

### Complete credential cutover — single authorized ~1h window (DRAFT / NO EXECUTION)
- [ ] **0. Backup + freeze — Cristhian [Supabase admin + GitHub maintainer]:** Database → Backups: read timestamp/status of a completed base backup, confirm daily/PITR retention and restore eligibility. STOP if no valid completed backup. Agree ~1h freeze; pause agents; confirm no queued/in_progress Train/admission/judge runs in GitHub → Actions for their workflows; do not apply labels. STOP if unsettled.
- [ ] **1. Secrets source — Cristhian [repo/org admin]:** confirm availability of **current postgres password** from secure password vault; **DO NOT reset/rotate it**. Obtain current GitHub App ID/key or create a *new* App private key in GitHub Settings → Developer settings → GitHub Apps → lf-migration-train → Private keys → Generate a private key, preserving existing one until validated. Confirm App installation and permissions. For SSH readback, generate a new SSH key pair on a secure operator computer using `ssh-keygen -t ed25519 -C lf-runtime-readback -f ./lf-runtime-readback` (do not commit private key), install public key on the **restricted** remote account's `authorized_keys` with verified forced-command/permissions before switching; validate host fingerprints for KNOWN_HOSTS. For S30, generate a new key pair likewise and add its **public** key to GitHub repo Settings → Deploy keys → Add deploy key (write checkbox ONLY if the broker actually requires push). Store corresponding private keys in a managed secret vault. SSH/S30 regeneration is an administrator operation, not performed now.
- [ ] **2. Role admission — Cristhian [Supabase DB admin]:** re-read catalog `provolatile='s'`, `prosecdef=true`, md5 `655aafa96c3f4aec1be1f42c5f7bb8a2` against reviewed repo; audit PUBLIC inherited EXECUTE, run separately approved role A DRAFT SQL to create `lf_ci_readonly`, verify pooler login and inability to write. STOP on mismatch. Note `default_transaction_read_only=on` defense-in-depth, not sole guarantee.
- [ ] **3. Environment setup — Cristhian [GitHub repo admin]:** Settings → Environments: create `lf-merge-train` and `lf-ig-judge` with branch policy `main`; **lf-ig-judge: NO required reviewers**; dedicated constrained Environments for SSH readback and S30. Populate secrets in intended Environment(s): Train postgres + App credentials; Judge postgres; Admission readonly; SSH and S30 private keys in their own environments. **STOP** if any privileged credential remains reachable from an unintended job/ref.
- [ ] **4. Activation PR — Cristhian [repo maintainer]:** review separate workflow PR incorporating Environment on BOTH M93 consuming jobs; admission readonly password and role; Train App/DB; two-job Judge execution plus always-on exact-name result check; SSH and S30 destinations. Verify on exact head: no new PR-code execution path, no trigger expansion, preserve disabled PASE paths. Merge only by owner, after prerequisites. **STOP** on pending/failing checks.
- [ ] **5. Canaries — Cristhian [repo maintainer + project admin]:** verify Train using approved safe PR and observed exact-head ledger; admission on applicable and NOT_APPLICABLE; Judge on applicable (temporary postgres; expected success) **and** NOT_APPLICABLE (finalizer exact check-run succeeds with no Environment credentials); M93 manually on main; SSH readback and S30 functionality. Inspect steps/outcomes, no secret values in logs. **STOP** immediately on any failure; revert activation PR and keep original repository secrets during rollback.
- [ ] **6. Final repository secret removal — Cristhian [GitHub repo admin]:** only after ALL six canaries passed, Settings → Secrets and variables → Actions → Repository secrets, remove privileged `LF_SUPABASE_DB_PASSWORD`, GitHub App key, SSH key, S30 deploy key that were successfully rehomed. Confirm no repo-level privileged copies; verify Environment job secret resolution. **STOP** on unknown consumer, loss of access, or lingering PR-executable privileged path. Recovery: restore previous configuration using password vault and revert workflow PR under incident approval.
- [ ] **7. Post-cutover — Cristhian:** confirm main protections and case receipts, unfreeze agents. **NO postgres password rotation in this window** until external worker consumers are migrated and tested.

**Reminder:** dynamic untrusted Judge SQL executed as postgres is still a privilege boundary risk even when an Environment is main-restricted. The Environment separation enables removal of the repo-wide secret, not a security sandbox for its contents.


### Workflow activation PR for owner-approved window
**Actual workflow changes prepared:** [PR #2316](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2316), branch `agent/f0-workflow-activation` (DRAFT). Replace the generic "activation PR" in runbook step 4 with **#2316** and verify that exact HEAD before owner merge. Required Environments are `lf-merge-train`, `lf-ci-readonly`, `lf-ig-judge` (main branch / NO reviewers), `lf-runtime-readback`, and `lf-s30-broker`. **All five must be precreated and configured BEFORE merge**. GitHub auto-creates a referenced nonexistent Environment without restrictions, making a missing precreation a STOP condition.
Premerge: actionlint + static scope test (run 38286164321, SUCCESS); source analysis, no consumer executes the PR version for `pull_request_target` until merge. Postmerge only: exact-head nonapplicable/applicable IG Judge check finalizer, Train, Admission, M93 and SSH/S30 runtime canaries. **NO credential secrets removed until all pass.**
