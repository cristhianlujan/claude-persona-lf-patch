-- INPUT_GOVERNANCE_AGENT 5.12
-- Non-decisional shadow evaluator v2 (corrected).
-- Purpose: compare current evaluator output with explicit family meta-specs,
-- typed provenance, executable meta-tests and a conservative direct-readback oracle.
-- No readiness, Story Gate, promotion, production, contract, assessment or human-decision mutation.

create or replace function programacion.fn_input_governance_shadow_family_spec_v2(
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_contract jsonb;
  v_stage_cfg jsonb;
  v_stage text;
  v_stage_authority text;
  v_declared_authorities jsonb := '[]'::jsonb;
  v_source_authority_status text := 'UNRESOLVED_NOT_DECLARED';
  v_tests jsonb;
  v_payload jsonb;
begin
  select c.especificacion into v_contract
  from programacion.contratos c
  where c.version_id=p_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_contract is null then
    raise exception 'SHADOW_V2_INPUT_READINESS_CONTRACT_NOT_FOUND:%',p_version_id;
  end if;

  if not exists(
    select 1
    from lf_ops.reglas r
    cross join lateral jsonb_array_elements_text(coalesce(r.valor_config->'families','[]'::jsonb)) f(value)
    where r.codigo='B2B-RULE-STORY-READINESS-001' and f.value=p_family_code
  ) then
    raise exception 'SHADOW_V2_FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',p_family_code;
  end if;

  v_stage_cfg:=coalesce(v_contract->'family_stage_requirements'->p_family_code,'{}'::jsonb);
  v_stage:=nullif(v_stage_cfg->>'coverage_required_by','');
  v_stage_authority:=nullif(v_stage_cfg->>'authority','');

  if p_family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS') then
    v_declared_authorities:=coalesce(v_contract->'governance_authority_policy'->'required_authority_kinds','[]'::jsonb);
    v_source_authority_status:='EXPLICIT_CONTRACT';
  elsif p_family_code in ('DESIGN_SYSTEM','ASSETS_ICONS') then
    v_declared_authorities:=coalesce(v_contract->'design_system_readiness'->'binding_authorities','[]'::jsonb);
    v_source_authority_status:='EXPLICIT_CONTRACT';
  elsif p_family_code='API_DATA_CONTRACT' then
    v_declared_authorities:=jsonb_build_array(coalesce(v_contract->'api_data_contract_readiness'->>'resolution_contract','API_CONTRACT_RESOLUTION_UNRESOLVED'));
    v_source_authority_status:='EXPLICIT_CONTRACT';
  end if;

  v_tests:=jsonb_build_array(
    jsonb_build_object('test_code','META_STAGE_AUTHORITY_EXPLICIT','actual',case when v_stage is null then 'UNRESOLVED' else 'EXPLICIT' end,'expected','EXPLICIT','status',case when v_stage is null then 'FAIL' else 'PASS' end),
    jsonb_build_object('test_code','META_NOT_APPLICABLE_REQUIRES_POSITIVE_AUTHORITY','actual',coalesce(v_contract->'not_applicable_positive_authority_contract'->>'absence_only_authority','UNRESOLVED'),'expected','DENY','status',case when v_contract->'not_applicable_positive_authority_contract'->>'absence_only_authority'='DENY' then 'PASS' else 'FAIL' end),
    jsonb_build_object('test_code','META_SOURCE_REFS_REQUIRED_PER_FAMILY','actual',coalesce((v_contract->>'source_refs_required_per_family')::boolean,false),'expected',true,'status',case when coalesce((v_contract->>'source_refs_required_per_family')::boolean,false) then 'PASS' else 'FAIL' end),
    jsonb_build_object('test_code','META_DIRECT_SOURCE_READBACK_REQUIRED','actual',coalesce((v_contract->>'direct_source_readback_required')::boolean,false),'expected',true,'status',case when coalesce((v_contract->>'direct_source_readback_required')::boolean,false) then 'PASS' else 'FAIL' end),
    jsonb_build_object('test_code','META_FAMILY_SEMANTICS_REQUIRED','actual',coalesce((v_contract->'semantic_coherence_contract'->>'family_semantics_required')::boolean,false),'expected',true,'status',case when coalesce((v_contract->'semantic_coherence_contract'->>'family_semantics_required')::boolean,false) then 'PASS' else 'FAIL' end)
  );

  v_payload:=jsonb_build_object(
    'shadow_contract','INPUT_GOVERNANCE_SHADOW_FAMILY_SPEC_V2','version_id',p_version_id,'family_code',p_family_code,
    'decisional',false,'mutates_readiness',false,'promotion_authorized',false,'production_authorized',false,
    'stage_authority',jsonb_build_object('status',case when v_stage is null then 'UNRESOLVED' else 'EXPLICIT' end,'coverage_required_by',v_stage,'authority',v_stage_authority,'implicit_default_used',false),
    'source_authority',jsonb_build_object('status',v_source_authority_status,'declared_authorities',v_declared_authorities,'generic_screen_graph_alone_sufficient',false),
    'applicability_contract',coalesce(v_contract->'not_applicable_positive_authority_contract','{}'::jsonb),
    'semantic_coherence_contract',coalesce(v_contract->'semantic_coherence_contract','{}'::jsonb),
    'test_obligations',v_tests,'test_obligation_count',jsonb_array_length(v_tests)
  );
  return v_payload||jsonb_build_object('shadow_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_shadow_priority_oracle_v2(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_screen_code text;
  v_a integer:=0;
  v_b integer:=0;
  v_c integer:=0;
  v_d integer:=0;
  v_refs jsonb:='[]'::jsonb;
  v_rejections jsonb:='[]'::jsonb;
  v_trace jsonb:='[]'::jsonb;
  v_classification text:='UNRESOLVED_NO_INDEPENDENT_ORACLE';
  v_reason text:='ORACLE_NOT_IMPLEMENTED_FOR_THIS_SCREEN_FAMILY_PAIR';
  v_payload jsonb;
begin
  select p.codigo into v_screen_code from lf_ops.pantallas p where p.id=p_pantalla_id;
  if v_screen_code is null then raise exception 'SHADOW_V2_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  if v_screen_code<>'REC_001' or p_family_code not in ('RATE_LIMIT','AUDIT','VISUAL_EVIDENCE','SECURITY') then
    return jsonb_build_object('shadow_contract','INPUT_GOVERNANCE_SHADOW_PRIORITY_ORACLE_V2','version_id',p_version_id,'pantalla_id',p_pantalla_id,'screen_code',v_screen_code,'family_code',p_family_code,'implemented',false,'decisional',false,'comparison_only',true,'classification',v_classification,'reason',v_reason,'trace','[]'::jsonb,'source_refs','[]'::jsonb);
  end if;

  if p_family_code='RATE_LIMIT' then
    select count(*) into v_a
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado='VIGENTE' and nullif(r.valor_config->>'old_phone_otp_operation','') is not null;
    select count(*) into v_b from lf_ops.reglas r
    where r.codigo='REG_RATE_003' and r.estado='VIGENTE' and nullif(r.valor_config->>'canonical_rate_policy_code','') is not null;
    select count(*) into v_c
    from lf_ops.reglas r join lf_ops.politicas_rate_limit p on p.policy_code=r.valor_config->>'canonical_rate_policy_code'
    where r.codigo='REG_RATE_003' and r.estado='VIGENTE' and p.status='VIGENTE' and p.resource_code='CLIENT_OTP_SEND';
    select count(*) into v_d from lf_ops.reglas r
    where r.codigo='REG_RISK_PHONE_MULTI_DNI_001' and r.estado='VIGENTE' and (r.pendiente_decision=true or r.valor_config->>'thresholds'='PENDING_BASELINE');
    v_refs:=jsonb_build_array(
      jsonb_build_object('kind','RULE','ref','REG_RATE_003'),
      jsonb_build_object('kind','RATE_LIMIT_POLICY','ref','RATE-CLIENT-OTP-PHONE-CROSSSESSION'),
      jsonb_build_object('kind','RULE','ref','REG_RISK_PHONE_MULTI_DNI_001','status',case when v_d>0 then 'PENDING_BASELINE' else 'RESOLVED' end)
    );
    if v_d>0 then v_rejections:=jsonb_build_array(jsonb_build_object('ref','REG_RISK_PHONE_MULTI_DNI_001','reason','PENDING_BASELINE_CANNOT_SATISFY_NUMERIC_POLICY_AUTHORITY')); end if;
    if v_a>0 and v_b>0 and v_c>0 then v_classification:='PARTIAL'; v_reason:='CANONICAL_CLIENT_OTP_RATE_POLICY_RESOLVED_BUT_MULTI_DNI_BASELINE_PENDING'; else v_classification:='MISSING'; v_reason:='DIRECT_RECOVERY_OTP_TO_CANONICAL_RATE_POLICY_CHAIN_INCOMPLETE'; end if;

  elsif p_family_code='AUDIT' then
    select count(*) filter(where r.valor_config->>'audit_storage'='lf_client.security_events'), count(*) filter(where nullif(r.valor_config->>'audit_rule_code','') is not null)
      into v_a,v_b
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado='VIGENTE';
    select count(*) filter(where r.estado='VIGENTE'),count(*) filter(where r.estado='CANDIDATO') into v_c,v_d
    from lf_ops.reglas r where r.codigo='REG_AUD_004';
    v_refs:=jsonb_build_array(jsonb_build_object('kind','AUDIT_STORAGE','ref','lf_client.security_events','status',case when to_regclass('lf_client.security_events') is not null then 'EXISTS' else 'MISSING' end),jsonb_build_object('kind','RULE','ref','REG_AUD_004','status',case when v_c>0 then 'VIGENTE' when v_d>0 then 'CANDIDATO' else 'MISSING' end));
    if v_d>0 then v_rejections:=jsonb_build_array(jsonb_build_object('ref','REG_AUD_004','reason','CANDIDATE_RULE_IS_EVIDENCE_BUT_NOT_SUFFICIENT_VIGENTE_AUTHORITY')); end if;
    if v_a>0 and to_regclass('lf_client.security_events') is not null and (v_c+v_d)>0 then v_classification:='PARTIAL'; v_reason:='AUDIT_STORAGE_EXISTS_BUT_REFERENCED_AUDIT_RULE_REMAINS_NONFINAL_OR_PARTIAL'; else v_classification:='MISSING'; v_reason:='AUDIT_STORAGE_OR_REFERENCED_RULE_CHAIN_INCOMPLETE'; end if;

  elsif p_family_code='VISUAL_EVIDENCE' then
    select count(*) into v_a from lf_design.visual_decisions vd where vd.decision_status='VIGENTE' and vd.impact_scope ? v_screen_code;
    select count(*) into v_b from lf_ops.pantalla_artefactos pa where pa.pantalla_id=p_pantalla_id and pa.status='VIGENTE' and pa.is_current=true and nullif(pa.checksum_sha256,'') is not null;
    select coalesce(jsonb_agg(jsonb_build_object('kind','VISUAL_DECISION','ref',vd.visual_decision_code,'status',vd.decision_status) order by vd.visual_decision_code),'[]'::jsonb) into v_refs
    from lf_design.visual_decisions vd where vd.decision_status='VIGENTE' and vd.impact_scope ? v_screen_code;
    if v_b=0 then v_rejections:=jsonb_build_array(jsonb_build_object('ref','lf_ops.pantalla_artefactos','reason','NO_CURRENT_CHECKSUMMED_ARTIFACT_FOR_SCREEN')); end if;
    if v_a>0 then v_classification:='PARTIAL'; v_reason:=case when v_b>0 then 'VISUAL_DECISIONS_AND_CURRENT_ARTIFACT_EXIST_BUT_FULL_CURRENTNESS_NOT_PROMOTED_BY_SHADOW' else 'VISUAL_DECISIONS_EXIST_BUT_CURRENT_SCREEN_ARTIFACT_IS_UNRESOLVED' end; else v_classification:='MISSING'; v_reason:='NO_VIGENTE_VISUAL_DECISION_SCOPED_TO_SCREEN'; end if;

  elsif p_family_code='SECURITY' then
    select count(*) into v_a
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado='VIGENTE' and lower(r.categoria)='seguridad';
    select count(*) into v_b
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado='VIGENTE' and r.valor_config->>'provider_binding' like 'PENDING%';
    select count(*) into v_c from lf_ops.reglas r
    where r.codigo='REG_RISK_PHONE_MULTI_DNI_001' and r.estado='VIGENTE' and (r.pendiente_decision=true or r.valor_config->>'thresholds'='PENDING_BASELINE');
    select coalesce(jsonb_agg(jsonb_build_object('kind','RULE','ref',r.codigo,'status',r.estado,'category',r.categoria) order by r.codigo),'[]'::jsonb) into v_refs
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado='VIGENTE' and lower(r.categoria)='seguridad';
    if v_b>0 then v_rejections:=v_rejections||jsonb_build_array(jsonb_build_object('ref','PENDING_CANONICAL_IDV_PROVIDER','reason','PENDING_PROVIDER_CANNOT_SATISFY_PROVIDER_AUTHORITY')); end if;
    if v_c>0 then v_rejections:=v_rejections||jsonb_build_array(jsonb_build_object('ref','REG_RISK_PHONE_MULTI_DNI_001','reason','PENDING_BASELINE_CANNOT_SATISFY_NUMERIC_RISK_AUTHORITY')); end if;
    if v_a>0 then v_classification:='PARTIAL'; v_reason:='DIRECT_VIGENTE_SECURITY_RULES_EXIST_WITH_UNRESOLVED_PROVIDER_AND_OR_RISK_BASELINE'; else v_classification:='MISSING'; v_reason:='NO_DIRECT_VIGENTE_SECURITY_RULES_FOR_SCREEN'; end if;
  end if;

  v_trace:=jsonb_build_array(
    jsonb_build_object('step','CANDIDATE_DISCOVERY','status',case when v_classification='MISSING' then 'FAIL' else 'PASS' end),
    jsonb_build_object('step','EXPLICIT_REFERENCE_EXPANSION','status','PASS','source_refs',v_refs),
    jsonb_build_object('step','AUTHORITY_RESOLUTION','status',case when v_classification='PARTIAL' then 'PARTIAL' else 'FAIL' end),
    jsonb_build_object('step','CANDIDATE_REJECTION','status','PASS','rejections',v_rejections),
    jsonb_build_object('step','SUFFICIENCY_EVALUATION','status',case when v_classification='PARTIAL' then 'PARTIAL' else 'FAIL' end),
    jsonb_build_object('step','FINAL_CLASSIFICATION','status','PASS','classification',v_classification,'reason',v_reason)
  );

  v_payload:=jsonb_build_object('shadow_contract','INPUT_GOVERNANCE_SHADOW_PRIORITY_ORACLE_V2','version_id',p_version_id,'pantalla_id',p_pantalla_id,'screen_code',v_screen_code,'family_code',p_family_code,'implemented',true,'decisional',false,'comparison_only',true,'mutates_readiness',false,'promotion_authorized',false,'production_authorized',false,'classification',v_classification,'reason',v_reason,'source_refs',v_refs,'candidate_rejections',v_rejections,'trace',v_trace,'trace_step_count',jsonb_array_length(v_trace));
  return v_payload||jsonb_build_object('shadow_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_shadow_evaluate_v2(
  p_pantalla_id integer,
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_family text;
  v_spec jsonb;
  v_current jsonb;
  v_sem jsonb;
  v_oracle jsonb;
  v_source_kinds jsonb;
  v_source_ref_count integer;
  v_specific_ref_count integer;
  v_test_fail_count integer;
  v_findings jsonb;
  v_rows jsonb:='[]'::jsonb;
  v_family_count integer:=0;
  v_stage_unresolved_count integer:=0;
  v_generic_source_only_count integer:=0;
  v_test_obligations_empty_count integer:=0;
  v_test_failure_family_count integer:=0;
  v_current_incomplete_without_semantic_resolver_count integer:=0;
  v_trace_contract_absent_count integer:=0;
  v_current_story_blocked_count integer:=0;
  v_oracle_implemented_family_count integer:=0;
  v_oracle_divergence_count integer:=0;
  v_meta_gap_family_count integer:=0;
  v_payload jsonb;
begin
  if not exists(select 1 from lf_ops.pantallas p where p.id=p_pantalla_id) then raise exception 'SHADOW_V2_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  perform programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);

  for v_family in
    select f.value from lf_ops.reglas r cross join lateral jsonb_array_elements_text(coalesce(r.valor_config->'families','[]'::jsonb)) f(value)
    where r.codigo='B2B-RULE-STORY-READINESS-001' order by f.value
  loop
    v_family_count:=v_family_count+1;
    v_spec:=programacion.fn_input_governance_shadow_family_spec_v2(v_family,p_version_id);
    v_current:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,p_version_id);
    v_sem:=programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id,v_family,p_version_id);
    v_oracle:=programacion.fn_input_governance_shadow_priority_oracle_v2(p_pantalla_id,v_family,p_version_id);

    if v_spec->'stage_authority'->>'status'='UNRESOLVED' then v_stage_unresolved_count:=v_stage_unresolved_count+1; end if;

    select coalesce(jsonb_agg(q.kind order by q.kind),'[]'::jsonb) into v_source_kinds
    from (select distinct sr.value->>'kind' as kind from jsonb_array_elements(coalesce(v_current->'source_refs','[]'::jsonb)) sr(value) where nullif(sr.value->>'kind','') is not null) q;
    v_source_ref_count:=jsonb_array_length(coalesce(v_current->'source_refs','[]'::jsonb));
    select count(*) into v_specific_ref_count from jsonb_array_elements(coalesce(v_current->'source_refs','[]'::jsonb)) sr(value) where sr.value->>'kind'<>'SCREEN_CANONICAL_GRAPH';
    if v_source_ref_count>0 and v_specific_ref_count=0 then v_generic_source_only_count:=v_generic_source_only_count+1; end if;
    if coalesce((v_spec->>'test_obligation_count')::integer,0)=0 then v_test_obligations_empty_count:=v_test_obligations_empty_count+1; end if;
    select count(*) into v_test_fail_count from jsonb_array_elements(coalesce(v_spec->'test_obligations','[]'::jsonb)) t(value) where t.value->>'status'='FAIL';
    if v_test_fail_count>0 then v_test_failure_family_count:=v_test_failure_family_count+1; end if;
    if v_current->>'coverage_status' in ('MISSING','PARTIAL') and not coalesce((v_sem->>'handled')::boolean,false) then v_current_incomplete_without_semantic_resolver_count:=v_current_incomplete_without_semantic_resolver_count+1; end if;
    if v_current->>'coverage_status' in ('MISSING','PARTIAL') and nullif(coalesce(v_sem->'probe'->>'resolution_contract',v_current->'probe'->>'resolution_contract'),'') is null and not coalesce((v_oracle->>'implemented')::boolean,false) then v_trace_contract_absent_count:=v_trace_contract_absent_count+1; end if;
    if v_current->>'story_ready_status'='BLOCKED' then v_current_story_blocked_count:=v_current_story_blocked_count+1; end if;
    if coalesce((v_oracle->>'implemented')::boolean,false) then
      v_oracle_implemented_family_count:=v_oracle_implemented_family_count+1;
      if v_oracle->>'classification' in ('MISSING','PARTIAL','COMPLETE') and v_current->>'coverage_status'<>v_oracle->>'classification' then v_oracle_divergence_count:=v_oracle_divergence_count+1; end if;
    end if;

    v_findings:='[]'::jsonb;
    if v_spec->'stage_authority'->>'status'='UNRESOLVED' then v_findings:=v_findings||jsonb_build_array(jsonb_build_object('code','SHADOW_V2_STAGE_AUTHORITY_UNRESOLVED','current_effective_required_by_stage',v_current->>'required_by_stage')); end if;
    if v_source_ref_count>0 and v_specific_ref_count=0 then v_findings:=v_findings||jsonb_build_array(jsonb_build_object('code','SHADOW_V2_TYPED_PROVENANCE_GENERIC_ONLY','source_kinds',v_source_kinds)); end if;
    if v_test_fail_count>0 then v_findings:=v_findings||jsonb_build_array(jsonb_build_object('code','SHADOW_V2_META_TEST_FAILURE','failed_test_count',v_test_fail_count)); end if;
    if coalesce((v_oracle->>'implemented')::boolean,false) and v_oracle->>'classification' in ('MISSING','PARTIAL','COMPLETE') and v_current->>'coverage_status'<>v_oracle->>'classification' then v_findings:=v_findings||jsonb_build_array(jsonb_build_object('code','SHADOW_V2_CURRENT_ORACLE_COVERAGE_DIVERGENCE','current_coverage',v_current->>'coverage_status','oracle_classification',v_oracle->>'classification')); end if;
    if jsonb_array_length(v_findings)>0 then v_meta_gap_family_count:=v_meta_gap_family_count+1; end if;

    v_rows:=v_rows||jsonb_build_array(jsonb_build_object('family_code',v_family,'shadow_decisional',false,'family_spec',v_spec,'typed_provenance',jsonb_build_object('status',case when v_specific_ref_count>0 then 'TYPED_PRESENT' when v_source_ref_count>0 then 'GENERIC_ONLY' else 'MISSING' end,'source_ref_count',v_source_ref_count,'specific_source_ref_count',v_specific_ref_count,'source_kinds',v_source_kinds),'current_resolver_observation',jsonb_build_object('semantic_handled',coalesce((v_sem->>'handled')::boolean,false),'resolution_contract',coalesce(v_sem->'probe'->>'resolution_contract',v_current->'probe'->>'resolution_contract')),'independent_oracle',v_oracle,'current_result',jsonb_build_object('applicability',v_current->>'applicability','coverage_status',v_current->>'coverage_status','story_ready_status',v_current->>'story_ready_status','severity',v_current->>'severity','blockers',coalesce(v_current->'blockers','[]'::jsonb)),'meta_findings',v_findings,'meta_status',case when jsonb_array_length(v_findings)=0 then 'META_CONTRACT_OK' else 'META_GAPS_PRESENT' end));
  end loop;

  v_payload:=jsonb_build_object('shadow_contract','INPUT_GOVERNANCE_SHADOW_EVALUATOR_V2','version_id',p_version_id,'pantalla_id',p_pantalla_id,'decisional',false,'mutates_readiness',false,'changes_story_gate',false,'promotion_authorized',false,'production_authorized',false,'comparison_only',true,'summary',jsonb_build_object('family_count',v_family_count,'stage_authority_unresolved_count',v_stage_unresolved_count,'generic_source_only_count',v_generic_source_only_count,'test_obligations_empty_count',v_test_obligations_empty_count,'test_failure_family_count',v_test_failure_family_count,'current_incomplete_without_semantic_resolver_count',v_current_incomplete_without_semantic_resolver_count,'resolution_trace_contract_absent_count',v_trace_contract_absent_count,'current_story_blocked_count',v_current_story_blocked_count,'oracle_implemented_family_count',v_oracle_implemented_family_count,'oracle_divergence_count',v_oracle_divergence_count,'meta_gap_family_count',v_meta_gap_family_count),'families',v_rows,'trace_contract_target',jsonb_build_object('required_steps',jsonb_build_array('CANDIDATE_DISCOVERY','EXPLICIT_REFERENCE_EXPANSION','AUTHORITY_RESOLUTION','CANDIDATE_REJECTION','SUFFICIENCY_EVALUATION','FINAL_CLASSIFICATION'),'priority_oracle_mode','DIRECT_READBACK_INDEPENDENT_OF_CURRENT_CLASSIFIER_FOR_CLASSIFICATION','non_priority_oracle_mode','UNRESOLVED_NO_INDEPENDENT_ORACLE'));
  return v_payload||jsonb_build_object('shadow_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_shadow_sweep_v2(p_version_id bigint default 19)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_screen record;
  v_eval jsonb;
  v_rows jsonb:='[]'::jsonb;
  v_screen_count integer:=0;
  v_payload jsonb;
begin
  for v_screen in
    select p.id,p.codigo,p.nombre from lf_ops.pantallas p
    where p.activa=true and p.codigo in ('REC_001','ONB_001','ONB_002','ONB_003','ONB_004','HOME_001','B2B-AUTH-001','B2B-AUTH-002')
    order by case p.codigo when 'REC_001' then 1 when 'ONB_001' then 2 when 'ONB_002' then 3 when 'ONB_003' then 4 when 'ONB_004' then 5 when 'HOME_001' then 6 when 'B2B-AUTH-001' then 7 when 'B2B-AUTH-002' then 8 else 99 end
  loop
    v_screen_count:=v_screen_count+1;
    v_eval:=programacion.fn_input_governance_shadow_evaluate_v2(v_screen.id,p_version_id);
    v_rows:=v_rows||jsonb_build_array(jsonb_build_object('pantalla_id',v_screen.id,'screen_code',v_screen.codigo,'name',v_screen.nombre,'summary',v_eval->'summary','shadow_sha256',v_eval->>'shadow_sha256'));
  end loop;
  v_payload:=jsonb_build_object('shadow_contract','INPUT_GOVERNANCE_SHADOW_SWEEP_V2','version_id',p_version_id,'decisional',false,'mutates_readiness',false,'promotion_authorized',false,'production_authorized',false,'representative_sample',true,'screen_count',v_screen_count,'screens',v_rows);
  return v_payload||jsonb_build_object('shadow_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

comment on function programacion.fn_input_governance_shadow_family_spec_v2(text,bigint) is 'Non-decisional v2 family meta-spec; missing stage/source authority remains explicit UNRESOLVED.';
comment on function programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint) is 'Non-decisional REC_001 priority direct-readback oracle; comparison only.';
comment on function programacion.fn_input_governance_shadow_evaluate_v2(integer,bigint) is 'Non-decisional v2 comparison evaluator; no readiness mutation.';
comment on function programacion.fn_input_governance_shadow_sweep_v2(bigint) is 'Representative non-decisional v2 sweep across Client and B2B control screens.';

revoke all on function programacion.fn_input_governance_shadow_family_spec_v2(text,bigint) from public;
revoke all on function programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint) from public;
revoke all on function programacion.fn_input_governance_shadow_evaluate_v2(integer,bigint) from public;
revoke all on function programacion.fn_input_governance_shadow_sweep_v2(bigint) from public;
grant execute on function programacion.fn_input_governance_shadow_family_spec_v2(text,bigint) to programacion_builder,programacion_auditor,programacion_verifier;
grant execute on function programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint) to programacion_builder,programacion_auditor,programacion_verifier;
grant execute on function programacion.fn_input_governance_shadow_evaluate_v2(integer,bigint) to programacion_builder,programacion_auditor,programacion_verifier;
grant execute on function programacion.fn_input_governance_shadow_sweep_v2(bigint) to programacion_builder,programacion_auditor,programacion_verifier;

