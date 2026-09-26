# LF Contract Check — responsibility boundary by nature

## Purpose

This stage classifies the 51 AS-IS responsibilities already inventoried for `lf-contract-check` by architectural nature. It does **not** extract code, assign a concrete destination owner, redesign sibling controls, or change runtime behavior.

Source inventory authority:

- inventory merge commit: `c49f5b046c6f33c3f18bdc7426ac10bd375b34a5`
- source validator blob: `5e6a1e9f0e0cd1dc6a92f4d3b4eac1425405b0c9`
- source workflow blob: `553dc9bfe21cb6db28b6f6a0f5367adea079461b`
- source inventory: `contract_check_responsibility_inventory_v1.md`

## Classification rule

The classification is theory-first and uses these boundaries:

1. **Contract semantics** belong to Contract Check: validate the declared contract and emit its verdict.
2. **Carrier mechanics** may remain only when they are generic transport needed to execute Contract Check itself: trigger, exact checkout, invoke the contract core.
3. **Change governance** does not belong to Contract Check: changed-file admission, repository path policy, authority/currentness and cross-cutting status policy are external to contract semantics.
4. **Applicability/orchestration** does not belong to Contract Check: deciding lane, required controls, deduplication or which sibling controls run is pass orchestration.
5. **Sibling/domain controls** do not belong to Contract Check: Migration Parity, Assurance, P0, runtime regression, validation engine, protocol-specific checks, etc. remain separate capabilities.
6. **Evidence/observability/persistence** is a separate concern: receipts, generic diagnostics, EKB persistence, reconciliation manifests and evidence transport must not define contract semantics.

The question is therefore not "does this run inside the current workflow?" but "would Contract Check cease to be Contract Check if this responsibility disappeared?".

## Classification codes

| Code | Meaning |
|---|---|
| `KEEP_CORE` | Intrinsic Contract Check responsibility. |
| `KEEP_MINIMAL_CARRIER` | Necessary thin execution carrier, not domain logic. |
| `SPLIT_KEEP_SHELL` | Current responsibility mixes intrinsic shell with foreign logic; keep only the minimal shell. |
| `MOVE_CHANGE_GOVERNANCE` | Repository/change-governance concern. |
| `MOVE_ORCHESTRATION` | Pass routing/applicability/orchestration concern. |
| `MOVE_DOMAIN_CONTROL` | Separate domain/control capability. |
| `MOVE_EVIDENCE` | Generic evidence/observability/persistence concern. |

## A. Validator boundary

| ID | Classification | Boundary reason |
|---|---|---|
| VAL-CONTRACT-TERMS | `KEEP_CORE` | Directly validates the declared contract terms. |
| VAL-CHANGE-DETECTION | `MOVE_CHANGE_GOVERNANCE` | Determines repository delta, not contract semantics. |
| VAL-PATH-ADMISSION | `MOVE_CHANGE_GOVERNANCE` | Decides which repository paths may change. |
| VAL-RETIRED-GITHUB-PATH | `MOVE_CHANGE_GOVERNANCE` | Repository lifecycle/path policy. |
| VAL-PROFILE-CREATOR-WORKFLOW-ADMISSION | `MOVE_CHANGE_GOVERNANCE` | Exact-path admission for another capability. |
| VAL-PROFILE-CREATOR-EDGE-ADMISSION | `MOVE_CHANGE_GOVERNANCE` | Exact-path admission for another capability. |
| VAL-PROFILE-RUNTIME-EDGE-ADMISSION | `MOVE_CHANGE_GOVERNANCE` | Exact-path admission for another capability. |
| VAL-OPERATIONAL-PROTOCOL-PATHS | `MOVE_CHANGE_GOVERNANCE` | Repository path admission for protocol assets. |
| VAL-COMPACT-PROTOCOL-SEMANTICS | `MOVE_DOMAIN_CONTROL` | Validates another protocol's semantics. |
| VAL-P0-CLOSURE-PATHS | `MOVE_CHANGE_GOVERNANCE` | Repository path admission for P0 evidence. |
| VAL-P0-PERSISTENCE-PATH | `MOVE_CHANGE_GOVERNANCE` | Repository path admission for a P0 test. |
| VAL-PROFILE-RUNTIME-REGRESSION | `MOVE_DOMAIN_CONTROL` | Executes Profile Runtime regression. |
| VAL-GOVERNED-PATH-CLASSIFICATION | `MOVE_CHANGE_GOVERNANCE` | Classifies repository surfaces as governed. |
| VAL-RECEIPT-DISCOVERY | `MOVE_EVIDENCE` | Discovers execution-evidence receipts. |
| VAL-RECEIPT-STANDARD | `MOVE_EVIDENCE` | Validates generic operation receipt shape. |
| VAL-RECEIPT-CANDIDATE | `MOVE_EVIDENCE` | Validates exact-head/blob execution evidence. |
| VAL-RECEIPT-COVERAGE | `MOVE_EVIDENCE` | Enforces evidence coverage over governed files. |
| VAL-FORBIDDEN-STATUS | `MOVE_CHANGE_GOVERNANCE` | Cross-cutting repository/state policy, not contract semantics. |
| VAL-FINAL-VERDICT | `SPLIT_KEEP_SHELL` | Contract Check needs a final verdict, but the current aggregator invokes many foreign concerns. Keep only aggregation of intrinsic contract checks. |

