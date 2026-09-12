# Contract — Composer Payload Boundary V1

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: `PERFIL-UI-ARCHITECT` production outputs that declare `output_contract_version="UI_PRODUCTION_SPEC_V6"`.

## Purpose
Separate the governed internal profile artifact from the only payload that Composer may consume. Internal evidence, provenance, scores, execution identifiers, routing and repository/provider traces must remain available for audit while being structurally excluded from the Composer payload.

This contract addresses leakage by construction. `render_policy=NON_RENDER` is not sufficient by itself for V6; an exact deterministic `composer_payload` projection is required.

Legacy V5 artifacts remain replayable historical evidence. They are not retroactively rewritten or requalified by this contract.

## V6 root shape
A normal V6 `PRODUCTION_UI_SPEC` uses these root fields:

- `worker`
- `output_type`
- `output_contract_version` = `UI_PRODUCTION_SPEC_V6`
- `governance_envelope`
- `deliverable_created`
- `composer_payload`
- `score`
- `handoff_to_next`
- `self_verdict`

Root operational fields are internal. Composer is authorized to consume only `composer_payload`.

## Governance envelope
`governance_envelope` is mandatory for V6 and must contain:

- `schema` = `LF_UI_GOVERNANCE_ENVELOPE_V1`
- `render_policy` = `NON_RENDER`
- `context`: an object carrying execution/provenance metadata needed for audit and downstream Quality.

`governance_envelope` must never be nested under `deliverable_created` or copied into `composer_payload`.

## Governed internal artifact
`deliverable_created` remains the evidence-bearing internal UI artifact used by deterministic and semantic validation. Existing V5 action evidence such as `semantic_authority.source_refs` and `precision_basis.source_refs` may remain there for audit and GOV-037 resolution.

For V6, `deliverable_created.governance_context` is forbidden. Execution identifiers, contract/commit hashes and global source maps belong under the root `governance_envelope.context`.

## Deterministic Composer projection
`composer_payload` must equal the deterministic projection of `deliverable_created` defined by `validators/validate_composer_payload_boundary.py`.

The projection allows only these top-level deliverable sections when present:

- `screen_definition`
- `component_tree`
- `layout_grid`
- `visual_hierarchy`
- `state_map`
- `token_map`
- `spacing_typography`
- `density_rules`
- `risk_controls`
- `remediation_actions`

The projection excludes `prompt_constraints` because those constraints may contain internal execution/provenance instructions.

Projection normalization rules:

1. Copy the allowed sections without changing UI semantics.
2. Remove `screen_definition.artifact_sha256` from Composer payload.
3. For each remediation action, retain the implementation decision and precision/authority meaning but remove nested `source_refs` from `semantic_authority` and `precision_basis`.
4. Never inject a replacement repository/provider reference into Composer payload.
5. Do not alter `precision_basis.mode`, `value_or_rule`, `proposal_status`, `semantic_authority.authority_type` or `semantic_authority.claim_boundary` when stripping evidence refs.

## Forbidden Composer metadata
The V6 Composer payload fails closed if it contains any of the following anywhere in its tree:

- keys: `governance_context`, `governance_envelope`, `source_refs`, `execution_id`, `execution_contract_sha256`, `prebound_commit_sha`, `artifact_sha256`, `receipt_sha256`, `binding_sha256`, `score`, `self_verdict`, `routing`, `worker`, `evidence_map`;
- any key ending in `_sha256`;
- string values containing `github://`, `sandbox/lf_contract_gate_test`, `supabase://`, `PASS_TO_COMPOSER`, `PASS_TO_QUALITY_PACK`, or `INDEPENDENT_CHAT_CONTEXT`.

This is a recipient-boundary rule, not a ban on those fields in the governed internal artifact.

## Handoff binding
For a V6 candidate routed to Quality/Composer:

- `handoff_to_next.payload_ref` must equal `composer_payload`;
- Quality reviews the full governed artifact plus the deterministic Composer projection;
- Composer may consume only `composer_payload` after the Orchestrator transition;
- no downstream component may substitute the full root object or `deliverable_created` for `composer_payload`.

## Semantic preservation
The boundary must not change the selected UI correction.

For S26 Run F specifically:

- pagination remains producer-derived `RELATIVE_GUIDANCE / PROPOSED_NOT_CANONICAL`;
- overflow remains producer-derived `RELATIVE_GUIDANCE / PROPOSED_NOT_CANONICAL`;
- `current_page` must not be prebound or inferred;
- all supplied table headers/actions remain preserved;
- shell/sidebar/topbar/company selector remain locked.

A payload boundary that changes any of those decisions is a semantic regression even if leakage validation passes.

## Deterministic acceptance
Strict V6 boundary PASS requires all of the following:

1. `output_contract_version` is exactly `UI_PRODUCTION_SPEC_V6`.
2. Governance envelope is valid and non-render.
3. `deliverable_created.governance_context` is absent.
4. `composer_payload` exists.
5. `composer_payload` equals the deterministic projection exactly.
6. No forbidden key/value occurs in `composer_payload`.
7. `handoff_to_next.payload_ref` equals `composer_payload`.
8. Existing UI Architect V5 validator still passes the full governed artifact.

The boundary validator does not replace the UI Architect validator, semantic judge, Quality Pack or Output Channel Gate; it adds a structural recipient boundary.
