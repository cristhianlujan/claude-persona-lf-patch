-- PE10E phase-boundary contract; new governed v2 source, Train only.
-- Original v1 source remains unapplied and requires separate retirement.
begin;
do $repair$
declare
  m jsonb;
  s jsonb;
  v jsonb;
begin
  if exists (select 1 from supabase_migrations.schema_migrations
             where version='20261013001500')
  then raise exception 'PE10E_V2_OLD_MIGRATION_ALREADY_APPLIED'; end if;
  select unit_metadata into strict m
  from programacion.engineering_plan_units
  where plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    and unit_code='PE10E' for update;
  if m#>>'{action_specs_v1,PE10E_C4,action_kind}' is distinct from 'READBACK_ONCE'
     or m ? 'phase_separation_v1'
     or (select status from programacion.engineering_work_checkpoints
       where checkpoint_code='PE10E_C4'
         and work_item_id=(select work_item_id from programacion.engineering_plan_units
           where plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and unit_code='PE10E'))
       is distinct from 'PENDING'
  then raise exception 'PE10E_V2_PRESTATE_MISMATCH'; end if;
  s:=m#>'{action_specs_v1,PE10E_C4}' ||
    jsonb_build_object(
      'status','BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING',
      'action_kind','DECLARED_TEST_EXECUTION',
      'requires_material_execution',true,
      'verification_queries','[]'::jsonb,
      'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'schema','PROFILE_EXPERT_BEHAVIOR_SCORE_V1',
          'status','BENCHMARK_PASS','independent_assurance','PASS',
          'cutover_eligible',true,'critical_regressions',0)));
  v:=jsonb_build_object(
    'schema','PROFILE_EVOLUTION_PHASE_SEPARATION_V1',
    'first_evolution',jsonb_build_object(
      'status','CODE_MERGED_USER_ACCEPTED','merged_profile_count',9,
      'expertise_certified',false,'runtime_activated',false),
    'expert_certification',jsonb_build_object(
      'checkpoint','PE10E_C4','status','PENDING_GENUINE_GPT_NATIVE_AND_INDEPENDENT_REVIEW',
      'four_arm_required',true,'independent_judge_required',true),
    'v02_cutover_allowed',false);
  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(jsonb_set(m,'{action_specs_v1,PE10E_C4}',s,true),
      '{phase_separation_v1}',v,true)
  where plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and unit_code='PE10E';
  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(unit_metadata,'{phase_separation_v1}',
    jsonb_build_object('first_evolution_code_status','CODE_MERGED_USER_ACCEPTED',
      'expert_checkpoint','PE10E_C4','expert_gate_required_for_cutover',true,
      'runtime_activated',false),true)
  where plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and unit_code='PE10'
    and not (unit_metadata ? 'phase_separation_v1');
  if not found then raise exception 'PE10_V2_PRESTATE_DRIFT'; end if;
  if (select count(*) from public.lf_policy_versions
      where policy_code='POL-PROFILE-UPDATE-PASS' and status='ACTIVE'
        and policy_version='v1.1')<>1
  then raise exception 'PE10E_V2_ACTIVE_POLICY_DRIFT'; end if;
  if (select count(*) from public.lf_policy_versions
       where policy_code='POL-PROFILE-UPDATE-PASS'
         and policy_version='v1.3-phase-separation-candidate')<>0
  then raise exception 'PE10E_V2_CANDIDATE_EXISTS'; end if;
  if programacion.fn_engineering_unit_bootstrap_v3(
      'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10E'
      )#>>'{action_spec,status}' is distinct from
        'BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING'
  then raise exception 'PE10E_V2_BOOTSTRAP_NOT_BLOCKED'; end if;
end $repair$;
with p as (
  select policy_code,policy_payload ||
  jsonb_build_object('profile_evolution_phase_separation_v1',
    jsonb_build_object('phase1','CODE_ONLY_ACCEPTED',
      'expert_checkpoint','PE10E_C4','expert_admission',false,
      'production_activation',false,'source_contract',
      'skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json')
  ) as payload from public.lf_policy_versions
  where policy_code='POL-PROFILE-UPDATE-PASS'
    and policy_version='v1.1' and status='ACTIVE'
)
insert into public.lf_policy_versions(
  policy_code,policy_version,policy_payload,policy_sha,status,effective_at,source_ref,created_by_execution_id)
select policy_code,'v1.3-phase-separation-candidate',payload,
  encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),
  'CANDIDATE',clock_timestamp(),
  'skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json',
  'EXEC-PE-PHASE-BOUNDARY-20261012-001'
from p;
insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
select
  'LF-PE-PHASE-CONFLATION-20261012-001','PROFILE_EVOLUTION',
  'Release de codigo confundido con admision experta',
  'Primera evolucion aceptada no constituye benchmark experto ni habilita v0.2.',
  'PE10E_C4 exigia cuatro ejecuciones GPT_NATIVE y juez independiente, pero la accion READBACK_ONCE no tenia SQL.',
  'READ_QUERY_MISSING oculta la ausencia de productor y juez autenticos.',
  'Separar etapas; bloquear ejecucion experta sin trazabilidad; migraciones solo por Train.',
  'Positivo: codigo de 9 perfiles reconocido; negativo: experto sigue PENDING y policy activa v1.1.',
  'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10E_C4','ACTIVO',
  'skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json'
where not exists (select 1 from public.lf_error_knowledge
                  where codigo='LF-PE-PHASE-CONFLATION-20261012-001');
commit;
