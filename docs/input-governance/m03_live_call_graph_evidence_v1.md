# M0.3 — Input Governance live call graph evidence v1

Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
Unit/work: `M0.3 / PAULO-102`  
Status at correction: `IN_PROGRESS`  
Purpose: reconstruct the real call graph across SQL, Edge, triggers, constraints and external consumers without changing runtime behavior.

## 1. Scope and boundary

The reproducible SQL evidence is:

`sandbox/lf_contract_gate_test/input_governance_incremental/m03_live_call_graph_v1.sql`

Current live DB scope:

- 108 seed functions:
  - the 96-function IG surface already mapped by PRs #1307/#1308;
  - 12 additional `programacion.fn_guard_input_*` functions.
- direct SQL neighbors of those seed functions;
- direct incoming consumers of `public.fn_input_governance_*` wrappers, so rule-exploration consumers remain explicit M0.3 boundary nodes.

Total live DB graph scope: **117 functions**.

This does **not** claim that the historical M0.2 baseline of 118 functions has been reconstructed. The 117-vs-118 delta remains M0.2 work.

## 2. Call extraction and schema resolution

The corrected extractor uses `pg_proc.prosrc` (function body), not the `CREATE FUNCTION ...` header from `pg_get_functiondef`.

For calls matching `fn_name(`:

- explicit `public.`, `programacion.` or `lf_ops.` qualification is preserved and resolved only to that schema;
- unqualified calls may resolve by function name only when no schema is explicit;
- self edges are excluded;
- current runtime inspection found no unqualified ambiguous `fn_*` calls across these three schemas.

The previous head joined only by `proname`. On the fixed 117-function scope that produced exactly **7 false internal edges**:

1. `programacion.fn_input_governance_curator_materialize_v1 -> public.fn_input_governance_curator_materialize_v1`
2. `programacion.fn_input_governance_execute -> public.fn_input_governance_execute`
3. `programacion.fn_input_governance_safe_autofix_v1 -> public.fn_input_governance_safe_autofix_v1`
4. `programacion.fn_input_governance_validator_validate_v1 -> public.fn_input_governance_validator_validate_v1`
5. `programacion.fn_lf_router_input_governance_resolve_v1 -> public.fn_input_governance_execute`
6. `public.lf_rule_exploration_materialize_candidate_v1 -> programacion.fn_input_governance_execute`
7. `public.lf_rule_exploration_prepare_v1 -> programacion.fn_input_governance_execute`

The real edge
`public.lf_rule_exploration_materialize_candidate_v1 -> public.fn_lf_operation_reserve_execution_v1`
is preserved. The call is schema-qualified and the target exists only in `public`.

## 3. Deterministic graph receipt

Current corrected receipt:

- seed functions: **108**
- scoped DB functions: **117**
- in-scope SQL edges: **262**
- outgoing SQL boundary edges: **2**
- incoming SQL boundary edges: **33**
- trigger bindings: **21**
- constraint bindings: **5**
- functions with no SQL caller/trigger/constraint binding: **21**
- functions with no `fn_*` SQL callee: **18**
- canonical graph SHA-256:
  `a70a01d28cf558bb9966208b0f12156cba57a9a33d7e347e0f63ae57b81d4e30`

The canonical hash includes scope members, SQL edges, trigger bindings and constraint bindings. Trigger event arrays are emitted in the detailed presentation but intentionally do not alter the binding fingerprint.

Empty caller/callee arrays are preserved as graph facts. M0.3 does not relabel them as ORPHAN, TEST, SHADOW or ACTIVE; that classification belongs to M0.2.

## 4. Assessment persistence → trigger graph

Direct runtime inspection finds **8 SQL writers** that INSERT/UPDATE `programacion.input_family_assessments`:

- `fn_input_governance_bootstrap_materialize_v1`
- `fn_input_governance_bootstrap_materialize_v2`
- `fn_input_governance_curator_rebind_v1`
- `fn_input_governance_recurate_source_stale_v1`
- `fn_input_governance_recurate_v2`
- `fn_input_governance_bootstrap_validate_v1`
- `fn_input_governance_validate_v2`
- `fn_input_governance_validator_rebind_v1`

The table currently has **11 BEFORE triggers**. Therefore this path is represented explicitly as:

`Curator/Validator writer -> input_family_assessments -> trigger -> fn_guard_input_* -> downstream callees`

This is a table-mediated edge, not a direct SQL function call. It is the follow-up recorded in `lf_eventos #19496`.

The detailed SQL output preserves **all events** on each trigger. Five provenance triggers currently fire on both `INSERT` and `UPDATE`; they are emitted as `events: ["INSERT","UPDATE"]`, not collapsed to the first matching event.

## 5. Core Edge sources

Exact main-branch source blobs used for M0.3:

