# HANDOFF_TECNICO_P0_LECTURA_VISUAL_Y_CONTEXTO_AUXILIAR_LF_v1.1

**Código del snapshot:** `P0_VISUAL_READING_ARCHITECTURE_LF_20260803`  
**Versión:** `v1.1`  
**Versión anterior:** `v1.0`  
**Ejecución:** `EXEC-BISC-P0-VISUAL-HANDOFF-004`  
**Generado:** `2026-08-04T22:11:00-05:00`  
**Estado:** `CANDIDATO_READ_ONLY`  
**Runtime:** `NO_HABILITADO`  
**Merge:** `NO AUTORIZADO`  
**Producción:** `NO AUTORIZADA`

---

## 0. Propósito

Esta versión mayor consolida la arquitectura P0 y cierra los errores históricos pendientes detectados en gobernanza, paridad, métricas, revisión humana, seguridad, evaluación e integración. Es una especificación candidata; no demuestra implementación, runtime ni calidad empírica.

Principio rector:

```text
LEER SIN CONTEXTO
→ VALIDAR
→ BLOQUEAR EL RESULTADO VISUAL
→ ADJUDICAR Y REJUZGAR CUANDO CORRESPONDA
→ RECIÉN ENRIQUECER
→ ENTREGAR A J02 SOLO UNA DECISIÓN EFECTIVA VIGENTE
```


---

## 1. Arquitectura obligatoria

| order | code | purpose |
|---|---|---|
| 1 | J01_SOURCE_INTEGRITY | Validate source identity, hashes, decodability, data classification and admission limits. |
| 2 | P0SEC_TRANSVERSE_SECURITY_PRIVACY | Cross-cutting security/privacy controls from admission through deletion; not a late sequential stage. |
| 3 | P0A_VISUAL_SOURCE_INTEGRITY | Create blind input bundle and normalized source manifest. |
| 4 | P0B_BLIND_MULTISCALE_SCAN | Global, region, tile and crop scans without auxiliary context. |
| 5 | P0C_DENSE_GEOMETRY_PARSE | Locate all visible regions and elements. |
| 6 | P0D_VISUAL_SEMANTIC_PARSE | Classify visible text, type and state separately from geometry. |
| 7 | P0E_VISUAL_STRUCTURE | Produce visual containment tree, layer graph and candidate visual reading orders. |
| 8 | P0F_VISUAL_STATE_TRANSITION_CAPTURE | Represent only states/transitions supported by source pairs and observed actions. |
| 9 | P0G_UNCERTAINTY_ABSTENTION | Calibrate, abstain and route unresolved critical observations. |
| 10 | P0H_VISUAL_COMPLETENESS_GATE | Evaluate dense coverage against governed gold/estimate rules and lock output. |
| 11 | J00_P0_VISUAL_READING | Independent judgment of P0A-P0H and transverse controls. |
| 12 | P0HR_HUMAN_ADJUDICATION | Governed human review that creates an immutable adjudication overlay. |
| 13 | J00R_P0_REJUDGMENT | Independent re-judgment of original output plus adjudication; emits effective decision for P1. |
| 14 | P0X_AUXILIARY_CONTEXT_RECONCILIATION | Optional late fusion of source-versioned auxiliary claims. |
| 15 | P0Y_ENRICHED_MODEL_GATE | Validate enriched claims without changing locked visual output. |
| 16 | J00X_P0_CONTEXT_RECONCILIATION | Independent judgment of P0X-P0Y. |
| 17 | J02_SCREEN_DECOMPOSITION | Accept only current effective P0 decision and provenance. |
| 18 | P1_STORY_PIPELINE | Continue existing story authoring and J03-J13 chain. |

---

## 2. Seguridad y privacidad transversales

P0SEC no es una etapa tardía. Sus controles comienzan en J01 y permanecen activos hasta la eliminación terminal de la evidencia.

```json
{
  "policy_version": "p0-visual-data-policy/v2",
  "prompt_injection_controls": [
    "reader_has_no_action_tools",
    "visual_text_cannot_change_policy",
    "instruction_like_text_is_flagged",
    "system_and_contract_prompts_are_immutable",
    "model_gateway_strips_tool_calls",
    "negative_suite_includes_direct_indirect_and_visual_distraction_attacks"
  ],
  "provider_training_opt_in": false,
  "raw_image_failure_retention_max_hours": 24,
  "raw_image_storage": "EPHEMERAL_BY_DEFAULT",
  "raw_image_success_retention_seconds": 0,
  "redacted_evidence_retention_days": 30,
  "required_controls": [
    "data_classification_before_persistence",
    "encryption_in_transit_and_at_rest",
    "least_privilege_access",
    "tenant_and_project_isolation",
    "PII_and_secret_detection",
    "redaction_or_approved_exception",
    "deletion_and_retention_enforcement",
    "audit_access_log",
    "minor_data_heightened_handling",
    "no_credentials_in_argv_or_logs"
  ],
  "retention_lease": {
    "delete_after_terminal_seconds": 0,
    "lease_extension_requires_reason_role_and_expiry": true,
    "redacted_evidence_may_outlive_raw_source": true,
    "retain_until": "max(terminal_state_time, human_review_expiry, security_privacy_investigation_expiry)"
  },
  "security_execution_model": "TRANSVERSE_FROM_J01_THROUGH_TERMINAL_DELETION",
  "sensitive_detection_metrics": [
    "M23_SENSITIVE_VALUE_DETECTION_RECALL",
    "M14_SENSITIVE_DATA_EVIDENCE_LEAK_RATE"
  ],
  "visual_text_trust": "UNTRUSTED_DATA"
}
```

---

## 3. Firewall ejecutable y aislamiento

```json
{
  "additionalProperties": false,
  "auxiliary_sources_before_lock": "DENIED",
  "blind_input_allowlist": [
    "tenant_id",
    "project_id",
    "screen_set_code",
    "target_screen_code",
    "source_images",
    "hashes",
    "dimensions",
    "format",
    "sequence_order",
    "state_code",
    "security_scope",
    "data_policy_version"
  ],
  "blind_input_manifest_sha256_required": true,
  "network_egress": "DENY_BY_DEFAULT",
  "separate_context_window": true,
  "separate_execution_identity": true,
  "tool_allowlist": [
    "image_decode",
    "image_crop",
    "image_resize",
    "structured_output"
  ]
}
```

---

## 4. Canonicalización RFC 8785 y hashing

```json
{
  "algorithm": "RFC8785_JCS",
  "hash_algorithm": "SHA-256",
  "input_constraints": [
    "I-JSON",
    "no duplicate property names",
    "valid Unicode without lone surrogates",
    "finite IEEE-754 double JSON numbers"
  ],
  "manifest_hash_scope": "entire manifest excluding document.canonical_manifest_sha256",
  "normative_source_id": "R11",
  "official_test_vectors_required": true,
  "runtime": "Node.js ECMAScript JSON.stringify plus recursive UTF-16 property sorting",
  "runtime_file": "P0_RFC8785_CANONICALIZER_v1.1.mjs",
  "schema_version": "p0-canonicalization/v1",
  "test_vectors": [
    {
      "expected": "{\"literals\":[null,true,false],\"numbers\":[333333333.3333333,1e+30,4.5,0.002,1e-27],\"string\":\"€$\\u000f\\nA'B\\\"\\\\\\\"/\"}",
      "id": "RFC8785_PRIMITIVES",
      "input": {
        "literals": [
          null,
          true,
          false
        ],
        "numbers": [
          333333333.3333333,
          1e+30,
          4.5,
          0.002,
          1e-27
        ],
        "string": "€$\u000f\nA'B\"\\\"/"
      }
    },
    {
      "expected": "{\"a\":1}",
      "id": "RFC8785_NUMBER_1_0",
      "input": {
        "a": 1.0
      }
    },
    {
      "expected_key_order": [
        "\r",
        "1",
        "",
        "ö",
        "€",
        "😀",
        "דּ"
      ],
      "id": "RFC8785_UTF16_SORT",
      "input": {
        "\r": "Carriage Return",
        "1": "One",
        "": "Control",
        "ö": "Latin Small Letter O With Diaeresis",
        "€": "Euro Sign",
        "דּ": "Hebrew Letter Dalet With Dagesh",
        "😀": "Emoji: Grinning Face"
      }
    }
  ]
}
```

---

## 5. Contrato de criticidad

```json
{
  "allowed_sources": [
    "GOLD_ANNOTATION",
    "APPROVED_SCREEN_POLICY"
  ],
  "approved_by_must_resolve_to_role": true,
  "authorized_approver_roles": [
    "P0_PRODUCT_RISK_OWNER",
    "P0_SECURITY_OWNER",
    "P0_PRIVACY_OWNER",
    "P0_LEGAL_OWNER",
    "P0_DATASET_CURATOR"
  ],
  "benchmark_denominator": "gold elements where criticality=true and criticality_tier in HIGH,CRITICAL",
  "conditional_rules": [
    "criticality_tier in HIGH,CRITICAL => criticality=true",
    "criticality_tier in NON_CRITICAL,IMPORTANT => criticality=false",
    "criticality=true => criticality_reason_codes non-empty",
    "criticality_reason_codes subset of allowed enum",
    "conflicting fields => BLOCKED_POLICY"
  ],
  "conflict_result": "BLOCKED_POLICY",
  "criticality_boolean_required": true,
  "criticality_reason_codes": [
    "AUTHENTICATION_OR_IDENTITY",
    "MONETARY_VALUE",
    "MONETARY_COMMITMENT",
    "LEGAL_OR_CONSENT",
    "PERSONAL_OR_SENSITIVE_DATA",
    "IRREVERSIBLE_ACTION",
    "PROCESS_FINALIZATION",
    "SAFETY_OR_FRAUD_WARNING",
    "BLOCKING_ERROR_OR_RECOVERY"
  ],
  "criticality_tiers": [
    "NON_CRITICAL",
    "IMPORTANT",
    "HIGH",
    "CRITICAL"
  ],
  "gold_annotation_governance": {
    "adjudicator_role": "P0_GOLD_ADJUDICATOR",
    "agreement_metric": "M26_GOLD_ANNOTATION_AGREEMENT",
    "annotation_policy_version_required": true,
    "blind_to_model_output_for_primary_annotation": true,
    "dataset_version_and_sha_required": true,
    "disagreement_must_be_adjudicated_before_acceptance": true,
    "label_change_log_required": true,
    "minimum_independent_annotators_for_critical_screens": 2
  },
  "gold_annotation_required_fields": [
    "criticality",
    "criticality_tier",
    "criticality_reason_codes",
    "criticality_source"
  ],
  "policy_required_fields": [
    "policy_code",
    "policy_version",
    "approved_by",
    "approved_at",
    "effective_from",
    "screen_scope",
    "reason_mapping",
    "source_sha256"
  ],
  "precedence": [
    "GOLD_ANNOTATION_FOR_BENCHMARK",
    "APPROVED_SCREEN_POLICY_FOR_PRE_GOLD_OPERATIONAL_CLASSIFICATION"
  ],
  "schema_version": "p0-criticality/v2",
  "tier_boolean_mapping": {
    "CRITICAL": true,
    "HIGH": true,
    "IMPORTANT": false,
    "NON_CRITICAL": false
  },
  "type_only_criticality_forbidden": true,
  "worker_may_assign_criticality": false
}
```

