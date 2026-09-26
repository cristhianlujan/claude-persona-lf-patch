# LF Contract Check — lightweight destination capability map

## Purpose

Map the 46 responsibilities already classified as outside the final `lf-contract-check` boundary to the **type of capability that should own them**, then identify an existing LF capability only when the match is sufficiently clear.

This is intentionally a **lightweight mapping**, not an audit of destination components.

Authority:
- boundary merge commit: `37b9a3b12f85de49a56d23dda0145ea8c2c98f7f`
- source boundary artifact: `contract_check_responsibility_boundary_v1.md`
- moved responsibilities: 46
- retained Contract Check concepts: 5

## Rules

1. Function first, identity second.
2. `owner_name`, legacy prefixes, historical project names, `Sxx`, `PRxx`, lane names and similar labels are **not** accepted as architectural authority.
3. An existing asset is reused only when its functional role matches the responsibility being transferred.
4. Destination components are not audited transitively. Only existence and direct transfer compatibility are considered here.
5. A defect found in a destination is deferred unless it directly blocks this transfer.
6. `UNRESOLVED` is valid and preferred over forcing a wrong owner.

### Identity status

| Status | Meaning |
|---|---|
| `MATCH_CLEAR` | Existing LF capability is a direct functional match for this responsibility family. |
| `CANDIDATE_ONLY` | Existing LF capability appears related, but its identity/scope is not trusted enough to canonize without a later direct compatibility check. |
| `UNRESOLVED` | No clear canonical LF destination was found in the lightweight lookup. |
| `DISSOLVE_WITH_DOMAIN_OWNERS` | This is carrier/support work that should travel with the domain controls that need it, not become a standalone owner. |

## A. Change governance — 15 responsibilities

### Responsibility family
Repository delta resolution, path admission, exact governed-path policy, authority/currentness and cross-cutting repository-state admission.

IDs:
- `VAL-CHANGE-DETECTION`
- `VAL-PATH-ADMISSION`
- `VAL-RETIRED-GITHUB-PATH`
- `VAL-PROFILE-CREATOR-WORKFLOW-ADMISSION`
- `VAL-PROFILE-CREATOR-EDGE-ADMISSION`
- `VAL-PROFILE-RUNTIME-EDGE-ADMISSION`
- `VAL-OPERATIONAL-PROTOCOL-PATHS`
- `VAL-P0-CLOSURE-PATHS`
- `VAL-P0-PERSISTENCE-PATH`
- `VAL-GOVERNED-PATH-CLASSIFICATION`
- `VAL-FORBIDDEN-STATUS`
- `WF-EXACT-DIFF`
- `WF-PREFLIGHT-SCOPE`
- `WF-AUTHORITY-CURRENTNESS`
- `WF-DECLARED-GOVERNANCE-PATHS`

Target capability by nature: **repository/change admission governance**.

Existing LF candidate found: `REPOSITORY_GOVERNANCE_BUNDLE`.

Status: `CANDIDATE_ONLY`.

Reason: the active LF asset clearly governs repository-governance state/bundles, but this stage does not prove that it already owns executable changed-path admission. Do not move or duplicate logic until that one direct compatibility question is checked.

## B. Pass applicability / orchestration — 5 responsibilities

IDs:
- `WF-DEDUPE`
- `WF-LANE-CLASSIFICATION`
- `WF-APPLICABILITY-PLAN`
- `WF-CI-ROUTER-SELFTEST`
- `WF-P0-FAST-LANE`

Target capability by nature: **pass applicability and execution orchestration**.

Existing LF candidate found: `CI_FAST_DEEP_LANE_ROUTER`.

Status: `CANDIDATE_ONLY`.

Reason: it is an active shared routing capability, but the implementation-oriented name is not treated as canonical architecture and this mapping does not audit whether it covers the whole pass-planning responsibility.

## C. Generic evidence / observability / persistence — 11 responsibilities

### C1. Receipt and generic evidence validation — 5

IDs:
- `VAL-RECEIPT-DISCOVERY`
- `VAL-RECEIPT-STANDARD`
- `VAL-RECEIPT-CANDIDATE`
- `VAL-RECEIPT-COVERAGE`
- `WF-PASS-EVIDENCE`

Target capability by nature: **typed evidence contract + exact evidence binding/anti-replay**.

Existing LF candidates found: `TYPED_EVIDENCE_REGISTRY`, `EVIDENCE_ANTIREPLAY`, `EVIDENCE_LEDGER`.

Status: `CANDIDATE_ONLY`.

Reason: the evidence primitives exist, but no assumption is made that the current Contract Check receipt schema is already represented by one canonical owner.

### C2. Gate diagnostic observability — 2

IDs:
- `WF-DIAGNOSTIC-DETECTION`
- `WF-DIAGNOSTIC-ARTIFACT`

Target capability by nature: **generic gate-check observability/diagnostics**.

Existing LF capability found: `GATE_CHECK_OBSERVABILITY`.

Status: `MATCH_CLEAR`.

Reason: the registered capability explicitly owns generic gate-check diagnostics and shared diagnostic producers. Artifact transport remains a carrier detail, not Contract Check semantics.

### C3. Evidence packaging / lineage — 3

