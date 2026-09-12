-- LF Input Governance positive human escalation authority v1
-- GOV-015 recurrence: pending_decision marker alone is not owner escalation authority.
-- Terminal runs remain immutable; currentness is superseded by a remediation policy revision.

update transversal.decision_log
set decision = decision || ' HUMAN_DECISION_REQUIRED requiere autoridad positiva explícita de owner escalation; pendiente_decision, evidencia faltante o candidato técnico por sí solos permanecen en remediación interna.',
    impacto = impacto || ' Owner escalation is fail-closed: no positive authority => internal remediation, not user interruption.'
where adr='DEC-INPUT-GOV-SELF-REMEDIATE-001'
  and decision not like '%autoridad positiva explícita de owner escalation%';

update programacion.contratos
set especificacion=jsonb_set(
  jsonb_set(especificacion,'{remediation_loop,owner_escalation}','"POSITIVE_OWNER_AUTHORITY_ONLY"'::jsonb,true),
  '{remediation_loop,policy_revision}','"POSITIVE_OWNER_AUTHORITY_V1"'::jsonb,true
)
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT';

create or replace function programacion.fn_input_governance_materialize_gap_proposals_v1(p_run_id bigint)
returns jsonb language plpgsql security definer set search_path=pg_catalog,programacion as $function$
declare
  v_run record; a record; b jsonb; v_gap text; v_kind text; v_class text;
  v_positive_owner_authority boolean; v_count int:=0; v_human int:=0; v_auto int:=0;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_REMEDIATION_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status<>'CURATING' then raise exception 'INPUT_REMEDIATION_REQUIRES_CURATING:%',p_run_id; end if;
  for a in select * from programacion.input_family_assessments where run_id=p_run_id and jsonb_array_length(blockers)>0 order by family_code,id loop
    for b in select value from jsonb_array_elements(a.blockers) loop
      v_gap:=coalesce(b->>'code','UNSPECIFIED_GAP');
      if a.family_code in ('PROFILES','PERMISSIONS','FEATURE_FLAGS','I18N_FORMATS') then v_class:='APPLICABILITY_AUTHORITY_GAP';
      elsif a.story_ready_status='READY' then v_class:='STAGE_SPECIFIC_GAP';
      elsif v_gap ~ '(EVIDENCE|AUTHORITY|PROVENANCE)' then v_class:='GOVERNANCE_EVIDENCE_GAP';
      else v_class:='FUNCTIONAL_DEFINITION_GAP'; end if;

      v_positive_owner_authority:=coalesce((b->>'owner_decision_required')::boolean,false)
        and nullif(b->>'owner_decision_authority','') is not null;

      if v_positive_owner_authority then v_kind:='HUMAN_DECISION_REQUIRED';
      elsif v_gap ~ '(CONFLICT|RECONCILIATION)' then v_kind:='SOURCE_CONFLICT';
      elsif coalesce((a.curator_evidence->'bootstrap_probe'->>'pending_decision_count')::int,0)>0 then v_kind:='RESEARCH_REQUIRED';
      else v_kind:='SOURCE_INCOMPLETE'; end if;

      insert into programacion.input_gap_proposals(
        run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,
        source_refs,evidence_refs,confidence,stage_impact,contradictions_checked,status,curator_identity,curator_execution_id
      ) values(
        p_run_id,a.id,a.family_code,v_gap,v_kind,
        jsonb_build_object(
          'gap_classification',v_class,
          'agent_action',case
            when v_kind='HUMAN_DECISION_REQUIRED' then 'ESCALATE_AFTER_VALIDATION'
            when a.family_code='DESIGN_SYSTEM' then 'SEARCH_AND_VALIDATE_EXISTING_CANONICAL_BINDING_BEFORE_ESCALATION'
            when v_kind='RESEARCH_REQUIRED' then 'RESOLVE_PENDING_SOURCE_OR_EVIDENCE_INTERNALLY'
            else 'KEEP_IN_INTERNAL_REMEDIATION_QUEUE' end,
          'blocker',b,'positive_owner_escalation_authority',v_positive_owner_authority,
          'pending_marker_is_not_owner_authority',true,'no_invention',true,
          'proposal_is_canonical_source',false,'automatic_canonicalization','DENY',
          'analysis_revision',coalesce(v_run.scope->>'analysis_revision','INPUT_GOV_REMEDIATION_1_3'),
          'remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1'
        ),
        jsonb_build_object('pantalla_id',v_run.pantalla_id,'family_code',a.family_code),
        a.source_refs,'[]'::jsonb,case when v_positive_owner_authority then 1.0 else 0.9 end,
        jsonb_build_object('story',a.story_ready_status,'implementation',a.implementation_ready_status,'qa',a.qa_ready_status,'production',a.production_ready_status),
        jsonb_build_array('GOV-015_CLASSIFICATION_APPLIED','POSITIVE_OWNER_AUTHORITY_REQUIRED','NO_PROPOSAL_AS_CANONICAL_SOURCE'),
        'PROPOSED',v_run.curator_identity,coalesce(a.curator_evidence->>'execution_id','UNKNOWN')
      ) on conflict (run_id,family_code,gap_code) do nothing;
      if found then v_count:=v_count+1; if v_kind='HUMAN_DECISION_REQUIRED' then v_human:=v_human+1; else v_auto:=v_auto+1; end if; end if;
    end loop;
  end loop;
  return jsonb_build_object('run_id',p_run_id,'proposal_count',v_count,'internal_remediation_count',v_auto,'human_decision_candidate_count',v_human,'owner_escalation_policy','POSITIVE_OWNER_AUTHORITY_ONLY','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1');