---

## 6. Gobernanza de anotaciones gold

```json
{
  "adjudicator_role": "P0_GOLD_ADJUDICATOR",
  "agreement_metric": "M26_GOLD_ANNOTATION_AGREEMENT",
  "annotation_policy_version_required": true,
  "blind_to_model_output_for_primary_annotation": true,
  "dataset_version_and_sha_required": true,
  "disagreement_must_be_adjudicated_before_acceptance": true,
  "label_change_log_required": true,
  "minimum_independent_annotators_for_critical_screens": 2
}
```

---

## 7. Estructura visual

```json
{
  "candidate_reading_orders": {
    "blind_output_allowed_basis": [
      "VISUAL_HEURISTIC_LTR_TTB",
      "VISUAL_HEURISTIC_RTL_TTB",
      "TASK_FLOW_CANDIDATE"
    ],
    "confirmed_basis": [
      "CONFIRMED_BY_AXTREE",
      "CONFIRMED_BY_DOM"
    ],
    "confirmed_order_storage": "screen_enriched_understanding.confirmed_reading_order_claims",
    "confirmed_requires_auxiliary_source_ref": true,
    "single_absolute_order_claim_forbidden": true,
    "visual_output_mutation_for_confirmation": false
  },
  "container_field": "ui_tree",
  "metric_mapping": {
    "M07_PARENT_ACCURACY": "visual containment gold parent only",
    "M21_LAYER_RELATION_F1": "gold layer relations when applicable",
    "M22_READING_ORDER_CLASSIFICATION_ACCURACY": "candidate/confirmed basis classification"
  },
  "required_substructures": [
    "visual_containment_tree",
    "visual_layer_graph",
    "candidate_reading_orders"
  ],
  "schema_version": "p0-ui-structure/v2",
  "visual_containment_tree": {
    "basis": "geometric containment plus visual grouping evidence",
    "cycles_allowed": false,
    "multiple_roots_policy": "one visual root per image/layer scope; overlays may have separate layer roots",
    "not_equivalent_to": [
      "DOM_TREE",
      "ACCESSIBILITY_TREE",
      "SEMANTIC_COMPONENT_TREE"
    ]
  },
  "visual_layer_graph": {
    "graph_not_forced_into_containment_tree": true,
    "relation_types": [
      "OVERLAY",
      "MODAL",
      "POPOVER",
      "OCCLUDES",
      "OCCLUDED_BY",
      "STICKY",
      "SCROLL_REGION",
      "PORTAL_LIKE_RELATION",
      "Z_ORDER_CANDIDATE"
    ]
  }
}
```

---

## 8. Revisión humana y retorno al pipeline

```json
{
  "adjudication_output": "human_adjudication references immutable visual_output_sha256",
  "allowed_decisions": [
    "CONFIRM_OBSERVATION",
    "CORRECT_WITH_ADJUDICATION",
    "REQUEST_NEW_CAPTURE",
    "REQUEST_ADDITIONAL_CONTEXT",
    "REJECT_AND_BLOCK",
    "ESCALATE_SECURITY",
    "ESCALATE_PRIVACY"
  ],
  "decision_routes": {
    "CONFIRM_OBSERVATION": "J00R_P0_REJUDGMENT",
    "CORRECT_WITH_ADJUDICATION": "J00R_P0_REJUDGMENT",
    "ESCALATE_PRIVACY": "P0_PRIVACY_OWNER_THEN_J00R_OR_BLOCKED",
    "ESCALATE_SECURITY": "P0_SECURITY_OWNER_THEN_J00R_OR_BLOCKED",
    "REJECT_AND_BLOCK": "BLOCKED",
    "REQUEST_ADDITIONAL_CONTEXT": "P0X_THEN_J00X_THEN_J00R",
    "REQUEST_NEW_CAPTURE": "NEW_P0_EXECUTION_FROM_J01"
  },
  "decision_schema": "human_review_decision.schema.json",
  "dual_review_disagreement": {
    "decision_rule": "majority_2_of_3",
    "result": "THIRD_INDEPENDENT_ADJUDICATOR_REQUIRED",
    "security_or_privacy_block_overrides_majority": true,
    "unresolved_after_third": "BLOCKED"
  },
  "dual_review_triggers": [
    "critical element disagreement",
    "payment or irreversible action",
    "legal consent",
    "sensitive or minor data",
    "security or privacy escalation",
    "worker/judge disagreement after quorum"
  ],
  "effective_output_contract": {
    "human_adjudication_overlay_immutable": true,
    "j00r_output_required_for_p1": true,
    "j02_accepts": [
      "J00_READY_FOR_P1",
      "J00R_READY_FOR_P1"
    ],
    "original_visual_output_immutable": true,
    "stale_or_superseded_decision_rejected": true
  },
  "packet_required_fields": [
    "review_id",
    "execution_id",
    "visual_output_ref",
    "visual_output_sha256",
    "reason_codes",
    "source_image_refs",
    "evidence_crops",
    "candidate_interpretations",
    "worker_outputs",
    "judge_findings",
    "data_classification",
    "required_reviewer_role",
    "dual_review_required",
    "created_at",
    "expires_at"
  ],
  "packet_schema": "human_review_packet.schema.json",
  "reviewer_identity_required": true,
  "reviewer_roles": [
    "P0_VISUAL_ADJUDICATOR",
    "P0_SECURITY_REVIEWER",
    "P0_PRIVACY_REVIEWER"
  ],
  "reviewer_training_and_scope_required": true,
  "schema_version": "p0-human-review/v2",
  "sla_policy_required_before_runtime": true,
  "tool_neutral_interface_contract": true,
  "visual_output_mutation_allowed": false
}
```

---

## 9. Holdouts y leakage

```json
{
  "access_policy": "least privilege with immutable access log; worker and prompt authors cannot inspect hidden labels or examples",
  "claim_before_evidence": "HOLDOUT_RISK_MANAGEMENT_CONTRACT_READY_ONLY",
  "contract_ready": true,
  "dedup_signals": [
    "cryptographic_hash",
    "perceptual_hash",
    "layout_signature",
    "embedding_similarity"
  ],
  "embedding_dissimilarity_proves_non_exposure": false,
  "embedding_similarity_role": "AUXILIARY_DUPLICATE_SIGNAL_ONLY",
  "hidden_example_debugging_forbidden": true,
  "model_release_and_evaluation_dates_recorded": true,
  "mutual_exclusion_required": true,
  "operational": false,
  "operational_evidence_required": [
    "dataset manifests",
    "access logs",
    "dedup reports",
    "rotation records",
    "evaluation run receipts"
  ],
  "recent_data_proves_non_exposure": false,
  "results_reported_by_set_origin": true,
  "risk_statement": "Foundation-model training exposure cannot be proven absent; controls manage project leakage and contamination risk.",
  "rotation_policy_required": true,
  "schema_version": "p0-holdout-governance/v2",
  "sets": [
    "CALIBRATION_SET",
    "ACCEPTANCE_SET",
    "PRIVATE_REAL_HOLDOUT",
    "ROTATING_RECENT_HOLDOUT",
    "CONTROLLED_SYNTHETIC_ADVERSARIAL_SET",
    "LOAD_TEST_SET",
    "SECURITY_ADVERSARIAL_SET"
  ],
  "synthetic_data_substitutes_real_holdout": false,
  "training_non_exposure_claim_allowed": false
}
```

---

## 10. Capacidad, idempotencia y aislamiento de tenant

```json
{
  "backpressure_policy": "Reject with BLOCKED_CAPACITY or keep queued within configured SLA; never bypass limits.",
  "cross_tenant_cache_reuse": false,
  "effective_limit_rule": "min(policy_limit, provider_capability_limit, infrastructure_limit)",
  "idempotency_key": "SHA256(tenant_id + project_id + security_scope + data_policy_version + source_hashes + blind_input_manifest_sha256 + contract_version + preprocessing_version + model_configuration_id)",
  "partial_failure_policy": "No partial screen_set may be published as complete; partial artifacts remain execution-scoped and non-reusable.",
  "policy_version": "p0-capacity-policy/v2",
  "prototype_defaults": {
    "admission_timeout_seconds": 5,
    "crop_timeout_seconds": 60,
    "dead_letter_retention_days": 30,
    "job_timeout_seconds": 180,
    "max_active_jobs_per_worker": 1,
    "max_global_concurrency": 10,
    "max_image_bytes": 15000000,
    "max_images_per_screen_set": 10,
    "max_pixels_per_image": 50000000,
    "max_total_pixels_per_screen_set": 120000000,
    "queue_capacity": 500,
    "worker_pool_size": 10
  },
  "tenant_project_namespace_required": true
}
```

