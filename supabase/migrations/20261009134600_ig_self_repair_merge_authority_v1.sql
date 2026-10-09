-- Existing merge process contract: fix self-authorization circularity without weakening ordinary changes.
-- Recovery is only a one-time, owner-authorized and independently evidenced repair
-- when SAFE_CHANGE_ADMISSION itself is incapable of classifying due to dependency drift.
-- Any ordinary merge, unrelated change, unknown PASE state or unverified negative => BLOCK.
create or replace function programacion.fn_engineering_merge_authorization_contract_v1()
returns jsonb language sql immutable set search_path to 'pg_catalog'
as $function$
select jsonb_build_object(
  'schema_version','ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1_1',
  'authorization_owner','PROCESS',
  'human_approval_required',false,
  'auto_merge_when_authorized',true,
  'authorization_capability','SAFE_CHANGE_ADMISSION',
  'required_execution_permission','DOWNSTREAM_EXECUTION_ELIGIBLE',
  'required_preconditions',jsonb_build_array(
    'EKB_PREFLIGHT_CLEAR','EXACT_HEAD_MATCH','PR_MERGEABLE_TRUE'
  ),
  'authority_self_repair_recovery',jsonb_build_object(
    'schema_version','ENGINEERING_AUTHORITY_SELF_REPAIR_RECOVERY_V1',
    'mode','CONSTRAINED_OWNER_AUTHORIZED_REPAIR',
    'applicability','ONLY_WHEN_OWN_ADMISSION_DEPENDENCY_CURRENTNESS_DRIFT_PROVEN',
    'authority_owner','SUPER_ADMIN',
    'owner_approval_required',true,
    'normal_safe_change_admission_eligible',false,
    'scope','EXACT_PR_HEAD_AND_AFFECTED_CAPABILITY_DEPENDENCY_CHAIN',
    'require',jsonb_build_array(
      'PROVEN_CURRENTNESS_DRIFT_ON_AUTHORIZATION_CAPABILITY',
      'OWNER_EXPLICIT_SCOPE_APPROVAL',
      'EKB_PREFLIGHT_CLEAR',
      'EXACT_HEAD_MATCH',
      'PR_MERGEABLE_TRUE',
      'EXACT_GIT_MIGRATION_SOURCE_READBACK',
      'INDEPENDENT_PYTHON_REGRESSION_POSITIVE_NEGATIVE_PASS',
      'TRANSACTIONAL_EXACT_SOURCE_ROLLBACK_NO_RESIDUE',
      'DOWNSTREAM_DEPENDENTS_IN_SAME_PATCH',
      'TRUSTED_BASE_PASE_APPLICABILITY_READBACK',
      'NO_PRODUCTION_ACTIVATION',
      'POST_MERGE_LEDGER_DB_PARITY'
    ),
    'validator_nature','CAPABILITY_CURRENTNESS_AND_GITHUB_SOURCE_PARITY_PLUS_REAL_EXECUTION_PROOF',
    'forbidden',jsonb_build_array(
      'SILENT_BYPASS','RETRY_UNKNOWN_CLASSIFICATION_AS_PASS',
      'USE_RECOVERY_WHEN_NORMAL_ADMISSION_HEALTHY','DOWNGRADE_PROVIDER_FOR_AUTHORIZATION',
      'TREAT_SKIPPED_CI_AS_PASS','ACTIVATE_REPAIRED_PROVIDER',
      'REUSE_AUTHORIZATION_ON_DIFFERENT_HEAD','APPLY_UNRELATED_CHANGES'
    ),
    'resolution','SELF_REPAIR_ONE_LOT_THEN_NORMAL_ADMISSION_REQUIRED',
    'fallback_to_normal_when_repaired',true,
    'fail_closed',true
  ),
  'pase_policy',jsonb_build_object(
    'repair_policy_id','PASE_CONTROL_REPAIR_QUARANTINE_V1',
    'repair_window_state','SUPPORTED',
    'activation_resolution','TRUSTED_BASE_EXACT_HEAD_READBACK_REQUIRED',
    'on_disabled','NOT_APPLICABLE',
    'disabled_skipped_workflow_is_pass',false,
    'on_enabled','REQUIRE_PASE_MERGE_POLICY_EFFECTIVE_ALLOW',
    'on_unknown','BLOCK',
    'observe_only_results_cannot_block_merge',true,
    'active_blocking_controls_require_exact_terminal_pass',true,
    'structural_governance_remains_fail_closed',true,
    'global_f09_f10_completion_required_for_ordinary_merge',false,
    'control_system_activation_requires_separate_terminal_qualification',true
  ),
  'forbidden',jsonb_build_array(
    'MERGE_WITHOUT_PROCESS_AUTHORIZATION','TREAT_RECOMMENDATION_AS_PERMISSION',
    'SKIP_EKB_PREFLIGHT','SKIP_ACTIVE_BLOCKING_CONTROL_WHEN_APPLICABLE',
    'TREAT_REPAIR_OBSERVE_ONLY_AS_MERGE_BLOCKER',
    'REQUIRE_GLOBAL_PASE_F09_F10_FOR_ORDINARY_MERGE',
    'MERGE_DIFFERENT_HEAD','TREAT_SKIPPED_WORKFLOW_AS_PASS',
    'ASSUME_DISABLED_WITHOUT_TRUSTED_BASE_READBACK'
  ),
  'on_authorized','MERGE_AND_CONTINUE_CURRENT_UNIT',
  'on_not_authorized','YIELD_CURRENT_UNIT_CONTINUE_SCHEDULER',
  'global_scheduler_stop',false,'fail_closed',true
);
$function$;


