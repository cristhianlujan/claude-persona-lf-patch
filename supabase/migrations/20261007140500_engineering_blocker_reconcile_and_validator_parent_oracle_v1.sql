-- Generic blocker reconciliation + successor-validator frozen-parent oracle.
-- Root causes:
--   1) repaired causes could leave OPEN blockers stale in the scheduler;
--   2) successor validation conditionally fell back to current bootstrap assertions,
--      allowing correlated Curator/Resolver defects to false-PASS.
--
-- Unit-specific facts remain metadata only. Procedure logic is generic by proof kind.

do $patch_validator$
declare
  v_sig regprocedure := 'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure;
  v_def text;
  v_old text := $old$
    v_assertions:=case
      when v_parent is not null
       and not exists (
         select 1
         from programacion.input_family_assessments pa
         cross join lateral jsonb_array_elements(
           programacion.fn_input_validator_evidence_rehydrate_v1(pa.validator_evidence)->'assertions'
         ) x(value)
         where pa.run_id=v_parent
           and pa.family_code=a.family_code
           and x.value#>>'{source_ref,kind}'='CONTRACT'
       )
      then programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)
      else programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code)
    end;
$old$;
  v_new text := $new$
    v_assertions:=case
      when v_parent is not null
      then programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)
      else programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code)
    end;
$new$;
begin
  v_def:=pg_get_functiondef(v_sig);

  if position(v_new in v_def)>0 then
    return;
  end if;

  if position(v_old in v_def)=0 then
    raise exception 'IG_VALIDATOR_PARENT_ORACLE_PATCH_ANCHOR_MISSING';
  end if;

  v_def:=replace(v_def,v_old,v_new);
  execute v_def;

  v_def:=pg_get_functiondef(v_sig);
  if position(v_new in v_def)=0 or position(v_old in v_def)>0 then
    raise exception 'IG_VALIDATOR_PARENT_ORACLE_PATCH_POSTCHECK_FAILED';
  end if;
end;
$patch_validator$;

comment on function programacion.fn_input_governance_validate_v2(bigint,text)
is 'Successor runs always derive Validator assertions from the frozen parent via fn_input_v58_build_assertions; only root/bootstrap runs use current bootstrap assertions. Prevents correlated Curator/Resolver false consensus.';

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
  select pu.work_item_id,
         coalesce(pu.unit_metadata->'blocker_reconciliation_v1','{}'::jsonb)
    into v_work_item_id,v_rules
  from programacion.engineering_plan_units pu
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
          v_resolution_ref:='supabase://'||(v_rule->>'regprocedure')||'#FUNCTION_SOURCE_CONTAINS_ALL';
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
          v_resolution_ref:='supabase://public.lf_test_suite_runs/'||v_suite.suite_run_id::text||
            '#status=PASSED;receipt=VERIFIED';
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

  return jsonb_build_object(
    'schema_version','ENGINEERING_BLOCKER_RECONCILE_V1',
    'status',case
      when v_checked=0 then 'NOT_APPLICABLE'
      when v_resolved>0 then 'RECONCILED'
      else 'CHECKED_NO_RESOLUTION'
    end,
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checked',v_checked,
    'resolved',v_resolved,
    'items',v_items
  );
end;
$function$;

comment on function programacion.fn_engineering_blocker_reconcile_v1(text,text,boolean)
is 'Generic data-driven blocker reconciliation. Supports canonical proof kinds and resolves only when current live evidence satisfies the registered rule. No unit-code branching.';