---

## 11. Registro de modelos y dependencias

```json
{
  "field_availability_states": [
    "AVAILABLE",
    "NOT_APPLICABLE_WITH_REASON",
    "NOT_PUBLISHED_WITH_REASON",
    "UNVERIFIABLE_BLOCKED"
  ],
  "not_applicable_without_reason_result": "BLOCKED",
  "provider_neutral": true,
  "provider_specific_fields": {
    "container_digest": "Required for local components; provider API gateway digest/config SHA required otherwise.",
    "deprecation_date": "May be NOT_PUBLISHED_WITH_REASON; review date remains mandatory.",
    "model_weight_sha": "May be NOT_APPLICABLE_WITH_REASON for proprietary APIs."
  },
  "required_fields": [
    "configuration_id",
    "provider",
    "model_id",
    "model_version",
    "release_or_snapshot_date",
    "resolution_tier",
    "max_image_bytes",
    "max_images_per_request",
    "max_pixels",
    "structured_output_support",
    "coordinate_mode",
    "known_limitations",
    "data_retention_policy",
    "fallback_rank",
    "prompt_contract_version",
    "preprocessing_version",
    "ocr_runtime",
    "cv_runtime",
    "container_digest",
    "lockfile_sha256",
    "benchmark_result_ref",
    "calibration_result_ref",
    "approved_environments",
    "deprecation_date"
  ],
  "runtime_precondition": "No visual runtime may execute with an unregistered or uncalibrated configuration.",
  "schema_version": "p0-model-capability-registry/v2",
  "unverifiable_security_or_identity_field_result": "BLOCKED"
}
```

---

## 12. Métricas y política anti-vacuidad

```json
{
  "applicability_manifest_sha256_required": true,
  "applicability_must_be_frozen_before_results": true,
  "confidence_intervals_required_for_acceptance_metrics": true,
  "hard_gate_na_policy": "A hard gate cannot contribute PASS when N/A; acceptance remains BLOCKED unless the metric was declared outside scope before dataset access and the approved scope does not claim that capability.",
  "minimum_sample_and_denominator_enforced": true,
  "post_result_not_applicable_assignment_forbidden": true,
  "required_strata_enforced": true,
  "result_values": [
    "PASS",
    "FAIL",
    "BLOCKED_BENCHMARK",
    "NOT_APPLICABLE_WITH_PREAPPROVED_REASON",
    "REPORT_ONLY"
  ],
  "schema_version": "p0-metric-governance/v1",
  "threshold_change_after_results_forbidden": true,
  "zero_denominator_default": "BLOCKED_BENCHMARK"
}
```

### 12.1 Inventario de métricas

| code | category | formula | denominator | minimum_denominator | zero_denominator_result | gate |
|---|---|---|---|---|---|---|
| M01_CRITICAL_ELEMENT_RECALL | QUALITY | matched_gold_critical_elements / total_gold_critical_elements | gold elements where criticality=true and criticality_tier in HIGH,CRITICAL | 30 | BLOCKED_BENCHMARK | PROTOTYPE_AND_PRODUCTION |
| M02_ELEMENT_RECALL | QUALITY | matched_gold_elements / total_gold_elements | all gold elements | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M03_ELEMENT_PRECISION | QUALITY | matched_predicted_elements / total_predicted_elements | all predicted elements | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M04_TEXT_EXACT_ACCURACY | QUALITY | exact_normalized_text_matches / matched_text_bearing_elements | matched elements with visible gold text | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M05_TEXT_CHARACTER_ERROR_RATE | QUALITY | sum_levenshtein_distance / total_gold_characters | gold characters after normalization | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M06_TYPE_ACCURACY | QUALITY | exact_type_matches / matched_elements | matched elements | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M07_PARENT_ACCURACY | QUALITY | exact_parent_matches / matched_non_root_elements | matched non-root elements | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M08_STATE_ACCURACY | QUALITY | exact_visual_state_matches / state_labeled_matched_elements | matched elements with gold state | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M09_BOX_IOU_MEDIAN | QUALITY | median(intersection_over_union for matched elements) | matched elements | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M10_SMALL_ELEMENT_RECALL | QUALITY | matched_small_gold_elements / total_small_gold_elements | gold elements covering <0.1% of screen area | 50 | BLOCKED_BENCHMARK | PROTOTYPE |
| M11_EVIDENCE_COVERAGE | TRACEABILITY | predicted_elements_with_resolvable_crop_and_source_ref / total_predicted_elements | all predicted elements | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | ALL |
| M12_ACCEPTED_PREDICTION_ERROR_RATE | UNCERTAINTY | incorrect_accepted_predictions / total_accepted_predictions | accepted predictions | 100 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | PRODUCTION |
| M13_PROMPT_INJECTION_ESCAPE_RATE | SECURITY | executions_where_visual_text_changed_policy_or_triggered_tools / injection_test_executions | visual prompt-injection tests | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | ALL |
| M14_SENSITIVE_DATA_EVIDENCE_LEAK_RATE | PRIVACY | unapproved_sensitive_values_persisted / total_gold_or_seeded_sensitive_values | gold_or_seeded_sensitive_values approved for the privacy suite | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | ALL |
| M15_SCHEMA_AND_SEMANTIC_VALIDATION_RATE | CONTRACT | outputs_passing_schema_and_semantic_validator / total_outputs | all outputs | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | ALL |
| M16_P95_END_TO_END_LATENCY_SECONDS | OPERATIONS | p95(completed_at - admitted_at) | benchmark load profile | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | PROTOTYPE_TARGET |
| M17_CORRECTIVE_RETRY_RATE | OPERATIONS | corrective_retries_due_to_failure / completed_jobs | completed jobs | 100 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | PROTOTYPE_TARGET |
| M18_QUEUE_WAIT_P95_SECONDS | OPERATIONS | p95(started_at - enqueued_at) | benchmark load profile | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | PROTOTYPE_TARGET |
| M19_THROUGHPUT_SCREENS_PER_MINUTE | OPERATIONS | successfully_completed_screens / elapsed_minutes | load profile LP-P0-01 | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | PROTOTYPE_TARGET |
| M20_COST_PER_SCREEN_USD | ECONOMICS | total_provider_and_compute_cost_usd / successfully_completed_screens | benchmark load profile | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | PROTOTYPE_TARGET |
| M21_LAYER_RELATION_F1 | QUALITY | 2 * layer_relation_precision * layer_relation_recall / (layer_relation_precision + layer_relation_recall) | gold visual layer relations for fixtures where overlays, modals, popovers, occlusion, sticky or scroll relations apply | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | PROTOTYPE_WHEN_APPLICABLE |
| M22_READING_ORDER_CLASSIFICATION_ACCURACY | QUALITY | correct candidate_vs_confirmed_basis_classifications / total reading order outputs | all emitted candidate_reading_orders | 50 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | PROTOTYPE_WHEN_APPLICABLE |
| M23_SENSITIVE_VALUE_DETECTION_RECALL | PRIVACY | detected_gold_or_seeded_sensitive_values / total_gold_or_seeded_sensitive_values | gold_or_seeded_sensitive_values | 50 | BLOCKED_BENCHMARK | PROTOTYPE_AND_PRODUCTION |
| M24_CRITICAL_BOX_IOU_FLOOR | QUALITY | minimum normalized IoU margin across matched critical elements | matched critical gold elements | 30 | BLOCKED_BENCHMARK | PROTOTYPE_AND_PRODUCTION |
| M25_ADAPTIVE_EXPANSION_RATE | OPERATIONS | planned_crop_or_resolution_expansions / completed_jobs | completed jobs | 100 | NOT_APPLICABLE_WITH_PREAPPROVED_REASON | OBSERVABILITY |
| M26_GOLD_ANNOTATION_AGREEMENT | EVALUATION_GOVERNANCE | Krippendorff_alpha_or_task_appropriate_agreement over independently annotated labels and geometry | double-annotated gold items | 100 | BLOCKED_BENCHMARK | PROTOTYPE_AND_PRODUCTION |

---

## 13. Hard gates y quality floor

```json
{
  "hard_gates": [
    "M01_CRITICAL_ELEMENT_RECALL",
    "M11_EVIDENCE_COVERAGE",
    "M13_PROMPT_INJECTION_ESCAPE_RATE",
    "M14_SENSITIVE_DATA_EVIDENCE_LEAK_RATE",
    "M15_SCHEMA_AND_SEMANTIC_VALIDATION_RATE",
    "M23_SENSITIVE_VALUE_DETECTION_RECALL",
    "M24_CRITICAL_BOX_IOU_FLOOR",
    "M26_GOLD_ANNOTATION_AGREEMENT"
  ],
  "quality_floor_formula": "MIN(M01_CRITICAL_ELEMENT_RECALL,M02_ELEMENT_RECALL,M03_ELEMENT_PRECISION,M04_TEXT_EXACT_ACCURACY,M06_TYPE_ACCURACY,M07_PARENT_ACCURACY,M08_STATE_ACCURACY,M10_SMALL_ELEMENT_RECALL,M11_EVIDENCE_COVERAGE,M23_SENSITIVE_VALUE_DETECTION_RECALL)"
}
```

---

## 14. Matching y calidad geométrica crítica

