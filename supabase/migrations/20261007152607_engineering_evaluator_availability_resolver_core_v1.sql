create or replace function programacion.fn_engineering_evaluator_availability_resolve_v1(
   p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
 ) returns jsonb
 language plpgsql
 set search_path to programacion,public,pg_catalog
 as $$
 declare
   v_work_item_id bigint; v_meta jsonb; v_blocker text; v_eval text;
   v_resolution text; v_res jsonb;
 begin
   select pu.work_item_id,pu.unit_metadata into v_work_item_id,v_meta
   from programacion.engineering_plan_units pu
   where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

   select b.blocker_code into v_blocker
   from programacion.engineering_work_blockers b
   where b.work_item_id=v_work_item_id and b.status='OPEN'
     and b.blocker_code ilike '%EVALUATOR_MISSING%'
   order by b.id limit 1;

   if v_blocker is null then
     return jsonb_build_object('schema_version','ENGINEERING_EVALUATOR_AVAILABILITY_RESOLVER_V1',
       'status','NOT_APPLICABLE','state_changed',false);
   end if;

   v_eval:=nullif(v_meta#>>array['runtime_repair_inputs_v1',p_checkpoint_code,'evaluator','regprocedure'],'');
   if v_eval is null then
     return jsonb_build_object('schema_version','ENGINEERING_EVALUATOR_AVAILABILITY_RESOLVER_V1',
       'status','INPUT_REQUIRED_EVALUATOR_REGPROCEDURE','blocker_code',v_blocker,'state_changed',false);
   end if;

   if to_regprocedure(v_eval) is null then
     return jsonb_build_object('schema_version','ENGINEERING_EVALUATOR_AVAILABILITY_RESOLVER_V1',
       'status','EVALUATOR_NOT_CURRENT','blocker_code',v_blocker,'regprocedure',v_eval,'state_changed',false);
   end if;

   v_resolution:='supabase://pg_proc/'||v_eval||'#CURRENT';
   if not p_apply then
     return jsonb_build_object('schema_version','ENGINEERING_EVALUATOR_AVAILABILITY_RESOLVER_V1',
       'status','DRY_RUN_READY','blocker_code',v_blocker,'regprocedure',v_eval,'state_changed',false);
   end if;

   v_res:=programacion.fn_engineering_blocker_resolve_v1(
     p_plan_code,p_unit_code,v_blocker,v_resolution,'ENGINEERING_EVALUATOR_AVAILABILITY_RESOLVER_V1'
   );

   return jsonb_build_object(
     'schema_version','ENGINEERING_EVALUATOR_AVAILABILITY_RESOLVER_V1',
     'status',case when coalesce(v_res->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then 'EVALUATOR_AVAILABLE' else 'RESOLUTION_FAILED' end,
     'blocker_code',v_blocker,'regprocedure',v_eval,'result',v_res,
     'state_changed',coalesce(v_res->>'status','')='RESOLVED'
   );
 end; $$;