# M0.2 — Input Governance live inventory v2

Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
Unit/work: `M0.2 / PAULO-101`  
Status: `READY_FOR_CLOSURE`

## 1. Correction of the historical “118 functions” claim

The original plan stated **118 functions + 3 Edge**, but the member list behind that number was not preserved in a canonical source. It cannot be recovered with certainty.

The previous revision of this PR found a deterministic rule that happened to total 118, but that rule mixed Input Governance functions with six boundary functions. Numeric equality is not evidence that the historical list was reconstructed.

This revision therefore makes no “historical 118 reconciled” claim.

## 2. Current observed boundary

The current live model is explicit:

### IG_PROPER — 113 functions

- **109 seed functions** under the M0.3 naming/runtime boundary;
- **4 public IG wrappers**:
  - `public.fn_input_governance_execute`
  - `public.fn_input_governance_safe_autofix_v1`
  - `public.fn_input_governance_curator_materialize_v1`
  - `public.fn_input_governance_validator_validate_v1`

The 109th seed function is:

`programacion.fn_input_source_inventory_lookup_l1_v1(text)`

It was originally direct-DB drift, then reconciled through #1314/#1315 and migration `20260930211500`. Its source-inventory capability is registered separately as candidate asset `PROGRAMACION_INPUT_SOURCE_INVENTORY_L1` (id 352), with `NOT_APPROVED` and the L2 note **“decidir en L2 si lo absorbe T-SOURCE”**.

That capability registration does not silently classify the lookup as a canonical `DB_FUNCTION` identity.

### BOUNDARY — 6 functions

Three transversal dependencies reached by the directed outgoing closure:

- `lf_ops.fn_b2b_backoffice_login_contract(text,text,text)`
- `programacion.fn_v09_sha256_jsonb(jsonb)`
- `programacion.fn_v09_canonical_jsonb_text(jsonb)`

Three direct SQL consumers:

- `public.lf_router_resolve_v1(text,text,text,text,text)`
- `public.lf_rule_exploration_prepare_v1(uuid,text)`
- `public.lf_rule_exploration_materialize_candidate_v1(uuid,jsonb,text,text)`

These six functions are part of the observed boundary but are **not owned by Input Governance**.

Current function scope:

**113 IG_PROPER + 6 BOUNDARY = 119 functions**

The three registered IG Edge runtimes remain separate:

- `EDGE_FN_INPUT_GOVERNANCE_AGENT_V1`
- `EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1`
- `EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1`

Total deterministic receipt: **122 rows**.

## 3. Transitive liveness

The old rule “has a caller ⇒ ACTIVE” was insufficient because a function can be called only by code that itself has no live root.

The v2 script starts from observable roots:

- known Edge/API entrypoints;
- trigger functions;
- functions referenced by constraints;
- functions with callers outside the observed inventory;
- the explicitly exposed candidate lookup `fn_input_source_inventory_lookup_l1_v1`.

It then follows SQL function-call edges transitively, while keeping SHADOW functions non-decisional.

Current function liveness:

| Observational label | Count |
|---|---:|
| ACTIVE_REACHABLE | 90 |
| ACTIVE_ONLY_VIA_UNUSED | 12 |
| ORPHAN | 11 |
| SHADOW | 6 |
| TEST | 0 |
| CANDIDATE | 0 |
| **Functions** | **119** |

These are evidence labels, not canonical lifecycle states.

### ACTIVE_ONLY_VIA_UNUSED — 12

- `programacion.fn_input_context_manifest`
- `programacion.fn_input_evaluation_outcome_summary`
- `programacion.fn_input_governance_bootstrap_classify_v1_cached_v2`
- `programacion.fn_input_governance_bootstrap_classify_v2_cached_v2`
- `programacion.fn_input_governance_field_reference_probe_v1_cached_v1`
- `programacion.fn_input_governance_semantic_probe_v1_cached_v1`
- `programacion.fn_input_governance_semantic_probe_v2_cached_v1`
- `programacion.fn_input_governance_semantic_probe_v3_cached_v1`
- `programacion.fn_input_na_positive_authority_v512_cached_v1`
- `programacion.fn_input_owner_decision_assertions`
- `programacion.fn_input_rebind_assertion_specs`
- `programacion.fn_input_stage_gate_summary`

This label means the function has an internal caller, but no path from a currently-known live root. It is useful for M9/M10 retirement analysis; it is **not** authorization to remove code.

## 4. Registry coverage

The function identity registry is evaluated separately from capability registration.

| Registry status | Count |
|---|---:|
| REGISTERED_FUNCTION_IDENTITY | 116 |
| UNREGISTERED_FUNCTION_IDENTITY | 0 |
| EXTERNAL_OWNER_BOUNDARY | 6 |
| **Total rows including 3 Edge** | **122** |

### Registry closure after #1324

Migration `20260930225000_lf_ig_register_17_function_gaps_v1.sql` extended the existing canonical capability sets and the explicit L1 candidate capability so every one of the 113 IG_PROPER function identities is now represented.

The closure did not create duplicate assets. It:

- expanded Guard from 1 to 13 members;
- added the four public wrappers to their existing functional sets;
- added the L1 lookup as the function member of `PROGRAMACION_INPUT_SOURCE_INVENTORY_L1`;
- added the five code-derived Guard cross-set `DEPENDE_DE` relations;
- verified 0 cross-set call/relation gaps.

The source inventory remains `CANDIDATO / READ_ONLY / NOT_APPROVED`; representation is not approval.

## 5. State authority

M0.2 does not create a parallel lifecycle.

Canonical authority remains:

- policy: `POL-LF-STATE-MODEL`
- version: `v2.0-canonical-lifecycle`
- SHA: `f0d039a7a0f5588494c1f31b27a57ed7de8877a2a191bcd205cd38a6d5b495b3`
- status: `ACTIVE`

In particular:

- `ORPHAN` ≠ remove-ready;
- `ACTIVE_ONLY_VIA_UNUSED` ≠ obsolete;
- the source inventory asset being `CANDIDATO` ≠ approved.

## 6. Transversal inventory observation

A broader `inventory.*` technical-inventory capability has been observed live and overlaps the pilot source inventory. It is **not used as canonical evidence by this M0.2 receipt until its own DB↔Git reconciliation is complete**.

This preserves D-V2.3 (#19529): live objects without Git migration are drift and cannot silently become canonical dependencies.

## 7. Reproducible receipt

Run:

`sandbox/lf_contract_gate_test/input_governance_incremental/m02_live_inventory_v2.sql`

Current inventory SHA-256:

`977178a13c06adec4b6c7033c7dc07519eeb2a63351d3c8a4ba5da2991222ae3`

The script checks:

- 109 seed functions;
- 113 IG_PROPER functions;
- 3 dependency boundary functions;
- 3 consumer boundary functions;
- 119 total functions;
- 3 Edge runtimes;
- transitive liveness counts;
- 17 unregistered IG function identities;
- exact candidate status of `PROGRAMACION_INPUT_SOURCE_INVENTORY_L1`;
- active State Model policy;
- the deterministic receipt fingerprint.

It uses only temporary objects and ends with `ROLLBACK`.

## 8. Closure status

M0.2 remains **IN_PROGRESS**.

The current inventory is now explicit and reproducible, but 17 IG function identities remain outside the canonical function registry. The broader transversal `inventory.*` capability also requires its own drift reconciliation before L2 can decide whether it absorbs the L1 source inventory.

No runtime definition, deploy, promotion or production authorization is changed by this PR.