```json
{
  "annotation_policy_sha256_required": true,
  "assignment": "Hungarian maximum-score one-to-one assignment per image",
  "critical_iou_tail_gate": "M24_CRITICAL_BOX_IOU_FLOOR",
  "criticality_source": "Mandatory gold criticality fields for benchmark scoring; approved versioned screen policy only for pre-gold operational routing; never predicted by evaluated worker.",
  "eligibility": {
    "other_element_min_iou": 0.5,
    "same_image_required": true,
    "small_element_area_fraction_lt": 0.001,
    "small_element_min_iou": 0.3,
    "text_similarity_support_threshold": 0.8,
    "type_or_text_support_required": true
  },
  "gold_manifest_sha256_required": true,
  "normalization": {
    "casefold": true,
    "collapse_whitespace": true,
    "strip_surrounding_punctuation": false,
    "unicode": "NFKC"
  },
  "score": "0.55*IoU + 0.25*type_compatibility + 0.20*text_similarity",
  "version": "p0-element-matching/v2"
}
```

---

## 15. Política de ejecución de evaluaciones

```json
{
  "actual_failure_reason_must_match_expected": true,
  "fixture_isolation_required": true,
  "negative_case_expected_assertion_required": true,
  "no_shared_mutable_fixture_state": true,
  "positive_regression_after_negative_result": "BLOCKED_TEST_CONTAMINATION",
  "rerun_positive_after_each_negative": true,
  "restore_canonical_positive_fixture_after_each_negative": true,
  "schema_version": "p0-evaluation-execution/v1"
}
```

---

## 16. Carriles de validación

| code | purpose | allowed_claims | forbidden_claims |
|---|---|---|---|
| ENGINEERING_SMOKE | Verify transport, schemas, locks, judge wiring, security controls and failure routing. | ['TECHNICAL_PIPELINE_VERIFIED'] | ['QUALITY_ACCEPTED', 'PRODUCTION_READY', 'READY_FOR_P1_OPERATIONAL'] |
| CONTROLLED_PILOT | Measure behavior on a small stratified real/synthetic set and refine contracts without granting acceptance. | ['PILOT_METRICS_OBSERVED', 'CONTRACT_REFINEMENT_EVIDENCE'] | ['PRODUCTION_READY', 'EMPIRICAL_ACCEPTANCE'] |
| EMPIRICAL_ACCEPTANCE | Evaluate M01-M26 on governed disjoint datasets and load/security suites. | ['EMPIRICAL_ACCEPTANCE_PASSED_IF_ALL_APPLICABLE_GATES_PASS'] | ['PERFECT_RECALL_ON_UNSEEN_OPERATIONAL_SCREENS'] |

---

## 17. Fallbacks

| error_class | action | max_retries | next |
|---|---|---|---|
| PERMANENT_INPUT | BLOCKED | 0 | owner correction |
| TRANSIENT_PROVIDER | EXPONENTIAL_BACKOFF_WITH_JITTER | 2 | dead-letter after budget |
| LOW_VISUAL_CONFIDENCE | ADAPTIVE_CROP_OR_HIGHER_RESOLUTION | 2 | human review if unresolved |
| MODEL_DISAGREEMENT | INDEPENDENT_SECOND_MODEL_OR_QUORUM | 1 | human review |
| SECURITY_RISK | BLOCKED_SECURITY | 0 | security review |
| CAPACITY | BACKPRESSURE_OR_REJECT | 0 | capacity alert |
| POLICY_OR_VERSION | BLOCKED_POLICY | 0 | governance repair |

---

## 18. Casos negativos

| id | category | severity | case | expected_result | owner |
|---|---|---|---|---|---|
| N001 | SOURCE_INTEGRITY | CRITICAL | image_sha_mismatch |  |  |
| N002 | SOURCE_INTEGRITY | CRITICAL | undecodable_or_truncated_image |  |  |
| N003 | SOURCE_INTEGRITY | HIGH | exif_orientation_changes_pixels_without_manifest |  |  |
| N004 | SOURCE_INTEGRITY | HIGH | animated_image_without_frame_policy |  |  |
| N005 | PREPROCESSING | HIGH | processed_dimensions_missing |  |  |
| N006 | PREPROCESSING | HIGH | coordinate_transform_not_reversible |  |  |
| N007 | PREPROCESSING | HIGH | dense_region_without_zoom_or_crop |  |  |
| N008 | PREPROCESSING | HIGH | crop_offset_does_not_map_to_source |  |  |
| N009 | GEOMETRY | HIGH | bounding_box_outside_image |  |  |
| N010 | GEOMETRY | HIGH | bounding_box_zero_or_negative_area |  |  |
| N011 | GEOMETRY | MEDIUM | duplicate_element_same_geometry_and_semantics |  |  |
| N012 | GEOMETRY | CRITICAL | critical_gold_element_omitted_in_benchmark |  |  |
| N013 | SEMANTICS | HIGH | visible_text_without_crop_evidence |  |  |
| N014 | SEMANTICS | HIGH | semantic_element_without_geometry |  |  |
| N015 | SEMANTICS | HIGH | unsupported_type_silently_coerced |  |  |
| N016 | SEMANTICS | HIGH | same_element_descriptions_ground_to_different_regions |  |  |
| N017 | STATE_TRANSITION | HIGH | hidden_state_invented_from_static_image |  |  |
| N018 | STATE_TRANSITION | HIGH | transition_without_action_or_source_pair |  |  |
| N019 | STATE_TRANSITION | HIGH | transition_endpoints_do_not_resolve |  |  |
| N020 | STATE_TRANSITION | MEDIUM | screens_from_different_versions_joined_as_sequence |  |  |
| N021 | ISOLATION | CRITICAL | auxiliary_context_present_in_blind_input_bundle |  |  |
| N022 | ISOLATION | CRITICAL | visual_worker_has_github_supabase_or_figma_tool_access |  |  |
| N023 | ISOLATION | CRITICAL | visual_output_not_committed_before_auxiliary_fetch |  |  |
| N024 | ISOLATION | CRITICAL | worker_and_judge_share_mutable_output_or_identity |  |  |
| N025 | SECURITY_PRIVACY | CRITICAL | visual_prompt_injection_changes_instructions |  |  |
| N026 | SECURITY_PRIVACY | CRITICAL | visual_prompt_injection_triggers_external_tool |  |  |
| N027 | SECURITY_PRIVACY | CRITICAL | sensitive_value_persisted_without_policy_or_redaction |  |  |
| N028 | SECURITY_PRIVACY | HIGH | image_decompression_bomb_or_pixel_limit_exceeded |  |  |
| N029 | UNCERTAINTY_FALLBACK | HIGH | raw_model_confidence_used_as_final_gate |  |  |
| N030 | UNCERTAINTY_FALLBACK | HIGH | hardcoded_threshold_without_calibration_record |  |  |
| N031 | UNCERTAINTY_FALLBACK | HIGH | model_disagreement_silently_resolved |  |  |
| N032 | UNCERTAINTY_FALLBACK | HIGH | permanent_input_error_retried_as_transient |  |  |
| N033 | OPERATIONS | HIGH | duplicate_request_without_idempotency_key |  |  |
| N034 | OPERATIONS | HIGH | queue_capacity_exceeded_without_backpressure |  |  |
| N035 | OPERATIONS | HIGH | provider_rate_limit_exhausts_retry_budget |  |  |
| N036 | OPERATIONS | HIGH | partial_screen_set_published_as_complete |  |  |
| N037 | GOVERNANCE | CRITICAL | markdown_manifest_supabase_or_receipt_counts_differ |  |  |
| N038 | GOVERNANCE | CRITICAL | visual_output_changed_after_lock |  |  |
| N039 | GOVERNANCE | HIGH | model_or_prompt_version_changed_without_recalibration |  |  |
| N040 | GOVERNANCE | CRITICAL | J02_accepts_unjudged_or_stale_visual_output |  |  |
| N041 | CRITICALITY | CRITICAL | gold_element_missing_mandatory_criticality_fields |  |  |
| N042 | CRITICALITY | CRITICAL | worker_assigns_or_changes_criticality_for_own_scoring |  |  |
| N043 | CRITICALITY | HIGH | unversioned_or_unapproved_screen_policy_drives_criticality |  |  |
| N044 | EVALUATION_GOVERNANCE | CRITICAL | engineering_smoke_result_claimed_as_quality_acceptance |  |  |
| N045 | EVALUATION_GOVERNANCE | CRITICAL | calibration_acceptance_or_hidden_sets_overlap |  |  |
| N046 | EVALUATION_GOVERNANCE | HIGH | embedding_dissimilarity_or_recent_date_claimed_as_proof_of_no_training_exposure |  |  |
| N047 | HUMAN_REVIEW | HIGH | human_review_packet_missing_hash_crops_reason_or_role |  |  |
| N048 | HUMAN_REVIEW | CRITICAL | reviewer_mutates_locked_visual_output_in_place |  |  |
| N049 | HUMAN_REVIEW | CRITICAL | dual_review_required_case_closed_by_single_reviewer |  |  |
| N050 | UI_STRUCTURE | HIGH | visual_reading_order_declared_absolute_without_confirming_source |  |  |
| N051 | UI_STRUCTURE | HIGH | modal_overlay_or_portal_relation_forced_into_containment_tree |  |  |
| N052 | UI_STRUCTURE | HIGH | M07_compares_visual_parent_to_DOM_or_AXTree_parent_without_mapping_contract |  |  |
| N053 | EVALUATION_GOVERNANCE | CRITICAL | hard_gate_zero_denominator | BLOCKED_BENCHMARK | J00 |
| N054 | EVALUATION_GOVERNANCE | HIGH | minimum_sample_size_not_met | BLOCKED_BENCHMARK | J00 |
| N055 | EVALUATION_GOVERNANCE | HIGH | required_stratum_empty | BLOCKED_BENCHMARK | J00 |
| N056 | EVALUATION_GOVERNANCE | HIGH | required_confidence_interval_missing | BLOCKED_BENCHMARK | J00 |
| N057 | SECURITY_PRIVACY | CRITICAL | sensitive_detector_misses_seeded_value | FAIL | J00 |
| N058 | GEOMETRY | CRITICAL | critical_box_below_applicable_iou_floor | FAIL | J00 |
| N059 | EVALUATION_GOVERNANCE | HIGH | accepted_prediction_unit_undefined | BLOCKED_CONTRACT | J00 |
| N060 | OPERATIONS | MEDIUM | planned_adaptive_expansion_counted_as_corrective_retry | FAIL_METRIC_INTEGRITY | J00 |
| N061 | GOVERNANCE | CRITICAL | canonicalizer_fails_rfc8785_official_vector | BLOCKED_CANONICALIZATION | PARITY_VALIDATOR |
| N062 | MODEL_REGISTRY | HIGH | provider_field_missing_without_na_reason | BLOCKED_MODEL_REGISTRY | J01 |
| N063 | GOVERNANCE | CRITICAL | receipt_missing_exact_parity_payload | BLOCKED_ATTESTATION | PARITY_VALIDATOR |
| N064 | GOVERNANCE | HIGH | supabase_has_research_count_without_exact_sources | BLOCKED_PARITY | PARITY_VALIDATOR |
| N065 | EVALUATION_GOVERNANCE | HIGH | positive_fixture_not_restored_after_negative | BLOCKED_TEST_CONTAMINATION | J00 |
| N066 | HUMAN_REVIEW | CRITICAL | human_decision_has_no_j00r_route | BLOCKED | J00R |
| N067 | HUMAN_REVIEW | CRITICAL | dual_reviewer_disagreement_unresolved | BLOCKED | P0HR |
| N068 | OPERATIONS | CRITICAL | idempotency_key_missing_tenant_or_project_namespace | BLOCKED_ISOLATION | J01 |
| N069 | SECURITY_PRIVACY | HIGH | raw_source_deleted_before_terminal_review_state | BLOCKED_EVIDENCE | P0HR |
| N070 | GOVERNANCE | CRITICAL | candidate_file_written_under_canonical_skill_before_manifest_promotion | BLOCKED_PACKAGE | J11 |
| N071 | UI_STRUCTURE | HIGH | dom_or_axtree_confirmation_written_into_locked_visual_output | FAIL_IMMUTABILITY | J00X |
| N072 | CRITICALITY | CRITICAL | criticality_boolean_tier_reason_inconsistent | BLOCKED_POLICY | J00 |
| N073 | EVALUATION_GOVERNANCE | HIGH | gold_annotation_without_dual_review_or_change_log | BLOCKED_BENCHMARK | J00 |
| N074 | GOVERNANCE | HIGH | contract_ready_claimed_as_operationally_proven | FAIL_CLAIM_INTEGRITY | PARITY_VALIDATOR |
| N075 | SECURITY_PRIVACY | CRITICAL | security_controls_start_only_after_visual_processing | BLOCKED_SECURITY | J01 |
| N076 | GOVERNANCE | CRITICAL | registration_receipt_not_attested_in_supabase | BLOCKED_ATTESTATION | PARITY_VALIDATOR |
| N077 | GOVERNANCE | CRITICAL | snapshot_supersession_and_registration_event_not_same_transaction | BLOCKED_ATOMICITY | PARITY_VALIDATOR |
| N078 | GOVERNANCE | HIGH | snapshot_updated_at_precedes_closure_or_attestation | BLOCKED_TIMELINE | PARITY_VALIDATOR |
| N079 | GOVERNANCE | HIGH | dry_run_claim_without_attested_receipt_evidence | BLOCKED_EVIDENCE | PARITY_VALIDATOR |
| N080 | GOVERNANCE | HIGH | snapshot_missing_registration_or_attestation_event_links | BLOCKED_TRACEABILITY | PARITY_VALIDATOR |

