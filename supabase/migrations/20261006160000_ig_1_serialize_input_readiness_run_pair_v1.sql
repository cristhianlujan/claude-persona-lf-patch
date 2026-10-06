-- IG-1 candidate — owner review required before apply.
-- Root incident: duplicate canonical runs 518/519 for (19,48) and 521/522 for (19,50).
-- Serialize (version_id,pantalla_id) before any bootstrap/recurate/rebind decision or run creation.
-- pg_advisory_xact_lock is transaction-scoped and therefore releases on commit/rollback.

-- Concurrency qualification assumption: PostgreSQL READ COMMITTED.
-- Verified in LF_SUPABASE_SANDBOX before apply: both default_transaction_isolation and
-- transaction_isolation are 'read committed'. IG-1 relies on the pair advisory xact lock
-- to serialize decision/create under that isolation level; other isolation levels are not
-- qualified by this migration.

-- Fail closed if any protected base definition moved since owner authorization.
DO $ig1_base_md5$
DECLARE
  v_actual text;
BEGIN
  v_actual := md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM 'fcf1afe1fd1abf3b241c7aa8b54a5fd0' THEN
    RAISE EXCEPTION 'IG1_BASE_MD5_MISMATCH function=bootstrap_materialize_v1 expected=% actual=%',
      'fcf1afe1fd1abf3b241c7aa8b54a5fd0', coalesce(v_actual,'<NULL>');
  END IF;

  v_actual := md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM 'cef03aa0d7595345e2f048e9dad4be69' THEN
    RAISE EXCEPTION 'IG1_BASE_MD5_MISMATCH function=bootstrap_materialize_v2 expected=% actual=%',
      'cef03aa0d7595345e2f048e9dad4be69', coalesce(v_actual,'<NULL>');
  END IF;

  v_actual := md5(pg_get_functiondef('programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure));
  IF v_actual IS DISTINCT FROM '996a6b3c0fc095ec714a70251adc14ef' THEN
    RAISE EXCEPTION 'IG1_BASE_MD5_MISMATCH function=recurate_source_stale_v1 expected=% actual=%',
      '996a6b3c0fc095ec714a70251adc14ef', coalesce(v_actual,'<NULL>');
  END IF;

  v_actual := md5(pg_get_functiondef('programacion.fn_input_governance_recurate_v2(integer,text,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM '0d389a7c037b1498d2641da14df0437a' THEN
    RAISE EXCEPTION 'IG1_BASE_MD5_MISMATCH function=recurate_v2 expected=% actual=%',
      '0d389a7c037b1498d2641da14df0437a', coalesce(v_actual,'<NULL>');
  END IF;

  v_actual := md5(pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure));
  IF v_actual IS DISTINCT FROM '382c9cac4f0a47598a3116c48eee4d92' THEN
    RAISE EXCEPTION 'IG1_BASE_MD5_MISMATCH function=curator_rebind_v1 expected=% actual=%',
      '382c9cac4f0a47598a3116c48eee4d92', coalesce(v_actual,'<NULL>');
  END IF;
END
$ig1_base_md5$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_materialize_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_version bigint:=19; v_code text; v_active boolean; v_pre jsonb; v_existing bigint; v_existing_status text; v_rule_id integer; v_families jsonb; v_family_count integer;
  v_universe_sha text; v_contract_schema integer; v_contract_revision text; v_curator_component bigint; v_run bigint; v_class jsonb; v_family text; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb;
begin
  -- IG-1: serialize the canonical run decision/create boundary for this exact pair.
  -- Transaction-scoped: automatically released on commit/rollback; re-entrant in nested successor paths.
  perform pg_advisory_xact_lock(
    hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text, 0)
  );
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null); if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;
  select id,status into v_existing,v_existing_status from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_existing_status in ('CURATING','VALIDATING') then return jsonb_build_object('status',case when v_existing_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,'run_id',v_existing,'required_role',case when v_existing_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,'promotion_authorized',false,'production_authorized',false); end if;
  if exists(select 1 from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED') then raise exception 'BOOTSTRAP_REQUIRES_NO_COMPLETED_PREDECESSOR:%',p_pantalla_id; end if;
  select id,valor_config->'families' into v_rule_id,v_families from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001'; v_family_count:=jsonb_array_length(v_families);
  v_universe_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('rule_code','B2B-RULE-STORY-READINESS-001','families',v_families));
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR';
  if v_rule_id is null or v_family_count<>47 or v_contract_revision is distinct from (programacion.fn_input_contract_clause_v1(v_version,'INPUT_READINESS_CONTRACT',array['family_stage_requirements'])->>'contract_revision') or v_curator_component is null then raise exception 'BOOTSTRAP_GOVERNANCE_DEPENDENCY_UNRESOLVED'; end if;
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_version,p_pantalla_id,v_rule_id,null,'CURATING',jsonb_build_object('mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','decision','DEC-INPUT-GOV-BOOTSTRAP-001','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_universe_sha,v_family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_run;
  for v_family in select value from jsonb_array_elements_text(v_families) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id,v_family,v_version);
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_run,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations','{}'::jsonb,jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'direct_source_readback',true,'semantic_policy','GOVERNED_CANONICAL_BOOTSTRAP_NO_INVENTION','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe'),repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64));
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_run; if v_count<>47 then raise exception 'BOOTSTRAP_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_run,'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',47,'required_role','INPUT_VALIDATOR','write_performed',true,'bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id integer, p_consumer text, p_curator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'); v_code text; v_active boolean; v_pre jsonb; v_existing bigint; v_existing_status text;
  v_rule_id integer; v_families jsonb; v_family_count integer; v_universe_sha text; v_contract_schema integer; v_contract_revision text;
  v_curator_component bigint; v_run bigint; v_class jsonb; v_family text; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb; v_prop jsonb;
begin
  -- IG-1: serialize the canonical run decision/create boundary for this exact pair.
  -- Transaction-scoped: automatically released on commit/rollback; re-entrant in nested successor paths.
  perform pg_advisory_xact_lock(
    hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text, 0)
  );
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null); if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;
  select id,status into v_existing,v_existing_status from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_existing_status in ('CURATING','VALIDATING') then return jsonb_build_object('status',case when v_existing_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,'run_id',v_existing,'required_role',case when v_existing_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,'promotion_authorized',false,'production_authorized',false); end if;
  if exists(select 1 from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED') then raise exception 'BOOTSTRAP_REQUIRES_NO_COMPLETED_PREDECESSOR:%',p_pantalla_id; end if;
  select id,valor_config->'families' into v_rule_id,v_families from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001'; v_family_count:=jsonb_array_length(v_families); v_universe_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('rule_code','B2B-RULE-STORY-READINESS-001','families',v_families));
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR'; if v_rule_id is null or v_family_count<>47 or v_contract_revision is null or v_curator_component is null then raise exception 'BOOTSTRAP_GOVERNANCE_DEPENDENCY_UNRESOLVED'; end if;
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_version,p_pantalla_id,v_rule_id,null,'CURATING',jsonb_build_object('mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','decision','DEC-INPUT-GOV-BOOTSTRAP-001','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_universe_sha,v_family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_run;
  for v_family in select value from jsonb_array_elements_text(v_families) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,v_version);
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_run,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations','{}'::jsonb,jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'direct_source_readback',true,'semantic_policy','GOVERNED_CANONICAL_BOOTSTRAP_NO_INVENTION','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe'),repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64));
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_run; if v_count<>47 then raise exception 'BOOTSTRAP_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_run);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_run,'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',47,'required_role','INPUT_VALIDATOR','write_performed',true,'bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_recurate_source_stale_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_parent_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_parent programacion.input_readiness_runs%rowtype;
  v_contract_schema integer;
  v_contract_revision text;
  v_curator_component bigint;
  v_new bigint;
  v_family text;
  v_class jsonb;
  v_count integer;
  v_exec_id text:=gen_random_uuid()::text;
  v_prop jsonb;
  v_payload jsonb;
  v_delta jsonb;
  v_changed integer:=0;
  v_affected integer:=0;
  v_successor_required boolean:=false;
  v_resolution_errors integer:=0;
  v_graph jsonb;
begin
  -- IG-1: serialize the canonical run decision/create boundary for this exact pair.
  -- Transaction-scoped: automatically released on commit/rollback; re-entrant in nested successor paths.
  perform pg_advisory_xact_lock(
    hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text, 0)
  );
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID';
  end if;
  if not exists(
    select 1
    from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v)
    where x.v=p_consumer
  ) then
    raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>');
  end if;

  select * into v_parent
  from programacion.input_readiness_runs
  where id=p_parent_run_id
    and version_id=v_version
    and pantalla_id=p_pantalla_id
    and status='COMPLETED'
    and invalidated_at is null;
  if not found then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_INVALID:%',p_parent_run_id; end if;
  if p_parent_run_id is distinct from (
    select id from programacion.input_readiness_runs
    where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED'
    order by id desc limit 1
  ) then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_NOT_LATEST:%',p_parent_run_id; end if;

  v_delta:=programacion.fn_input_freshness_delta(p_parent_run_id);
  v_changed:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0);
  v_affected:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0);
  v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);
  select count(*) into v_resolution_errors
  from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value)
  where x.value->>'state'='RESOLUTION_ERROR';

  if v_delta->>'run_state'<>'STALE'
     or v_changed<=0
     or v_affected<=0
     or v_successor_required
     or v_resolution_errors<>0 then
    raise exception 'INPUT_SOURCE_STALE_RECURATION_PROOF_INVALID:run=% summary=%',p_parent_run_id,v_delta->'summary';
  end if;

  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision'
    into v_contract_schema,v_contract_revision
  from programacion.contratos
  where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_RECURATION_CONTRACT_REVISION_UNSUPPORTED:%',v_contract_revision; end if;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR';
  if v_curator_component is null then raise exception 'INPUT_CURATOR_COMPONENT_UNRESOLVED'; end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);

  insert into programacion.input_readiness_runs(
    version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,
    universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id
  ) values(
    v_parent.version_id,v_parent.pantalla_id,v_parent.universe_rule_id,v_parent.id,'CURATING',
    v_parent.scope || jsonb_build_object(
      'mode','RUNTIME_GOVERNED_RECURATION_V2','parent_run_id',v_parent.id,
      'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
      'remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001',
      'remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1',
      'runtime','input-governance-curator-v1',
      'source_stale_proof','INPUT_FRESHNESS_DELTA_V1',
      'source_stale_affected_family_count',v_affected,
      'classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT',
      'promotion_authorized',false,'production_authorized',false
    ),
    v_parent.universe_snapshot_sha256,v_parent.family_count,v_contract_schema,p_curator_identity,v_curator_component
  ) returning id into v_new;

  for v_family in
    select value from jsonb_array_elements_text((select valor_config->'families' from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001'))
  loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph);
    insert into programacion.input_family_assessments(
      run_id,family_code,severity,applicability,coverage_status,well_defined_status,
      story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
      source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,
      curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,
      validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256
    ) values(
      v_new,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',
      v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',
      v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations','{}'::jsonb,
      jsonb_build_object(
        'component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR',
        'runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,
        'parent_run_id',v_parent.id,'direct_source_readback',true,'semantic_policy','GOVERNED_RECURATION_FROM_CANONICAL_SOURCES',
        'remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
        'remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256',
        'bootstrap_probe',v_class->'probe','source_stale_proof','INPUT_FRESHNESS_DELTA_V1','classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT'
      ),
      repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64)
    );
  end loop;

  select count(*) into v_count from programacion.input_family_assessments where run_id=v_new;
  if v_count<>47 then raise exception 'INPUT_RECURATION_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_new);
  v_payload:=jsonb_build_object(
    'status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent.id,'pantalla_id',p_pantalla_id,
    'family_count',47,'required_role','INPUT_VALIDATOR','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
    'remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,
    'source_stale_proof','INPUT_FRESHNESS_DELTA_V1','affected_family_count',v_affected,
    'promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_recurate_v2(p_pantalla_id integer, p_consumer text, p_curator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_parent record; v_contract_schema int; v_contract_revision text; v_curator_component bigint; v_new bigint; v_family text;
  v_class jsonb; v_count int; v_exec_id text:=gen_random_uuid()::text; v_prop jsonb; v_payload jsonb;
begin
  -- IG-1: serialize the canonical run decision/create boundary for this exact pair.
  -- Transaction-scoped: automatically released on commit/rollback; re-entrant in nested successor paths.
  perform pg_advisory_xact_lock(
    hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text, 0)
  );
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select * into v_parent from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' order by id desc limit 1;
  if not found then return programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id,p_consumer,p_curator_identity); end if;
  if programacion.fn_input_readiness_run_is_current(v_parent.id) then return jsonb_build_object('status','NOOP_CURRENT','run_id',v_parent.id,'required_role','NONE','promotion_authorized',false,'production_authorized',false); end if;
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_RECURATION_CONTRACT_REVISION_UNSUPPORTED:%',v_contract_revision; end if;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR';
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_parent.version_id,v_parent.pantalla_id,v_parent.universe_rule_id,v_parent.id,'CURATING',v_parent.scope || jsonb_build_object('mode','RUNTIME_GOVERNED_RECURATION_V2','parent_run_id',v_parent.id,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_parent.universe_snapshot_sha256,v_parent.family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_new;
  for v_family in select value from jsonb_array_elements_text((select valor_config->'families' from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001')) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,v_version);
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_new,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations','{}'::jsonb,jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'parent_run_id',v_parent.id,'direct_source_readback',true,'semantic_policy','GOVERNED_RECURATION_FROM_CANONICAL_SOURCES','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe'),repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64));
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_new; if v_count<>47 then raise exception 'INPUT_RECURATION_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_new);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent.id,'pantalla_id',p_pantalla_id,'family_count',47,'required_role','INPUT_VALIDATOR','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_curator_component_id bigint;
  v_component_count integer;
  v_code text;
  v_active boolean;
  v_current bigint;
  v_latest bigint;
  v_latest_status text;
  v_parent bigint;
  v_new bigint;
  v_contract_schema integer;
  v_contract_revision text;
  v_contract_sha text;
  v_parent_contract_sha text;
  v_family_count integer;
  v_assessed integer;
  v_pre jsonb;
  a record;
  v_payload jsonb;
  v_classifier jsonb;
begin
  -- IG-1: serialize the canonical run decision/create boundary for this exact pair.
  -- Transaction-scoped: automatically released on commit/rollback; re-entrant in nested successor paths.
  perform pg_advisory_xact_lock(
    hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text, 0)
  );
  select count(*),min(id)
    into v_component_count,v_curator_component_id
  from programacion.componentes
  where version_id=v_version and componente_codigo='INPUT_CURATOR';
  if v_component_count<>1 then
    raise exception 'INPUT_GOVERNANCE_CURATOR_COMPONENT_BINDING_AMBIGUOUS_OR_MISSING version=% count=%',v_version,v_component_count;
  end if;

  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID';
  end if;
  if not exists(
    select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v)
    where x.v=p_consumer
  ) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;

  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;

  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;

  select id into v_current from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(id)
  order by id desc limit 1;
  if v_current is not null and not p_force_selftest then
    return jsonb_build_object('status','NOOP_CURRENT','run_id',v_current,'required_role','NONE','promotion_authorized',false,'production_authorized',false);
  end if;

  select id,status into v_latest,v_latest_status from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_latest is not null and v_latest_status in ('CURATING','VALIDATING') and not p_force_selftest then
    return jsonb_build_object(
      'status',case when v_latest_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,
      'run_id',v_latest,
      'required_role',case when v_latest_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,
      'promotion_authorized',false,'production_authorized',false
    );
  end if;

  select id,contract_snapshot_sha256,family_count into v_parent,v_parent_contract_sha,v_family_count
  from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED'
  order by id desc limit 1;
  if v_parent is null then
    v_payload:=jsonb_build_object(
      'status','BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED','pantalla_id',p_pantalla_id,'screen_code',v_code,
      'required_role','HUMAN_OR_GOVERNED_SEMANTIC_BOOTSTRAP','write_performed',false,
      'reason','NO_COMPLETED_PREDECESSOR_TO_REBIND','proposal_is_canonical_source',false,
      'promotion_authorized',false,'production_authorized',false
    );
    return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',
         programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion))
  into v_contract_schema,v_contract_revision,v_contract_sha
  from programacion.contratos c
  where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_READINESS_CONTRACT_NOT_RESOLVABLE:%',v_version; end if;
  if v_parent_contract_sha is distinct from v_contract_sha then
    if v_contract_revision is not null then
      return programacion.fn_input_governance_recurate_v2(p_pantalla_id,p_consumer,p_curator_identity);
    end if;
    return jsonb_build_object(
      'status','CONTRACT_CHANGED_SEMANTIC_REVIEW_REQUIRED','parent_run_id',v_parent,
      'required_role','HUMAN_OR_GOVERNED_CONTRACT_MIGRATION','write_performed',false,
      'promotion_authorized',false,'production_authorized',false
    );
  end if;

  insert into programacion.input_readiness_runs(
    version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,
    universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id
  )
  select version_id,pantalla_id,universe_rule_id,id,'CURATING',
         scope||jsonb_build_object(
           'mode','RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1','parent_run_id',id,
           'runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false
         ),
         universe_snapshot_sha256,family_count,v_contract_schema,p_curator_identity,v_curator_component_id
  from programacion.input_readiness_runs where id=v_parent
  returning id into v_new;

  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code
  loop
    v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(
      p_pantalla_id,a.family_code,v_version
    );
    insert into programacion.input_family_assessments(
      run_id,family_code,severity,applicability,coverage_status,well_defined_status,
      story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
      source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,
      curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,
      validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256
    ) values (
      v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,
      a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,
      coalesce(v_classifier->'source_refs','[]'::jsonb),a.rationale,a.blockers,a.negative_requirements,a.test_obligations,'{}'::jsonb,
      jsonb_build_object(
        'component_id',v_curator_component_id,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR',
        'runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,
        'parent_run_id',v_parent,'parent_assessment_id',a.id,'direct_source_readback',true,
        'semantic_policy','NO_INVENTION_REBIND_ONLY',
        'bootstrap_classifier_sha256',v_classifier->>'classifier_sha256'
      ),
      repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,
      a.subject_coverage,a.threat_coverage,a.semantic_depth_sha256
    );
  end loop;

  select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_new;
  if v_assessed<>v_family_count then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_UNIVERSE_INCOMPLETE expected=% actual=%',v_family_count,v_assessed; end if;

  v_payload:=jsonb_build_object(
    'status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent,
    'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',v_family_count,
    'curator_identity',p_curator_identity,'run_status','CURATING','required_role','INPUT_VALIDATOR',
    'write_performed',true,'promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$

-- Fail closed if the five protected entrypoints do not retain the lock primitive.
do $ig1_verify$
declare v_count integer;
begin
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_governance_bootstrap_materialize_v1',
      'fn_input_governance_bootstrap_materialize_v2',
      'fn_input_governance_recurate_source_stale_v1',
      'fn_input_governance_recurate_v2',
      'fn_input_governance_curator_rebind_v1'
    )
    and position('pg_advisory_xact_lock' in pg_get_functiondef(p.oid))>0;
  if v_count<>5 then
    raise exception 'IG1_SERIALIZATION_BIND_INCOMPLETE expected=5 actual=%',v_count;
  end if;
end
$ig1_verify$;