Validator result:

- `KEEP_CORE`: 1
- `SPLIT_KEEP_SHELL`: 1
- `MOVE_CHANGE_GOVERNANCE`: 11
- `MOVE_DOMAIN_CONTROL`: 2
- `MOVE_EVIDENCE`: 4
- total: 19

## B. Workflow boundary

| ID | Classification | Boundary reason |
|---|---|---|
| WF-TRIGGER | `KEEP_MINIMAL_CARRIER` | Thin carrier needs an execution trigger. |
| WF-DEDUPE | `MOVE_ORCHESTRATION` | Reuse/skip/deep selection is execution orchestration. |
| WF-EXACT-CHECKOUT | `KEEP_MINIMAL_CARRIER` | Contract Check must execute against an exact candidate revision. |
| WF-EXACT-DIFF | `MOVE_CHANGE_GOVERNANCE` | Computes repository change scope. |
| WF-PREFLIGHT-SCOPE | `MOVE_CHANGE_GOVERNANCE` | Re-enforces path/receipt/status governance. |
| WF-LANE-CLASSIFICATION | `MOVE_ORCHESTRATION` | Selects FAST/DEEP lane. |
| WF-APPLICABILITY-PLAN | `MOVE_ORCHESTRATION` | Decides required sibling controls. |
| WF-AUTHORITY-CURRENTNESS | `MOVE_CHANGE_GOVERNANCE` | Validates external authority/currentness of the change. |
| WF-CI-ROUTER-SELFTEST | `MOVE_ORCHESTRATION` | Tests routing/applicability infrastructure. |
| WF-TRANSVERSAL-README | `MOVE_DOMAIN_CONTROL` | Asset/documentation governance unrelated to contract semantics. |
| WF-P0-FAST-LANE | `MOVE_ORCHESTRATION` | Pass execution optimization. |
| WF-DECLARED-GOVERNANCE-PATHS | `MOVE_CHANGE_GOVERNANCE` | Repository governance-path enforcement. |
| WF-SUPABASE-CONTROL-PLANE | `MOVE_DOMAIN_CONTROL` | Supabase exposure/security check. |
| WF-MIGRATION-INPUTS | `MOVE_DOMAIN_CONTROL` | Produces inputs for Migration Source Parity. |
| WF-MIGRATION-PARITY | `MOVE_DOMAIN_CONTROL` | Executes Migration Source Parity. |
| WF-INPUT-GOV-MIGRATION-PARITY | `MOVE_DOMAIN_CONTROL` | Executes Input Governance migration parity. |
| WF-AUDIT-DEPS | `MOVE_DOMAIN_CONTROL` | Installs dependencies for foreign audit/domain controls. |
| WF-P0-VISUAL-PROVISION | `MOVE_DOMAIN_CONTROL` | Provisions P0 visual/OCR runtime. |
| WF-S36-ASSURANCE | `MOVE_DOMAIN_CONTROL` | Executes Assurance controls. |
| WF-CONTRACT-CORE-RUNNER | `SPLIT_KEEP_SHELL` | Keep only invocation of the intrinsic Contract Check core; legacy/declared routing and foreign scans leave the boundary. |
| WF-E16-GOVERNANCE | `MOVE_DOMAIN_CONTROL` | Executes E.16 governance matrices. |
| WF-VALIDATION-ENGINE | `MOVE_DOMAIN_CONTROL` | Executes the LF Validation Engine. |
| WF-NO-BYPASS | `MOVE_DOMAIN_CONTROL` | Executes NO BYPASS control. |
| WF-PASS-EVIDENCE | `MOVE_EVIDENCE` | Validates generic merge/CI evidence. |
| WF-R8-AUDIT | `MOVE_DOMAIN_CONTROL` | Executes user-story audit. |
| WF-DIAGNOSTIC-DETECTION | `MOVE_EVIDENCE` | Generic diagnostic discovery. |
| WF-PLAN-ARTIFACT | `MOVE_EVIDENCE` | Persists applicability-plan evidence. |
| WF-DIAGNOSTIC-ARTIFACT | `MOVE_EVIDENCE` | Persists generic gate diagnostics. |
| WF-PRE-EKB | `MOVE_EVIDENCE` | Persists failures/checks into governed DB/EKB execution state. |
| WF-E16-ACTIONS-INVENTORY | `MOVE_DOMAIN_CONTROL` | Captures E.16-specific GitHub inventory. |
| WF-RECONCILIATION-MANIFEST | `MOVE_EVIDENCE` | Builds a whole-repository reconciliation manifest. |
| WF-AUDIT-SNAPSHOT-UPLOAD | `MOVE_EVIDENCE` | Persists generic audit/source snapshot evidence. |

