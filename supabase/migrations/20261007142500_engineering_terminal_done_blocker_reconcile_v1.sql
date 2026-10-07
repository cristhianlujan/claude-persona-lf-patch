-- Generic terminal-DONE blocker reconciliation.
-- Any OPEN blocker left behind after a unit is canonically DONE is stale by invariant.
-- Resolve it automatically; non-terminal units still require exact registered proof.

create or replace function programacion.fn_engineering_blocker_reconcile_v1(
  p_plan_code text,
  p_unit_code text,
  p_apply boolean default true
)
returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_work_status text;
  v_rules jsonb;
  v_rule jsonb;
  v_blocker record;
  v_kind text;
  v_pass boolean;
  v_source text;
  v_sig regprocedure;
  v_token text;
  v_suite record;
  v_bundle jsonb;
  v_expected int;
  v_resolution_ref text;
  v_result jsonb;
  v_items jsonb := '[]'::jsonb;
  v_resolved int := 0;
  v_checked int := 0;
begin
  select pu.work_item_id,wi.status,
         coalesce(pu.unit_metadata->'blocker_reconciliation_v1','{}'::jsonb)
    into v_work_item_id,v_work_status,v_rules
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items wi on wi.id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_BLOCKER_RECONCILE_V1',
      'status','NOT_FOUND',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code
    );
  end if;

  -- Global invariant: terminal DONE cannot legitimately retain an OPEN blocker.
  if v_work_status='DONE' then
    for v_blocker in
      select b.blocker_code
      from programacion.engineering_work_blockers b
      where b.work_item_id=v_work_item_id
        and b.status='OPEN'
      order by b.id
    loop
      v_checked:=v_checked+1;
      v_pass:=true;
      v_resolution_ref:='supabase://programacion.engineering_work_items/'||
        v_work_item_id::text||'#status=DONE';

      if p_apply then
        v_result:=programacion.fn_engineering_blocker_resolve_v1(
          p_plan_code,p_unit_code,v_blocker.blocker_code,
          v_resolution_ref,'ENGINEERING_BLOCKER_RECONCILE_V1'
        );
        if coalesce(v_result->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then
          v_resolved:=v_resolved+1;
        end if;
      end if;

      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'blocker_code',v_blocker.blocker_code,
        'kind','UNIT_TERMINAL_DONE',
        'proof_passed',true,
        'resolution_ref',v_resolution_ref,
        'applied',p_apply
      ));
    end loop;
  end if;

  -- For non-terminal units, reconcile only explicitly registered proof rules.
  if v_work_status<>'DONE' then
    for v_blocker in
      select b.blocker_code
      from programacion.engineering_work_blockers b
      where b.work_item_id=v_work_item_id
        and b.status='OPEN'
        and v_rules ? b.blocker_code
      order by b.id
    loop
      v_checked:=v_checked+1;
      v_rule:=v_rules->v_blocker.blocker_code;
      v_kind:=coalesce(v_rule->>'kind','');
      v_pass:=false;
      v_resolution_ref:=null;

      if v_kind='FUNCTION_SOURCE_CONTAINS_ALL' then
        begin
          v_sig:=to_regprocedure(v_rule->>'regprocedure');
        exception when others then
          v_sig:=null;
        end;

        if v_sig is not null
           and jsonb_typeof(v_rule->'tokens')='array'
           and jsonb_array_length(v_rule->'tokens')>0 then
          v_source:=pg_get_functiondef(v_sig);
          v_pass:=true;
          for v_token in
            select value from jsonb_array_elements_text(v_rule->'tokens')
          loop
            if position(v_token in v_source)=0 then
              v_pass:=false;
              exit;
            end if;
          end loop;

          if v_pass then
            v_resolution_ref:='supabase://'||(v_rule->>'regprocedure')||
              '#FUNCTION_SOURCE_CONTAINS_ALL';
          end if;
        end if;

      elsif v_kind='LATEST_SUITE_RUN_PASS' then
        v_expected:=nullif(v_rule->>'expected_tests','')::int;

        select s.*
          into v_suite
        from public.lf_test_suite_runs s
        where s.suite_code=v_rule->>'suite_code'
          and s.metadata->>'unit_code'=p_unit_code
          and s.metadata->>'checkpoint_code'=v_rule->>'checkpoint_code'
        order by s.created_at desc
        limit 1;

        if found then
          v_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite.suite_run_id);
          v_pass:=
            v_suite.status='PASSED'
            and (v_expected is null or v_suite.tests_total=v_expected)
            and v_suite.tests_total=v_suite.tests_passed
            and coalesce(v_suite.tests_failed,0)=0
            and coalesce(v_suite.tests_blocked,0)=0
            and coalesce(v_suite.tests_review_required,0)=0
            and v_bundle->>'status'='VERIFIED';

          if v_pass then
            v_resolution_ref:='supabase://public.lf_test_suite_runs/'||
              v_suite.suite_run_id::text||'#status=PASSED;receipt=VERIFIED';
          end if;
        end if;
      end if;

      if v_pass and p_apply then
        v_result:=programacion.fn_engineering_blocker_resolve_v1(
          p_plan_code,p_unit_code,v_blocker.blocker_code,
          v_resolution_ref,'ENGINEERING_BLOCKER_RECONCILE_V1'
        );
        if coalesce(v_result->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then
          v_resolved:=v_resolved+1;
        end if;
      end if;

      v_items:=v_items||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'blocker_code',v_blocker.blocker_code,
        'kind',v_kind,
        'proof_passed',v_pass,
        'resolution_ref',v_resolution_ref,
        'applied',v_pass and p_apply
      )));
    end loop;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_BLOCKER_RECONCILE_V1',
    'status',case
      when v_checked=0 then 'NOT_APPLICABLE'
      when v_resolved>0 then 'RECONCILED'
      else 'CHECKED_NO_RESOLUTION'
    end,
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'work_status',v_work_status,
    'checked',v_checked,
    'resolved',v_resolved,
    'items',v_items
  );
