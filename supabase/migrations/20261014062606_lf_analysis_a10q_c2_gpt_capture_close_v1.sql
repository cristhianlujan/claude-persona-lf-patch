-- A10Q_C2: stores the verified GPT Native capture (data) and then closes the checkpoint under the owner-accepted tier and the approved criterion amendment.
-- Evidence: raw output SHA-256 19baaf6a191a373f7f17b6c1bb2d00820d1aa535248560d902a54d08078e18cf; every value asserted below is recomputed from the stored capture and cross-checked against the stored A7/A8 captures.
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision documents).
BEGIN;
DO $a10q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := '8f428ca9c40294eb0efa79fa37313257c7d947358a45e47c4588a45b3292aabd';
 v_raw_text text := $raw${
  "schema_version": "A10_COHORT_OUTPUT_V1",
  "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
  "cohort": [
    {
      "case_id": "A10-HIST-001",
      "change_family": "FEATURE",
      "critical_impacts_observed": [
        {
          "impact": "Posible inconsistencia entre el estado objetivo del agente de programación y los contratos que vinculan sus componentes o capacidades.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible propagación de referencias de diseño incorrectas hacia consumidores posteriores del estado objetivo.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        }
      ],
      "currentness_verdict": "NOT_EVALUATED",
      "duplicate_read_count": 0,
      "evidence_note": "Análisis hipotético basado exclusivamente en el asunto histórico y la familia FEATURE. No se leyó el contenido del evento ni del PR; sus referencias no acreditan resultados, alcance ni vigencia.",
      "evidence_refs": [
        "lf_eventos://20397",
        "github://cristhianlujan/claude-persona-lf-patch/pull/1800"
      ],
      "false_ready_count": 0,
      "handoff_parity_verdict": "NOT_EVALUATED",
      "material_fronts_observed": [
        {
          "front": "CONTRATOS_DE_BINDING",
          "reason": "Determinar qué vinculaciones del estado objetivo se pretendían refinar y cuáles estaban autorizadas."
        },
        {
          "front": "ALCANCE_Y_CONSUMIDORES",
          "reason": "Identificar los elementos afectados y sus consumidores antes de concluir que el refinamiento conserva la coherencia."
        },
        {
          "front": "EVIDENCIA_DE_CAMBIO",
          "reason": "Contrastar el estado anterior, el estado propuesto y las evidencias de aceptación sin presumir su existencia."
        }
      ],
      "reinterpretation_required": true,
      "retry_count": 0,
      "scope_front_consistency_verdict": "NOT_EVALUATED",
      "source_read_count": 0,
      "verdict": "NEED_MORE_EVIDENCE"
    },
    {
      "case_id": "A10-HIST-002",
      "change_family": "MIGRATION",
      "critical_impacts_observed": [
        {
          "impact": "Posible divergencia entre el estado anterior y posterior de una migración, con consecuencias sobre contratos o datos afectados.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible pérdida de coherencia entre autorización, aplicación y evidencia de una operación de migración.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        }
      ],
      "currentness_verdict": "NOT_EVALUATED",
      "duplicate_read_count": 0,
      "evidence_note": "Hipótesis derivadas únicamente de la familia MIGRATION y del identificador PASE-ATOM-F09-S02. No se consultó el evento referenciado y no se conoce su contenido ni el resultado de la operación.",
      "evidence_refs": [
        "lf_eventos://20356"
      ],
      "false_ready_count": 0,
      "handoff_parity_verdict": "NOT_EVALUATED",
      "material_fronts_observed": [
        {
          "front": "ALCANCE_DE_MIGRACION",
          "reason": "Establecer los objetos y contratos potencialmente afectados sin atribuir al identificador un significado no documentado."
        },
        {
          "front": "PARIDAD_DE_ESTADOS",
          "reason": "Verificar si corresponde comparar estados de origen, aplicación y destino con evidencia auténtica."
        },
        {
          "front": "ORDEN_Y_RECUPERACION",
          "reason": "Determinar las dependencias, condiciones de aplicación y recuperación pertinentes antes de evaluar el cierre."
        }
      ],
      "reinterpretation_required": true,
      "retry_count": 0,
      "scope_front_consistency_verdict": "NOT_EVALUATED",
      "source_read_count": 0,
      "verdict": "NEED_MORE_EVIDENCE"
    },
    {
      "case_id": "A10-HIST-003",
      "change_family": "RUNTIME",
      "critical_impacts_observed": [
        {
          "impact": "Posible diferencia entre el comportamiento efectivo de ejecución y el comportamiento permitido por sus contratos.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible propagación de resultados de ejecución sin evidencia suficiente de sus condiciones de entrada y salida.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        }
      ],
      "currentness_verdict": "NOT_EVALUATED",
      "duplicate_read_count": 0,
      "evidence_note": "El análisis parte únicamente del asunto PASE-ATOM-F09-S03 y de la clasificación RUNTIME. No se leyó el evento, por lo que no se afirma ninguna ejecución, fallo o resultado real.",
      "evidence_refs": [
        "lf_eventos://20357"
      ],
      "false_ready_count": 0,
      "handoff_parity_verdict": "NOT_EVALUATED",
      "material_fronts_observed": [
        {
          "front": "LIMITES_DE_EJECUCION",
          "reason": "Determinar qué operaciones puede realizar el runtime y qué restricciones funcionales o de autoridad deben respetarse."
        },
        {
          "front": "ENTRADAS_Y_SALIDAS",
          "reason": "Identificar los contratos de entrada y salida y los consumidores potencialmente afectados."
        },
        {
          "front": "EVIDENCIA_OPERATIVA",
          "reason": "Comprobar qué resultados y condiciones de ejecución están documentados antes de emitir conclusiones."
        }
      ],
      "reinterpretation_required": true,
      "retry_count": 0,
      "scope_front_consistency_verdict": "NOT_EVALUATED",
      "source_read_count": 0,
      "verdict": "NEED_MORE_EVIDENCE"
    },
    {
      "case_id": "A10-HIST-004",
      "change_family": "CONCURRENCY_IDEMPOTENCY",
      "critical_impacts_observed": [
        {
          "impact": "Posible generación de resultados duplicados cuando operaciones equivalentes se ejecutan simultáneamente o se repiten.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible inconsistencia de estado cuando ejecuciones concurrentes compiten por una misma operación lógica.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible comportamiento distinto entre una ejecución inicial y su reintento sobre el mismo objetivo.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        }
      ],
      "currentness_verdict": "NOT_EVALUATED",
      "duplicate_read_count": 0,
      "evidence_note": "Las hipótesis proceden de la familia CONCURRENCY_IDEMPOTENCY, no de evidencia obtenida sobre PAULO-148. El evento no fue leído y no se conoce la operación concreta ni su comportamiento.",
      "evidence_refs": [
        "lf_eventos://20268"
      ],
      "false_ready_count": 0,
      "handoff_parity_verdict": "NOT_EVALUATED",
      "material_fronts_observed": [
        {
          "front": "IDENTIDAD_DE_OPERACION",
          "reason": "Determinar cuándo dos solicitudes representan la misma operación lógica y qué resultado debería conservarse."
        },
        {
          "front": "CONSISTENCIA_CONCURRENTE",
          "reason": "Identificar las invariantes funcionales que no deben romperse ante operaciones simultáneas."
        },
        {
          "front": "REINTENTOS_Y_RESULTADOS",
          "reason": "Examinar las expectativas de repetición, recuperación y ausencia de efectos duplicados."
        }
      ],
      "reinterpretation_required": true,
      "retry_count": 0,
      "scope_front_consistency_verdict": "NOT_EVALUATED",
      "source_read_count": 0,
      "verdict": "NEED_MORE_EVIDENCE"
    },
    {
      "case_id": "A10-HIST-005",
      "change_family": "MODEL_OR_INTELLIGENCE",
      "critical_impacts_observed": [
        {
          "impact": "Posible selección de métodos o candidatos que no correspondan con las condiciones y restricciones del trabajo analizado.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible pérdida de trazabilidad entre la selección realizada y el conjunto de candidatos considerado congelado.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible utilización de criterios de selección insuficientemente justificados frente a alternativas relevantes.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        }
      ],
      "currentness_verdict": "NOT_EVALUATED",
      "duplicate_read_count": 0,
      "evidence_note": "Análisis candidato basado en el nombre PROGRAMMING_AGENT_WAVE2_SELECTION_METHOD_CANDIDATE_FREEZE_R2. No se leyó la fuente ni se verificaron criterios, candidatos o resultados.",
      "evidence_refs": [
        "lf_eventos://20373"
      ],
      "false_ready_count": 0,
      "handoff_parity_verdict": "NOT_EVALUATED",
      "material_fronts_observed": [
        {
          "front": "CRITERIOS_DE_SELECCION",
          "reason": "Identificar las condiciones y restricciones que deberían justificar la elección de un método o candidato."
        },
        {
          "front": "INTEGRIDAD_DE_CANDIDATOS",
          "reason": "Determinar el significado y alcance del congelamiento mencionado sin asumir que fue ejecutado correctamente."
        },
        {
          "front": "EVALUACION_COMPARATIVA",
          "reason": "Establecer qué evidencia sería necesaria para comparar la pertinencia de alternativas sin inventar resultados."
        }
      ],
      "reinterpretation_required": true,
      "retry_count": 0,
      "scope_front_consistency_verdict": "NOT_EVALUATED",
      "source_read_count": 0,
      "verdict": "NEED_MORE_EVIDENCE"
    },
    {
      "case_id": "A10-HIST-006",
      "change_family": "BUG",
      "critical_impacts_observed": [
        {
          "impact": "Posible identificación incorrecta de pantallas cuando sus identificadores numéricos se interpretan de manera inconsistente.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible asociación de aserciones o resultados de validación con una pantalla distinta de la pretendida.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posibles resultados de validación incorrectos ante representaciones ambiguas de la identidad de pantalla.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        }
      ],
      "currentness_verdict": "NOT_EVALUATED",
      "duplicate_read_count": 0,
      "evidence_note": "Hipótesis formuladas a partir del asunto INPUT_GOVERNANCE_NUMERIC_SCREEN_IDENTITY. No se consultó ninguna de las tres funciones referenciadas ni se comprobó que contengan el defecto supuesto.",
      "evidence_refs": [
        "supabase://programacion.fn_input_v58_assertion_template",
        "supabase://programacion.fn_input_v512_assertion_template",
        "supabase://programacion.fn_input_v58_build_assertions"
      ],
      "false_ready_count": 0,
      "handoff_parity_verdict": "NOT_EVALUATED",
      "material_fronts_observed": [
        {
          "front": "IDENTIDAD_CANONICA",
          "reason": "Determinar qué constituye una identidad válida de pantalla y cómo deben interpretarse sus representaciones numéricas."
        },
        {
          "front": "COHERENCIA_DE_ASERCIONES",
          "reason": "Examinar si las obligaciones y resultados de validación corresponden al objeto correcto."
        },
        {
          "front": "ALCANCE_DE_REGRESION",
          "reason": "Identificar las familias de casos que podrían verse afectadas y los comportamientos que requieren verificación."
        }
      ],
      "reinterpretation_required": true,
      "retry_count": 0,
      "scope_front_consistency_verdict": "NOT_EVALUATED",
      "source_read_count": 0,
      "verdict": "NEED_MORE_EVIDENCE"
    },
    {
      "case_id": "A10-HIST-008",
      "change_family": "GOVERNANCE",
      "critical_impacts_observed": [
        {
          "impact": "Posible atribución incorrecta de autoridad a un artefacto anterior que únicamente pertenece a una etapa delimitada.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible contaminación de decisiones o contratos posteriores mediante evidencia cuya autoridad no corresponde a la etapa consumidora.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        },
        {
          "impact": "Posible cierre de obligaciones basándose en referencias históricas que no acreditan autorización vigente.",
          "basis": "HYPOTHESIS_FROM_SUBJECT"
        }
      ],
      "currentness_verdict": "NOT_EVALUATED",
      "duplicate_read_count": 0,
      "evidence_note": "Análisis hipotético derivado del asunto STAGE_BOUND_PRIOR_ART_NOT_UPSTREAM_AUTHORITY. No se leyeron el evento ni las funciones y no se afirma una infracción comprobada.",
      "evidence_refs": [
        "lf_eventos://20335",
        "supabase://programacion.fn_agent_task_execution_bundle",
        "supabase://programacion.fn_test_contract_generation_source"
      ],
      "false_ready_count": 0,
      "handoff_parity_verdict": "NOT_EVALUATED",
      "material_fronts_observed": [
        {
          "front": "LIMITES_DE_AUTORIDAD",
          "reason": "Distinguir la evidencia válida de una etapa de las fuentes que pueden gobernar legítimamente otra etapa."
        },
        {
          "front": "TRAZABILIDAD_ENTRE_ETAPAS",
          "reason": "Determinar qué artefactos pueden transmitirse entre etapas y bajo qué condiciones mantienen su significado."
        },
        {
          "front": "ADMISION_DE_EVIDENCIA",
          "reason": "Verificar qué referencias son suficientes para respaldar decisiones y cierres sin promover antecedentes a autoridad."
        }
      ],
      "reinterpretation_required": true,
      "retry_count": 0,
      "scope_front_consistency_verdict": "NOT_EVALUATED",
      "source_read_count": 0,
      "verdict": "NEED_MORE_EVIDENCE"
    }
  ],
  "families_covered": [
    "BUG",
    "CONCURRENCY_IDEMPOTENCY",
    "FEATURE",
    "GOVERNANCE",
    "MIGRATION",
    "MODEL_OR_INTELLIGENCE",
    "RUNTIME"
  ],
  "no_ready_claim": true,
  "cohort_statement": "Resultado candidato de siete casos históricos y siete familias distintas. Los impactos y frentes registrados son hipótesis derivadas únicamente de los asuntos y las familias suministradas; no constituyen hallazgos observados en las fuentes. No se leyó ninguna fuente de los casos ni se evaluaron vigencia, paridad de traspaso o consistencia real entre scopes y frentes. Ningún caso se declara READY. La cohorte no ha sido medida contra un oráculo, no demuestra mejoras de calidad ni acredita el cierre de los casos históricos. Todos requieren evidencia adicional antes de cualquier conclusión definitiva."
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser at capture time (44453 bytes, after the A10Q_C2 reply); the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"f53ef62c107a6edc83c7487bea0ab0731d71211b8a5f02bc309b6dfaac24e0fa","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"2f61c8a1e4bf2253108230f1d5ab5775f1ad67fbbacb9f2066d6747735360e6a","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"19baaf6a191a373f7f17b6c1bb2d00820d1aa535248560d902a54d08078e18cf","request_sha256":"2fa0b2bee4ce729bc98896f3d8bb549083badf617cf99d0a8cff9530d499293b","run_id":"A10Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A10","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A10Q/A10Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a10q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_raw jsonb; v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text;
 v_in jsonb;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_raw := v_raw_text::jsonb;

 v_in:=$in${
  "cases": [
    {
      "case_id": "A10-HIST-001",
      "change_family": "FEATURE",
      "historical_subject": "PROGRAMMING_AGENT_TARGET_STATE_DESIGN_BINDING_REFINEMENT_V1",
      "source_refs": [
        "lf_eventos://20397",
        "github://cristhianlujan/claude-persona-lf-patch/pull/1800"
      ]
    },
    {
      "case_id": "A10-HIST-002",
      "change_family": "MIGRATION",
      "historical_subject": "PASE-ATOM-F09-S02",
      "source_refs": [
        "lf_eventos://20356"
      ]
    },
    {
      "case_id": "A10-HIST-003",
      "change_family": "RUNTIME",
      "historical_subject": "PASE-ATOM-F09-S03",
      "source_refs": [
        "lf_eventos://20357"
      ]
    },
    {
      "case_id": "A10-HIST-004",
      "change_family": "CONCURRENCY_IDEMPOTENCY",
      "historical_subject": "PAULO-148",
      "source_refs": [
        "lf_eventos://20268"
      ]
    },
    {
      "case_id": "A10-HIST-005",
      "change_family": "MODEL_OR_INTELLIGENCE",
      "historical_subject": "PROGRAMMING_AGENT_WAVE2_SELECTION_METHOD_CANDIDATE_FREEZE_R2",
      "source_refs": [
        "lf_eventos://20373"
      ]
    },
    {
      "case_id": "A10-HIST-006",
      "change_family": "BUG",
      "historical_subject": "INPUT_GOVERNANCE_NUMERIC_SCREEN_IDENTITY",
      "source_refs": [
        "supabase://programacion.fn_input_v58_assertion_template",
        "supabase://programacion.fn_input_v512_assertion_template",
        "supabase://programacion.fn_input_v58_build_assertions"
      ]
    },
    {
      "case_id": "A10-HIST-008",
      "change_family": "GOVERNANCE",
      "historical_subject": "STAGE_BOUND_PRIOR_ART_NOT_UPSTREAM_AUTHORITY",
      "source_refs": [
        "lf_eventos://20335",
        "supabase://programacion.fn_agent_task_execution_bundle",
        "supabase://programacion.fn_test_contract_generation_source"
      ]
    }
  ],
  "schema_version": "A10_COHORT_INPUT_V1"
}
$in$::jsonb;
 IF encode(sha256(convert_to(rtrim($in${
  "cases": [
    {
      "case_id": "A10-HIST-001",
      "change_family": "FEATURE",
      "historical_subject": "PROGRAMMING_AGENT_TARGET_STATE_DESIGN_BINDING_REFINEMENT_V1",
      "source_refs": [
        "lf_eventos://20397",
        "github://cristhianlujan/claude-persona-lf-patch/pull/1800"
      ]
    },
    {
      "case_id": "A10-HIST-002",
      "change_family": "MIGRATION",
      "historical_subject": "PASE-ATOM-F09-S02",
      "source_refs": [
        "lf_eventos://20356"
      ]
    },
    {
      "case_id": "A10-HIST-003",
      "change_family": "RUNTIME",
      "historical_subject": "PASE-ATOM-F09-S03",
      "source_refs": [
        "lf_eventos://20357"
      ]
    },
    {
      "case_id": "A10-HIST-004",
      "change_family": "CONCURRENCY_IDEMPOTENCY",
      "historical_subject": "PAULO-148",
      "source_refs": [
        "lf_eventos://20268"
      ]
    },
    {
      "case_id": "A10-HIST-005",
      "change_family": "MODEL_OR_INTELLIGENCE",
      "historical_subject": "PROGRAMMING_AGENT_WAVE2_SELECTION_METHOD_CANDIDATE_FREEZE_R2",
      "source_refs": [
        "lf_eventos://20373"
      ]
    },
    {
      "case_id": "A10-HIST-006",
      "change_family": "BUG",
      "historical_subject": "INPUT_GOVERNANCE_NUMERIC_SCREEN_IDENTITY",
      "source_refs": [
        "supabase://programacion.fn_input_v58_assertion_template",
        "supabase://programacion.fn_input_v512_assertion_template",
        "supabase://programacion.fn_input_v58_build_assertions"
      ]
    },
    {
      "case_id": "A10-HIST-008",
      "change_family": "GOVERNANCE",
      "historical_subject": "STAGE_BOUND_PRIOR_ART_NOT_UPSTREAM_AUTHORITY",
      "source_refs": [
        "lf_eventos://20335",
        "supabase://programacion.fn_agent_task_execution_bundle",
        "supabase://programacion.fn_test_contract_generation_source"
      ]
    }
  ],
  "schema_version": "A10_COHORT_INPUT_V1"
}
$in$,E'\n'),'UTF8')),'hex') <> '2f61c8a1e4bf2253108230f1d5ab5775f1ad67fbbacb9f2066d6747735360e6a' THEN RAISE EXCEPTION 'A10Q_C2_INPUT_FIXTURE_DRIFT'; END IF;
 IF (v_raw->>'schema_version'='A10_COHORT_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'no_ready_claim'='true' AND jsonb_array_length(v_raw->'cohort')=jsonb_array_length(v_in->'cases') AND jsonb_array_length(v_in->'cases')=7 AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(r->>'case_id' ORDER BY r->>'case_id') FROM jsonb_array_elements(v_raw->'cohort') r) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'cohort') r WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_in->'cases') c WHERE c->>'case_id'=r->>'case_id' AND c->>'change_family'=r->>'change_family' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(r->'evidence_refs') e WHERE NOT (c->'source_refs') ? e) AND jsonb_array_length(r->'evidence_refs')>=1)) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'cohort') r WHERE r->>'verdict' NOT IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE') OR (r->>'false_ready_count')<>'0' OR r->>'handoff_parity_verdict'<>'NOT_EVALUATED' OR r->>'scope_front_consistency_verdict'<>'NOT_EVALUATED' OR r->>'currentness_verdict'<>'NOT_EVALUATED' OR (r->>'source_read_count')<>'0' OR (r->>'duplicate_read_count')<>'0' OR (r->>'retry_count')<>'0' OR jsonb_array_length(r->'critical_impacts_observed')<1 OR jsonb_array_length(r->'material_fronts_observed')<1 OR EXISTS (SELECT 1 FROM jsonb_array_elements(r->'critical_impacts_observed') i WHERE i->>'basis'<>'HYPOTHESIS_FROM_SUBJECT')) AND (SELECT count(DISTINCT c->>'change_family') FROM jsonb_array_elements(v_in->'cases') c)=7 AND v_raw->'families_covered'=(SELECT jsonb_agg(f ORDER BY f) FROM (SELECT DISTINCT c->>'change_family' f FROM jsonb_array_elements(v_in->'cases') c) q)) IS NOT TRUE THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1120 AND checkpoint_code='A10Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A10Q' AND work_item_id=1120 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A10Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A10Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A10Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A10Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1120;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A10Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A10Q' AND work_item_id=1120;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A10Q' AND work_item_id=1120;
 IF v_m#>'{gpt_native_captures_v1,A10Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1120;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a10q_c2_cap$;
-- A10Q_C2 closure under the owner-approved GPT Native tier (decision: docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md).
-- A10Q_C2 closure under the owner-approved GPT Native tier (docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md) and the criterion amendment (docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).
DO $a10q_c2_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A10Q';
 v_cp constant text := 'A10Q_C2';
 v_wi constant bigint := 1120;
 v_actor constant text := 'ANALYSIS_QUAL_C2_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_a10q_c2_gpt_native_packet_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '2918579179b97bf3d479a3b3a05bda51a08a05fed456e41270c1a95e710acf53';
 v_amend_doc constant text := 'docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md';
 v_amend_sha constant text := '17d77d4af397a768d65617368cd043e2abc3795fc9f8f523ddfcb4044b8c2109';
 v_packet_sha constant text := '8f428ca9c40294eb0efa79fa37313257c7d947358a45e47c4588a45b3292aabd';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1120 and checkpoint_code=''A10Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_open int; v_pass jsonb; v_amend jsonb;
 v_in jsonb;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A10Q_C2_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A10Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A10Q/A10Q_C2'
 THEN RAISE EXCEPTION 'A10Q_C2_PRESTATE_DRIFT'; END IF;

 -- Recompute the evidence from the stored capture.
 v_cap:=v_m#>'{gpt_native_captures_v1,A10Q_C2}'; v_pk:=v_m#>'{gpt_native_packets_v1,A10Q_C2}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha
    OR v_cap->>'request_sha256' IS DISTINCT FROM v_pk->>'request_sha256'
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A10Q_C2_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'A10Q_C2_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A10Q_C2_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_open:=jsonb_array_length(v_raw->'cohort');
 v_in:=$in${
  "cases": [
    {
      "case_id": "A10-HIST-001",
      "change_family": "FEATURE",
      "historical_subject": "PROGRAMMING_AGENT_TARGET_STATE_DESIGN_BINDING_REFINEMENT_V1",
      "source_refs": [
        "lf_eventos://20397",
        "github://cristhianlujan/claude-persona-lf-patch/pull/1800"
      ]
    },
    {
      "case_id": "A10-HIST-002",
      "change_family": "MIGRATION",
      "historical_subject": "PASE-ATOM-F09-S02",
      "source_refs": [
        "lf_eventos://20356"
      ]
    },
    {
      "case_id": "A10-HIST-003",
      "change_family": "RUNTIME",
      "historical_subject": "PASE-ATOM-F09-S03",
      "source_refs": [
        "lf_eventos://20357"
      ]
    },
    {
      "case_id": "A10-HIST-004",
      "change_family": "CONCURRENCY_IDEMPOTENCY",
      "historical_subject": "PAULO-148",
      "source_refs": [
        "lf_eventos://20268"
      ]
    },
    {
      "case_id": "A10-HIST-005",
      "change_family": "MODEL_OR_INTELLIGENCE",
      "historical_subject": "PROGRAMMING_AGENT_WAVE2_SELECTION_METHOD_CANDIDATE_FREEZE_R2",
      "source_refs": [
        "lf_eventos://20373"
      ]
    },
    {
      "case_id": "A10-HIST-006",
      "change_family": "BUG",
      "historical_subject": "INPUT_GOVERNANCE_NUMERIC_SCREEN_IDENTITY",
      "source_refs": [
        "supabase://programacion.fn_input_v58_assertion_template",
        "supabase://programacion.fn_input_v512_assertion_template",
        "supabase://programacion.fn_input_v58_build_assertions"
      ]
    },
    {
      "case_id": "A10-HIST-008",
      "change_family": "GOVERNANCE",
      "historical_subject": "STAGE_BOUND_PRIOR_ART_NOT_UPSTREAM_AUTHORITY",
      "source_refs": [
        "lf_eventos://20335",
        "supabase://programacion.fn_agent_task_execution_bundle",
        "supabase://programacion.fn_test_contract_generation_source"
      ]
    }
  ],
  "schema_version": "A10_COHORT_INPUT_V1"
}
$in$::jsonb;
 IF encode(sha256(convert_to(rtrim($in${
  "cases": [
    {
      "case_id": "A10-HIST-001",
      "change_family": "FEATURE",
      "historical_subject": "PROGRAMMING_AGENT_TARGET_STATE_DESIGN_BINDING_REFINEMENT_V1",
      "source_refs": [
        "lf_eventos://20397",
        "github://cristhianlujan/claude-persona-lf-patch/pull/1800"
      ]
    },
    {
      "case_id": "A10-HIST-002",
      "change_family": "MIGRATION",
      "historical_subject": "PASE-ATOM-F09-S02",
      "source_refs": [
        "lf_eventos://20356"
      ]
    },
    {
      "case_id": "A10-HIST-003",
      "change_family": "RUNTIME",
      "historical_subject": "PASE-ATOM-F09-S03",
      "source_refs": [
        "lf_eventos://20357"
      ]
    },
    {
      "case_id": "A10-HIST-004",
      "change_family": "CONCURRENCY_IDEMPOTENCY",
      "historical_subject": "PAULO-148",
      "source_refs": [
        "lf_eventos://20268"
      ]
    },
    {
      "case_id": "A10-HIST-005",
      "change_family": "MODEL_OR_INTELLIGENCE",
      "historical_subject": "PROGRAMMING_AGENT_WAVE2_SELECTION_METHOD_CANDIDATE_FREEZE_R2",
      "source_refs": [
        "lf_eventos://20373"
      ]
    },
    {
      "case_id": "A10-HIST-006",
      "change_family": "BUG",
      "historical_subject": "INPUT_GOVERNANCE_NUMERIC_SCREEN_IDENTITY",
      "source_refs": [
        "supabase://programacion.fn_input_v58_assertion_template",
        "supabase://programacion.fn_input_v512_assertion_template",
        "supabase://programacion.fn_input_v58_build_assertions"
      ]
    },
    {
      "case_id": "A10-HIST-008",
      "change_family": "GOVERNANCE",
      "historical_subject": "STAGE_BOUND_PRIOR_ART_NOT_UPSTREAM_AUTHORITY",
      "source_refs": [
        "lf_eventos://20335",
        "supabase://programacion.fn_agent_task_execution_bundle",
        "supabase://programacion.fn_test_contract_generation_source"
      ]
    }
  ],
  "schema_version": "A10_COHORT_INPUT_V1"
}
$in$,E'\n'),'UTF8')),'hex') <> '2f61c8a1e4bf2253108230f1d5ab5775f1ad67fbbacb9f2066d6747735360e6a' THEN RAISE EXCEPTION 'A10Q_C2_INPUT_FIXTURE_DRIFT'; END IF;
 IF (v_raw->>'schema_version'='A10_COHORT_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'no_ready_claim'='true' AND jsonb_array_length(v_raw->'cohort')=jsonb_array_length(v_in->'cases') AND jsonb_array_length(v_in->'cases')=7 AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(r->>'case_id' ORDER BY r->>'case_id') FROM jsonb_array_elements(v_raw->'cohort') r) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'cohort') r WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_in->'cases') c WHERE c->>'case_id'=r->>'case_id' AND c->>'change_family'=r->>'change_family' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(r->'evidence_refs') e WHERE NOT (c->'source_refs') ? e) AND jsonb_array_length(r->'evidence_refs')>=1)) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'cohort') r WHERE r->>'verdict' NOT IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE') OR (r->>'false_ready_count')<>'0' OR r->>'handoff_parity_verdict'<>'NOT_EVALUATED' OR r->>'scope_front_consistency_verdict'<>'NOT_EVALUATED' OR r->>'currentness_verdict'<>'NOT_EVALUATED' OR (r->>'source_read_count')<>'0' OR (r->>'duplicate_read_count')<>'0' OR (r->>'retry_count')<>'0' OR jsonb_array_length(r->'critical_impacts_observed')<1 OR jsonb_array_length(r->'material_fronts_observed')<1 OR EXISTS (SELECT 1 FROM jsonb_array_elements(r->'critical_impacts_observed') i WHERE i->>'basis'<>'HYPOTHESIS_FROM_SUBJECT')) AND (SELECT count(DISTINCT c->>'change_family') FROM jsonb_array_elements(v_in->'cases') c)=7 AND v_raw->'families_covered'=(SELECT jsonb_agg(f ORDER BY f) FROM (SELECT DISTINCT c->>'change_family' f FROM jsonb_array_elements(v_in->'cases') c) q)) IS NOT TRUE
 THEN RAISE EXCEPTION 'A10Q_C2_CONTENT_CHECK_FAILED'; END IF;
 IF length(coalesce(v_cap->>'chat_transcript_ref',''))<10 OR coalesce(v_cap->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'A10Q_C2_CHAT_BINDING_MISSING'; END IF;

 v_amend:=jsonb_build_object('criterion_amended',true,'original','Ejecuciones reales heterogéneas con evidencias por caso','amended','Casos heterogéneos producidos por GPT con evidencia por caso','amendment_ref',v_amend_doc||'@'||v_amend_sha,'plan_exit_criterion_modified',false);
 v_pass:=jsonb_build_object('capture_verified',true,'criterion_amendment',v_amend,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,
   'content_checks_passed',true,'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native capture of the A10 heterogeneous cohort under the owner-approved equivalent tier and the approved criterion amendment, and bind its result',
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
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A10Q_C2_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A10Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A10Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A10Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A10Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/A10Q#unit_metadata.gpt_native_captures_v1.A10Q_C2'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';request_sha256:'||(v_cap->>'request_sha256')
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha||';amendment:'||v_amend_doc||'@'||v_amend_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A10Q_C2_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A10Q_C2_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','request_sha256',v_cap->>'request_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'request_ref',v_raw->>'request_ref','cases_in_cohort',v_open,'families_covered',jsonb_array_length(v_raw->'families_covered'),'no_case_ready',true,'impacts_tagged_hypothesis',true,'evidence_refs_within_case_sources',true,'unmeasured_dimensions_not_claimed',true,
    'producer_mode','GPT_NATIVE','evidence_class',v_tier,
    'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,'criterion_amendment_ref',v_amend_doc||'@'||v_amend_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A10Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A10Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed under the owner-approved GPT Native in-chat tier and the approved criterion amendment (A10 cohort produced by GPT with evidence per case); hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A10Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A10Q_C1:DONE,A10Q_C2:DONE,A10Q_C3:PENDING'
 THEN RAISE EXCEPTION 'A10Q_C2_POSTSTATE_FAILED'; END IF;
END $a10q_c2_close$;
COMMIT;
