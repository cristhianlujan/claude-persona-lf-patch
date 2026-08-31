-- Source-first Gate 9 remediation for LEARNING_BRIDGE_KB_CARD_LF.
-- Materializes only ACTIVE_ROUTER_MAPPING + ACTIVE_STEP_CONTRACT.
-- Does not activate runtime, policy binding, judge binding, ACT-0046, production, or automatic impact.

insert into public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,
  requires_existing_target,requires_missing_target,write_allowed,status,notes,
  created_by_execution_id,updated_by_execution_id
) values (
  'KNOWLEDGE','KNOWLEDGE_LEARNING_BRIDGE','LEARNING_BRIDGE_KB_CARD_LF','STATIC',
  true,false,false,'ACTIVE',
  'Source: gobernanza/router/learning_bridge_kb_card_lf_router_action.yaml. Read-only Router entry for eligible canonical LF knowledge.',
  'LF-AUTOLEARN-RUN-20260831-021','LF-AUTOLEARN-RUN-20260831-021'
)
on conflict (asset_type,action_code) do update set
  operation_code=excluded.operation_code,
  operation_resolution=excluded.operation_resolution,
  requires_existing_target=excluded.requires_existing_target,
  requires_missing_target=excluded.requires_missing_target,
  write_allowed=excluded.write_allowed,
  status=excluded.status,
  notes=excluded.notes,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=now();

