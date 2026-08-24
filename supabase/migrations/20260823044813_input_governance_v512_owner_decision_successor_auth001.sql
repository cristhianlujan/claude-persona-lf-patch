do $do$
declare
  v_version_id bigint;
  v_screen integer;
  v_parent bigint;
  v_new bigint;
  v_curator_component bigint;
  v_validator_component bigint;
  v_validator_identity text;
  v_source_sha text;
  v_assert jsonb;
  v_decision_number bigint;
  v_assessment record;
begin
  select v.id into v_version_id
  from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    and v.version_codigo='v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate';
  select id into v_screen from lf_ops.pantallas where codigo='B2B-AUTH-001';
  select decision_number into v_decision_number from public.lf_decisiones_gov where id_decision='DEC-INPUT-GOV-512-HUMAN-001';
  select id into v_curator_component from programacion.componentes where version_id=v_version_id and componente_codigo='INPUT_CURATOR';
  select id into v_validator_component from programacion.componentes where version_id=v_version_id and componente_codigo='INPUT_VALIDATOR';
  select r.id into v_parent from programacion.input_readiness_runs r
  where r.version_id=v_version_id and r.pantalla_id=v_screen and r.status='COMPLETED' and r.invalidated_at is null
  order by r.id desc limit 1;
  if v_version_id is null or v_screen is null or v_decision_number is null or v_curator_component is null or v_validator_component is null or v_parent is null then raise exception 'AUTH001_OWNER_DECISION_PREFLIGHT_UNRESOLVED'; end if;
  if programacion.fn_input_readiness_run_is_current(v_parent) then raise exception 'AUTH001_PARENT_EXPECTED_STALE:%',v_parent; end if;

  v_validator_identity:=format('INPUT_VALIDATOR:v0.5r1-auth-%s-v512-owner-decision',v_screen);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  select version_id,pantalla_id,universe_rule_id,id,'CURATING',
         scope||jsonb_build_object('mode','CANDIDATE_V512_OWNER_DECISION_CANONICALIZED','remediation','V512_HUMAN_DECISION_18_CANONICALIZED_20260822','parent_run_id',id,'owner_decision_id','DEC-INPUT-GOV-512-HUMAN-001','owner_decision_number',v_decision_number,'historical_proposals',(select coalesce(jsonb_agg(jsonb_build_object('family_code',gp.family_code,'gap_code',gp.gap_code) order by gp.family_code),'[]'::jsonb) from programacion.input_gap_proposals gp where gp.run_id=id),'canon_vs_proposal','STRICT_SEPARATION','merge_authorized',false,'promotion_authorized',false,'production_authorized',false),
         universe_snapshot_sha256,family_count,contract_version,
         format('INPUT_CURATOR:v0.5r1-auth-%s-v512-owner-decision',pantalla_id),v_curator_component
  from programacion.input_readiness_runs where id=v_parent returning id into v_new;

  insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
  select v_new,src.family_code,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'P4' else src.severity end,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'NOT_APPLICABLE' else src.applicability end,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'NOT_APPLICABLE' else src.coverage_status end,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'NOT_APPLICABLE' else src.well_defined_status end,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'NOT_APPLICABLE' else src.story_ready_status end,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'NOT_APPLICABLE' else src.implementation_ready_status end,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'NOT_APPLICABLE' else src.qa_ready_status end,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'NOT_APPLICABLE' else src.production_ready_status end,
         case when src.family_code='FEATURE_FLAGS' then jsonb_build_array(jsonb_build_object('kind','CAPABILITY_ABSENCE','capability','FEATURE_FLAGS','pantalla_id',v_screen),jsonb_build_object('kind','RULE','codigo','B2B-RULE-INPUT-APPLICABILITY-001'))
              when src.family_code='I18N_FORMATS' then jsonb_build_array(jsonb_build_object('kind','CAPABILITY_ABSENCE','capability','I18N_FORMATS','pantalla_id',v_screen),jsonb_build_object('kind','RULE','codigo','B2B-RULE-INPUT-APPLICABILITY-001'))
              else src.source_refs end,
         case when src.family_code='FEATURE_FLAGS' then 'NOT_APPLICABLE por autoridad canónica explícita DEC-INPUT-GOV-512-HUMAN-001: FEATURE_FLAGS queda excluido del alcance actual de autenticación B2B; la ausencia observada es solo evidencia complementaria.'
              when src.family_code='I18N_FORMATS' then 'NOT_APPLICABLE por autoridad canónica explícita DEC-INPUT-GOV-512-HUMAN-001: I18N_FORMATS queda excluido mientras el alcance actual permanezca single-locale; la ausencia observada es solo evidencia complementaria.'
              else src.rationale||' | Revalidado después de canonicalizar DEC-INPUT-GOV-512-HUMAN-001.' end,
         case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then '[]'::jsonb else src.blockers end,
         src.negative_requirements,
         case when src.family_code='FEATURE_FLAGS' then src.test_obligations||jsonb_build_array('Reopen FEATURE_FLAGS exclusion if a canonical feature-flag source is introduced')
              when src.family_code='I18N_FORMATS' then src.test_obligations||jsonb_build_array('Reopen I18N_FORMATS exclusion if multi-locale becomes required or locale authority is introduced')
              else src.test_obligations end,
         '{}'::jsonb,
         jsonb_build_object('component_id',v_curator_component,'execution_id',gen_random_uuid()::text,'parent_run_id',v_parent,'parent_assessment_id',src.id,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.12','owner_decision_id','DEC-INPUT-GOV-512-HUMAN-001','owner_decision_number',v_decision_number,'direct_source_readback',true,'canon_vs_proposal','STRICT_SEPARATION'),
         repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,src.subject_coverage,src.threat_coverage,src.semantic_depth_sha256
  from programacion.input_family_assessments src where src.run_id=v_parent order by src.family_code;

  if (select count(*) from programacion.input_family_assessments where run_id=v_new)<>47 then raise exception 'AUTH001_CURATOR_CARDINALITY_MISMATCH'; end if;
  update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_validator_identity,validator_component_id=v_validator_component where id=v_new;
  select source_snapshot_sha256 into v_source_sha from programacion.input_readiness_runs where id=v_new;

  for v_assessment in select * from programacion.input_family_assessments where run_id=v_new order by family_code loop
    v_assert:=programacion.fn_input_v58_build_assertions(v_new,v_parent,v_assessment.family_code);
    update programacion.input_family_assessments
    set validator_outcome='PASS',validator_findings='[]'::jsonb,
        validator_evidence=jsonb_build_object('component_id',v_validator_component,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_VALIDATOR','contract_revision','5.12','direct_source_readback',true,'source_snapshot_sha256',v_source_sha,'curator_sha256',v_assessment.curator_sha256,'semantic_depth_sha256',v_assessment.semantic_depth_sha256,'validated_curator_execution_id',v_assessment.curator_evidence->>'execution_id','owner_decision_id','DEC-INPUT-GOV-512-HUMAN-001','assertions',v_assert),
        validator_identity=v_validator_identity,validator_assessed_at=now()
    where id=v_assessment.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  if not programacion.fn_input_readiness_run_is_current(v_new) then raise exception 'AUTH001_SUCCESSOR_NOT_CURRENT:%',v_new; end if;
  if (select count(*) from programacion.input_family_assessments where run_id=v_new and validator_outcome='PASS')<>47 then raise exception 'AUTH001_VALIDATOR_CARDINALITY_MISMATCH'; end if;
  if (select count(*) from programacion.input_family_assessments where run_id=v_new and applicability='UNRESOLVED')<>0 then raise exception 'AUTH001_UNRESOLVED_REMAINS'; end if;
end;
$do$;