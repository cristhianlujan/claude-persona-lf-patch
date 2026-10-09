-- M4.2 oracle negative: explicit readback of the live transitive PASS gate.
-- No validator runtime mutation. The finding is contract/evidence drift, not a missing evaluator.

update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'NEG_PASS_WITHOUT_ORACLE',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','NEG_PASS_WITHOUT_ORACLE',
      'checkpoint_title','Negativo: ningún camino puede producir PASS sin ejecutar la fase oracle',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','VERIFY_EXACT',
      'precision','EXPLICIT_TRANSITIVE_ORACLE_GATE_READBACK',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','PASS is persistence-gated: validator rebind assertions are rebound/evaluated fail-closed and every terminal PASS update is re-evaluated by the enabled assessment guard before persistence.',
      'verification_queries',jsonb_build_array(
        $q$
with defs as (
  select
    pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure) as guard_def,
    pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure) as builder_def
), trg as (
  select count(*) filter (
           where p.proname='fn_guard_input_family_assessment_update'
             and t.tgenabled='O'
         ) as enabled_guard_count
  from pg_trigger t
  join pg_proc p on p.oid=t.tgfoid
  where t.tgrelid='programacion.input_family_assessments'::regclass
    and not t.tgisinternal
)
select
  trg.enabled_guard_count=1 as persistence_guard_enabled,
  position('fn_input_evaluate_assertion' in defs.guard_def)>0 as persistence_re_evaluates_assertions,
  position('VALIDATOR_ASSERTION_FAILED' in defs.guard_def)>0 as failed_assertion_blocks_pass,
  position('fn_input_rebind_assertion' in defs.builder_def)>0 as rebind_builder_executes_oracle,
  position('V58_REBOUND_ASSERTION_FAILED' in defs.builder_def)>0 as rebind_builder_fails_closed
from defs cross join trg
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'INFER_GATE_ONLY_FROM_WRITER_UPDATE_TEXT',
        'ADD_REDUNDANT_ASSERTION_ENGINE',
        'BYPASS_PERSISTENCE_GUARD'
      ),
      'contract_correction','TRANSITIVE_ORACLE_GATE_IS_BUILDER_PLUS_PERSISTENCE_GUARD'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.2';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-TRANSITIVE-VALIDATOR-GATE-STATIC-SCAN-001',
  'ENGINEERING_ORCHESTRATION',
  'Validator PASS gate must be evaluated across writer, builder and persistence guard',
  'A static scan of fn_input_governance_validator_rebind_v1 saw an unconditional PASS assignment and classified the path as PASS-without-oracle, but the called builder fails closed on rebound assertion FAIL and the enabled BEFORE UPDATE persistence guard re-evaluates every assertion before accepting PASS.',
  'Checkpoint verification inspected only the writer body and did not follow the transitive execution/persistence gate.',
  'LOCAL_WRITER_SCAN_MISCLASSIFIES_TRANSITIVE_FAIL_CLOSED_GATE',
  'For validator PASS-path audits, trace writer -> assertion builder/evaluator -> enabled persistence trigger. A direct PASS assignment is not sufficient evidence of false PASS when a mandatory downstream guard re-evaluates assertions fail-closed.',
  'Live readback 2026-10-06: fn_input_v58_build_assertions calls fn_input_rebind_assertion and raises V58_REBOUND_ASSERTION_FAILED; trg_input_family_assessment_update is enabled BEFORE UPDATE and fn_guard_input_family_assessment_update calls fn_input_evaluate_assertion, raising VALIDATOR_ASSERTION_FAILED when a PASS assertion does not evaluate true.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_input_v58_build_assertions; supabase://programacion.fn_guard_input_family_assessment_update; supabase://programacion.input_family_assessments#trg_input_family_assessment_update',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','PROCESS_DEPENDENT',
  'M4.2 NEG_PASS_WITHOUT_ORACLE contract correction',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M4.2'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();
