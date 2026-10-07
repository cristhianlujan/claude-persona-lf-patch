-- PROFILE_EVOLUTION_ORCHESTRATOR_CUTOVER_V1
-- Deliberately fail-closed. Do not apply until E10 admission exists and v0.1 executions are drained.

do $cutover$
declare
  v_exec constant text := 'EXEC-PROFILE-EVOLUTION-CUTOVER-V1-20261007';
  v_steps jsonb := '[{"step_id":"init_execution","purpose":"Crear execution_id y congelar contrato/políticas.","keys":["execution_id_created","target_code","target_path"],"order":0,"next":"router"},{"step_id":"router","purpose":"Resolver ACT-0001 y clasificar actualización de perfil.","keys":["router_read","action"],"order":10,"next":"profile_resolve"},{"step_id":"profile_resolve","purpose":"Resolver exactamente un perfil existente.","keys":["codigo_activo","profile_slug","repo_path","exact_profile_resolved"],"order":20,"next":"baseline_read"},{"step_id":"baseline_read","purpose":"Leer baseline exacta y separar compatibilidad S26 de capacidad.","keys":["baseline_revision","baseline_files","before_evidence","structural_status"],"order":30,"next":"profile_assessment"},{"step_id":"profile_assessment","purpose":"Evaluar madurez, gaps, incertidumbre y riesgo con evidencia.","keys":["schema","maturity","profile_gaps","write_authorized","admission_required"],"order":40,"next":"evolution_mode_selection"},{"step_id":"evolution_mode_selection","purpose":"Seleccionar NO_CHANGE/PATCH/SPECIALIZE/ADAPT/REARCHITECT/OPTIMIZE.","keys":["evolution_mode","mode_reason"],"order":50,"next":"method_capability_composition"},{"step_id":"method_capability_composition","purpose":"Componer capabilities y métodos por señales tipadas y presupuesto.","keys":["selected_capabilities","method_requirements","composition_order","estimated_cost","execution_authorized","admission_required"],"order":60,"next":"evolution_plan"},{"step_id":"evolution_plan","purpose":"Definir delta acotado, preservaciones, escalamiento y cortes.","keys":["evolution_plan","candidate_scope","preserved_constraints"],"order":70,"next":"candidate_materialization"},{"step_id":"candidate_materialization","purpose":"Materializar candidato reversible fuera de autoridad del perfil.","keys":["candidate_ref","candidate_sha","reversible","authority_state"],"order":80,"next":"benchmark_eval"},{"step_id":"benchmark_eval","purpose":"Comparar candidato contra baseline con holdout y métricas de seguridad/costo.","keys":["benchmark_ref","benchmark_verdict","critical_regressions","false_pass_not_worse","valid_behavior_preserved","cost_latency"],"order":90,"next":"challenge_assurance"},{"step_id":"challenge_assurance","purpose":"Desafiar candidato cuando aplique y obtener assurance independiente.","keys":["assurance_ref","assurance_verdict","open_challenges"],"order":100,"next":"admission"},{"step_id":"admission","purpose":"Admitir únicamente el candidato probado; optimizer no es autoridad.","keys":["admission_ref","admission_verdict","admitted_candidate_sha"],"order":110,"next":"regression_plan"},{"step_id":"regression_plan","purpose":"Congelar positivos, negativos, adversariales y holdout para actualización gobernada.","keys":["positive_cases","negative_cases","adversarial_cases","holdout"],"order":120,"next":"pre_write_execution_binding_gate"},{"step_id":"pre_write_execution_binding_gate","purpose":"Exigir binding exacto previo al write de fuente oficial.","keys":["execution_id","target_code","target_path","write_plan","pre_write_gate_passed"],"order":130,"next":"github_write"},{"step_id":"github_write","purpose":"Aplicar únicamente el candidato admitido preservando identidad.","keys":["branch","written_files","commit_sha","candidate_source_sha","identity_preserved"],"order":140,"next":"github_readback"},{"step_id":"github_readback","purpose":"Verificar exact-head, archivos e identidad.","keys":["exact_head","readback_files","sha_match","identity_preserved"],"order":150,"next":"deterministic_validation"},{"step_id":"deterministic_validation","purpose":"Ejecutar validators y negativos estructurales.","keys":["validator_result","malformed_input_result","negative_regressions"],"order":160,"next":"semantic_judge"},{"step_id":"semantic_judge","purpose":"Evaluar semántica, autoridad y consistencia Router/direct.","keys":["semantic_judge_result","authority_checks","router_direct_consistency"],"order":170,"next":"regression_after"},{"step_id":"regression_after","purpose":"Repetir BEFORE/adversariales/holdout.","keys":["before_after_matrix","adversarial_result","holdout_result"],"order":180,"next":"post_merge_reconcile"},{"step_id":"post_merge_reconcile","purpose":"Reconciliar fuente post-merge sin auto-promoción de runtime.","keys":["reconciliation_disposition","merge_sha","entrypoint_sha","manifest_sha","profile_pack_id","runtime_state_before","runtime_state_after","operational_state_preserved","automatic_impact_preserved","next_gate"],"order":190,"next":"evolution_state_record"},{"step_id":"evolution_state_record","purpose":"Registrar trayectoria evolutiva probada.","keys":["schema","evolution_state_ref","from_maturity","to_maturity","result","benchmark_ref","admission_ref"],"order":200,"next":"close"},{"step_id":"close","purpose":"Cerrar solo con gates limpios y sin impacto automático.","keys":["all_required_steps_clean","open_blockers","runtime_unchanged","no_auto_promotion"],"order":210,"next":"report_output"},{"step_id":"report_output","purpose":"Emitir cierre con evidencia y siguiente gate.","keys":["result","exact_head","evidence_refs","open_blockers","next_gate"],"order":220,"next":null}]'::jsonb;
  v_step jsonb;
  v_policy jsonb;
  v_policy_sha text;
  v_judge text;
