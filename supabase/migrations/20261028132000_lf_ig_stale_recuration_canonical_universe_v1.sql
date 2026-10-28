-- Controlled de-hardcoding: no change to the actual canonical full-universe
-- readiness contract. The registry is authoritative, and this run is pinned
-- to its predecessor's universe rule ID. No selector bypass, no scope broadening.
DO $guard$
DECLARE v_oid oid:=to_regprocedure('programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)');
BEGIN
 IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid))<>'97880c062e8c96253bcbae31cedd6f8c'
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_oid)
    OR pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=v_oid))<>'postgres'
 THEN RAISE EXCEPTION 'IG_STALE_RECURATION_UNIVERSE_BASELINE_DRIFT'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_recurate_source_stale_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_parent_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_parent programacion.input_readiness_runs%rowtype; v_contract_schema integer; v_contract_revision text; v_curator_component bigint; v_new bigint; v_family text; v_class jsonb; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_prop jsonb; v_payload jsonb; v_delta jsonb; v_changed integer:=0; v_affected integer:=0; v_successor_required boolean:=false; v_resolution_errors integer:=0; v_graph jsonb;
  v_freshness jsonb; v_evidence jsonb; v_subject jsonb; v_threat jsonb; v_semantic_sha text; v_curator_sha text;
  v_family_list jsonb; v_rule_code text; v_registry_rule text; v_registry_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text,0));
  if p_curator_identity !~ '^INPUT_CURATOR:(EDGE:input-governance-curator-v1|SQL:ig-governed-dispatch-v1):[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select * into v_parent from programacion.input_readiness_runs where id=p_parent_run_id and version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null;
  if not found then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_INVALID:%',p_parent_run_id; end if;
  if p_parent_run_id is distinct from (select id from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' order by id desc limit 1) then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_NOT_LATEST:%',p_parent_run_id; end if;
  v_delta:=case
    when (nullif(current_setting('lf.input_request_freshness_delta_cached_v1',true),'')::jsonb->>'run_id')::bigint
         is not distinct from p_parent_run_id
     and (nullif(current_setting('lf.input_request_freshness_delta_cached_v1',true),'')::jsonb->>'pantalla_id')::integer
         is not distinct from p_pantalla_id
    then nullif(current_setting('lf.input_request_freshness_delta_cached_v1',true),'')::jsonb->'delta'
    else programacion.fn_input_freshness_delta(p_parent_run_id) end; v_changed:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0); v_affected:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0); v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);
  select count(*) into v_resolution_errors from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value) where x.value->>'state'='RESOLUTION_ERROR';
  if v_delta->>'run_state'<>'STALE' or v_changed<=0 or v_affected<=0 or v_successor_required or v_resolution_errors<>0 then raise exception 'INPUT_SOURCE_STALE_RECURATION_PROOF_INVALID:run=% summary=%',p_parent_run_id,v_delta->'summary'; end if;
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_RECURATION_CONTRACT_REVISION_UNSUPPORTED:%',v_contract_revision; end if;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR'; if v_curator_component is null then raise exception 'INPUT_CURATOR_COMPONENT_UNRESOLVED'; end if;
  -- Universe binding derives from the current governed registry AND the
  -- exact predecessor's universe_rule_id, never a screen-specific literal.
  -- A stale source or cardinality drift must fail before any successor INSERT.
  select r.codigo,r.valor_config->'families',
         c.especificacion->>'canonical_universe_rule',
         (c.especificacion->>'family_count')::integer
    into v_rule_code,v_family_list,v_registry_rule,v_registry_count
  from lf_ops.reglas r
  join programacion.contratos c
    on c.version_id=v_version
   and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
   and c.estado='defined' and c.fail_closed
  where r.id=v_parent.universe_rule_id
  order by c.id desc limit 1;
  if v_rule_code is null
     or v_rule_code is distinct from v_registry_rule
     or jsonb_typeof(v_family_list) is distinct from 'array'
     or v_registry_count is null or v_registry_count<=0
     or jsonb_array_length(v_family_list)<>v_registry_count
     or v_parent.family_count<>v_registry_count
     or exists (
       select 1 from jsonb_array_elements(v_family_list) x(value)
       where jsonb_typeof(x.value)<>'string'
     )
     or (
       select count(*) from jsonb_array_elements_text(v_family_list) x(value)
     ) <> (
       select count(distinct x.value) from jsonb_array_elements_text(v_family_list) x(value)
     )
  then
    raise exception 'IG_STALE_RECURATION_CANONICAL_UNIVERSE_BINDING_INVALID:parent=%',v_parent.id;
  end if;
  -- The registry and the exact predecessor must agree on the entire
  -- family identity set, not merely the count. Stable cardinality with
  -- replacement family still fails closed. Pin the original universe SHA.
  if exists (
       select x.code
       from jsonb_object_keys(
         (select c.especificacion->'families'
          from programacion.contratos c
          where c.version_id=v_version
            and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
            and c.estado='defined' and c.fail_closed
          order by c.id desc limit 1)
       ) x(code)
       except
       select y.value from jsonb_array_elements_text(v_family_list) y(value)
     )
     or exists (
       select y.value from jsonb_array_elements_text(v_family_list) y(value)
       except
       select x.code
       from jsonb_object_keys(
         (select c.especificacion->'families'
          from programacion.contratos c
          where c.version_id=v_version
            and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
            and c.estado='defined' and c.fail_closed
          order by c.id desc limit 1)
       ) x(code)
     )
     or programacion.fn_v09_sha256_jsonb(
       jsonb_build_object('rule_code',v_rule_code,'families',v_family_list)
     ) is distinct from v_parent.universe_snapshot_sha256
  then
    raise exception 'IG_STALE_RECURATION_CANONICAL_UNIVERSE_SNAPSHOT_DRIFT:parent=%',v_parent.id;
  end if;
  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_parent.version_id,v_parent.pantalla_id,v_parent.universe_rule_id,v_parent.id,'CURATING',v_parent.scope || jsonb_build_object('mode','RUNTIME_GOVERNED_RECURATION_V2','parent_run_id',v_parent.id,'reason','SOURCE_STALE_RECURATION','successor_strategy','REBUILD_CHANGED_SOURCES','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','source_stale_proof','INPUT_FRESHNESS_DELTA_V1','source_stale_affected_family_count',v_affected,'classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT','promotion_authorized',false,'production_authorized',false),v_parent.universe_snapshot_sha256,v_parent.family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_new;
  for v_family in select value from jsonb_array_elements_text(v_family_list) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph);
    v_freshness:=jsonb_build_object('mode','DB_MANIFEST_V'||v_contract_schema::text,'status','PENDING_RUN_SNAPSHOT');
    v_subject:=case when v_family in ('DESIGN_SYSTEM','SECURITY') then programacion.fn_input_subject_depth_expected(p_pantalla_id,v_family) else '[]'::jsonb end;
    v_threat:=case when v_family='SECURITY' then programacion.fn_input_security_threat_expected(p_pantalla_id) else '[]'::jsonb end;
    v_semantic_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',v_family,'subject_coverage',v_subject,'threat_coverage',v_threat));
    v_evidence:=jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'parent_run_id',v_parent.id,'direct_source_readback',true,'semantic_policy','GOVERNED_RECURATION_FROM_CANONICAL_SOURCES','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe','source_stale_proof','INPUT_FRESHNESS_DELTA_V1','classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT','semantic_depth_sha256',v_semantic_sha);
    v_curator_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('run_id',v_new,'family_code',v_family,'severity',v_class->>'severity','applicability',v_class->>'applicability','coverage_status',v_class->>'coverage_status','well_defined_status',v_class->>'well_defined_status','story_ready_status',v_class->>'story_ready_status','implementation_ready_status',v_class->>'implementation_ready_status','qa_ready_status',v_class->>'qa_ready_status','production_ready_status',v_class->>'production_ready_status','source_refs',v_class->'source_refs','rationale',v_class->>'rationale','blockers',v_class->'blockers','negative_requirements',v_class->'negative_requirements','test_obligations',v_class->'test_obligations','freshness',v_freshness,'curator_evidence',v_evidence,'subject_coverage',v_subject,'threat_coverage',v_threat,'semantic_depth_sha256',v_semantic_sha));
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_new,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations',v_freshness,v_evidence,v_curator_sha,'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,v_subject,v_threat,v_semantic_sha);
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_new; if v_count<>v_registry_count then raise exception 'INPUT_RECURATION_UNIVERSE_INCOMPLETE expected=% actual=%',v_registry_count,v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_new);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent.id,'pantalla_id',p_pantalla_id,'family_count',v_registry_count,'required_role','INPUT_VALIDATOR','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'source_stale_proof','INPUT_FRESHNESS_DELTA_V1','affected_family_count',v_affected,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;
DO $verify$
DECLARE v_oid oid:='programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure;
DECLARE v_def text:=pg_get_functiondef(v_oid);
BEGIN
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_oid)
    OR position('IG_STALE_RECURATION_CANONICAL_UNIVERSE_BINDING_INVALID' IN v_def)=0
    OR position('v_parent.universe_rule_id' IN v_def)=0
    OR position('v_registry_count' IN v_def)=0
    OR position('IG_STALE_RECURATION_CANONICAL_UNIVERSE_SNAPSHOT_DRIFT' IN v_def)=0
    OR position('B2B-RULE-STORY-READINESS-001' IN v_def)>0
 THEN RAISE EXCEPTION 'IG_STALE_RECURATION_UNIVERSE_POSTCHECK_FAILED'; END IF;
END $verify$;
