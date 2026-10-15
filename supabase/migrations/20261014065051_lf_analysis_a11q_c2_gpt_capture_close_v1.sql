-- A11Q_C2: stores the verified GPT Native capture (data) and then closes the checkpoint under the owner-accepted tier and the approved criterion amendment.
-- Evidence: raw output SHA-256 37d54b45f8bda6d017508f550bdfd3d9fa5f463902c20ca35eb113bca13dd1e6; every value asserted below is recomputed from the stored capture and cross-checked against the stored A7/A8 captures.
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision documents).
BEGIN;
DO $a11q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := '30b92ac11381fb6c5fad853fb0a9fffc98c631b9bcf05d6994a7dbc78aa4d02a';
 v_raw_text text := $raw${
  "schema_version": "A11_ADVERSARIAL_OUTPUT_V1",
  "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
  "cases": [
    {
      "category": "STALE_AUTHORITY",
      "executed": false,
      "expected_safe_behavior": "BLOCK",
      "false_ready_if_unblocked": true,
      "mutation_description": "Inyectar en A7-FRONT-002 una referencia de autoridad sintética presentada como vigente, aunque no tenga validación de actualidad, eliminar los bloqueadores A5-DEC-002 y A5-DEC-004 y cambiar closure de BLOCKED a CLOSED. Intentar que A6-REQ-002 sea admitido como READY por esa supuesta autoridad.",
      "observed_result": null,
      "target_refs": [
        "A7-FRONT-002",
        "A6-REQ-002"
      ]
    },
    {
      "category": "HIDDEN_INDIRECT_IMPACT",
      "executed": false,
      "expected_safe_behavior": "NEED_MORE_EVIDENCE",
      "false_ready_if_unblocked": true,
      "mutation_description": "Eliminar dimension:side_effects de scope_refs de A7-FRONT-004 y retirar su relación de scope_front_matrix, conservando artificialmente all_material_fronts_accounted=true. Intentar cerrar el frente sin contabilizar los posibles efectos indirectos asociados a la comunicación del ahorro.",
      "observed_result": null,
      "target_refs": [
        "A7-FRONT-004",
        "dimension:side_effects"
      ]
    },
    {
      "category": "INCOMPLETE_CONTEXT",
      "executed": false,
      "expected_safe_behavior": "NEED_MORE_EVIDENCE",
      "false_ready_if_unblocked": true,
      "mutation_description": "Modificar scope_readiness de A6-REQ-002 para asignarle READY pese a que A7-FRONT-002 no contiene autoridad verificada ni definiciones aprobadas del ahorro y su base de comparación. Mantener vacías las referencias de autoridad y vigencia, pero intentar admitir el paquete como completo.",
      "observed_result": null,
      "target_refs": [
        "A6-REQ-002",
        "A7-FRONT-002",
        "dimension:data"
      ]
    },
    {
      "category": "CONTRADICTORY_CONTEXT",
      "executed": false,
      "expected_safe_behavior": "BLOCK",
      "false_ready_if_unblocked": true,
      "mutation_description": "Cambiar el estado de A6-REQ-003 a READY y declarar resuelto su requisito temporal, manteniendo A7-FRONT-003 con closure=BLOCKED y el bloqueador A5-DEC-003. Intentar que prevalezca la declaración positiva del scope sobre la evidencia contradictoria del frente.",
      "observed_result": null,
      "target_refs": [
        "A6-REQ-003",
        "A7-FRONT-003",
        "dimension:state"
      ]
    },
    {
      "category": "OMITTED_MATERIAL_FRONT",
      "executed": false,
      "expected_safe_behavior": "BLOCK",
      "false_ready_if_unblocked": true,
      "mutation_description": "Eliminar A7-FRONT-005 de material_fronts y front_candidate_refs, omitir su relación con A6-REQ-005 en scope_front_matrix y conservar all_material_fronts_accounted=true. Intentar que el paquete obtenga PASS sin contabilizar el frente de criterios de comprensión.",
      "observed_result": null,
      "target_refs": [
        "A7-FRONT-005",
        "A6-REQ-005"
      ]
    },
    {
      "category": "READY_SCOPE_WITH_BLOCKING_FRONT",
      "executed": false,
      "expected_safe_behavior": "BLOCK",
      "false_ready_if_unblocked": true,
      "mutation_description": "Asignar status=READY a A6-REQ-001 en scope_readiness mientras A7-FRONT-001 conserva status=REQUIRED, closure=BLOCKED y los bloqueadores A5-DEC-001 y A5-DEC-003. Intentar promover el scope a programación sin resolver su frente obligatorio.",
      "observed_result": null,
      "target_refs": [
        "A6-REQ-001",
        "A7-FRONT-001"
      ]
    },
    {
      "category": "HANDOFF_SCHEMA_DRIFT",
      "executed": false,
      "expected_safe_behavior": "BLOCK",
      "false_ready_if_unblocked": true,
      "mutation_description": "Alterar la representación de A6-REQ-003 en el traspaso sustituyendo material_front_refs por una clave diferente, front_refs, y omitir blockers. Conservar el identificador del scope para intentar que el consumidor acepte el mensaje y produzca PASS aunque haya perdido las relaciones obligatorias con A7-FRONT-003.",
      "observed_result": null,
      "target_refs": [
        "A6-REQ-003",
        "A7-FRONT-003"
      ]
    },
    {
      "category": "LOSSY_WORKER_PROJECTION",
      "executed": false,
      "expected_safe_behavior": "BLOCK",
      "false_ready_if_unblocked": true,
      "mutation_description": "Construir una proyección sintética hacia un worker que conserve el identificador A7-FRONT-004 pero omita blockers, closure y la relación con dimension:side_effects. Intentar que el consumidor interprete la ausencia de estos campos como ausencia de restricciones y devuelva PASS.",
      "observed_result": null,
      "target_refs": [
        "A7-FRONT-004",
        "dimension:side_effects",
        "dimension:errors"
      ]
    },
    {
      "category": "CURRENTNESS_FALSE_INVALIDATION",
      "executed": false,
      "expected_safe_behavior": "NEED_MORE_EVIDENCE",
      "false_ready_if_unblocked": true,
      "mutation_description": "Introducir en una variante sintética de A7-FRONT-001 una referencia de autoridad supuestamente vigente y después etiquetarla como STALE sin prueba de invalidación. Utilizar ese rechazo no demostrado para retirar el frente del alcance como NOT_APPLICABLE e intentar declarar READY a dimension:permissions. El caso debe exigir comprobación de vigencia, no asumir que existe una autoridad real.",
      "observed_result": null,
      "target_refs": [
        "A7-FRONT-001",
        "dimension:permissions"
      ]
    },
    {
      "category": "CURRENTNESS_FALSE_REUSE",
      "executed": false,
      "expected_safe_behavior": "BLOCK",
      "false_ready_if_unblocked": true,
      "mutation_description": "Inyectar en A7-FRONT-002 una referencia sintética a una regla presentada como vencida y cambiar su evaluación de actualidad a CURRENT sin evidencia de renovación. Asignar status=REUSE_AS_IS y closure=CLOSED para intentar declarar READY a A6-REQ-004, aunque las decisiones económicas continúen sin resolver.",
      "observed_result": null,
      "target_refs": [
        "A7-FRONT-002",
        "A6-REQ-004"
      ]
    },
    {
      "category": "SECOND_ORDER_CONSUMER_FAILURE",
      "executed": false,
      "expected_safe_behavior": "BLOCK",
      "false_ready_if_unblocked": true,
      "mutation_description": "Simular un traspaso de segundo orden que consuma A6-REQ-004 a partir de una proyección de A7-FRONT-002, pero descarte A5-DEC-004 y la relación con dimension:data. Intentar que ese consumidor hipotético emita PASS al recibir únicamente el requisito textual, ignorando que el frente original sigue BLOCKED.",
      "observed_result": null,
      "target_refs": [
        "A6-REQ-004",
        "A7-FRONT-002",
        "dimension:data"
      ]
    }
  ],
  "no_ready_claim": true,
  "adversarial_statement": "Se produjeron exactamente once casos adversariales candidatos, uno por cada categoría suministrada, utilizando identificadores de scopes y frentes existentes en el snapshot A9. Cada caso describe una mutación controlada destinada a intentar producir un falso READY o falso PASS y establece el comportamiento seguro esperado. Ningún caso fue ejecutado: executed=false y observed_result=null en los once registros. No existen resultados observados, medición contra un oráculo ni evidencia de que los controles hayan superado estas pruebas. Los escenarios sintéticos de autoridad y consumidores son mutaciones hipotéticas, no afirmaciones sobre el sistema real. El snapshot sigue siendo candidato, sus cinco frentes permanecen bloqueados y no se declara READY, PASS, cierre, admisión ni autorización de programación."
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser at capture time (46550 bytes, after the A11Q_C2 reply); the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"4ff1f1be13c5b1d185164dbd3e6c83cabdf8ce2becac1bdaa5a5bc405070ba16","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"bb991adf3fde3cd5c05238cf2a26b12c70d8afa99466313252b56a781d1bb4ac","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"37d54b45f8bda6d017508f550bdfd3d9fa5f463902c20ca35eb113bca13dd1e6","request_sha256":"0a542a147b6e2374d22fabbcc5cabe93b54ba1aa6cd1f3b35bef13452a10d5a7","run_id":"A11Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A11","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A11Q/A11Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a11q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_raw jsonb; v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text;
 v_in jsonb;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_raw := v_raw_text::jsonb;

 v_in:=$in${
  "a9_snapshot": {
    "candidate_only": true,
    "material_front_coverage": {
      "all_material_fronts_accounted": true,
      "coverage_fingerprint_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "currentness_refs": [],
      "front_candidate_refs": [
        "A7-FRONT-001",
        "A7-FRONT-002",
        "A7-FRONT-003",
        "A7-FRONT-004",
        "A7-FRONT-005"
      ],
      "material_fronts": [
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-001",
            "A5-DEC-003"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions",
            "decision:A5-DEC-001",
            "decision:A5-DEC-003"
          ],
          "front_id": "A7-FRONT-001",
          "front_kind": "ALCANCE_Y_PERMISOS",
          "reason": "El alcance funcional del piloto, los destinatarios, las condiciones previas a la aceptación y los permisos aplicables carecen de definición y autoridad verificadas. Las decisiones A5-DEC-001 y A5-DEC-003 permanecen pendientes. No existe evidencia que autorice cerrar este frente.",
          "scope_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions"
          ],
          "source_signal_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions",
            "decision:A5-DEC-001",
            "decision:A5-DEC-003",
            "gap:TARGET_AUTHORITY_NOT_SUPPLIED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-002",
            "A5-DEC-004"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data",
            "decision:A5-DEC-002",
            "decision:A5-DEC-004",
            "gap:SAVINGS_SEMANTICS_UNRESOLVED",
            "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
          ],
          "front_id": "A7-FRONT-002",
          "front_kind": "SEMANTICA_ECONOMICA",
          "reason": "La definición del ahorro, su base de comparación y su distinción respecto del monto de la cuota no están autorizadas. Las decisiones A5-DEC-002 y A5-DEC-004 permanecen pendientes. No se pueden establecer valores, reglas económicas definitivas ni cierre del frente.",
          "scope_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data"
          ],
          "source_signal_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data",
            "gap:SAVINGS_SEMANTICS_UNRESOLVED",
            "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-003"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-003",
            "dimension:state",
            "decision:A5-DEC-003",
            "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
          ],
          "front_id": "A7-FRONT-003",
          "front_kind": "MOMENTO_Y_ESTADO_OFERTA",
          "reason": "No están acreditados los estados de la oferta, sus transiciones ni las condiciones para comunicar el ahorro antes de la aceptación. A5-DEC-003 permanece pendiente y no se pueden inferir estados o transiciones.",
          "scope_refs": [
            "A6-REQ-003",
            "dimension:state"
          ],
          "source_signal_refs": [
            "A6-REQ-003",
            "dimension:state",
            "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-002",
            "A5-DEC-003",
            "A5-DEC-004"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "dimension:errors",
            "dimension:side_effects",
            "decision:A5-DEC-002",
            "decision:A5-DEC-003",
            "decision:A5-DEC-004"
          ],
          "front_id": "A7-FRONT-004",
          "front_kind": "ERRORES_Y_EFECTOS",
          "reason": "Los comportamientos ante información económica no disponible, indeterminada o incompatible con una oferta, así como los posibles efectos colaterales, permanecen sin determinación autorizada. No se afirma su existencia ni su ausencia. Las tres decisiones relacionadas siguen pendientes.",
          "scope_refs": [
            "dimension:errors",
            "dimension:side_effects"
          ],
          "source_signal_refs": [
            "dimension:errors",
            "dimension:side_effects",
            "decision:A5-DEC-002",
            "decision:A5-DEC-003",
            "decision:A5-DEC-004"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-004",
            "A5-DEC-005"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-005",
            "decision:A5-DEC-004",
            "decision:A5-DEC-005",
            "gap:ACCEPTANCE_EVIDENCE_MISSING"
          ],
          "front_id": "A7-FRONT-005",
          "front_kind": "CRITERIOS_COMPRENSION",
          "reason": "Faltan criterios autorizados para verificar que los clientes comprenden el ahorro y lo distinguen de la cuota durante el piloto. No existen umbrales o resultados verificables suministrados. Las decisiones A5-DEC-004 y A5-DEC-005 permanecen pendientes.",
          "scope_refs": [
            "A6-REQ-005"
          ],
          "source_signal_refs": [
            "A6-REQ-005",
            "gap:ACCEPTANCE_EVIDENCE_MISSING",
            "decision:A5-DEC-004",
            "decision:A5-DEC-005"
          ],
          "status": "REQUIRED"
        }
      ],
      "source_refs": [
        "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
        "supabase://public.lf_eventos/20843"
      ],
      "unmapped_material_signals": []
    },
    "no_ready_claim": true,
    "package_readiness": "BLOCKED",
    "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
    "research_decision": "REQUIRES_DECISION",
    "schema_version": "PROGRAMMING_CONTEXT_SNAPSHOT_V1",
    "scope_front_matrix": [
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-001"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "dimension:functional"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "dimension:permissions"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-002"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-004"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "dimension:data"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-003",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-003"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-003",
        "front_status": "REQUIRED",
        "scope_id": "dimension:state"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-004",
        "front_status": "REQUIRED",
        "scope_id": "dimension:errors"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-004",
        "front_status": "REQUIRED",
        "scope_id": "dimension:side_effects"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-005",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-005"
      }
    ],
    "scope_readiness": [
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "A6-REQ-001",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "A6-REQ-002",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-003"
        ],
        "scope_id": "A6-REQ-003",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "A6-REQ-004",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-004",
          "A5-DEC-005"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-005"
        ],
        "scope_id": "A6-REQ-005",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "dimension:functional",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "dimension:data",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "dimension:permissions",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-003"
        ],
        "scope_id": "dimension:state",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-004"
        ],
        "scope_id": "dimension:errors",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-004"
        ],
        "scope_id": "dimension:side_effects",
        "status": "BLOCKED"
      }
    ],
    "snapshot_statement": "Snapshot exclusivamente candidato, construido a partir de las salidas A7 y A8 suministradas. Contiene once scopes: cinco requisitos provisionales y seis dimensiones, vinculados mediante once relaciones a cinco frentes materiales. La contabilidad de los elementos recibidos está completa, pero los cinco frentes permanecen REQUIRED y BLOCKED. Cada scope tiene al menos un frente bloqueante, por lo que ninguno puede declararse READY. La investigación conserva REQUIRES_DECISION según A8, mientras que el paquete permanece BLOCKED por decisiones materiales pendientes, ausencia de autoridad positiva, falta de evidencia de vigencia, implementación desconocida y línea base AS-IS no suministrada. Los cinco identificadores A5 deben contrastarse primero con decisiones y reglas vigentes; solo las cuestiones materialmente no resueltas corresponderían al propietario humano. La cobertura de la entrada no demuestra cobertura completa del sistema real. No se creó una huella de cobertura auténtica: los 64 ceros son únicamente el marcador solicitado por el arnés. No se ha persistido, atestiguado, aprobado ni admitido el snapshot para programación. Tampoco se ha declarado READY, seleccionado una solución técnica o autorizado implementación."
  },
  "categories": [
    {
      "category": "STALE_AUTHORITY",
      "definition": "una autoridad citada ya no está vigente"
    },
    {
      "category": "HIDDEN_INDIRECT_IMPACT",
      "definition": "un impacto indirecto no aparece declarado"
    },
    {
      "category": "INCOMPLETE_CONTEXT",
      "definition": "falta contexto necesario para decidir"
    },
    {
      "category": "CONTRADICTORY_CONTEXT",
      "definition": "dos piezas del contexto se contradicen"
    },
    {
      "category": "OMITTED_MATERIAL_FRONT",
      "definition": "se omite un frente material"
    },
    {
      "category": "READY_SCOPE_WITH_BLOCKING_FRONT",
      "definition": "un scope aparece READY pese a tener un frente bloqueante"
    },
    {
      "category": "HANDOFF_SCHEMA_DRIFT",
      "definition": "el esquema del traspaso cambia respecto del acordado"
    },
    {
      "category": "LOSSY_WORKER_PROJECTION",
      "definition": "la proyección hacia el worker pierde información material"
    },
    {
      "category": "CURRENTNESS_FALSE_INVALIDATION",
      "definition": "se invalida como vencido algo que sigue vigente"
    },
    {
      "category": "CURRENTNESS_FALSE_REUSE",
      "definition": "se reutiliza como vigente algo vencido"
    },
    {
      "category": "SECOND_ORDER_CONSUMER_FAILURE",
      "definition": "falla un consumidor de segundo orden del resultado"
    }
  ],
  "schema_version": "A11_ADVERSARIAL_INPUT_V1"
}
$in$::jsonb;
 IF encode(sha256(convert_to(rtrim($in${
  "a9_snapshot": {
    "candidate_only": true,
    "material_front_coverage": {
      "all_material_fronts_accounted": true,
      "coverage_fingerprint_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "currentness_refs": [],
      "front_candidate_refs": [
        "A7-FRONT-001",
        "A7-FRONT-002",
        "A7-FRONT-003",
        "A7-FRONT-004",
        "A7-FRONT-005"
      ],
      "material_fronts": [
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-001",
            "A5-DEC-003"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions",
            "decision:A5-DEC-001",
            "decision:A5-DEC-003"
          ],
          "front_id": "A7-FRONT-001",
          "front_kind": "ALCANCE_Y_PERMISOS",
          "reason": "El alcance funcional del piloto, los destinatarios, las condiciones previas a la aceptación y los permisos aplicables carecen de definición y autoridad verificadas. Las decisiones A5-DEC-001 y A5-DEC-003 permanecen pendientes. No existe evidencia que autorice cerrar este frente.",
          "scope_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions"
          ],
          "source_signal_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions",
            "decision:A5-DEC-001",
            "decision:A5-DEC-003",
            "gap:TARGET_AUTHORITY_NOT_SUPPLIED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-002",
            "A5-DEC-004"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data",
            "decision:A5-DEC-002",
            "decision:A5-DEC-004",
            "gap:SAVINGS_SEMANTICS_UNRESOLVED",
            "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
          ],
          "front_id": "A7-FRONT-002",
          "front_kind": "SEMANTICA_ECONOMICA",
          "reason": "La definición del ahorro, su base de comparación y su distinción respecto del monto de la cuota no están autorizadas. Las decisiones A5-DEC-002 y A5-DEC-004 permanecen pendientes. No se pueden establecer valores, reglas económicas definitivas ni cierre del frente.",
          "scope_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data"
          ],
          "source_signal_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data",
            "gap:SAVINGS_SEMANTICS_UNRESOLVED",
            "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-003"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-003",
            "dimension:state",
            "decision:A5-DEC-003",
            "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
          ],
          "front_id": "A7-FRONT-003",
          "front_kind": "MOMENTO_Y_ESTADO_OFERTA",
          "reason": "No están acreditados los estados de la oferta, sus transiciones ni las condiciones para comunicar el ahorro antes de la aceptación. A5-DEC-003 permanece pendiente y no se pueden inferir estados o transiciones.",
          "scope_refs": [
            "A6-REQ-003",
            "dimension:state"
          ],
          "source_signal_refs": [
            "A6-REQ-003",
            "dimension:state",
            "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-002",
            "A5-DEC-003",
            "A5-DEC-004"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "dimension:errors",
            "dimension:side_effects",
            "decision:A5-DEC-002",
            "decision:A5-DEC-003",
            "decision:A5-DEC-004"
          ],
          "front_id": "A7-FRONT-004",
          "front_kind": "ERRORES_Y_EFECTOS",
          "reason": "Los comportamientos ante información económica no disponible, indeterminada o incompatible con una oferta, así como los posibles efectos colaterales, permanecen sin determinación autorizada. No se afirma su existencia ni su ausencia. Las tres decisiones relacionadas siguen pendientes.",
          "scope_refs": [
            "dimension:errors",
            "dimension:side_effects"
          ],
          "source_signal_refs": [
            "dimension:errors",
            "dimension:side_effects",
            "decision:A5-DEC-002",
            "decision:A5-DEC-003",
            "decision:A5-DEC-004"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-004",
            "A5-DEC-005"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-005",
            "decision:A5-DEC-004",
            "decision:A5-DEC-005",
            "gap:ACCEPTANCE_EVIDENCE_MISSING"
          ],
          "front_id": "A7-FRONT-005",
          "front_kind": "CRITERIOS_COMPRENSION",
          "reason": "Faltan criterios autorizados para verificar que los clientes comprenden el ahorro y lo distinguen de la cuota durante el piloto. No existen umbrales o resultados verificables suministrados. Las decisiones A5-DEC-004 y A5-DEC-005 permanecen pendientes.",
          "scope_refs": [
            "A6-REQ-005"
          ],
          "source_signal_refs": [
            "A6-REQ-005",
            "gap:ACCEPTANCE_EVIDENCE_MISSING",
            "decision:A5-DEC-004",
            "decision:A5-DEC-005"
          ],
          "status": "REQUIRED"
        }
      ],
      "source_refs": [
        "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
        "supabase://public.lf_eventos/20843"
      ],
      "unmapped_material_signals": []
    },
    "no_ready_claim": true,
    "package_readiness": "BLOCKED",
    "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
    "research_decision": "REQUIRES_DECISION",
    "schema_version": "PROGRAMMING_CONTEXT_SNAPSHOT_V1",
    "scope_front_matrix": [
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-001"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "dimension:functional"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "dimension:permissions"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-002"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-004"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "dimension:data"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-003",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-003"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-003",
        "front_status": "REQUIRED",
        "scope_id": "dimension:state"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-004",
        "front_status": "REQUIRED",
        "scope_id": "dimension:errors"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-004",
        "front_status": "REQUIRED",
        "scope_id": "dimension:side_effects"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-005",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-005"
      }
    ],
    "scope_readiness": [
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "A6-REQ-001",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "A6-REQ-002",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-003"
        ],
        "scope_id": "A6-REQ-003",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "A6-REQ-004",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-004",
          "A5-DEC-005"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-005"
        ],
        "scope_id": "A6-REQ-005",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "dimension:functional",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "dimension:data",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "dimension:permissions",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-003"
        ],
        "scope_id": "dimension:state",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-004"
        ],
        "scope_id": "dimension:errors",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-004"
        ],
        "scope_id": "dimension:side_effects",
        "status": "BLOCKED"
      }
    ],
    "snapshot_statement": "Snapshot exclusivamente candidato, construido a partir de las salidas A7 y A8 suministradas. Contiene once scopes: cinco requisitos provisionales y seis dimensiones, vinculados mediante once relaciones a cinco frentes materiales. La contabilidad de los elementos recibidos está completa, pero los cinco frentes permanecen REQUIRED y BLOCKED. Cada scope tiene al menos un frente bloqueante, por lo que ninguno puede declararse READY. La investigación conserva REQUIRES_DECISION según A8, mientras que el paquete permanece BLOCKED por decisiones materiales pendientes, ausencia de autoridad positiva, falta de evidencia de vigencia, implementación desconocida y línea base AS-IS no suministrada. Los cinco identificadores A5 deben contrastarse primero con decisiones y reglas vigentes; solo las cuestiones materialmente no resueltas corresponderían al propietario humano. La cobertura de la entrada no demuestra cobertura completa del sistema real. No se creó una huella de cobertura auténtica: los 64 ceros son únicamente el marcador solicitado por el arnés. No se ha persistido, atestiguado, aprobado ni admitido el snapshot para programación. Tampoco se ha declarado READY, seleccionado una solución técnica o autorizado implementación."
  },
  "categories": [
    {
      "category": "STALE_AUTHORITY",
      "definition": "una autoridad citada ya no está vigente"
    },
    {
      "category": "HIDDEN_INDIRECT_IMPACT",
      "definition": "un impacto indirecto no aparece declarado"
    },
    {
      "category": "INCOMPLETE_CONTEXT",
      "definition": "falta contexto necesario para decidir"
    },
    {
      "category": "CONTRADICTORY_CONTEXT",
      "definition": "dos piezas del contexto se contradicen"
    },
    {
      "category": "OMITTED_MATERIAL_FRONT",
      "definition": "se omite un frente material"
    },
    {
      "category": "READY_SCOPE_WITH_BLOCKING_FRONT",
      "definition": "un scope aparece READY pese a tener un frente bloqueante"
    },
    {
      "category": "HANDOFF_SCHEMA_DRIFT",
      "definition": "el esquema del traspaso cambia respecto del acordado"
    },
    {
      "category": "LOSSY_WORKER_PROJECTION",
      "definition": "la proyección hacia el worker pierde información material"
    },
    {
      "category": "CURRENTNESS_FALSE_INVALIDATION",
      "definition": "se invalida como vencido algo que sigue vigente"
    },
    {
      "category": "CURRENTNESS_FALSE_REUSE",
      "definition": "se reutiliza como vigente algo vencido"
    },
    {
      "category": "SECOND_ORDER_CONSUMER_FAILURE",
      "definition": "falla un consumidor de segundo orden del resultado"
    }
  ],
  "schema_version": "A11_ADVERSARIAL_INPUT_V1"
}
$in$,E'\n'),'UTF8')),'hex') <> 'bb991adf3fde3cd5c05238cf2a26b12c70d8afa99466313252b56a781d1bb4ac' THEN RAISE EXCEPTION 'A11Q_C2_INPUT_FIXTURE_DRIFT'; END IF;
 IF (v_raw->>'schema_version'='A11_ADVERSARIAL_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'no_ready_claim'='true' AND (SELECT u.unit_metadata#>'{gpt_native_captures_v1,A9Q_C2}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A9Q')->>'raw_output_sha256'='c7bc45fdc546d263ed34754d1780073d7ffcef44c16f0b85440990ebc530d513' AND v_in->'a9_snapshot'=(((SELECT u.unit_metadata#>'{gpt_native_captures_v1,A9Q_C2}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A9Q')->>'raw_output_text')::jsonb) AND jsonb_array_length(v_raw->'cases')=11 AND jsonb_array_length(v_in->'categories')=11 AND (SELECT array_agg(c->>'category' ORDER BY c->>'category') FROM jsonb_array_elements(v_in->'categories') c)=(SELECT array_agg(r->>'category' ORDER BY r->>'category') FROM jsonb_array_elements(v_raw->'cases') r) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'cases') r WHERE (r->>'executed')<>'false' OR r->'observed_result'<>'null'::jsonb OR (r->>'false_ready_if_unblocked')<>'true' OR r->>'expected_safe_behavior' NOT IN ('BLOCK','REQUIRES_DECISION','NEED_MORE_EVIDENCE') OR length(trim(r->>'mutation_description'))<30 OR jsonb_array_length(r->'target_refs')<1 OR (SELECT count(DISTINCT t) FROM jsonb_array_elements_text(r->'target_refs') t)<>jsonb_array_length(r->'target_refs')) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'cases') r, jsonb_array_elements_text(r->'target_refs') t WHERE NOT (EXISTS (SELECT 1 FROM jsonb_array_elements(v_in#>'{a9_snapshot,scope_readiness}') s WHERE s->>'scope_id'=t) OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_in#>'{a9_snapshot,material_front_coverage,material_fronts}') f WHERE f->>'front_id'=t)))) IS NOT TRUE THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1121 AND checkpoint_code='A11Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A11Q' AND work_item_id=1121 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A11Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A11Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A11Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A11Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1121;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A11Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A11Q' AND work_item_id=1121;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A11Q' AND work_item_id=1121;
 IF v_m#>'{gpt_native_captures_v1,A11Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1121;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a11q_c2_cap$;
-- A11Q_C2 closure under the owner-approved GPT Native tier (decision: docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md).
-- A11Q_C2 closure under the owner-approved GPT Native tier (docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md) and the criterion amendment (docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).
DO $a11q_c2_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A11Q';
 v_cp constant text := 'A11Q_C2';
 v_wi constant bigint := 1121;
 v_actor constant text := 'ANALYSIS_QUAL_C2_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_a11q_c2_gpt_native_packet_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '2918579179b97bf3d479a3b3a05bda51a08a05fed456e41270c1a95e710acf53';
 v_amend_doc constant text := 'docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md';
 v_amend_sha constant text := '17d77d4af397a768d65617368cd043e2abc3795fc9f8f523ddfcb4044b8c2109';
 v_packet_sha constant text := '30b92ac11381fb6c5fad853fb0a9fffc98c631b9bcf05d6994a7dbc78aa4d02a';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1121 and checkpoint_code=''A11Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_open int; v_pass jsonb; v_amend jsonb;
 v_in jsonb;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A11Q_C2_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A11Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A11Q/A11Q_C2'
 THEN RAISE EXCEPTION 'A11Q_C2_PRESTATE_DRIFT'; END IF;

 -- Recompute the evidence from the stored capture.
 v_cap:=v_m#>'{gpt_native_captures_v1,A11Q_C2}'; v_pk:=v_m#>'{gpt_native_packets_v1,A11Q_C2}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha
    OR v_cap->>'request_sha256' IS DISTINCT FROM v_pk->>'request_sha256'
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A11Q_C2_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'A11Q_C2_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A11Q_C2_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_open:=jsonb_array_length(v_raw->'cases');
 v_in:=$in${
  "a9_snapshot": {
    "candidate_only": true,
    "material_front_coverage": {
      "all_material_fronts_accounted": true,
      "coverage_fingerprint_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "currentness_refs": [],
      "front_candidate_refs": [
        "A7-FRONT-001",
        "A7-FRONT-002",
        "A7-FRONT-003",
        "A7-FRONT-004",
        "A7-FRONT-005"
      ],
      "material_fronts": [
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-001",
            "A5-DEC-003"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions",
            "decision:A5-DEC-001",
            "decision:A5-DEC-003"
          ],
          "front_id": "A7-FRONT-001",
          "front_kind": "ALCANCE_Y_PERMISOS",
          "reason": "El alcance funcional del piloto, los destinatarios, las condiciones previas a la aceptación y los permisos aplicables carecen de definición y autoridad verificadas. Las decisiones A5-DEC-001 y A5-DEC-003 permanecen pendientes. No existe evidencia que autorice cerrar este frente.",
          "scope_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions"
          ],
          "source_signal_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions",
            "decision:A5-DEC-001",
            "decision:A5-DEC-003",
            "gap:TARGET_AUTHORITY_NOT_SUPPLIED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-002",
            "A5-DEC-004"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data",
            "decision:A5-DEC-002",
            "decision:A5-DEC-004",
            "gap:SAVINGS_SEMANTICS_UNRESOLVED",
            "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
          ],
          "front_id": "A7-FRONT-002",
          "front_kind": "SEMANTICA_ECONOMICA",
          "reason": "La definición del ahorro, su base de comparación y su distinción respecto del monto de la cuota no están autorizadas. Las decisiones A5-DEC-002 y A5-DEC-004 permanecen pendientes. No se pueden establecer valores, reglas económicas definitivas ni cierre del frente.",
          "scope_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data"
          ],
          "source_signal_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data",
            "gap:SAVINGS_SEMANTICS_UNRESOLVED",
            "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-003"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-003",
            "dimension:state",
            "decision:A5-DEC-003",
            "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
          ],
          "front_id": "A7-FRONT-003",
          "front_kind": "MOMENTO_Y_ESTADO_OFERTA",
          "reason": "No están acreditados los estados de la oferta, sus transiciones ni las condiciones para comunicar el ahorro antes de la aceptación. A5-DEC-003 permanece pendiente y no se pueden inferir estados o transiciones.",
          "scope_refs": [
            "A6-REQ-003",
            "dimension:state"
          ],
          "source_signal_refs": [
            "A6-REQ-003",
            "dimension:state",
            "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-002",
            "A5-DEC-003",
            "A5-DEC-004"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "dimension:errors",
            "dimension:side_effects",
            "decision:A5-DEC-002",
            "decision:A5-DEC-003",
            "decision:A5-DEC-004"
          ],
          "front_id": "A7-FRONT-004",
          "front_kind": "ERRORES_Y_EFECTOS",
          "reason": "Los comportamientos ante información económica no disponible, indeterminada o incompatible con una oferta, así como los posibles efectos colaterales, permanecen sin determinación autorizada. No se afirma su existencia ni su ausencia. Las tres decisiones relacionadas siguen pendientes.",
          "scope_refs": [
            "dimension:errors",
            "dimension:side_effects"
          ],
          "source_signal_refs": [
            "dimension:errors",
            "dimension:side_effects",
            "decision:A5-DEC-002",
            "decision:A5-DEC-003",
            "decision:A5-DEC-004"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-004",
            "A5-DEC-005"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-005",
            "decision:A5-DEC-004",
            "decision:A5-DEC-005",
            "gap:ACCEPTANCE_EVIDENCE_MISSING"
          ],
          "front_id": "A7-FRONT-005",
          "front_kind": "CRITERIOS_COMPRENSION",
          "reason": "Faltan criterios autorizados para verificar que los clientes comprenden el ahorro y lo distinguen de la cuota durante el piloto. No existen umbrales o resultados verificables suministrados. Las decisiones A5-DEC-004 y A5-DEC-005 permanecen pendientes.",
          "scope_refs": [
            "A6-REQ-005"
          ],
          "source_signal_refs": [
            "A6-REQ-005",
            "gap:ACCEPTANCE_EVIDENCE_MISSING",
            "decision:A5-DEC-004",
            "decision:A5-DEC-005"
          ],
          "status": "REQUIRED"
        }
      ],
      "source_refs": [
        "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
        "supabase://public.lf_eventos/20843"
      ],
      "unmapped_material_signals": []
    },
    "no_ready_claim": true,
    "package_readiness": "BLOCKED",
    "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
    "research_decision": "REQUIRES_DECISION",
    "schema_version": "PROGRAMMING_CONTEXT_SNAPSHOT_V1",
    "scope_front_matrix": [
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-001"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "dimension:functional"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "dimension:permissions"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-002"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-004"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "dimension:data"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-003",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-003"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-003",
        "front_status": "REQUIRED",
        "scope_id": "dimension:state"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-004",
        "front_status": "REQUIRED",
        "scope_id": "dimension:errors"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-004",
        "front_status": "REQUIRED",
        "scope_id": "dimension:side_effects"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-005",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-005"
      }
    ],
    "scope_readiness": [
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "A6-REQ-001",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "A6-REQ-002",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-003"
        ],
        "scope_id": "A6-REQ-003",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "A6-REQ-004",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-004",
          "A5-DEC-005"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-005"
        ],
        "scope_id": "A6-REQ-005",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "dimension:functional",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "dimension:data",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "dimension:permissions",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-003"
        ],
        "scope_id": "dimension:state",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-004"
        ],
        "scope_id": "dimension:errors",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-004"
        ],
        "scope_id": "dimension:side_effects",
        "status": "BLOCKED"
      }
    ],
    "snapshot_statement": "Snapshot exclusivamente candidato, construido a partir de las salidas A7 y A8 suministradas. Contiene once scopes: cinco requisitos provisionales y seis dimensiones, vinculados mediante once relaciones a cinco frentes materiales. La contabilidad de los elementos recibidos está completa, pero los cinco frentes permanecen REQUIRED y BLOCKED. Cada scope tiene al menos un frente bloqueante, por lo que ninguno puede declararse READY. La investigación conserva REQUIRES_DECISION según A8, mientras que el paquete permanece BLOCKED por decisiones materiales pendientes, ausencia de autoridad positiva, falta de evidencia de vigencia, implementación desconocida y línea base AS-IS no suministrada. Los cinco identificadores A5 deben contrastarse primero con decisiones y reglas vigentes; solo las cuestiones materialmente no resueltas corresponderían al propietario humano. La cobertura de la entrada no demuestra cobertura completa del sistema real. No se creó una huella de cobertura auténtica: los 64 ceros son únicamente el marcador solicitado por el arnés. No se ha persistido, atestiguado, aprobado ni admitido el snapshot para programación. Tampoco se ha declarado READY, seleccionado una solución técnica o autorizado implementación."
  },
  "categories": [
    {
      "category": "STALE_AUTHORITY",
      "definition": "una autoridad citada ya no está vigente"
    },
    {
      "category": "HIDDEN_INDIRECT_IMPACT",
      "definition": "un impacto indirecto no aparece declarado"
    },
    {
      "category": "INCOMPLETE_CONTEXT",
      "definition": "falta contexto necesario para decidir"
    },
    {
      "category": "CONTRADICTORY_CONTEXT",
      "definition": "dos piezas del contexto se contradicen"
    },
    {
      "category": "OMITTED_MATERIAL_FRONT",
      "definition": "se omite un frente material"
    },
    {
      "category": "READY_SCOPE_WITH_BLOCKING_FRONT",
      "definition": "un scope aparece READY pese a tener un frente bloqueante"
    },
    {
      "category": "HANDOFF_SCHEMA_DRIFT",
      "definition": "el esquema del traspaso cambia respecto del acordado"
    },
    {
      "category": "LOSSY_WORKER_PROJECTION",
      "definition": "la proyección hacia el worker pierde información material"
    },
    {
      "category": "CURRENTNESS_FALSE_INVALIDATION",
      "definition": "se invalida como vencido algo que sigue vigente"
    },
    {
      "category": "CURRENTNESS_FALSE_REUSE",
      "definition": "se reutiliza como vigente algo vencido"
    },
    {
      "category": "SECOND_ORDER_CONSUMER_FAILURE",
      "definition": "falla un consumidor de segundo orden del resultado"
    }
  ],
  "schema_version": "A11_ADVERSARIAL_INPUT_V1"
}
$in$::jsonb;
 IF encode(sha256(convert_to(rtrim($in${
  "a9_snapshot": {
    "candidate_only": true,
    "material_front_coverage": {
      "all_material_fronts_accounted": true,
      "coverage_fingerprint_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "currentness_refs": [],
      "front_candidate_refs": [
        "A7-FRONT-001",
        "A7-FRONT-002",
        "A7-FRONT-003",
        "A7-FRONT-004",
        "A7-FRONT-005"
      ],
      "material_fronts": [
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-001",
            "A5-DEC-003"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions",
            "decision:A5-DEC-001",
            "decision:A5-DEC-003"
          ],
          "front_id": "A7-FRONT-001",
          "front_kind": "ALCANCE_Y_PERMISOS",
          "reason": "El alcance funcional del piloto, los destinatarios, las condiciones previas a la aceptación y los permisos aplicables carecen de definición y autoridad verificadas. Las decisiones A5-DEC-001 y A5-DEC-003 permanecen pendientes. No existe evidencia que autorice cerrar este frente.",
          "scope_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions"
          ],
          "source_signal_refs": [
            "A6-REQ-001",
            "dimension:functional",
            "dimension:permissions",
            "decision:A5-DEC-001",
            "decision:A5-DEC-003",
            "gap:TARGET_AUTHORITY_NOT_SUPPLIED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-002",
            "A5-DEC-004"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data",
            "decision:A5-DEC-002",
            "decision:A5-DEC-004",
            "gap:SAVINGS_SEMANTICS_UNRESOLVED",
            "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
          ],
          "front_id": "A7-FRONT-002",
          "front_kind": "SEMANTICA_ECONOMICA",
          "reason": "La definición del ahorro, su base de comparación y su distinción respecto del monto de la cuota no están autorizadas. Las decisiones A5-DEC-002 y A5-DEC-004 permanecen pendientes. No se pueden establecer valores, reglas económicas definitivas ni cierre del frente.",
          "scope_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data"
          ],
          "source_signal_refs": [
            "A6-REQ-002",
            "A6-REQ-004",
            "dimension:data",
            "gap:SAVINGS_SEMANTICS_UNRESOLVED",
            "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-003"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-003",
            "dimension:state",
            "decision:A5-DEC-003",
            "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
          ],
          "front_id": "A7-FRONT-003",
          "front_kind": "MOMENTO_Y_ESTADO_OFERTA",
          "reason": "No están acreditados los estados de la oferta, sus transiciones ni las condiciones para comunicar el ahorro antes de la aceptación. A5-DEC-003 permanece pendiente y no se pueden inferir estados o transiciones.",
          "scope_refs": [
            "A6-REQ-003",
            "dimension:state"
          ],
          "source_signal_refs": [
            "A6-REQ-003",
            "dimension:state",
            "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-002",
            "A5-DEC-003",
            "A5-DEC-004"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "dimension:errors",
            "dimension:side_effects",
            "decision:A5-DEC-002",
            "decision:A5-DEC-003",
            "decision:A5-DEC-004"
          ],
          "front_id": "A7-FRONT-004",
          "front_kind": "ERRORES_Y_EFECTOS",
          "reason": "Los comportamientos ante información económica no disponible, indeterminada o incompatible con una oferta, así como los posibles efectos colaterales, permanecen sin determinación autorizada. No se afirma su existencia ni su ausencia. Las tres decisiones relacionadas siguen pendientes.",
          "scope_refs": [
            "dimension:errors",
            "dimension:side_effects"
          ],
          "source_signal_refs": [
            "dimension:errors",
            "dimension:side_effects",
            "decision:A5-DEC-002",
            "decision:A5-DEC-003",
            "decision:A5-DEC-004"
          ],
          "status": "REQUIRED"
        },
        {
          "authority_refs": [],
          "blockers": [
            "A5-DEC-004",
            "A5-DEC-005"
          ],
          "closure": "BLOCKED",
          "currentness_refs": [],
          "evidence_refs": [
            "A6-REQ-005",
            "decision:A5-DEC-004",
            "decision:A5-DEC-005",
            "gap:ACCEPTANCE_EVIDENCE_MISSING"
          ],
          "front_id": "A7-FRONT-005",
          "front_kind": "CRITERIOS_COMPRENSION",
          "reason": "Faltan criterios autorizados para verificar que los clientes comprenden el ahorro y lo distinguen de la cuota durante el piloto. No existen umbrales o resultados verificables suministrados. Las decisiones A5-DEC-004 y A5-DEC-005 permanecen pendientes.",
          "scope_refs": [
            "A6-REQ-005"
          ],
          "source_signal_refs": [
            "A6-REQ-005",
            "gap:ACCEPTANCE_EVIDENCE_MISSING",
            "decision:A5-DEC-004",
            "decision:A5-DEC-005"
          ],
          "status": "REQUIRED"
        }
      ],
      "source_refs": [
        "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
        "supabase://public.lf_eventos/20843"
      ],
      "unmapped_material_signals": []
    },
    "no_ready_claim": true,
    "package_readiness": "BLOCKED",
    "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
    "research_decision": "REQUIRES_DECISION",
    "schema_version": "PROGRAMMING_CONTEXT_SNAPSHOT_V1",
    "scope_front_matrix": [
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-001"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "dimension:functional"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-001",
        "front_status": "REQUIRED",
        "scope_id": "dimension:permissions"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-002"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-004"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-002",
        "front_status": "REQUIRED",
        "scope_id": "dimension:data"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-003",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-003"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-003",
        "front_status": "REQUIRED",
        "scope_id": "dimension:state"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-004",
        "front_status": "REQUIRED",
        "scope_id": "dimension:errors"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-004",
        "front_status": "REQUIRED",
        "scope_id": "dimension:side_effects"
      },
      {
        "effect_on_scope": "BLOCKS",
        "front_closure": "BLOCKED",
        "front_id": "A7-FRONT-005",
        "front_status": "REQUIRED",
        "scope_id": "A6-REQ-005"
      }
    ],
    "scope_readiness": [
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "A6-REQ-001",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "A6-REQ-002",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-003"
        ],
        "scope_id": "A6-REQ-003",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "A6-REQ-004",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-004",
          "A5-DEC-005"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-005"
        ],
        "scope_id": "A6-REQ-005",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "dimension:functional",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-002"
        ],
        "scope_id": "dimension:data",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-001",
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-001"
        ],
        "scope_id": "dimension:permissions",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-003"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-003"
        ],
        "scope_id": "dimension:state",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-004"
        ],
        "scope_id": "dimension:errors",
        "status": "BLOCKED"
      },
      {
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "depends_on_scope_ids": [],
        "material_front_refs": [
          "A7-FRONT-004"
        ],
        "scope_id": "dimension:side_effects",
        "status": "BLOCKED"
      }
    ],
    "snapshot_statement": "Snapshot exclusivamente candidato, construido a partir de las salidas A7 y A8 suministradas. Contiene once scopes: cinco requisitos provisionales y seis dimensiones, vinculados mediante once relaciones a cinco frentes materiales. La contabilidad de los elementos recibidos está completa, pero los cinco frentes permanecen REQUIRED y BLOCKED. Cada scope tiene al menos un frente bloqueante, por lo que ninguno puede declararse READY. La investigación conserva REQUIRES_DECISION según A8, mientras que el paquete permanece BLOCKED por decisiones materiales pendientes, ausencia de autoridad positiva, falta de evidencia de vigencia, implementación desconocida y línea base AS-IS no suministrada. Los cinco identificadores A5 deben contrastarse primero con decisiones y reglas vigentes; solo las cuestiones materialmente no resueltas corresponderían al propietario humano. La cobertura de la entrada no demuestra cobertura completa del sistema real. No se creó una huella de cobertura auténtica: los 64 ceros son únicamente el marcador solicitado por el arnés. No se ha persistido, atestiguado, aprobado ni admitido el snapshot para programación. Tampoco se ha declarado READY, seleccionado una solución técnica o autorizado implementación."
  },
  "categories": [
    {
      "category": "STALE_AUTHORITY",
      "definition": "una autoridad citada ya no está vigente"
    },
    {
      "category": "HIDDEN_INDIRECT_IMPACT",
      "definition": "un impacto indirecto no aparece declarado"
    },
    {
      "category": "INCOMPLETE_CONTEXT",
      "definition": "falta contexto necesario para decidir"
    },
    {
      "category": "CONTRADICTORY_CONTEXT",
      "definition": "dos piezas del contexto se contradicen"
    },
    {
      "category": "OMITTED_MATERIAL_FRONT",
      "definition": "se omite un frente material"
    },
    {
      "category": "READY_SCOPE_WITH_BLOCKING_FRONT",
      "definition": "un scope aparece READY pese a tener un frente bloqueante"
    },
    {
      "category": "HANDOFF_SCHEMA_DRIFT",
      "definition": "el esquema del traspaso cambia respecto del acordado"
    },
    {
      "category": "LOSSY_WORKER_PROJECTION",
      "definition": "la proyección hacia el worker pierde información material"
    },
    {
      "category": "CURRENTNESS_FALSE_INVALIDATION",
      "definition": "se invalida como vencido algo que sigue vigente"
    },
    {
      "category": "CURRENTNESS_FALSE_REUSE",
      "definition": "se reutiliza como vigente algo vencido"
    },
    {
      "category": "SECOND_ORDER_CONSUMER_FAILURE",
      "definition": "falla un consumidor de segundo orden del resultado"
    }
  ],
  "schema_version": "A11_ADVERSARIAL_INPUT_V1"
}
$in$,E'\n'),'UTF8')),'hex') <> 'bb991adf3fde3cd5c05238cf2a26b12c70d8afa99466313252b56a781d1bb4ac' THEN RAISE EXCEPTION 'A11Q_C2_INPUT_FIXTURE_DRIFT'; END IF;
 IF (v_raw->>'schema_version'='A11_ADVERSARIAL_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'no_ready_claim'='true' AND (SELECT u.unit_metadata#>'{gpt_native_captures_v1,A9Q_C2}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A9Q')->>'raw_output_sha256'='c7bc45fdc546d263ed34754d1780073d7ffcef44c16f0b85440990ebc530d513' AND v_in->'a9_snapshot'=(((SELECT u.unit_metadata#>'{gpt_native_captures_v1,A9Q_C2}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A9Q')->>'raw_output_text')::jsonb) AND jsonb_array_length(v_raw->'cases')=11 AND jsonb_array_length(v_in->'categories')=11 AND (SELECT array_agg(c->>'category' ORDER BY c->>'category') FROM jsonb_array_elements(v_in->'categories') c)=(SELECT array_agg(r->>'category' ORDER BY r->>'category') FROM jsonb_array_elements(v_raw->'cases') r) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'cases') r WHERE (r->>'executed')<>'false' OR r->'observed_result'<>'null'::jsonb OR (r->>'false_ready_if_unblocked')<>'true' OR r->>'expected_safe_behavior' NOT IN ('BLOCK','REQUIRES_DECISION','NEED_MORE_EVIDENCE') OR length(trim(r->>'mutation_description'))<30 OR jsonb_array_length(r->'target_refs')<1 OR (SELECT count(DISTINCT t) FROM jsonb_array_elements_text(r->'target_refs') t)<>jsonb_array_length(r->'target_refs')) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'cases') r, jsonb_array_elements_text(r->'target_refs') t WHERE NOT (EXISTS (SELECT 1 FROM jsonb_array_elements(v_in#>'{a9_snapshot,scope_readiness}') s WHERE s->>'scope_id'=t) OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_in#>'{a9_snapshot,material_front_coverage,material_fronts}') f WHERE f->>'front_id'=t)))) IS NOT TRUE
 THEN RAISE EXCEPTION 'A11Q_C2_CONTENT_CHECK_FAILED'; END IF;
 IF length(coalesce(v_cap->>'chat_transcript_ref',''))<10 OR coalesce(v_cap->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'A11Q_C2_CHAT_BINDING_MISSING'; END IF;

 v_amend:=jsonb_build_object('criterion_amended',true,'original','Ejecuciones reales adversariales sobre ruta gobernada','amended','Casos adversariales producidos por GPT, sin ejecución gobernada','amendment_ref',v_amend_doc||'@'||v_amend_sha,'plan_exit_criterion_modified',false);
 v_pass:=jsonb_build_object('capture_verified',true,'criterion_amendment',v_amend,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,
   'content_checks_passed',true,'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native capture of the A11 adversarial case set under the owner-approved equivalent tier and the approved criterion amendment, and bind its result',
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
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A11Q_C2_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A11Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A11Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A11Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A11Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/A11Q#unit_metadata.gpt_native_captures_v1.A11Q_C2'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';request_sha256:'||(v_cap->>'request_sha256')
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha||';amendment:'||v_amend_doc||'@'||v_amend_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A11Q_C2_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A11Q_C2_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','request_sha256',v_cap->>'request_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'request_ref',v_raw->>'request_ref','cases_in_set',v_open,'categories_covered',jsonb_array_length(v_in->'categories'),'no_case_executed',true,'safe_behavior_never_pass_or_ready',true,'targets_within_snapshot',true,'input_snapshot_matches_stored_a9_capture',true,
    'producer_mode','GPT_NATIVE','evidence_class',v_tier,
    'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,'criterion_amendment_ref',v_amend_doc||'@'||v_amend_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A11Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A11Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed under the owner-approved GPT Native in-chat tier and the approved criterion amendment (A11 adversarial set produced by GPT with evidence per case); hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A11Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A11Q_C1:DONE,A11Q_C2:DONE,A11Q_C3:PENDING'
 THEN RAISE EXCEPTION 'A11Q_C2_POSTSTATE_FAILED'; END IF;
END $a11q_c2_close$;
COMMIT;
