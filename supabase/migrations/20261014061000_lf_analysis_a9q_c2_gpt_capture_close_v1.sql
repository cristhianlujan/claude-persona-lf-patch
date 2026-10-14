-- A9Q_C2: stores the verified GPT Native capture (data) and then closes the checkpoint under the owner-accepted tier and the approved criterion amendment.
-- Evidence: raw output SHA-256 c7bc45fdc546d263ed34754d1780073d7ffcef44c16f0b85440990ebc530d513; every value asserted below is recomputed from the stored capture and cross-checked against the stored A7/A8 captures.
-- Limits: provider_attested=false, real_execution_receipt=false, independent_review=false (see the decision documents).
BEGIN;
DO $a9q_c2_cap$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_packet_sha constant text := '1b61735e4eed41a44f61f7d1f36ecbcf7e3683ca8b9ec3d871c3762897da7080';
 v_raw_text text := $raw${
  "schema_version": "PROGRAMMING_CONTEXT_SNAPSHOT_V1",
  "request_ref": "REQ-LF-A1Q-C2-PILOT-0001",
  "candidate_only": true,
  "research_decision": "REQUIRES_DECISION",
  "scope_readiness": [
    {
      "scope_id": "A6-REQ-001",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-001"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-001", "A5-DEC-003"]
    },
    {
      "scope_id": "A6-REQ-002",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-002"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-002", "A5-DEC-004"]
    },
    {
      "scope_id": "A6-REQ-003",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-003"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-003"]
    },
    {
      "scope_id": "A6-REQ-004",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-002"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-002", "A5-DEC-004"]
    },
    {
      "scope_id": "A6-REQ-005",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-005"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-004", "A5-DEC-005"]
    },
    {
      "scope_id": "dimension:functional",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-001"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-001", "A5-DEC-003"]
    },
    {
      "scope_id": "dimension:data",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-002"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-002", "A5-DEC-004"]
    },
    {
      "scope_id": "dimension:permissions",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-001"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-001", "A5-DEC-003"]
    },
    {
      "scope_id": "dimension:state",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-003"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-003"]
    },
    {
      "scope_id": "dimension:errors",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-004"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-002", "A5-DEC-003", "A5-DEC-004"]
    },
    {
      "scope_id": "dimension:side_effects",
      "status": "BLOCKED",
      "material_front_refs": ["A7-FRONT-004"],
      "depends_on_scope_ids": [],
      "blockers": ["A5-DEC-002", "A5-DEC-003", "A5-DEC-004"]
    }
  ],
  "material_front_coverage": {
    "all_material_fronts_accounted": true,
    "material_fronts": [
      {
        "front_id": "A7-FRONT-001",
        "front_kind": "ALCANCE_Y_PERMISOS",
        "status": "REQUIRED",
        "closure": "BLOCKED",
        "source_signal_refs": [
          "A6-REQ-001",
          "dimension:functional",
          "dimension:permissions",
          "decision:A5-DEC-001",
          "decision:A5-DEC-003",
          "gap:TARGET_AUTHORITY_NOT_SUPPLIED"
        ],
        "scope_refs": [
          "A6-REQ-001",
          "dimension:functional",
          "dimension:permissions"
        ],
        "authority_refs": [],
        "evidence_refs": [
          "A6-REQ-001",
          "dimension:functional",
          "dimension:permissions",
          "decision:A5-DEC-001",
          "decision:A5-DEC-003"
        ],
        "currentness_refs": [],
        "blockers": ["A5-DEC-001", "A5-DEC-003"],
        "reason": "El alcance funcional del piloto, los destinatarios, las condiciones previas a la aceptación y los permisos aplicables carecen de definición y autoridad verificadas. Las decisiones A5-DEC-001 y A5-DEC-003 permanecen pendientes. No existe evidencia que autorice cerrar este frente."
      },
      {
        "front_id": "A7-FRONT-002",
        "front_kind": "SEMANTICA_ECONOMICA",
        "status": "REQUIRED",
        "closure": "BLOCKED",
        "source_signal_refs": [
          "A6-REQ-002",
          "A6-REQ-004",
          "dimension:data",
          "gap:SAVINGS_SEMANTICS_UNRESOLVED",
          "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
        ],
        "scope_refs": [
          "A6-REQ-002",
          "A6-REQ-004",
          "dimension:data"
        ],
        "authority_refs": [],
        "evidence_refs": [
          "A6-REQ-002",
          "A6-REQ-004",
          "dimension:data",
          "decision:A5-DEC-002",
          "decision:A5-DEC-004",
          "gap:SAVINGS_SEMANTICS_UNRESOLVED",
          "gap:INSTALLMENT_DISTINCTION_UNRESOLVED"
        ],
        "currentness_refs": [],
        "blockers": ["A5-DEC-002", "A5-DEC-004"],
        "reason": "La definición del ahorro, su base de comparación y su distinción respecto del monto de la cuota no están autorizadas. Las decisiones A5-DEC-002 y A5-DEC-004 permanecen pendientes. No se pueden establecer valores, reglas económicas definitivas ni cierre del frente."
      },
      {
        "front_id": "A7-FRONT-003",
        "front_kind": "MOMENTO_Y_ESTADO_OFERTA",
        "status": "REQUIRED",
        "closure": "BLOCKED",
        "source_signal_refs": [
          "A6-REQ-003",
          "dimension:state",
          "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
        ],
        "scope_refs": [
          "A6-REQ-003",
          "dimension:state"
        ],
        "authority_refs": [],
        "evidence_refs": [
          "A6-REQ-003",
          "dimension:state",
          "decision:A5-DEC-003",
          "gap:OFFER_ACCEPTANCE_BOUNDARY_UNRESOLVED"
        ],
        "currentness_refs": [],
        "blockers": ["A5-DEC-003"],
        "reason": "No están acreditados los estados de la oferta, sus transiciones ni las condiciones para comunicar el ahorro antes de la aceptación. A5-DEC-003 permanece pendiente y no se pueden inferir estados o transiciones."
      },
      {
        "front_id": "A7-FRONT-004",
        "front_kind": "ERRORES_Y_EFECTOS",
        "status": "REQUIRED",
        "closure": "BLOCKED",
        "source_signal_refs": [
          "dimension:errors",
          "dimension:side_effects",
          "decision:A5-DEC-002",
          "decision:A5-DEC-003",
          "decision:A5-DEC-004"
        ],
        "scope_refs": [
          "dimension:errors",
          "dimension:side_effects"
        ],
        "authority_refs": [],
        "evidence_refs": [
          "dimension:errors",
          "dimension:side_effects",
          "decision:A5-DEC-002",
          "decision:A5-DEC-003",
          "decision:A5-DEC-004"
        ],
        "currentness_refs": [],
        "blockers": [
          "A5-DEC-002",
          "A5-DEC-003",
          "A5-DEC-004"
        ],
        "reason": "Los comportamientos ante información económica no disponible, indeterminada o incompatible con una oferta, así como los posibles efectos colaterales, permanecen sin determinación autorizada. No se afirma su existencia ni su ausencia. Las tres decisiones relacionadas siguen pendientes."
      },
      {
        "front_id": "A7-FRONT-005",
        "front_kind": "CRITERIOS_COMPRENSION",
        "status": "REQUIRED",
        "closure": "BLOCKED",
        "source_signal_refs": [
          "A6-REQ-005",
          "gap:ACCEPTANCE_EVIDENCE_MISSING",
          "decision:A5-DEC-004",
          "decision:A5-DEC-005"
        ],
        "scope_refs": ["A6-REQ-005"],
        "authority_refs": [],
        "evidence_refs": [
          "A6-REQ-005",
          "decision:A5-DEC-004",
          "decision:A5-DEC-005",
          "gap:ACCEPTANCE_EVIDENCE_MISSING"
        ],
        "currentness_refs": [],
        "blockers": ["A5-DEC-004", "A5-DEC-005"],
        "reason": "Faltan criterios autorizados para verificar que los clientes comprenden el ahorro y lo distinguen de la cuota durante el piloto. No existen umbrales o resultados verificables suministrados. Las decisiones A5-DEC-004 y A5-DEC-005 permanecen pendientes."
      }
    ],
    "front_candidate_refs": [
      "A7-FRONT-001",
      "A7-FRONT-002",
      "A7-FRONT-003",
      "A7-FRONT-004",
      "A7-FRONT-005"
    ],
    "unmapped_material_signals": [],
    "source_refs": [
      "supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2",
      "supabase://public.lf_eventos/20843"
    ],
    "currentness_refs": [],
    "coverage_fingerprint_sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  },
  "scope_front_matrix": [
    {
      "scope_id": "A6-REQ-001",
      "front_id": "A7-FRONT-001",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "dimension:functional",
      "front_id": "A7-FRONT-001",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "dimension:permissions",
      "front_id": "A7-FRONT-001",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "A6-REQ-002",
      "front_id": "A7-FRONT-002",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "A6-REQ-004",
      "front_id": "A7-FRONT-002",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "dimension:data",
      "front_id": "A7-FRONT-002",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "A6-REQ-003",
      "front_id": "A7-FRONT-003",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "dimension:state",
      "front_id": "A7-FRONT-003",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "dimension:errors",
      "front_id": "A7-FRONT-004",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "dimension:side_effects",
      "front_id": "A7-FRONT-004",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    },
    {
      "scope_id": "A6-REQ-005",
      "front_id": "A7-FRONT-005",
      "front_status": "REQUIRED",
      "front_closure": "BLOCKED",
      "effect_on_scope": "BLOCKS"
    }
  ],
  "package_readiness": "BLOCKED",
  "no_ready_claim": true,
  "snapshot_statement": "Snapshot exclusivamente candidato, construido a partir de las salidas A7 y A8 suministradas. Contiene once scopes: cinco requisitos provisionales y seis dimensiones, vinculados mediante once relaciones a cinco frentes materiales. La contabilidad de los elementos recibidos está completa, pero los cinco frentes permanecen REQUIRED y BLOCKED. Cada scope tiene al menos un frente bloqueante, por lo que ninguno puede declararse READY. La investigación conserva REQUIRES_DECISION según A8, mientras que el paquete permanece BLOCKED por decisiones materiales pendientes, ausencia de autoridad positiva, falta de evidencia de vigencia, implementación desconocida y línea base AS-IS no suministrada. Los cinco identificadores A5 deben contrastarse primero con decisiones y reglas vigentes; solo las cuestiones materialmente no resueltas corresponderían al propietario humano. La cobertura de la entrada no demuestra cobertura completa del sistema real. No se creó una huella de cobertura auténtica: los 64 ceros son únicamente el marcador solicitado por el arnés. No se ha persistido, atestiguado, aprobado ni admitido el snapshot para programación. Tampoco se ha declarado READY, seleccionado una solución técnica o autorizado implementación."
}$raw$;
 v_rec jsonb := $rec${"admission_state":"CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION","chat_transcript_hash_basis":"SHA-256 of the conversation main-element innerText captured in the browser at capture time (33894 bytes, after the A9Q_C2 reply); the transcript text itself is not stored here","chat_transcript_ref":"https://chatgpt.com/g/g-p-6a6d99aa6330819180764b10e86c9392-agente-de-programacion/c/6acef59c-df30-83e8-accd-609d3b78e0bf","chat_transcript_sha256":"fd6996435ac64705a2e85d59f590ef596cb2a2d1e222e5144d5cbd215a6460ce","evidence_tier":"OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT","input_sha256":"7bbd29aaf5bad0d3e2504f85987e941d64c26fbe74a11641d38431018152bec8","limits":{"checkpoint_transition":false,"independent_assurance_admitted":false,"provider_attested":false,"real_execution_receipt":false},"owner_approval_doc_sha256":"d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","owner_approval_ref":"docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md@d8908725237f39426fb1c40e4e9090c12eeb0a899d811f4317173ff9c25dd6dd","producer_mode":"GPT_NATIVE","raw_output_sha256":"c7bc45fdc546d263ed34754d1780073d7ffcef44c16f0b85440990ebc530d513","request_sha256":"e5a428fc99499b6bcf140da466196544a9230f7e1941cb5f49a6973298bb3891","run_id":"A9Q_C2-GPTN-PILOT-0001","runtime_provider_attested":false,"schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1","stage_output_selector":"A9","subject_ref":"PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A9Q/A9Q_C2","transcript_is_provider_evidence":false,"verifier":"analysis_qualification_a9q_c2_gpt_native_packet_v1.py intake -> PASS_EQUIVALENT_TIER_UNATTESTED_C2"}$rec$::jsonb;
 v_raw jsonb; v_m jsonb; v_specs jsonb; v_cps_before text; v_cps_after text;
 v_c7 jsonb; v_c8 jsonb; v_a7 jsonb; v_a8 jsonb;