with src(step_order,step_id,purpose,evidence_key,mini_judge_code,resolver_ref) as (
  values
  (1,'router','Resolve ACT-0001 route','router_read','JUDGE_LB_STEP_ROUTER_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (2,'operational_source','Read operational source','operational_source_read','JUDGE_LB_STEP_OPERATIONAL_SOURCE_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (3,'ekb_precheck','Read EKB before mutation','ekb_read','JUDGE_LB_STEP_EKB_PRECHECK_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (4,'select_kb_candidate','Select traced canonical KB candidate','kb_source_readback','JUDGE_LB_STEP_KB_SELECT_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (5,'eligibility_gate','Verify grounded consumer-ready eligibility','grounded_consumer_ready_allow_prod_gate','JUDGE_LB_STEP_ELIGIBILITY_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (6,'effective_competitor','Resolve effective competitor deterministically','effective_competitor_and_fallback_flag','JUDGE_LB_STEP_COMPETITOR_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (7,'deterministic_dedup','Deduplicate learning and card target','duplicate_and_existing_card_check','JUDGE_LB_STEP_DEDUP_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (8,'deterministic_cluster','Assign canonical learning cluster','taxonomy_version_cluster_code_assignment_rule_reason','JUDGE_LB_STEP_CLUSTER_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (9,'lifecycle_detectado','Persist DETECTADO transition','detectado_transition_receipt','JUDGE_LB_STEP_DETECTADO_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (10,'semantic_analysis','Perform bounded semantic analysis','analysis_pack','JUDGE_LB_STEP_SEMANTIC_ANALYSIS_V1','GPT_RUNTIME_WITH_SUPABASE_CONTEXT'),
  (11,'lifecycle_analizado','Persist ANALIZADO transition','analizado_transition_receipt','JUDGE_LB_STEP_ANALIZADO_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (12,'research_to_rules_matrix','Materialize research-to-rules matrix','research_to_rules_matrix_present','JUDGE_LB_STEP_RULES_MATRIX_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (13,'decision_matrix','Materialize bounded decision matrix','decision_matrix_present','JUDGE_LB_STEP_DECISION_MATRIX_V1','GPT_RUNTIME_WITH_SUPABASE_CONTEXT'),
  (14,'card_factory_contract','Read current CREACION_CARD_LF contract','creacion_card_lf_contract_read','JUDGE_LB_STEP_CARD_CONTRACT_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (15,'card_candidate','Invoke governed Card candidate path','card_factory_candidate_receipt','JUDGE_LB_STEP_CARD_CANDIDATE_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (16,'lifecycle_card_creada','Persist CARD_CREADA transition','card_creada_transition_receipt','JUDGE_LB_STEP_CARD_CREADA_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (17,'lifecycle_en_revision','Persist EN_REVISION transition','en_revision_transition_receipt','JUDGE_LB_STEP_EN_REVISION_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (18,'sandbox','Execute governed sandbox tests','sandbox_test_receipt','JUDGE_LB_STEP_SANDBOX_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (19,'quality_gate','Evaluate quality gate','quality_gate_result','JUDGE_LB_STEP_QUALITY_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (20,'performance_gate','Evaluate measured performance gate','performance_gate_result','JUDGE_LB_STEP_PERFORMANCE_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (21,'governance_gate','Evaluate governance minimum lifecycle','governance_gate_result','JUDGE_LB_STEP_GOVERNANCE_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (22,'approval_boundary','Enforce approval boundary','approval_or_blocked_governance_gate','JUDGE_LB_STEP_APPROVAL_BOUNDARY_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (23,'impact_if_authorized','Allow impact only with valid authorization','authorized_executor_receipt','JUDGE_LB_STEP_IMPACT_AUTH_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (24,'verify','Read back authorized effects or no-impact state','verification_readback','JUDGE_LB_STEP_VERIFY_V1','DETERMINISTIC_SUPABASE_GITHUB'),
  (25,'close','Close with durable event','closure_event','JUDGE_LB_STEP_CLOSE_V1','DETERMINISTIC_SUPABASE_GITHUB')
), shaped as (
  select
    'LEARNING_BRIDGE_KB_CARD_LF'::text operation_code,
    step_id,step_order,step_order execution_order,
    'CONTRACT-LEARNING-BRIDGE-KB-CARD-LF-v0.2'::text contract_code,
    purpose,
    jsonb_build_array('prior_step_readback') input_required,
    resolver_ref,
    jsonb_build_array(evidence_key) output_payload,
    jsonb_build_object('required_evidence_key',evidence_key,'must_be_present',true) pass_condition,
    jsonb_build_object('required_evidence_key',evidence_key,'missing',true) block_condition,
    ('BLOCK_LB_STEP_'||upper(step_id)||'_EVIDENCE_MISSING')::text blocking_code,
    mini_judge_code,
    jsonb_build_array(evidence_key) required_evidence_keys,
    lead(step_id) over(order by step_order) next_if_pass,
    'close'::text next_if_blocked,
    'ACTIVE_ENFORCEMENT'::text status,
    'Source: gobernanza/procedimientos/learning_bridge_kb_card_lf_step_contracts.yaml'::text notes
  from src
)
insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,
  resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,
  required_evidence_keys,next_if_pass,next_if_blocked,status,notes,
  created_by_execution_id,updated_by_execution_id
)
select operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,
       resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,
       required_evidence_keys,next_if_pass,next_if_blocked,status,notes,
       'LF-AUTOLEARN-RUN-20260831-021','LF-AUTOLEARN-RUN-20260831-021'
from shaped
on conflict (operation_code,step_id) do update set
  step_order=excluded.step_order,
  execution_order=excluded.execution_order,
  contract_code=excluded.contract_code,
  purpose=excluded.purpose,
  input_required=excluded.input_required,
  resolver_ref=excluded.resolver_ref,
  output_payload=excluded.output_payload,
  pass_condition=excluded.pass_condition,
  block_condition=excluded.block_condition,
  blocking_code=excluded.blocking_code,
  mini_judge_code=excluded.mini_judge_code,
  required_evidence_keys=excluded.required_evidence_keys,
  next_if_pass=excluded.next_if_pass,
  next_if_blocked=excluded.next_if_blocked,
  status=excluded.status,
  notes=excluded.notes,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=now();

update public.lf_operation_registry
set source_paths = source_paths || jsonb_build_array(
      'gobernanza/router/learning_bridge_kb_card_lf_router_action.yaml',
      'gobernanza/procedimientos/learning_bridge_kb_card_lf_step_contracts.yaml'
    ),
    notes = coalesce(notes,'') || ' | Gate9 minimum lifecycle source: Router action + exact step contracts; no runtime/binding/impact activation.',
    updated_by_execution_id='LF-AUTOLEARN-RUN-20260831-021',
    updated_at=now()
where operation_code='LEARNING_BRIDGE_KB_CARD_LF'
  and not source_paths @> '["gobernanza/router/learning_bridge_kb_card_lf_router_action.yaml"]'::jsonb;
