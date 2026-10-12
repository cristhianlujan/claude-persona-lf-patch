-- IG M10.1: preventive preflight repair learned from M9.9 and M9.10.
-- Only the engineering unit's CP3 metadata and unit-local governance are changed.
-- Explicitly distinguishes sandbox consumer inventory from runtime facade migration/activation.
DO $m101_contract$
DECLARE
  v_id bigint;
  v_m jsonb;
  v_spec jsonb;
  v_gov jsonb;
  v_after jsonb;
  v_query text := $q$with source_consumers as (select distinct a.codigo_activo,a.tipo_activo,a.metadata, r.relacionado_codigo from public.lf_activo_relaciones r join public.lf_activos a on a.codigo_activo=r.codigo_activo and a.archived_at is null where r.relacionado_codigo in ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1')), eligible as (select codigo_activo,case when tipo_activo='ADAPTER' and nullif(metadata->>'input_governance_binding_contract','') is not null then 'ADAPTER' when tipo_activo='CAPABILITY' and (metadata->>'consumer_domain'='PROFILES' or metadata->>'dominio'='GOBERNANZA_PERFILES') then 'PROFILE' end as consumer_class from source_consumers), expected as (select distinct codigo_activo,consumer_class from eligible where consumer_class is not null), linked as (select e.codigo_activo,e.relacionado_codigo,e.relacion_tipo from public.lf_activo_relaciones e where e.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and e.relacion_tipo='GOBERNADO_POR') select (select count(*) from expected) eligible_count, (select count(*) from expected e join linked l using(codigo_activo)) governed_count, (select count(*) from linked l left join expected e using(codigo_activo) where e.codigo_activo is null) unauthorized_count, (select count(*) from linked l join expected e using(codigo_activo) group by l.codigo_activo having count(*)>1 limit 1) duplicate_asset_count$q$;
BEGIN
 SELECT u.id,u.unit_metadata INTO v_id,v_m
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND u.unit_code='M10.1'
   AND c.checkpoint_code='PROFILES_ADAPTERS_CONSUMERS'
   AND c.status='PENDING'
 FOR UPDATE OF u;
 IF v_id IS NULL THEN RAISE EXCEPTION 'M101_UNIT_CP3_PRESTATE_DRIFT'; END IF;
 v_spec:=v_m#>'{action_specs_v1,PROFILES_ADAPTERS_CONSUMERS}';
 IF v_spec->>'contract_family' IS DISTINCT FROM 'BOUNDED_IMPLEMENTATION_AUTHORING'
 OR v_spec->>'recipe_mode' IS DISTINCT FROM 'GIT_FIRST_MIGRATION'
 OR v_spec#>>'{authoring_contract,runtime_activation}' IS DISTINCT FROM 'NOT_IMPLIED'
 OR v_spec#>>'{assertion_contract,pass_when,implementation_written}' IS DISTINCT FROM 'true'
 OR v_m ? 'm10_1_consumer_inventory_governance_v1'
 THEN RAISE EXCEPTION 'M101_PRESTATE_CONTRACT_GOVERNANCE_DRIFT'; END IF;

 v_spec:=jsonb_set(v_spec,'{expected}',to_jsonb(
   'Sandbox engineering checkpoint: inventory all governed Profiles and Adapters dynamically from canonical asset metadata and observed relations; prove complete authorized coverage, 0 unauthorized, 0 duplicate, 0 runtime activation. Migration to facade is a DIFFERENT checkpoint, and live admission remains separately gated.'::text),true);
 v_spec:=jsonb_set(v_spec,'{verification_queries}',jsonb_build_array(v_query),true);
 v_spec:=jsonb_set(v_spec,'{assertion_contract,pass_when}',
   (v_spec#>'{assertion_contract,pass_when}')||
   jsonb_build_object('consumer_inventory_verified',true,
                      'runtime_unchanged',true,
                      'unauthorized_count',0,
                      'duplicate_count',0),true);
 v_spec:=jsonb_set(v_spec,'{authoring_contract,consumer_inventory_selection}',
   jsonb_build_object('source','public.lf_activo_relaciones + public.lf_activos.metadata',
                      'selector','GOVERNED_TYPED_ASSET_METADATA_NOT_CODE_PREFIX',
                      'coverage','DYNAMIC_ELIGIBLE_SET_MINUS_ALREADY_GOVERNED',
                      'require_active',true,
                      'require_positive_and_negative_rollback',true,
                      'prohibit_name_pattern_filter',true,
                      'batch_residue_rule','COMPARE_TO_PRESTATE_NOT_ZERO_HISTORY'),true);
 v_m:=jsonb_set(v_m,'{action_specs_v1,PROFILES_ADAPTERS_CONSUMERS}',v_spec,true);
 v_m:=jsonb_set(v_m,'{source_pack_v1,checkpoint_inputs,PROFILES_ADAPTERS_CONSUMERS,inputs,queries}',jsonb_build_array(v_query),true);
 v_gov:=jsonb_build_object(
   'schema_version','IG_M101_SANDBOX_CONSUMER_INVENTORY_GOVERNANCE_V1',
   'classification','ENGINEERING_SANDBOX_INVENTORY',
   'owner','IG_CHECKPOINT_EXECUTOR',
   'authority','LIVE_CANONICAL_ASSET_METADATA_AND_RELATIONSHIPS',
   'consumer_count','DYNAMIC_NO_FIXED_4_2_2',
   'profile_membership','GOVERNED_CONSUMER_DOMAIN_OR_DOMAIN_METADATA',
   'adapter_membership','ACTIVE_ADAPTER_WITH_INPUT_GOVERNANCE_BINDING_CONTRACT',
   'negative_control','UNBOUND_ADAPTER_AND_UNRELATED_CAPABILITY_EXCLUDED',
   'release_gate','INDEPENDENT_NOT_IMPLIED_BY_CP3_DONE',
   'router_migration_checkpoint','ROUTER_MIGRATED',
   'terminal_zero_internal_callers','NEG_INTERNAL_CALL_AND_FACADE_READBACK',
   'runtime_activation',false,
   'production_activation',false,
   'forbidden',jsonb_build_array('HARDCODED_CONSUMER_COUNT','NAME_PREFIX_AS_AUTHORITY',
    'CLAIM_ROUTER_MIGRATED_FROM_INVENTORY','CLAIM_PRODUCTION_FROM_SANDBOX',
    'REPEAT_M99_M910_LIVE_RECEIPT_DEPENDENCIES_FOR_SANDBOX'));
 v_m:=jsonb_set(v_m,'{m10_1_consumer_inventory_governance_v1}',v_gov,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_m WHERE id=v_id;
 v_after:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.1');
 IF v_after->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
   OR v_after#>>'{execution_packet,status}' IS DISTINCT FROM 'READY'
   OR v_after#>>'{action_spec,assertion_contract,pass_when,consumer_inventory_verified}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M101_POST_REPAIR_PACKET_NOT_READY: % / %',
    v_after->>'terminal_action',v_after#>>'{execution_packet,status}'; END IF;
END $m101_contract$;
