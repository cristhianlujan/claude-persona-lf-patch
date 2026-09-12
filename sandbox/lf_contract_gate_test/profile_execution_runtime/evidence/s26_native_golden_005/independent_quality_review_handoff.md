# S26 Run E — Independent Quality Review Handoff

## Execution boundary

This file is a locator-only frozen review bundle for an **independent** Quality Pack reviewer.

- `review_case_id`: `S26-N08E-QUALITY-001`
- required execution mode: `INDEPENDENT_CHAT_CONTEXT`
- the reviewer must run in a new chat/context that did not produce Run E
- do **not** use any producer-authored score, self-verdict, previous Run D review, or desired outcome as semantic authority
- do **not** reconstruct missing producer state
- no paid external model/API and no model-weight download
- return the independent receipt JSON only

## Exact artifact under review

- RAW artifact ref:
  `github://cristhianlujan/claude-persona-lf-patch@5044763bc3ccdd0bac5bc2ded7342a74f20f8ed3/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/raw_output.json`
- artifact byte SHA-256:
  `c93e0f11d58c8043b8374a53de257406c21e2a52dd0f426e8742bf387c21b799`
- semantic/canonical RAW SHA-256:
  `1a4ac2bd67451920c549afa0416d1b59a280a627cb1988397a6a1c74ce32d8a3`
- producer execution id:
  `EXEC-S26-N08E-GPT-NATIVE-GOLDEN-E-001`
- producer run id:
  `CHATGPT-NATIVE-S26-N08E-GOLDEN-E-001`

## Prebound upstream evidence

Use these immutable refs as the supplied upstream authority. The original PNG is provenance only; semantic review should judge the RAW against the resolver-backed observation packet and input below, without inventing additional visual facts.

- execution input:
  `github://cristhianlujan/claude-persona-lf-patch@be81529076840bd73c1a883ee504f929760c6906/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/input.txt`
- resolver-backed screen observation packet:
  `github://cristhianlujan/claude-persona-lf-patch@be81529076840bd73c1a883ee504f929760c6906/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/visual_observation_packet.json`
- visual provenance metadata:
  `github://cristhianlujan/claude-persona-lf-patch@be81529076840bd73c1a883ee504f929760c6906/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/visual_artifact_ref.json`
- fresh Input Governance snapshot:
  `github://cristhianlujan/claude-persona-lf-patch@be81529076840bd73c1a883ee504f929760c6906/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/input_governance_snapshot.json`
- fresh Router/Adapter binding snapshot:
  `github://cristhianlujan/claude-persona-lf-patch@be81529076840bd73c1a883ee504f929760c6906/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/router_adapter_binding_snapshot.json`
- governed Card:
  `github://cristhianlujan/claude-persona-lf-patch@be81529076840bd73c1a883ee504f929760c6906/cards/marketplace_lf/decision_product_experience/CARD.md`
- Adapter capsule:
  `github://cristhianlujan/claude-persona-lf-patch@be81529076840bd73c1a883ee504f929760c6906/adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml`

## Producer lineage objects to validate, not inherit

These are evidence objects. Their existence is not a semantic PASS and their producer score/self-verdict must not be adopted by the reviewer.

- execution receipt:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/execution_receipt.json`
  - internal canonical receipt SHA-256: `60d8387758b3335f322791e6b573b6f1d0513b2aa1f20f581a3572e2203300ac`
- governed context receipt:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/governed_context_receipt.json`
  - internal canonical SHA-256: `31143210721e4be0dd06907031fe2386b15af686adc1fb196459a7b7edb4cf94`
- obligation manifest:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/obligation_manifest.json`
  - canonical SHA-256: `89cc4928717a43753af0fedcd95f8fa614ec51dc042d0e7c403aeeb4ad415969`
- semantic check bundle:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005/semantic_check_bundle.json`
  - canonical SHA-256: `959d298cd87d612e1c95e937d5868e8026beb9916e7fc99c5dccb89b7752bba9`
- execution contract SHA-256 recorded in the producer receipt:
  `b292a88f133937865881ad97a94c939bf7be9b64b9a87090b111db23c987c563`
- overall producer context fingerprint:
  `ab855a0402dd4fb1c744d0cc0ac5382515c17e2be3829cc6c1d236edd800fe23`

## Worker and Quality contracts

Read these exact immutable refs before judging:

- UI Architect SKILL:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/ui_architect/SKILL.md`
- existing-screen review contract:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/ui_architect/contracts/existing_screen_review.md`
- Quality Pack SKILL:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/SKILL.md`
- independent chat semantic review contract:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md`
- Quality gate contract:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/contracts/quality_gate_contract.md`
- LF Quality controls:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/contracts/lf_quality_controls.md`
- score rubric:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/judges/quality_pack_score_rubric.md`
- mini judge:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/judges/quality_pack_mini_judge.md`
- quality review schema:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/schemas/quality_review.schema.json`
- independent receipt validator:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/validators/validate_independent_semantic_review.py`
- routing validator:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/validators/validate_routing.py`
- trusted ref resolver:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/profiles/quality_pack/validators/trusted_ref_resolver.py`
- provider-agnostic final semantic validator:
  `github://cristhianlujan/claude-persona-lf-patch@4b46c57d190a2fef280047c3ee2c3025ef7e233f/sandbox/lf_contract_gate_test/profile_execution_runtime/validate_semantic_quality.py`

## Semantic obligations to adjudicate independently

Do not assume either answer.

### `PAGINATION-DIRECTION`

Question:
`Does this action reduce pagination inconsistency using a derived non-canonical state rule, without inventing current_page or business semantics?`

Judge the exact Run E remediation action against the supplied input and observation packet. Treat unsupported state as unsupported.

### `OVERFLOW-DIRECTION`

Question:
`Does this action reduce unnecessary scroll chrome while preserving access to all columns under real overflow, without presenting the rule as canonical?`

Judge the exact Run E remediation action against the supplied input and observation packet. Do not authorize column/action removal that is not supplied upstream.

## Deterministic / governance checks

Independently verify at least:

- RAW immutable ref resolves and its byte SHA-256 matches `c93e0f11d58c8043b8374a53de257406c21e2a52dd0f426e8742bf387c21b799`
- semantic RAW canonical SHA matches the execution receipt
- execution receipt internal `receipt_sha256` validates
- obligation manifest validates and matches its canonical SHA
- semantic check bundle is exactly derivable from manifest + RAW
- producer run id in runtime attestation is `CHATGPT-NATIVE-S26-N08E-GOLDEN-E-001`
- reviewer run id is new and different
- `reviewer_is_producer=false`
- `producer_context_available=false`
- `external_paid_model_used=false`
- `automated_semantic_judge_implemented=false`
- `review_completed=true`
- `execution_mode=INDEPENDENT_CHAT_CONTEXT`
- `semantic_status=EXECUTED_INDEPENDENT_CONTEXT`
- all source refs used for gate authority are immutable/resolver-backed or explicitly treated as non-gating provenance
- no unsupported current-page state is introduced
- producer-derived interaction rules are not represented as canonical/upstream values
- shell/sidebar/topbar/company selector remain outside remediation scope
- no payment, approval, eligibility, legal, guarantee or urgency semantics are invented
- no model weights are acquired and no paid inference is used

## Receipt requirements

Return a complete receipt conforming to current Quality Pack validators. It must include `quality_review.routing`; do not omit routing even if another wrapper schema does not make it syntactically required.

Create a new `reviewer_run_id` different from the producer run id. Bind the receipt cryptographically to:

- execution id
- profile code
- producer run id
- reviewer run id
- input SHA-256
- semantic RAW SHA-256
- execution receipt canonical SHA-256
- obligation manifest canonical SHA-256
- semantic check bundle canonical SHA-256
- source bundle canonical SHA-256
- semantic binding SHA-256
- receipt SHA-256

Use `artifact_ref` equal to the immutable RAW ref above and `artifact_byte_sha256` equal to the RAW byte SHA. `semantic_raw_output_sha256` must equal the producer receipt's canonical RAW SHA.

Run both:

1. `profiles/quality_pack/validators/validate_independent_semantic_review.py`
2. `profiles/quality_pack/validators/validate_routing.py`

Then run the provider-agnostic semantic validation path against the exact Run E RAW, manifest, semantic bundle and execution receipt.

## Claim boundary

This handoff does not authorize Golden, Composer, merge, main, deployment or production. The reviewer must return the result dictated by the evidence and current contracts. Any unresolved material evidence, schema failure, routing failure, semantic uncertainty or hard LF control remains fail-closed.
