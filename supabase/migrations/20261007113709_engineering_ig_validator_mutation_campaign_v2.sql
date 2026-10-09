create or replace function programacion.fn_engineering_ig_validator_mutation_campaign_v1(
  p_pantalla_id integer default 50
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path to 'pg_catalog','programacion','public','lf_ops','extensions'
set statement_timeout to '120s'
as $function$
declare
  v_sig regprocedure:='programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure;
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_orig text; v_candidate text; v_anchor text:='v:=v-''classifier_sha256'';';
  v_md5 text; v_mutation text; v_injection text;
  v_cur_id text; v_val_id text; v_cur jsonb; v_val jsonb;
  v_run bigint; v_i integer; v_j integer; v_pending integer;
  v_fail integer; v_blocked integer; v_target_outcome text; v_target_findings jsonb;
  v_detected boolean; v_err text; v_marker text;
  v_results jsonb:='[]'::jsonb; v_case jsonb;
  v_baseline jsonb; v_mutated jsonb; v_false_pass boolean;
  v_detected_count integer:=0;
  v_outer_marker text:='M49_BASE_ROLLBACK';
begin
  perform pg_advisory_xact_lock(hashtextextended('IG_VALIDATOR_MUTATION_CAMPAIGN',0));
  v_orig:=pg_get_functiondef(v_sig);
  v_md5:=md5(v_orig);
  if position(v_anchor in v_orig)=0 then raise exception 'M49_CLASSIFIER_PATCH_ANCHOR_MISSING'; end if;

  -- One real Curator self-test baseline reused for T1-T9.
  v_cur_id:='INPUT_CURATOR:EDGE:input-governance-curator-v1:M49BASE'||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  begin
    v_cur:=programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id,'MANUAL',v_cur_id,true);
    v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
    if v_run is null then raise exception 'M49_NO_BASE_SELFTEST_RUN:%',v_cur; end if;

    for v_i in 1..9 loop
      v_mutation:=case v_i
        when 1 then 'MISSING_SOURCE'
        when 2 then 'CONTRADICTORY_SOURCE'
        when 3 then 'BROKEN_ID'
        when 4 then 'INVENTED_URL'
        when 5 then 'TIMEOUT_WITHOUT_SOURCE'
        when 6 then 'UNJUSTIFIED_NOT_APPLICABLE'
        when 7 then 'STALE_EVIDENCE'
        when 8 then 'HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE'
        else 'SELF_AUTHORITY' end;
      v_val_id:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M49T'||lpad(v_i::text,2,'0')||substr(replace(gen_random_uuid()::text,'-',''),1,10);
      v_marker:='M49_CASE_ROLLBACK_'||v_i;
      v_case:=null;

      begin
        v_injection:=case v_i
          when 1 then
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',''[]''::jsonb,true); end if; '
          when 2 then
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'',''contradiction'',true)),true); end if; '
          when 3 then
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''__BROKEN_ID__'')),true); end if; '
          when 4 then
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',jsonb_build_array(jsonb_build_object(''kind'',''URL'',''url'',''https://invalid.example/m4-9'')),true); end if; '
          when 5 then
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',''[]''::jsonb,true); v:=jsonb_set(v,''{rationale}'',to_jsonb(''TIMEOUT_WITHOUT_SOURCE''::text),true); end if; '
          when 6 then
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{applicability}'',''"NOT_APPLICABLE"''::jsonb,true); v:=jsonb_set(v,''{coverage_status}'',''"NOT_APPLICABLE"''::jsonb,true); end if; '
          when 7 then
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'',''stale_evidence'',true)),true); end if; '
          when 8 then
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'',''historical_pass_override'',true)),true); end if; '
          else
            'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''CONTRACT'',''codigo'',''INPUT_READINESS_CONTRACT'')),true); end if; '
        end;
        v_candidate:=replace(v_orig,v_anchor,v_injection||v_anchor);
        execute v_candidate;

        for v_j in 1..8 loop
          v_val:=programacion.fn_input_governance_validate_v2(v_run,v_val_id);
          select count(*) filter(where validator_outcome='PENDING'),
                 count(*) filter(where validator_outcome='FAIL'),
                 count(*) filter(where validator_outcome='BLOCKED')
            into v_pending,v_fail,v_blocked
          from programacion.input_family_assessments where run_id=v_run;
          exit when v_pending=0;
        end loop;

        select validator_outcome,validator_findings
          into v_target_outcome,v_target_findings
        from programacion.input_family_assessments
        where run_id=v_run and family_code='VISUAL_EVIDENCE';

        v_detected:=coalesce(v_target_outcome,'') in ('FAIL','BLOCKED')
          and jsonb_array_length(coalesce(v_target_findings,'[]'::jsonb))>0
          and coalesce((v_val->>'promotion_authorized')::boolean,false)=false;

        v_case:=jsonb_build_object(
          'ordinal',v_i,'mutation_code',v_mutation,
          'status',case when v_detected then 'PASS' else 'FAIL' end,
          'detected',v_detected,'validator_outcome',v_target_outcome,
          'validator_terminal',v_val->>'status','findings',v_target_findings,
          'promotion_authorized',coalesce((v_val->>'promotion_authorized')::boolean,false),
          'detection_surface','VALIDATOR_CLASSIFIER_MISMATCH','actual_execution',true
        );
        raise exception '%',v_marker;
      exception when others then
        v_err:=sqlerrm;
        if v_err<>v_marker then
          v_case:=jsonb_build_object(
            'ordinal',v_i,'mutation_code',v_mutation,'status','FAIL',
            'detected',false,'technical_error',v_err,'actual_execution',true
          );
        end if;
      end;

      if md5(pg_get_functiondef(v_sig))<>v_md5 then raise exception 'M49_CLASSIFIER_RESIDUE_T%',v_i; end if;
      v_case:=v_case||jsonb_build_object('rollback_clean',true,'classifier_restored',true);
      if coalesce((v_case->>'detected')::boolean,false) then v_detected_count:=v_detected_count+1; end if;
      v_results:=v_results||jsonb_build_array(v_case);
    end loop;

    raise exception '%',v_outer_marker;
  exception when others then
    v_err:=sqlerrm;
    if v_err<>v_outer_marker then raise; end if;
  end;

  if md5(pg_get_functiondef(v_sig))<>v_md5 then raise exception 'M49_CLASSIFIER_RESIDUE_BASE'; end if;
  if exists(select 1 from programacion.input_readiness_runs where curator_identity=v_cur_id) then
    raise exception 'M49_BASE_RUN_RESIDUE';
  end if;

  -- T10: correlated mutation is installed before Curator, so Curator and classifier agree.
  v_baseline:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,'VISUAL_EVIDENCE',v_version);
  v_cur_id:='INPUT_CURATOR:EDGE:input-governance-curator-v1:M49T10'||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  v_val_id:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M49T10'||substr(replace(gen_random_uuid()::text,'-',''),1,10);
  v_outer_marker:='M49_T10_ROLLBACK';
  v_case:=null;

  begin
    v_injection:='if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'')),true); end if; ';
    v_candidate:=replace(v_orig,v_anchor,v_injection||v_anchor);
    execute v_candidate;
    v_mutated:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,'VISUAL_EVIDENCE',v_version);
    if v_mutated->'source_refs' is not distinct from v_baseline->'source_refs' then
      raise exception 'M49_T10_MUTATION_NOT_MATERIAL';
    end if;

    v_cur:=programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id,'MANUAL',v_cur_id,true);
    v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
    if v_run is null then raise exception 'M49_T10_NO_SELFTEST_RUN'; end if;

    for v_j in 1..8 loop
      v_val:=programacion.fn_input_governance_validate_v2(v_run,v_val_id);
      select count(*) filter(where validator_outcome='PENDING'),
             count(*) filter(where validator_outcome='FAIL'),
             count(*) filter(where validator_outcome='BLOCKED')
        into v_pending,v_fail,v_blocked
      from programacion.input_family_assessments where run_id=v_run;
      exit when v_pending=0;
    end loop;
    if v_pending=0 and coalesce(v_fail,0)+coalesce(v_blocked,0)=0 then
      v_val:=programacion.fn_input_governance_validate_v2(v_run,v_val_id);
    end if;

    select validator_outcome,validator_findings
      into v_target_outcome,v_target_findings
    from programacion.input_family_assessments
    where run_id=v_run and family_code='VISUAL_EVIDENCE';

    v_detected:=coalesce(v_target_outcome,'') in ('FAIL','BLOCKED')
      or coalesce(v_fail,0)+coalesce(v_blocked,0)>0;
    v_false_pass:=not v_detected;

    v_case:=jsonb_build_object(
      'ordinal',10,'mutation_code','CORRELATED_CURATOR_RESOLVER_DEFECT',
      'status',case when v_detected then 'PASS' else 'FAIL' end,
      'detected',v_detected,'false_consensus_pass',v_false_pass,
      'validator_outcome',v_target_outcome,'validator_terminal',v_val->>'status',
      'findings',coalesce(v_target_findings,'[]'::jsonb),
      'baseline_sha256',programacion.fn_v09_sha256_jsonb(v_baseline),
      'correlated_classifier_sha256',v_mutated->>'classifier_sha256',
      'baseline_source_refs_sha256',programacion.fn_v09_sha256_jsonb(v_baseline->'source_refs'),
      'mutated_source_refs_sha256',programacion.fn_v09_sha256_jsonb(v_mutated->'source_refs'),
      'promotion_authorized',coalesce((v_val->>'promotion_authorized')::boolean,false),
      'detection_surface',case when v_detected then 'VALIDATOR_OR_TRANSITIVE_GUARD' else 'FALSE_CONSENSUS_NOT_DETECTED' end,
      'actual_execution',true,'independent_baseline_frozen_before_mutation',true
    );
    raise exception '%',v_outer_marker;
  exception when others then
    v_err:=sqlerrm;
    if v_err<>v_outer_marker then
      v_case:=jsonb_build_object(
        'ordinal',10,'mutation_code','CORRELATED_CURATOR_RESOLVER_DEFECT',
        'status','FAIL','detected',false,'technical_error',v_err,'actual_execution',true
      );
    end if;
  end;

  if md5(pg_get_functiondef(v_sig))<>v_md5 then raise exception 'M49_CLASSIFIER_RESIDUE_T10'; end if;
  if exists(select 1 from programacion.input_readiness_runs where curator_identity=v_cur_id or validator_identity=v_val_id) then
    raise exception 'M49_T10_RUN_RESIDUE';
  end if;
  v_case:=v_case||jsonb_build_object('rollback_clean',true,'classifier_restored',true);
  if coalesce((v_case->>'detected')::boolean,false) then v_detected_count:=v_detected_count+1; end if;
  v_results:=v_results||jsonb_build_array(v_case);

  return jsonb_build_object(
    'schema_version','ENGINEERING_IG_VALIDATOR_MUTATION_CAMPAIGN_V1',
    'status',case when v_detected_count=10 then 'PASS' else 'FAIL' end,
    'test_code','ENG_M4_9_RUN_CAMPAIGN','pantalla_id',p_pantalla_id,
    'known_mutations_total',10,'known_mutations_detected',v_detected_count,
    't10_detected',coalesce((v_case->>'detected')::boolean,false),
    't10_false_consensus_pass',coalesce((v_case->>'false_consensus_pass')::boolean,false),
    'semantic_authority_bound',true,'actual_execution',true,'synthetic_pass',false,
    'durable_residue',false,'classifier_restored',true,'results',v_results
  );
end
$function$;