| Runtime | Git path | blob SHA | Direct calls |
|---|---|---|---|
| Agent | `supabase/functions/input-governance-agent-v1/index.ts` | `2140c07b67a36cb93c89d056f8180f4736de2eca` | RPC `fn_input_governance_execute`, RPC `fn_input_governance_safe_autofix_v1`, runtime Curator, runtime Validator |
| Curator | `supabase/functions/input-governance-curator-v1/index.ts` | `6e5ccf8f817d575183bc619b312016b7e653aeab` | RPC `fn_input_governance_curator_materialize_v1` |
| Validator | `supabase/functions/input-governance-validator-v1/index.ts` | `5b53db7633da386770a0b9dd6ed5bc12bfcf0bd3` | RPC `fn_input_governance_validator_resume_context_v1`, RPC `fn_input_governance_validator_validate_v1` |

These are source edges only; this artifact does not deploy or alter any Edge Function.

### Public wrapper inventory follow-up for M0.2

The Edge surface enters through five `public.fn_input_governance_*` functions.

Already represented in the current IG function assets:

- `public.fn_input_governance_validator_resume_context_v1`

Still requiring explicit M0.2 inventory/canonical treatment:

- `public.fn_input_governance_execute`
- `public.fn_input_governance_safe_autofix_v1`
- `public.fn_input_governance_curator_materialize_v1`
- `public.fn_input_governance_validator_validate_v1`

These four are wrappers/entrypoints, not additional internal engines.

## 6. Validator runtime paths

The current Validator Edge has three observable control-flow paths relevant to the call graph:

1. **Fresh identity path**  
   `resume_context_v1 -> resume_allowed != true -> new validator identity -> validator_validate_v1`.

2. **Resume path**  
   `resume_context_v1 -> resume_allowed = true -> reuse validated identity -> validator_validate_v1`.

3. **Chunk continuation path**  
   `validator_validate_v1 -> VALIDATOR_CONTINUE_REQUIRED -> validator_validate_v1` again, up to `MAX_VALIDATION_CHUNKS=8`; terminal success is `COMPLETED` or `NOOP_COMPLETED`.

This is a runtime path map only. It does not claim closure of independent-oracle requirements or AUD-045.

## 7. External consumers

### Profiles Edge caller

Source:
`supabase/functions/lf-profiles-governance-caller-v1/index.ts`  
blob SHA: `76999acf9fe19d3f753e59361696bd6f4ccce1ee`

Direct edge:

`lf-profiles-governance-caller-v1 -> input-governance-agent-v1`

This is already persisted as `lf_activo_relaciones.id=127`.

### Profiles batch worker

Source:
`sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_batch_queue_worker.py`  
blob SHA: `5f9b94fbb420f06a635b1a142f18096be8f5ec0d`

Direct edge:

`github_actions_batch_queue_worker.py -> programacion.fn_lf_router_input_governance_resolve_v1`

The worker also fail-closes with `BLOCK_INPUT_GOVERNANCE` / `BLOCK_INPUT_GOVERNANCE_RECEIPT_INVALID`.

The worker is not yet a canonical `lf_activos` asset. Its registry relation belongs to the N-1 closeout after this graph work.

### Adapter consumers

Existing registry evidence:

- relation 128: `ADAPTER-LF-SHELL-PROFILE-20260827 -> EDGE_FN_INPUT_GOVERNANCE_AGENT_V1` as `CONSUME_TRANSITIVAMENTE`
- relation 129: `ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827 -> EDGE_FN_INPUT_GOVERNANCE_AGENT_V1` as `CONSUME_TRANSITIVAMENTE`

These are transitive receipt dependencies and do not claim direct Agent calls.

## 8. SQL consumer entrypoints

The corrected schema-aware graph confirms:

- `public.lf_router_resolve_v1 -> programacion.fn_lf_router_input_governance_resolve_v1`
- `public.lf_rule_exploration_prepare_v1 -> public.fn_input_governance_execute`
- `public.lf_rule_exploration_materialize_candidate_v1 -> public.fn_input_governance_execute`
- `public.fn_input_governance_execute -> programacion.fn_input_governance_execute`

The two rule-exploration functions are retained as controlled second-hop incoming consumers of a public IG wrapper, because M0.3 explicitly covers external consumers.

## 9. Closure status

What this PR can establish:

- reproducible live SQL graph with explicit callers/callees for every one of the 117 scoped DB functions;
- schema-aware call resolution with function headers excluded;
- Edge source edges;
- trigger and constraint bindings, including all trigger events;
- Profiles caller and batch-worker edges;
- the current Validator control-flow paths;
- a fail-closed graph fingerprint.

What it must **not** establish yet:

- M0.2 historical baseline 118 = current 117;
- lifecycle classification of caller/callee boundaries;
- canonical asset ownership for the 12 additional guard functions;
- canonical registration of the four missing public IG wrappers;
- N-1 DONE before the Profiles batch worker becomes a canonical asset and relation;
- Validator independence / oracle closure.

Accordingly, M0.3 remains **IN_PROGRESS** after this evidence PR until M0.2 resolves the historical inventory/classification and any required registry rows are reconciled.
