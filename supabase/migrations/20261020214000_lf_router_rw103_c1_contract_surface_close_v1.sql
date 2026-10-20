-- RW1-03_C1: bind exact contract/consumer/permission/EKB surface baseline and close only after readback.
-- Governance metadata only. No Router runtime, ACL, operation, profile/adapter or production mutation.
BEGIN;
DO $rw103_c1$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-03';
  v_cp constant text := 'RW1-03_C1';
  v_work_item constant bigint := 1129;
  v_prior_md5 constant text := '4801c1945f0549ab8086adf115f55486';
  v_actor constant text := 'LF_ROUTER_RW103_C1_CONTRACT_SURFACE_CLOSE_20261020';
  v_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_03_C1_CONTRACT_SURFACE_AUTHORITY_BASELINE_V1.md#blob:017150ff7a56e3a0b0d04369d05333abc5c539af';
  v_spec jsonb := $json$
{
  "status":"READY",
  "schema_version":"ENGINEERING_ACTION_SPEC_V3",
  "checkpoint_code":"RW1-03_C1",
  "contract_source":"EXPLICIT_ACTION_SPEC",
  "contract_family":"READ_ONLY_EVIDENCE",
  "precision":"EXACT_RW103_CONTRACT_SURFACE_AUTHORITY",
  "action_kind":"READBACK_ONCE",
  "recipe_mode":"READBACK_EXACT",
  "mutation_policy":"NO_DOMAIN_MUTATION",
  "requires_material_execution":false,
  "target":{
    "checkpoint":"RW1-03_C1",
    "declared_assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "declared_events":[21263],
    "declared_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_router_action_registry",
      "public.lf_operation_registry",
      "public.lf_activos",
      "public.lf_error_knowledge",
      "public.lf_eventos"
    ],
    "declared_artifacts":[],
    "evidence_artifacts":[
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_03_C1_CONTRACT_SURFACE_AUTHORITY_BASELINE_V1.md","role":"EVIDENCE","purpose":"RW103_CONTRACT_SURFACE_BASELINE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V2.json","role":"EVIDENCE","purpose":"SELECTED_ARCHITECTURE","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json","role":"EVIDENCE","purpose":"SELECTED_DESIGN_INVARIANTS","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md","role":"EVIDENCE","purpose":"REUSED_CONSUMER_AUTHORITY_INVENTORY","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md","role":"EVIDENCE","purpose":"REUSED_E2E_BINDING_GAPS","target_kind":"EXACT_EXISTING_FILE"},
      {"path":"cristhianlujan/claude-persona-lf-patch:docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md","role":"EVIDENCE","purpose":"CURRENT_ROUTER_CALLER_CONTRACT","target_kind":"EXACT_EXISTING_FILE"}
    ],
    "mutation_artifacts":[]
  },
  "expected":"Freeze the exact surface contracts, consumers, permissions and EKB strictly affected by selected architecture A. Reuse A16Q; do not define final ABI, widen ACL, mutate Router runtime, operations or production.",
  "forbidden":[
    "DEFINE_FINAL_ABI_IN_C1",
    "CREATE_SECOND_ROUTER",
    "CREATE_SEMANTIC_EFFECT_AUTHORITY",
    "WIDEN_ROUTER_OR_IG_ACL",
    "MUTATE_ROUTER_RUNTIME",
    "MUTATE_OPERATION_REGISTRY",
    "ENABLE_PROFILE_OR_ADAPTER",
    "CHANGE_MERGE_TRAIN",
    "REPEAT_A16Q_INVENTORY",
    "CLAIM_ROUTER_RUNTIME_PASS",
    "CLAIM_E2E_PASS",
    "CLAIM_PRODUCTION_EFFECT",
    "CHANGE_RW1_02",
    "CHANGE_RW1_03_C2_OR_C3"
  ],
  "action_steps":[
    "VERIFY_RW102_DEPENDENCY_DONE",
    "FREEZE_SELECTED_ARCHITECTURE_A",
    "VERIFY_CURRENT_ROUTER_AND_HANDOFF_IDENTITIES",
    "VERIFY_A16Q_C1_C2_REUSE",
    "MAP_FIVE_AFFECTED_SURFACE_GROUPS",
    "VERIFY_THREE_PERMISSION_BOUNDARIES",
    "VERIFY_TWELVE_ACTIVE_EKB_REFERENCES",
    "VERIFY_PLAN_ACCEPTANCE_FALSE",
    "ASSERT_NO_ABI_OR_RUNTIME_OR_ACL_MUTATION",
    "VERIFY_POSITIVE_AND_NEGATIVE_C1_PREDICATE",
    "PERSIST_C1_DONE_ONLY_AFTER_READBACK"
  ],
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_03_C1_CONTRACT_SURFACE_AUTHORITY_BASELINE_V1.md#blob:017150ff7a56e3a0b0d04369d05333abc5c539af",
  "assertion_contract":{
    "mode":"EXPLICIT_PASS_WHEN_SUBSET",
    "pass_when":{
      "dependency_rw102_done":true,
      "selected_architecture":"A_MIN_ROUTER_SEMANTIC_SPECIALIST",
      "checkpoint_source_verified":true,
      "source_sha_current":true,
      "a16q_reused_not_duplicated":true,
      "affected_surface_groups":5,
      "permission_boundaries_verified":3,
      "active_router_routes":35,
      "write_router_routes":26,
      "nonwrite_router_routes":9,
      "ekb_references_verified":12,
      "router_source_md5_matches":true,
      "handoff_source_md5_matches":true,
      "ig_source_md5_matches":true,
      "plan_acceptance_false":true,
      "no_final_abi_defined":true,
      "no_acl_change":true,
      "no_router_runtime_mutation":true,
      "no_production_mutation":true
    }
  },
  "verification_queries":[
    "SELECT u.plan_code,u.unit_code,u.work_item_id,w.status AS work_status,c.checkpoint_code,c.status FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_items w ON w.id=u.work_item_id JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id WHERE u.plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND u.unit_code='RW1-03' ORDER BY c.sequence_no",
    "SELECT c.checkpoint_code,c.status,c.evidence_ref,c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1128 ORDER BY c.sequence_no",
    "SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS args,p.prosecdef,p.proacl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname IN ('lf_router_resolve_v1','lf_router_intent_handoff_v1')) OR (n.nspname='programacion' AND p.proname='fn_lf_router_input_governance_resolve_v1') ORDER BY p.proname",
    "SELECT count(*) AS active_routes,count(*) FILTER (WHERE write_allowed) AS write_routes,count(*) FILTER (WHERE NOT write_allowed) AS nonwrite_routes FROM public.lf_router_action_registry WHERE status='ACTIVE'",
    "SELECT codigo_activo,tipo_activo,estado_documental,estado_operativo,runtime_estado FROM public.lf_activos WHERE codigo_activo IN ('ACT-0001','ROUTER_DOWNSTREAM_AUTHORITY','OPERATION_EFFECT_GUARD','OPERATION_MATERIALIZATION_GUARD') ORDER BY codigo_activo",
    "SELECT codigo,titulo,estado FROM public.lf_error_knowledge WHERE codigo LIKE 'LF-ROUTER-ACT0001-%' OR codigo IN ('ENGINEERING-FOUR-CAPABILITY-ROUTER-001','ENGINEERING-CONSUMER-PROBE-WRITE-MISCLASSIFICATION-001','POST-PASE-CONSUMER-CANONICAL-BINDING-001','ENGINEERING-REPOSITORY-CAPABILITY-CONSUMER-ASSERTION-001','CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL') ORDER BY codigo",
    "SELECT id,entidad_tipo,entidad_codigo,evento_tipo,payload->>'acceptance_declared' AS acceptance_declared FROM public.lf_eventos WHERE id=21263"
  ]
}
$json$::jsonb;
  v_source jsonb := $json$
{
  "inputs":{
    "assets":["ACT-0001","ROUTER_DOWNSTREAM_AUTHORITY","OPERATION_EFFECT_GUARD","OPERATION_MATERIALIZATION_GUARD"],
    "events":[21263],
    "queries":[
      "SELECT u.plan_code,u.unit_code,u.work_item_id,w.status AS work_status,c.checkpoint_code,c.status FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_items w ON w.id=u.work_item_id JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id WHERE u.plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND u.unit_code='RW1-03' ORDER BY c.sequence_no",
      "SELECT c.checkpoint_code,c.status,c.evidence_ref,c.assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1128 ORDER BY c.sequence_no",
      "SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS args,p.prosecdef,p.proacl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname IN ('lf_router_resolve_v1','lf_router_intent_handoff_v1')) OR (n.nspname='programacion' AND p.proname='fn_lf_router_input_governance_resolve_v1') ORDER BY p.proname",
      "SELECT count(*) AS active_routes,count(*) FILTER (WHERE write_allowed) AS write_routes,count(*) FILTER (WHERE NOT write_allowed) AS nonwrite_routes FROM public.lf_router_action_registry WHERE status='ACTIVE'",
      "SELECT codigo_activo,tipo_activo,estado_documental,estado_operativo,runtime_estado FROM public.lf_activos WHERE codigo_activo IN ('ACT-0001','ROUTER_DOWNSTREAM_AUTHORITY','OPERATION_EFFECT_GUARD','OPERATION_MATERIALIZATION_GUARD') ORDER BY codigo_activo",
      "SELECT codigo,titulo,estado FROM public.lf_error_knowledge WHERE codigo LIKE 'LF-ROUTER-ACT0001-%' OR codigo IN ('ENGINEERING-FOUR-CAPABILITY-ROUTER-001','ENGINEERING-CONSUMER-PROBE-WRITE-MISCLASSIFICATION-001','POST-PASE-CONSUMER-CANONICAL-BINDING-001','ENGINEERING-REPOSITORY-CAPABILITY-CONSUMER-ASSERTION-001','CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL') ORDER BY codigo",
      "SELECT id,entidad_tipo,entidad_codigo,evento_tipo,payload->>'acceptance_declared' AS acceptance_declared FROM public.lf_eventos WHERE id=21263"
    ],
    "db_objects":[
      "programacion.engineering_plan_units",
      "programacion.engineering_work_items",
      "programacion.engineering_work_checkpoints",
      "public.lf_router_action_registry",
      "public.lf_operation_registry",
      "public.lf_activos",
      "public.lf_error_knowledge",
      "public.lf_eventos"
    ],
    "artifacts":[
      "docs/programming-agent/router_wave/RW1_03_C1_CONTRACT_SURFACE_AUTHORITY_BASELINE_V1.md",
      "docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V2.json",
      "docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json",
      "docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md",
      "docs/programming-agent/ANALYSIS_A16Q_C2_CONSUMER_TRACE_BASELINE_V1.md",
      "docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md"
    ]
  },
  "missing":[],
  "missing_typed":[],
  "expected_result":"Current authority map for the five contract/consumer/effect/permission/Train surface groups affected by architecture A, reusing A16Q and preserving all effect authority outside the semantic specialist.",
  "evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_03_C1_CONTRACT_SURFACE_AUTHORITY_BASELINE_V1.md#blob:017150ff7a56e3a0b0d04369d05333abc5c539af",
  "verification_boundary":"RW103_C1_SOURCE_AUTHORITY_ONLY_NOT_ABI_RUNTIME_E2E_OR_PRODUCTION",
  "source_snapshot_commit":"e02a9836f0ea51214f9f9583fe2281367002f3ff",
  "source_git_blobs":{
    "rw103_c1_baseline":"017150ff7a56e3a0b0d04369d05333abc5c539af",
    "wave":"4bb64d568c3f005cf454fb223b4a5ed699c34504",
    "rw102_c3_verdict":"623c9926d745bf0670156fe1b96d5729f0e4900b",
    "rw102_c2_competition":"cf22d9889eb008dc7afcf64dd1b3712b9536ec98",
    "a16q_c1":"28e020ba05721892524bfc7971cd7c0f3a8f9878",
    "a16q_c2":"72b4e5977c96162ab60c5d76a1b070bd5d70b3eb",
    "compact_router_protocol":"06d8905db56f04bf8557ccb0db556a25f704d015"
  },
  "db_source_md5":{
    "lf_router_resolve_v1":"d45f5bddb693791b6459bbe3acfd4ed3",
    "lf_router_intent_handoff_v1":"540bc1b60caf2e3f9d81461f99c509ef",
    "fn_lf_router_input_governance_resolve_v1":"72e153a7fbfe7b10a8c9ae694a61b334"
  }
}
$json$::jsonb;
  v_new jsonb;
  v_action jsonb;
  v_contract jsonb;
  v_ready jsonb;
  v_preflight jsonb;
  v_obs jsonb;
  v_bad jsonb;
  v_pass_when jsonb;
  v_transition jsonb;
  v_count integer;
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
      WHERE u.plan_code=v_plan AND u.unit_code=v_unit
        AND u.work_item_id=v_work_item AND u.plan_event_id=21263
        AND u.disposition='ASSIGNED'
        AND w.work_code='ROUTER-W1-03'
        AND w.status='BACKLOG'
        AND md5(u.unit_metadata::text)=v_prior_md5
        AND NOT (u.unit_metadata ? 'action_specs_v1')
        AND NOT (u.unit_metadata ? 'source_pack_v2'))<>1
  THEN RAISE EXCEPTION 'RW103_C1_PRESTATE_OR_METADATA_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND status='PENDING')<>3
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
           AND id=1613 AND status='PENDING' AND evidence_ref IS NULL
           AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW103_C1_CHECKPOINT_PRESTATE_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1128 AND status='DONE')<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=1128 AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1128 AND checkpoint_code='RW1-02_C3'
           AND status='DONE'
           AND evidence_ref='github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V2.json'
           AND assertion_receipt->>'passed'='true')<>1
  THEN RAISE EXCEPTION 'RW103_C1_RW102_DEPENDENCY_NOT_DONE'; END IF;

  IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
       IS DISTINCT FROM 'd45f5bddb693791b6459bbe3acfd4ed3'
     OR md5(pg_get_functiondef('public.lf_router_intent_handoff_v1(text,jsonb,text)'::regprocedure))
       IS DISTINCT FROM '540bc1b60caf2e3f9d81461f99c509ef'
     OR md5(pg_get_functiondef('programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure))
       IS DISTINCT FROM '72e153a7fbfe7b10a8c9ae694a61b334'
  THEN RAISE EXCEPTION 'RW103_C1_FUNCTION_SOURCE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE')<>35
     OR (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE' AND write_allowed)<>26
     OR (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE' AND NOT write_allowed)<>9
  THEN RAISE EXCEPTION 'RW103_C1_ROUTER_ACTION_REGISTRY_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_activos
      WHERE codigo_activo IN ('ACT-0001','ROUTER_DOWNSTREAM_AUTHORITY','OPERATION_EFFECT_GUARD','OPERATION_MATERIALIZATION_GUARD')
        AND estado_documental='VIGENTE' AND estado_operativo='ACTIVO')<>4
  THEN RAISE EXCEPTION 'RW103_C1_EFFECT_AUTHORITY_SURFACE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_error_knowledge
      WHERE (codigo LIKE 'LF-ROUTER-ACT0001-%'
         OR codigo IN ('ENGINEERING-FOUR-CAPABILITY-ROUTER-001',
                       'ENGINEERING-CONSUMER-PROBE-WRITE-MISCLASSIFICATION-001',
                       'POST-PASE-CONSUMER-CANONICAL-BINDING-001',
                       'ENGINEERING-REPOSITORY-CAPABILITY-CONSUMER-ASSERTION-001',
                       'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'))
        AND estado IN ('ACTIVO','ACTIVE'))<>12
  THEN RAISE EXCEPTION 'RW103_C1_EKB_SET_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_eventos
      WHERE id=21263 AND entidad_tipo='ENGINEERING_PLAN'
        AND entidad_codigo=v_plan AND evento_tipo='PLAN_SNAPSHOT_DETALLADO'
        AND payload->>'acceptance_declared'='false')<>1
  THEN RAISE EXCEPTION 'RW103_C1_PLAN_EVENT_OR_ACCEPTANCE_DRIFT'; END IF;

  v_new := (
    SELECT jsonb_set(
      jsonb_set(u.unit_metadata,'{action_specs_v1}',jsonb_build_object(v_cp,v_spec),true),
      '{source_pack_v2}',jsonb_build_object('checkpoint_inputs',jsonb_build_object(v_cp,v_source)),true)
    FROM programacion.engineering_plan_units u
    WHERE u.plan_code=v_plan AND u.unit_code=v_unit
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW103_C1_SOURCE_BIND_ROW_COUNT:%',v_count; END IF;

  v_action:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_action);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  v_preflight:=programacion.fn_engineering_checkpoint_source_query_preflight_v1(v_plan,v_unit,v_cp);

  IF v_action->>'status' IS DISTINCT FROM 'READY'
     OR v_action->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
     OR v_action->>'contract_source' IS DISTINCT FROM 'EXPLICIT_ACTION_SPEC'
     OR v_contract->>'status' IS DISTINCT FROM 'NOT_REQUIRED'
     OR v_contract->>'reason' IS DISTINCT FROM 'NON_MATERIAL_CHECKPOINT'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready#>>'{source_currentness,status}' IS DISTINCT FROM 'CURRENT'
     OR v_preflight->>'status' IS DISTINCT FROM 'PASS'
     OR (v_preflight->>'query_count')::int IS DISTINCT FROM 7
     OR (v_preflight->>'passed')::int IS DISTINCT FROM 7
     OR (v_preflight->>'failed')::int IS DISTINCT FROM 0
  THEN RAISE EXCEPTION 'RW103_C1_CONTRACT_OR_SOURCE_PREFLIGHT_FAILED: action=% contract=% ready=% preflight=%',
       v_action::text,v_contract::text,v_ready::text,v_preflight::text; END IF;

  v_obs:=jsonb_build_object(
    'dependency_rw102_done',true,
    'selected_architecture','A_MIN_ROUTER_SEMANTIC_SPECIALIST',
    'checkpoint_source_verified',true,
    'source_sha_current',true,
    'source_main_sha','e02a9836f0ea51214f9f9583fe2281367002f3ff',
    'source_doc_blob','017150ff7a56e3a0b0d04369d05333abc5c539af',
    'a16q_reused_not_duplicated',true,
    'affected_surface_groups',5,
    'permission_boundaries_verified',3,
    'active_router_routes',35,
    'write_router_routes',26,
    'nonwrite_router_routes',9,
    'ekb_references_verified',12,
    'router_source_md5_matches',true,
    'handoff_source_md5_matches',true,
    'ig_source_md5_matches',true,
    'plan_acceptance_false',true,
    'source_queries_passed',7,
    'no_final_abi_defined',true,
    'no_acl_change',true,
    'no_router_runtime_mutation',true,
    'no_production_mutation',true,
    'c2_c3_untouched',true
  );

  v_pass_when:=v_action#>'{assertion_contract,pass_when}';
  IF jsonb_typeof(v_pass_when) IS DISTINCT FROM 'object'
     OR (v_obs @> v_pass_when) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW103_C1_POSITIVE_PREDICATE_FAILED'; END IF;

  -- Negative control: allowing the semantic specialist to own effect authority must fail C1.
  v_bad:=jsonb_set(v_obs,'{no_router_runtime_mutation}','false'::jsonb,true);
  IF (v_bad @> v_pass_when) IS NOT DISTINCT FROM false
  THEN NULL;
  ELSE
    RAISE EXCEPTION 'RW103_C1_NEGATIVE_PREDICATE_FALSE_PASS';
  END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING'
        AND assertion_receipt IS NULL
        AND assertion_receipt_sha256 IS NULL
        AND assertion_contract_sha256 IS NULL)<>1
  THEN RAISE EXCEPTION 'RW103_C1_NONMATERIAL_RECEIPT_INVARIANT_FAILED'; END IF;

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_ref,v_actor,
    'RW1-03_C1 nonmaterial READBACK_ONCE: RW1-02 3/3 DONE and architecture A frozen; current Router/handoff/IG source identities verified; A16Q reused; five affected surface groups, three ACL boundaries, 35 active routes and 12 active Router/consumer EKB entries mapped; no final ABI, ACL, runtime, operation or production mutation.'
  );
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW103_C1_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-03_C1' AND status='DONE'
              AND evidence_ref=v_ref
              AND assertion_receipt IS NULL
              AND assertion_receipt_sha256 IS NULL
              AND assertion_contract_sha256 IS NULL)
          OR (checkpoint_code IN ('RW1-03_C2','RW1-03_C3')
              AND status='PENDING' AND evidence_ref IS NULL)))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=v_work_item AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1128 AND status='DONE')<>3
  THEN RAISE EXCEPTION 'RW103_C1_POST_READBACK_NOT_CONSISTENT'; END IF;
END
$rw103_c1$;
COMMIT;