---

## 19. Controles preventivos de auditoría

| id | control |
|---|---|
| AC01 | Single canonical manifest generates Markdown, Supabase payload and receipt. |
| AC02 | All counts are recalculated from arrays; no author-reported counts are trusted. |
| AC03 | Exact parity is required for metrics, negatives, controls, lots, sources and formulas. |
| AC04 | v0.1 through v0.3 and v1.0 remain immutable; v1.1 is a separate minor correction with explicit predecessor v1.0. |
| AC05 | No PASS, readiness, runtime, merge or production claim is inferred from this document. |
| AC06 | J01 ordering is fixed before P0 visual processing. |
| AC07 | The blind reader receives an allowlisted input bundle with additionalProperties=false. |
| AC08 | The blind reader has no GitHub, Supabase, Figma, browser, shell or write tools. |
| AC09 | Network egress is denied except through a model gateway allowlist. |
| AC10 | Visual text is treated as untrusted data and cannot alter system policy. |
| AC11 | The visual output is committed and hashed before auxiliary context is fetched. |
| AC12 | RFC 8785 JSON Canonicalization Scheme is used for JSON hashes. |
| AC13 | Raw byte SHA, normalized pixel SHA and processing manifest SHA are all recorded. |
| AC14 | Judge execution is separate from worker execution with distinct identity and context. |
| AC15 | Judge independence level L2 is the minimum; L3 is required for critical screen classes before production. |
| AC16 | The judge never claims perfect recall on an unseen screen without gold annotations. |
| AC17 | Benchmark calibration, acceptance and hidden regression sets are disjoint. |
| AC18 | Metric matching algorithm and threshold configuration are versioned. |
| AC19 | Critical element recall is a hard gate and cannot be compensated by averages. |
| AC20 | Prompt-injection escape and sensitive-data leak targets are zero. |
| AC21 | Retries are error-class-specific; permanent input errors are not retried. |
| AC22 | Low-confidence and disagreement paths support abstention and human review. |
| AC23 | Queue backpressure, idempotency and dead-letter handling are mandatory. |
| AC24 | Provider/model, prompt, preprocessing, OCR/CV, container and weight versions are pinned. |
| AC25 | Any model, prompt, preprocessing or metric change invalidates prior calibration. |
| AC26 | Raw screenshots are ephemeral by default and excluded from model training. |
| AC27 | Sensitive crops require redaction or an approved encrypted evidence policy. |
| AC28 | No self-test substitutes for an independent benchmark or post-merge readback. |
| AC29 | No green CI check substitutes for visual runtime evidence. |
| AC30 | No artifact is added to the canonical skill inventory before its governed implementation lot. |
| AC31 | No Supabase canonical artifact update occurs before GitHub merge and applicable reconciliation. |
| AC32 | No direct main write, force update, runtime enablement or production activation is authorized. |
| AC33 | Every gold element has mandatory boolean criticality, tier, reason codes and source; missing fields block scoring. |
| AC34 | Criticality cannot be assigned or changed by the worker being evaluated; type alone never determines criticality. |
| AC35 | Engineering smoke, controlled pilot and empirical acceptance have distinct claims and cannot substitute for each other. |
| AC36 | Human review uses governed packet and decision schemas with reviewer identity, role, evidence and expiry. |
| AC37 | Human adjudication never mutates the locked visual output; it creates a separately hashed adjudication object. |
| AC38 | Dual review is mandatory for defined critical, payment, consent, sensitive-data and security/privacy cases. |
| AC39 | Training-data non-exposure is never claimed; project leakage and contamination risk are managed and reported. |
| AC40 | Embedding similarity is only a duplicate signal; dissimilarity is not evidence of non-exposure. |
| AC41 | Private real, rotating recent and controlled synthetic holdouts are combined and reported separately. |
| AC42 | UI structure separates visual containment, layer graph and candidate reading orders. |
| AC43 | Blind visual reading order is always a candidate; confirmed order requires a source reference. |
| AC44 | P0-0 distinguishes documentary parity already demonstrated from repository runtime and final-head tasks still pending. |
| AC45 | All metric applicability, denominators, minimum samples, strata and CI rules are frozen before execution. |
| AC46 | Zero denominator on any acceptance hard gate blocks benchmark acceptance. |
| AC47 | Sensitive detection recall and evidence leak rate are separate hard gates. |
| AC48 | Critical bounding boxes must pass per-element IoU floors; median cannot compensate. |
| AC49 | Accepted prediction unit is atomic element claim and is versioned. |
| AC50 | Corrective retries and planned adaptive expansions are measured separately. |
| AC51 | RFC 8785 canonicalization is executed by the versioned Node canonicalizer and official vectors. |
| AC52 | Provider-specific unavailable fields require typed N/A reasons; unverifiable security fields block. |
| AC53 | Receipt contains exact parity payload, not only counts. |
| AC54 | Supabase stores exact research sources and all parity inventories. |
| AC55 | Final registration receipt SHA is attested by a separate Supabase snapshot/event. |
| AC56 | Snapshot finalization, predecessor supersession and registration event share one transaction ID. |
| AC57 | Snapshot metadata stores registration_event_id, receipt_sha256 and receipt_attestation_event_id. |
| AC58 | updated_at is refreshed at closure and receipt attestation. |
| AC59 | Dry-run SQL digest and rollback evidence are included in the attested receipt. |
| AC60 | Every negative test restores and reruns the canonical positive fixture. |
| AC61 | Human adjudication always routes through J00R before J02. |
| AC62 | Dual-review disagreement invokes a third adjudicator and blocks if unresolved. |
| AC63 | Idempotency and caches are tenant/project/policy scoped. |
| AC64 | Raw evidence retention uses a terminal-state lease and cannot expire during review. |
| AC65 | P0-1 through P0-6 write only under the non-canonical sandbox candidate root. |
| AC66 | P0-7 promotes candidate files and updates canonical manifest in the same commit. |
| AC67 | Confirmed DOM/AXTree reading orders live only in enriched understanding. |
| AC68 | Criticality boolean, tier and reason fields obey executable conditional rules. |
| AC69 | Gold annotations use independent annotators, adjudication, versioning, SHA and change logs. |
| AC70 | Security/privacy is transverse from admission through terminal deletion. |
| AC71 | Contract-ready and operationally-proven claims are distinct booleans. |
| AC72 | Post-registration validator compares Markdown, manifest, Supabase, receipt and attestation exact payloads. |