BEGIN
 v_rec := v_rec || jsonb_build_object('raw_output_text', v_raw_text);
 IF encode(sha256(convert_to(v_raw_text,'UTF8')),'hex') <> v_rec->>'raw_output_sha256' THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_RAW_SHA_MISMATCH'; END IF;
 v_raw := v_raw_text::jsonb;
 v_c7:=(SELECT u.unit_metadata#>'{gpt_native_captures_v1,A7Q_C2}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A7Q'); v_c8:=(SELECT u.unit_metadata#>'{gpt_native_captures_v1,A8Q_C2}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A8Q');
 v_a7:=(v_c7->>'raw_output_text')::jsonb; v_a8:=(v_c8->>'raw_output_text')::jsonb;
 IF (v_raw->>'schema_version'='PROGRAMMING_CONTEXT_SNAPSHOT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'candidate_only'='true' AND v_raw->>'no_ready_claim'='true' AND v_raw->>'package_readiness' IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE') AND v_raw#>>'{material_front_coverage,coverage_fingerprint_sha256}'=repeat('0',64) AND v_c7->>'raw_output_sha256'='6bbeadcc8ac1c69d239aec02af75d6a0e153a745c1954703e6c4811c001173fa' AND v_c8->>'raw_output_sha256'='2fee538e7c6228fbd19d7ce5a01b88decd3afec213bb63170d52715fc7b09d30' AND v_raw->>'research_decision'=v_a8->>'research_decision' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'scope_readiness') s WHERE s->>'status' NOT IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE')) AND (SELECT array_agg(s ORDER BY s) FROM (SELECT DISTINCT s FROM jsonb_array_elements(v_a7->'material_fronts') f, jsonb_array_elements_text(f->'scope_ids') s) q)=(SELECT array_agg(s->>'scope_id' ORDER BY s->>'scope_id') FROM jsonb_array_elements(v_raw->'scope_readiness') s) AND (SELECT count(DISTINCT s->>'scope_id') FROM jsonb_array_elements(v_raw->'scope_readiness') s)=jsonb_array_length(v_raw->'scope_readiness') AND (SELECT array_agg(f->>'front_id' ORDER BY f->>'front_id') FROM jsonb_array_elements(v_a7->'material_fronts') f)=(SELECT array_agg(f->>'front_id' ORDER BY f->>'front_id') FROM jsonb_array_elements(v_raw#>'{material_front_coverage,material_fronts}') f) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_a7->'material_fronts') f WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw#>'{material_front_coverage,material_fronts}') g WHERE g->>'front_id'=f->>'front_id' AND g->>'closure'=f->>'closure' AND g->>'status'=f->>'obligation_mode' AND (SELECT coalesce(jsonb_agg(b ORDER BY b),'[]'::jsonb) FROM jsonb_array_elements_text(g->'blockers') b)=(SELECT coalesce(jsonb_agg(b ORDER BY b),'[]'::jsonb) FROM jsonb_array_elements_text(f->'blockers') b))) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'scope_front_matrix') m WHERE m->>'effect_on_scope'<>'BLOCKS') AND jsonb_array_length(v_raw->'scope_front_matrix')=(SELECT sum(jsonb_array_length(f->'scope_ids')) FROM jsonb_array_elements(v_a7->'material_fronts') f)) IS NOT TRUE THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_CONTENT_CHECK_FAILED'; END IF;
 IF (v_rec->>'evidence_tier') <> 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT' OR (v_rec->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_rec#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_LIMITS'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1119 AND checkpoint_code='A9Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_NOT_PENDING'; END IF;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A9Q' AND work_item_id=1119 FOR UPDATE;
 IF v_m#>>'{gpt_native_packets_v1,A9Q_C2,packet_sha256}' IS DISTINCT FROM v_packet_sha OR v_rec->>'request_sha256' IS DISTINCT FROM v_m#>>'{gpt_native_packets_v1,A9Q_C2,request_sha256}'
  THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_PACKET_BINDING'; END IF;
 IF v_m#>'{gpt_native_captures_v1,A9Q_C2}' IS NOT NULL AND v_m#>>'{gpt_native_captures_v1,A9Q_C2,raw_output_sha256}' <> v_rec->>'raw_output_sha256'
  THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_DIFFERENT_ALREADY_STORED'; END IF;
 v_specs := v_m->'action_specs_v1';
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1119;
 UPDATE programacion.engineering_plan_units SET unit_metadata = v_m || jsonb_build_object('gpt_native_captures_v1',
     COALESCE(v_m->'gpt_native_captures_v1','{}'::jsonb) || jsonb_build_object('A9Q_C2',v_rec))
  WHERE plan_code=v_plan AND unit_code='A9Q' AND work_item_id=1119;
 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='A9Q' AND work_item_id=1119;
 IF v_m#>'{gpt_native_captures_v1,A9Q_C2}' IS DISTINCT FROM v_rec THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_READBACK_MISMATCH'; END IF;
 IF v_m->'action_specs_v1' IS DISTINCT FROM v_specs THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_SPECS_CHANGED'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1119;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_CHECKPOINTS_CHANGED'; END IF;
END
$a9q_c2_cap$;
-- A9Q_C2 closure under the owner-approved GPT Native tier (decision: docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md).
-- A9Q_C2 closure under the owner-approved GPT Native tier (docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md) and the criterion amendment (docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).
DO $a9q_c2_close$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_unit constant text := 'A9Q';
 v_cp constant text := 'A9Q_C2';
 v_wi constant bigint := 1119;
 v_actor constant text := 'ANALYSIS_QUAL_C2_TIER_ACCEPTANCE';
 v_tier constant text := 'OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT';
 v_runner constant text := 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/analysis_qualification_a9q_c2_gpt_native_packet_v1.py';
 v_decision_doc constant text := 'docs/programming-agent/ANALYSIS_C2_TIER_ACCEPTANCE_DECISION_V1.md';
 v_decision_sha constant text := '2918579179b97bf3d479a3b3a05bda51a08a05fed456e41270c1a95e710acf53';
 v_amend_doc constant text := 'docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md';
 v_amend_sha constant text := '17d77d4af397a768d65617368cd043e2abc3795fc9f8f523ddfcb4044b8c2109';
 v_packet_sha constant text := '1b61735e4eed41a44f61f7d1f36ecbcf7e3683ca8b9ec3d871c3762897da7080';
 v_vq constant text := 'select checkpoint_code,status from programacion.engineering_work_checkpoints where work_item_id=1119 and checkpoint_code=''A9Q_C2''';
 v_state jsonb; v_m jsonb; v_old jsonb; v_spec jsonb; v_art jsonb; v_ready jsonb; v_cap jsonb; v_pk jsonb; v_raw jsonb;
 v_out jsonb; v_receipt jsonb; v_evidence text; v_open int; v_pass jsonb; v_amend jsonb;
 v_c7 jsonb; v_c8 jsonb; v_a7 jsonb; v_a8 jsonb;
BEGIN
 IF (SELECT c.checkpoint_code FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_wi AND c.status NOT IN ('DONE','NOT_APPLICABLE')
      ORDER BY c.sequence_no LIMIT 1) IS DISTINCT FROM v_cp
 THEN RAISE EXCEPTION 'A9Q_C2_NOT_CURRENT'; END IF;

 SELECT unit_metadata INTO v_m FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi FOR UPDATE;
 v_old:=v_m#>'{action_specs_v1,A9Q_C2}';
 IF v_old IS NULL OR v_old->>'status'<>'BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED'
    OR v_old#>>'{validator_contract,subject_ref}'<>v_plan||'/A9Q/A9Q_C2'
 THEN RAISE EXCEPTION 'A9Q_C2_PRESTATE_DRIFT'; END IF;

 -- Recompute the evidence from the stored capture.
 v_cap:=v_m#>'{gpt_native_captures_v1,A9Q_C2}'; v_pk:=v_m#>'{gpt_native_packets_v1,A9Q_C2}';
 IF v_cap IS NULL OR v_pk IS NULL OR v_pk->>'packet_sha256'<>v_packet_sha
    OR v_cap->>'request_sha256' IS DISTINCT FROM v_pk->>'request_sha256'
    OR v_cap->>'admission_state'<>'CAPTURED_VERIFIED_TIER_UNATTESTED_PENDING_ADMISSION'
 THEN RAISE EXCEPTION 'A9Q_C2_CAPTURE_MISSING_OR_UNBOUND'; END IF;
 IF encode(sha256(convert_to(v_cap->>'raw_output_text','UTF8')),'hex')<>v_cap->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'A9Q_C2_RAW_SHA_MISMATCH'; END IF;
 IF v_cap->>'evidence_tier'<>v_tier OR (v_cap->>'runtime_provider_attested')::boolean IS NOT FALSE
    OR (v_cap#>>'{limits,real_execution_receipt}')::boolean IS NOT FALSE
 THEN RAISE EXCEPTION 'A9Q_C2_TIER_OR_LIMITS'; END IF;
 v_raw:=(v_cap->>'raw_output_text')::jsonb;
 v_open:=jsonb_array_length(v_raw->'scope_readiness');
 v_c7:=(SELECT u.unit_metadata#>'{gpt_native_captures_v1,A7Q_C2}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A7Q'); v_c8:=(SELECT u.unit_metadata#>'{gpt_native_captures_v1,A8Q_C2}' FROM programacion.engineering_plan_units u WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A8Q');
 v_a7:=(v_c7->>'raw_output_text')::jsonb; v_a8:=(v_c8->>'raw_output_text')::jsonb;
 IF (v_raw->>'schema_version'='PROGRAMMING_CONTEXT_SNAPSHOT_V1' AND v_raw->>'request_ref'='REQ-LF-A1Q-C2-PILOT-0001' AND v_raw->>'candidate_only'='true' AND v_raw->>'no_ready_claim'='true' AND v_raw->>'package_readiness' IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE') AND v_raw#>>'{material_front_coverage,coverage_fingerprint_sha256}'=repeat('0',64) AND v_c7->>'raw_output_sha256'='6bbeadcc8ac1c69d239aec02af75d6a0e153a745c1954703e6c4811c001173fa' AND v_c8->>'raw_output_sha256'='2fee538e7c6228fbd19d7ce5a01b88decd3afec213bb63170d52715fc7b09d30' AND v_raw->>'research_decision'=v_a8->>'research_decision' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'scope_readiness') s WHERE s->>'status' NOT IN ('BLOCKED','REQUIRES_DECISION','NEED_MORE_EVIDENCE')) AND (SELECT array_agg(s ORDER BY s) FROM (SELECT DISTINCT s FROM jsonb_array_elements(v_a7->'material_fronts') f, jsonb_array_elements_text(f->'scope_ids') s) q)=(SELECT array_agg(s->>'scope_id' ORDER BY s->>'scope_id') FROM jsonb_array_elements(v_raw->'scope_readiness') s) AND (SELECT count(DISTINCT s->>'scope_id') FROM jsonb_array_elements(v_raw->'scope_readiness') s)=jsonb_array_length(v_raw->'scope_readiness') AND (SELECT array_agg(f->>'front_id' ORDER BY f->>'front_id') FROM jsonb_array_elements(v_a7->'material_fronts') f)=(SELECT array_agg(f->>'front_id' ORDER BY f->>'front_id') FROM jsonb_array_elements(v_raw#>'{material_front_coverage,material_fronts}') f) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_a7->'material_fronts') f WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw#>'{material_front_coverage,material_fronts}') g WHERE g->>'front_id'=f->>'front_id' AND g->>'closure'=f->>'closure' AND g->>'status'=f->>'obligation_mode' AND (SELECT coalesce(jsonb_agg(b ORDER BY b),'[]'::jsonb) FROM jsonb_array_elements_text(g->'blockers') b)=(SELECT coalesce(jsonb_agg(b ORDER BY b),'[]'::jsonb) FROM jsonb_array_elements_text(f->'blockers') b))) AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_raw->'scope_front_matrix') m WHERE m->>'effect_on_scope'<>'BLOCKS') AND jsonb_array_length(v_raw->'scope_front_matrix')=(SELECT sum(jsonb_array_length(f->'scope_ids')) FROM jsonb_array_elements(v_a7->'material_fronts') f)) IS NOT TRUE
 THEN RAISE EXCEPTION 'A9Q_C2_CONTENT_CHECK_FAILED'; END IF;
 IF length(coalesce(v_cap->>'chat_transcript_ref',''))<10 OR coalesce(v_cap->>'chat_transcript_sha256','')!~'^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'A9Q_C2_CHAT_BINDING_MISSING'; END IF;

 v_amend:=jsonb_build_object('criterion_amended',true,'original','Snapshot real A9 persistido con identidad y huellas verificables','amended','Snapshot A9 producido por GPT con huellas del RAW verificadas','amendment_ref',v_amend_doc||'@'||v_amend_sha,'plan_exit_criterion_modified',false);
 v_pass:=jsonb_build_object('capture_verified',true,'criterion_amendment',v_amend,'evidence_tier',v_tier,'raw_sha256_recomputed_matches',true,
   'content_checks_passed',true,'owner_decision_recorded',true);
 v_art:=jsonb_build_object('path',v_runner,'role','MUTATION_TARGET','purpose','CHECKPOINT_TEST_ARTIFACT','target_kind','EXACT_NEW_OR_UPDATE_FILE');
 v_spec:=v_old||jsonb_build_object(
  'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',v_cp,
  'contract_family','BOUNDED_CHECKPOINT_TEST','contract_source','EXPLICIT_ACTION_SPEC',
  'mutation_policy','TEST_ARTIFACT_ONLY','precision','BOUNDED_CHECKPOINT_TEST_AUTHORING_V1',
  'action_kind','BOUNDED_CHECKPOINT_TEST_AUTHORING','recipe_mode','AUTHOR_AND_RUN_CHECKPOINT_TEST',
  'expected','Verify the stored GPT Native capture of the A9 snapshot candidate under the owner-approved equivalent tier and the approved criterion amendment, and bind its result',
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
  'test_execution_contract',jsonb_build_object('mode','AUTHORED_NEGATIVE','test_code','ENG_A9Q_C2_GPT_NATIVE_TIER_CAPTURE',
    'test_path',v_runner,'synthetic_pass','FORBIDDEN',
    'declared_objects',jsonb_build_array('programacion.engineering_work_checkpoints'),
    'declared_queries',jsonb_build_array(v_vq),'negative_required',true,'authoring_required',true,
    'semantic_authority','CANONICAL_PLAN_EXIT_CRITERION','fallback_case_discovery','FORBIDDEN',
    'canonical_exit_criterion',v_old#>>'{validator_contract,criterion}','checkpoint_title_context',v_cp),
  'source_pack_missing_typed','[]'::jsonb,'requires_material_execution',true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,A9Q_C2}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,A9Q_C2,missing_typed}','[]'::jsonb,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_wi;

 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'A9Q_C2_BOOTSTRAP_NOT_CONTINUE:%',v_state->>'terminal_action'; END IF;
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'A9Q_C2_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/A9Q#unit_metadata.gpt_native_captures_v1.A9Q_C2'
   ||';raw_sha256:'||(v_cap->>'raw_output_sha256')||';request_sha256:'||(v_cap->>'request_sha256')
   ||';chat:'||(v_cap->>'chat_transcript_ref')||';chat_sha256:'||(v_cap->>'chat_transcript_sha256')
   ||';tier:'||v_tier||';decision:'||v_decision_doc||'@'||v_decision_sha||';amendment:'||v_amend_doc||'@'||v_amend_sha;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A9Q_C2_HEARTBEAT_START:%',v_out; END IF;

 v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(v_plan,v_unit,v_cp,
  jsonb_build_object('status','PASS','test_code','ENG_A9Q_C2_GPT_NATIVE_TIER_CAPTURE','evidence_ref',v_evidence,
   'observed',v_pass||jsonb_build_object(
    'raw_output_sha256',v_cap->>'raw_output_sha256','request_sha256',v_cap->>'request_sha256','packet_sha256',v_packet_sha,
    'chat_transcript_ref',v_cap->>'chat_transcript_ref','chat_transcript_sha256',v_cap->>'chat_transcript_sha256',
    'request_ref',v_raw->>'request_ref','scopes_in_snapshot',v_open,'fronts_in_snapshot',jsonb_array_length(v_raw#>'{material_front_coverage,material_fronts}'),'matrix_rows',jsonb_array_length(v_raw->'scope_front_matrix'),'no_scope_ready',true,'package_readiness',v_raw->>'package_readiness','fingerprint_is_harness_placeholder',true,'linked_to_stored_a7_fronts_and_a8_decision',true,
    'producer_mode','GPT_NATIVE','evidence_class',v_tier,
    'owner_decision_ref',v_decision_doc||'@'||v_decision_sha,'criterion_amendment_ref',v_amend_doc||'@'||v_amend_sha,
    'provider_attested',false,'governed_runtime_receipt',false,'real_execution_receipt',false,'independent_review',false,
    'attestation_scope','CAPTURE_BOUND_BY_HASH_ONLY',
    'not_verified_by_this_assertion',jsonb_build_array('that_gpt_produced_the_raw','provider_runtime_identity','conversation_transcript_authenticity','independent_review'))),
  v_actor);
 IF v_receipt->>'passed'<>'true' OR nullif(v_receipt->>'assertion_receipt_sha256','') IS NULL
 THEN RAISE EXCEPTION 'A9Q_C2_RECEIPT_FAILED:%',v_receipt; END IF;

 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,v_actor,true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'A9Q_C2_HEARTBEAT_END:%',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,v_unit,v_cp,'DONE',v_evidence,v_actor,
  'C2 closed under the owner-approved GPT Native in-chat tier and the approved criterion amendment (A9 snapshot produced by GPT with RAW fingerprints verified); hash-bound capture only; no provider attestation, no governed-runtime receipt, no independent review');
 IF v_out#>>'{transition,status}'<>'APPLIED' THEN RAISE EXCEPTION 'A9Q_C2_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wi)
    <>'A9Q_C1:DONE,A9Q_C2:DONE,A9Q_C3:PENDING'
 THEN RAISE EXCEPTION 'A9Q_C2_POSTSTATE_FAILED'; END IF;
END $a9q_c2_close$;
COMMIT;