do $do$
declare
  v_rec jsonb;
  v_sweep jsonb;
  v_rate jsonb;
  v_audit jsonb;
  v_visual jsonb;
  v_security jsonb;
begin
  v_rec:=programacion.fn_input_governance_shadow_evaluate_v2(58,19);
  if coalesce((v_rec->>'decisional')::boolean,true) or coalesce((v_rec->>'mutates_readiness')::boolean,true) or coalesce((v_rec->>'promotion_authorized')::boolean,true) or coalesce((v_rec->>'production_authorized')::boolean,true) then raise exception 'SHADOW_V2_MUST_REMAIN_NON_DECISIONAL'; end if;
  if (v_rec->'summary'->>'family_count')::integer<>47 then raise exception 'SHADOW_V2_FAMILY_COUNT_MISMATCH'; end if;
  if (v_rec->'summary'->>'stage_authority_unresolved_count')::integer<>39 then raise exception 'SHADOW_V2_STAGE_AUTHORITY_BASELINE_MISMATCH'; end if;
  if (v_rec->'summary'->>'test_obligations_empty_count')::integer<>0 then raise exception 'SHADOW_V2_TEST_OBLIGATIONS_MUST_BE_NONEMPTY'; end if;
  if (v_rec->'summary'->>'oracle_implemented_family_count')::integer<>4 then raise exception 'SHADOW_V2_PRIORITY_ORACLE_COUNT_MISMATCH'; end if;
  if (v_rec->'summary'->>'current_story_blocked_count')::integer<>19 then raise exception 'SHADOW_V2_REC001_CURRENT_STORY_BASELINE_MISMATCH'; end if;
  v_rate:=programacion.fn_input_governance_shadow_priority_oracle_v2(58,'RATE_LIMIT',19);
  v_audit:=programacion.fn_input_governance_shadow_priority_oracle_v2(58,'AUDIT',19);
  v_visual:=programacion.fn_input_governance_shadow_priority_oracle_v2(58,'VISUAL_EVIDENCE',19);
  v_security:=programacion.fn_input_governance_shadow_priority_oracle_v2(58,'SECURITY',19);
  if v_rate->>'classification'<>'PARTIAL' or v_audit->>'classification'<>'PARTIAL' or v_visual->>'classification'<>'PARTIAL' or v_security->>'classification'<>'PARTIAL' then raise exception 'SHADOW_V2_PRIORITY_ORACLE_BASELINE_MISMATCH'; end if;
  if (v_rate->>'trace_step_count')::integer<>6 or (v_audit->>'trace_step_count')::integer<>6 or (v_visual->>'trace_step_count')::integer<>6 or (v_security->>'trace_step_count')::integer<>6 then raise exception 'SHADOW_V2_TRACE_CONTRACT_MUST_HAVE_SIX_STEPS'; end if;
  v_sweep:=programacion.fn_input_governance_shadow_sweep_v2(19);
  if (v_sweep->>'screen_count')::integer<>8 then raise exception 'SHADOW_V2_REPRESENTATIVE_SWEEP_COUNT_MISMATCH'; end if;
end;
$do$;