---

## 20. Errores históricos rojos cerrados por contrato

| error_id | status | evidence_refs |
|---|---|---|
| A06 | COVERED_BY_V1_CONTRACT | ['AC53', 'AC54', 'AC72'] |
| A15 | COVERED_BY_V1_CONTRACT | ['AC55'] |
| A16 | COVERED_BY_V1_CONTRACT | ['AC56'] |
| A17 | COVERED_BY_V1_CONTRACT | ['AC58'] |
| A18 | COVERED_BY_V1_CONTRACT | ['AC57'] |
| A19 | COVERED_BY_V1_CONTRACT | ['research_sources.accessed_at'] |
| A20 | COVERED_BY_V1_CONTRACT | ['AC71'] |
| B11 | COVERED_BY_V1_CONTRACT | ['AC65', 'candidate_inventory_strategy'] |
| B12 | COVERED_BY_V1_CONTRACT | ['AC66'] |
| C15 | COVERED_BY_V1_CONTRACT | ['AC58'] |
| C16 | COVERED_BY_V1_CONTRACT | ['AC55', 'AC57'] |
| C17 | COVERED_BY_V1_CONTRACT | ['AC59'] |
| C18 | COVERED_BY_V1_CONTRACT | ['AC56'] |
| C19 | COVERED_BY_V1_CONTRACT | ['AC57'] |
| D12 | COVERED_BY_V1_CONTRACT | ['AC60'] |
| D17 | COVERED_BY_V1_CONTRACT | ['AC45', 'AC46'] |
| D18 | COVERED_BY_V1_CONTRACT | ['AC45'] |
| D19 | COVERED_BY_V1_CONTRACT | ['AC47', 'M23_SENSITIVE_VALUE_DETECTION_RECALL'] |
| D20 | COVERED_BY_V1_CONTRACT | ['AC48', 'M24_CRITICAL_BOX_IOU_FLOOR'] |
| D21 | COVERED_BY_V1_CONTRACT | ['AC49'] |
| D22 | COVERED_BY_V1_CONTRACT | ['AC50', 'M25_ADAPTIVE_EXPANSION_RATE'] |
| D23 | COVERED_BY_V1_CONTRACT | ['AC51', 'canonicalization_contract'] |
| D24 | COVERED_BY_V1_CONTRACT | ['AC52'] |
| D25 | COVERED_BY_V1_CONTRACT | ['AC53'] |
| D26 | COVERED_BY_V1_CONTRACT | ['AC54'] |
| D27 | COVERED_BY_V1_CONTRACT | ['AC72'] |
| E18 | COVERED_BY_V1_CONTRACT | ['AC68'] |
| E19 | COVERED_BY_V1_CONTRACT | ['criticality_contract.authorized_approver_roles'] |
| E20 | COVERED_BY_V1_CONTRACT | ['AC69', 'M26_GOLD_ANNOTATION_AGREEMENT'] |
| E22 | COVERED_BY_V1_CONTRACT | ['AC61'] |
| E23 | COVERED_BY_V1_CONTRACT | ['AC62'] |
| E24 | COVERED_BY_V1_CONTRACT | ['AC63'] |
| E25 | COVERED_BY_V1_CONTRACT | ['AC64'] |
| E28 | COVERED_BY_V1_CONTRACT | ['AC67'] |
| E32 | COVERED_BY_V1_CONTRACT | ['AC47'] |
| E33 | COVERED_BY_V1_CONTRACT | ['AC70'] |
| E34 | COVERED_BY_V1_CONTRACT | ['AC71'] |
| E35 | COVERED_BY_V1_CONTRACT | ['AC63'] |

---


## 20A. Controles cerrados por la auditoría PR #107

- Todos los 26 checks post-registro son obligatorios; un check ausente bloquea.
- El validador registra argv normalizado y hashes de todos los inputs.
- Ninguna métrica puede tener `required_strata=[]`; una exención requiere razón y aprobación previa.
- Los hard gates usan `BLOCKED_BENCHMARK` ante denominador cero o estrato requerido vacío.
- El receipt literal se almacena como texto UTF-8 dentro de un string JSONB y su hash se recalcula desde PostgreSQL.
- La publicación candidata usa archivos de texto directos y un gate CI que inspecciona el contenido real.
- `non_pass=0` describe solo el estado efectivo de las 64 filas current; no equivale a 64 cierres formales individuales.

---

## 21. Estrategia de inventario candidato y J11

```json
{
  "candidate_manifest": "sandbox/story_creator_p0_visual/v1.1/manifest.candidate.json",
  "candidate_package_gate_required": true,
  "candidate_root_must_match_publication_root": true,
  "canonical_j11_scope": "skills/creating-integral-user-stories/** only; candidate root is audited by P0 candidate gate until P0-7",
  "canonical_promotion_lot": "P0-7",
  "documentation_branch": "agent/p0-visual-architecture-v1",
  "documentation_pr": 107,
  "p0_lots_1_to_6_must_not_write_under_canonical_skill_root": true,
  "pre_integration_root": "sandbox/story_creator_p0_visual/v1.1/",
  "promotion_transaction": [
    "freeze candidate inventory and hashes",
    "copy/move exact approved files into skills/creating-integral-user-stories/",
    "update canonical manifest expected inventory in same commit",
    "run J11 with zero missing and zero unexpected files",
    "run J12 GitHub readback",
    "merge only after authorization",
    "update Supabase canonical inventory only after post-merge reconciliation"
  ],
  "publication_root": "sandbox/story_creator_p0_visual/v1.1/",
  "schema_version": "p0-candidate-inventory/v2",
  "unexpected_file_window_allowed": false
}
```

---

## 22. Lotes de implementación

| code | name | write_root | gate | outputs |
|---|---|---|---|---|
| P0-0 | Baseline and governance |  | Final Story Creator head reconciled; v1.1 receipt attested; exact base SHA frozen; no target-path concurrency. | ['final head readback', 'inventory parity', 'audit code allocation', 'governed task packet', 'model registry skeleton', 'repository parity validator'] |
| P0-1 | Canonical contracts and schemas | sandbox/story_creator_p0_visual/v1.1/ | Positive and negative schema fixtures pass. | ['blind input bundle schema', 'visual observation schema', 'enriched understanding schema', 'evidence schema', 'canonicalization contract', 'criticality schema', 'UI structure schema', 'human review packet and decision schemas'] |
| P0-2 | Deterministic preprocessing and security | sandbox/story_creator_p0_visual/v1.1/ | N001-N008 and N025-N028 pass. | ['image normalizer', 'pixel hash', 'transform manifest', 'prompt-injection controls', 'privacy policy enforcement'] |
| P0-3 | Visual workers and validators | sandbox/story_creator_p0_visual/v1.1/ | Dense benchmark fixtures execute. | ['multiscale scanner', 'geometry parser', 'semantic parser', 'UI tree', 'state capture', 'semantic validators'] |
| P0-4 | Independent judges and fallbacks | sandbox/story_creator_p0_visual/v1.1/ | Independence L2 and fallback negatives pass. | ['J00', 'J00X', 'uncertainty calibration', 'quorum/fallback', 'human review contract', 'dual-review policy', 'human adjudication contract'] |
| P0-5 | Staged benchmark, holdouts and load validation | sandbox/story_creator_p0_visual/v1.1/ | Smoke proves wiring only; empirical acceptance requires all applicable hard and quality gates on governed disjoint datasets. | ['engineering smoke report', 'controlled pilot report', 'calibration set', 'acceptance set', 'private real holdout', 'rotating recent holdout', 'controlled synthetic adversarial set', 'load profile', 'M01-M26 metrics report'] |
| P0-6 | P0 to P1 adapter | sandbox/story_creator_p0_visual/v1.1/ | J02 rejects stale/unjudged P0 outputs. | ['provenance mapping', 'inventory adapter', 'pending decisions', 'J02 preflight'] |
| P0-7 | Canonical integration |  | Atomic candidate promotion updates canonical files and manifest in the same commit; J11 zero missing/unexpected. | ['skill/manifest updates', 'inventory update', 'CI', 'post-merge readback', 'Supabase parity'] |

---

## 23. Registro, atomicidad, receipt y atestación

```json
{
  "attestation": {
    "event_type": "STRATEGY_SNAPSHOT_CREATED",
    "independent_readback_required": true,
    "primary_snapshot_backlink_update_required": true,
    "receipt_literal_bytes_required": true,
    "receipt_literal_sha256_recomputed_in_postgres_required": true,
    "receipt_literal_utf8_required": true,
    "recompute_expression": "encode(digest(convert_to(content_payload #>> '{receipt_storage,receipt_literal_utf8}','UTF8'),'sha256'),'hex')",
    "schema_version": "p0-supabase-receipt-attestation/v2",
    "separate_snapshot_code": "P0_VISUAL_READING_RECEIPT_ATTESTATION_LF_20260806",
    "stored_form": "UTF8_TEXT_IN_JSONB_STRING",
    "stores": [
      "receipt_sha256",
      "receipt_literal_utf8",
      "receipt_literal_bytes",
      "architecture_snapshot_id",
      "registration_event_id",
      "all canonical file hashes",
      "dry_run_evidence_sha256",
      "parity_payload_sha256"
    ]
  },
  "dry_run": {
    "evidence_embedded_in_registration_receipt": true,
    "pre_counts_and_post_counts_required": true,
    "sql_sha256_required": true,
    "transaction_rollback_required": true
  },
  "final_activation_transaction": {
    "operations": [
      "verify literal receipt hash from stored UTF-8 text",
      "verify independent readback",
      "supersede v1.0",
      "set v1.1 status CANDIDATO_READ_ONLY",
      "store activation and attestation backlinks"
    ],
    "rollback_on_any_mismatch": true,
    "single_transaction_required": true
  },
  "primary_closure_transaction": {
    "operations": [
      "mark v1.1 assembly_complete with status CANDIDATO_PENDING_ATTESTATION",
      "insert registration event",
      "store closure_txid and registration_event_id"
    ],
    "predecessor_supersession_in_primary_closure": false,
    "rollback_on_any_mismatch": true,
    "single_transaction_required": true
  },
  "receipt": {
    "exact_parity_payload_required": true,
    "receipt_sha256_required": true,
    "registration_event_id_required": true
  },
  "schema_version": "p0-registration-attestation/v2"
}
```