-- Read-only independent *eligibility* evaluator, not an autonomous merger.
-- Does not call the broken SAFE_CHANGE_ADMISSION or accept caller-provided version claims.
create or replace function programacion.fn_engineering_authority_self_repair_eligibility_v1(
 p_plan_code text,p_unit_code text)
returns jsonb language plpgsql stable
set search_path to 'pg_catalog','public','programacion'
as $function$
declare v_expected text;v_expected_sha text;v_current text;v_current_sha text;v_unit_exists boolean;v_safe_sha text;v_check jsonb;
begin
 select exists(select 1 from programacion.engineering_plan_units pu
 where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED')
 into v_unit_exists;
 if not v_unit_exists then
   return jsonb_build_object('status','BLOCK','code','UNIT_NOT_ASSIGNED',
     'execution_permission','NO_EXECUTION_PERMISSION');
 end if;
 select c.version,c.manifest_sha256,v.manifest#>>'{dependencies,INDEPENDENT_ASSURANCE,version}',
        v.manifest#>>'{dependencies,INDEPENDENT_ASSURANCE,manifest_sha256}'
   into v_current,v_safe_sha,v_expected,v_expected_sha
 from public.lf_capability_current c
 join public.lf_capability_version_registry v
 on v.capability_code=c.capability_code and v.version=c.version and v.manifest_sha256=c.manifest_sha256
 where c.capability_code='SAFE_CHANGE_ADMISSION';
 if not found or v_expected is null or v_expected_sha is null then
   return jsonb_build_object('status','BLOCK','code','AUTHORITY_MANIFEST_UNRESOLVED',
     'execution_permission','NO_EXECUTION_PERMISSION');
 end if;
 select version,manifest_sha256 into v_current,v_current_sha
 from public.lf_capability_current where capability_code='INDEPENDENT_ASSURANCE';
 if v_current is null or v_current_sha is null then
   return jsonb_build_object('status','BLOCK','code','ASSURANCE_PROVIDER_MISSING',
      'execution_permission','NO_EXECUTION_PERMISSION');
 end if;
 if v_expected=v_current and v_expected_sha=v_current_sha then
   return jsonb_build_object('status','NOT_APPLICABLE','code','NORMAL_ADMISSION_AVAILABLE',
     'execution_permission','NO_EXECUTION_PERMISSION','recovery_allowed',false);
 end if;
 if not exists(
  select 1 from programacion.engineering_work_blockers b
  join programacion.engineering_plan_units u on u.work_item_id=b.work_item_id
  where u.plan_code=p_plan_code and u.unit_code=p_unit_code and b.status='OPEN'
 ) then
   return jsonb_build_object('status','BLOCK','code','NO_OPEN_REPAIR_SCOPE',
      'execution_permission','NO_EXECUTION_PERMISSION');
 end if;
 return jsonb_build_object(
   'schema_version','ENGINEERING_AUTHORITY_SELF_REPAIR_ELIGIBILITY_V1',
   'status','REQUIRES_OWNER_AND_INDEPENDENT_PROOF',
   'code','PROVEN_AUTHORIZATION_SELF_DEPENDENCY_DRIFT',
   'unit',p_unit_code,'plan',p_plan_code,
   'broken_authorizer','SAFE_CHANGE_ADMISSION',
   'provider','INDEPENDENT_ASSURANCE',
   'expected_version',v_expected,'live_version',v_current,
   'expected_sha',v_expected_sha,'live_sha',v_current_sha,
   'recovery_allowed',false,
   'execution_permission','NO_EXECUTION_PERMISSION',
   'next_action','OWNER_APPROVAL_PLUS_EXACT_HEAD_GIT_PASE_PYTHON_ROLLBACK_PROOF',
   'normal_admission_bypassed',false
 );
end;
$function$;

insert into public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,source_ref)
select gen_random_uuid(),'ENGINEERING-AUTHORITY-SELF-REPAIR-CIRCULAR-001','GOVERNANCE_CURRENTNESS',
 'Autorizador sin recuperación independiente de su propia versión obsoleta',
 'Una capability de autorización nunca puede autorizar su propia reparación si primero exige estar sana.',
 'AUTO-MERGE contract always requires SAFE_CHANGE_ADMISSION even when SAFE_CHANGE_ADMISSION has independently proven dependency currentness drift.',
 'SELF_REPAIR_SCOPE -> explicit owner authorization + real independent execution proof + exact-head Git+PASE -> one-lot repair -> normal admission',
 'Usar autoridad de recuperación limitada en el contrato de merge existente: solo si el autorizador tiene drift propio comprobado y el owner aprueba explícitamente. Exigir EKB, PR exacto, PASE aplicable, 12 casos Python reales, SQL conjunto ROLLBACK con 0 residuos y todos consumidores afectados. Tras reconciliar pins, volver al flujo normal y no reusar esta excepción. No crear gate propio ni modificar reglas de producción.',
 'Verificar casos negativos: ninguna autorización si normal healthy, si PR head difiere, si owner no aprueba, si PASE UNKNOWN, si falta prueba positiva/negativa o rollback. Prueba positiva exclusivamente de repair scope cuando own currentness drift está probado.',
 'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','CANDIDATO',
 'M7.13 PR2100 / INDEPENDENT_ASSURANCE 1.0.1->2.0.1; Git exact-head replay, Python 12, SQL 5 reversible 0 residue',
 now(),now(),'programacion.fn_engineering_merge_authorization_contract_v1'
where not exists(select 1 from public.lf_error_knowledge where codigo='ENGINEERING-AUTHORITY-SELF-REPAIR-CIRCULAR-001');