end;
$function$;

comment on function programacion.fn_engineering_blocker_reconcile_v1(text,text,boolean)
is 'Generic blocker reconciliation. Terminal DONE auto-resolves residual OPEN blockers by invariant; non-terminal units require explicit canonical proof rules.';

create or replace function programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  boot jsonb;
  cp text;
  st text;
  repair jsonb;
  blocker_reconcile jsonb;
  changed boolean:=false;
begin
  blocker_reconcile:=programacion.fn_engineering_blocker_reconcile_v1(
    p_plan_code,p_unit_code,true
  );

  boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  cp:=nullif(btrim(coalesce(boot#>>'{current_checkpoint,checkpoint_code}','')),'');

  if cp is null then
    return boot
      || jsonb_build_object('blocker_reconcile_auto',blocker_reconcile)
      || jsonb_build_object(
        'contract_repair_auto',
        jsonb_build_object(
          'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V5',
          'status','NOT_APPLICABLE',
          'reason','NO_CURRENT_CHECKPOINT'
        )
      );
  end if;

  st:=coalesce(boot#>>'{action_spec,status}','');

  repair:=programacion.fn_engineering_checkpoint_repair_dispatch_v2(
    p_plan_code,p_unit_code,cp,null,true
  );

  changed:=coalesce((repair->>'state_changed')::boolean,false);

  if changed then
    boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  end if;

  return boot
    || jsonb_build_object('blocker_reconcile_auto',blocker_reconcile)
    || jsonb_build_object(
      'contract_repair_auto',
      jsonb_build_object(
        'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V5',
        'checkpoint_code',cp,
        'detected_action_spec_status',st,
        'repair_dispatch_supported_error_classes',
          nullif(repair->>'supported_error_classes','')::int,
        'result',repair,
        'rebootstrap_after_repair',changed
      )
    );
end;
$function$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-TERMINAL-DONE-BLOCKER-RECONCILIATION-001',
  'ENGINEERING_ORCHESTRATION',
  'Terminal DONE units cannot retain OPEN blockers',
  'Historical blocker rows could remain OPEN after a unit reached canonical DONE, creating confusing reports even though effective scheduling ignored them.',
  'Blocker row lifecycle was not reconciled with terminal unit state.',
  'UNIT_DONE_WITH_RESIDUAL_OPEN_BLOCKER',
  'Before every repair-aware bootstrap, resolve any residual OPEN blocker when the canonical work item is already DONE. This rule is global and requires no unit-specific mapping.',
  'PASS when M3.9 remains DONE 100%, its residual blocker row becomes RESOLVED, and non-terminal real blockers remain OPEN.',
  'MEDIUM',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_blocker_reconcile_v1',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Terminal blocker lifecycle reconciliation',
  'supabase://programacion.fn_engineering_blocker_reconcile_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

do $selftest$
declare
  r jsonb;
  n int;
begin
  r:=programacion.fn_engineering_blocker_reconcile_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.9',true
  );

  select count(*) into n
  from programacion.engineering_work_blockers b
  where b.work_item_id=(
    select work_item_id
    from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code='M3.9'
  )
  and b.status='OPEN';

  if n<>0 then
    raise exception 'ENGINEERING_TERMINAL_BLOCKER_RECONCILE_SELFTEST_FAIL:%',r;
  end if;
end;
$selftest$;
