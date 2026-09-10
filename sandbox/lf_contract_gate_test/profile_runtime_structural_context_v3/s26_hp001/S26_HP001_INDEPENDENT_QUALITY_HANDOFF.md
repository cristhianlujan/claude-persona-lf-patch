# S26-HP-001 — Independent Quality Review Handoff

## Execution boundary

Operate in a **new independent chat/context** that did not produce or repair S26-HP-001. Return **only the JSON receipt** required by the current Quality Pack independent-review contract.

- `review_case_id`: `S26-HP001-INDEPENDENT-QUALITY-001`
- required execution mode: `INDEPENDENT_CHAT_CONTEXT`
- producer/integrator context must not be available as semantic authority
- do not inherit the producer score or self-verdict
- no paid external model/API
- no model-weight download
- no production, merge, Composer execution, Supabase write or Golden declaration

## Frozen artifact under review

- immutable evidence commit: `be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652`
- runtime source that produced the artifact: `d5f27f129464163d915b08a26be08ca117385482`
- artifact ref: `github://cristhianlujan/claude-persona-lf-patch@be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_materialized_output.json`
- artifact byte SHA-256: `9f1c3c8bb90e6fc279998273d59d043273791c2e5b7793307db4be9d3e0ab5c2`
- model raw ref: `github://cristhianlujan/claude-persona-lf-patch@be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_model_output.json`
- model raw SHA-256: `8270b0ab381fed8ec3060c73bfe3cdb6ba645e184a64daa90eda22f7f75f8d1b`
- exact input ref: `github://cristhianlujan/claude-persona-lf-patch@be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/input.txt`
- exact input SHA-256: `fdfb12f2c8c5313fef5152e1f6b6689ccae78ed94170358cf065bb02649135a1`

## Deterministic evidence to validate, not inherit

- Gate F: `github://cristhianlujan/claude-persona-lf-patch@be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_output.json` — SHA `87912fce0aa9b3851cd2c43d50ce1ed1c3bc327f3da4291995e5437226838baf`
- Gate F runtime evidence: `github://cristhianlujan/claude-persona-lf-patch@be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_exact_runtime_evidence.json` — SHA `73d8d2d3afff1d7dd78c9dbf0084cb46c22cdbc00a932debda28a33d1d27470b`
- Gate G: `github://cristhianlujan/claude-persona-lf-patch@be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_g_output.json` — SHA `56639ed8529683e54ab51c41c2cad5daefd67a389c98604060a748846ad32069`
- Gate H: `github://cristhianlujan/claude-persona-lf-patch@be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_h_output.json` — SHA `4162be5a97fbee4ed96ccb0c2d5b24bbefbd914138f84def4e19e6c2e7825353`
- replay manifest: `github://cristhianlujan/claude-persona-lf-patch@be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652/sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/exact_replay_manifest.json` — SHA `830964a27ef785aa4ee83854ca937aecbbb22a92dae783e65d39d1179a202ef3`

## Contracts to read from the immutable evidence commit

- `profiles/ui_architect/SKILL.md`
- `profiles/ui_architect/schemas/ui_production_spec.schema.json`
- `profiles/ui_architect/contracts/composer_payload_boundary_v1.md`
- `profiles/quality_pack/SKILL.md`
- `profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md`
- `profiles/quality_pack/contracts/quality_gate_contract.md`
- `profiles/quality_pack/contracts/lf_quality_controls.md`
- `profiles/quality_pack/judges/quality_pack_score_rubric.md`
- `profiles/quality_pack/judges/quality_pack_mini_judge.md`
- `profiles/quality_pack/schemas/quality_review.schema.json`
- `profiles/quality_pack/validators/validate_independent_semantic_review.py`
- `profiles/quality_pack/validators/validate_routing.py`

Use immutable refs at `be3bc2227fc6cd3920fc0e7f9dc8dce7d1fb7652` for all of the above.

## Semantic questions

Judge from the supplied artifact and input only. Do not assume PASS because deterministic gates passed.

1. Does the output materially satisfy header/search, main categories, featured services, service cards, and title/provider/price/CTA?
2. Is the specification actually clear, professional, easy to navigate, and usable by the next implementation agent without inventing structure?
3. Are layout hierarchy, state mapping, typography/spacing and token guidance semantically useful rather than merely schema-filling placeholders?
4. Does it preserve source-bound values (`DATA_BOUND`, `SOURCE_DEFINED`, unresolved CTA destination) without fabricating services, prices, providers, routes, discounts or urgency?
5. Does the implementation payload avoid internal governance/receipt/runtime metadata leakage?
6. Does it stay within the generic service-marketplace scope instead of inventing LF-specific business rules?
7. Are any odd component types/zones/states or repeated generic token values materially harmful to implementation quality? Score them according to the rubric rather than normalizing them away.

## Required receipt

Top-level requirements include:
- `receipt_version = "v0.1"`
- `execution_mode = "INDEPENDENT_CHAT_CONTEXT"`
- `semantic_status = "EXECUTED_INDEPENDENT_CONTEXT"`
- `review_case_id = "S26-HP001-INDEPENDENT-QUALITY-001"`
- `reviewer_is_producer = false`
- `producer_context_available = false`
- `external_paid_model_used = false`
- `automated_semantic_judge_implemented = false`
- `review_completed = true`
- `execution_blockers = []`
- complete `source_bundle`
- complete `quality_review`, including `routing`

Apply the 25-point Quality Pack rubric exactly. Evidence-free claims score 0. Any hard LF/governance violation blocks regardless of numeric total.

Before returning the receipt, validate it with:

`python profiles/quality_pack/validators/validate_independent_semantic_review.py <receipt.json>`

and validate `quality_review.routing` with `profiles/quality_pack/validators/validate_routing.py` (or an equivalent invocation of its `validate_routing()` function if the CLI expects the inner review object).

## Claim boundary

This handoff does **not** authorize Golden. Return the independent receipt only. The integrator will validate the receipt and decide the next gate from evidence.
