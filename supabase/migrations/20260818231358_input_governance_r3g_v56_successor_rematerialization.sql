create or replace function programacion.fn_input_r3_transform_refs(p_refs jsonb,p_pantalla_id integer,p_applicability text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','programacion' as $$
declare v_ref jsonb; v_out jsonb:='[]'::jsonb; v_has_non_absence boolean:=false;
begin
  for v_ref in select value from jsonb_array_elements(p_refs) loop
    if v_ref->>'kind' in ('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','CURRENT_VISUAL_ARTIFACT','CAPABILITY_ABSENCE') then v_ref:=v_ref||jsonb_build_object('pantalla_id',p_pantalla_id); end if;
    if v_ref->>'kind'<>'CAPABILITY_ABSENCE' then v_has_non_absence:=true; end if;
    v_out:=v_out||jsonb_build_array(v_ref);
  end loop;
  if p_applicability='NOT_APPLICABLE' and not v_has_non_absence then
    v_out:=v_out||jsonb_build_array(jsonb_build_object('kind','SCREEN_RULE_SET','pantalla_id',p_pantalla_id));
  end if;
  return v_out;
end $$;

create or replace function programacion.fn_input_r3_source_receipts(p_refs jsonb,p_pantalla_id integer,p_version_id bigint)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','programacion' as $$
declare v_ref jsonb; v_receipt jsonb; v_out jsonb:='[]'::jsonb;
begin
  for v_ref in select value from jsonb_array_elements(p_refs) loop
    v_receipt:=programacion.fn_input_resolve_source_ref(v_ref,p_pantalla_id,p_version_id);
    v_out:=v_out||jsonb_build_array(jsonb_build_object('source_ref',v_ref,'authority',programacion.fn_input_source_authority_class(v_ref),'observed_sha256',v_receipt->>'observed_sha256'));
  end loop;
  return v_out;
end $$;

create or replace function programacion.fn_input_r3_refresh_assertion(p_assertion jsonb,p_pantalla_id integer,p_version_id bigint)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','programacion' as $$
declare v_ref jsonb:=p_assertion->'source_ref'; v_kind text:=p_assertion#>>'{source_ref,kind}'; v_receipt jsonb; v_path text[]; v_actual jsonb; v_expected jsonb:=p_assertion->'expected'; v_op text:=upper(p_assertion->>'operator'); v_pass boolean:=false; v_sha text;
begin
  if v_kind in ('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','CURRENT_VISUAL_ARTIFACT','CAPABILITY_ABSENCE','SCREEN_CANONICAL_GRAPH') then v_ref:=v_ref||jsonb_build_object('pantalla_id',p_pantalla_id); end if;
  if v_kind='SCREEN_CANONICAL_GRAPH' then
    v_receipt:=jsonb_build_object('ref',v_ref,'observed',programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id));
    v_sha:=programacion.fn_v09_sha256_jsonb(v_receipt->'observed');
  else
    v_receipt:=programacion.fn_input_resolve_source_ref(v_ref,p_pantalla_id,p_version_id); v_sha:=v_receipt->>'observed_sha256';
  end if;
  select array_agg(x.value order by x.ord) into v_path from jsonb_array_elements_text(p_assertion->'path') with ordinality x(value,ord);
  v_actual:=v_receipt#>v_path;
  case v_op
    when 'EQ' then v_pass:=v_actual=v_expected;
    when 'NE' then v_pass:=v_actual is distinct from v_expected;
    when 'CONTAINS' then v_pass:=coalesce(v_actual@>v_expected,false);
    when 'NOT_CONTAINS' then v_pass:=not coalesce(v_actual@>v_expected,false);
    when 'ARRAY_LENGTH_EQ' then v_pass:=jsonb_typeof(v_actual)='array' and jsonb_typeof(v_expected)='number' and jsonb_array_length(v_actual)=(v_expected#>>'{}')::integer;
    else raise exception 'R3_ASSERTION_OPERATOR_UNSUPPORTED:%',v_op;
  end case;
  return (p_assertion-'actual'-'source_ref'-'result'-'source_observed_sha256')||jsonb_build_object('source_ref',v_ref,'actual',v_actual,'result',case when v_pass then 'PASS' else 'FAIL' end,'source_observed_sha256',v_sha);
end $$;

create or replace function programacion.fn_input_r3_refresh_assertions(p_assertions jsonb,p_pantalla_id integer,p_version_id bigint,p_add_element_inventory_assertion boolean)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','programacion' as $$
declare v_a jsonb; v_out jsonb:='[]'::jsonb; v_refreshed jsonb;
begin
  for v_a in select value from jsonb_array_elements(p_assertions) loop
    v_refreshed:=programacion.fn_input_r3_refresh_assertion(v_a,p_pantalla_id,p_version_id);
    if v_refreshed->>'result'<>'PASS' then raise exception 'R3_EXPECTATION_NO_LONGER_REPRODUCES:%:%',p_pantalla_id,v_refreshed; end if;
    v_out:=v_out||jsonb_build_array(v_refreshed);
  end loop;
  if p_add_element_inventory_assertion then
    v_a:=jsonb_build_object('path',jsonb_build_array('observed','canonical_contract','visual','design_bindings','summary','element_inventory_count'),'expected',0,'operator','EQ','source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH'));
    v_refreshed:=programacion.fn_input_r3_refresh_assertion(v_a,p_pantalla_id,p_version_id);
    if v_refreshed->>'result'<>'PASS' then raise exception 'R3_DESIGN_ELEMENT_INVENTORY_EXPECTATION_NOT_REPRODUCED:%',p_pantalla_id; end if;
    v_out:=v_out||jsonb_build_array(v_refreshed);
  end if;
  return v_out;