---

## 24. Versionado y drift

```json
{
  "change_rules": {
    "MAJOR": "Breaking schema, output semantics, hashing, judge decision or integration sequence change.",
    "MINOR": "Backward-compatible contract, metric, taxonomy, model or operational policy change.",
    "PATCH": "Editorial clarification with no schema, metric, behavior, threshold, model or execution change."
  },
  "drift_checks": [
    "weekly stratified regression while runtime is enabled",
    "immediate check after provider release or unexplained metric degradation",
    "monthly cost/latency review",
    "automatic disablement if critical recall or security/privacy hard gates fail"
  ],
  "immutable_snapshots": true,
  "mandatory_recalibration_triggers": [
    "provider change",
    "model_id or model_version change",
    "resolution tier change",
    "prompt contract change",
    "preprocessing or coordinate transform change",
    "OCR/CV runtime change",
    "element taxonomy change",
    "matching algorithm change",
    "threshold change",
    "benchmark dataset or annotation policy change"
  ],
  "schema_version": "p0-versioning-policy/v1",
  "supersession": "v1.0 remains the current candidate through primary closure; v1.1 becomes current only in a final activation transaction after receipt attestation and independent post-registration readback."
}
```

---

## 25. Fuentes de investigación

| id | title | publisher | source_version | accessed_at | url |
|---|---|---|---|---|---|
| R01 | Claude vision documentation: image sizing and visual processing | Anthropic | accessed_live | 2026-08-05T03:11:00Z | https://docs.anthropic.com/en/docs/build-with-claude/vision |
| R02 | ScreenAI: A Vision-Language Model for UI and Infographics Understanding | Google Research | published_2024 | 2026-08-05T03:11:00Z | https://research.google/pubs/screenai-a-vision-language-model-for-ui-and-infographics-understanding/ |
| R03 | OmniParser for Pure Vision Based GUI Agent | Microsoft Research | published_2024 | 2026-08-05T03:11:00Z | https://www.microsoft.com/en-us/research/publication/omniparser-for-pure-vision-based-gui-agent/ |
| R04 | Ferret-UI: Grounded Mobile UI Understanding with Multimodal LLMs | Apple Machine Learning Research | published_2024 | 2026-08-05T03:11:00Z | https://machinelearning.apple.com/research/ferretui-mobile |
| R05 | Ferret-UI 2: Mastering Universal User Interface Understanding Across Platforms | OpenReview / ICLR | published_2025 | 2026-08-05T03:11:00Z | https://openreview.net/forum?id=GBfYgjOfSe |
| R06 | Moving Beyond Sparse Grounding with Complete Screen Parsing Supervision | ICML / Microsoft Research | published_2026 | 2026-08-05T03:11:00Z | https://www.microsoft.com/en-us/research/publication/moving-beyond-sparse-grounding-with-complete-screen-parsing-supervision/ |
| R07 | SafeGround: Know When to Trust GUI Grounding Models via Uncertainty Calibration | arXiv / UCSB-UCSC | published_2026 | 2026-08-05T03:11:00Z | https://arxiv.org/abs/2602.02419 |
| R08 | Toward Autonomous UI Exploration: The UIExplorer Benchmark | OpenReview / WCUA | published_2025 | 2026-08-05T03:11:00Z | https://openreview.net/forum?id=DFPYSAyWRv |
| R09 | Do GUI Grounders Truly Understand UI Elements? | ACL Anthology / EACL Findings | published_2026 | 2026-08-05T03:11:00Z | https://aclanthology.org/2026.findings-eacl.144/ |
| R10 | Are GUI Agents Focused Enough? Automated Distraction via Semantic-level UI Element Injection | arXiv | published_2026 | 2026-08-05T03:11:00Z | https://arxiv.org/abs/2604.07831 |
| R11 | RFC 8785: JSON Canonicalization Scheme (JCS) | RFC Editor | RFC8785 | 2026-08-05T03:11:00Z | https://www.rfc-editor.org/rfc/rfc8785.html |

---

## 26. Claims permitidos

```json
{
  "architecture_complete_for_implementation_planning": true,
  "github_published_at_manifest_freeze": false,
  "holdout_risk_management_contract_ready": true,
  "holdout_risk_management_operational": false,
  "human_review_runtime_proven": false,
  "implementation_proven": false,
  "manifest_freeze_point": "PRE_REGISTRATION",
  "manifest_freeze_semantics": "Claims below describe state at canonical manifest freeze; receipt, attestation, activation and GitHub publication are external later events.",
  "perfect_visual_recall_claimed": false,
  "production_ready": false,
  "provider_or_model_selected": false,
  "provider_selection_required_before_runtime": true,
  "receipt_attested_at_manifest_freeze": false,
  "runtime_proven": false,
  "static_parity_proven_before_registration": true,
  "training_data_non_exposure_proven": false,
  "unresolved_architecture_decisions": []
}
```

---

## 27. Paridad exacta canónica

El siguiente objeto debe ser idéntico en manifest, Markdown, Supabase y receipt. Su SHA JCS es `713537771fdda72f8a3357fb1d4150eaa0d89793287f33823de81e2b78bfa277`.

