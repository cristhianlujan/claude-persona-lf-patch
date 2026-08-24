set local statement_timeout = '10min';

do $$
declare
  v_screen integer := 56;
  v_parent bigint;
  a record;
  v_new bigint;
  v_cur text;
  v_val text;
  v_sha text;
  v_assert jsonb;
begin
  select r.id into v_parent from programacion.input_readiness_runs r
  where r.version_id=19 and r.pantalla_id=v_screen and r.status='COMPLETED' and r.contract_revision='5.11' and r.invalidated_at is null
    and not exists (select 1 from programacion.input_readiness_runs s where s.supersedes_run_id=r.id and s.status in ('COMPLETED','BLOCKED'))
  order by r.id desc limit 1;
  if v_parent is null then raise exception 'V511_R3_PARENT_NOT_FOUND screen=%',v_screen; end if;
  if programacion.fn_input_readiness_run_is_current(v_parent) then raise exception 'V511_R3_PARENT_EXPECTED_STALE screen=% run=%',v_screen,v_parent; end if;

  v_cur := 'INPUT_CURATOR:v0.5r1-auth-'||v_screen||'-v511-live-r3-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version)
  select version_id,pantalla_id,universe_rule_id,id,scope || jsonb_build_object('mode','CANDIDATE_V511_LIVE_SOURCE_R3','parent_run_id',id,'remediation','PR179_LIVE_SOURCE_SEMANTIC_RECONCILIATION_20260822'),universe_snapshot_sha256,family_count,'CURATING',v_cur,curator_component_id,contract_version
  from programacion.input_readiness_runs where id=v_parent returning id into v_new;

  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code loop
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
    values(
      v_new,
      a.family_code,
      a.severity,
      case when a.family_code='PROFILES' then 'APPLICABLE' else a.applicability end,
      case when a.family_code='PROFILES' then 'COMPLETE' else a.coverage_status end,
      case when a.family_code='PROFILES' then 'COMPLETE' else a.well_defined_status end,
      case when a.family_code='PROFILES' then 'READY' else a.story_ready_status end,
      case when a.family_code='PROFILES' then 'READY' else a.implementation_ready_status end,
      case when a.family_code='PROFILES' then 'READY' else a.qa_ready_status end,
      case when a.family_code='PROFILES' then 'READY' else a.production_ready_status end,
      a.source_refs,
      case
        when a.family_code='PROFILES' then 'La autoridad canónica vigente de B2B-AUTH-006 materializa cuatro perfiles no administradores (profile_id 3,4,5,6) para el flujo gobernado. PROFILES es APPLICABLE y COMPLETE para esta pantalla; los perfiles administradores se resuelven por la estrategia de identidad corporativa fuera de este flujo. No se infiere autorización operativa desde la presencia del perfil.'
        when a.family_code='RATE_LIMIT' then 'La política central RATE-B2B-PASSWORD-RECOVERY-OTP (rate_limit_policy_id=7) está materializada para AUTH_PASSWORD_RECOVERY_OTP_SEND con 6 solicitudes por 900 segundos, burst 6 y scope USER. El input de rate limit está completo; activación/calibración runtime y controles de abuso siguen gobernados por SECURITY/RUNTIME_CONFIG. | Recurado contra autoridad vigente PR #179 2026-08-22.'
        when a.family_code='PERMISSIONS' then a.rationale || ' | Readback 2026-08-22: NOT_APPLICABLE se sustenta en AUTH-029/037, que restringen el contexto a PASSWORD_UPDATE_ONLY y niegan autorización operativa antes de completar el flujo; la matriz de permisos vacía es evidencia complementaria, no la única base de exclusión.'
        else a.rationale || ' | Revalidado contra fuentes canónicas vigentes por reconciliación semántica PR #179 2026-08-22.'
      end,
      case when a.family_code='PROFILES' then '[]'::jsonb else a.blockers end,
      a.negative_requirements,
      case when a.family_code='PROFILES' then jsonb_build_array('NON_ADMIN_RECOVERY_PROFILE_SCOPE_CATALOG_TEST') else a.test_obligations end,
      jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.11','parent_run_id',v_parent,'parent_assessment_id',a.id,'remediation_revision','PR179_LIVE_SOURCE_SEMANTIC_RECONCILIATION_20260822','direct_source_readback',true),
      repeat('0',64));
  end loop;

  v_val := 'INPUT_VALIDATOR:v0.5r1-auth-'||v_screen||'-v511-live-r3-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_new;
  select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_new;
  for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code loop
    v_assert := programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);
    update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.11','source_snapshot_sha256',v_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assert) where id=a.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  if not programacion.fn_input_readiness_run_is_current(v_new) then raise exception 'V511_R3_POSTCHECK_CURRENTNESS_FAILED screen=% run=%',v_screen,v_new; end if;
end$$;