Workflow result:

- `KEEP_MINIMAL_CARRIER`: 2
- `SPLIT_KEEP_SHELL`: 1
- `MOVE_CHANGE_GOVERNANCE`: 4
- `MOVE_ORCHESTRATION`: 5
- `MOVE_DOMAIN_CONTROL`: 13
- `MOVE_EVIDENCE`: 7
- total: 32

## C. Consolidated boundary

| Nature | Count | Remains inside final Contract Check boundary? |
|---|---:|---|
| Intrinsic contract core | 1 | Yes |
| Minimal carrier | 2 | Yes, as transport only |
| Mixed shell to split | 2 | Only the thin shell remains |
| Change governance | 15 | No |
| Pass orchestration/applicability | 5 | No |
| Separate domain controls | 15 | No |
| Generic evidence/observability/persistence | 11 | No |
| **Total** | **51** | |

Therefore the current 51 responsibilities reduce architecturally to **five concepts that may remain associated with Contract Check**:

1. validate contract semantics;
2. emit the contract verdict;
3. trigger the check;
4. checkout/bind the exact candidate revision;
5. invoke the intrinsic contract validator.

Of those five, two (`VAL-FINAL-VERDICT` and `WF-CONTRACT-CORE-RUNNER`) require splitting because their current implementations aggregate foreign concerns.

The other **46 current responsibilities do not belong to the final Contract Check boundary as responsibilities of that capability**. This does not imply 46 new assets or 46 PRs; many are facets of the same external capability and can collapse under their canonical owners in the ownership stage.

## D. Target responsibility boundary, without assigning owners

```text
PASS / CHANGE GOVERNANCE / ORCHESTRATION
        |
        | exact candidate + request to validate contract
        v
+------------------------------------+
| LF CONTRACT CHECK                  |
|                                    |
|  1. receive exact contract input   |
|  2. validate contract semantics    |
|  3. emit structured verdict        |
+------------------------------------+
        |
        v
contract result + evidence reference

Outside this box:
- changed-file/path admission
- applicability / lane / sibling selection
- Migration Parity / P0 / S36 / E16 / Runtime / Validation Engine / No Bypass
- generic receipts / EKB / reconciliation / audit persistence
```

A thin workflow may still trigger, checkout the exact revision and invoke the validator, but those mechanics must not become policy or sibling-control ownership.

## E. Explicit non-decisions in this stage

This stage does not decide:

- which existing LF asset becomes owner of each moved responsibility;
- whether a missing owner must be created;
- extraction order;
- migration/cutover mechanics;
- required-check/ruleset changes;
- removal of current code;
- Supabase mutation;
- runtime or production activation.

Those belong to the next ownership/mapping stage.

## Closure criterion

This boundary classification is demonstrated only when:

- all 51 inventory IDs appear exactly once in this classification;
- category totals reconcile to 51;
- the PR changes only this classification artifact;
- the source inventory remains unchanged;
- no implementation or concrete owner assignment is introduced.