```json
{
  "architecture_codes": [
    "J01_SOURCE_INTEGRITY",
    "P0SEC_TRANSVERSE_SECURITY_PRIVACY",
    "P0A_VISUAL_SOURCE_INTEGRITY",
    "P0B_BLIND_MULTISCALE_SCAN",
    "P0C_DENSE_GEOMETRY_PARSE",
    "P0D_VISUAL_SEMANTIC_PARSE",
    "P0E_VISUAL_STRUCTURE",
    "P0F_VISUAL_STATE_TRANSITION_CAPTURE",
    "P0G_UNCERTAINTY_ABSTENTION",
    "P0H_VISUAL_COMPLETENESS_GATE",
    "J00_P0_VISUAL_READING",
    "P0HR_HUMAN_ADJUDICATION",
    "J00R_P0_REJUDGMENT",
    "P0X_AUXILIARY_CONTEXT_RECONCILIATION",
    "P0Y_ENRICHED_MODEL_GATE",
    "J00X_P0_CONTEXT_RECONCILIATION",
    "J02_SCREEN_DECOMPOSITION",
    "P1_STORY_PIPELINE"
  ],
  "audit_control_ids": [
    "AC01",
    "AC02",
    "AC03",
    "AC04",
    "AC05",
    "AC06",
    "AC07",
    "AC08",
    "AC09",
    "AC10",
    "AC11",
    "AC12",
    "AC13",
    "AC14",
    "AC15",
    "AC16",
    "AC17",
    "AC18",
    "AC19",
    "AC20",
    "AC21",
    "AC22",
    "AC23",
    "AC24",
    "AC25",
    "AC26",
    "AC27",
    "AC28",
    "AC29",
    "AC30",
    "AC31",
    "AC32",
    "AC33",
    "AC34",
    "AC35",
    "AC36",
    "AC37",
    "AC38",
    "AC39",
    "AC40",
    "AC41",
    "AC42",
    "AC43",
    "AC44",
    "AC45",
    "AC46",
    "AC47",
    "AC48",
    "AC49",
    "AC50",
    "AC51",
    "AC52",
    "AC53",
    "AC54",
    "AC55",
    "AC56",
    "AC57",
    "AC58",
    "AC59",
    "AC60",
    "AC61",
    "AC62",
    "AC63",
    "AC64",
    "AC65",
    "AC66",
    "AC67",
    "AC68",
    "AC69",
    "AC70",
    "AC71",
    "AC72"
  ],
  "audit_followup_correction_ids": [
    "C1",
    "C2",
    "C3",
    "C4",
    "C5",
    "C6",
    "C7",
    "C8",
    "C9",
    "C10",
    "C11",
    "C12",
    "C13",
    "C14"
  ],
  "canonicalization_algorithm": "RFC8785_JCS",
  "canonicalizer_file": "P0_RFC8785_CANONICALIZER_v1.1.mjs",
  "counts": {
    "architecture_steps": 18,
    "audit_controls": 72,
    "audit_followup_corrections": 14,
    "auditor_findings_preempted": 21,
    "fallback_classes": 7,
    "implementation_lots": 8,
    "metrics": 26,
    "negative_cases": 80,
    "negative_categories": 15,
    "research_sources": 11,
    "resolved_historical_red_errors": 38,
    "unresolved_architecture_decisions": 0,
    "validation_tracks": 3
  },
  "hard_gates": [
    "M01_CRITICAL_ELEMENT_RECALL",
    "M11_EVIDENCE_COVERAGE",
    "M13_PROMPT_INJECTION_ESCAPE_RATE",
    "M14_SENSITIVE_DATA_EVIDENCE_LEAK_RATE",
    "M15_SCHEMA_AND_SEMANTIC_VALIDATION_RATE",
    "M23_SENSITIVE_VALUE_DETECTION_RECALL",
    "M24_CRITICAL_BOX_IOU_FLOOR",
    "M26_GOLD_ANNOTATION_AGREEMENT"
  ],
  "implementation_lot_codes": [
    "P0-0",
    "P0-1",
    "P0-2",
    "P0-3",
    "P0-4",
    "P0-5",
    "P0-6",
    "P0-7"
  ],
  "metric_codes": [
    "M01_CRITICAL_ELEMENT_RECALL",
    "M02_ELEMENT_RECALL",
    "M03_ELEMENT_PRECISION",
    "M04_TEXT_EXACT_ACCURACY",
    "M05_TEXT_CHARACTER_ERROR_RATE",
    "M06_TYPE_ACCURACY",
    "M07_PARENT_ACCURACY",
    "M08_STATE_ACCURACY",
    "M09_BOX_IOU_MEDIAN",
    "M10_SMALL_ELEMENT_RECALL",
    "M11_EVIDENCE_COVERAGE",
    "M12_ACCEPTED_PREDICTION_ERROR_RATE",
    "M13_PROMPT_INJECTION_ESCAPE_RATE",
    "M14_SENSITIVE_DATA_EVIDENCE_LEAK_RATE",
    "M15_SCHEMA_AND_SEMANTIC_VALIDATION_RATE",
    "M16_P95_END_TO_END_LATENCY_SECONDS",
    "M17_CORRECTIVE_RETRY_RATE",
    "M18_QUEUE_WAIT_P95_SECONDS",
    "M19_THROUGHPUT_SCREENS_PER_MINUTE",
    "M20_COST_PER_SCREEN_USD",
    "M21_LAYER_RELATION_F1",
    "M22_READING_ORDER_CLASSIFICATION_ACCURACY",
    "M23_SENSITIVE_VALUE_DETECTION_RECALL",
    "M24_CRITICAL_BOX_IOU_FLOOR",
    "M25_ADAPTIVE_EXPANSION_RATE",
    "M26_GOLD_ANNOTATION_AGREEMENT"
  ],
  "negative_case_ids": [
    "N001",
    "N002",
    "N003",
    "N004",
    "N005",
    "N006",
    "N007",
    "N008",
    "N009",
    "N010",
    "N011",
    "N012",
    "N013",
    "N014",
    "N015",
    "N016",
    "N017",
    "N018",
    "N019",
    "N020",
    "N021",
    "N022",
    "N023",
    "N024",
    "N025",
    "N026",
    "N027",
    "N028",
    "N029",
    "N030",
    "N031",
    "N032",
    "N033",
    "N034",
    "N035",
    "N036",
    "N037",
    "N038",
    "N039",
    "N040",
    "N041",
    "N042",
    "N043",
    "N044",
    "N045",
    "N046",
    "N047",
    "N048",
    "N049",
    "N050",
    "N051",
    "N052",
    "N053",
    "N054",
    "N055",
    "N056",
    "N057",
    "N058",
    "N059",
    "N060",
    "N061",
    "N062",
    "N063",
    "N064",
    "N065",
    "N066",
    "N067",
    "N068",
    "N069",
    "N070",
    "N071",
    "N072",
    "N073",
    "N074",
    "N075",
    "N076",
    "N077",
    "N078",
    "N079",
    "N080"
  ],
  "quality_floor_formula": "MIN(M01_CRITICAL_ELEMENT_RECALL,M02_ELEMENT_RECALL,M03_ELEMENT_PRECISION,M04_TEXT_EXACT_ACCURACY,M06_TYPE_ACCURACY,M07_PARENT_ACCURACY,M08_STATE_ACCURACY,M10_SMALL_ELEMENT_RECALL,M11_EVIDENCE_COVERAGE,M23_SENSITIVE_VALUE_DETECTION_RECALL)",
  "research_sources": [
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R01",
      "publisher": "Anthropic",
      "source_version": "accessed_live",
      "title": "Claude vision documentation: image sizing and visual processing",
      "url": "https://docs.anthropic.com/en/docs/build-with-claude/vision"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R02",
      "publisher": "Google Research",
      "source_version": "published_2024",
      "title": "ScreenAI: A Vision-Language Model for UI and Infographics Understanding",
      "url": "https://research.google/pubs/screenai-a-vision-language-model-for-ui-and-infographics-understanding/"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R03",
      "publisher": "Microsoft Research",
      "source_version": "published_2024",
      "title": "OmniParser for Pure Vision Based GUI Agent",
      "url": "https://www.microsoft.com/en-us/research/publication/omniparser-for-pure-vision-based-gui-agent/"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R04",
      "publisher": "Apple Machine Learning Research",
      "source_version": "published_2024",
      "title": "Ferret-UI: Grounded Mobile UI Understanding with Multimodal LLMs",
      "url": "https://machinelearning.apple.com/research/ferretui-mobile"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R05",
      "publisher": "OpenReview / ICLR",
      "source_version": "published_2025",
      "title": "Ferret-UI 2: Mastering Universal User Interface Understanding Across Platforms",
      "url": "https://openreview.net/forum?id=GBfYgjOfSe"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R06",
      "publisher": "ICML / Microsoft Research",
      "source_version": "published_2026",
      "title": "Moving Beyond Sparse Grounding with Complete Screen Parsing Supervision",
      "url": "https://www.microsoft.com/en-us/research/publication/moving-beyond-sparse-grounding-with-complete-screen-parsing-supervision/"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R07",
      "publisher": "arXiv / UCSB-UCSC",
      "source_version": "published_2026",
      "title": "SafeGround: Know When to Trust GUI Grounding Models via Uncertainty Calibration",
      "url": "https://arxiv.org/abs/2602.02419"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R08",
      "publisher": "OpenReview / WCUA",
      "source_version": "published_2025",
      "title": "Toward Autonomous UI Exploration: The UIExplorer Benchmark",
      "url": "https://openreview.net/forum?id=DFPYSAyWRv"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R09",
      "publisher": "ACL Anthology / EACL Findings",
      "source_version": "published_2026",
      "title": "Do GUI Grounders Truly Understand UI Elements?",
      "url": "https://aclanthology.org/2026.findings-eacl.144/"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R10",
      "publisher": "arXiv",
      "source_version": "published_2026",
      "title": "Are GUI Agents Focused Enough? Automated Distraction via Semantic-level UI Element Injection",
      "url": "https://arxiv.org/abs/2604.07831"
    },
    {
      "accessed_at": "2026-08-05T03:11:00Z",
      "id": "R11",
      "publisher": "RFC Editor",
      "source_version": "RFC8785",
      "title": "RFC 8785: JSON Canonicalization Scheme (JCS)",
      "url": "https://www.rfc-editor.org/rfc/rfc8785.html"
    }
  ],
  "resolved_error_ids": [
    "A06",
    "A15",
    "A16",
    "A17",
    "A18",
    "A19",
    "A20",
    "B11",
    "B12",
    "C15",
    "C16",
    "C17",
    "C18",
    "C19",
    "D12",
    "D17",
    "D18",
    "D19",
    "D20",
    "D21",
    "D22",
    "D23",
    "D24",
    "D25",
    "D26",
    "D27",
    "E18",
    "E19",
    "E20",
    "E22",
    "E23",
    "E24",
    "E25",
    "E28",
    "E32",
    "E33",
    "E34",
    "E35"
  ],
  "schema_version": "p0-exact-parity/v1",
  "snapshot_code": "P0_VISUAL_READING_ARCHITECTURE_LF_20260803",
  "unresolved_architecture_decisions": [],
  "validation_track_codes": [
    "ENGINEERING_SMOKE",
    "CONTROLLED_PILOT",
    "EMPIRICAL_ACCEPTANCE"
  ],
  "version": "v1.1"
}
```

---

## 27A. Freeze point y remediación de auditoría PR #107

```json
{
  "audit_remediation": {
    "all_corrections_in_single_release": "v1.1",
    "correction_count": 14,
    "correction_ids": [
      "C1",
      "C2",
      "C3",
      "C4",
      "C5",
      "C6",
      "C7",
      "C8",
      "C9",
      "C10",
      "C11",
      "C12",
      "C13",
      "C14"
    ],
    "github_publication_event_is_post_commit_external_evidence": true,
    "high_findings_closed": [
      "H-01",
      "H-02",
      "H-03"
    ],
    "low_info_findings_closed": [
      "H-10",
      "H-11",
      "H-12",
      "H-13",
      "H-14"
    ],
    "medium_findings_closed": [
      "H-04",
      "H-05",
      "H-06",
      "H-07_CONTRACT_AND_POST_COMMIT_EVENT",
      "H-08",
      "H-09"
    ],
    "source_audit": "PR107_INDEPENDENT_AUDIT_2026-08-06",
    "v1_0_immutable": true
  },
  "manifest_freeze_point": "PRE_REGISTRATION"
}
```

El manifest se congela antes del registro. Los hechos posteriores —receipt, atestación, activación y publicación GitHub— se prueban mediante artefactos externos versionados y eventos, no mutando el manifest congelado.

---

## 28. Identidad de archivos y validación

```json
{
  "canonicalizer_file": "P0_RFC8785_CANONICALIZER_v1.1.mjs",
  "manifest_file": "P0_VISUAL_READING_CANONICAL_MANIFEST_v1.1.json",
  "post_registration_validation": "HANDOFF_TECNICO_P0_LECTURA_VISUAL_VALIDATION_v1.1.json",
  "pre_registration_validation": "HANDOFF_TECNICO_P0_LECTURA_VISUAL_PRE_REGISTRATION_VALIDATION_v1.1.json",
  "receipt_attestation": "P0_SUPABASE_RECEIPT_ATTESTATION_v1.1.json",
  "registration_receipt": "P0_SUPABASE_REGISTRATION_RECEIPT_v1.1.json"
}
```

---

## 29. Condiciones para iniciar P0

```text
PR/ramas concurrentes cerradas o reconciliadas
+ head final exacto congelado
+ v1.1 vigente, receipt literal atestado y publicación GitHub registrada
+ inventario Story Creator estable
+ Task Packet gobernado
= AUTORIZABLE PARA P0-0/P0-1, NO PARA RUNTIME
```

---

## 30. Declaración final

La v1.1 es una corrección inmutable de arquitectura candidata y contrato de implementación. No declara runtime, merge, producción, calidad empírica, ausencia absoluta de leakage ni ejecución operacional de holdouts o revisión humana.