begin
  if exists (
    select 1 from public.lf_operation_execution
    where operation_code='ACTUALIZACION_PERFIL_LF' and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_PROFILE_EVOLUTION_CUTOVER_OPEN_V01_EXECUTIONS';
  end if;

  if not exists (
    select 1 from public.lf_eventos
    where evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
      and entidad_tipo='OPERACION'
      and entidad_codigo='ACTUALIZACION_PERFIL_LF'
      and payload->>'status'='ADMIT_CUTOVER'
      and coalesce((payload->>'case_count')::integer,0) >= 20
      and payload->>'primary_capability_score_direction'='UP'
      and payload->>'holdout_direction'='UP'
      and coalesce((payload->>'critical_regressions')::integer,1)=0
      and coalesce((payload->>'false_pass_not_worse')::boolean,false)
      and coalesce((payload->>'valid_behavior_preserved')::boolean,false)
      and coalesce((payload->>'cost_latency_within_budget')::boolean,false)
      and payload->>'independent_assurance'='PASS'
      and coalesce((payload->>'paired_interval_predefined')::boolean,false)
      and btrim(coalesce(payload->>'benchmark_ref',''))<>''
      and btrim(coalesce(payload->>'safe_change_admission_ref',''))<>''
  ) then
    raise exception 'BLOCK_PROFILE_EVOLUTION_CUTOVER_E10_NOT_ADMITTED';
  end if;

  if not exists (select 1 from public.lf_capability_current where capability_code='PROFILE_ASSESSMENT' and version='1.0.0')
     or not exists (select 1 from public.lf_capability_current where capability_code='METHOD_PACK_REGISTRY' and version='1.0.0')
     or not exists (select 1 from public.lf_capability_current where capability_code='CAPABILITY_SELECTOR' and version='1.1.0') then
    raise exception 'BLOCK_PROFILE_EVOLUTION_CAPABILITIES_NOT_CURRENT';
  end if;

  update public.lf_operation_contracts
  set status='SUPERSEDED',updated_by_execution_id=v_exec,updated_at=now()
  where operation_code='ACTUALIZACION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';

  insert into public.lf_operation_contracts(
    operation_code,contract_code,contract_path,contract_sha,
    required_before_write,allowed,blocked,required_after_write,status,
    created_by_execution_id,updated_by_execution_id
  ) values (
    'ACTUALIZACION_PERFIL_LF',
    'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2',
    'skills/profile_creator/contracts/profile_evolution_orchestrator_v1.json',
    null,
    '["router_read","exact_profile_resolved","baseline_read","profile_assessment","evolution_mode_selected","method_capability_composition","evolution_plan","candidate_materialized","benchmark_pass","assurance_clean","admission_pass","regression_plan_defined","execution_bound_before_write","pre_write_gate_passed"]'::jsonb,
    '{"asset_type":"PERFIL","asset_must_exist":true,"candidate_materialization":true,"profile_source_write_after_admission":true,"minimal_patch_universal":false,"minimal_patch_when_mode":"PATCH","bounded_delta_required":true,"preserve_profile_slug":true,"preserve_codigo_activo":true,"github_readback_required":true,"runtime_enable":false,"validated_mark":false,"automatic_promotion":false,"merge_requires_explicit_user_approval":true}'::jsonb,
    '["profile_not_found","ambiguous_profile","create_new_profile","profile_source_write_before_admission","write_before_execution_binding","identity_change","profile_slug_change","runtime_enable","validated_mark","automatic_promotion","merge_without_explicit_user_approval","benchmark_regression","semantic_regression","router_direct_divergence","optimizer_self_admission"]'::jsonb,
    '["github_readback_exact_head","deterministic_validation_pass","semantic_judge_pass","regression_after_pass","post_merge_reconciliation","evolution_state_recorded","identity_preserved","no_runtime_change","no_automatic_promotion"]'::jsonb,
    'ACTIVE_ENFORCEMENT',v_exec,v_exec
  );

  delete from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_PERFIL_LF';
  delete from public.lf_operation_step_contracts where operation_code='ACTUALIZACION_PERFIL_LF';
  delete from public.lf_operation_steps where operation_code='ACTUALIZACION_PERFIL_LF';

  for v_step in select value from jsonb_array_elements(v_steps)
  loop
    insert into public.lf_operation_steps(
      operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,created_by_execution_id,updated_by_execution_id
    ) values (
      'ACTUALIZACION_PERFIL_LF',
      (v_step->>'order')::integer,
      v_step->>'step_id',
      true,
      array_to_string(array(select jsonb_array_elements_text(v_step->'keys')),','),
      'skills/profile_creator/contracts/profile_evolution_orchestrator_v1.json',
      null,true,(v_step->>'order')::integer,v_exec,v_exec
    );

    v_judge:=case when v_step->>'step_id'='pre_write_execution_binding_gate'
                  then 'JUDGE-ACTUALIZACION-PERFIL-LF-PREWRITE-BINDING-v1'
                  else 'JUDGE-ACTUALIZACION-PERFIL-LF-v0.1' end;

    insert into public.lf_operation_step_contracts(
      operation_code,step_id,step_order,execution_order,contract_code,purpose,
      input_required,resolver_ref,output_payload,pass_condition,block_condition,
      blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
      status,notes,created_by_execution_id,updated_by_execution_id
    ) values (
      'ACTUALIZACION_PERFIL_LF',v_step->>'step_id',(v_step->>'order')::integer,(v_step->>'order')::integer,
      'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2',v_step->>'purpose',
      '[]'::jsonb,'GPT_RUNTIME_WITH_SUPABASE_CONTEXT',v_step->'keys',
      '{"must_not_be_generic":true,"must_match_step_purpose":true}'::jsonb,
      '{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true}'::jsonb,
      'BLOCKED_PROFILE_EVOLUTION_'||upper(v_step->>'step_id')||'_NOT_CLEAN',
      v_judge,v_step->'keys',v_step->>'next','RETURN_TO_ROUTER',
      'ACTIVE_ENFORCEMENT',
      'Profile Evolution v0.2. Candidate work before admission is reversible and non-authoritative.',
      v_exec,v_exec
    );

    insert into public.lf_operation_step_judge_bindings(
      operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,
      return_result_value,required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
    ) values (
      'ACTUALIZACION_PERFIL_LF',(v_step->>'order')::integer,v_step->>'step_id',v_judge,
      'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
      v_step->'keys','ACTIVE_ENFORCEMENT',v_exec,v_exec
    );
  end loop;

  update public.lf_operation_registry
  set version='v0.2',
      operation_domain='PROFILE_EVOLUTION',
      operation_type='EVOLUTION_ORCHESTRATION',
      notes='PROFILE_EVOLUTION_ORCHESTRATOR: assess -> select/compose -> reversible candidate -> benchmark -> assurance -> admission -> governed update -> evolution state. S26 is structural compatibility; minimal patch is PATCH-only. Runtime/autopromotion remain forbidden.',
      updated_by_execution_id=v_exec,
      updated_at=now()
  where operation_code='ACTUALIZACION_PERFIL_LF';

  update public.lf_policy_versions
  set status='SUPERSEDED',superseded_at=now(),updated_by_execution_id=v_exec,updated_at=now()
  where policy_code='POL-PROFILE-UPDATE-PASS' and status='ACTIVE';

  v_policy:=jsonb_build_object(
    'authority','SUPABASE',
    'policy_id','POL-PROFILE-UPDATE-PASS',
    'policy_kind','PROFILE_EVOLUTION_PASS_POLICY',
    'applies_to_operation_code','ACTUALIZACION_PERFIL_LF',
    'required_steps','["init_execution","router","profile_resolve","baseline_read","profile_assessment","evolution_mode_selection","method_capability_composition","evolution_plan","candidate_materialization","benchmark_eval","challenge_assurance","admission","regression_plan","pre_write_execution_binding_gate","github_write","github_readback","deterministic_validation","semantic_judge","regression_after","post_merge_reconcile","evolution_state_record","close","report_output"]'::jsonb,
    'required_behaviors',jsonb_build_object(
      'ekb_first',true,'ekb_close',true,
      's26_structural_dimensions',13,
      's26_pass_semantics','STRUCTURALLY_COMPATIBLE',
      'minimal_patch_universal',false,
      'patch_mode_minimality',true,
      'profile_assessment_required',true,
      'method_capability_composition_required',true,
      'candidate_before_admission_is_non_authority',true,
      'benchmark_required',true,
      'independent_assurance_required_or_evidence_not_applicable',true,
      'safe_change_admission_required',true,
      'profile_source_write_before_admission',false,
      'evolution_state_required',true,
      'automatic_runtime_promotion',false,
      'optimizer_auto_admission',false,
      'github_readback_exact_head',true,
      'deterministic_validation',true,
      'semantic_judge',true,
      'adversarial_and_holdout',true,
      'post_merge_reconciliation',true
    ),
    'blocking_rules',jsonb_build_array(
      'BLOCK_PROFILE_EVOLUTION_EVIDENCE_INSUFFICIENT',
      'BLOCK_PROFILE_EVOLUTION_CANDIDATE_NOT_REVERSIBLE',
      'BLOCK_PROFILE_EVOLUTION_BENCHMARK_NOT_PASS',
      'BLOCK_PROFILE_EVOLUTION_ASSURANCE_NOT_CLEAN',
      'BLOCK_PROFILE_EVOLUTION_ADMISSION_NOT_PASS',
      'BLOCK_PROFILE_EVOLUTION_WRITE_NOT_BOUND_TO_ADMITTED_CANDIDATE',
      'BLOCK_PROFILE_EVOLUTION_STATE_NOT_PROVEN'
    )
  );
  v_policy_sha:=encode(extensions.digest(convert_to(v_policy::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_policy_versions(
    policy_code,policy_version,policy_payload,policy_sha,status,effective_at,source_ref,
    created_by_execution_id,updated_by_execution_id
  ) values (
    'POL-PROFILE-UPDATE-PASS','v1.2-profile-evolution',v_policy,v_policy_sha,'ACTIVE',now(),
    'skills/profile_creator/contracts/profile_evolution_orchestrator_v1.json',v_exec,v_exec
  );

  if (select count(*) from public.lf_operation_contracts
      where operation_code='ACTUALIZACION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT') <> 1 then
    raise exception 'BLOCK_PROFILE_EVOLUTION_ACTIVE_CONTRACT_NOT_EXACT_ONE';
  end if;
  if (select count(*) from public.lf_operation_steps
      where operation_code='ACTUALIZACION_PERFIL_LF' and active) <> jsonb_array_length(v_steps) then
    raise exception 'BLOCK_PROFILE_EVOLUTION_STEP_READBACK_MISMATCH';
  end if;
end
$cutover$;

-- Semantic gate exists only for v0.2 clean step writes.
create or replace function public.lf_profile_evolution_step_gate_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  v_manifest jsonb;
  v_admitted_sha text;
begin
  select manifest into v_manifest
  from public.lf_operation_execution
  where execution_id=new.execution_id and operation_code='ACTUALIZACION_PERFIL_LF';

  if v_manifest is null
     or coalesce(v_manifest->>'contract_code','') <> 'CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2'
     or new.status <> 'STEP_PASS_WITH_EVIDENCE' then
    return new;
  end if;

  if new.step_id='profile_assessment' then
    if new.evidence_payload->>'schema' <> 'PROFILE_ASSESSMENT_V1'
       or coalesce(new.evidence_payload->'write_authorized','true'::jsonb) <> 'false'::jsonb
       or coalesce(new.evidence_payload->'admission_required','false'::jsonb) <> 'true'::jsonb then
      raise exception 'PROFILE_EVOLUTION_ASSESSMENT_BOUNDARY_INVALID';
    end if;
  elsif new.step_id='evolution_mode_selection' then
    if coalesce(new.evidence_payload->>'evolution_mode','') not in ('NO_CHANGE','PATCH','SPECIALIZE','ADAPT','REARCHITECT','OPTIMIZE') then
      raise exception 'PROFILE_EVOLUTION_MODE_INVALID';
    end if;
  elsif new.step_id='method_capability_composition' then
    if coalesce(new.evidence_payload->'execution_authorized','true'::jsonb) <> 'false'::jsonb
       or coalesce(new.evidence_payload->'admission_required','false'::jsonb) <> 'true'::jsonb then
      raise exception 'PROFILE_EVOLUTION_SELECTION_AUTHORITY_LEAK';
    end if;
  elsif new.step_id='candidate_materialization' then
    if coalesce(new.evidence_payload->'reversible','false'::jsonb) <> 'true'::jsonb
       or new.evidence_payload->>'authority_state' <> 'NON_AUTHORITY_CANDIDATE'
       or coalesce(new.evidence_payload->>'candidate_sha','') !~ '^[0-9a-f]{40}$' then
      raise exception 'PROFILE_EVOLUTION_CANDIDATE_BOUNDARY_INVALID';
    end if;
  elsif new.step_id='benchmark_eval' then
    if new.evidence_payload->>'benchmark_verdict' <> 'PASS'
       or coalesce((new.evidence_payload->>'critical_regressions')::integer,1) <> 0
       or coalesce(new.evidence_payload->'false_pass_not_worse','false'::jsonb) <> 'true'::jsonb
       or coalesce(new.evidence_payload->'valid_behavior_preserved','false'::jsonb) <> 'true'::jsonb then
      raise exception 'PROFILE_EVOLUTION_BENCHMARK_NOT_ADMISSIBLE';
    end if;
  elsif new.step_id='challenge_assurance' then
    if coalesce(new.evidence_payload->>'assurance_verdict','') not in ('PASS','NOT_REQUIRED_WITH_EVIDENCE') then
      raise exception 'PROFILE_EVOLUTION_ASSURANCE_NOT_CLEAN';
    end if;
  elsif new.step_id='admission' then
    if new.evidence_payload->>'admission_verdict' <> 'PASS'
       or coalesce(new.evidence_payload->>'admitted_candidate_sha','') !~ '^[0-9a-f]{40}$' then
      raise exception 'PROFILE_EVOLUTION_ADMISSION_NOT_PASS';
    end if;
  elsif new.step_id='github_write' then
    select evidence_payload->>'admitted_candidate_sha' into v_admitted_sha
    from public.lf_operation_execution_steps
    where execution_id=new.execution_id and step_id='admission';
    if v_admitted_sha is null or new.evidence_payload->>'candidate_source_sha' <> v_admitted_sha then
      raise exception 'PROFILE_EVOLUTION_WRITE_NOT_BOUND_TO_ADMITTED_CANDIDATE';
    end if;
  elsif new.step_id='evolution_state_record' then
    if new.evidence_payload->>'schema' <> 'PROFILE_EVOLUTION_STATE_V1'
       or new.evidence_payload->>'result' <> 'ADMITTED'
       or btrim(coalesce(new.evidence_payload->>'benchmark_ref',''))=''
       or btrim(coalesce(new.evidence_payload->>'admission_ref',''))='' then
      raise exception 'PROFILE_EVOLUTION_STATE_NOT_PROVEN';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_profile_evolution_step_gate_v1 on public.lf_operation_execution_steps;
create trigger trg_profile_evolution_step_gate_v1
before insert or update on public.lf_operation_execution_steps
for each row execute function public.lf_profile_evolution_step_gate_v1();
