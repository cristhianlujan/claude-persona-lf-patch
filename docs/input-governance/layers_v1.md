# M1.1 — Input Governance Layer Decomposition

**Plan:** `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
**Unit:** `M1.1` / `PAULO-116` / L4  
**Purpose:** freeze a single-owner layer model for current Input Governance code without changing runtime behavior.  
**Source M0.5:** `docs/input-governance/responsibility_block_map_v1.json` at merge `e3a08f2ba27fbe7ecd2d85a4f81778d3a0c09200`.  
**Runtime change:** none.  
**Production change:** none.

## Current universe readback

M0.2 closed with 113 IG-proper functions. The current readback has 112 because `programacion.fn_input_source_inventory_lookup_l1_v1(text)` and its legacy L1 asset were deliberately retired. The current liveness graph still contains **90 ACTIVE_REACHABLE IG-proper functions**.

The canonical function-set registry has no duplicate member identities. The layer assignment below covers **90/90 active functions**, with **0 unassigned** and **0 non-single assignments**.

Assignment SHA-256 over ordered `{identity,set_code,layer}` rows:

`0de2ca1cf31cea3d0a260d957faf4a1ba56d2f0ea29a9ea2a51acefa61312806`

Layer totals for the 90 active functions:

| Layer | Active functions |
|---|---:|
| Core | 15 |
| Semantic | 28 |
| Readiness Policy | 8 |
| Orchestration | 20 |
| Evidence | 4 |
| Persistence | 15 |
| **Total** | **90** |

The three registered Edge runtimes (`Agent`, `Curator`, `Validator`) are orchestration entrypoints and are tracked as assets, not included in the 90 database-function count.

## Layer contracts

All layers remain accountable to the existing `LF_GOVERNANCE` owner. The names below are logical responsibilities, not new registry assets.

### 1. Core

**Owns:** deterministic canonical reads, canonical graph/context, source/authority resolution, deterministic bootstrap facts and deterministic helpers.

**MUST** be deterministic for the same governed inputs and explicit version context.  
**MUST** return facts or deterministic derived facts, not stage verdicts.  
**MUST NOT** perform durable writes.  
**MUST NOT** decide semantic meaning that requires domain interpretation.  
**MUST NOT** orchestrate Curator/Validator execution.

### 2. Semantic

**Owns:** domain interpretation, assertion evaluation/templates, semantic probes/resolvers and security/domain expectations.

**MUST** consume canonical facts/refs and return semantic resolutions.  
**MUST** expose uncertainty rather than silently converting ambiguity to readiness.  
**MUST NOT** compute final stage readiness.  
**MUST NOT** persist runs/assessments/gaps directly.  
**MUST NOT** depend on Curator conclusions as authority.

### 3. Readiness Policy

**Owns:** applicability, currentness/invalidation policy, N/A/stage authority application, coverage/well-defined policy, blockers and stage boundaries.

**MUST** transform governed facts/semantic outputs into readiness-policy results.  
**MUST** preserve fail-closed behavior.  
**MUST NOT** invent domain semantics.  
**MUST NOT** own orchestration strategy.  
**MUST NOT** perform durable writes in the target architecture; persistence effects are delegated.

### 4. Orchestration

**Owns:** entrypoints, strategy selection, ordering, fan-out/chunking, handoff between Core → Semantic → Readiness Policy → Evidence/Persistence, and Agent/Curator/Validator coordination.

**MUST** invoke other layers through explicit contracts.  
**MUST** keep Curator and Validator identities distinct per `DEC-INPUT-GOV-RUNTIME-001`.  
**MUST NOT** embed family/domain knowledge.  
**MUST NOT** compute independent semantic conclusions.  
**MUST NOT** write authoritative state directly in the target architecture; it delegates to Persistence.

### 5. Evidence

**Owns:** source manifests, receipts, hashes, explainability payloads, shadow observations, EKB observations and readback envelopes.

**MUST** bind evidence to exact source/version identities.  
**MUST** remain descriptive and reproducible.  
**MUST NOT** decide semantic truth or readiness.  
**MUST NOT** promote or activate anything.  
**MUST NOT** perform durable storage directly in the target architecture; storage is delegated to Persistence.

### 6. Persistence

**Owns:** durable writes to governed run/assessment/gap/evidence/remediation state and write-boundary invariants.

**MUST** persist only typed outputs already decided by the owning layer.  
**MUST** enforce identity/cardinality/integrity constraints and write-boundary guards.  
**MUST NOT** derive semantic conclusions.  
**MUST NOT** choose orchestration strategy.  
**MUST NOT** silently reinterpret readiness policy.

## Function-set ownership

| Function set / singleton | Target layer | Current active count |
|---|---|---:|
| `PROGRAMACION_FN_INPUT_GOVERNANCE_ASSERTION_ENGINE_SET` | Semantic | 7 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET` | Core | 8 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET` | Orchestration | 7 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_INVALIDATION_SET` | Readiness Policy | 2 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_CURRENTNESS_SET` | Readiness Policy | 2 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_DESIGN_BINDING_SET` | Core | 5 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET` | Evidence | 1 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET` | Orchestration | 5 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET` | Persistence | 13 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_HEALTH_SET` | Evidence | 0 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_NA_AUTHORITY_SET` | Core | 2 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_OUTCOME_REMEDIATION_SET` | Evidence | 3 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET` | Persistence | 2 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_SECURITY_EXPECTATIONS_SET` | Semantic | 5 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET` | Semantic | 16 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_SHADOW_SET` | Evidence | 0 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_STAGE_AUTHORITY_SET` | Readiness Policy | 4 |
| `PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET` | Orchestration | 7 |
| `programacion.fn_lf_router_input_governance_resolve_v1` | Orchestration | 1 |

The three Edge assets `EDGE_FN_INPUT_GOVERNANCE_AGENT_V1`, `EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1`, and `EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1` are also assigned to **Orchestration**.

## M0.5 block-class → M1.1 layer mapping

Every M0.5 logical block inherits exactly one layer through this total mapping:

| M0.5 class | M1.1 layer |
|---|---|
| `FACT` | Core |
| `HEURISTIC` | Core |
| `SEMANTIC` | Semantic |
| `POLICY` | Readiness Policy |
| `READINESS` | Readiness Policy |
| `ORCHESTRATION` | Orchestration |
| `EVIDENCE` | Evidence |
| `PERSISTENCE` | Persistence |

M0.5 already closed with `unclassified_logical_blocks=0` and `dual_class_logical_blocks=0`; therefore this mapping gives every M0.5 block exactly one layer. M0.5 observed no persistence block in the five classified base functions.

## Current violations to remove in later implementation units

M1.1 documents these; it does not refactor them yet.

1. **Classifier/probe mixing.** `classify_v1/v2` and `semantic_probe_v1/v2/v3` physically mix Core, Semantic, Readiness Policy, Orchestration and Evidence responsibilities. M0.5 provides the exact block boundaries.
2. **Curator writes from Orchestration.** Active curation paths including `bootstrap_materialize_v2`, `curator_rebind_v1`, `materialize_gap_proposals_v1`, `recurate_source_stale_v1` and `recurate_v2` contain direct insert behavior instead of delegating persistence.
3. **Curator consumes Validator builder.** `fn_input_governance_curator_rebind_v1` calls `fn_input_v58_build_assertions`; this violates the intended Curator/Validator boundary.
4. **Validator writes from Orchestration.** Active validation paths currently update/insert run validation state directly instead of delegating persistence.
5. **Validator rebind uses the same v58 builder.** `fn_input_governance_validator_rebind_v1` calls `fn_input_v58_build_assertions`; later M4 work must preserve independent oracle semantics rather than correlated reproduction.
6. **Currentness invalidation writes inside policy code.** `fn_input_latch_predecessor_invalidation` currently performs an update; target ownership places the decision in Readiness Policy and the write effect behind Persistence.

Static keyword scans are used only to locate these seams; later implementation units must verify actual statement behavior before moving code.

## Negative/readback contract

M1.1 is satisfied only when all of the following remain true:

- active IG-proper database functions = 90 for this snapshot;
- assigned active functions = 90;
- unassigned active functions = 0;
- functions assigned to more than one layer = 0;
- canonical function-set member duplicates = 0;
- all 18 registered DB function sets have one layer, including currently inactive `HEALTH` and `SHADOW` sets;
- all three IG Edge assets have one layer;
- all eight M0.5 responsibility classes map to exactly one M1.1 layer;
- no runtime, deployment, migration or production state is changed by M1.1.

Any future membership/liveness drift requires recomputing the assignment digest before relying on this document.
