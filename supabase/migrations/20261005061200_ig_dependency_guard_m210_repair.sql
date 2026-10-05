-- Repair the exact bad edge created by the generic-runner defect and prevent recurrence.
create or replace function programacion.fn_guard_cancelled_required_dependency_v1()
returns trigger
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $$
declare v_status text;
begin
  if new.relation_type='REQUIRES' then
    select status into v_status from programacion.engineering_work_items where id=new.depends_on_work_item_id;
    if v_status='CANCELLED' then
      raise exception 'REQUIRES_CANCELLED_DEPENDENCY_FORBIDDEN: depends_on_work_item_id=%',new.depends_on_work_item_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_cancelled_required_dependency_v1 on programacion.engineering_work_dependencies;
create trigger trg_guard_cancelled_required_dependency_v1
before insert or update of depends_on_work_item_id,relation_type
on programacion.engineering_work_dependencies
for each row execute function programacion.fn_guard_cancelled_required_dependency_v1();

do $$
declare
  v_work_id bigint;
  v_bad_id bigint;
  v_refs jsonb;
  v_exit text := 'R11: las 9 unidades vigentes M2.1–M2.9 en DONE o FUSED con evidencia; handoff de cierre M2 registrado en lf_eventos y readback independiente (otra identidad) READBACK_VERIFICADO que recalcula los criterios de salida de cada unidad';
begin
  select pu.work_item_id into v_work_id
  from programacion.engineering_plan_units pu
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M2.10';

  select id into v_bad_id from programacion.engineering_work_items where work_code='PAULO-127';

  delete from programacion.engineering_work_dependencies
   where work_item_id=v_work_id
     and depends_on_work_item_id=v_bad_id
     and relation_type='REQUIRES';

  update programacion.engineering_work_checkpoints
     set title='Readback de dependencias canónicas M2.1–M2.9; confirmar 9/9 terminales y no mutar el grafo',
         updated_at=now(),
         updated_by_execution_id='CHATGPT-IG-GENERIC-RUNNER-HARDENING-20261005'
   where work_item_id=v_work_id and checkpoint_code='DEPENDENCY_WIRING';

  update programacion.engineering_work_checkpoints
     set title='Readback AS-IS del estado de las 9 unidades vigentes M2.1–M2.9 y sus checkpoints',
         updated_at=now(),
         updated_by_execution_id='CHATGPT-IG-GENERIC-RUNNER-HARDENING-20261005'
   where work_item_id=v_work_id and checkpoint_code='M2_UNITS_ASIS';

  select coalesce(jsonb_agg(ref order by ref),'[]'::jsonb) into v_refs
  from (
    select distinct coalesce(t.unit_code,dw.work_code) ref
    from programacion.engineering_work_dependencies d
    join programacion.engineering_work_items dw on dw.id=d.depends_on_work_item_id
    left join programacion.engineering_plan_units t
      on t.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and t.work_item_id=d.depends_on_work_item_id
    where d.work_item_id=v_work_id and d.relation_type='REQUIRES'
  ) q;

  update programacion.engineering_plan_units pu
     set exit_criterion=v_exit,
         unit_metadata=jsonb_set(
           jsonb_set(
             jsonb_set(
               jsonb_set(
                 jsonb_set(
                   jsonb_set(coalesce(pu.unit_metadata,'{}'::jsonb),'{exit_criterion}',to_jsonb(v_exit),true),
                   '{source_pack_v1,checkpoint_inputs,M2_UNITS_ASIS,inputs,queries}',
                   jsonb_build_array(
                     'select work_code,status,title from programacion.engineering_work_items where work_code in (''PAULO-017'',''PAULO-018'',''PAULO-019'',''PAULO-020'',''PAULO-021'',''PAULO-039'',''PAULO-128'',''PAULO-040'',''PAULO-041'') order by work_code'
                   ),true
                 ),
                 '{source_pack_v1,checkpoint_inputs,DEPENDENCY_WIRING,missing}','[]'::jsonb,true
               ),
               '{source_pack_v1,checkpoint_inputs,DEPENDENCY_WIRING,missing_typed}','[]'::jsonb,true
             ),
             '{source_pack_v1,exact_dependencies}',v_refs,true
           ),
           '{dependency_snapshot_v1}',jsonb_build_object(
             'refs',v_refs,
             'count',jsonb_array_length(v_refs),
             'rule','SOURCE_PACK_DEPENDENCIES_ARE_DERIVED_FROM_CANONICAL_GRAPH_NOT_MANUALLY_MAINTAINED',
             'contract','PLAN_DEPENDENCY_SNAPSHOT_V1',
             'authority','programacion.engineering_work_dependencies',
             'generated_at',now()
           ),true
         )
   where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M2.10';

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_id,'PLAN_CORRECTION',
    'M2.10 dependency graph repaired after generic-runner misclassification',
    'Removed only erroneous REQUIRES edge to orphan CANCELLED PAULO-127; retained valid M2.1–M2.9/T-CURR/T-SOURCE dependencies. DEPENDENCY_WIRING is now readback-only and exit criterion uses the 9 live M2 units.',
    'REBOOTSTRAP_V3',
    jsonb_build_array('supabase://programacion.engineering_work_dependencies/M2.10','supabase://programacion.engineering_plan_units/M2.10'),
    'CHATGPT-IG-GENERIC-RUNNER-HARDENING-20261005',now(),
    'CHATGPT-IG-GENERIC-RUNNER-HARDENING-20261005'
  );
end;
$$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,estado,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-CANCELLED-DEPENDENCY-GUARD-001','ENGINEERING_GOVERNANCE',
  'REQUIRES must never target a CANCELLED work item',
  'A readback checkpoint was misclassified as material and created a REQUIRES edge toward an orphan CANCELLED work item, blocking the unit after the write.',
  'Generic deliverable fallback allowed a verification checkpoint to mutate the dependency graph.',
  'readback checkpoint -> inferred materialization -> invalid cancelled dependency -> WAIT_DEPENDENCIES',
  'Reject INSERT/UPDATE of REQUIRES when the target work item is CANCELLED; readback/hallazgo checkpoints use NO_DOMAIN_MUTATION.',
  'PASS when no REQUIRES edge targets CANCELLED and attempts are rejected by trg_guard_cancelled_required_dependency_v1.',
  'HIGH','ACTIVO','EXECUTION',array['IG','ENGINEERING_AGENT'],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT','IG generic runner dependency mutation',
  'supabase://programacion.fn_guard_cancelled_required_dependency_v1'
)
on conflict (codigo) do update set
  titulo=excluded.titulo,descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,patron=excluded.patron,
  prevencion=excluded.prevencion,validacion=excluded.validacion,severidad=excluded.severidad,estado='ACTIVO',
  lifecycle_phase=excluded.lifecycle_phase,consumer_role=excluded.consumer_role,root_cause_family=excluded.root_cause_family,
  detectability=excluded.detectability,source_context=excluded.source_context,source_ref=excluded.source_ref;

update public.lf_error_knowledge
set prevencion='Use ENGINEERING_UNIT_BOOTSTRAP_V3 with ACTION_SPEC_V3. Obey terminal_action before action_spec. Read-only checkpoints expose mutation_policy=NO_DOMAIN_MUTATION; material checkpoints may touch only declared targets; undeclared shared/transversal abstractions and dependency-graph mutations are forbidden.'
where codigo='ENGINEERING-ACTION-SPEC-CONTRACT-001';
