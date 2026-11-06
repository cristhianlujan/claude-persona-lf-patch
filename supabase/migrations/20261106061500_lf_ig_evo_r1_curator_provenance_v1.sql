-- IG-EVO R1: parameter provenance read-only detector and native Curator non-blocking diagnostics.
-- No Router change; no new tables, judges, profile grants, business policy mutations, or auto promotion.
-- EKB: GOV-010, GOV-032, GOV-LF-RECEIPT-001, SEC-011, IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001.
-- Shadow only: no input_gap_proposals insertion, no new T_REMED work, no source-only semantic PASS.
BEGIN;
DO $pin$
DECLARE v_md5 text;
BEGIN
 SELECT md5(pg_get_functiondef('programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure)) INTO v_md5;
 IF v_md5<>'5205aacc6540ee73e9c2621b0502e963' THEN
   RAISE EXCEPTION 'IG_EVO_R1_CURATOR_SOURCE_DRIFT:%',v_md5;
 END IF;
END $pin$;

CREATE OR REPLACE FUNCTION programacion.fn_ig_evo_r1_parameter_provenance_v1(p_pantalla_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY INVOKER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $r1$
WITH policy_source AS (
  SELECT b.pantalla_id,b.status binding_status,'RATE_LIMIT'::text family,
    p.rate_limit_policy_id::text policy_id,p.policy_code,p.status policy_status,
    p.source_decision_id,p.parameter_provenance,
    jsonb_build_object('max_requests',p.max_requests,'window_seconds',p.window_seconds,'burst_limit',p.burst_limit) attrs,
    programacion.fn_v09_sha256_jsonb(to_jsonb(p)) policy_row_sha256,
    programacion.fn_v09_sha256_jsonb(to_jsonb(b)) policy_binding_sha256
  FROM lf_ops.pantallas_politicas b
  JOIN lf_ops.politicas_rate_limit p ON p.rate_limit_policy_id=b.rate_limit_policy_id
  WHERE b.pantalla_id=p_pantalla_id
  UNION ALL
  SELECT b.pantalla_id,b.status,'TIMEOUT',p.timeout_policy_id::text,p.policy_code,p.status,
    p.source_decision_id,p.parameter_provenance,
    jsonb_build_object('timeout_seconds',p.timeout_seconds,'retry_limit',p.retry_limit),
    programacion.fn_v09_sha256_jsonb(to_jsonb(p)),programacion.fn_v09_sha256_jsonb(to_jsonb(b))
  FROM lf_ops.pantallas_politicas b
  JOIN lf_ops.politicas_timeout p ON p.timeout_policy_id=b.timeout_policy_id
  WHERE b.pantalla_id=p_pantalla_id
  UNION ALL
  SELECT b.pantalla_id,b.status,'SESSION',p.session_policy_id::text,p.policy_code,p.status,
    p.source_decision_id,p.parameter_provenance,
    jsonb_build_object(
      'idle_timeout_seconds',p.idle_timeout_seconds,
      'warning_before_timeout_seconds',p.warning_before_timeout_seconds,
      'absolute_timeout_seconds',p.absolute_timeout_seconds,
      'access_token_ttl_seconds',p.access_token_ttl_seconds,
      'max_concurrent_sessions',p.max_concurrent_sessions),
    programacion.fn_v09_sha256_jsonb(to_jsonb(p)),programacion.fn_v09_sha256_jsonb(to_jsonb(b))
  FROM lf_ops.pantallas_politicas b
  JOIN lf_ops.politicas_sesion p ON p.session_policy_id=b.session_policy_id
  WHERE b.pantalla_id=p_pantalla_id
  UNION ALL
  SELECT b.pantalla_id,b.status,'SECURITY',p.security_policy_id::text,p.policy_code,p.status,
    p.source_decision_id,p.parameter_provenance,
    COALESCE(p.policy_config,'{}'::jsonb),
    programacion.fn_v09_sha256_jsonb(to_jsonb(p)),programacion.fn_v09_sha256_jsonb(to_jsonb(b))
  FROM lf_ops.pantallas_politicas b
  JOIN lf_ops.politicas_seguridad p ON p.security_policy_id=b.security_policy_id
  WHERE b.pantalla_id=p_pantalla_id
), numeric_fields AS (
  SELECT p.*,k.key parameter_name,k.value parameter_value,
    COALESCE(jsonb_typeof(p.parameter_provenance),'NULL') provenance_type,
    CASE WHEN jsonb_typeof(p.parameter_provenance)='object'
      THEN p.parameter_provenance ? k.key ELSE false END has_parameter_provenance
  FROM policy_source p
  CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(p.attrs)='object' THEN p.attrs ELSE '{}'::jsonb END) k
  WHERE jsonb_typeof(k.value)='number'
    AND (p.family<>'SECURITY' OR k.key ~* '(limit|timeout|ttl|window|seconds|requests|burst|retry|intentos|threshold|concurrent|max_|count|expiracion)')
), missing AS (
  SELECT pantalla_id,binding_status,family,policy_id,policy_code,policy_status,
    source_decision_id,policy_row_sha256,policy_binding_sha256,
    jsonb_agg(jsonb_build_object('parameter',parameter_name,'observed_value',parameter_value)
      ORDER BY parameter_name) FILTER (WHERE NOT has_parameter_provenance) missing_parameters,
    COUNT(*) FILTER (WHERE NOT has_parameter_provenance) missing_count
  FROM numeric_fields
  GROUP BY pantalla_id,binding_status,family,policy_id,policy_code,policy_status,
    source_decision_id,policy_row_sha256,policy_binding_sha256
), scoped AS (
  SELECT jsonb_build_object(
    'detector','R1','pantalla_id',pantalla_id,'policy_family',family,
    'policy_id',policy_id,'policy_code',policy_code,
    'policy_status',policy_status,'binding_status',binding_status,
    'source_decision_id',source_decision_id,
    'policy_row_sha256',policy_row_sha256,
    'policy_binding_sha256',policy_binding_sha256,
    'missing_parameter_count',missing_count,
    'missing_parameters',missing_parameters,
    'numeric_policy_values_incorrect','NOT_PROVEN',
    'binding_live_authorized',binding_status='VIGENTE',
    'semantic_quality_evaluated',false,
    'provenance_status','MISSING_PER_PARAMETER',
    'coverage_note','TOP_LEVEL_POLICY_NUMERIC_PARAMETERS_ONLY'
  ) finding
  FROM missing WHERE missing_count>0
)
SELECT jsonb_build_object(
 'schema_version','IG_EVO_R1_PARAMETER_PROVENANCE_V1',
 'pantalla_id',p_pantalla_id,
 'mode','DETERMINISTIC_SOURCE_INSPECTION',
 'canonical_write_authorized',false,
 'source_readback_proof','DIRECT_POLICY_ROW_AND_BINDING_DIGEST_ONLY',
 'finding_count',COUNT(*),
 'findings',COALESCE(jsonb_agg(finding ORDER BY finding->>'policy_family',finding->>'policy_id'),'[]'::jsonb)
) FROM scoped;
$r1$;

REVOKE ALL ON FUNCTION programacion.fn_ig_evo_r1_parameter_provenance_v1(integer) FROM PUBLIC;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_materialize_gap_proposals_v1(p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_run record;
  a record;
  b jsonb;
  v_gap text;
  v_kind text;
  v_class text;
  v_synthesis text;
  v_result text;
  v_positive_owner_authority boolean;
  v_policy jsonb;
  v_policy_ref text;
  v_count int:=0;
  v_human int:=0;
  v_auto int:=0;
  v_create int:=0;
  v_inherit int:=0;
  v_close_candidates int:=0;
  v_r1_scan jsonb;
begin
  select c.especificacion->'gap_policy_contract',
         c.especificacion->>'gap_policy_decision'
    into v_policy,v_policy_ref
  from programacion.contratos c
  where c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado='defined'
    and c.fail_closed
  order by c.version_id desc,c.id desc
  limit 1;

  if coalesce(v_policy->>'schema_version','')<>'INPUT_GAP_POLICY_V1'
     or v_policy_ref<>'DEC-INPUT-GOV-GAP-POLICY-001'
     or v_policy->>'targeted_evidence_before_escalation'<>'TARGETED_EVIDENCE_ACQUISITION'
     or v_policy->>'canonical_change_admission'<>'SAFE_CHANGE_ADMISSION' then
    raise exception 'INPUT_GAP_POLICY_NOT_CURRENT_OR_INCOMPLETE';
  end if;

  select * into v_run
  from programacion.input_readiness_runs
  where id=p_run_id;

  if not found then
    raise exception 'INPUT_REMEDIATION_RUN_NOT_FOUND:%',p_run_id;
  end if;
  if v_run.status<>'CURATING' then
    raise exception 'INPUT_REMEDIATION_REQUIRES_CURATING:%',p_run_id;
  end if;

  for a in
    select *
    from programacion.input_family_assessments
    where run_id=p_run_id
      and jsonb_array_length(blockers)>0
    order by family_code,id
  loop
    for b in select value from jsonb_array_elements(a.blockers)
    loop
      v_gap:=coalesce(b->>'code','UNSPECIFIED_GAP');

      if a.family_code in ('PROFILES','PERMISSIONS','FEATURE_FLAGS','I18N_FORMATS') then
        v_class:='APPLICABILITY_AUTHORITY_GAP';
      elsif a.story_ready_status='READY' then
        v_class:='STAGE_SPECIFIC_GAP';
      elsif v_gap ~ '(EVIDENCE|AUTHORITY|PROVENANCE)' then
        v_class:='GOVERNANCE_EVIDENCE_GAP';
      else
        v_class:='FUNCTIONAL_DEFINITION_GAP';
      end if;

      v_positive_owner_authority:=
        coalesce((b->>'owner_decision_required')::boolean,false)
        and nullif(b->>'owner_decision_authority','') is not null;

      if v_positive_owner_authority then
        v_kind:='HUMAN_DECISION_REQUIRED';
      elsif v_gap ~ '(CONFLICT|RECONCILIATION)' then
        v_kind:='SOURCE_CONFLICT';
      elsif coalesce((a.curator_evidence->'bootstrap_probe'->>'pending_decision_count')::int,0)>0 then
        v_kind:='RESEARCH_REQUIRED';
      else
        v_kind:='SOURCE_INCOMPLETE';
      end if;

      if v_kind in ('HUMAN_DECISION_REQUIRED','SOURCE_CONFLICT') then
        v_synthesis:='BOUNDED_ALTERNATIVES';
      elsif jsonb_array_length(coalesce(a.source_refs,'[]'::jsonb))>0
            and v_kind='SOURCE_INCOMPLETE' then
        v_synthesis:='SINGLE_EXACT';
      else
        v_synthesis:='HOLD_FOR_EVIDENCE';
      end if;

      if exists (
        select 1
        from programacion.input_gap_proposals p
        where p.run_id=p_run_id
          and p.family_code=a.family_code
          and p.gap_code=v_gap
      ) then
        v_inherit:=v_inherit+1;
        continue;
      end if;

      v_result:=case
        when v_kind='HUMAN_DECISION_REQUIRED' then 'REQUIERE_DECISION'
        when v_kind in ('SOURCE_CONFLICT','RESEARCH_REQUIRED','SOURCE_INCOMPLETE') then 'RECOMENDADA'
        else 'UNKNOWN'
      end;

      insert into programacion.input_gap_proposals(
        run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,
        source_refs,evidence_refs,confidence,stage_impact,contradictions_checked,status,
        curator_identity,curator_execution_id
      ) values(
        p_run_id,a.id,a.family_code,v_gap,v_kind,
        jsonb_build_object(
          'gap_classification',v_class,
          'agent_action',case
            when v_kind='HUMAN_DECISION_REQUIRED' then 'ESCALATE_AFTER_VALIDATION'
            when a.family_code='DESIGN_SYSTEM' then 'SEARCH_AND_VALIDATE_EXISTING_CANONICAL_BINDING_BEFORE_ESCALATION'
            when v_kind='RESEARCH_REQUIRED' then 'RESOLVE_PENDING_SOURCE_OR_EVIDENCE_INTERNALLY'
            else 'KEEP_IN_INTERNAL_REMEDIATION_QUEUE'
          end,
          'gap_policy_ref',v_policy_ref,
          'gap_policy_schema',v_policy->>'schema_version',
          'gap_policy_action','CREATE',
          'synthesis_mode',v_synthesis,
          'policy_result',v_result,
          'targeted_evidence_before_escalation',v_policy->>'targeted_evidence_before_escalation',
          'canonical_change_admission',v_policy->>'canonical_change_admission',
          'no_effective_change_result',v_policy->>'no_effective_change_result',
          'positive_owner_escalation_authority',v_positive_owner_authority,
          'pending_marker_is_not_owner_authority',true,
          'no_invention',true,
          'proposal_is_canonical_source',false,
          'automatic_canonicalization','DENY',
          'analysis_revision',coalesce(v_run.scope->>'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX'),
          'remediation_policy_revision','INPUT_GAP_POLICY_V1'
        ),
        jsonb_build_object('pantalla_id',v_run.pantalla_id,'family_code',a.family_code),
        a.source_refs,'[]'::jsonb,
        case when v_positive_owner_authority then 1.0 else 0.9 end,
        jsonb_build_object(
          'story',a.story_ready_status,
          'implementation',a.implementation_ready_status,
          'qa',a.qa_ready_status,
          'production',a.production_ready_status
        ),
        jsonb_build_array(
          'GOV-015_CLASSIFICATION_APPLIED',
          'POSITIVE_OWNER_AUTHORITY_REQUIRED',
          'NO_PROPOSAL_AS_CANONICAL_SOURCE',
          'INPUT_GAP_POLICY_V1_APPLIED'
        ),
        'PROPOSED',
        v_run.curator_identity,
        coalesce(a.curator_evidence->>'execution_id','UNKNOWN')
      )
      on conflict (run_id,family_code,gap_code) do nothing;

      if found then
        v_count:=v_count+1;
        v_create:=v_create+1;
        if v_kind='HUMAN_DECISION_REQUIRED' then
          v_human:=v_human+1;
        else
          v_auto:=v_auto+1;
        end if;
      else
        v_inherit:=v_inherit+1;
      end if;
    end loop;
  end loop;


  -- IG-EVO R1 shadow: publish factual evidence without creating proposals.
  -- A new proposal would be counted by T_REMED as a remediation even though
  -- the semantic-quality gate is NOT_TESTED. Do not modify run outcome.
  v_r1_scan:=programacion.fn_ig_evo_r1_parameter_provenance_v1(v_run.pantalla_id);
  if v_r1_scan->>'schema_version'<>'IG_EVO_R1_PARAMETER_PROVENANCE_V1'
     or (v_r1_scan->>'pantalla_id')::integer is distinct from v_run.pantalla_id
     or v_r1_scan->>'canonical_write_authorized'<>'false' then
    raise exception 'IG_EVO_R1_SCAN_CONTRACT_INVALID:%',p_run_id;
  end if;

  select count(*)
    into v_close_candidates
  from programacion.input_gap_proposals p
  where p.run_id=p_run_id
    and not exists (
      select 1
      from programacion.input_family_assessments a2
      cross join lateral jsonb_array_elements(a2.blockers) bx(value)
      where a2.run_id=p_run_id
        and a2.family_code=p.family_code
        and coalesce(bx.value->>'code','UNSPECIFIED_GAP')=p.gap_code
    );

  return jsonb_build_object(
    'run_id',p_run_id,
    'proposal_count',v_count,
    'internal_remediation_count',v_auto,
    'human_decision_candidate_count',v_human,
    'gap_policy_ref',v_policy_ref,
    'gap_policy_schema',v_policy->>'schema_version',
    'strategy_results',jsonb_build_object(
      'CREATE',jsonb_build_object('executed_count',v_create,'duplicate_policy','DENY'),
      'INHERIT',jsonb_build_object('reused_count',v_inherit,'mutated_existing_validated_row',false),
      'CLOSE',jsonb_build_object(
        'candidate_count',v_close_candidates,
        'executed_count',0,
        'state','HOLD_FOR_EVIDENCE',
        'reason','INDEPENDENT_VALIDATION_REQUIRED'
      )
    ),
    'synthesis_modes',v_policy->'dynamic_synthesis_modes',
    'targeted_evidence_before_escalation',v_policy->>'targeted_evidence_before_escalation',
    'canonical_change_admission',v_policy->>'canonical_change_admission',
    'no_effective_change_result',v_policy->>'no_effective_change_result',
    'owner_escalation_policy','POSITIVE_OWNER_AUTHORITY_ONLY',
    'proposal_is_canonical_source',false,
    'automatic_canonicalization','DENY',
    'ig_evo_r1_diagnostics',v_r1_scan,
    'ig_evo_execution_mode','SHADOW_NON_BLOCKING',
    'ig_evo_semantic_quality','NOT_TESTED',
    'ig_evo_proposals_created',0
  );
end;
$function$;

-- Focal positive/negative read-only tests executed by governed Migration Train after apply.
DO $r1_tests$
DECLARE v_doc jsonb; v_case jsonb; v_zero jsonb; v_source text;
BEGIN
 v_doc:=programacion.fn_ig_evo_r1_parameter_provenance_v1(51);
 IF v_doc->>'schema_version'<>'IG_EVO_R1_PARAMETER_PROVENANCE_V1'
    OR coalesce((v_doc->>'finding_count')::integer,0)<1 THEN
   RAISE EXCEPTION 'IG_EVO_R1_B2B_NO_FINDINGS';
 END IF;
 SELECT x INTO v_case FROM jsonb_array_elements(v_doc->'findings') x
 WHERE x->>'policy_code'='RATE-B2B-LOGIN' LIMIT 1;
 IF v_case IS NULL
 OR v_case->>'policy_status'<>'VIGENTE'
 OR v_case->>'binding_status'<>'CANDIDATO'
 OR v_case->>'source_decision_id'<>'DEC-B2B-HANDOFF-SCREEN-PACKAGE-001'
 OR coalesce((v_case->>'missing_parameter_count')::integer,0)<>3
 OR v_case->>'numeric_policy_values_incorrect'<>'NOT_PROVEN'
 OR v_case->>'binding_live_authorized'<>'false' THEN
   RAISE EXCEPTION 'IG_EVO_R1_B2B_EXPECTED_CASE_DRIFT:%',v_case;
 END IF;
 v_zero:=programacion.fn_ig_evo_r1_parameter_provenance_v1(1);
 IF coalesce((v_zero->>'finding_count')::integer,-1)<>0
    OR jsonb_array_length(v_zero->'findings')<>0 THEN
    RAISE EXCEPTION 'IG_EVO_R1_FALSE_POSITIVE_SCREEN_WITHOUT_POLICIES:%',v_zero;
 END IF;
 SELECT pg_get_functiondef('programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure)
 INTO v_source;
 IF position('fn_ig_evo_r1_parameter_provenance_v1' in v_source)=0
    OR position('ig_evo_r1_diagnostics' in v_source)=0
    OR position('SHADOW_NON_BLOCKING' in v_source)=0 THEN
    RAISE EXCEPTION 'IG_EVO_R1_CURATOR_NOT_NATIVE_INTEGRATED';
 END IF;
 IF has_function_privilege('public','programacion.fn_ig_evo_r1_parameter_provenance_v1(integer)'::regprocedure,'EXECUTE') THEN
   RAISE EXCEPTION 'IG_EVO_R1_SECURITY_DEFINER_PUBLIC_EXPOSURE';
 END IF;
END $r1_tests$;
COMMIT;
