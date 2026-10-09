-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M5.6 / PAULO-071
-- Single invocable Curator persistence route without fusing strategy functions.
-- Scope: declared M5.6 Curator strategy functions only. No promotion/runtime activation.

do $m56$
declare
  v_sig constant regprocedure :=
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure;
  v_def text := pg_get_functiondef(v_sig);
  v_anchor text := E'  v_core_run_id:=nullif(v_result->>\'run_id\',\'\')::bigint;\n  if v_core_run_id is not null then';
  v_patch text := E'  v_core_run_id:=nullif(v_result->>\'run_id\',\'\')::bigint;\n'
    || E'  if v_strategy in (\'BOOTSTRAP\',\'REBIND\',\'SOURCE_STALE_RECURATE\',\'FULL_RECURATE\') then\n'
    || E'    if v_core_run_id is null then\n'
    || E'      raise exception \'M5_6_PERSISTENCE_PIPELINE_RUN_ID_MISSING:%\',v_strategy;\n'
    || E'    end if;\n'
    || E'    if not exists (select 1 from programacion.input_readiness_runs r where r.id=v_core_run_id and r.pantalla_id=p_pantalla_id) then\n'
    || E'      raise exception \'M5_6_PERSISTENCE_PIPELINE_RUN_READBACK_MISSING:%:%\',v_strategy,v_core_run_id;\n'
    || E'    end if;\n'
    || E'    if (select count(*) from programacion.input_family_assessments a where a.run_id=v_core_run_id)=0 then\n'
    || E'      raise exception \'M5_6_PERSISTENCE_PIPELINE_ASSESSMENTS_MISSING:%:%\',v_strategy,v_core_run_id;\n'
    || E'    end if;\n'
    || E'    v_result:=v_result || jsonb_build_object(\n'
    || E'      \'persistence_pipeline_receipt\',jsonb_build_object(\n'
    || E'        \'schema_version\',\'INPUT_GOVERNANCE_PERSISTENCE_PIPELINE_RECEIPT_V1\',\n'
    || E'        \'entrypoint\',\'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)\',\n'
    || E'        \'strategy\',v_strategy,\n'
    || E'        \'strategy_writer\',case v_strategy\n'
    || E'          when \'BOOTSTRAP\' then \'programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)\'\n'
    || E'          when \'REBIND\' then \'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)\'\n'
    || E'          when \'SOURCE_STALE_RECURATE\' then \'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)\'\n'
    || E'          when \'FULL_RECURATE\' then \'programacion.fn_input_governance_recurate_v2(integer,text,text)\' end,\n'
    || E'        \'run_id\',v_core_run_id,\n'
    || E'        \'run_count\',(select count(*) from programacion.input_readiness_runs r where r.id=v_core_run_id),\n'
    || E'        \'assessment_count\',(select count(*) from programacion.input_family_assessments a where a.run_id=v_core_run_id),\n'
    || E'        \'gap_proposal_count\',(select count(*) from programacion.input_gap_proposals g where g.run_id=v_core_run_id),\n'
    || E'        \'receipt_mode\',\'RETURN_ENVELOPE_READBACK\',\n'
    || E'        \'strategy_functions_fused\',false,\n'
    || E'        \'promotion_authorized\',false,\n'
    || E'        \'production_authorized\',false\n'
    || E'      )\n'
    || E'    );\n'
    || E'  end if;\n'
    || E'  if v_core_run_id is not null then';
begin
  if position('INPUT_GOVERNANCE_PERSISTENCE_PIPELINE_RECEIPT_V1' in v_def)=0 then
    if position(v_anchor in v_def)=0 then
      raise exception 'M5_6_CURATOR_MATERIALIZER_PATCH_ANCHOR_MISSING';
    end if;
    v_def:=replace(v_def,v_anchor,v_patch);
    execute v_def;
  end if;
end
$m56$;

-- Internal strategy writers remain distinct, but are no longer directly invocable
-- by application roles. The SECURITY DEFINER Curator materializer remains their
-- single execution route.
revoke execute on function programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)
  from public,anon,authenticated,service_role;
revoke execute on function programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)
  from public,anon,authenticated,service_role;
revoke execute on function programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)
  from public,anon,authenticated,service_role;
revoke execute on function programacion.fn_input_governance_recurate_v2(integer,text,text)
  from public,anon,authenticated,service_role;

grant execute on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)
  to service_role;

comment on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) is
'M5.6 single Curator materialization route. BOOTSTRAP, REBIND, SOURCE_STALE_RECURATE and FULL_RECURATE remain separate strategy functions, execute only behind this SECURITY DEFINER entrypoint, and return one INPUT_GOVERNANCE_PERSISTENCE_PIPELINE_RECEIPT_V1 readback envelope.';

do $verify$
declare
  v_def text;
  v_public_def text;
begin
  v_def:=pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  );
  v_public_def:=pg_get_functiondef(
    'public.fn_input_governance_curator_materialize_v1(integer,text,text)'::regprocedure
  );

  if position('INPUT_GOVERNANCE_PERSISTENCE_PIPELINE_RECEIPT_V1' in v_def)=0
     or position('fn_input_governance_bootstrap_materialize_v2' in v_def)=0
     or position('fn_input_governance_curator_rebind_v1' in v_def)=0
     or position('fn_input_governance_recurate_source_stale_v1' in v_def)=0
     or position('fn_input_governance_recurate_v2' in v_def)=0 then
    raise exception 'M5_6_SINGLE_PIPELINE_SOURCE_READBACK_FAILED';
  end if;

  if has_function_privilege('service_role','programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)','EXECUTE')
     or has_function_privilege('service_role','programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)','EXECUTE')
     or has_function_privilege('service_role','programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)','EXECUTE')
     or has_function_privilege('service_role','programacion.fn_input_governance_recurate_v2(integer,text,text)','EXECUTE')
     or has_function_privilege('anon','programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)','EXECUTE')
     or has_function_privilege('authenticated','programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)','EXECUTE')
     or has_function_privilege('anon','programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)','EXECUTE')
     or has_function_privilege('authenticated','programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)','EXECUTE')
     or has_function_privilege('anon','programacion.fn_input_governance_recurate_v2(integer,text,text)','EXECUTE')
     or has_function_privilege('authenticated','programacion.fn_input_governance_recurate_v2(integer,text,text)','EXECUTE') then
    raise exception 'M5_6_DIRECT_STRATEGY_EXECUTE_REMAINS';
  end if;

  if not has_function_privilege(
       'service_role',
       'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)',
       'EXECUTE'
     ) then
    raise exception 'M5_6_CANONICAL_ENTRYPOINT_NOT_EXECUTABLE';
  end if;

  if position(
       'programacion.fn_input_governance_curator_materialize_v1' in v_public_def
     )=0 then
    raise exception 'M5_6_PUBLIC_FACADE_NOT_ROUTED_TO_CANONICAL_ENTRYPOINT';
  end if;
end
$verify$;