end;
$function$;

create or replace function programacion.fn_input_readiness_run_is_current(p_run_id bigint)
returns boolean language plpgsql security definer set search_path=pg_catalog,programacion as $function$
declare
  v_run record; v_current_manifest jsonb; v_current_sha text; v_contract_schema integer; v_contract_revision text;
  v_contract_payload jsonb; v_contract_sha text; v_has_terminal_successor boolean; v_analysis_revision text; v_policy_revision text;
begin
  select r.status,r.version_id,r.contract_version,r.contract_revision,r.contract_snapshot_sha256,r.source_manifest,r.source_snapshot_sha256,r.invalidated_at,r.scope into v_run
  from programacion.input_readiness_runs r where r.id=p_run_id;
  if not found then return false; end if;
  if v_run.status<>'COMPLETED' or v_run.source_snapshot_sha256 is null or v_run.invalidated_at is not null then return false; end if;
  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)
  into v_contract_schema,v_contract_revision,v_contract_payload from programacion.contratos c where c.version_id=v_run.version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  if v_contract_schema is null or v_contract_revision is null then return false; end if;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_run.contract_version<>v_contract_schema or v_run.contract_revision is distinct from v_contract_revision or v_run.contract_snapshot_sha256 is distinct from v_contract_sha then return false; end if;
  if coalesce(v_run.scope->>'mode','') in ('GOVERNED_CANONICAL_BOOTSTRAP_V1','RUNTIME_GOVERNED_RECURATION_V2') then
    select especificacion->>'analysis_revision',especificacion->'remediation_loop'->>'policy_revision'
    into v_analysis_revision,v_policy_revision from programacion.contratos
    where version_id=v_run.version_id and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined' and fail_closed;
    if v_analysis_revision is null or v_run.scope->>'analysis_revision' is distinct from v_analysis_revision then return false; end if;
    if v_policy_revision is not null and v_run.scope->>'remediation_policy_revision' is distinct from v_policy_revision then return false; end if;
  end if;
  select exists(select 1 from programacion.input_readiness_runs n where n.supersedes_run_id=p_run_id and n.status in ('COMPLETED','BLOCKED')) into v_has_terminal_successor;
  if v_has_terminal_successor then return false; end if;
  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id); v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  return v_current_sha=v_run.source_snapshot_sha256 and v_current_manifest=v_run.source_manifest;
end;
$function$;

