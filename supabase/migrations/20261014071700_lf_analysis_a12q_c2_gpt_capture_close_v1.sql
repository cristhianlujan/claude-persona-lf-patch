-- A12Q_C2: stores the verified GPT Native capture (data) and then closes the checkpoint under the owner-accepted tier and the approved criterion amendment.
-- Evidence: raw output SHA-256 baa34497205888966654473cb7a14b019f75efa41c1157a4fa014108dc741d3a; every value asserted below is recomputed from the stored capture against the embedded input fixture (no upstream cross-check: the fixture is the A10 cohort frozen in the packet).
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision documents).
BEGIN;
DO $a12q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := '250f2e050ccf0df31c5fc7efe47460fb7e28ef05122f23a531d087676b326a99';
 v_raw_text text := $raw${
  "schema_version": "A12_ARMS_OUTPUT_V1",
  "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
  "arms": {
    "baseline": [
      {
        "case_id": "A10-HIST-001",
        "domains": [
          {
            "domain": "ALCANCE",
            "note": "Dominio incluido obligatoriamente por el método fijo; alcance real no verificado."
          },
          {
            "domain": "DATOS",
            "note": "Dominio incluido por el método fijo; no se aportó evidencia específica de datos."
          },
          {
            "domain": "PERMISOS",
            "note": "Dominio incluido por el método fijo; permisos aplicables no determinados."
          },
          {
            "domain": "ESTADOS",
            "note": "Dominio incluido por el método fijo; estados funcionales no comprobados."
          },
          {
            "domain": "ERRORES",
            "note": "Dominio incluido por el método fijo; comportamientos de error desconocidos."
          },
          {
            "domain": "EFECTOS_COLATERALES",
            "note": "Dominio incluido por el método fijo; efectos colaterales no investigados."
          }
        ],
        "evidence_refs": [
          "lf_eventos://20397",
          "github://cristhianlujan/claude-persona-lf-patch/pull/1800"
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-002",
        "domains": [
          {
            "domain": "ALCANCE",
            "note": "Dominio obligatorio del baseline; objetos de la migración no identificados."
          },
          {
            "domain": "DATOS",
            "note": "Dominio obligatorio del baseline; cambios de datos no acreditados."
          },
          {
            "domain": "PERMISOS",
            "note": "Dominio obligatorio del baseline; permisos de migración no verificados."
          },
          {
            "domain": "ESTADOS",
            "note": "Dominio obligatorio del baseline; estados anterior y posterior desconocidos."
          },
          {
            "domain": "ERRORES",
            "note": "Dominio obligatorio del baseline; errores de migración no investigados."
          },
          {
            "domain": "EFECTOS_COLATERALES",
            "note": "Dominio obligatorio del baseline; impactos secundarios no comprobados."
          }
        ],
        "evidence_refs": [
          "lf_eventos://20356"
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-003",
        "domains": [
          {
            "domain": "ALCANCE",
            "note": "Dominio obligatorio del baseline; alcance del runtime no verificado."
          },
          {
            "domain": "DATOS",
            "note": "Dominio obligatorio del baseline; datos procesados no identificados."
          },
          {
            "domain": "PERMISOS",
            "note": "Dominio obligatorio del baseline; autorizaciones de ejecución desconocidas."
          },
          {
            "domain": "ESTADOS",
            "note": "Dominio obligatorio del baseline; estados de ejecución no acreditados."
          },
          {
            "domain": "ERRORES",
            "note": "Dominio obligatorio del baseline; resultados de error no observados."
          },
          {
            "domain": "EFECTOS_COLATERALES",
            "note": "Dominio obligatorio del baseline; consecuencias indirectas no investigadas."
          }
        ],
        "evidence_refs": [
          "lf_eventos://20357"
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-004",
        "domains": [
          {
            "domain": "ALCANCE",
            "note": "Dominio obligatorio del baseline; operaciones concurrentes no identificadas."
          },
          {
            "domain": "DATOS",
            "note": "Dominio obligatorio del baseline; datos compartidos no acreditados."
          },
          {
            "domain": "PERMISOS",
            "note": "Dominio obligatorio del baseline; permisos pertinentes no comprobados."
          },
          {
            "domain": "ESTADOS",
            "note": "Dominio obligatorio del baseline; transiciones concurrentes desconocidas."
          },
          {
            "domain": "ERRORES",
            "note": "Dominio obligatorio del baseline; comportamiento ante fallos no investigado."
          },
          {
            "domain": "EFECTOS_COLATERALES",
            "note": "Dominio obligatorio del baseline; posibles duplicaciones no verificadas."
          }
        ],
        "evidence_refs": [
          "lf_eventos://20268"
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-005",
        "domains": [
          {
            "domain": "ALCANCE",
            "note": "Dominio obligatorio del baseline; alcance de selección no comprobado."
          },
          {
            "domain": "DATOS",
            "note": "Dominio obligatorio del baseline; entradas de selección no examinadas."
          },
          {
            "domain": "PERMISOS",
            "note": "Dominio obligatorio del baseline; autoridad de selección no acreditada."
          },
          {
            "domain": "ESTADOS",
            "note": "Dominio obligatorio del baseline; estado de candidatos no verificado."
          },
          {
            "domain": "ERRORES",
            "note": "Dominio obligatorio del baseline; fallos de selección no observados."
          },
          {
            "domain": "EFECTOS_COLATERALES",
            "note": "Dominio obligatorio del baseline; impactos de la selección no comprobados."
          }
        ],
        "evidence_refs": [
          "lf_eventos://20373"
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-006",
        "domains": [
          {
            "domain": "ALCANCE",
            "note": "Dominio obligatorio del baseline; pantallas afectadas no verificadas."
          },
          {
            "domain": "DATOS",
            "note": "Dominio obligatorio del baseline; representaciones numéricas no examinadas."
          },
          {
            "domain": "PERMISOS",
            "note": "Dominio obligatorio del baseline; permisos relacionados no acreditados."
          },
          {
            "domain": "ESTADOS",
            "note": "Dominio obligatorio del baseline; estados relacionados no investigados."
          },
          {
            "domain": "ERRORES",
            "note": "Dominio obligatorio del baseline; defectos reales no reproducidos."
          },
          {
            "domain": "EFECTOS_COLATERALES",
            "note": "Dominio obligatorio del baseline; regresiones posibles no verificadas."
          }
        ],
        "evidence_refs": [
          "supabase://programacion.fn_input_v58_assertion_template",
          "supabase://programacion.fn_input_v512_assertion_template",
          "supabase://programacion.fn_input_v58_build_assertions"
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-008",
        "domains": [
          {
            "domain": "ALCANCE",
            "note": "Dominio obligatorio del baseline; límites entre etapas no verificados."
          },
          {
            "domain": "DATOS",
            "note": "Dominio obligatorio del baseline; artefactos intercambiados no examinados."
          },
          {
            "domain": "PERMISOS",
            "note": "Dominio obligatorio del baseline; autoridad aplicable no determinada."
          },
          {
            "domain": "ESTADOS",
            "note": "Dominio obligatorio del baseline; estados de gobernanza no comprobados."
          },
          {
            "domain": "ERRORES",
            "note": "Dominio obligatorio del baseline; incumplimientos reales no acreditados."
          },
          {
            "domain": "EFECTOS_COLATERALES",
            "note": "Dominio obligatorio del baseline; consumidores afectados no identificados."
          }
        ],
        "evidence_refs": [
          "lf_eventos://20335",
          "supabase://programacion.fn_agent_task_execution_bundle",
          "supabase://programacion.fn_test_contract_generation_source"
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      }
    ],
    "candidate": [
      {
        "case_id": "A10-HIST-001",
        "evidence_refs": [
          "lf_eventos://20397",
          "github://cristhianlujan/claude-persona-lf-patch/pull/1800"
        ],
        "fronts": [
          {
            "front": "ESTADO_OBJETIVO",
            "trigger_ref": "lf_eventos://20397",
            "reason": "El asunto menciona un refinamiento del diseño del estado objetivo. Corresponde investigar su alcance, sin afirmar qué contiene el evento."
          },
          {
            "front": "BINDING_CONTRATOS",
            "trigger_ref": "github://cristhianlujan/claude-persona-lf-patch/pull/1800",
            "reason": "El asunto incluye refinamiento de vinculaciones. El PR es una referencia candidata para comprobar contratos y cambios, pero su contenido no fue consultado."
          }
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-002",
        "evidence_refs": [
          "lf_eventos://20356"
        ],
        "fronts": [
          {
            "front": "ALCANCE_MIGRACION",
            "trigger_ref": "lf_eventos://20356",
            "reason": "La familia MIGRATION justifica investigar el alcance y las condiciones de una posible migración. El identificador PASE-ATOM-F09-S02 no permite inferir objetos ni resultados concretos."
          }
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-003",
        "evidence_refs": [
          "lf_eventos://20357"
        ],
        "fronts": [
          {
            "front": "CONTRATO_RUNTIME",
            "trigger_ref": "lf_eventos://20357",
            "reason": "La familia RUNTIME justifica investigar los límites y condiciones de ejecución. El asunto PASE-ATOM-F09-S03 no acredita operaciones específicas ni comportamientos observados."
          }
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-004",
        "evidence_refs": [
          "lf_eventos://20268"
        ],
        "fronts": [
          {
            "front": "CONCURRENCIA",
            "trigger_ref": "lf_eventos://20268",
            "reason": "La familia CONCURRENCY_IDEMPOTENCY justifica investigar la consistencia de operaciones simultáneas, aunque el asunto PAULO-148 no identifica la operación real."
          },
          {
            "front": "IDEMPOTENCIA",
            "trigger_ref": "lf_eventos://20268",
            "reason": "La misma familia justifica revisar las expectativas de repetición y posibles efectos duplicados. No se presume que exista un defecto de idempotencia."
          }
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-005",
        "evidence_refs": [
          "lf_eventos://20373"
        ],
        "fronts": [
          {
            "front": "SELECCION_METODO",
            "trigger_ref": "lf_eventos://20373",
            "reason": "El asunto menciona explícitamente selección de método. Corresponde investigar los criterios y candidatos, sin asumir que fueron aplicados o evaluados."
          },
          {
            "front": "FREEZE_CANDIDATO",
            "trigger_ref": "lf_eventos://20373",
            "reason": "El asunto menciona el congelamiento de un candidato R2. Debe comprobarse qué significa ese congelamiento y su evidencia, sin atribuirle validez automáticamente."
          }
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-006",
        "evidence_refs": [
          "supabase://programacion.fn_input_v58_assertion_template",
          "supabase://programacion.fn_input_v512_assertion_template",
          "supabase://programacion.fn_input_v58_build_assertions"
        ],
        "fronts": [
          {
            "front": "IDENTIDAD_PANTALLA",
            "trigger_ref": "supabase://programacion.fn_input_v58_assertion_template",
            "reason": "El asunto INPUT_GOVERNANCE_NUMERIC_SCREEN_IDENTITY justifica investigar la interpretación de identificadores numéricos. No se ha inspeccionado la función."
          },
          {
            "front": "COHERENCIA_ASSERTIONS",
            "trigger_ref": "supabase://programacion.fn_input_v58_build_assertions",
            "reason": "Las referencias a plantillas y construcción de aserciones justifican investigar su consistencia con la identidad de pantalla. No se afirma ningún fallo comprobado."
          }
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      },
      {
        "case_id": "A10-HIST-008",
        "evidence_refs": [
          "lf_eventos://20335",
          "supabase://programacion.fn_agent_task_execution_bundle",
          "supabase://programacion.fn_test_contract_generation_source"
        ],
        "fronts": [
          {
            "front": "AUTORIDAD_ETAPAS",
            "trigger_ref": "lf_eventos://20335",
            "reason": "El asunto distingue los artefactos de una etapa de la autoridad anterior o superior. Corresponde investigar esa frontera sin presumir una infracción existente."
          },
          {
            "front": "TRASPASO_CONTRATOS",
            "trigger_ref": "supabase://programacion.fn_test_contract_generation_source",
            "reason": "Las referencias a ejecución y generación de contratos justifican investigar cómo se consume la información entre etapas, sin inferir el comportamiento de las funciones."
          }
        ],
        "reinterpretation_required": true,
        "verdict": "NEED_MORE_EVIDENCE"
      }
    ]
  },
  "comparison": {
    "baseline_fixed_domains_per_case": 6,
    "baseline_total_domains": 42,
    "candidate_total_fronts": 12,
    "cases_compared": 7
  },
  "no_ready_claim": true,
  "arms_statement": "Se produjeron ambos brazos para los mismos siete casos históricos. El baseline incluye seis dominios fijos por caso, con 42 asignaciones en total. El candidate contiene 12 frentes hipotéticos derivados de los asuntos, familias y referencias suministradas. Las fuentes no fueron leídas, de modo que ningún frente del candidate está confirmado por el contenido de esas fuentes. Ambos brazos son resultados candidatos, no ejecutados ni medidos. Esta es una comparación estructural de cobertura declarada y cantidad de elementos, no una comparación de rendimiento, calidad, precisión, latencia o superioridad de un método. El menor número de frentes del candidate no demuestra mayor eficiencia ni ausencia de impactos omitidos. No se utilizó un oráculo, no se calcularon métricas de desempeño y ningún caso se declara READY."
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser at capture time (56002 bytes, after the A12Q_C2 reply); the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"4d9f1f2a9e53f545faf165a622756d120eb18f9b74839800379bd5bfcd956c5c","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"9dbc2185a3ba5f9f2b84e6380bdf86d610d0ce88701dbb9394ff98e8bb06fa4b","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"baa34497205888966654473cb7a14b019f75efa41c1157a4fa014108dc741d3a","request_sha256":"bdc14baad8224114b640764f0217d85bc73652e59d70650bd2c70bc614296628","run_id":"A12Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A12","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A12Q/A12Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a12q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_raw jsonb; v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text;
 v_in jsonb;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_raw := v_raw_text::jsonb;

 v_in:=$in${
  "arms": {
    "baseline": "Método de dominios fijos: aplica a cada caso la lista completa de dominios obligatorios, independientemente de la evidencia del caso (salida histórica tipo STORY_PACK).",
    "candidate": "Método de frentes activados por evidencia: solo registra los frentes materiales que una referencia del propio caso permita justificar (salida tipo paquete de análisis)."
  },
  "baseline_fixed_domains": [
    "ALCANCE",
    "DATOS",
    "PERMISOS",
    "ESTADOS",
    "ERRORES",
    "EFECTOS_COLATERALES"
  ],
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
  "schema_version": "A12_ARMS_INPUT_V1"
}
$in$::jsonb;
 IF encode(sha256(convert_to(rtrim($in${
  "arms": {
    "baseline": "Método de dominios fijos: aplica a cada caso la lista completa de dominios obligatorios, independientemente de la evidencia del caso (salida histórica tipo STORY_PACK).",
    "candidate": "Método de frentes activados por evidencia: solo registra los frentes materiales que una referencia del propio caso permita justificar (salida tipo paquete de análisis)."
  },
  "baseline_fixed_domains": [
    "ALCANCE",
    "DATOS",
    "PERMISOS",
    "ESTADOS",
    "ERRORES",
    "EFECTOS_COLATERALES"
  ],
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
  "schema_version": "A12_ARMS_INPUT_V1"
}
$in$,E'\n'),'UTF8')),'hex') <> '9dbc2185a3ba5f9f2b84e6380bdf86d610d0ce88701dbb9394ff98e8bb06fa4b' THEN RAISE EXCEPTION 'A12Q_C2_INPUT_FIXTURE_DRIFT'; END IF;
 IF (v_raw->>'schema_version'='A12_ARMS_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'no_ready_claim'='true' AND jsonb_array_length(v_in->'cases')=7 AND jsonb_array_length(v_in->'baseline_fixed_domains')=6 AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(r->>'case_id' ORDER BY r->>'case_id') FROM jsonb_array_elements(v_raw#>'{arms,baseline}') r) AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(r->>'case_id' ORDER BY r->>'case_id') FROM jsonb_array_elements(v_raw#>'{arms,candidate}') r) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw#>'{arms,baseline}') r WHERE jsonb_array_length(r->'domains')<>6 OR (SELECT array_agg(d->>'domain' ORDER BY d->>'domain') FROM jsonb_array_elements(r->'domains') d) IS DISTINCT FROM (SELECT array_agg(d ORDER BY d) FROM jsonb_array_elements_text(v_in->'baseline_fixed_domains') d) OR r->>'verdict' NOT IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE') OR jsonb_typeof(r->'reinterpretation_required')<>'boolean' OR jsonb_array_length(r->'evidence_refs')<1 OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(r->'evidence_refs') e WHERE NOT ((SELECT c->'source_refs' FROM jsonb_array_elements(v_in->'cases') c WHERE c->>'case_id'=r->>'case_id') ? e))) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw#>'{arms,candidate}') r WHERE jsonb_array_length(r->'fronts')<1 OR r->>'verdict' NOT IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE') OR jsonb_typeof(r->'reinterpretation_required')<>'boolean' OR jsonb_array_length(r->'evidence_refs')<1 OR (SELECT count(DISTINCT f->>'front') FROM jsonb_array_elements(r->'fronts') f)<>jsonb_array_length(r->'fronts') OR EXISTS (SELECT 1 FROM jsonb_array_elements(r->'fronts') f WHERE NOT ((SELECT c->'source_refs' FROM jsonb_array_elements(v_in->'cases') c WHERE c->>'case_id'=r->>'case_id') ? (f->>'trigger_ref'))) OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(r->'evidence_refs') e WHERE NOT ((SELECT c->'source_refs' FROM jsonb_array_elements(v_in->'cases') c WHERE c->>'case_id'=r->>'case_id') ? e))) AND (v_raw#>>'{comparison,cases_compared}')::int=7 AND (v_raw#>>'{comparison,baseline_fixed_domains_per_case}')::int=6 AND (v_raw#>>'{comparison,baseline_total_domains}')::int=(SELECT sum(jsonb_array_length(r->'domains')) FROM jsonb_array_elements(v_raw#>'{arms,baseline}') r) AND (v_raw#>>'{comparison,candidate_total_fronts}')::int=(SELECT sum(jsonb_array_length(r->'fronts')) FROM jsonb_array_elements(v_raw#>'{arms,candidate}') r) AND (SELECT sum(jsonb_array_length(r->'domains')) FROM jsonb_array_elements(v_raw#>'{arms,baseline}') r)=42 AND (SELECT sum(jsonb_array_length(r->'fronts')) FROM jsonb_array_elements(v_raw#>'{arms,candidate}') r)=12) IS NOT TRUE THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1122 AND checkpoint_code='A12Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A12Q' AND work_item_id=1122 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A12Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A12Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A12Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A12Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1122;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A12Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A12Q' AND work_item_id=1122;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A12Q' AND work_item_id=1122;
 IF v_m#>'{gpt_native_captures_v1,A12Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1122;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a12q_c2_cap$;
-- A12Q_C2 closure under the owner-approved GPT Native tier (decision: docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md).
-- A12Q_C2 closure under the owner-approved GPT Native tier (docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md) and the criterion amendment (docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).
DO $a12q_c2_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A12Q';
 v_cp constant text := 'A12Q_C2';
 v_wi constant bigint := 1122;
 v_actor constant text := 'ANALYSIS_QUAL_C2_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_a12q_c2_gpt_native_packet_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '2918579179b97bf3d479a3b3a05bda51a08a05fed456e41270c1a95e710acf53';
 v_amend_doc constant text := 'docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md';
 v_amend_sha constant text := '17d77d4af397a768d65617368cd043e2abc3795fc9f8f523ddfcb4044b8c2109';
 v_packet_sha constant text := '250f2e050ccf0df31c5fc7efe47460fb7e28ef05122f23a531d087676b326a99';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1122 and checkpoint_code=''A12Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_open int; v_pass jsonb; v_amend jsonb;
 v_in jsonb;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A12Q_C2_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A12Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A12Q/A12Q_C2'
 THEN RAISE EXCEPTION 'A12Q_C2_PRESTATE_DRIFT'; END IF;

 -- Recompute the evidence from the stored capture.
 v_cap:=v_m#>'{gpt_native_captures_v1,A12Q_C2}'; v_pk:=v_m#>'{gpt_native_packets_v1,A12Q_C2}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha
    OR v_cap->>'request_sha256' IS DISTINCT FROM v_pk->>'request_sha256'
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A12Q_C2_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'A12Q_C2_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A12Q_C2_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_open:=jsonb_array_length(v_raw#>'{arms,baseline}');
 v_in:=$in${
  "arms": {
    "baseline": "Método de dominios fijos: aplica a cada caso la lista completa de dominios obligatorios, independientemente de la evidencia del caso (salida histórica tipo STORY_PACK).",
    "candidate": "Método de frentes activados por evidencia: solo registra los frentes materiales que una referencia del propio caso permita justificar (salida tipo paquete de análisis)."
  },
  "baseline_fixed_domains": [
    "ALCANCE",
    "DATOS",
    "PERMISOS",
    "ESTADOS",
    "ERRORES",
    "EFECTOS_COLATERALES"
  ],
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
  "schema_version": "A12_ARMS_INPUT_V1"
}
$in$::jsonb;
 IF encode(sha256(convert_to(rtrim($in${
  "arms": {
    "baseline": "Método de dominios fijos: aplica a cada caso la lista completa de dominios obligatorios, independientemente de la evidencia del caso (salida histórica tipo STORY_PACK).",
    "candidate": "Método de frentes activados por evidencia: solo registra los frentes materiales que una referencia del propio caso permita justificar (salida tipo paquete de análisis)."
  },
  "baseline_fixed_domains": [
    "ALCANCE",
    "DATOS",
    "PERMISOS",
    "ESTADOS",
    "ERRORES",
    "EFECTOS_COLATERALES"
  ],
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
  "schema_version": "A12_ARMS_INPUT_V1"
}
$in$,E'\n'),'UTF8')),'hex') <> '9dbc2185a3ba5f9f2b84e6380bdf86d610d0ce88701dbb9394ff98e8bb06fa4b' THEN RAISE EXCEPTION 'A12Q_C2_INPUT_FIXTURE_DRIFT'; END IF;
 IF (v_raw->>'schema_version'='A12_ARMS_OUTPUT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'no_ready_claim'='true' AND jsonb_array_length(v_in->'cases')=7 AND jsonb_array_length(v_in->'baseline_fixed_domains')=6 AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(r->>'case_id' ORDER BY r->>'case_id') FROM jsonb_array_elements(v_raw#>'{arms,baseline}') r) AND (SELECT array_agg(c->>'case_id' ORDER BY c->>'case_id') FROM jsonb_array_elements(v_in->'cases') c)=(SELECT array_agg(r->>'case_id' ORDER BY r->>'case_id') FROM jsonb_array_elements(v_raw#>'{arms,candidate}') r) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw#>'{arms,baseline}') r WHERE jsonb_array_length(r->'domains')<>6 OR (SELECT array_agg(d->>'domain' ORDER BY d->>'domain') FROM jsonb_array_elements(r->'domains') d) IS DISTINCT FROM (SELECT array_agg(d ORDER BY d) FROM jsonb_array_elements_text(v_in->'baseline_fixed_domains') d) OR r->>'verdict' NOT IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE') OR jsonb_typeof(r->'reinterpretation_required')<>'boolean' OR jsonb_array_length(r->'evidence_refs')<1 OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(r->'evidence_refs') e WHERE NOT ((SELECT c->'source_refs' FROM jsonb_array_elements(v_in->'cases') c WHERE c->>'case_id'=r->>'case_id') ? e))) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw#>'{arms,candidate}') r WHERE jsonb_array_length(r->'fronts')<1 OR r->>'verdict' NOT IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE') OR jsonb_typeof(r->'reinterpretation_required')<>'boolean' OR jsonb_array_length(r->'evidence_refs')<1 OR (SELECT count(DISTINCT f->>'front') FROM jsonb_array_elements(r->'fronts') f)<>jsonb_array_length(r->'fronts') OR EXISTS (SELECT 1 FROM jsonb_array_elements(r->'fronts') f WHERE NOT ((SELECT c->'source_refs' FROM jsonb_array_elements(v_in->'cases') c WHERE c->>'case_id'=r->>'case_id') ? (f->>'trigger_ref'))) OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(r->'evidence_refs') e WHERE NOT ((SELECT c->'source_refs' FROM jsonb_array_elements(v_in->'cases') c WHERE c->>'case_id'=r->>'case_id') ? e))) AND (v_raw#>>'{comparison,cases_compared}')::int=7 AND (v_raw#>>'{comparison,baseline_fixed_domains_per_case}')::int=6 AND (v_raw#>>'{comparison,baseline_total_domains}')::int=(SELECT sum(jsonb_array_length(r->'domains')) FROM jsonb_array_elements(v_raw#>'{arms,baseline}') r) AND (v_raw#>>'{comparison,candidate_total_fronts}')::int=(SELECT sum(jsonb_array_length(r->'fronts')) FROM jsonb_array_elements(v_raw#>'{arms,candidate}') r) AND (SELECT sum(jsonb_array_length(r->'domains')) FROM jsonb_array_elements(v_raw#>'{arms,baseline}') r)=42 AND (SELECT sum(jsonb_array_length(r->'fronts')) FROM jsonb_array_elements(v_raw#>'{arms,candidate}') r)=12) IS NOT TRUE
 THEN RAISE EXCEPTION 'A12Q_C2_CONTENT_CHECK_FAILED'; END IF;
 IF length(coalesce(v_cap->>'chat_transcript_ref',''))<10 OR coalesce(v_cap->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'A12Q_C2_CHAT_BINDING_MISSING'; END IF;

 v_amend:=jsonb_build_object('criterion_amended',true,'original','Inferencia real de ambos brazos con latencia y tokens observables','amended','Ambos brazos producidos por GPT; latencia y tokens fuera del criterio','amendment_ref',v_amend_doc||'@'||v_amend_sha,'plan_exit_criterion_modified',false);
 v_pass:=jsonb_build_object('capture_verified',true,'criterion_amendment',v_amend,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,
   'content_checks_passed',true,'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native capture of the A12 two-arm comparison under the owner-approved equivalent tier and the approved criterion amendment, and bind its result',
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
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A12Q_C2_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A12Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A12Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A12Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A12Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/A12Q#unit_metadata.gpt_native_captures_v1.A12Q_C2'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';request_sha256:'||(v_cap->>'request_sha256')
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha||';amendment:'||v_amend_doc||'@'||v_amend_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A12Q_C2_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A12Q_C2_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','request_sha256',v_cap->>'request_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'request_ref',v_raw->>'request_ref','cases_compared',v_open,'baseline_total_domains',(v_raw#>>'{comparison,baseline_total_domains}')::int,'candidate_total_fronts',(v_raw#>>'{comparison,candidate_total_fronts}')::int,'no_ready_claim',true,'refs_within_case_sources',true,'no_latency_tokens_provider_claims',true,
    'producer_mode','GPT_NATIVE','evidence_class',v_tier,
    'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,'criterion_amendment_ref',v_amend_doc||'@'||v_amend_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A12Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A12Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed under the owner-approved GPT Native in-chat tier and the approved criterion amendment (A12 two arms produced by GPT; latency and tokens out of the criterion); hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A12Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A12Q_C1:DONE,A12Q_C2:DONE,A12Q_C3:PENDING'
 THEN RAISE EXCEPTION 'A12Q_C2_POSTSTATE_FAILED'; END IF;
END $a12q_c2_close$;
COMMIT;
