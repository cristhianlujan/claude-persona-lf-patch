-- M1.8 final closure: exact Golden T0 reproduction + compatibility artifact/event.

do $pre$
begin
  if not exists (
    select 1
    from public.lf_eventos
    where id=20312
      and payload->>'snapshot_sha256'='476710dd85f597e30e94995dea2f168112c1798f69aed73c7720dd7b6dc4d0e9'
      and payload->>'rows'='611'
      and payload->>'screens'='13'
      and payload->>'families_per_screen'='47'
  ) then
    raise exception 'M18_GOLDEN_T0_AUTHORITY_MISSING_OR_DRIFTED';
  end if;
end;
$pre$;

update programacion.engineering_plan_units
set unit_metadata =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        coalesce(unit_metadata,'{}'::jsonb),
        '{source_pack_v1,checkpoint_inputs,REPRODUCE_513,missing}',
        '[]'::jsonb,
        true
      ),
      '{source_pack_v1,checkpoint_inputs,REPRODUCE_513,missing_typed}',
      '[]'::jsonb,
      true
    ),
    '{source_pack_v1,checkpoint_inputs,REPRODUCE_513,inputs,events}',
    '["event://20312"]'::jsonb,
    true
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M1.8';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'REPRODUCE_513',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','REPRODUCE_513',
      'checkpoint_title','Reproducir la salida 5.13 contra la golden sin cambiar comportamiento y comparar SHA',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','VERIFY_EXACT',
      'precision','EXPLICIT_FROZEN_GOLDEN_REPRODUCTION',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Frozen M0.6 run set reserializes to exactly 611 rows, 13 screens, 47 families, 122290 bytes, MD5 92434c2a... and SHA256 476710dd...; no mutable latest-run substitution.',
      'verification_queries',jsonb_build_array(
$q$
with frozen(run_id) as (
  values (373::bigint),(374),(507),(508),(510),(511),(490),(491),(492),(493),(494),(512),(496)
), rows as (
  select r.pantalla_id,r.id as run_id,a.family_code,
         a.coverage_status,a.story_ready_status,a.implementation_ready_status,
         a.qa_ready_status,a.production_ready_status,a.validator_outcome,
         r.contract_revision,a.curator_sha256,a.validator_sha256
  from frozen f
  join programacion.input_readiness_runs r on r.id=f.run_id
  join programacion.input_family_assessments a on a.run_id=r.id
), snap as (
  select string_agg(concat_ws('|',
           pantalla_id,run_id,family_code,coverage_status,story_ready_status,
           implementation_ready_status,qa_ready_status,production_ready_status,
           validator_outcome,contract_revision,curator_sha256,validator_sha256
         ),E'\n' order by pantalla_id,family_code) as body
  from rows
)
select
  (select count(*) from rows)=611 as rows_exact,
  (select count(distinct pantalla_id) from rows)=13 as screens_exact,
  (select count(distinct family_code) from rows)=47 as families_exact,
  octet_length(body)=122290 as bytes_exact,
  md5(body)='92434c2a0837b4579aa720e3366ccc2b' as md5_exact,
  encode(digest(body,'sha256'),'hex')='476710dd85f597e30e94995dea2f168112c1798f69aed73c7720dd7b6dc4d0e9' as sha256_exact
from snap
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'USE_LATEST_MUTABLE_RUNS',
        'REEXECUTE_M0_6',
        'CHANGE_CANONICAL_FIELD_ORDER',
        'MUTATE_DOMAIN_DATA'
      ),
      'contract_correction','FROZEN_RUN_SET_PLUS_CANONICAL_SERIALIZATION'
    ),
    'COMPAT_READBACK',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','COMPAT_READBACK',
      'checkpoint_title','Publicar contrato de compatibilidad en Git y evento con SHA idéntico',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'precision','EXPLICIT_GIT_EVENT_SHA_COMPATIBILITY_READBACK',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Compatibility artifact exists in Git and canonical event carries the identical Golden T0 SHA256; traceability revision 2 remains exact 62/62 against current 5.13.1 representation.',
      'verification_queries',jsonb_build_array(
$q$
with c as (
  select id,version_id,especificacion->>'contract_revision' as revision,
         md5(especificacion::text) as spec_md5
  from programacion.contratos
  where contrato_codigo='INPUT_READINESS_CONTRACT'
  order by version_id desc
  limit 1
), m as (
  select *
  from programacion.contract_traceability_matrices
  where source_plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and source_unit_code='M1.8'
  order by matrix_revision desc,id desc
  limit 1
), e as (
  select *
  from public.lf_eventos
  where evento_tipo='READBACK_VERIFICADO'
    and entidad_tipo='ENGINEERING_PLAN_UNIT'
    and entidad_codigo='PAULO-122'
    and payload->>'artifact_schema'='IG_M1_8_INPUT_READINESS_5_13_COMPATIBILITY_V1'
  order by id desc
  limit 1
)
select
  c.id=37 and c.version_id=19 and c.revision='5.13.1'
    and c.spec_md5='229eb569cf7e988ec1b222df91b70876' as contract_exact,
  m.id=3 and m.matrix_revision=2 and m.clause_count=62
    and m.matrix_sha256='2c1053d3e0ab451a26966ef9bddcfccf2292f6489e39edf8ec90543bd9fd062c' as matrix_exact,
  e.payload->>'snapshot_sha256'='476710dd85f597e30e94995dea2f168112c1798f69aed73c7720dd7b6dc4d0e9' as event_sha_exact,
  e.payload->>'git_artifact_path'='docs/input-governance/m1_8_input_readiness_5_13_compatibility_v1.json' as git_artifact_exact,
  e.payload->>'behavior_change'='false' as behavior_unchanged
from c cross join m cross join e
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'PUBLISH_WITH_DIFFERENT_GOLDEN_SHA',
        'REWRITE_HISTORICAL_MATRIX',
        'CLAIM_RUNTIME_OR_PRODUCTION_ACTIVATION'
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M1.8';

insert into public.lf_eventos(
  evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
)
select
  'READBACK_VERIFICADO',
  'ENGINEERING_PLAN_UNIT',
  'PAULO-122',
  'M1.8 compatibility contract: frozen 5.13 Golden T0 reproduces exact SHA and current 5.13.1 representation remains traceable 62/62.',
  'INFO',
  jsonb_build_object(
    'artifact_schema','IG_M1_8_INPUT_READINESS_5_13_COMPATIBILITY_V1',
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M1.8',
    'work_code','PAULO-122',
    'compatibility_baseline_revision','5.13',
    'current_representation_revision','5.13.1',
    'contract_id',37,
    'traceability_matrix_id',3,
    'traceability_matrix_revision',2,
    'traceability_matrix_sha256','2c1053d3e0ab451a26966ef9bddcfccf2292f6489e39edf8ec90543bd9fd062c',
    'golden_source_event','event://20312',
    'snapshot_rows',611,
    'snapshot_screens',13,
    'families_per_screen',47,
    'snapshot_md5','92434c2a0837b4579aa720e3366ccc2b',
    'snapshot_sha256','476710dd85f597e30e94995dea2f168112c1798f69aed73c7720dd7b6dc4d0e9',
    'canonical_bytes',122290,
    'git_artifact_path','docs/input-governance/m1_8_input_readiness_5_13_compatibility_v1.json',
    'behavior_change',false,
    'production_authorized',false
  ),
  'EXECUTION:CHATGPT-IG-M18-COMPAT-20261006',
  'CHATGPT-IG-M18-COMPAT-20261006'
where not exists (
  select 1
  from public.lf_eventos e
  where e.evento_tipo='READBACK_VERIFICADO'
    and e.entidad_tipo='ENGINEERING_PLAN_UNIT'
    and e.entidad_codigo='PAULO-122'
    and e.payload->>'artifact_schema'='IG_M1_8_INPUT_READINESS_5_13_COMPATIBILITY_V1'
);

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-M18-GOLDEN-T0-SOURCEPACK-STALE-001',
  'ENGINEERING_ORCHESTRATION',
  'Checkpoint source pack must not retain missing-upstream state after upstream closes',
  'M1.8 REPRODUCE_513 still declared Golden T0 de M0.6 no existe even though M0.6 was terminal DONE 7/7 with event 20312 and frozen 611-row Golden T0.',
  'Cached checkpoint input was not reconciled after upstream M0.6 closure.',
  'STALE_SOURCE_PACK_REPORTS_COMPLETED_UPSTREAM_AS_MISSING',
  'On upstream terminal transition, current checkpoint compilation must prefer live canonical dependency/evidence state and clear stale nonblocking missing entries before execution.',
  'M1.8 source pack now points to event://20312 with empty missing/missing_typed; exact frozen serialization reproduces bytes, MD5 and SHA256.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'event://20312; supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M1.8',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','INPUT_GOVERNANCE']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M1.8 REPRODUCE_513',
  'supabase://programacion.engineering_plan_units'
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