create or replace function programacion.fn_input_governance_recurate_v2(p_pantalla_id integer,p_consumer text,p_curator_identity text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,programacion,lf_ops,transversal as $function$
declare
  v_parent record; v_contract_schema int; v_contract_revision text; v_curator_component bigint; v_new bigint; v_family text;
  v_class jsonb; v_count int; v_exec_id text:=gen_random_uuid()::text; v_prop jsonb; v_payload jsonb;
begin
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select * into v_parent from programacion.input_readiness_runs where version_id=19 and pantalla_id=p_pantalla_id and status='COMPLETED' order by id desc limit 1;
  if not found then return programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id,p_consumer,p_curator_identity); end if;
  if programacion.fn_input_readiness_run_is_current(v_parent.id) then return jsonb_build_object('status','NOOP_CURRENT','run_id',v_parent.id,'required_role','NONE','promotion_authorized',false,'production_authorized',false); end if;
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  if v_contract_revision<>'5.12' then raise exception 'INPUT_RECURATION_CONTRACT_REVISION_UNSUPPORTED:%',v_contract_revision; end if;
  select id into v_curator_component from programacion.componentes where version_id=19 and componente_codigo='INPUT_CURATOR';
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_parent.version_id,v_parent.pantalla_id,v_parent.universe_rule_id,v_parent.id,'CURATING',v_parent.scope || jsonb_build_object('mode','RUNTIME_GOVERNED_RECURATION_V2','parent_run_id',v_parent.id,'analysis_revision','INPUT_GOV_REMEDIATION_1_3','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_parent.universe_snapshot_sha256,v_parent.family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_new;
  for v_family in select value from jsonb_array_elements_text((select valor_config->'families' from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001')) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,19);
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_new,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations','{}'::jsonb,jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'parent_run_id',v_parent.id,'direct_source_readback',true,'semantic_policy','GOVERNED_RECURATION_FROM_CANONICAL_SOURCES','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_3','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe'),repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64));
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_new; if v_count<>47 then raise exception 'INPUT_RECURATION_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_new);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent.id,'pantalla_id',p_pantalla_id,'family_count',47,'required_role','INPUT_VALIDATOR','analysis_revision','INPUT_GOV_REMEDIATION_1_3','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

-- Ensure new-screen bootstrap also carries the remediation policy revision without duplicating bootstrap logic.
create or replace function programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id integer,p_consumer text,p_curator_identity text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,programacion,lf_ops,transversal as $function$
declare
  v_version bigint:=19; v_code text; v_active boolean; v_pre jsonb; v_existing bigint; v_existing_status text;
  v_rule_id integer; v_families jsonb; v_family_count integer; v_universe_sha text; v_contract_schema integer; v_contract_revision text;
  v_curator_component bigint; v_run bigint; v_class jsonb; v_family text; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb; v_prop jsonb;
begin
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null); if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;
  select id,status into v_existing,v_existing_status from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_existing_status in ('CURATING','VALIDATING') then return jsonb_build_object('status',case when v_existing_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,'run_id',v_existing,'required_role',case when v_existing_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,'promotion_authorized',false,'production_authorized',false); end if;
  if exists(select 1 from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED') then raise exception 'BOOTSTRAP_REQUIRES_NO_COMPLETED_PREDECESSOR:%',p_pantalla_id; end if;
  select id,valor_config->'families' into v_rule_id,v_families from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001'; v_family_count:=jsonb_array_length(v_families); v_universe_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('rule_code','B2B-RULE-STORY-READINESS-001','families',v_families));
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR'; if v_rule_id is null or v_family_count<>47 or v_contract_revision<>'5.12' or v_curator_component is null then raise exception 'BOOTSTRAP_GOVERNANCE_DEPENDENCY_UNRESOLVED'; end if;
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_version,p_pantalla_id,v_rule_id,null,'CURATING',jsonb_build_object('mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','decision','DEC-INPUT-GOV-BOOTSTRAP-001','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_3','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_universe_sha,v_family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_run;
  for v_family in select value from jsonb_array_elements_text(v_families) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,v_version);
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_run,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations','{}'::jsonb,jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'direct_source_readback',true,'semantic_policy','GOVERNED_CANONICAL_BOOTSTRAP_NO_INVENTION','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_3','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe'),repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64));
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_run; if v_count<>47 then raise exception 'BOOTSTRAP_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_run);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_run,'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',47,'required_role','INPUT_VALIDATOR','write_performed',true,'bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','analysis_revision','INPUT_GOV_REMEDIATION_1_3','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

-- Old run remains immutable but must no longer be current under the new remediation policy.
do $block$
begin
  if programacion.fn_input_readiness_run_is_current(195) then raise exception 'GOV015_POLICY_REVISION_DID_NOT_STALE_RUN195'; end if;
end;
$block$;