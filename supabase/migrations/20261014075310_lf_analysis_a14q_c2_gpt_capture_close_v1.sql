-- A14Q_C2: stores the verified GPT Native capture (data) and then closes the checkpoint under the owner-accepted tier and the approved criterion amendment.
-- Evidence: raw output SHA-256 0611d05e497a09f00eb59e7c9b35aa97964f3570a79bab59c90496ce377df589; every value asserted below is recomputed from the stored capture against the embedded input fixture (no upstream cross-check: the holdout fixture and the blind oracle are frozen and pinned by sha).
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision documents).
BEGIN;
DO $a14q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := '1dd500b54e57e77c172ef6b58ac27da6b6168ddea3465708509d6ccbad931618';
 v_raw_text text := $raw${
  "schema_version": "A14_HOLDOUT_ANSWERS_OUTPUT_V1",
  "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
  "answers": [
    {
      "case_id": "A14-FRESH-001",
      "depth_level": "L1",
      "critical_impacts": [
        "OFFER_PERCENT_RULE"
      ],
      "material_fronts": [
        "UI_RULE"
      ],
      "blocked_scope_ids": [],
      "ready_scope_ids": [
        "S1"
      ],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "READY",
      "rationale": "Todas las condiciones de L1 se cumplen. El frente UI_RULE está ACCOUNTED con efecto PRESERVE, no hay especialistas requeridos ni scopes afectados por problemas de vigencia. Los digests coinciden y la proyección no presenta pérdida. S1 permanece disponible."
    },
    {
      "case_id": "A14-FRESH-002",
      "depth_level": "L2",
      "critical_impacts": [
        "SCHEDULE_INTERACTION"
      ],
      "material_fronts": [
        "UX_BEHAVIOR"
      ],
      "blocked_scope_ids": [],
      "ready_scope_ids": [
        "S1"
      ],
      "specialist_refs": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current"
      ],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "READY",
      "rationale": "La profundidad es L2 porque required_specialist_count=1 impide L1. El especialista PRODUCT_SCREEN tiene una referencia válida, el frente UX_BEHAVIOR está ACCOUNTED con efecto PRESERVE y el handoff conserva paridad. Ninguna regla bloquea S1."
    },
    {
      "case_id": "A14-FRESH-003",
      "depth_level": "L2",
      "critical_impacts": [
        "UPLOAD_TABLE_SEMANTICS",
        "ERROR_DOWNLOAD_FLOW"
      ],
      "material_fronts": [
        "TABLE",
        "ERROR_FLOW"
      ],
      "blocked_scope_ids": [],
      "ready_scope_ids": [
        "S1",
        "S2"
      ],
      "specialist_refs": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current",
        "capability://DATA_CONTRACT_SPECIALIST@current"
      ],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "READY",
      "rationale": "La materialidad MEDIUM y los dos especialistas requeridos determinan L2. Ambos especialistas tienen referencias válidas. TABLE y ERROR_FLOW están ACCOUNTED con PRESERVE, incluyendo el impacto indirecto crítico. El handoff pasa y ninguno de los dos scopes queda bloqueado."
    },
    {
      "case_id": "A14-FRESH-004",
      "depth_level": "L2",
      "critical_impacts": [
        "APPROVAL_ACTIONS"
      ],
      "material_fronts": [
        "SPECIALIST_GAP"
      ],
      "blocked_scope_ids": [
        "S2"
      ],
      "ready_scope_ids": [
        "S1"
      ],
      "specialist_refs": [],
      "missing_required_specialists": [
        "POLICY_SPECIALIST"
      ],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "PARTIAL_READY",
      "rationale": "La materialidad UNKNOWN, una señal material sin resolver y un especialista requerido determinan L2. POLICY_SPECIALIST tiene matched_ref=null y bloquea exclusivamente S2. El frente SPECIALIST_GAP está ACCOUNTED con PRESERVE y el handoff pasa, por lo que S1 no queda bloqueado."
    },
    {
      "case_id": "A14-FRESH-005",
      "depth_level": "L2",
      "critical_impacts": [
        "API_HEADER_CONTRACT"
      ],
      "material_fronts": [
        "API_CONTRACT"
      ],
      "blocked_scope_ids": [],
      "ready_scope_ids": [
        "S1"
      ],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "READY",
      "rationale": "La materialidad MEDIUM establece L2 sin señales de precedencia L3. API_CONTRACT está ACCOUNTED con PRESERVE, la vigencia es CURRENT y la paridad del handoff es válida. No se identifica ninguna condición que bloquee S1."
    },
    {
      "case_id": "A14-FRESH-006",
      "depth_level": "L3",
      "critical_impacts": [
        "SCHEMA_COMPATIBILITY",
        "MIGRATION_PARITY"
      ],
      "material_fronts": [
        "SCHEMA"
      ],
      "blocked_scope_ids": [],
      "ready_scope_ids": [
        "S1"
      ],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "READY",
      "rationale": "La materialidad HIGH activa L3 por precedencia. El nivel de profundidad no bloquea automáticamente un scope. SCHEMA está ACCOUNTED con PRESERVE, no existen especialistas faltantes ni problemas de vigencia o paridad. Por las reglas suministradas, S1 queda disponible."
    },
    {
      "case_id": "A14-FRESH-007",
      "depth_level": "L3",
      "critical_impacts": [
        "RULE_READ"
      ],
      "material_fronts": [
        "CURRENTNESS"
      ],
      "blocked_scope_ids": [
        "S1"
      ],
      "ready_scope_ids": [
        "S2"
      ],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "PARTIAL_READY",
      "rationale": "STALE_AFFECTED activa L3 y bloquea el scope S1 identificado en evidence.currentness.affected_scope_ids. El frente CURRENTNESS está ACCOUNTED con PRESERVE y no bloquea por sí mismo. S2 no está afectado por la pérdida de vigencia y el handoff pasa."
    },
    {
      "case_id": "A14-FRESH-008",
      "depth_level": "L3",
      "critical_impacts": [
        "STATE_CONTRADICTION"
      ],
      "material_fronts": [
        "SEMANTIC_CONTRADICTION"
      ],
      "blocked_scope_ids": [
        "S1"
      ],
      "ready_scope_ids": [],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "BLOCKED",
      "rationale": "material_contradiction=true activa L3. El frente material SEMANTIC_CONTRADICTION tiene status BLOCKED y effect_on_scope=BLOCKS, por lo que bloquea S1. Aunque el handoff pasa, el único scope permanece bloqueado."
    },
    {
      "case_id": "A14-FRESH-009",
      "depth_level": "L3",
      "critical_impacts": [
        "CAPABILITY_CHANGE",
        "DOWNSTREAM_CONSUMER_BREAK"
      ],
      "material_fronts": [
        "SECOND_ORDER"
      ],
      "blocked_scope_ids": [],
      "ready_scope_ids": [
        "S1",
        "S2"
      ],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "READY",
      "rationale": "known_cross_scope_impact=true activa L3 y el impacto de segundo orden DOWNSTREAM_CONSUMER_BREAK se incorpora a los impactos críticos. El frente SECOND_ORDER está ACCOUNTED con PRESERVE, el handoff pasa y ninguna regla suministrada bloquea S1 ni S2."
    },
    {
      "case_id": "A14-FRESH-010",
      "depth_level": "L2",
      "critical_impacts": [
        "HANDOFF_SCHEMA"
      ],
      "material_fronts": [
        "HANDOFF"
      ],
      "blocked_scope_ids": [
        "S1"
      ],
      "ready_scope_ids": [],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "BLOCK",
      "lossy_projection_detected": false,
      "verdict": "BLOCKED",
      "rationale": "La materialidad MEDIUM y una señal material pendiente determinan L2. Los digests de esquema de productor y receptor son diferentes, por lo que falla la paridad del handoff. Además, HANDOFF tiene status BLOCKED con efecto BLOCKS. Ambas condiciones bloquean S1."
    },
    {
      "case_id": "A14-FRESH-011",
      "depth_level": "L2",
      "critical_impacts": [
        "SUMMARY_PROJECTION"
      ],
      "material_fronts": [
        "PROJECTION"
      ],
      "blocked_scope_ids": [
        "S1"
      ],
      "ready_scope_ids": [],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "BLOCK",
      "lossy_projection_detected": true,
      "verdict": "BLOCKED",
      "rationale": "La reversibilidad UNKNOWN y una señal material sin resolver determinan L2. handoff.lossy_projection=true invalida la paridad aun cuando los digests coincidan. El frente PROJECTION también está BLOCKED con efecto BLOCKS. El único scope S1 queda bloqueado."
    },
    {
      "case_id": "A14-FRESH-012",
      "depth_level": "L1",
      "critical_impacts": [
        "METADATA_TRACE"
      ],
      "material_fronts": [
        "TRACEABILITY"
      ],
      "blocked_scope_ids": [],
      "ready_scope_ids": [
        "S1"
      ],
      "specialist_refs": [],
      "missing_required_specialists": [],
      "handoff_parity": "PASS",
      "lossy_projection_detected": false,
      "verdict": "READY",
      "rationale": "Todas las condiciones exigidas para L1 están satisfechas. TRACEABILITY está ACCOUNTED con PRESERVE, los digests del handoff coinciden, no hay pérdida de proyección ni especialistas faltantes. Ninguna regla bloquea S1."
    }
  ],
  "answers_statement": "Se produjeron las respuestas para los doce casos holdout aplicando únicamente las reglas y los datos suministrados. Se calcularon las profundidades, impactos críticos, frentes, especialistas, paridad del handoff y disponibilidad de scopes sin inferir información externa. READY y PARTIAL_READY son resultados de clasificación derivados de las reglas del conjunto de casos, no autorizaciones reales de programación o despliegue. No se ejecutó ningún caso, no se realizaron mediciones y no se compararon estas respuestas contra un oráculo."
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser at capture time (56570 bytes, after the A14Q_C2 reply); the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"d3869859c5c7643815d61915d0020d904d17f27daf326606bfd0c33b2add5444","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"bf435cdf0e3635c4116fa300ac2fd51fe0e359875da2e3241410e410a96686b2","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"0611d05e497a09f00eb59e7c9b35aa97964f3570a79bab59c90496ce377df589","request_sha256":"4526ea6f4a8dbe7cd2d131dc0f0c49c1cd8101087f8213480fe362313f36ba7b","run_id":"A14Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A14","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A14Q/A14Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a14q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_raw jsonb; v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text;
 v_in jsonb; v_or jsonb;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_raw := v_raw_text::jsonb;

 v_in:=$in${
  "case_set_id": "A14-FRESH-20261007-V1",
  "cases": [
    {
      "case_id": "A14-FRESH-001",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/001/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "OFFER_PERCENT_RULE",
            "source_ref": "fixture://a14/001/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "UI_RULE",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/001/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/001/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receipt_context_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receiver_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-002",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/002/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SCHEDULE_INTERACTION",
            "source_ref": "fixture://a14/002/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "UX_BEHAVIOR",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/002/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/002/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receipt_context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receiver_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 1,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S1"
          ],
          "matched_ref": "capability://PRODUCT_SCREEN_SPECIALIST@current",
          "required": true,
          "specialist_type": "PRODUCT_SCREEN"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-003",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/003/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "UPLOAD_TABLE_SEMANTICS",
            "source_ref": "fixture://a14/003/i1"
          }
        ],
        "indirect_impacts": [
          {
            "critical": true,
            "impact_id": "ERROR_DOWNLOAD_FLOW",
            "source_ref": "fixture://a14/003/i2"
          }
        ],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "TABLE",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/003/f1"
            ],
            "status": "ACCOUNTED"
          },
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "ERROR_FLOW",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/003/f2"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/003/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "DATA_SCOPE",
            "source_ref": "fixture://a14/003/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receipt_context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receiver_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 2,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S1"
          ],
          "matched_ref": "capability://PRODUCT_SCREEN_SPECIALIST@current",
          "required": true,
          "specialist_type": "PRODUCT_SCREEN"
        },
        {
          "affected_scope_ids": [
            "S2"
          ],
          "matched_ref": "capability://DATA_CONTRACT_SPECIALIST@current",
          "required": true,
          "specialist_type": "DATA_CONTRACT"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-004",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/004/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "APPROVAL_ACTIONS",
            "source_ref": "fixture://a14/004/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SPECIALIST_GAP",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/004/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/004/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "POLICY_SCOPE",
            "source_ref": "fixture://a14/004/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receipt_context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receiver_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "UNKNOWN",
        "required_specialist_count": 1,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S2"
          ],
          "matched_ref": null,
          "required": true,
          "specialist_type": "POLICY_SPECIALIST"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-005",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/005/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "API_HEADER_CONTRACT",
            "source_ref": "fixture://a14/005/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "API_CONTRACT",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/005/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "API_SCOPE",
            "source_ref": "fixture://a14/005/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receipt_context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receiver_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-006",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/006/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SCHEMA_COMPATIBILITY",
            "source_ref": "fixture://a14/006/i1"
          }
        ],
        "indirect_impacts": [
          {
            "critical": true,
            "impact_id": "MIGRATION_PARITY",
            "source_ref": "fixture://a14/006/i2"
          }
        ],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SCHEMA",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/006/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "DATA_SCOPE",
            "source_ref": "fixture://a14/006/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receipt_context_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "receiver_schema_digest_sha256": "6666666666666666666666666666666666666666666666666666666666666666"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "HIGH",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-007",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [
            "S1"
          ],
          "decision": "STALE_AFFECTED",
          "source_ref": "fixture://a14/007/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "RULE_READ",
            "source_ref": "fixture://a14/007/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "CURRENTNESS",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/007/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "RULE_SCOPE",
            "source_ref": "fixture://a14/007/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "RULE_SCOPE",
            "source_ref": "fixture://a14/007/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "receipt_context_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "receiver_schema_digest_sha256": "7777777777777777777777777777777777777777777777777777777777777777"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "STALE_AFFECTED",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-008",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/008/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "STATE_CONTRADICTION",
            "source_ref": "fixture://a14/008/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "SEMANTIC_CONTRADICTION",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/008/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "WORKFLOW_SCOPE",
            "source_ref": "fixture://a14/008/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "receipt_context_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receiver_schema_digest_sha256": "8888888888888888888888888888888888888888888888888888888888888888"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": true,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-009",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/009/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "CAPABILITY_CHANGE",
            "source_ref": "fixture://a14/009/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SECOND_ORDER",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/009/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "CAPABILITY_SCOPE",
            "source_ref": "fixture://a14/009/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "CONSUMER_SCOPE",
            "source_ref": "fixture://a14/009/s2"
          }
        ],
        "second_order_impacts": [
          {
            "critical": true,
            "impact_id": "DOWNSTREAM_CONSUMER_BREAK",
            "source_ref": "fixture://a14/009/i2"
          }
        ]
      },
      "handoff": {
        "context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receipt_context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receiver_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": true,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-010",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/010/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "HANDOFF_SCHEMA",
            "source_ref": "fixture://a14/010/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "HANDOFF",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/010/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "HANDOFF_SCOPE",
            "source_ref": "fixture://a14/010/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receipt_context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receiver_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-011",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/011/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SUMMARY_PROJECTION",
            "source_ref": "fixture://a14/011/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "PROJECTION",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/011/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/011/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "lossy_projection": true,
        "producer_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receipt_context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receiver_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "UNKNOWN",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-012",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/012/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "METADATA_TRACE",
            "source_ref": "fixture://a14/012/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "TRACEABILITY",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/012/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "GOVERNANCE_SCOPE",
            "source_ref": "fixture://a14/012/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receipt_context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receiver_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    }
  ],
  "rules": {
    "blocked_scope_ids": "Un scope queda bloqueado si: (a) un frente material tiene status BLOCKED, UNRESOLVED, NEED_MORE_EVIDENCE o REQUIRES_DECISION: se bloquean los scope_ids de ese frente; (b) evidence.currentness.decision es STALE_AFFECTED o UNKNOWN_FAIL_CLOSED: se bloquean evidence.currentness.affected_scope_ids; (c) un specialist_requirement con required=true y matched_ref=null: se bloquean sus affected_scope_ids; (d) el handoff no pasa (ver handoff_parity): se bloquean TODOS los scopes; (e) los frentes materiales son inconsistentes (front_id repetido o vacío, scope_ids vacío o fuera de los scopes del caso, status fuera de ACCOUNTED/BLOCKED/UNRESOLVED/NEED_MORE_EVIDENCE/REQUIRES_DECISION, status distinto de ACCOUNTED con effect_on_scope distinto de BLOCKS, o status ACCOUNTED con effect_on_scope distinto de PRESERVE): se bloquean TODOS los scopes. Un frente ACCOUNTED con effect_on_scope PRESERVE no bloquea nada.",
    "critical_impacts": "Lista sin repetidos (en orden de aparición) de impact_id de los impactos con critical=true en evidence.direct_impacts, evidence.indirect_impacts y evidence.second_order_impacts.",
    "depth_level": "Se calcula solo con el objeto signals del caso, con esta política de precedencia sin pesos: L3 si se cumple cualquiera de L3_if_any; si no, L2 si se cumple cualquiera de L2_if_no_L3_and_any; L1 solo si se cumplen todas las condiciones de L1_requires_all. La profundidad no es permiso de ejecución.",
    "depth_policy": {
      "L1_requires_all": [
        "materiality_level=LOW",
        "scope_bounded=TRUE",
        "authority_state=SUFFICIENT",
        "reversibility_state=DEMONSTRATED",
        "currentness_decision=CURRENT",
        "material_contradiction=false",
        "known_cross_scope_impact=false",
        "unresolved_material_signal_count=0",
        "required_specialist_count=0"
      ],
      "L2_if_no_L3_and_any": [
        "materiality_level in [MEDIUM,UNKNOWN]",
        "scope_bounded=UNKNOWN",
        "authority_state=UNKNOWN",
        "reversibility_state in [NOT_DEMONSTRATED,UNKNOWN]",
        "currentness_decision in [CURRENT_REBOUND,UNKNOWN_FAIL_CLOSED,UNRESOLVED]",
        "known_cross_scope_impact=UNKNOWN",
        "unresolved_material_signal_count>0",
        "required_specialist_count>0"
      ],
      "L3_if_any": [
        "materiality_level=HIGH",
        "scope_bounded=FALSE",
        "authority_state=INSUFFICIENT",
        "currentness_decision=STALE_AFFECTED",
        "material_contradiction=true",
        "known_cross_scope_impact=true"
      ],
      "precedence": [
        "L3_EXPLICIT_HIGH_RISK",
        "L2_MEDIUM_OR_UNPROVEN",
        "L1_FULLY_BOUNDED_LOW_RISK"
      ],
      "signals": {
        "authority_state": [
          "SUFFICIENT",
          "INSUFFICIENT",
          "UNKNOWN"
        ],
        "currentness_decision": [
          "CURRENT",
          "CURRENT_REBOUND",
          "STALE_AFFECTED",
          "UNKNOWN_FAIL_CLOSED",
          "UNRESOLVED"
        ],
        "known_cross_scope_impact": "BOOLEAN_OR_UNKNOWN",
        "material_contradiction": "BOOLEAN",
        "materiality_level": [
          "LOW",
          "MEDIUM",
          "HIGH",
          "UNKNOWN"
        ],
        "required_specialist_count": "NON_NEGATIVE_INTEGER",
        "reversibility_state": [
          "DEMONSTRATED",
          "NOT_DEMONSTRATED",
          "UNKNOWN"
        ],
        "scope_bounded": [
          "TRUE",
          "FALSE",
          "UNKNOWN"
        ],
        "unresolved_material_signal_count": "NON_NEGATIVE_INTEGER"
      }
    },
    "handoff_parity": "PASS solo si los cuatro digests (producer_schema_digest_sha256, receiver_schema_digest_sha256, context_sha256, receipt_context_sha256) son cadenas de 64 caracteres hexadecimales en minúscula, producer_schema_digest_sha256 es igual a receiver_schema_digest_sha256, context_sha256 es igual a receipt_context_sha256 y lossy_projection es false. En cualquier otro caso BLOCK.",
    "lossy_projection_detected": "true si handoff.lossy_projection es true; si no, false.",
    "material_fronts": "Lista sin repetidos de front_id de evidence.material_fronts con material=true.",
    "missing_required_specialists": "Lista de specialist_type de los requirements con required=true y matched_ref=null.",
    "ready_scope_ids": "Todos los scope_id del caso que no están bloqueados.",
    "specialist_refs": "Lista de matched_ref no nulos de los specialist_requirements.",
    "verdict": "READY si ningún scope está bloqueado; BLOCKED si todos los scopes están bloqueados; PARTIAL_READY en otro caso."
  },
  "schema_version": "A14_INPUT_HOLDOUT_V1"
}
$in$::jsonb;
 IF encode(sha256(convert_to(rtrim($in${
  "case_set_id": "A14-FRESH-20261007-V1",
  "cases": [
    {
      "case_id": "A14-FRESH-001",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/001/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "OFFER_PERCENT_RULE",
            "source_ref": "fixture://a14/001/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "UI_RULE",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/001/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/001/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receipt_context_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receiver_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-002",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/002/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SCHEDULE_INTERACTION",
            "source_ref": "fixture://a14/002/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "UX_BEHAVIOR",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/002/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/002/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receipt_context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receiver_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 1,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S1"
          ],
          "matched_ref": "capability://PRODUCT_SCREEN_SPECIALIST@current",
          "required": true,
          "specialist_type": "PRODUCT_SCREEN"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-003",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/003/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "UPLOAD_TABLE_SEMANTICS",
            "source_ref": "fixture://a14/003/i1"
          }
        ],
        "indirect_impacts": [
          {
            "critical": true,
            "impact_id": "ERROR_DOWNLOAD_FLOW",
            "source_ref": "fixture://a14/003/i2"
          }
        ],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "TABLE",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/003/f1"
            ],
            "status": "ACCOUNTED"
          },
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "ERROR_FLOW",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/003/f2"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/003/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "DATA_SCOPE",
            "source_ref": "fixture://a14/003/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receipt_context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receiver_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 2,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S1"
          ],
          "matched_ref": "capability://PRODUCT_SCREEN_SPECIALIST@current",
          "required": true,
          "specialist_type": "PRODUCT_SCREEN"
        },
        {
          "affected_scope_ids": [
            "S2"
          ],
          "matched_ref": "capability://DATA_CONTRACT_SPECIALIST@current",
          "required": true,
          "specialist_type": "DATA_CONTRACT"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-004",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/004/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "APPROVAL_ACTIONS",
            "source_ref": "fixture://a14/004/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SPECIALIST_GAP",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/004/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/004/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "POLICY_SCOPE",
            "source_ref": "fixture://a14/004/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receipt_context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receiver_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "UNKNOWN",
        "required_specialist_count": 1,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S2"
          ],
          "matched_ref": null,
          "required": true,
          "specialist_type": "POLICY_SPECIALIST"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-005",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/005/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "API_HEADER_CONTRACT",
            "source_ref": "fixture://a14/005/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "API_CONTRACT",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/005/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "API_SCOPE",
            "source_ref": "fixture://a14/005/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receipt_context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receiver_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-006",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/006/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SCHEMA_COMPATIBILITY",
            "source_ref": "fixture://a14/006/i1"
          }
        ],
        "indirect_impacts": [
          {
            "critical": true,
            "impact_id": "MIGRATION_PARITY",
            "source_ref": "fixture://a14/006/i2"
          }
        ],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SCHEMA",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/006/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "DATA_SCOPE",
            "source_ref": "fixture://a14/006/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receipt_context_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "receiver_schema_digest_sha256": "6666666666666666666666666666666666666666666666666666666666666666"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "HIGH",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-007",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [
            "S1"
          ],
          "decision": "STALE_AFFECTED",
          "source_ref": "fixture://a14/007/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "RULE_READ",
            "source_ref": "fixture://a14/007/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "CURRENTNESS",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/007/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "RULE_SCOPE",
            "source_ref": "fixture://a14/007/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "RULE_SCOPE",
            "source_ref": "fixture://a14/007/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "receipt_context_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "receiver_schema_digest_sha256": "7777777777777777777777777777777777777777777777777777777777777777"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "STALE_AFFECTED",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-008",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/008/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "STATE_CONTRADICTION",
            "source_ref": "fixture://a14/008/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "SEMANTIC_CONTRADICTION",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/008/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "WORKFLOW_SCOPE",
            "source_ref": "fixture://a14/008/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "receipt_context_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receiver_schema_digest_sha256": "8888888888888888888888888888888888888888888888888888888888888888"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": true,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-009",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/009/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "CAPABILITY_CHANGE",
            "source_ref": "fixture://a14/009/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SECOND_ORDER",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/009/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "CAPABILITY_SCOPE",
            "source_ref": "fixture://a14/009/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "CONSUMER_SCOPE",
            "source_ref": "fixture://a14/009/s2"
          }
        ],
        "second_order_impacts": [
          {
            "critical": true,
            "impact_id": "DOWNSTREAM_CONSUMER_BREAK",
            "source_ref": "fixture://a14/009/i2"
          }
        ]
      },
      "handoff": {
        "context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receipt_context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receiver_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": true,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-010",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/010/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "HANDOFF_SCHEMA",
            "source_ref": "fixture://a14/010/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "HANDOFF",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/010/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "HANDOFF_SCOPE",
            "source_ref": "fixture://a14/010/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receipt_context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receiver_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-011",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/011/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SUMMARY_PROJECTION",
            "source_ref": "fixture://a14/011/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "PROJECTION",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/011/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/011/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "lossy_projection": true,
        "producer_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receipt_context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receiver_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "UNKNOWN",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-012",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/012/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "METADATA_TRACE",
            "source_ref": "fixture://a14/012/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "TRACEABILITY",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/012/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "GOVERNANCE_SCOPE",
            "source_ref": "fixture://a14/012/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receipt_context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receiver_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    }
  ],
  "rules": {
    "blocked_scope_ids": "Un scope queda bloqueado si: (a) un frente material tiene status BLOCKED, UNRESOLVED, NEED_MORE_EVIDENCE o REQUIRES_DECISION: se bloquean los scope_ids de ese frente; (b) evidence.currentness.decision es STALE_AFFECTED o UNKNOWN_FAIL_CLOSED: se bloquean evidence.currentness.affected_scope_ids; (c) un specialist_requirement con required=true y matched_ref=null: se bloquean sus affected_scope_ids; (d) el handoff no pasa (ver handoff_parity): se bloquean TODOS los scopes; (e) los frentes materiales son inconsistentes (front_id repetido o vacío, scope_ids vacío o fuera de los scopes del caso, status fuera de ACCOUNTED/BLOCKED/UNRESOLVED/NEED_MORE_EVIDENCE/REQUIRES_DECISION, status distinto de ACCOUNTED con effect_on_scope distinto de BLOCKS, o status ACCOUNTED con effect_on_scope distinto de PRESERVE): se bloquean TODOS los scopes. Un frente ACCOUNTED con effect_on_scope PRESERVE no bloquea nada.",
    "critical_impacts": "Lista sin repetidos (en orden de aparición) de impact_id de los impactos con critical=true en evidence.direct_impacts, evidence.indirect_impacts y evidence.second_order_impacts.",
    "depth_level": "Se calcula solo con el objeto signals del caso, con esta política de precedencia sin pesos: L3 si se cumple cualquiera de L3_if_any; si no, L2 si se cumple cualquiera de L2_if_no_L3_and_any; L1 solo si se cumplen todas las condiciones de L1_requires_all. La profundidad no es permiso de ejecución.",
    "depth_policy": {
      "L1_requires_all": [
        "materiality_level=LOW",
        "scope_bounded=TRUE",
        "authority_state=SUFFICIENT",
        "reversibility_state=DEMONSTRATED",
        "currentness_decision=CURRENT",
        "material_contradiction=false",
        "known_cross_scope_impact=false",
        "unresolved_material_signal_count=0",
        "required_specialist_count=0"
      ],
      "L2_if_no_L3_and_any": [
        "materiality_level in [MEDIUM,UNKNOWN]",
        "scope_bounded=UNKNOWN",
        "authority_state=UNKNOWN",
        "reversibility_state in [NOT_DEMONSTRATED,UNKNOWN]",
        "currentness_decision in [CURRENT_REBOUND,UNKNOWN_FAIL_CLOSED,UNRESOLVED]",
        "known_cross_scope_impact=UNKNOWN",
        "unresolved_material_signal_count>0",
        "required_specialist_count>0"
      ],
      "L3_if_any": [
        "materiality_level=HIGH",
        "scope_bounded=FALSE",
        "authority_state=INSUFFICIENT",
        "currentness_decision=STALE_AFFECTED",
        "material_contradiction=true",
        "known_cross_scope_impact=true"
      ],
      "precedence": [
        "L3_EXPLICIT_HIGH_RISK",
        "L2_MEDIUM_OR_UNPROVEN",
        "L1_FULLY_BOUNDED_LOW_RISK"
      ],
      "signals": {
        "authority_state": [
          "SUFFICIENT",
          "INSUFFICIENT",
          "UNKNOWN"
        ],
        "currentness_decision": [
          "CURRENT",
          "CURRENT_REBOUND",
          "STALE_AFFECTED",
          "UNKNOWN_FAIL_CLOSED",
          "UNRESOLVED"
        ],
        "known_cross_scope_impact": "BOOLEAN_OR_UNKNOWN",
        "material_contradiction": "BOOLEAN",
        "materiality_level": [
          "LOW",
          "MEDIUM",
          "HIGH",
          "UNKNOWN"
        ],
        "required_specialist_count": "NON_NEGATIVE_INTEGER",
        "reversibility_state": [
          "DEMONSTRATED",
          "NOT_DEMONSTRATED",
          "UNKNOWN"
        ],
        "scope_bounded": [
          "TRUE",
          "FALSE",
          "UNKNOWN"
        ],
        "unresolved_material_signal_count": "NON_NEGATIVE_INTEGER"
      }
    },
    "handoff_parity": "PASS solo si los cuatro digests (producer_schema_digest_sha256, receiver_schema_digest_sha256, context_sha256, receipt_context_sha256) son cadenas de 64 caracteres hexadecimales en minúscula, producer_schema_digest_sha256 es igual a receiver_schema_digest_sha256, context_sha256 es igual a receipt_context_sha256 y lossy_projection es false. En cualquier otro caso BLOCK.",
    "lossy_projection_detected": "true si handoff.lossy_projection es true; si no, false.",
    "material_fronts": "Lista sin repetidos de front_id de evidence.material_fronts con material=true.",
    "missing_required_specialists": "Lista de specialist_type de los requirements con required=true y matched_ref=null.",
    "ready_scope_ids": "Todos los scope_id del caso que no están bloqueados.",
    "specialist_refs": "Lista de matched_ref no nulos de los specialist_requirements.",
    "verdict": "READY si ningún scope está bloqueado; BLOCKED si todos los scopes están bloqueados; PARTIAL_READY en otro caso."
  },
  "schema_version": "A14_INPUT_HOLDOUT_V1"
}
$in$,E'\n'),'UTF8')),'hex') <> 'bf435cdf0e3635c4116fa300ac2fd51fe0e359875da2e3241410e410a96686b2' THEN RAISE EXCEPTION 'A14Q_C2_INPUT_FIXTURE_DRIFT'; END IF;
 v_or:=$or${
  "schema_version": "ANALYSIS_A14_FRESH_ORACLE_V1",
  "state": "FROZEN_AFTER_CANDIDATE_EXECUTION_WITHOUT_READING_RESULT",
  "case_set_id": "A14-FRESH-20261007-V1",
  "case_set_commit": "a77a7b21f390538a64b096a2deaef9d8915095e7",
  "candidate_result_sha256_committed_before_oracle": "888817096732324fd546ac3f1d80be1c9056a8d647479288866c89ce209cefe7",
  "oracle_basis": "FROZEN_ANALYSIS_CONTRACTS_PLUS_CASE_EVIDENCE",
  "candidate_result_not_consulted_for_labeling": true,
  "oracle": [
    {
      "case_id": "A14-FRESH-001",
      "critical_impacts_expected": [
        "OFFER_PERCENT_RULE"
      ],
      "material_fronts_expected": [
        "UI_RULE"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L1",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-002",
      "critical_impacts_expected": [
        "SCHEDULE_INTERACTION"
      ],
      "material_fronts_expected": [
        "UX_BEHAVIOR"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current"
      ],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-003",
      "critical_impacts_expected": [
        "UPLOAD_TABLE_SEMANTICS",
        "ERROR_DOWNLOAD_FLOW"
      ],
      "material_fronts_expected": [
        "TABLE",
        "ERROR_FLOW"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current",
        "capability://DATA_CONTRACT_SPECIALIST@current"
      ],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-004",
      "critical_impacts_expected": [
        "APPROVAL_ACTIONS"
      ],
      "material_fronts_expected": [
        "SPECIALIST_GAP"
      ],
      "blocked_scope_ids_expected": [
        "S2"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": true,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-005",
      "critical_impacts_expected": [
        "API_HEADER_CONTRACT"
      ],
      "material_fronts_expected": [
        "API_CONTRACT"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-006",
      "critical_impacts_expected": [
        "SCHEMA_COMPATIBILITY",
        "MIGRATION_PARITY"
      ],
      "material_fronts_expected": [
        "SCHEMA"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-007",
      "critical_impacts_expected": [
        "RULE_READ"
      ],
      "material_fronts_expected": [
        "CURRENTNESS"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-008",
      "critical_impacts_expected": [
        "STATE_CONTRADICTION"
      ],
      "material_fronts_expected": [
        "SEMANTIC_CONTRADICTION"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-009",
      "critical_impacts_expected": [
        "CAPABILITY_CHANGE",
        "DOWNSTREAM_CONSUMER_BREAK"
      ],
      "material_fronts_expected": [
        "SECOND_ORDER"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-010",
      "critical_impacts_expected": [
        "HANDOFF_SCHEMA"
      ],
      "material_fronts_expected": [
        "HANDOFF"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "BLOCK",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-011",
      "critical_impacts_expected": [
        "SUMMARY_PROJECTION"
      ],
      "material_fronts_expected": [
        "PROJECTION"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "BLOCK",
      "depth_expected": "L2",
      "lossy_projection_expected_block": true,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-012",
      "critical_impacts_expected": [
        "METADATA_TRACE"
      ],
      "material_fronts_expected": [
        "TRACEABILITY"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L1",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    }
  ],
  "guards": {
    "A13_tuning_forbidden": true,
    "oracle_labels_frozen": true,
    "runtime_activation": false,
    "production_activation": false
  }
}$or$::jsonb;
 IF encode(sha256(convert_to(rtrim($or${
  "schema_version": "ANALYSIS_A14_FRESH_ORACLE_V1",
  "state": "FROZEN_AFTER_CANDIDATE_EXECUTION_WITHOUT_READING_RESULT",
  "case_set_id": "A14-FRESH-20261007-V1",
  "case_set_commit": "a77a7b21f390538a64b096a2deaef9d8915095e7",
  "candidate_result_sha256_committed_before_oracle": "888817096732324fd546ac3f1d80be1c9056a8d647479288866c89ce209cefe7",
  "oracle_basis": "FROZEN_ANALYSIS_CONTRACTS_PLUS_CASE_EVIDENCE",
  "candidate_result_not_consulted_for_labeling": true,
  "oracle": [
    {
      "case_id": "A14-FRESH-001",
      "critical_impacts_expected": [
        "OFFER_PERCENT_RULE"
      ],
      "material_fronts_expected": [
        "UI_RULE"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L1",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-002",
      "critical_impacts_expected": [
        "SCHEDULE_INTERACTION"
      ],
      "material_fronts_expected": [
        "UX_BEHAVIOR"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current"
      ],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-003",
      "critical_impacts_expected": [
        "UPLOAD_TABLE_SEMANTICS",
        "ERROR_DOWNLOAD_FLOW"
      ],
      "material_fronts_expected": [
        "TABLE",
        "ERROR_FLOW"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current",
        "capability://DATA_CONTRACT_SPECIALIST@current"
      ],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-004",
      "critical_impacts_expected": [
        "APPROVAL_ACTIONS"
      ],
      "material_fronts_expected": [
        "SPECIALIST_GAP"
      ],
      "blocked_scope_ids_expected": [
        "S2"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": true,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-005",
      "critical_impacts_expected": [
        "API_HEADER_CONTRACT"
      ],
      "material_fronts_expected": [
        "API_CONTRACT"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-006",
      "critical_impacts_expected": [
        "SCHEMA_COMPATIBILITY",
        "MIGRATION_PARITY"
      ],
      "material_fronts_expected": [
        "SCHEMA"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-007",
      "critical_impacts_expected": [
        "RULE_READ"
      ],
      "material_fronts_expected": [
        "CURRENTNESS"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-008",
      "critical_impacts_expected": [
        "STATE_CONTRADICTION"
      ],
      "material_fronts_expected": [
        "SEMANTIC_CONTRADICTION"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-009",
      "critical_impacts_expected": [
        "CAPABILITY_CHANGE",
        "DOWNSTREAM_CONSUMER_BREAK"
      ],
      "material_fronts_expected": [
        "SECOND_ORDER"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-010",
      "critical_impacts_expected": [
        "HANDOFF_SCHEMA"
      ],
      "material_fronts_expected": [
        "HANDOFF"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "BLOCK",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-011",
      "critical_impacts_expected": [
        "SUMMARY_PROJECTION"
      ],
      "material_fronts_expected": [
        "PROJECTION"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "BLOCK",
      "depth_expected": "L2",
      "lossy_projection_expected_block": true,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-012",
      "critical_impacts_expected": [
        "METADATA_TRACE"
      ],
      "material_fronts_expected": [
        "TRACEABILITY"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L1",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    }
  ],
  "guards": {
    "A13_tuning_forbidden": true,
    "oracle_labels_frozen": true,
    "runtime_activation": false,
    "production_activation": false
  }
}$or$,E'\n'),'UTF8')),'hex') <> '7db7ae22ed5ecd65fd9233c1a1ef8d9b66fc24979166554eb6131f7f538a29e1' THEN RAISE EXCEPTION 'A14Q_C2_ORACLE_FIXTURE_DRIFT'; END IF;
 IF (v_raw->>'schema_version'='A14_HOLDOUT_ANSWERS_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_raw) k)=ARRAY['answers','answers_statement','request_ref','schema_version']::text[] AND length(trim(v_raw->>'answers_statement'))>=40 AND jsonb_array_length(v_in->'cases')=12 AND jsonb_array_length(v_or->'oracle')=12 AND jsonb_array_length(v_raw->'answers')=12 AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(o->>'case_id' ORDER BY o->>'case_id') FROM jsonb_array_elements(v_or->'oracle') o) AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(a->>'case_id' ORDER BY a->>'case_id') FROM jsonb_array_elements(v_raw->'answers') a) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'answers') a JOIN jsonb_array_elements(v_in->'cases') c ON c->>'case_id'=a->>'case_id' JOIN jsonb_array_elements(v_or->'oracle') o ON o->>'case_id'=a->>'case_id' WHERE NOT ((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(a) k)=ARRAY['blocked_scope_ids','case_id','critical_impacts','depth_level','handoff_parity','lossy_projection_detected','material_fronts','missing_required_specialists','rationale','ready_scope_ids','specialist_refs','verdict']::text[]) OR length(trim(a->>'rationale'))<20 OR jsonb_typeof(a->'rationale')<>'string' OR jsonb_typeof(a->'lossy_projection_detected')<>'boolean' OR a->>'depth_level' IS DISTINCT FROM o->>'depth_expected' OR jsonb_typeof(a->'critical_impacts')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'critical_impacts') x)<>jsonb_array_length(a->'critical_impacts') OR jsonb_typeof(a->'material_fronts')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'material_fronts') x)<>jsonb_array_length(a->'material_fronts') OR jsonb_typeof(a->'blocked_scope_ids')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'blocked_scope_ids') x)<>jsonb_array_length(a->'blocked_scope_ids') OR jsonb_typeof(a->'ready_scope_ids')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'ready_scope_ids') x)<>jsonb_array_length(a->'ready_scope_ids') OR jsonb_typeof(a->'specialist_refs')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'specialist_refs') x)<>jsonb_array_length(a->'specialist_refs') OR jsonb_typeof(a->'missing_required_specialists')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'missing_required_specialists') x)<>jsonb_array_length(a->'missing_required_specialists') OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'critical_impacts')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(o->'critical_impacts_expected')) q(x)) OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'material_fronts')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(o->'material_fronts_expected')) q(x)) OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'blocked_scope_ids')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(o->'blocked_scope_ids_expected')) q(x)) OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'ready_scope_ids')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT s->>'scope_id' FROM jsonb_array_elements(c#>'{evidence,scopes}') s EXCEPT SELECT jsonb_array_elements_text(o->'blocked_scope_ids_expected')) q(x)) OR a->>'handoff_parity' IS DISTINCT FROM o->>'handoff_parity_expected' OR (a->>'lossy_projection_detected')::boolean IS DISTINCT FROM (o->>'lossy_projection_expected_block')::boolean OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'specialist_refs')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(o->'specialist_refs_expected')) q(x)) OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'missing_required_specialists')) q(x)) <> (SELECT coalesce(jsonb_agg(r->>'specialist_type' ORDER BY r->>'specialist_type'),'[]'::jsonb) FROM jsonb_array_elements(c->'specialist_requirements') r WHERE (r->>'required')='true' AND (r->>'matched_ref') IS NULL) OR (jsonb_array_length((SELECT coalesce(jsonb_agg(r->>'specialist_type' ORDER BY r->>'specialist_type'),'[]'::jsonb) FROM jsonb_array_elements(c->'specialist_requirements') r WHERE (r->>'required')='true' AND (r->>'matched_ref') IS NULL))>0) IS DISTINCT FROM (o->>'required_specialist_missing_expected')::boolean OR a->>'verdict' IS DISTINCT FROM (CASE WHEN jsonb_array_length(o->'blocked_scope_ids_expected')=0 THEN 'READY' WHEN jsonb_array_length(o->'blocked_scope_ids_expected')=jsonb_array_length(c#>'{evidence,scopes}') THEN 'BLOCKED' ELSE 'PARTIAL_READY' END))) IS NOT TRUE THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1124 AND checkpoint_code='A14Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A14Q' AND work_item_id=1124 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A14Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A14Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A14Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A14Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1124;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A14Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A14Q' AND work_item_id=1124;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A14Q' AND work_item_id=1124;
 IF v_m#>'{gpt_native_captures_v1,A14Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1124;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a14q_c2_cap$;
-- A14Q_C2 closure under the owner-approved GPT Native tier (decision: docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md).
-- A14Q_C2 closure under the owner-approved GPT Native tier (docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md) and the criterion amendment (docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).
DO $a14q_c2_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A14Q';
 v_cp constant text := 'A14Q_C2';
 v_wi constant bigint := 1124;
 v_actor constant text := 'ANALYSIS_QUAL_C2_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_a14q_c2_gpt_native_packet_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '2918579179b97bf3d479a3b3a05bda51a08a05fed456e41270c1a95e710acf53';
 v_amend_doc constant text := 'docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md';
 v_amend_sha constant text := '17d77d4af397a768d65617368cd043e2abc3795fc9f8f523ddfcb4044b8c2109';
 v_packet_sha constant text := '1dd500b54e57e77c172ef6b58ac27da6b6168ddea3465708509d6ccbad931618';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1124 and checkpoint_code=''A14Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_open int; v_pass jsonb; v_amend jsonb;
 v_in jsonb; v_or jsonb;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A14Q_C2_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A14Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A14Q/A14Q_C2'
 THEN RAISE EXCEPTION 'A14Q_C2_PRESTATE_DRIFT'; END IF;

 -- Recompute the evidence from the stored capture.
 v_cap:=v_m#>'{gpt_native_captures_v1,A14Q_C2}'; v_pk:=v_m#>'{gpt_native_packets_v1,A14Q_C2}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha
    OR v_cap->>'request_sha256' IS DISTINCT FROM v_pk->>'request_sha256'
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A14Q_C2_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'A14Q_C2_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A14Q_C2_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_open:=jsonb_array_length(v_raw->'answers');
 v_in:=$in${
  "case_set_id": "A14-FRESH-20261007-V1",
  "cases": [
    {
      "case_id": "A14-FRESH-001",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/001/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "OFFER_PERCENT_RULE",
            "source_ref": "fixture://a14/001/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "UI_RULE",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/001/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/001/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receipt_context_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receiver_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-002",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/002/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SCHEDULE_INTERACTION",
            "source_ref": "fixture://a14/002/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "UX_BEHAVIOR",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/002/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/002/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receipt_context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receiver_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 1,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S1"
          ],
          "matched_ref": "capability://PRODUCT_SCREEN_SPECIALIST@current",
          "required": true,
          "specialist_type": "PRODUCT_SCREEN"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-003",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/003/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "UPLOAD_TABLE_SEMANTICS",
            "source_ref": "fixture://a14/003/i1"
          }
        ],
        "indirect_impacts": [
          {
            "critical": true,
            "impact_id": "ERROR_DOWNLOAD_FLOW",
            "source_ref": "fixture://a14/003/i2"
          }
        ],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "TABLE",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/003/f1"
            ],
            "status": "ACCOUNTED"
          },
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "ERROR_FLOW",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/003/f2"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/003/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "DATA_SCOPE",
            "source_ref": "fixture://a14/003/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receipt_context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receiver_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 2,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S1"
          ],
          "matched_ref": "capability://PRODUCT_SCREEN_SPECIALIST@current",
          "required": true,
          "specialist_type": "PRODUCT_SCREEN"
        },
        {
          "affected_scope_ids": [
            "S2"
          ],
          "matched_ref": "capability://DATA_CONTRACT_SPECIALIST@current",
          "required": true,
          "specialist_type": "DATA_CONTRACT"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-004",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/004/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "APPROVAL_ACTIONS",
            "source_ref": "fixture://a14/004/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SPECIALIST_GAP",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/004/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/004/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "POLICY_SCOPE",
            "source_ref": "fixture://a14/004/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receipt_context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receiver_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "UNKNOWN",
        "required_specialist_count": 1,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S2"
          ],
          "matched_ref": null,
          "required": true,
          "specialist_type": "POLICY_SPECIALIST"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-005",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/005/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "API_HEADER_CONTRACT",
            "source_ref": "fixture://a14/005/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "API_CONTRACT",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/005/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "API_SCOPE",
            "source_ref": "fixture://a14/005/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receipt_context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receiver_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-006",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/006/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SCHEMA_COMPATIBILITY",
            "source_ref": "fixture://a14/006/i1"
          }
        ],
        "indirect_impacts": [
          {
            "critical": true,
            "impact_id": "MIGRATION_PARITY",
            "source_ref": "fixture://a14/006/i2"
          }
        ],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SCHEMA",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/006/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "DATA_SCOPE",
            "source_ref": "fixture://a14/006/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receipt_context_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "receiver_schema_digest_sha256": "6666666666666666666666666666666666666666666666666666666666666666"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "HIGH",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-007",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [
            "S1"
          ],
          "decision": "STALE_AFFECTED",
          "source_ref": "fixture://a14/007/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "RULE_READ",
            "source_ref": "fixture://a14/007/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "CURRENTNESS",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/007/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "RULE_SCOPE",
            "source_ref": "fixture://a14/007/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "RULE_SCOPE",
            "source_ref": "fixture://a14/007/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "receipt_context_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "receiver_schema_digest_sha256": "7777777777777777777777777777777777777777777777777777777777777777"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "STALE_AFFECTED",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-008",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/008/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "STATE_CONTRADICTION",
            "source_ref": "fixture://a14/008/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "SEMANTIC_CONTRADICTION",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/008/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "WORKFLOW_SCOPE",
            "source_ref": "fixture://a14/008/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "receipt_context_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receiver_schema_digest_sha256": "8888888888888888888888888888888888888888888888888888888888888888"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": true,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-009",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/009/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "CAPABILITY_CHANGE",
            "source_ref": "fixture://a14/009/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SECOND_ORDER",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/009/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "CAPABILITY_SCOPE",
            "source_ref": "fixture://a14/009/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "CONSUMER_SCOPE",
            "source_ref": "fixture://a14/009/s2"
          }
        ],
        "second_order_impacts": [
          {
            "critical": true,
            "impact_id": "DOWNSTREAM_CONSUMER_BREAK",
            "source_ref": "fixture://a14/009/i2"
          }
        ]
      },
      "handoff": {
        "context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receipt_context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receiver_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": true,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-010",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/010/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "HANDOFF_SCHEMA",
            "source_ref": "fixture://a14/010/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "HANDOFF",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/010/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "HANDOFF_SCOPE",
            "source_ref": "fixture://a14/010/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receipt_context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receiver_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-011",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/011/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SUMMARY_PROJECTION",
            "source_ref": "fixture://a14/011/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "PROJECTION",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/011/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/011/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "lossy_projection": true,
        "producer_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receipt_context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receiver_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "UNKNOWN",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-012",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/012/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "METADATA_TRACE",
            "source_ref": "fixture://a14/012/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "TRACEABILITY",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/012/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "GOVERNANCE_SCOPE",
            "source_ref": "fixture://a14/012/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receipt_context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receiver_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    }
  ],
  "rules": {
    "blocked_scope_ids": "Un scope queda bloqueado si: (a) un frente material tiene status BLOCKED, UNRESOLVED, NEED_MORE_EVIDENCE o REQUIRES_DECISION: se bloquean los scope_ids de ese frente; (b) evidence.currentness.decision es STALE_AFFECTED o UNKNOWN_FAIL_CLOSED: se bloquean evidence.currentness.affected_scope_ids; (c) un specialist_requirement con required=true y matched_ref=null: se bloquean sus affected_scope_ids; (d) el handoff no pasa (ver handoff_parity): se bloquean TODOS los scopes; (e) los frentes materiales son inconsistentes (front_id repetido o vacío, scope_ids vacío o fuera de los scopes del caso, status fuera de ACCOUNTED/BLOCKED/UNRESOLVED/NEED_MORE_EVIDENCE/REQUIRES_DECISION, status distinto de ACCOUNTED con effect_on_scope distinto de BLOCKS, o status ACCOUNTED con effect_on_scope distinto de PRESERVE): se bloquean TODOS los scopes. Un frente ACCOUNTED con effect_on_scope PRESERVE no bloquea nada.",
    "critical_impacts": "Lista sin repetidos (en orden de aparición) de impact_id de los impactos con critical=true en evidence.direct_impacts, evidence.indirect_impacts y evidence.second_order_impacts.",
    "depth_level": "Se calcula solo con el objeto signals del caso, con esta política de precedencia sin pesos: L3 si se cumple cualquiera de L3_if_any; si no, L2 si se cumple cualquiera de L2_if_no_L3_and_any; L1 solo si se cumplen todas las condiciones de L1_requires_all. La profundidad no es permiso de ejecución.",
    "depth_policy": {
      "L1_requires_all": [
        "materiality_level=LOW",
        "scope_bounded=TRUE",
        "authority_state=SUFFICIENT",
        "reversibility_state=DEMONSTRATED",
        "currentness_decision=CURRENT",
        "material_contradiction=false",
        "known_cross_scope_impact=false",
        "unresolved_material_signal_count=0",
        "required_specialist_count=0"
      ],
      "L2_if_no_L3_and_any": [
        "materiality_level in [MEDIUM,UNKNOWN]",
        "scope_bounded=UNKNOWN",
        "authority_state=UNKNOWN",
        "reversibility_state in [NOT_DEMONSTRATED,UNKNOWN]",
        "currentness_decision in [CURRENT_REBOUND,UNKNOWN_FAIL_CLOSED,UNRESOLVED]",
        "known_cross_scope_impact=UNKNOWN",
        "unresolved_material_signal_count>0",
        "required_specialist_count>0"
      ],
      "L3_if_any": [
        "materiality_level=HIGH",
        "scope_bounded=FALSE",
        "authority_state=INSUFFICIENT",
        "currentness_decision=STALE_AFFECTED",
        "material_contradiction=true",
        "known_cross_scope_impact=true"
      ],
      "precedence": [
        "L3_EXPLICIT_HIGH_RISK",
        "L2_MEDIUM_OR_UNPROVEN",
        "L1_FULLY_BOUNDED_LOW_RISK"
      ],
      "signals": {
        "authority_state": [
          "SUFFICIENT",
          "INSUFFICIENT",
          "UNKNOWN"
        ],
        "currentness_decision": [
          "CURRENT",
          "CURRENT_REBOUND",
          "STALE_AFFECTED",
          "UNKNOWN_FAIL_CLOSED",
          "UNRESOLVED"
        ],
        "known_cross_scope_impact": "BOOLEAN_OR_UNKNOWN",
        "material_contradiction": "BOOLEAN",
        "materiality_level": [
          "LOW",
          "MEDIUM",
          "HIGH",
          "UNKNOWN"
        ],
        "required_specialist_count": "NON_NEGATIVE_INTEGER",
        "reversibility_state": [
          "DEMONSTRATED",
          "NOT_DEMONSTRATED",
          "UNKNOWN"
        ],
        "scope_bounded": [
          "TRUE",
          "FALSE",
          "UNKNOWN"
        ],
        "unresolved_material_signal_count": "NON_NEGATIVE_INTEGER"
      }
    },
    "handoff_parity": "PASS solo si los cuatro digests (producer_schema_digest_sha256, receiver_schema_digest_sha256, context_sha256, receipt_context_sha256) son cadenas de 64 caracteres hexadecimales en minúscula, producer_schema_digest_sha256 es igual a receiver_schema_digest_sha256, context_sha256 es igual a receipt_context_sha256 y lossy_projection es false. En cualquier otro caso BLOCK.",
    "lossy_projection_detected": "true si handoff.lossy_projection es true; si no, false.",
    "material_fronts": "Lista sin repetidos de front_id de evidence.material_fronts con material=true.",
    "missing_required_specialists": "Lista de specialist_type de los requirements con required=true y matched_ref=null.",
    "ready_scope_ids": "Todos los scope_id del caso que no están bloqueados.",
    "specialist_refs": "Lista de matched_ref no nulos de los specialist_requirements.",
    "verdict": "READY si ningún scope está bloqueado; BLOCKED si todos los scopes están bloqueados; PARTIAL_READY en otro caso."
  },
  "schema_version": "A14_INPUT_HOLDOUT_V1"
}
$in$::jsonb;
 IF encode(sha256(convert_to(rtrim($in${
  "case_set_id": "A14-FRESH-20261007-V1",
  "cases": [
    {
      "case_id": "A14-FRESH-001",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/001/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "OFFER_PERCENT_RULE",
            "source_ref": "fixture://a14/001/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "UI_RULE",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/001/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/001/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receipt_context_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receiver_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-002",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/002/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SCHEDULE_INTERACTION",
            "source_ref": "fixture://a14/002/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "UX_BEHAVIOR",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/002/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/002/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receipt_context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receiver_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 1,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S1"
          ],
          "matched_ref": "capability://PRODUCT_SCREEN_SPECIALIST@current",
          "required": true,
          "specialist_type": "PRODUCT_SCREEN"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-003",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/003/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "UPLOAD_TABLE_SEMANTICS",
            "source_ref": "fixture://a14/003/i1"
          }
        ],
        "indirect_impacts": [
          {
            "critical": true,
            "impact_id": "ERROR_DOWNLOAD_FLOW",
            "source_ref": "fixture://a14/003/i2"
          }
        ],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "TABLE",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/003/f1"
            ],
            "status": "ACCOUNTED"
          },
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "ERROR_FLOW",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/003/f2"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/003/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "DATA_SCOPE",
            "source_ref": "fixture://a14/003/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receipt_context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receiver_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 2,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S1"
          ],
          "matched_ref": "capability://PRODUCT_SCREEN_SPECIALIST@current",
          "required": true,
          "specialist_type": "PRODUCT_SCREEN"
        },
        {
          "affected_scope_ids": [
            "S2"
          ],
          "matched_ref": "capability://DATA_CONTRACT_SPECIALIST@current",
          "required": true,
          "specialist_type": "DATA_CONTRACT"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-004",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/004/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "APPROVAL_ACTIONS",
            "source_ref": "fixture://a14/004/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SPECIALIST_GAP",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/004/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/004/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "POLICY_SCOPE",
            "source_ref": "fixture://a14/004/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receipt_context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receiver_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "UNKNOWN",
        "required_specialist_count": 1,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": [
        {
          "affected_scope_ids": [
            "S2"
          ],
          "matched_ref": null,
          "required": true,
          "specialist_type": "POLICY_SPECIALIST"
        }
      ]
    },
    {
      "case_id": "A14-FRESH-005",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/005/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "API_HEADER_CONTRACT",
            "source_ref": "fixture://a14/005/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "API_CONTRACT",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/005/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "API_SCOPE",
            "source_ref": "fixture://a14/005/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receipt_context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receiver_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-006",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/006/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SCHEMA_COMPATIBILITY",
            "source_ref": "fixture://a14/006/i1"
          }
        ],
        "indirect_impacts": [
          {
            "critical": true,
            "impact_id": "MIGRATION_PARITY",
            "source_ref": "fixture://a14/006/i2"
          }
        ],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SCHEMA",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/006/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "DATA_SCOPE",
            "source_ref": "fixture://a14/006/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receipt_context_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "receiver_schema_digest_sha256": "6666666666666666666666666666666666666666666666666666666666666666"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "HIGH",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-007",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [
            "S1"
          ],
          "decision": "STALE_AFFECTED",
          "source_ref": "fixture://a14/007/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "RULE_READ",
            "source_ref": "fixture://a14/007/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "CURRENTNESS",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/007/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "RULE_SCOPE",
            "source_ref": "fixture://a14/007/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "RULE_SCOPE",
            "source_ref": "fixture://a14/007/s2"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
        "receipt_context_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "receiver_schema_digest_sha256": "7777777777777777777777777777777777777777777777777777777777777777"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "STALE_AFFECTED",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-008",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/008/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "STATE_CONTRADICTION",
            "source_ref": "fixture://a14/008/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "SEMANTIC_CONTRADICTION",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/008/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "WORKFLOW_SCOPE",
            "source_ref": "fixture://a14/008/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
        "receipt_context_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receiver_schema_digest_sha256": "8888888888888888888888888888888888888888888888888888888888888888"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": true,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-009",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/009/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "CAPABILITY_CHANGE",
            "source_ref": "fixture://a14/009/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "SECOND_ORDER",
            "material": true,
            "scope_ids": [
              "S2"
            ],
            "source_refs": [
              "fixture://a14/009/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "CAPABILITY_SCOPE",
            "source_ref": "fixture://a14/009/s1"
          },
          {
            "scope_id": "S2",
            "scope_kind": "CONSUMER_SCOPE",
            "source_ref": "fixture://a14/009/s2"
          }
        ],
        "second_order_impacts": [
          {
            "critical": true,
            "impact_id": "DOWNSTREAM_CONSUMER_BREAK",
            "source_ref": "fixture://a14/009/i2"
          }
        ]
      },
      "handoff": {
        "context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
        "receipt_context_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
        "receiver_schema_digest_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": true,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-010",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/010/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "HANDOFF_SCHEMA",
            "source_ref": "fixture://a14/010/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "HANDOFF",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/010/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "HANDOFF_SCOPE",
            "source_ref": "fixture://a14/010/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
        "receipt_context_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receiver_schema_digest_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "MEDIUM",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-011",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/011/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "SUMMARY_PROJECTION",
            "source_ref": "fixture://a14/011/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "BLOCKS",
            "front_id": "PROJECTION",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/011/f1"
            ],
            "status": "BLOCKED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "PRODUCT_SURFACE",
            "source_ref": "fixture://a14/011/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "lossy_projection": true,
        "producer_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
        "receipt_context_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receiver_schema_digest_sha256": "4444444444444444444444444444444444444444444444444444444444444444"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "UNKNOWN",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 1
      },
      "specialist_requirements": []
    },
    {
      "case_id": "A14-FRESH-012",
      "evidence": {
        "currentness": {
          "affected_scope_ids": [],
          "decision": "CURRENT",
          "source_ref": "fixture://a14/012/c"
        },
        "direct_impacts": [
          {
            "critical": true,
            "impact_id": "METADATA_TRACE",
            "source_ref": "fixture://a14/012/i1"
          }
        ],
        "indirect_impacts": [],
        "material_fronts": [
          {
            "effect_on_scope": "PRESERVE",
            "front_id": "TRACEABILITY",
            "material": true,
            "scope_ids": [
              "S1"
            ],
            "source_refs": [
              "fixture://a14/012/f1"
            ],
            "status": "ACCOUNTED"
          }
        ],
        "scopes": [
          {
            "scope_id": "S1",
            "scope_kind": "GOVERNANCE_SCOPE",
            "source_ref": "fixture://a14/012/s1"
          }
        ],
        "second_order_impacts": []
      },
      "handoff": {
        "context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "lossy_projection": false,
        "producer_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
        "receipt_context_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
        "receiver_schema_digest_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
      },
      "signals": {
        "authority_state": "SUFFICIENT",
        "currentness_decision": "CURRENT",
        "known_cross_scope_impact": false,
        "material_contradiction": false,
        "materiality_level": "LOW",
        "required_specialist_count": 0,
        "reversibility_state": "DEMONSTRATED",
        "scope_bounded": "TRUE",
        "unresolved_material_signal_count": 0
      },
      "specialist_requirements": []
    }
  ],
  "rules": {
    "blocked_scope_ids": "Un scope queda bloqueado si: (a) un frente material tiene status BLOCKED, UNRESOLVED, NEED_MORE_EVIDENCE o REQUIRES_DECISION: se bloquean los scope_ids de ese frente; (b) evidence.currentness.decision es STALE_AFFECTED o UNKNOWN_FAIL_CLOSED: se bloquean evidence.currentness.affected_scope_ids; (c) un specialist_requirement con required=true y matched_ref=null: se bloquean sus affected_scope_ids; (d) el handoff no pasa (ver handoff_parity): se bloquean TODOS los scopes; (e) los frentes materiales son inconsistentes (front_id repetido o vacío, scope_ids vacío o fuera de los scopes del caso, status fuera de ACCOUNTED/BLOCKED/UNRESOLVED/NEED_MORE_EVIDENCE/REQUIRES_DECISION, status distinto de ACCOUNTED con effect_on_scope distinto de BLOCKS, o status ACCOUNTED con effect_on_scope distinto de PRESERVE): se bloquean TODOS los scopes. Un frente ACCOUNTED con effect_on_scope PRESERVE no bloquea nada.",
    "critical_impacts": "Lista sin repetidos (en orden de aparición) de impact_id de los impactos con critical=true en evidence.direct_impacts, evidence.indirect_impacts y evidence.second_order_impacts.",
    "depth_level": "Se calcula solo con el objeto signals del caso, con esta política de precedencia sin pesos: L3 si se cumple cualquiera de L3_if_any; si no, L2 si se cumple cualquiera de L2_if_no_L3_and_any; L1 solo si se cumplen todas las condiciones de L1_requires_all. La profundidad no es permiso de ejecución.",
    "depth_policy": {
      "L1_requires_all": [
        "materiality_level=LOW",
        "scope_bounded=TRUE",
        "authority_state=SUFFICIENT",
        "reversibility_state=DEMONSTRATED",
        "currentness_decision=CURRENT",
        "material_contradiction=false",
        "known_cross_scope_impact=false",
        "unresolved_material_signal_count=0",
        "required_specialist_count=0"
      ],
      "L2_if_no_L3_and_any": [
        "materiality_level in [MEDIUM,UNKNOWN]",
        "scope_bounded=UNKNOWN",
        "authority_state=UNKNOWN",
        "reversibility_state in [NOT_DEMONSTRATED,UNKNOWN]",
        "currentness_decision in [CURRENT_REBOUND,UNKNOWN_FAIL_CLOSED,UNRESOLVED]",
        "known_cross_scope_impact=UNKNOWN",
        "unresolved_material_signal_count>0",
        "required_specialist_count>0"
      ],
      "L3_if_any": [
        "materiality_level=HIGH",
        "scope_bounded=FALSE",
        "authority_state=INSUFFICIENT",
        "currentness_decision=STALE_AFFECTED",
        "material_contradiction=true",
        "known_cross_scope_impact=true"
      ],
      "precedence": [
        "L3_EXPLICIT_HIGH_RISK",
        "L2_MEDIUM_OR_UNPROVEN",
        "L1_FULLY_BOUNDED_LOW_RISK"
      ],
      "signals": {
        "authority_state": [
          "SUFFICIENT",
          "INSUFFICIENT",
          "UNKNOWN"
        ],
        "currentness_decision": [
          "CURRENT",
          "CURRENT_REBOUND",
          "STALE_AFFECTED",
          "UNKNOWN_FAIL_CLOSED",
          "UNRESOLVED"
        ],
        "known_cross_scope_impact": "BOOLEAN_OR_UNKNOWN",
        "material_contradiction": "BOOLEAN",
        "materiality_level": [
          "LOW",
          "MEDIUM",
          "HIGH",
          "UNKNOWN"
        ],
        "required_specialist_count": "NON_NEGATIVE_INTEGER",
        "reversibility_state": [
          "DEMONSTRATED",
          "NOT_DEMONSTRATED",
          "UNKNOWN"
        ],
        "scope_bounded": [
          "TRUE",
          "FALSE",
          "UNKNOWN"
        ],
        "unresolved_material_signal_count": "NON_NEGATIVE_INTEGER"
      }
    },
    "handoff_parity": "PASS solo si los cuatro digests (producer_schema_digest_sha256, receiver_schema_digest_sha256, context_sha256, receipt_context_sha256) son cadenas de 64 caracteres hexadecimales en minúscula, producer_schema_digest_sha256 es igual a receiver_schema_digest_sha256, context_sha256 es igual a receipt_context_sha256 y lossy_projection es false. En cualquier otro caso BLOCK.",
    "lossy_projection_detected": "true si handoff.lossy_projection es true; si no, false.",
    "material_fronts": "Lista sin repetidos de front_id de evidence.material_fronts con material=true.",
    "missing_required_specialists": "Lista de specialist_type de los requirements con required=true y matched_ref=null.",
    "ready_scope_ids": "Todos los scope_id del caso que no están bloqueados.",
    "specialist_refs": "Lista de matched_ref no nulos de los specialist_requirements.",
    "verdict": "READY si ningún scope está bloqueado; BLOCKED si todos los scopes están bloqueados; PARTIAL_READY en otro caso."
  },
  "schema_version": "A14_INPUT_HOLDOUT_V1"
}
$in$,E'\n'),'UTF8')),'hex') <> 'bf435cdf0e3635c4116fa300ac2fd51fe0e359875da2e3241410e410a96686b2' THEN RAISE EXCEPTION 'A14Q_C2_INPUT_FIXTURE_DRIFT'; END IF;
 v_or:=$or${
  "schema_version": "ANALYSIS_A14_FRESH_ORACLE_V1",
  "state": "FROZEN_AFTER_CANDIDATE_EXECUTION_WITHOUT_READING_RESULT",
  "case_set_id": "A14-FRESH-20261007-V1",
  "case_set_commit": "a77a7b21f390538a64b096a2deaef9d8915095e7",
  "candidate_result_sha256_committed_before_oracle": "888817096732324fd546ac3f1d80be1c9056a8d647479288866c89ce209cefe7",
  "oracle_basis": "FROZEN_ANALYSIS_CONTRACTS_PLUS_CASE_EVIDENCE",
  "candidate_result_not_consulted_for_labeling": true,
  "oracle": [
    {
      "case_id": "A14-FRESH-001",
      "critical_impacts_expected": [
        "OFFER_PERCENT_RULE"
      ],
      "material_fronts_expected": [
        "UI_RULE"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L1",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-002",
      "critical_impacts_expected": [
        "SCHEDULE_INTERACTION"
      ],
      "material_fronts_expected": [
        "UX_BEHAVIOR"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current"
      ],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-003",
      "critical_impacts_expected": [
        "UPLOAD_TABLE_SEMANTICS",
        "ERROR_DOWNLOAD_FLOW"
      ],
      "material_fronts_expected": [
        "TABLE",
        "ERROR_FLOW"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current",
        "capability://DATA_CONTRACT_SPECIALIST@current"
      ],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-004",
      "critical_impacts_expected": [
        "APPROVAL_ACTIONS"
      ],
      "material_fronts_expected": [
        "SPECIALIST_GAP"
      ],
      "blocked_scope_ids_expected": [
        "S2"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": true,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-005",
      "critical_impacts_expected": [
        "API_HEADER_CONTRACT"
      ],
      "material_fronts_expected": [
        "API_CONTRACT"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-006",
      "critical_impacts_expected": [
        "SCHEMA_COMPATIBILITY",
        "MIGRATION_PARITY"
      ],
      "material_fronts_expected": [
        "SCHEMA"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-007",
      "critical_impacts_expected": [
        "RULE_READ"
      ],
      "material_fronts_expected": [
        "CURRENTNESS"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-008",
      "critical_impacts_expected": [
        "STATE_CONTRADICTION"
      ],
      "material_fronts_expected": [
        "SEMANTIC_CONTRADICTION"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-009",
      "critical_impacts_expected": [
        "CAPABILITY_CHANGE",
        "DOWNSTREAM_CONSUMER_BREAK"
      ],
      "material_fronts_expected": [
        "SECOND_ORDER"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-010",
      "critical_impacts_expected": [
        "HANDOFF_SCHEMA"
      ],
      "material_fronts_expected": [
        "HANDOFF"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "BLOCK",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-011",
      "critical_impacts_expected": [
        "SUMMARY_PROJECTION"
      ],
      "material_fronts_expected": [
        "PROJECTION"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "BLOCK",
      "depth_expected": "L2",
      "lossy_projection_expected_block": true,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-012",
      "critical_impacts_expected": [
        "METADATA_TRACE"
      ],
      "material_fronts_expected": [
        "TRACEABILITY"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L1",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    }
  ],
  "guards": {
    "A13_tuning_forbidden": true,
    "oracle_labels_frozen": true,
    "runtime_activation": false,
    "production_activation": false
  }
}$or$::jsonb;
 IF encode(sha256(convert_to(rtrim($or${
  "schema_version": "ANALYSIS_A14_FRESH_ORACLE_V1",
  "state": "FROZEN_AFTER_CANDIDATE_EXECUTION_WITHOUT_READING_RESULT",
  "case_set_id": "A14-FRESH-20261007-V1",
  "case_set_commit": "a77a7b21f390538a64b096a2deaef9d8915095e7",
  "candidate_result_sha256_committed_before_oracle": "888817096732324fd546ac3f1d80be1c9056a8d647479288866c89ce209cefe7",
  "oracle_basis": "FROZEN_ANALYSIS_CONTRACTS_PLUS_CASE_EVIDENCE",
  "candidate_result_not_consulted_for_labeling": true,
  "oracle": [
    {
      "case_id": "A14-FRESH-001",
      "critical_impacts_expected": [
        "OFFER_PERCENT_RULE"
      ],
      "material_fronts_expected": [
        "UI_RULE"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L1",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-002",
      "critical_impacts_expected": [
        "SCHEDULE_INTERACTION"
      ],
      "material_fronts_expected": [
        "UX_BEHAVIOR"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current"
      ],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-003",
      "critical_impacts_expected": [
        "UPLOAD_TABLE_SEMANTICS",
        "ERROR_DOWNLOAD_FLOW"
      ],
      "material_fronts_expected": [
        "TABLE",
        "ERROR_FLOW"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [
        "capability://PRODUCT_SCREEN_SPECIALIST@current",
        "capability://DATA_CONTRACT_SPECIALIST@current"
      ],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-004",
      "critical_impacts_expected": [
        "APPROVAL_ACTIONS"
      ],
      "material_fronts_expected": [
        "SPECIALIST_GAP"
      ],
      "blocked_scope_ids_expected": [
        "S2"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": true,
      "no_specialist_expected": false
    },
    {
      "case_id": "A14-FRESH-005",
      "critical_impacts_expected": [
        "API_HEADER_CONTRACT"
      ],
      "material_fronts_expected": [
        "API_CONTRACT"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-006",
      "critical_impacts_expected": [
        "SCHEMA_COMPATIBILITY",
        "MIGRATION_PARITY"
      ],
      "material_fronts_expected": [
        "SCHEMA"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-007",
      "critical_impacts_expected": [
        "RULE_READ"
      ],
      "material_fronts_expected": [
        "CURRENTNESS"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-008",
      "critical_impacts_expected": [
        "STATE_CONTRADICTION"
      ],
      "material_fronts_expected": [
        "SEMANTIC_CONTRADICTION"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-009",
      "critical_impacts_expected": [
        "CAPABILITY_CHANGE",
        "DOWNSTREAM_CONSUMER_BREAK"
      ],
      "material_fronts_expected": [
        "SECOND_ORDER"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L3",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-010",
      "critical_impacts_expected": [
        "HANDOFF_SCHEMA"
      ],
      "material_fronts_expected": [
        "HANDOFF"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "BLOCK",
      "depth_expected": "L2",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-011",
      "critical_impacts_expected": [
        "SUMMARY_PROJECTION"
      ],
      "material_fronts_expected": [
        "PROJECTION"
      ],
      "blocked_scope_ids_expected": [
        "S1"
      ],
      "handoff_parity_expected": "BLOCK",
      "depth_expected": "L2",
      "lossy_projection_expected_block": true,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    },
    {
      "case_id": "A14-FRESH-012",
      "critical_impacts_expected": [
        "METADATA_TRACE"
      ],
      "material_fronts_expected": [
        "TRACEABILITY"
      ],
      "blocked_scope_ids_expected": [],
      "handoff_parity_expected": "PASS",
      "depth_expected": "L1",
      "lossy_projection_expected_block": false,
      "specialist_refs_expected": [],
      "required_specialist_missing_expected": false,
      "no_specialist_expected": true
    }
  ],
  "guards": {
    "A13_tuning_forbidden": true,
    "oracle_labels_frozen": true,
    "runtime_activation": false,
    "production_activation": false
  }
}$or$,E'\n'),'UTF8')),'hex') <> '7db7ae22ed5ecd65fd9233c1a1ef8d9b66fc24979166554eb6131f7f538a29e1' THEN RAISE EXCEPTION 'A14Q_C2_ORACLE_FIXTURE_DRIFT'; END IF;
 IF (v_raw->>'schema_version'='A14_HOLDOUT_ANSWERS_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_raw) k)=ARRAY['answers','answers_statement','request_ref','schema_version']::text[] AND length(trim(v_raw->>'answers_statement'))>=40 AND jsonb_array_length(v_in->'cases')=12 AND jsonb_array_length(v_or->'oracle')=12 AND jsonb_array_length(v_raw->'answers')=12 AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(o->>'case_id' ORDER BY o->>'case_id') FROM jsonb_array_elements(v_or->'oracle') o) AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(a->>'case_id' ORDER BY a->>'case_id') FROM jsonb_array_elements(v_raw->'answers') a) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'answers') a JOIN jsonb_array_elements(v_in->'cases') c ON c->>'case_id'=a->>'case_id' JOIN jsonb_array_elements(v_or->'oracle') o ON o->>'case_id'=a->>'case_id' WHERE NOT ((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(a) k)=ARRAY['blocked_scope_ids','case_id','critical_impacts','depth_level','handoff_parity','lossy_projection_detected','material_fronts','missing_required_specialists','rationale','ready_scope_ids','specialist_refs','verdict']::text[]) OR length(trim(a->>'rationale'))<20 OR jsonb_typeof(a->'rationale')<>'string' OR jsonb_typeof(a->'lossy_projection_detected')<>'boolean' OR a->>'depth_level' IS DISTINCT FROM o->>'depth_expected' OR jsonb_typeof(a->'critical_impacts')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'critical_impacts') x)<>jsonb_array_length(a->'critical_impacts') OR jsonb_typeof(a->'material_fronts')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'material_fronts') x)<>jsonb_array_length(a->'material_fronts') OR jsonb_typeof(a->'blocked_scope_ids')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'blocked_scope_ids') x)<>jsonb_array_length(a->'blocked_scope_ids') OR jsonb_typeof(a->'ready_scope_ids')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'ready_scope_ids') x)<>jsonb_array_length(a->'ready_scope_ids') OR jsonb_typeof(a->'specialist_refs')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'specialist_refs') x)<>jsonb_array_length(a->'specialist_refs') OR jsonb_typeof(a->'missing_required_specialists')<>'array' OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(a->'missing_required_specialists') x)<>jsonb_array_length(a->'missing_required_specialists') OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'critical_impacts')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(o->'critical_impacts_expected')) q(x)) OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'material_fronts')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(o->'material_fronts_expected')) q(x)) OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'blocked_scope_ids')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(o->'blocked_scope_ids_expected')) q(x)) OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'ready_scope_ids')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT s->>'scope_id' FROM jsonb_array_elements(c#>'{evidence,scopes}') s EXCEPT SELECT jsonb_array_elements_text(o->'blocked_scope_ids_expected')) q(x)) OR a->>'handoff_parity' IS DISTINCT FROM o->>'handoff_parity_expected' OR (a->>'lossy_projection_detected')::boolean IS DISTINCT FROM (o->>'lossy_projection_expected_block')::boolean OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'specialist_refs')) q(x)) <> (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(o->'specialist_refs_expected')) q(x)) OR (SELECT coalesce(jsonb_agg(x ORDER BY x),'[]'::jsonb) FROM (SELECT jsonb_array_elements_text(a->'missing_required_specialists')) q(x)) <> (SELECT coalesce(jsonb_agg(r->>'specialist_type' ORDER BY r->>'specialist_type'),'[]'::jsonb) FROM jsonb_array_elements(c->'specialist_requirements') r WHERE (r->>'required')='true' AND (r->>'matched_ref') IS NULL) OR (jsonb_array_length((SELECT coalesce(jsonb_agg(r->>'specialist_type' ORDER BY r->>'specialist_type'),'[]'::jsonb) FROM jsonb_array_elements(c->'specialist_requirements') r WHERE (r->>'required')='true' AND (r->>'matched_ref') IS NULL))>0) IS DISTINCT FROM (o->>'required_specialist_missing_expected')::boolean OR a->>'verdict' IS DISTINCT FROM (CASE WHEN jsonb_array_length(o->'blocked_scope_ids_expected')=0 THEN 'READY' WHEN jsonb_array_length(o->'blocked_scope_ids_expected')=jsonb_array_length(c#>'{evidence,scopes}') THEN 'BLOCKED' ELSE 'PARTIAL_READY' END))) IS NOT TRUE
 THEN RAISE EXCEPTION 'A14Q_C2_CONTENT_CHECK_FAILED'; END IF;
 IF length(coalesce(v_cap->>'chat_transcript_ref',''))<10 OR coalesce(v_cap->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'A14Q_C2_CHAT_BINDING_MISSING'; END IF;

 v_amend:=jsonb_build_object('criterion_amended',true,'original','Respuestas reales en holdout con identidad del proveedor y costos','amended','Respuestas de holdout por GPT; sin proveedor ni costos','amendment_ref',v_amend_doc||'@'||v_amend_sha,'plan_exit_criterion_modified',false);
 v_pass:=jsonb_build_object('capture_verified',true,'criterion_amendment',v_amend,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,
   'content_checks_passed',true,'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native capture of the A14 holdout answers under the owner-approved equivalent tier and the approved criterion amendment, and bind its result',
  'expected_evidence_class',v_tier,
  'tier_acceptance',jsonb_build_object('tier',v_tier,'decision_ref',v_decision_doc||'@'||v_decision_sha,
    'replaces_expected_evidence_class','REAL_EXECUTION_RECEIPT','scope','C2_ONLY','criterion_amendment',v_amend,
    'limits',jsonb_build_object('provider_attested',false,'real_execution_receipt',false,'independent_review',false)),
  'target',jsonb_build_object('declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_artifacts',jsonb_build_array(v_art),'evidence_artifacts','[]'::jsonb,
    'mutation_artifacts',jsonb_build_array(v_art)),
  'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET','pass_when',v_pass),
  'verification_queries',jsonb_build_array(v_vq),
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A14Q_C2_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A14Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A14Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A14Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A14Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/A14Q#unit_metadata.gpt_native_captures_v1.A14Q_C2'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';request_sha256:'||(v_cap->>'request_sha256')
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha||';amendment:'||v_amend_doc||'@'||v_amend_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A14Q_C2_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A14Q_C2_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','request_sha256',v_cap->>'request_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'request_ref',v_raw->>'request_ref','cases_answered',v_open,'answers_matching_blind_oracle',v_open,'oracle_sha256','7db7ae22ed5ecd65fd9233c1a1ef8d9b66fc24979166554eb6131f7f538a29e1','gates_relaxed',false,'provider_tokens_cost_in_criterion',false,
    'producer_mode','GPT_NATIVE','evidence_class',v_tier,
    'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,'criterion_amendment_ref',v_amend_doc||'@'||v_amend_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A14Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A14Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed under the owner-approved GPT Native in-chat tier and the approved criterion amendment (A14 holdout answers produced by GPT; provider and costs out of the criterion); hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A14Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A14Q_C1:DONE,A14Q_C2:DONE,A14Q_C3:PENDING'
 THEN RAISE EXCEPTION 'A14Q_C2_POSTSTATE_FAILED'; END IF;
END $a14q_c2_close$;
COMMIT;
