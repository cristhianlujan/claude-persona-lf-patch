# S31 — LF Reusable Capability & Governed Development Platform

Status: BOOTSTRAP_CANDIDATE
Branch: `lf/s31-bootstrap`
Base main at bootstrap: `ee7aca94c672fcc555db90962f09fe439eedf4f0`
Runtime activation: false
Production activation: false
Main merge authority: false
Golden promotion authority: false

## Objective

Convert proven LF governance/execution patterns that currently live inside S30, S26, Learning Engine and Creating Integral User Stories into reusable, versioned, governed capabilities without weakening the owning strategies or creating cross-lane write collisions.

S31 generalizes. S30/S26/Learning/Story Creator remain owners of their internal implementations.

## Core principle

S31 MUST run under the Work Package model it is building.

The initial contract is `LF_WORK_PACKAGE_BOOTSTRAP_V0_1`. It evolves only from observed execution evidence, reusable requirements or verified architectural gaps. S31 must not add fields or controls merely because they appear theoretically useful.

## Source findings that justify S31

1. S30 already contains candidate self-governance, pre-execution assurance, ownership, data access, evidence and reliability capabilities.
2. S26 already contains source-first construction, governed Cards/fallback, runtime authority, typed context, adapters and reconstructible provenance.
3. Learning Engine already contains trace-to-change, capability-vs-regression eval semantics, evidence ceilings, known-vs-new separation and domain ownership controls.
4. Creating Integral User Stories already contains a strong Task Packet, worker/judge separation, scoped execution, binary closure and evidence discipline.
5. The main architectural gaps are transversalization, canonical vocabulary, capability lifecycle/registry and stable ports/adapters—not rebuilding the existing systems.

## Ownership boundary

### S31 may read

- S30 contracts, candidate implementations, receipts and tests.
- S26 governance/runtime contracts, profile runtime implementation, receipts and tests.
- Learning Engine contracts, judges, eval semantics and evidence rules.
- Creating Integral User Stories Task Packet, ledgers, judges, schemas and closure rules.
- Relevant external research and standards documents.

### S31 may write

Only S31-owned candidate paths during bootstrap:

- `sandbox/lf_contract_gate_test/s31_bootstrap/`
- future S31-owned paths explicitly registered by an S31 ownership registry.

### S31 must not write directly

- S30 internals.
- S26 internals.
- Learning Engine internals.
- Creating Integral User Stories internals.
- unrelated Supabase migrations/functions.
- production/runtime fleet settings.

If S31 requires an internal change in another strategy/capability, it must emit an interface-change request/handoff to that owner.

## Initial lanes

| Lane | Responsibility | Initial status |
|---|---|---|
| S31-A | Canonical Capability Model | ACTIVE_BOOTSTRAP |
| S31-B | LF Work Package Contract evolution | QUEUED_AFTER_BOOTSTRAP_EVIDENCE |
| S31-C | Canonical Cards/Fallback semantics | QUEUED |
| S31-D | Shared Authority + Typed Context kernel | QUEUED |
| S31-E | Capability Registry | QUEUED |
| S31-F | Evidence / Receipt / Lifecycle | QUEUED |
| S31-G | Runtime Ports & Adapters | QUEUED |
| S31-H | External Standards / PoCs | DEFERRED_UNTIL_INTERNAL_CONTRACTS_STABLE |

## Initial priority order

1. Bootstrap Work Package and deterministic validation.
2. Canonical Capability Model.
3. Work Package v0.2 candidate derived from actual S31-A friction/findings.
4. Canonical Cards/Fallback vocabulary.
5. Shared Authority/Typed Context interfaces.
6. Capability Registry.
7. Evidence/Receipt/Lifecycle unification.
8. Runtime ports/adapters.
9. Only then external runtime/durable/interop PoCs.

## Architecture target

```text
LF CONTROL PLANE (owned by LF)
  Work Package Contract
  Capability Registry
  Authority + Currentness
  Pre-execution Assurance
  Policy / Fail-closed
  Golden Lifecycle
  Evidence / Replay
  Learning -> Regression
       |
       v stable ports/adapters
EXECUTION PLANE
  Deterministic workers
  Model runtime adapters
  Durable engine adapter (TBD by PoC)
  Eval runtime adapter
  Interoperability adapters
       |
       v
Supabase/PostgreSQL source of truth
Observability through a mapping layer
```

## S31 bootstrap gates

S31 material work is allowed only when the active Work Package proves:

- exact/current base;
- source authority;
- applicable EKB/governance;
- collision-free ownership;
- resolved schemas/contracts;
- resolved tools/functions/adapters;
- evidence/readback path;
- acceptance/failure/blocking assertions;
- negative/fail-closed path.

## Evolution rule

Every Work Package change must answer:

1. What observed defect or reusable need caused the change?
2. Which execution/evidence demonstrates it?
3. Is the requirement transversal or lane-specific?
4. Can the requirement be expressed as a stable contract rather than implementation detail?
5. What positive and negative regression protects it?

If these cannot be answered, the change does not enter the Work Package contract.

## Non-goals for bootstrap

- installing LangGraph, Temporal, DBOS, Dapr or other execution frameworks;
- adopting MCP/A2A as mandatory runtime dependencies;
- migrating S30/S26 code into S31;
- promoting any candidate to Golden;
- changing production;
- replacing existing working execution paths before stable LF ports exist.
