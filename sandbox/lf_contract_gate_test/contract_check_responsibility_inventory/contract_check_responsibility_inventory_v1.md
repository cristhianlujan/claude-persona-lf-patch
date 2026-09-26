# LF Contract Check — current responsibility inventory

## Scope

This document inventories what `lf-contract-check` actually does today. It does **not** decide ownership, extraction order, redesign, or target architecture.

Frozen authority for this inventory:

- repository: `cristhianlujan/claude-persona-lf-patch`
- exact commit: `d193dbea3e6bd193c9d48a1c0dc9a1722b87d5f4`
- workflow: `.github/workflows/lf-contract-check.yml`
  - git blob: `553dc9bfe21cb6db28b6f6a0f5367adea079461b`
- validator: `scripts/lf_contract_check.py`
  - git blob: `5e6a1e9f0e0cd1dc6a92f4d3b4eac1425405b0c9`
- contract input: `sandbox/lf_contract_gate_test/lf_contract.yml`
  - git blob: `55a842e7805c88673762eb2fcadec654b5ba213f`

Ownership classification is intentionally deferred to the next stage.

## A. Responsibilities embedded in `scripts/lf_contract_check.py`

| ID | Current responsibility | Concrete source | Inputs | Observable result / effect | External dependency or effect |
|---|---|---|---|---|---|
| VAL-CONTRACT-TERMS | Validate intrinsic LF contract terms | `validate_contract()` | `lf_contract.yml`, `REQUIRED_TERMS` | success or `FAIL_CONTRACT_MISSING` / `FAIL_CONTRACT_INVALID` | none |
| VAL-CHANGE-DETECTION | Resolve changed files by GitHub event | `get_changed_files()` | PR/push/workflow-dispatch env + git history | changed-file list | git fetch/read |
| VAL-PATH-ADMISSION | Admit/block changed paths using exact/prefix policies | `is_allowed_path()`, `validate_changed_files()` | changed files, allow/block sets | governed list or scope failure | repository tree |
| VAL-RETIRED-GITHUB-PATH | Prevent reintroduction of retired GitHub workflow paths | `validate_retired_github_paths()` | repository paths | pass/fail invariant | filesystem |
| VAL-PROFILE-CREATOR-WORKFLOW-ADMISSION | Admit exactly the Profile Creator governance caller workflow and reject lookalikes | `validate_profile_creator_workflow_admission_scope()` | path constants | pass/fail invariant | none |
| VAL-PROFILE-CREATOR-EDGE-ADMISSION | Admit exactly the Profile Creator Edge source and reject lookalikes | `validate_profile_creator_edge_admission_scope()` | path constants | pass/fail invariant | none |
| VAL-PROFILE-RUNTIME-EDGE-ADMISSION | Admit exactly the Profile operation runtime Edge source and reject lookalikes | `validate_profile_operation_runtime_edge_admission_scope()` | path constants | pass/fail invariant | none |
| VAL-OPERATIONAL-PROTOCOL-PATHS | Admit exact operational-protocol files and reject lookalikes | `validate_operational_protocol_scope()` | path constants | pass/fail invariant | none |
| VAL-COMPACT-PROTOCOL-SEMANTICS | Validate promoted compact protocol structure, fields, helper SQL and locator | `validate_compact_protocol_contract()` | two protocol files | semantic pass/fail | filesystem |
| VAL-P0-CLOSURE-PATHS | Admit exact P0 closure-evidence documents and reject lookalikes | `validate_p0_closure_evidence_scope()` | P0 path constants | pass/fail invariant | none |
| VAL-P0-PERSISTENCE-PATH | Admit exact P0 persistence test and reject lookalikes | `validate_p0_persistence_test_scope()` | P0 test path constants | pass/fail invariant | none |
| VAL-PROFILE-RUNTIME-REGRESSION | Execute Profile Runtime regression intrinsically | `validate_profile_runtime_regression()` | `profile_execution_runtime/run_tests.py` | subprocess result + required marker | executes another test suite |
| VAL-GOVERNED-PATH-CLASSIFICATION | Classify profiles/skills/cards/adapters/governance paths as governed | `is_governed_path()` | changed path | governed/not governed | none |
| VAL-RECEIPT-DISCOVERY | Discover changed receipt JSON files | `load_receipts_from_changed_files()` | changed files | parsed receipt set or JSON failure | filesystem |
| VAL-RECEIPT-STANDARD | Validate standard operation receipt shape and evidence fields | `validate_receipt_shape()` | receipt JSON | pass/fail | none |
| VAL-RECEIPT-CANDIDATE | Validate candidate receipt head ancestry, post-code-head isolation and blob binding | `validate_candidate_receipt_shape()` | receipt JSON, governed files, git blobs | pass/fail with exact-head/blob evidence | git history/tree |
| VAL-RECEIPT-COVERAGE | Require governed files to be covered by a valid receipt | `validate_governed_receipt()` | changed/governed files + receipts | pass/fail coverage | none |
| VAL-FORBIDDEN-STATUS | Scan changed files for forbidden terminal/productive status assignments | `validate_forbidden_terms()` | changed files | pass/fail scanner | filesystem |
| VAL-FINAL-VERDICT | Aggregate sequential validator calls and emit process exit verdict | `main()`, `pass_check()`, `fail()` | all preceding checks | process exit 0/1 + message | none |