-- Register M4.9 proof rules as data only.
update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  coalesce(pu.unit_metadata,'{}'::jsonb),
  '{blocker_reconciliation_v1}',
  coalesce(pu.unit_metadata->'blocker_reconciliation_v1','{}'::jsonb)
  || jsonb_build_object(
    'M49_RECURATE_V2_UNCACHED_TIMEOUT',
    jsonb_build_object(
      'kind','FUNCTION_SOURCE_CONTAINS_ALL',
      'regprocedure','programacion.fn_input_governance_recurate_v2(integer,text,text)',
      'tokens',jsonb_build_array(
        'fn_input_screen_canonical_graph',
        'fn_input_governance_bootstrap_classify_v2_cached_v2'
      )
    ),
    'M4_9_VALIDATOR_FALSE_PASS_GAPS',
    jsonb_build_object(
      'kind','LATEST_SUITE_RUN_PASS',
      'suite_code','INPUT_GOVERNANCE_REGRESSION',
      'checkpoint_code','RUN_CAMPAIGN',
      'expected_tests',10
    )
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M4.9'
  and pu.disposition='ASSIGNED';

-- Register exact repair authority as checkpoint data; the generic RUN_TEST repair loop owns execution.
update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  pu.unit_metadata,
  '{action_specs_v1,RUN_CAMPAIGN}',
  (
    pu.unit_metadata#>'{action_specs_v1,RUN_CAMPAIGN}'
    || jsonb_build_object(
      'target',
      coalesce(pu.unit_metadata#>'{action_specs_v1,RUN_CAMPAIGN,target}','{}'::jsonb)
      || jsonb_build_object(
        'declared_objects',
        (
          select coalesce(jsonb_agg(x.value order by x.value),'[]'::jsonb)
          from (
            select distinct value
            from jsonb_array_elements_text(
              coalesce(pu.unit_metadata#>'{action_specs_v1,RUN_CAMPAIGN,target,declared_objects}','[]'::jsonb)
              || jsonb_build_array('programacion.fn_input_governance_validate_v2')
            )
          ) x
        )
      ),
      'repair_policy',jsonb_build_object(
        'mode','REPAIR_DECLARED_TARGET_THEN_RETEST',
        'max_repairs',1,
        'repair_trigger','FALSE_PASS_OR_CONTRADICTION',
        'retest_scope','FAILED_CASES_THEN_FULL_CANONICAL_CASE_SET',
        'synthetic_pass','FORBIDDEN'
      )
    )
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M4.9'
  and pu.disposition='ASSIGNED';

-- Hook blocker reconciliation into the existing generic bootstrap-repair entrypoint.
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

  if coalesce((blocker_reconcile->>'resolved')::int,0)>0 then
    boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
  end if;

  cp:=nullif(btrim(coalesce(boot#>>'{current_checkpoint,checkpoint_code}','')),'');

  if cp is null then
    return boot
      || jsonb_build_object('blocker_reconcile_auto',blocker_reconcile)
      || jsonb_build_object(
        'contract_repair_auto',
        jsonb_build_object(
          'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V4',
          'status','NOT_APPLICABLE',
          'reason','NO_CURRENT_CHECKPOINT',
          'supported_error_classes',15
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
        'schema_version','ENGINEERING_CONTRACT_REPAIR_AUTO_V4',
        'checkpoint_code',cp,
        'detected_action_spec_status',st,
        'supported_error_classes',15,
        'result',repair,
        'rebootstrap_after_repair',changed
      )
    );
end;
$function$;

-- Reconcile immediately what is already proven live (cache-path blocker).
do $reconcile_cache$
declare
  r jsonb;
begin
  r:=programacion.fn_engineering_blocker_reconcile_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9',true
  );
  if coalesce((r->>'resolved')::int,0)<1 then
    raise exception 'ENGINEERING_M49_CACHE_BLOCKER_NOT_RECONCILED:%',r;
  end if;
end;
$reconcile_cache$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-BLOCKER-RECONCILIATION-001',
  'ENGINEERING_ORCHESTRATION',
  'Resolved root causes must automatically reconcile stale OPEN blockers',
  'A repair could make the checkpoint executable while an earlier OPEN blocker still forced STOP_OPEN_BLOCKER.',
  'Repair execution and blocker lifecycle reconciliation were separate.',
  'ROOT_CAUSE_FIXED_BUT_OPEN_BLOCKER_REMAINS',
  'Register blocker proof rules as unit metadata and run fn_engineering_blocker_reconcile_v1 before every repair-aware bootstrap. Resolve only from current canonical proof; never from narrative or unit-code branches.',
  'PASS when a function-source proof closes the stale recurate cache blocker, a verified 10/10 suite closes the false-pass blocker, and bootstrap immediately reflects the reduced open_blockers count.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_blocker_reconcile_v1',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Generic blocker lifecycle reconciliation',
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
  v_def text;
  v_boot jsonb;
begin
  v_def:=pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure);
  if position('when v_parent is not null' in v_def)=0
     or position('then programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)' in v_def)=0 then
    raise exception 'IG_VALIDATOR_PARENT_ORACLE_SELFTEST_FAILED';
  end if;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9'
  );
  if coalesce(v_boot#>>'{state,open_blockers}','-1')::int<>1 then
    raise exception 'ENGINEERING_M49_EXPECT_ONE_REMAINING_BLOCKER:%',v_boot#>'{state}';
  end if;
end;
$selftest$;
