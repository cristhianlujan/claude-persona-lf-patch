# S26-HP-001 — Independent Semantic Quality Review Handoff

Use this file in a **clean reviewer chat/context** that did not produce S26-HP-001. Do not provide the reviewer with the producer conversation, previous semantic verdicts, target score, or desired result.

## Frozen identity

| Field | Immutable value |
|---|---|
| Repository | `cristhianlujan/claude-persona-lf-patch` |
| Review case | `S26-HP-001-INDEPENDENT-QUALITY-001` |
| Frozen candidate SHA | `ad267759028700f988aeb3d9bb022a1bdda0d6fb` |
| Frozen candidate branch | `lf/s26-hp001-candidate-frozen-ad267759` |
| Producer branch | `lf/s26-hp001-isolated-20260909` |
| Producer PR | `#633` |
| Artifact path | `sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/manual_profile_output.json` |
| Artifact SHA-256 | `712fcb036a4db6ded06615f0ec1c4dd7b9d475fa6208f5b9fc72c7688b9f01d6` |
| Input path | `sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/input.txt` |
| Input SHA-256 | `fdfb12f2c8c5313fef5152e1f6b6689ccae78ed94170358cf065bb02649135a1` |

## Exact user input

`Diseña una pantalla para un marketplace de servicios. Debe tener un encabezado con buscador, categorías principales, una sección de servicios destacados y tarjetas que muestren título, proveedor, precio y una llamada a la acción. El diseño debe ser claro, profesional y fácil de navegar. Entrega una especificación estructurada lista para que otro agente implemente la pantalla.`

## Immutable review sources

Resolve every source at commit `ad267759028700f988aeb3d9bb022a1bdda0d6fb`.

| Role | Path |
|---|---|
| Artifact payload | `sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/manual_profile_output.json` |
| Producer execution receipt | `sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/manual_profile_execution_receipt.json` |
| Material requirements | `sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/expected_requirements.json` |
| Upstream worker contract | `profiles/ui_architect/SKILL.md` |
| Output schema | `profiles/ui_architect/schemas/ui_production_spec.schema.json` |
| Composer boundary | `profiles/ui_architect/contracts/composer_payload_boundary_v1.md` |
| Independent-review contract | `profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md` |
| Quality gate | `profiles/quality_pack/contracts/quality_gate_contract.md` |
| LF quality controls | `profiles/quality_pack/contracts/lf_quality_controls.md` |
| Score rubric | `profiles/quality_pack/judges/quality_pack_score_rubric.md` |
| Mini judge | `profiles/quality_pack/judges/quality_pack_mini_judge.md` |
| Review schema | `profiles/quality_pack/schemas/quality_review.schema.json` |
| Receipt schema | `profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json` |
| Receipt validator | `profiles/quality_pack/validators/validate_independent_semantic_review.py` |

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-01 | The output materially preserves the requested header with search. |
| AC-02 | The output materially preserves main categories. |
| AC-03 | The output materially preserves a featured-services section. |
| AC-04 | Service cards materially expose title, provider, price, and call-to-action. |
| AC-05 | The specification supports the requested clear, professional, easy-to-navigate intent without inventing unsupported domain truth. |
| AC-06 | The result is a structured implementation handoff compatible with the UI Architect contract and Composer boundary. |
| AC-07 | CREATE_NEW does not introduce remediation actions for nonexistent prior defects. |
| AC-08 | Source-bound values such as service records, providers, prices, categories, or CTA destinations are not fabricated. |
| AC-09 | Generic “marketplace de servicios” is not silently reinterpreted as MarketPlace Libertad Financiera. |
| AC-10 | Governance-only metadata does not leak into the Composer payload. |

## Blocking criteria

| ID | Block if observed |
|---|---|
| BC-01 | A material user requirement is omitted or materially contradicted. |
| BC-02 | Unsupported service/provider/price/category/CTA/business truth is invented. |
| BC-03 | Output violates the upstream worker contract or required V6 boundary. |
| BC-04 | CREATE_NEW is treated as remediation of an assumed prior artifact. |
| BC-05 | Governance metadata becomes renderable Composer content. |
| BC-06 | Evidence needed for a positive semantic claim is missing or unresolvable from the frozen bundle. |
| BC-07 | Reviewer independence metadata is false or cannot be truthfully asserted. |

## Required reviewer procedure

Evaluate only the immutable sources above. Apply the upstream worker contract, Quality Pack gate, LF quality controls when applicable, 25-point rubric, mini judge, and review schema. Unsupported claims receive no evidence credit. Do not modify or repair the artifact. Do not infer producer intent beyond the frozen sources.

Return **only one JSON object** conforming to `profiles/quality_pack/schemas/independent_semantic_review_receipt.schema.json`. Set these execution fields truthfully:

| Field | Required value if review actually completed independently |
|---|---|
| `receipt_version` | `v0.1` |
| `execution_mode` | `INDEPENDENT_CHAT_CONTEXT` |
| `semantic_status` | `EXECUTED_INDEPENDENT_CONTEXT` |
| `review_case_id` | `S26-HP-001-INDEPENDENT-QUALITY-001` |
| `reviewer_is_producer` | `false` |
| `producer_context_available` | `false` |
| `external_paid_model_used` | `false` |
| `automated_semantic_judge_implemented` | `false` |
| `review_completed` | `true` only after the semantic review is actually complete |

After the reviewer returns the receipt, validate it deterministically with:

`python profiles/quality_pack/validators/validate_independent_semantic_review.py <receipt.json>`

If independence is not true, return a blocked/incomplete receipt according to the schema rather than fabricating an independent review.

## Claim boundary

This handoff contains **no producer-authored semantic verdict or target score**. A deterministic Happy Path PASS does not instruct the reviewer to pass the semantic review. The independent receipt is valid only for the exact artifact SHA and frozen candidate above. It does not authorize production or overall S26 Golden status.