Validator responsibility count: **19**.

## B. Responsibilities embedded in `.github/workflows/lf-contract-check.yml`

| ID | Current responsibility | Concrete workflow area | Inputs | Observable result / effect | External dependency or effect |
|---|---|---|---|---|---|
| WF-TRIGGER | Trigger on manual, push and PR events; define read permissions | workflow header | GitHub event | job creation | GitHub Actions |
| WF-DEDUPE | Decide DEEP execution vs exact-context reuse / duplicate push skip | `dedupe-router` job | event, PR/base/head, previous runs/artifacts | `run_deep`, decision, reason | GitHub API reads |
| WF-EXACT-CHECKOUT | Checkout exact candidate commit and prepare Python | first `lf-contract-check` steps | candidate SHA | exact working tree | GitHub checkout |
| WF-EXACT-DIFF | Compute exact base→head changed set | canonical preflight | base/head SHA | changed-path set | git fetch/diff |
| WF-PREFLIGHT-SCOPE | Re-run path admission, receipt coverage and forbidden-status checks before applicability | canonical preflight | changed paths | fail-closed preflight | imports validator |
| WF-LANE-CLASSIFICATION | Classify FAST/DEEP lane | `lf_ci_lane_router.py` | changed paths | lane + required controls | local router module |
| WF-APPLICABILITY-PLAN | Build the unified CI execution/applicability plan | `lf_ci_execution_plan_v2.py` | changed paths + lane controls | required controls + plan hash | local plan module |
| WF-AUTHORITY-CURRENTNESS | Resolve and enforce authority evidence revision/currentness | `lf_ci_currentness_bridge_v1.py` | base/head/current main | ready/block decision | git remote main read |
| WF-CI-ROUTER-SELFTEST | Execute lane-router/currentness/plan/wiring self-tests | `CI_ROUTER_SELFTEST` step | plan-selected control | diagnostics | executes multiple test programs |
| WF-TRANSVERSAL-README | Validate active transversal asset READMEs and inventory | transversal closure step | repository + `lf_activos` data | pass/fail | Supabase DB read |
| WF-P0-FAST-LANE | Short-circuit exact regular P0-doc-only deltas | `P0_FAST_DOCS` step | required controls | fast-lane result | none |
| WF-DECLARED-GOVERNANCE-PATHS | Enforce declared governance paths through gate-group orchestrator | `DECLARED_GOVERNANCE_PATHS` step | manifest | diagnostics/result | executes gate orchestrator |
| WF-SUPABASE-CONTROL-PLANE | Verify hosted Supabase Data API does not expose `net` schema | `SUPABASE_CONTROL_PLANE_READBACK` step | Supabase Management API | pass/fail + summary | Supabase API read |
| WF-MIGRATION-INPUTS | Build frozen migration-parity inputs, legacy checkpoints and owner-currentness evidence | `Prepare LF migration source parity frozen inputs` | repo migrations, Supabase ledger, GitHub PRs | CSV/JSON runtime inputs | Supabase DB + GitHub API reads |
| WF-MIGRATION-PARITY | Execute Migration Source Parity through gate orchestrator | `MIGRATION_SOURCE_PARITY` step | frozen parity inputs | gate diagnostics/result | DB connection + parity control |
| WF-INPUT-GOV-MIGRATION-PARITY | Execute Input Governance migration parity | dedicated step | remote migration ledger + repo migrations | pass/fail | Supabase DB read |
| WF-AUDIT-DEPS | Install deterministic audit dependencies | dependency-install step | selected controls | Python packages installed | package network |
| WF-P0-VISUAL-PROVISION | Provision OCR/visual runtime dependencies | P0 visual runtime step | selected control | Python/system packages installed | package/apt network |
| WF-S36-ASSURANCE | Execute S36 completeness self-test and debt monotonicity | two S36 steps | selected control | deterministic diagnostics | S36 programs; DB secret for debt check |
| WF-CONTRACT-CORE-RUNNER | Route LF contract execution between declared-governance and legacy entrypoint; execute contract gate | `Validate LF contract` step | exact changed set + repo files | contract result | executes entrypoints and validator scanner |
| WF-E16-GOVERNANCE | Execute E.16 regression, inventory, ratification, integration and P0 runtime matrices | E.16 regression step | selected control | deterministic diagnostics | multiple test programs |
| WF-VALIDATION-ENGINE | Execute LF Validation Engine self-test | validation-engine step | selected control | deterministic diagnostics | validation-engine program |
| WF-NO-BYPASS | Execute NO BYPASS profile-card-skill self-test | no-bypass step | selected control | deterministic diagnostics | no-bypass program |
| WF-PASS-EVIDENCE | Verify merge/CI evidence for PASS candidates | PASS-evidence step | candidate evidence + GitHub repository | deterministic diagnostics | GitHub read via program |
| WF-R8-AUDIT | Audit creating-integral-user-stories A01-A62 | R8 audit step | skill tree + commit SHA | audit output + diagnostics | audit program |
| WF-DIAGNOSTIC-DETECTION | Detect deterministic diagnostic files | diagnostic-detection step | `.lf_gate_diagnostics` | presence flag | filesystem |
| WF-PLAN-ARTIFACT | Persist unified applicability plan | upload-artifact step | `.lf_ci/lf_ci_execution_plan_v2.json` | durable Actions artifact | GitHub Actions artifact write |
| WF-DIAGNOSTIC-ARTIFACT | Persist deterministic gate diagnostics | upload-artifact step | `.lf_gate_diagnostics/lf_contract_check` | durable Actions artifact | GitHub Actions artifact write |
| WF-PRE-EKB | Transform failed deterministic diagnostics into governed gate-check records/EKB persistence and finalize a parent execution | PRE_EKB step | diagnostics + exact source SHA + DB bindings | reserves execution, records checks, verifies EKB receipts, updates execution status | **Supabase writes** |
| WF-E16-ACTIONS-INVENTORY | Capture authenticated GitHub Actions inventory for E.16 | E.16 inventory step | PR head + GitHub token | inventory JSON | GitHub API read |
| WF-RECONCILIATION-MANIFEST | Build whole-repository reconciliation manifest with hashes/blob IDs | reconciliation step | tracked repository | manifest JSON | git/hash reads |
| WF-AUDIT-SNAPSHOT-UPLOAD | Upload audit evidence plus canonical skill source snapshot | final upload step | audit output + skill tree | Actions artifact | GitHub Actions artifact write |

Workflow responsibility count: **32**.

## C. Inventory result

Total independently observable responsibilities inventoried: **51**.

This count is a current-state inventory, not a target-state count. Several rows may later collapse into one owner capability, while others may split further when ownership is evaluated. No such decision is made here.

## D. Boundary facts observed, without ownership judgment

1. The Python validator contains both intrinsic contract validation and repository/path/receipt/runtime/protocol/P0 concerns.
2. The workflow contains trigger/transport concerns, applicability planning, currentness, multiple domain controls, diagnostics, artifact persistence, GitHub API reads, Supabase reads, and a Supabase write path through PRE_EKB.
3. The workflow is therefore not merely a thin carrier around `validate_contract()` in the current state.
4. `WF-PRE-EKB` has productive database side effects; most other listed workflow responsibilities are reads, local execution, or Actions artifact writes.
5. Ownership, legitimacy, extraction order and replacement design are explicitly out of scope for this inventory.

## Closure criterion for this stage

This inventory can be considered demonstrated only when:

- the source commit and blob IDs above read back exactly;
- this PR changes only this inventory artifact;
- the inventory is reviewed against the exact validator and workflow surfaces;
- no ownership or target architecture is silently introduced.
