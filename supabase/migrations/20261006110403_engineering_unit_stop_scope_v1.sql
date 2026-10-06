create or replace function programacion.fn_engineering_unit_bootstrap_v3(
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_fast jsonb;
  v_payload jsonb;
  v_cp text;
  v_readiness jsonb;
  v_terminal text;
  v_continuation jsonb;
  v_execution_contract jsonb;
begin
  v_fast:=programacion.fn_engineering_unit_bootstrap_snapshot_v1(
    p_plan_code,p_unit_code
  );

  if coalesce((v_fast->>'snapshot_fast_path_supported')::boolean,false) then
    v_payload:=v_fast;
  else
    v_payload:=programacion.fn_engineering_unit_bootstrap_v3_legacy(
      p_plan_code,p_unit_code
    ) || jsonb_build_object(
      'engine_variant','LEGACY_FALLBACK_V3',
      'snapshot_fast_path_supported',false
    );
  end if;

  v_cp:=v_payload#>>'{current_checkpoint,checkpoint_code}';

  if v_cp is not null then
    v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(
      p_plan_code,
      p_unit_code,
      v_cp,
      coalesce(v_payload->'action_spec','{}'::jsonb),
      coalesce(v_payload->'execution_packet','{}'::jsonb)
    );

    v_payload:=v_payload||jsonb_build_object(
      'execution_readiness',v_readiness
    );

    if coalesce(v_payload->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT'
       and coalesce((v_readiness->>'execution_ready')::boolean,false)=false then
      v_payload:=v_payload
        || jsonb_build_object(
          'terminal_action','STOP_EXECUTION_PREFLIGHT',
          'execution_allowed',false,
          'preflight_block',jsonb_build_object(
            'status','NOT_READY',
            'checkpoint_code',v_cp,
            'reasons',v_readiness->'reasons',
            'gates',v_readiness->'gates',
            'next_action','FIX_PREFLIGHT_CONTRACT_BEFORE_CONNECTOR_EXECUTION'
          )
        );
    end if;
  end if;

  v_terminal:=coalesce(v_payload->>'terminal_action','');
  v_continuation:=jsonb_build_object(
    'terminal_scope',case
      when v_terminal='CONTINUE_CURRENT_CHECKPOINT' then 'CURRENT_UNIT'
      else 'CURRENT_UNIT_ONLY'
    end,
    'global_stop',false,
    'orchestrator_action',case
      when v_terminal='CONTINUE_CURRENT_CHECKPOINT' then 'EXECUTE_CURRENT_UNIT'
      else 'YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK'
    end,
    'selection_owner','ENGINEERING_SCHEDULER',
    'rule','NON_CONTINUE_TERMINAL_ACTION_STOPS_ONLY_CURRENT_UNIT; SCHEDULER MAY CONTINUE OTHER ELIGIBLE WORK'
  );

  v_execution_contract:=coalesce(v_payload->'execution_contract','{}'::jsonb)
    || jsonb_build_object(
      'terminal_action_scope','CURRENT_UNIT_ONLY_UNLESS_EXPLICIT_GLOBAL_STOP',
      'non_continue_terminal_behavior','YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK',
      'scheduler_continuation_owner','ENGINEERING_SCHEDULER',
      'global_stop_requires_explicit_flag',true
    );

  return v_payload || jsonb_build_object(
    'continuation_contract',v_continuation,
    'execution_contract',v_execution_contract
  );
end;
$function$;

insert into public.lf_error_knowledge (
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
  created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref
)
select
  gen_random_uuid(),
  'ENGINEERING-UNIT-STOP-SCOPE-001',
  'ENGINEERING_ORCHESTRATION',
  'terminal_action de una unidad no debe interpretarse como stop global del orquestador',
  'bootstrap_v3 devolvía STOP_EXECUTION_PREFLIGHT cuando el checkpoint actual no estaba executable-ready. Un consumidor podía interpretar ese STOP como fin de toda la corrida, aunque el bloqueo correspondía únicamente a la unidad actual y existiera trabajo elegible fuera de ella.',
  'La salida de bootstrap mezclaba dos alcances: decisión de ejecución de la unidad y decisión de continuidad del scheduler. terminal_action no declaraba explícitamente su scope.',
  'UNIT_STOP_MISREAD_AS_GLOBAL_STOP',
  'Mantener bootstrap_v3 unit-scoped. No seleccionar otra unidad dentro del bootstrap. Añadir continuation_contract que marque non-CONTINUE terminal actions como CURRENT_UNIT_ONLY, global_stop=false y orchestrator_action=YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK; ENGINEERING_SCHEDULER conserva ownership de selección de la siguiente unidad.',
  'PASS si una unidad con STOP_EXECUTION_PREFLIGHT conserva execution_allowed=false y el checkpoint bloqueado, pero continuation_contract declara CURRENT_UNIT_ONLY/global_stop=false/YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK. Nunca saltar checkpoints dentro de la misma unidad.',
  'HIGH',1,now(),now(),
  'IG_ENGINEERING_BOOTSTRAP_V3_CONTINUATION_SCOPE',
  'ACTIVO',
  'M4.4 live readback: STOP_EXECUTION_PREFLIGHT preserved, execution_allowed=false, terminal_scope=CURRENT_UNIT_ONLY, global_stop=false, scheduler action=YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK.',
  now(),now(),'OPERATION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
  'M4.4 ORACLE_FRAMEWORK_IMPL preflight + parallel continuation semantics',
  'supabase://programacion.fn_engineering_unit_bootstrap_v3'
where not exists (
  select 1 from public.lf_error_knowledge
  where codigo='ENGINEERING-UNIT-STOP-SCOPE-001'
);

do $$
declare
  v jsonb;
begin
  v:=programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.4'
  );

  if v#>>'{execution_contract,non_continue_terminal_behavior}'
       is distinct from 'YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK' then
    raise exception 'ENGINEERING_UNIT_STOP_SCOPE_SELFTEST_CONTRACT_MISSING';
  end if;

  if coalesce((v#>>'{continuation_contract,global_stop}')::boolean,true) then
    raise exception 'ENGINEERING_UNIT_STOP_SCOPE_SELFTEST_GLOBAL_STOP_TRUE';
  end if;
end;
$$;