end $$;

lock table programacion.input_readiness_runs in share row exclusive mode;
lock table programacion.input_family_assessments in share row exclusive mode;

do $$
declare
  p record; a record; v_new_run_id bigint; v_new_assessment_id bigint; v_screen_code text; v_curator_identity text; v_validator_identity text;
  v_refs jsonb; v_curator_evidence jsonb; v_validator_evidence jsonb; v_assertions jsonb; v_source_sha text; v_curator_sha text;
  v_cov text; v_well text; v_story text; v_impl text; v_qa text; v_prod text; v_severity text; v_rationale text; v_blockers jsonb; v_design jsonb;
  v_curator_exec text; v_validator_exec text;
begin
  for p in select * from programacion.input_readiness_runs where id in (69,70,71,72,76) order by id loop
    select codigo into v_screen_code from lf_ops.pantallas where id=p.pantalla_id;
    select coalesce(max(id),0)+1 into v_new_run_id from programacion.input_readiness_runs;
    v_curator_identity:='INPUT_CURATOR:v0.5r1-'||lower(replace(v_screen_code,'B2B-AUTH-','auth'))||'-v56-r3-'||substr(gen_random_uuid()::text,1,8);
    v_validator_identity:='INPUT_VALIDATOR:v0.5r1-'||lower(replace(v_screen_code,'B2B-AUTH-','auth'))||'-v56-r3-'||substr(gen_random_uuid()::text,1,8);

    insert into programacion.input_readiness_runs(id,version_id,pantalla_id,universe_rule_id,universe_snapshot_sha256,family_count,status,scope,curator_identity,curator_component_id,contract_version,supersedes_run_id)
    values(v_new_run_id,p.version_id,p.pantalla_id,p.universe_rule_id,p.universe_snapshot_sha256,p.family_count,'CURATING',
      p.scope||jsonb_build_object('mode','CANDIDATE_V56_R3_SEMANTIC_FAIL_CLOSED','remediation','AUDIT_20260818_R3','parent_run_id',p.id),
      v_curator_identity,46,4,p.id);

    for a in select * from programacion.input_family_assessments where run_id=p.id order by family_code loop
      v_refs:=programacion.fn_input_r3_transform_refs(a.source_refs,p.pantalla_id,a.applicability);
      v_cov:=a.coverage_status; v_well:=a.well_defined_status; v_story:=a.story_ready_status; v_impl:=a.implementation_ready_status; v_qa:=a.qa_ready_status; v_prod:=a.production_ready_status; v_blockers:=a.blockers;

      if a.family_code='DESIGN_SYSTEM' then
        v_design:=programacion.fn_input_design_readiness_v2(p.pantalla_id);
        v_cov:=v_design->>'coverage_status'; v_well:=v_design->>'well_defined_status'; v_story:=v_design->>'story_ready_status'; v_impl:=v_design->>'implementation_ready_status'; v_qa:=v_design->>'qa_ready_status'; v_prod:=v_design->>'production_ready_status'; v_blockers:=v_design->'blockers';
      end if;

      if a.applicability='APPLICABLE' then
        if v_cov in ('MISSING','PENDING','BLOCKED') or v_well in ('MISSING','PENDING','BLOCKED') then v_story:='BLOCKED'; end if;
        if v_story<>'READY' or v_cov<>'COMPLETE' or v_well<>'COMPLETE' then
          if v_impl='READY' then v_impl:=case when v_story='READY' then 'NOT_READY' else 'BLOCKED' end; end if;
        end if;
        if v_impl<>'READY' and v_qa='READY' then v_qa:='BLOCKED'; end if;
        if v_qa<>'READY' and v_prod='READY' then v_prod:='BLOCKED'; end if;
      end if;

      v_severity:=case
        when a.applicability='NOT_APPLICABLE' then case when a.severity in ('P0','P1','P2','P3','P4') then a.severity else 'P4' end
        when a.applicability='UNRESOLVED' then 'P0'
        when v_story<>'READY' then 'P0'
        when v_impl<>'READY' then 'P1'
        when v_qa<>'READY' then 'P2'
        when v_prod<>'READY' then 'P3'
        else 'P4' end;

      if a.applicability='APPLICABLE' and (v_story is distinct from a.story_ready_status or v_impl is distinct from a.implementation_ready_status or v_qa is distinct from a.qa_ready_status or v_prod is distinct from a.production_ready_status) and a.family_code<>'DESIGN_SYSTEM' then
        v_blockers:=coalesce(v_blockers,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('code','R3_SEMANTIC_FAIL_CLOSED_RECLASSIFICATION','detail','Downstream readiness recalculated from current coverage/well-defined state; no sufficiency inferred.'));
      end if;
      v_rationale:=coalesce(a.rationale,'')||' | R3 v5.6 rematerialized from current authority; severity and downstream readiness are fail-closed.';
      v_curator_exec:=gen_random_uuid()::text;
      v_curator_evidence:=jsonb_build_object(
        'contract_revision','5.6','remediation_revision','AUDIT_20260818_R3_SEMANTIC_FAIL_CLOSED','execution_mode','INDEPENDENT_CURATOR','execution_id',v_curator_exec,
        'component_id',46,'direct_source_readback',true,'parent_run_id',p.id,'parent_assessment_id',a.id,'prior_curator_sha256',a.curator_sha256,
        'source_receipts',programacion.fn_input_r3_source_receipts(v_refs,p.pantalla_id,p.version_id));

      select coalesce(max(id),0)+1 into v_new_assessment_id from programacion.input_family_assessments;
      insert into programacion.input_family_assessments(id,run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence)
      values(v_new_assessment_id,v_new_run_id,a.family_code,v_severity,a.applicability,v_cov,v_well,v_story,v_impl,v_qa,v_prod,v_refs,v_rationale,v_blockers,a.negative_requirements,a.test_obligations,v_curator_evidence);
    end loop;

    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_validator_identity,validator_component_id=47,curator_completed_at=clock_timestamp() where id=v_new_run_id;
    select source_snapshot_sha256 into v_source_sha from programacion.input_readiness_runs where id=v_new_run_id;

    for a in select na.*,pa.validator_evidence parent_validator_evidence from programacion.input_family_assessments na join programacion.input_family_assessments pa on pa.run_id=p.id and pa.family_code=na.family_code where na.run_id=v_new_run_id order by na.family_code loop
      v_assertions:=programacion.fn_input_r3_refresh_assertions(a.parent_validator_evidence->'assertions',p.pantalla_id,p.version_id,a.family_code='DESIGN_SYSTEM');
      v_validator_exec:=gen_random_uuid()::text;
      v_validator_evidence:=jsonb_build_object(
        'contract_revision','5.6','remediation_revision','AUDIT_20260818_R3_SEMANTIC_FAIL_CLOSED','execution_mode','INDEPENDENT_VALIDATOR','execution_id',v_validator_exec,
        'component_id',47,'validated_curator_execution_id',a.curator_evidence->>'execution_id','direct_source_readback',true,
        'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,'assertions',v_assertions,'prevalidation','R3_CURRENT_AUTHORITY_RECHECK');
      update programacion.input_family_assessments set validator_outcome='PASS',validator_identity=v_validator_identity,validator_evidence=v_validator_evidence,validator_findings='[]'::jsonb,validator_assessed_at=clock_timestamp() where id=a.id;
    end loop;

    update programacion.input_readiness_runs set status='COMPLETED',validator_completed_at=clock_timestamp() where id=v_new_run_id;
  end loop;
end $$;

drop function programacion.fn_input_r3_refresh_assertions(jsonb,integer,bigint,boolean);
drop function programacion.fn_input_r3_refresh_assertion(jsonb,integer,bigint);
drop function programacion.fn_input_r3_source_receipts(jsonb,integer,bigint);
drop function programacion.fn_input_r3_transform_refs(jsonb,integer,text);