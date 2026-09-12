# S31-A — Current LF Assets to Canonical Capability Model v0.1

Status: CANDIDATE / READ-ONLY SOURCE CLASSIFICATION
Work Package: `WP-S31-A-001`
Base main: `ee7aca94c672fcc555db90962f09fe439eedf4f0`

## Purpose

Classify existing LF mechanisms into reusable capability identities without moving or mutating their owner implementations.

## Source inventory and classification

| Canonical capability | Current source / implementation | Current owner | Target action | Notes |
|---|---|---|---|---|
| `PREEXECUTION_ASSURANCE` | `gobernanza/contratos/s30_self_governance_gate_v1.json` | S30 | GENERALIZE_SHARED | Preserve S30 implementation; extract stable contract/port semantics. |
| `CURRENTNESS_AUTHORITY` | S30 self-governance + S26 runtime authority | S30/S26 | GENERALIZE_SHARED | Exact-head/source revision and runtime authority become common LF contracts. |
| `LANE_OWNERSHIP` | `s30_lane_ownership_registry_v1.json` | S30 | GENERALIZE_SHARED | Keep path ownership registry; expose ownership resolution as transversal capability. |
| `DATA_ACCESS_TYPED_READER` | S30-B `lf_data_access.py` / budgeted reader | S30 | GENERALIZE_SHARED | Candidate implementation stays S30-owned until stable shared port exists. |
| `CARD_RESOLUTION` | S26 governance contract + runtime card resolver | S26 | REFACTOR_CANONICAL_VOCABULARY | Unify `EXACT/COMPATIBLE/NONE/AMBIGUOUS`, `COMPOSED/GENERIC_SAFE`, and `NO_CARD_GOVERNED`. |
| `TYPED_RUNTIME_CONTEXT` | `services/profile_runtime_api/profile_runtime_api/runtime_authority.py` | S26 | GENERALIZE_SHARED | Keep implementation; extract reusable typed-context contract and port. |
| `RUNTIME_EXECUTION_PORT` | `ProfileRuntimeEngine` | S26 | ADAPTER_REQUIRED | Separate LF governance contract from model/runtime implementation. |
| `LEARNING_GOVERNANCE` | `skills/learning_engine/SKILL.md` | Learning Engine | GENERALIZE_SHARED | Preserve trace-to-change, evidence ceiling, known/new and domain ownership. |
| `EVAL_EXECUTION_PORT` | Learning Engine eval routes | Learning Engine | ADAPTER_REQUIRED | LF owns pass/promotion semantics; external eval engines may sit behind port later. |
| `WORK_PACKAGE` | Story Creator `task-packet.schema.json` + S30 assurance | Story Creator/S30 | GENERALIZE_SHARED | Evolve Task Packet into mother contract; do not create unrelated parallel contract. |
| `EVIDENCE_LEDGER` | S30 gate evidence + Story Creator execution ledger + S26 receipts | Multiple | GENERALIZE_SHARED | Unify evidence layers and claim ceiling without destroying owner receipts. |
| `CAPABILITY_REGISTRY` | S30 lane registry is partial precursor | S31 target | BUILD | New transversal registry required for capability identity/version/lifecycle/dependencies/compatibility. |
| `GOLDEN_LIFECYCLE` | Candidate/Golden rules distributed across S26, S30, Learning, Story Creator | Multiple | GENERALIZE_SHARED | Canonical lifecycle must not self-certify; promotion remains evidence-bound. |

## Canonical capability boundary

A capability describes **what LF guarantees**, not where the implementation currently lives.

```text
Canonical Capability Manifest
        |
        +-- identity/version/owner
        +-- lifecycle
        +-- contracts/invariants
        +-- authority/currentness
        +-- dependencies/compatibility
        +-- execution port
        +-- evidence/claim ceiling
        +-- fail-closed policy
        +-- source of truth
                |
                v
        owner implementation
        S30 / S26 / Learning / Story Creator / adapter
```

## Invariants derived from current LF evidence

1. A model must never become authority/currentness/routing identity.
2. Source authority is resolved before material generation.
3. A candidate capability cannot self-promote to Golden.
4. Evidence layer cannot be escalated beyond what was executed.
5. Runtime/framework state cannot become LF domain truth by accident.
6. A capability dependency must be explicit and version/compatibility resolvable.
7. An owner implementation is not moved merely because a transversal abstraction is created.
8. Cross-strategy changes require owner handoff, not direct S31 mutation.
9. Missing/ambiguous critical dependency is fail-closed.
10. External frameworks are replaceable implementations behind ports, never mandatory kernel identity.

## Positive model example

`TYPED_RUNTIME_CONTEXT` may be represented as a canonical capability owned by LF/S26, with exact authority/currentness contracts, an execution port, evidence requirements and its existing S26 implementation binding. S31 does not need to copy `runtime_authority.py`.

## Negative model example

The following design is rejected:

```text
capability_id: TYPED_RUNTIME_CONTEXT
owner: LANGGRAPH
framework_is_kernel_dependency: true
source_of_truth: langgraph_checkpoint_store
model_may_decide_authority: true
```

It violates LF ownership, replaceability, deterministic authority and source-of-truth hard blockers.

## First candidate registry projection

The canonical manifest should be versioned in Git/repo as source-of-truth and may later be projected into Supabase/PostgreSQL for runtime resolution. Projection is not authority over the versioned manifest unless a future governance decision explicitly changes that rule.

## Not decided by S31-A v0.1

- Dapr vs Temporal vs DBOS.
- LangGraph vs OpenAI Agents SDK.
- MCP/A2A adoption timing.
- OpenTelemetry exact semantic-convention version.
- migration of existing owner implementations.

Those decisions remain outside this lane until common ports/contracts are stable.