IDs:
- `WF-PLAN-ARTIFACT`
- `WF-RECONCILIATION-MANIFEST`
- `WF-AUDIT-SNAPSHOT-UPLOAD`

Target capability by nature: **generic evidence packaging, lineage and durable evidence reference**.

Existing LF candidates found: `EVIDENCE_LEDGER`, `TYPED_EVIDENCE_REGISTRY`.

Status: `CANDIDATE_ONLY`.

Reason: reusable evidence infrastructure exists, but the current whole-repository manifest and Actions artifact packaging are not assumed to be canonical ledger responsibilities without a later direct compatibility check.

### C4. Pre-EKB persistence — 1

ID:
- `WF-PRE-EKB`

Target capability by nature: **governed pre-EKB persistence of failed checks**.

Existing LF capability found: `PRE_EKB_GATE`.

Status: `MATCH_CLEAR`.

Reason: this capability is explicitly registered for governed pre-EKB persistence and already lists `GITHUB_CONTRACT_GATE_LF` as a consumer. Contract Check should consume it, not implement it internally.

## D. Domain controls — 15 responsibilities

| IDs | Target capability by nature | Existing LF identity | Status | Minimal conclusion |
|---|---|---|---|---|
| `WF-MIGRATION-INPUTS`, `WF-MIGRATION-PARITY` | migration source parity | `MIGRATION_SOURCE_PARITY` | `MATCH_CLEAR` | Existing active capability is the direct functional destination. |
| `WF-INPUT-GOV-MIGRATION-PARITY` | Input Governance migration parity | none proven | `UNRESOLVED` | Edge Input Governance assets exist, but they are not assumed to own migration parity. |
| `WF-S36-ASSURANCE` | assurance completeness | `ASSURANCE_COMPLETENESS` | `MATCH_CLEAR` | Existing active capability directly matches the S36 completeness responsibility. |
| `VAL-PROFILE-RUNTIME-REGRESSION` | profile-runtime regression/validation | `PROFILE_RUNTIME_API_SERVICE` candidate | `CANDIDATE_ONLY` | Runtime service exists but is recorded as candidate pending qualification; do not canonize it from this mapping. |
| `VAL-COMPACT-PROTOCOL-SEMANTICS` | compact-protocol semantic validation | none proven | `UNRESOLVED` | Do not create a new owner now; only record the gap. |
| `WF-TRANSVERSAL-README` | transversal asset documentation/readme governance | none proven | `UNRESOLVED` | Current repository has transversal documentation controls, but no single canonical identity is established here. |
| `WF-SUPABASE-CONTROL-PLANE` | Supabase control-plane security/readback | none proven | `UNRESOLVED` | Record only; no destination audit now. |
| `WF-AUDIT-DEPS` | dependency provisioning for selected domain controls | n/a | `DISSOLVE_WITH_DOMAIN_OWNERS` | Package installation should follow the controls that need it, not become a standalone capability. |
| `WF-P0-VISUAL-PROVISION` | P0 visual runtime/control | none proven | `UNRESOLVED` | Existing P0 evidence broker is evidence transport, not proof of ownership of visual validation. |
| `WF-E16-GOVERNANCE`, `WF-E16-ACTIONS-INVENTORY` | E.16 governance control | none proven | `UNRESOLVED` | Keep recorded as a separate domain responsibility; do not chase its internals now. |
| `WF-VALIDATION-ENGINE` | LF validation engine | `ACT-0035` candidate documentation | `CANDIDATE_ONLY` | An active inventory record exists, but its route is explicitly unverified and it is not accepted here as canonical execution owner. |
| `WF-NO-BYPASS` | no-bypass profile/card/skill validation | none proven | `UNRESOLVED` | Record only. |
| `WF-R8-AUDIT` | integral-user-story audit | `SKILL-CREATING-INTEGRAL-USER-STORIES` related asset | `CANDIDATE_ONLY` | The skill is related to the audited domain, but producer identity is not automatically audit ownership. |

Domain-control count reconciled: **15**.

## E. Count reconciliation

| Family | Count |
|---|---:|
| Change governance | 15 |
| Pass applicability/orchestration | 5 |
| Generic evidence/observability/persistence | 11 |
| Domain controls | 15 |
| **Total moved out of Contract Check** | **46** |

The five concepts retained with Contract Check remain unchanged from the boundary stage:
1. validate contract semantics;
2. emit the contract verdict;
3. trigger the check;
4. bind/checkout the exact candidate;
5. invoke the intrinsic validator.

## F. What this mapping means for the next implementation stage

No destination is audited broadly.

For a transfer, the next stage asks only:

```text
responsibility leaving Contract Check
        ↓
identified destination capability
        ↓
one direct compatibility check
        ↓
can receive it? ── yes → move + prove + remove old copy
        │
        └─ no / unclear → keep as explicit blocker; do not chase unrelated defects
```

`CANDIDATE_ONLY` and `UNRESOLVED` rows do not block cleaning the unrelated `MATCH_CLEAR` families unless there is an actual dependency between them.

## Explicit non-scope

- no code extraction;
- no audit of destination internals;
- no normalization of legacy owner names;
- no renaming of unrelated assets;
- no creation of missing capabilities;
- no Supabase mutation;
- no workflow/ruleset changes;
- no deployment or activation.
