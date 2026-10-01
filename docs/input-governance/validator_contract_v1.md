# M1.3 — Validator logical contract v1

**Plan:** `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
**Unit:** `M1.3` / `PAULO-118` / L4  
**Contracts:** Input Readiness `5.13`; Execution `1.5`  
**ADR:** `DEC-INPUT-GOV-VALIDATOR-CLAIMS-NOT-CONCLUSIONS-001`

## Purpose

Freeze the logical boundary between Curator and Validator without changing runtime. The Validator may inspect Curator claims, references and integrity bindings, but it MUST NOT treat Curator conclusions as authoritative truth or as sufficient evidence for PASS/readiness.

Authoritative upstream evidence:

- M1.2 Curator field map: `55` Curator-produced/initialized/derived fields out of `80` persisted fields; map SHA256 `88f9290cc99a02cc75ba7e0db65b880c5423ce7b283ecdc5e07e399d8f59c868`.
- M4.1 corrected correlation inventory: `validator_rebind_v1 17/17`, `validate_v2 29/31`, `bootstrap_validate_v1 16/17` shared `programacion` dependencies with Curator.
- EKB `IG-VALIDATOR-MULTIPATH-CORRELATED-001` remains active.

## MUST NOT rule

> The Validator MUST NOT use any semantic, readiness or proposal conclusion produced by the Curator as authoritative truth, or as sufficient evidence for `PASS`, `COMPLETE`, `READY` or `NOT_APPLICABLE`.

The Validator MAY read those values only as **candidate claims** to compare, contradict or adjudicate. A successful validation requires an independent oracle or direct canonical source readback appropriate to the property being checked.

Additional mandatory semantics:

1. `source_refs`, `evidence_refs`, `canonical_target` and source manifests are locators, not truth. The Validator must re-resolve them against current canonical authority and bind the observed result/digest.
2. `curator_sha256`, `semantic_depth_sha256`, source/universe/contract snapshot hashes are integrity bindings. They prove what bytes/state were bound, not that the Curator conclusion was correct.
3. `curator_evidence` may provide provenance/candidate claims. Its semantic payload is not authoritative. A field such as an execution id may be used as provenance; a statement such as `direct_source_readback=true` must not substitute for the Validator's own readback.
4. Replaying the same classifier, resolver graph or highly correlated path is a consistency/equivalence check. It does **not** satisfy `validator_independence_required=true` by itself.
5. Proposal fields remain proposals. Contract `5.13` states `proposal_is_canonical_source=false`, `validator_re_resolves_source_refs=true` and `validator_source_readback_digests_required=true`.
6. Validator identity/execution must remain distinct from Curator identity/execution.

## Field classification

The classification covers all `55/55` M1.2 fields whose Curator role is `PRODUCES`, `PERSISTENCE_DERIVED`, `PRODUCES_INITIAL_STATE` or `INITIALIZES_ONLY`. The remaining 25 persisted fields are system-generated, Validator-owned or explicitly `NOT_PRODUCER` and are not Curator logical outputs.

Classification SHA256: `cf11f65a5c629dc811bd953ffb60fefb0cf997914c2858edbd6a9c94d60e2ced`.

### REFERENCE_ALLOWED — 20

May be consumed for identity, routing, provenance or correlation. Never sufficient for semantic correctness.

`input_readiness_runs.version_id`, `pantalla_id`, `universe_rule_id`, `supersedes_run_id`, `scope`, `family_count`, `curator_identity`, `curator_completed_at`, `contract_version`, `source_observed_at`, `curator_component_id`, `contract_revision`, `curator_duration_ms`; `input_family_assessments.run_id`, `family_code`; `input_gap_proposals.run_id`, `assessment_id`, `family_code`, `curator_identity`, `curator_execution_id`.

### INTEGRITY_BINDING_ALLOWED — 6

May bind the exact Curator/source snapshot that was inspected. Integrity is not correctness.

`input_readiness_runs.source_snapshot_sha256`, `universe_snapshot_sha256`, `contract_snapshot_sha256`; `input_family_assessments.curator_sha256`, `semantic_depth_sha256`; `input_gap_proposals.curator_sha256`.

### RERESOLVE_REQUIRED — 5

May be consumed only as locators/input references; current authority must be read again and digested by Validator.

`input_readiness_runs.source_manifest`; `input_family_assessments.source_refs`; `input_gap_proposals.canonical_target`, `source_refs`, `evidence_refs`.

### STATE_PRECONDITION_ONLY — 2

May gate lifecycle/control flow only; not semantic evidence.

`input_readiness_runs.status`; `input_gap_proposals.status`.

### CANDIDATE_CLAIM_ONLY — 22

May be read only as candidate claims for independent comparison/adjudication. MUST NOT be accepted as truth.

`input_family_assessments.severity`, `applicability`, `coverage_status`, `well_defined_status`, `story_ready_status`, `implementation_ready_status`, `qa_ready_status`, `production_ready_status`, `rationale`, `blockers`, `negative_requirements`, `test_obligations`, `freshness`, `curator_evidence`, `subject_coverage`, `threat_coverage`; `input_gap_proposals.gap_code`, `proposal_kind`, `proposed_payload`, `confidence`, `stage_impact`, `contradictions_checked`.

## AS-IS Validator paths

Current fingerprints at M1.3 readback:

| Path | MD5(prosrc) | Key reads / behavior | M4.1 corrected correlation |
|---|---|---|---:|
| `fn_input_governance_validator_validate_v1(bigint,text)` | `22212901a0d64947fda27eeae5f3191d` | dispatcher across bootstrap / v2 / rebind paths | dispatcher |
| `fn_input_governance_validate_v2(bigint,text)` | `b4b186c5a832d1f83bcb6db45230c0d7` | reads Curator semantic/readiness fields and compares them with `fn_input_governance_bootstrap_classify_v2`; reads refs/integrity | 29/31 shared |
| `fn_input_governance_validator_rebind_v1(bigint,text)` | `dbe48a41e796a401d39099b035400283` | builds assertions through `fn_input_v58_build_assertions`, then writes PASS/evidence | 17/17 shared |
| `fn_input_v58_build_assertions(bigint,bigint,text)` | `e0993c9ed287d632bc5107cb77ac62b6` | starts from parent Validator assertions and rebinds/templates them | helper |
| `fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)` | `6e4a524ccd85e691a2e81a4559df0e0c` | reads source refs; separate shadow/oracle candidate | not credited here as independent by mere existence |

## Current violations / debt

These are findings, not runtime changes in M1.3.

1. **`VALIDATE_V2_CORRELATED_CONCLUSION_REPLAY`** — `validate_v2` reads Curator conclusions (`severity`, `applicability`, `coverage_status`, `well_defined_status`, readiness statuses and blockers) and compares them with `fn_input_governance_bootstrap_classify_v2`. M4.1 shows the path shares 29/31 `programacion` dependencies with Curator and the classifier is shared. This is useful as a consistency check but cannot by itself satisfy independent-oracle semantics.
2. **`VALIDATOR_REBIND_NO_INDEPENDENT_ORACLE`** — M4.1 shows `validator_rebind_v1` shares 17/17 `programacion` dependencies with Curator and has no independent dependency set. It may validate rebind integrity/assertions, but the path cannot be credited as independent semantic judgment until an independent oracle boundary exists.
3. **`BOOTSTRAP_VALIDATE_HIGH_CORRELATION`** — the bootstrap validation path shares 16/17 `programacion` dependencies. A different classifier version alone is insufficient proof of independent authority.
4. **`SHARED_BUILDER_BOUNDARY_DEBT`** — M1.2 already recorded that Curator rebind and Validator rebind both use `fn_input_v58_build_assertions`. This cross-boundary reuse remains implementation debt; M1.3 does not refactor it.

## Required future implementation properties

A later implementation unit may claim independent validation only when all applicable checks below have evidence:

- one governed Validator entrypoint with explicit phases;
- direct re-resolution of canonical source refs and readback digests;
- independent oracle path for semantic correctness, not merely same-classifier replay;
- Curator conclusions are candidate claims, never authority;
- integrity hashes bind producer output without asserting correctness;
- proposal validation never promotes a proposal to canonical source;
- negative tests include same-execution identity, stale/broken refs, stored-result/source-SHA mismatch and semantic-depth mutation;
- any equivalence/shadow replay is labeled equivalence, not independence.

## Scope / R16 / R17

M1.3 changes contract documentation and records one governance ADR through a Git-first migration. It does **not** modify or execute Curator/Validator runtime. R17 runtime preflight is therefore not applicable. Runtime implementation, cutover, deploy, promotion and production remain out of scope.
