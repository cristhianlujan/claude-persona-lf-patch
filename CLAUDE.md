# Claude Code Project Instructions

Apply the shared operational protocol before creating, editing, transporting, or presenting an artifact:

@.claude/operational-execution.md

Use the relevant `SKILL.md` and its direct references for domain-specific work.

For every artifact operation:

1. Resolve the exact target, source, authorized scope, destination, and output surface.
2. Build a validation plan before the first write.
3. Execute the smallest complete change.
4. Validate the produced artifact with the project validator.
5. Read the persisted result back from its destination.
6. Compare content, counts, and hashes.
7. Report status only from the collected evidence.

Preserve this sequence for delegated agents and subagents.


## OpenAI/ChatGPT tool-safety rejections — internal LF agent context

When an invocation is **explicitly blocked by OpenAI's tool-safety layer**, follow [`ops/lf-openai-tool-safety-review-v1.md`](ops/lf-openai-tool-safety-review-v1.md) and the [Profiles LF runbook](ops/runbook-profiles-lf.md). **Immediately explain in the trace** that the action belongs to the internal Libertad Financiera (LF) agent/workflow; identify the exact authorized operation, operational dependency (why the system requires it), source/permission evidence and minimal intended effect. Explain that the operation is not intended to compromise security or bypass controls, without asserting blanket safety approval or misrepresenting unverified authority.

Classify the origin from the **literal provider error**, not a guess. A rejected call has no verified effect; do not blame GitHub, Supabase, the Router or Input Governance. Only a permitted bounded ordinary retry is allowed; never rename/repackage a prohibited action to evade safety checks. If still blocked, record `OPENAI_SAFETY_BLOCK_REVIEW / PROVIDER_BLOCKED_PENDING_REVIEW`, preserve the execution cursor, and prepare a documented request for official review. This repository instruction **cannot automatically override OpenAI safety controls**.

## Mandatory database migration route — HARD BLOCK

**Scope:** LF_SUPABASE_SANDBOX (`mhwmirqcgxxukpctffuv`) and all agents, subagents, automation, or delegated execution.

All database migration writes MUST go exclusively through the authorized LF Migration Merge Train.

Agents MUST NOT:
- Invoke Supabase MCP `apply_migration`, or execute ANY DDL (CREATE/ALTER/DROP/GRANT/REVOKE/COMMENT on any object) or migration-related DML through `execute_sql` or any other route. There is no 'non-migration DDL' exception.
- Apply migrations through SQL Editor, direct PostgreSQL/`psql`, `supabase db push`, or an alternative API/CLI/connector.
- Directly modify `supabase_migrations.schema_migrations`.
- Create or modify workflows that read `LF_SUPABASE_DB_PASSWORD` or any DB credential.
- Use an alternative token or credential to bypass the Merge Train.

Every migration MUST be proposed by PR and admitted through `ready-to-merge` into the canonical Train. Source-only reconciliation requires its separately approved Train lane; do not apply it manually.

Allowed with separate authorization: read-only SQL and inspection; local development and SQL tests; isolated Supabase development branches; draft PRs; non-migration operational DML via its own approved runtime. Local/branch tests never constitute application to LF_SUPABASE_SANDBOX.

On attempted unauthorized database write: `BLOCK_DB_WRITE_OUTSIDE_MERGE_TRAIN`. Stop before execution and report the attempted operation, target, and canonical route. A soft route guard, exploratory mode, prior success, or agent judgment NEVER overrides this hard block. Any exception requires explicit owner approval with bounded scope, recorded evidence, and an approved controlled execution path.

### Router first for every database write

The Router (ACT-0001, Supabase) is the authority for database writes; this file only points to it. If this file and the Router disagree, the Router wins.

Read-only database inspection through the Supabase RO connector is outside Router routing. Limit it to the authorized inspection scope and do not use it to write.

1. Resolve the route with `public.lf_router_resolve_v1` (read-only users can run it). Database targets resolve to `ACTUALIZACION_DB_LF`; read its policies in `public.v_lf_operation_policy_snapshot`.
2. Ask `DB_WRITE_TRANSPORT` for the route:

```bash
python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py \
  --target-type <MIGRATION|DB|FUNCTION|TRIGGER|CAPABILITY> \
  [--migration-path supabase/migrations/<version>_<name>.sql] \
  --router-operation ACTUALIZACION_DB_LF   # or --router-execution-id EXEC-…
```

Without Router passage the answer is `REDIRECT_TO_ROUTER`. With it, the only route is `MIGRATION_VIA_MERGE_TRAIN`. There is no direct executor for agents.

Merge Train checklist:
- one migration file per PR;
- classified name (see below);
- PR not in Draft (`FAIL_TRAIN_DRAFT_PR`);
- required checks green on the exact HEAD;
- no other `ready-to-merge` PR in flight;
- then label `ready-to-merge`. The Train assigns or reassigns the version; do not hand-pick one to dodge a collision.

A write rejected for read-only access or missing permission is intentional. Do not look for another route; use the Merge Train.

You do not need to create the `ACTUALIZACION_DB_LF` execution: the Merge Train reserves it when the PR is labeled, records preflight/patch/verify with real evidence and closes it (`EXEC-DB-TRAIN-PR<n>-<version>-R<run>`). Do not reserve executions by hand for Train migrations.

### Migration naming — check before opening a migration PR

The Merge Train rejects any migration whose name (the filename without the 14-digit version and `.sql`) is not classified in `sandbox/lf_contract_gate_test/migration_source_parity/lf_migration_source_parity_ci_context.py`. A name is accepted only if it:

- starts with a prefix in `MANAGED_PREFIXES` (e.g. `lf_`, `pr93_`, `programacion_…`); or
- matches `STRATEGY_MIGRATION_RE` (`s<N>_…`, e.g. `s30_…`); or
- is listed in `MANAGED_EXACT_NAMES`; or
- starts with a prefix in `CLASSIFIED_EXTERNAL_PREFIXES` or is listed in `CLASSIFIED_EXTERNAL_NAMES`.

Read that file on `main` before naming a migration. Its lists are the authority; this section only points to them.

If the name does not fit, first open a separate code-only PR that registers the exact name (or a family the owner approved) with a positive and a negative test (pattern: `test_f0_train_exact_classification.py`), get it merged into `main`, and only then label the migration PR `ready-to-merge`. The Train reads the classifier from `main`, so registering the name inside the migration PR itself does not work. Never broaden prefixes without owner approval.

The PR check `classify-migration-names` flags unclassified names early, and the Train rejects them before any database write (`FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY`). Do not label an unclassified migration.

### One merge path to `main`: the Train queue

The Train runs one PR at a time (`concurrency: lf-migrations`) and syncs each PR with `main` when it starts. A merge that bypasses the Train while a Train run is in flight moves `main` under it, and the Train's final exact-head merge is rejected (observed 2026-10-13: #2484 merged directly during the Train run of #2485).

Rules for every agent:
- Merge every PR, with or without migrations, by labeling it `ready-to-merge`. Do not merge PRs directly from the web, `gh pr merge`, or the merge API, even when `lf-merge-train/verified` is already green for a code-only PR.
- Before labeling, check that no Train run is `queued` or `in_progress` for a PR you are not handling; if one is, wait for it to finish.
- PRs that change the Train itself (`.github/workflows/lf-migration-merge-train.yml`, `sandbox/lf_contract_gate_test/db_write_transport/**`, guard or parity code) always go through the Train.
- If a Train run fails because `main` advanced (stale head, not a content conflict), update the branch from `main`, wait for green checks on the new head, then remove and re-add `ready-to-merge`. Do not force-push and do not hand-merge.

This is enforced: the route guard (`DIRECT_MERGE_FOR_NON_MIGRATION = False` in `sandbox/lf_contract_gate_test/migration_route_guard/lf_migration_route_guard.py`) no longer publishes `lf-merge-train/verified` for code-only PRs, so the merge button stays blocked until the Train publishes the status right before its own exact-head merge. A PR showing "Expected — waiting for status" is normal: label it `ready-to-merge`.

