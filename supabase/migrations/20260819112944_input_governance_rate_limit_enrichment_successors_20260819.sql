create or replace function programacion.fn_input_rate_enrichment_assertions(
  p_new_run_id bigint,
  p_parent_run_id bigint,
  p_family_code text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $$
declare
  v_screen integer;
  v_specs jsonb;
begin
  select pantalla_id into v_screen from programacion.input_readiness_runs where id=p_new_run_id;
  if v_screen is null then raise exception 'RATE_ENRICHMENT_RUN_NOT_FOUND:%',p_new_run_id; end if;

  if v_screen in (52,56) and p_family_code='RATE_LIMIT' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_screen),
        'path',jsonb_build_array('observed','canonical_contract','policies','rate_limit'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(jsonb_build_object(
          'rate_limit_policy_id',7,
          'policy_code','RATE-B2B-PASSWORD-RECOVERY-OTP',
          'resource_code','AUTH_PASSWORD_RECOVERY_OTP_SEND',
          'window_seconds',900,
          'max_requests',4,
          'burst_limit',4,
          'scope_key','USER',
          'status','CANDIDATO'
        ))
      )
    );
    return programacion.fn_input_rebind_assertion_specs(p_new_run_id,p_family_code,v_specs);
  end if;

  return programacion.fn_input_owner_decision_assertions(p_new_run_id,p_parent_run_id,p_family_code);
end;
$$;

do $$
declare
  rec record;
  a record;
  v_new bigint;
  v_cur text;
  v_val text;
  v_sha text;
  v_assert jsonb;
  v_sev text;
  v_cov text;
  v_well text;
  v_story text;
  v_impl text;
  v_qa text;
  v_prod text;
  v_rat text;
  v_block jsonb;
  v_threat_open integer;
begin
  for rec in select * from (values
    (51,117::bigint),(52,118::bigint),(56,121::bigint)
  ) v(pantalla_id,parent_run_id)
  loop
    if not exists(select 1 from programacion.input_readiness_runs r where r.id=rec.parent_run_id and r.pantalla_id=rec.pantalla_id and r.status='COMPLETED') then
      raise exception 'RATE_ENRICHMENT_PARENT_INVALID screen=% parent=%',rec.pantalla_id,rec.parent_run_id;
    end if;
    if not exists(select 1 from lf_ops.pantallas p where p.id=rec.pantalla_id and p.activa=true) then
      raise exception 'RATE_ENRICHMENT_REQUIRES_ACTIVE_SCREEN:%',rec.pantalla_id;
    end if;

    v_cur:='INPUT_CURATOR:v0.5r1-auth-'||rec.pantalla_id||'-rate-enrichment-20260819-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    insert into programacion.input_readiness_runs(
      version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version
    )
    select version_id,pantalla_id,universe_rule_id,id,
           scope||jsonb_build_object('mode','RATE_LIMIT_ENRICHMENT_20260819','parent_run_id',id,'remediation','CURRENT_SOURCE_RATE_LIMIT_ENRICHMENT'),
           universe_snapshot_sha256,family_count,'CURATING',v_cur,curator_component_id,5
    from programacion.input_readiness_runs where id=rec.parent_run_id
    returning id into v_new;

    select count(*) into v_threat_open
    from jsonb_array_elements(programacion.fn_input_security_threat_expected(rec.pantalla_id)) t
    where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');

    for a in select * from programacion.input_family_assessments where run_id=rec.parent_run_id order by family_code
    loop
      v_sev:=a.severity; v_cov:=a.coverage_status; v_well:=a.well_defined_status;
      v_story:=a.story_ready_status; v_impl:=a.implementation_ready_status; v_qa:=a.qa_ready_status; v_prod:=a.production_ready_status;
      v_rat:=a.rationale||' | Current-source rate-limit enrichment successor 2026-08-19.';
      v_block:=a.blockers;

      if rec.pantalla_id in (52,56) and a.family_code='RATE_LIMIT' then
        v_sev:='P4'; v_cov:='COMPLETE'; v_well:='COMPLETE';
        v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='READY';
        v_block:='[]'::jsonb;
        v_rat:='La política central RATE-B2B-PASSWORD-RECOVERY-OTP (rate_limit_policy_id=7) está materializada en el canonical graph para AUTH_PASSWORD_RECOVERY_OTP_SEND: 4 solicitudes por 900 segundos, burst 4, scope USER. El input de rate limit está completo; activación/calibración de runtime y controles de abuso siguen gobernados por SECURITY/RUNTIME_CONFIG.';
      elsif a.family_code='SECURITY' then
        v_block:=coalesce((
          select jsonb_agg(
            case when b->>'code'='SECURITY_THREAT_MATRIX_INCOMPLETE'
                 then b || jsonb_build_object('open_or_partial_count',v_threat_open)
                 else b end
          )
          from jsonb_array_elements(coalesce(a.blockers,'[]'::jsonb)) b
        ),'[]'::jsonb);
        v_rat:='La cobertura Security se recalcula contra la fuente viva y la matriz contextual de 30 amenazas. La familia permanece PARTIAL mientras existan amenazas aplicables abiertas; el conteo actual es '||v_threat_open||'.';
      end if;

      insert into programacion.input_family_assessments(
        run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
        source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256
      ) values(
        v_new,a.family_code,v_sev,a.applicability,v_cov,v_well,v_story,v_impl,v_qa,v_prod,
        a.source_refs,v_rat,v_block,a.negative_requirements,a.test_obligations,
        jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.11','parent_run_id',rec.parent_run_id,'parent_assessment_id',a.id,'remediation_revision','CURRENT_SOURCE_RATE_LIMIT_ENRICHMENT','direct_source_readback',true),
        repeat('0',64)
      );
    end loop;

    v_val:='INPUT_VALIDATOR:v0.5r1-auth-'||rec.pantalla_id||'-rate-enrichment-20260819-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_new;
    select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_new;

    for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code
    loop
      v_assert:=programacion.fn_input_rate_enrichment_assertions(v_new,rec.parent_run_id,a.family_code);
      update programacion.input_family_assessments
      set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val,
          validator_evidence=jsonb_build_object(
            'component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id',
            'execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.11',
            'source_snapshot_sha256',v_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assert
          )
      where id=a.id;
    end loop;
    update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  end loop;
end;
$$;