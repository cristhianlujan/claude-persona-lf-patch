-- IG_CURATOR_VALIDATOR_REFACTOR_V2 - bounded graph repair + derived snapshot synchronization.
-- EKB IG-PLAN-SOURCEPACK-DEPENDENCY-DRIFT-001.
-- M3.10 retirement is explicitly deferred into M10.12, not a blocking prerequisite of M3.11 handoff.
-- Readback must retain ownership transfer; never treat M10.12 as DONE or reopen historical DONE units.
do $repair$
declare
  v_unit bigint;
  v_target bigint;
  v_deleted int;
begin
  select work_item_id into v_unit from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M3.11' and disposition='ASSIGNED';
  select work_item_id into v_target from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.12' and disposition='ASSIGNED';
  if v_unit is null or v_target is null then raise exception 'IG_M311_M1012_IDENTITY_MISSING'; end if;
  delete from programacion.engineering_work_dependencies d
  where d.id=3157 and d.work_item_id=v_unit and d.depends_on_work_item_id=v_target
    and d.relation_type='REQUIRES'
    and d.created_by_execution_id='CHATGPT-M3-11-CLOSURE-WIRING-20261006';
  get diagnostics v_deleted=row_count;
  if v_deleted<>1 then raise exception 'IG_M311_DEFERRED_DEPENDENCY_DRIFT:%',v_deleted; end if;
  update programacion.engineering_plan_units u set
    exit_criterion=replace(
      u.exit_criterion,
      'FUSED con destino DONE',
      'FUSED con destino DONE, excepto retiro M3.10 FUSED->M10.12, transferido explícitamente como ejecución diferida no bloqueante'),
    unit_metadata=jsonb_set(
      u.unit_metadata,'{deferred_lifecycle_transfer_v1}',
      jsonb_build_object('source_unit','M3.10','target_unit','M10.12',
         'reason','PHYSICAL_RETIREMENT_BELONGS_TO_LATER_M10_PHASE',
         'handoff_requirement','RECORD_OWNER_AND_PENDING_STATUS_NOT_SYNTHETIC_DONE',
         'blocking_dependency',false,'owner_remains','M10.12',
         'evidence','programacion.engineering_work_dependencies#3157 removed as cross-phase gate'),
      true)
  where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and u.unit_code='M3.11'
    and u.exit_criterion like '%FUSED con destino DONE%';
  if not found then raise exception 'IG_M311_EXIT_CRITERION_MISSING'; end if;
end $repair$;

with actual as (
 select u.unit_code,
    coalesce((
      select jsonb_agg(to_jsonb(x.dep_code) order by x.dep_code)
      from (
        select distinct coalesce(t.unit_code,tw.work_code) dep_code
        from programacion.engineering_work_dependencies d
        left join programacion.engineering_plan_units t on t.work_item_id=d.depends_on_work_item_id and t.plan_code=u.plan_code
        left join programacion.engineering_work_items tw on tw.id=d.depends_on_work_item_id
        where d.work_item_id=u.work_item_id and d.relation_type='REQUIRES'
      ) x
      where x.dep_code is not null
    ),'[]'::jsonb) deps
 from programacion.engineering_plan_units u
 where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and u.disposition='ASSIGNED'
    and u.unit_code in ('M3.11','M5.4','M5.8','M9.3','M9.5')
)
update programacion.engineering_plan_units u
set unit_metadata=jsonb_set(
      jsonb_set(u.unit_metadata,'{source_pack_v1,exact_dependencies}',a.deps,true),
      '{dependency_snapshot_v1}',
      (coalesce(u.unit_metadata->'dependency_snapshot_v1','{}'::jsonb)
       || jsonb_build_object('refs',a.deps,'count',jsonb_array_length(a.deps),'generated_at',now(),
            'authority','programacion.engineering_work_dependencies'))
       || case when u.unit_code='M3.11' then
          jsonb_build_object(
             'effective_fused_targets',jsonb_build_object('M3.3','M1.4'),
             'deferred_fused_targets',jsonb_build_object('M3.10','M10.12'))
          else '{}'::jsonb end,
      true)
from actual a
where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and u.unit_code=a.unit_code;

do $verify$
declare
 v_mismatch int;
 v_link int;
 v_self int;
begin
 select count(*) into v_link from programacion.engineering_work_dependencies d
 join programacion.engineering_plan_units u on u.work_item_id=d.work_item_id
 where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 and u.unit_code='M3.11'
 and d.depends_on_work_item_id=(select work_item_id from programacion.engineering_plan_units
    where plan_code=u.plan_code and unit_code='M10.12');
 if v_link<>0 then raise exception 'IG_M311_M1012_STILL_BLOCKING';end if;
 select count(*) into v_self
 from programacion.engineering_work_dependencies d
 join programacion.engineering_plan_units u on u.work_item_id=d.work_item_id
 where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 and d.work_item_id=d.depends_on_work_item_id;
 if v_self<>0 then raise exception 'IG_PLAN_SELF_DEPENDENCY:%',v_self;end if;
 with actual as (
  select u.unit_code,u.unit_metadata,
    coalesce((select jsonb_agg(to_jsonb(x.dep_code) order by x.dep_code)
      from (select distinct coalesce(t.unit_code,tw.work_code) dep_code
        from programacion.engineering_work_dependencies d
        left join programacion.engineering_plan_units t on t.work_item_id=d.depends_on_work_item_id and t.plan_code=u.plan_code
        left join programacion.engineering_work_items tw on tw.id=d.depends_on_work_item_id
        where d.work_item_id=u.work_item_id and d.relation_type='REQUIRES')x
      where x.dep_code is not null),'[]'::jsonb) deps
  from programacion.engineering_plan_units u
  where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and u.disposition='ASSIGNED'
 )
 select count(*) into v_mismatch from actual
 where deps is distinct from coalesce(unit_metadata#>'{source_pack_v1,exact_dependencies}','[]'::jsonb)
    or deps is distinct from coalesce(unit_metadata#>'{dependency_snapshot_v1,refs}','[]'::jsonb)
    or jsonb_array_length(deps) is distinct from (unit_metadata#>>'{dependency_snapshot_v1,count}')::int;
 if v_mismatch<>0 then raise exception 'IG_DEPENDENCY_SNAPSHOT_DRIFT_REMAINS:%',v_mismatch;end if;
end $verify$;