Emergency (Train itself broken): only the repository admin may temporarily relax the `protect-main` ruleset to merge the Train fix, restore it immediately after, and record both changes in that PR.

### PASE required check, stale bases and classification

PASE is a required check (activated 2026-10-20, #2947). Interpret its red results this way:

- `BLOCK_CI_AUTHORITY_CURRENTNESS:UNKNOWN_FAIL_CLOSED:COMPATIBILITY_ASSESSMENT_MISSING`, or an `Enforce single ordinary PR entrypoint` assertion listing many existing workflows, on a branch that is behind `main` means **stale base**, not a defect in the PR. Do not edit code to silence it. The Train syncs the branch with `main` when it starts; for the RECONCILE lane (which does not sync) update the branch from `main` before labeling `ready-to-reconcile`.
- `FAIL_UNAUTHORIZED_GITHUB_PATH:.github/workflows/<file>` means the workflow path is not admitted: first merge a separate code PR that adds the exact path to `path_admission.github_exact` in `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json` (pattern: #2843, #2942).
#### Classify before you push (changeset manifest)

Before every push to a PR, fetch `origin/main` and run the local PASE plan on the committed candidate HEAD:

```bash
python3 sandbox/lf_contract_gate_test/s28_ci_lane_router/emit_ci_execution_plan_v2.py \
  --repo-root . --head "$(git rev-parse HEAD)" \
  --base "$(git merge-base HEAD origin/main)" \
  --authority-current-revision "$(git rev-parse origin/main)" \
  --event-name pull_request --event-action synchronize \
  --ref-name "$(git branch --show-current)" --output-json /tmp/lf_plan.json
```

A changeset manifest is required only when the PR changes paths without a registered family. If the plan reports `FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:CLASSIFICATION_REQUIRED`, include `sandbox/lf_contract_gate_test/changesets/<solution_ref>.json` in the **same commit** as those paths, starting with the first commit. Map every changed path without a family to an **existing** family in `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json`, and list the manifest itself as `CHANGESET_MANIFEST`. The emitter reads Git objects from HEAD, so commit the manifest before rerunning the plan; do not push while classification remains unresolved. A diff with no changed paths returns `DEEP_SHARED_EMPTY_FAIL_CLOSED`; validate the actual PR diff.

Use one `solution_ref` per PR, matching the manifest filename without `.json`, and list only paths in the PR diff. `FAIL_CHANGESET_MULTIPLE_SOLUTIONS` means multiple manifests are changed in the same PR. `FAIL_CHANGESET_FIXED_FAMILY_OVERRIDE` means the manifest tries to replace a path's registered fixed family. Correct the manifest; do not force a different family. Use only existing families; do not edit the family registry or broaden prefixes/allowlists to pass. If no existing family fits, stop and consult the owner; new-family registration is a separate owner decision.

Example format (replace the example paths and solution reference with the actual PR diff):

```json
{
  "solution_ref": "example-change-v1",
  "paths": {"sandbox/lf_contract_gate_test/example/new_probe.py": "ENGINEERING_CHECKPOINTS", "sandbox/lf_contract_gate_test/changesets/example-change-v1.json": "CHANGESET_MANIFEST"}
}
```

Do not wait for PASE to go red to add the manifest.

PASE is required in `protect-main` with source GitHub Actions (app `15368`) and in `sandbox/lf_contract_gate_test/migration_merge_train/lf_train_required_pre_apply_checks_v1.json`. The admin saved the ruleset on 2026-10-20 at 10:48 America/Lima after #2947 merged. The Train reads its check list from trusted `main`, re-runs checks on the synced PR head and waits for all three: `lf-independent-change-admission`, `ig-runtime-candidate-judge` and `PASE`. Keep ruleset contexts (excluding `lf-merge-train/verified`) and Train pre-apply checks equal; future changes require the owner's decision and a coordinated window. Activation evidence: #2947 (merge `c031265af7b082f9ae26dbf68770994ea9d18ac0`), `PASS_F07_X01_PARITY`, and smoke #2953 (Train run `39452264310`, merge `dcd88821e6f903c9e1ba68a4ab7cab7c02e2da6a`).

## Soft canonical-route guard

Before any repository, database, API, or external-system write, resolve the
canonical operation/route through ACT-0001 or the current governing authority.
Compare that route with the route the agent is about to use. This is a routing
guard, not an additional approval gate.

Run:

```bash
python sandbox/lf_contract_gate_test/canonical_route_guard/canonical_route_guard.py \
  --canonical-route <ROUTE_FROM_ROUTER> \
  --selected-route <ROUTE_ABOUT_TO_BE_USED>
```

Interpret the deterministic result as follows:

- `PROCEED_CANONICAL`: continue without another routing question.
- `ASK_CANONICAL_OR_EXPLORATORY`: before the write, ask exactly one routing
  question: retake the canonical route or deliberately explore the alternative.
  This question is for path correction, not for re-authorizing already approved
  reversible work.
- `PROCEED_EXPLORATORY_NO_CANONICAL_EFFECT`: only when exploration was explicit;
  exploration may continue reversibly but cannot merge, apply production/database
  effects, close the canonical lifecycle, or claim canonical PASS.
- `RESOLVE_CANONICAL_ROUTE_FIRST`: resolve the route before selecting a write path.

A low-level transport such as Git, GitHub, Supabase, or SentinelX is not by itself
an alternate route when it is already executing inside the resolved canonical
operation. The guard compares execution routes, not tool names.

Do not turn this soft guard into a broad deny-list. Existing hard boundaries for
destructive actions, production, spend, irreversible effects, or explicit
contract blocks remain unchanged.

## Governed profile updates

When creating a patch that modifies an existing repository profile under `profiles/**`, route the operation as `ACTUALIZACION_PERFIL_LF` and apply section 15, **Protocolo de pase para actualización de perfiles**, in:

@.claude/operational-execution.md

Supabase remains the canonical authority for the operation contract, execution binding, judge, state **and active pass policy**. The GitHub protocol is a reproducible human-readable projection and does not supersede the active Supabase policy snapshot.

### Dynamic pass-policy snapshot

Every new `ACTUALIZACION_PERFIL_LF` execution is automatically bound by Supabase to the active policy registered for that operation. Read the execution manifest before doing any repository write and require:

```text
manifest.operation_policy_source = SUPABASE
manifest.operation_policy_snapshots.PASS_POLICY.policy_code
manifest.operation_policy_snapshots.PASS_POLICY.policy_version
manifest.operation_policy_snapshots.PASS_POLICY.policy_sha
manifest.operation_policy_snapshots.PASS_POLICY.policy_payload
```

The current policy family is inventoried as `POL-PROFILE-UPDATE-PASS` (`tipo_activo=REGLA`, `subtipo_activo=POLICY_TRANSVERSAL_GOV`) and is resolved through `public.v_lf_operation_policy_snapshot`.

Rules:

- Router and direct profile-update invocations consume the same Supabase policy snapshot.
- Never use a prior PR, branch, chat, example or previous successful profile as the operational source of truth for how to pass.
- Prior PRs are historical evidence only.
- If the required policy snapshot is missing, fail closed with `BLOCK_PROFILE_UPDATE_POLICY_MISSING`.
- The policy snapshot in an execution is immutable.
- On any execution status transition, Supabase compares the bound `policy_sha` with the active policy. A stale SHA must block with `BLOCK_STALE_PROFILE_UPDATE_POLICY`.
- If this file or section 15 disagrees with the bound active `policy_payload`, the Supabase snapshot wins and the divergence must be recorded/remediated as governance drift.

At minimum:

1. query EKB first;
2. resolve exactly one profile and the canonical `ACTUALIZACION_PERFIL_LF` operation;
3. create the canonical execution and read its active policy snapshot before any repository write;
4. create and pass the canonical pre-write execution binding before any repository write;
5. branch from the current exact `main` SHA;
6. write only authorized paths and read them back from the remote branch;
7. require deterministic, semantic, adversarial/holdout and Router/direct evidence as required by the bound policy;
8. require all required workflows to be `SUCCESS` on the exact candidate HEAD;
9. immediately before merge, re-read both `main` and the active operation policy; if either advanced, fail closed and recertify under the current authority without force-push;
10. never create retroactive receipts or auxiliary PRs merely to compare branches;
11. after merge, read back from the new `main`, close the canonical execution with evidence and enrich EKB.

### Single-command update (Router -> profile -> updater, native chat)

When the user says "actualiza el perfil X" (or equivalent), the Router (ACT-0001) resolves the registered action `PROFILE_UPDATE` -> `ACTUALIZACION_PERFIL_LF` through the governed caller `CALLER-GHA-PROFILE-UPDATE-V1`. A native GPT or Claude chat completes it end to end with one command; the user uploads nothing:

1. Read the profile and its failing evidence. Measure first if needed: `python3 scripts/lf_profile_update_run.py ... --dry-run` validates every request offline and writes nothing.
2. Author the candidate as a full profile directory in a scratch folder, in this chat (zero-cost: the native chat is the model).
3. Run `python3 scripts/lf_profile_update_run.py --slug <slug> --target-code <PERFIL-CODE> --candidate-dir <dir> --state <file>`. It opens the execution, measures, records the steps, pushes the branch, runs the compare proof on the exact commit, passes the Merge Train, reads back from `main` and closes. It stops with a stable code if an update is not justified, `main` moved, or a check fails; rerunning resumes from the state file. When it prints `status: BLOCKED`, nothing was opened or written: read `why`, `missing` (what, exact path, the tree hash to bind) and `how`, supply exactly that, and rerun.
4. Do not dispatch workflows by hand, write to the database, or merge directly. Report the final status and the open limits (self-review, single run, pending semantic checks).
5. The update does not change the profile runtime state. Enabling is the separate governed operation `ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF`.

## Governed profile execution — LF native route (mandatory and first)

**DO NOT STOP AT ROUTER HANDOFF.** When a user requests an LF profile execution, a Router `GATE2_DERIVED_PENDING_GOVERNED_ADMISSION` / `HANDOFF_CONTEXT_TO_SELECTED_PROFILE` response means the profile **has not yet received** the request. It is a profile-owned continuation obligation, not a permission request to the user. Read the live EKB first; use `ops/runbook-profiles-lf.md` §6.9 for the proven exact actions.

- **Router responsibility (read-only):** process ACT-0001, preserve the literal original request and validated semantic selection, output the unchanged LF Router V2 context. The Router **does not** invoke a profile, grant execute permission or carry `service_role`.
- **Profile-owned BEGIN:** use the already deployed GitHub Issues / Actions transport. Create an Issue with `{"schema_version":"LF_PROFILE_NATIVE_BEGIN_REQUEST_V1","router_context":<FULL_VALIDATED_GATE2_CONTEXT>,"executor_mode":"GPT_NATIVE"}` (or authorized native mode) and apply the existing label `lf-profile-resume-governed`. The existing workflow passes GitHub OIDC to `lf-profiles-governance-caller-v1`, where the restricted `lf_router_pipeline_context_profile_admit_v2(jsonb,text)` is invoked **with Edge's own service-role credential**, then `lf_profile_execution_begin_from_handoff_v1` starts the **new** `EJECUCION_PERFIL_LF` run. The Edge action is `profile_native_begin_from_context_v1`; no direct profile call or extra Router dispatcher.
- **Never invoke** `lf_router_pipeline_context_profile_admit_v2` through a `supabase_read_only_user` SQL connector. PostgreSQL `42501` on that call is **an expected ACL denial on the wrong caller**, not evidence of missing permission for the canonical OIDC/Edge transport. Never extend the ACL or ask for a key to fix this.
- **Freshness rule:** if user requested a **new** execution, persist and read back a **new execution ID** before claiming delivery. Matching request text, identical hash, or an older `COMPLETED` run may be used as background only. Never substitute it for a new profile invocation. If no new ID exists, report `NOT_EXECUTED` and keep the handoff pending.
- **Profile-owned continuation:** when the runner emits `CONTINUATION_REQUIRED_NOT_COMPLETE`, continue the **same execution ID** via `LF_PROFILE_NATIVE_RESUME_REQUEST_V1` with a source-supported `screen_selection_draft` (if needed), original real GPT-native `profile_output`, and 12-check `semantic_judge_review` V3. This is a nonterminal boundary, even if the Actions job exits nonzero. Do not ask for repeated owner permission; do not manufacture RAW, evidence, model-call receipts, verdicts or provider identities.
- **Judge modes:** the old `INDEPENDENT_SEMANTIC_JUDGE_REQUIRED` phase name does not prohibit the separately governed `CURRENT_CONTEXT_REVIEW` on `read_only/no_write/no_promotion` runs. Set `producer_independence_proven=false`, `reviewer_is_producer=true` and `model_call_count=0` when no separate judge call happened, and enforce all applicable V3 checks and genuine source evidence. If independent review actually occurred and its evidence is verified, retain `INDEPENDENT_SEMANTIC`. Neither mode bypasses material controls.
- **Final readback:** accept only the **same newly created ID** with steps 0–80, `semantic_judge` and `report_output` both `STEP_PASS_WITH_EVIDENCE`, exactly `11/11` clean, `lf_operation_execution.status=COMPLETED`, terminal authority receipt `READY`. Never treat an incomplete run or successful API call as equivalent to actual profile execution.

The live positive example is `EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00`: #3449 BEGIN, #3450 screen selection, #3451 real RAW, #3452 V3; GitHub Actions `41293887404` succeeded, Supabase `11/11 / COMPLETED / READY`. This is proof that OIDC/Edge transport works; it is **not permission to reuse that old run**.

### Separate legacy provenance contracts

The older `PROFILE_EXECUTION_RECEIPT_V1` / `PASS_PROFILE_EXECUTION_PROVENANCE` provenance path applies only when **explicitly demanded by its own active consumer contract**. It must not silently supersede the already-active LF `EJECUCION_PERFIL_LF` native operation, create a second judge/adapter, or block a current-context review already permitted by its live trust validator. In any case, only actual real model RAW and source-bound validation count; fixtures or reconstructed responses never prove execution.

### Certification for governed `EJECUCION_PERFIL_LF` — Supabase readback

Use the [canonical step 70/80 accreditation procedure](docs/profile-execution/ACREDITACION_JUEZ_V3_SUPABASE_RUTA_GOBERNADA_20261101.md) and [Profiles LF runbook](ops/runbook-profiles-lf.md). The persisted server trust validator verifies V3 and original hashes. The operational readback certifies acceptance/transport, **not** an external HTTP trace or independent-model identity that has not been observed. Do not demand a second, external attestation for the same operational persistence. If the current scope's evidence is insufficient, block with exact codes rather than claiming PASS.

## Zero-cost runtime policy

Operational profile execution is `ZERO_COST_ONLY`.

- Do not invoke any API, hosted model, external service, credit pool, subscription add-on, paid inference endpoint or other runtime that can generate incremental monetary charges.
- OpenAI API live execution is explicitly disabled, even when credentials are present.
- The former OpenAI Responses implementation is retained only as quarantined reference/test code and is not an authorized operational provider.
- `run_openai_profile.py` must fail closed with `PAID_PROVIDER_DISABLED_BY_ZERO_COST_POLICY` and must never issue an OpenAI API request.
- An operational provider must be local or otherwise demonstrably zero incremental monetary cost in the current environment before it can be authorized.
- Absence of a zero-cost runtime means `BLOCK_PIPELINE`; it never authorizes a fallback to a paid provider, fixture, expected output, manually reconstructed response or direct downstream generator.

Operational profile execution must reject test adapters/verifiers. A static fixture, expected output, manually reconstructed response or summarized decision is not evidence that the profile executed. If a trusted zero-cost real model runtime or independent attestation verifier is unavailable, fail closed; do not fabricate `profile_output` and do not bypass directly to a generator.
