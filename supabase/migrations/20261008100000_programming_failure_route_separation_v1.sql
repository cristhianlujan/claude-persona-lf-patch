-- PROGRAMMING FAILURE ROUTE SEPARATION V1
-- Separates deterministic validation nature from what happens after FAIL.
-- A deterministic validator PASS closes normally; FAIL may BLOCK, AUTO_RESOLVE,
-- HUMAN_DECISION or CHECK_ONLY according to an explicit failure_route.

alter table programacion.programming_validation_registry
  add column if not exists failure_route text;

update programacion.programming_validation_registry
set failure_route=case rule_mode
  when 'BLOCKING_AUTOMATIC' then 'AUTO_RESOLVE'
  when 'HUMAN_DECISION' then 'HUMAN_DECISION'
  when 'CHECK_ONLY' then 'CHECK_ONLY'
  else 'BLOCK'
end
where failure_route is null;

alter table programacion.programming_validation_registry
  alter column failure_route set default 'BLOCK',
  alter column failure_route set not null;

alter table programacion.programming_validation_registry
  drop constraint if exists programming_validation_registry_rule_mode_check;

alter table programacion.programming_validation_registry
  add constraint programming_validation_registry_rule_mode_check
  check (rule_mode in (
    'DETERMINISTIC',
    'BLOCKING_AUTOMATIC',
    'HUMAN_DECISION',
    'CHECK_ONLY'
  ));

do $constraint$
begin
  if exists(
    select 1
    from pg_constraint
    where conrelid='programacion.programming_validation_registry'::regclass
      and conname='programming_validation_registry_failure_route_check'
  ) then
    alter table programacion.programming_validation_registry
      drop constraint programming_validation_registry_failure_route_check;
  end if;

  alter table programacion.programming_validation_registry
    add constraint programming_validation_registry_failure_route_check
    check (failure_route in (
      'BLOCK',
      'AUTO_RESOLVE',
      'HUMAN_DECISION',
      'CHECK_ONLY'
    ));

  if exists(
    select 1
    from pg_constraint
    where conrelid='programacion.programming_validation_registry'::regclass
      and conname='programming_validation_registry_mode_route_coherence_check'
  ) then
    alter table programacion.programming_validation_registry
      drop constraint programming_validation_registry_mode_route_coherence_check;
  end if;

  alter table programacion.programming_validation_registry
    add constraint programming_validation_registry_mode_route_coherence_check
    check (
      (rule_mode='BLOCKING_AUTOMATIC' and failure_route='AUTO_RESOLVE')
      or (rule_mode='HUMAN_DECISION' and failure_route='HUMAN_DECISION')
      or (rule_mode='CHECK_ONLY' and failure_route='CHECK_ONLY')
      or (
        rule_mode='DETERMINISTIC'
        and failure_route in ('BLOCK','AUTO_RESOLVE','HUMAN_DECISION')
      )
    );
end
$constraint$;

update programacion.programming_validation_registry
set rule_mode='DETERMINISTIC',
    failure_route='BLOCK',
    updated_at=now()
where validation_code in (
  'PROGRAMMING_GITHUB_FILE_SHA256_ASSERT_V1',
  'PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1',
  'PROGRAMMING_SUPABASE_CATALOG_ASSERT_V1'
)
  and status='ACTIVE'
  and deterministic;

do $patch_rule_admission$
declare
  v_def text;
  v_sha text;
begin
  select pg_get_functiondef(
           'programacion.fn_programming_rule_admission_v1(text,text)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'programacion.fn_programming_rule_admission_v1(text,text)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'f70d35cbfb9826acee2b78b857ea98937cd7035fc807ff55377f833eb3675c13' then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_RULE_ADMISSION_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  if position('if v.rule_mode=''BLOCKING_AUTOMATIC'' then' in v_def)=0 then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_RULE_ADMISSION_AUTO_ANCHOR_DRIFT';
  end if;

  v_def:=replace(
    v_def,
    'if v.rule_mode=''BLOCKING_AUTOMATIC'' then',
    'if v.failure_route=''AUTO_RESOLVE'' then'
  );

  v_def:=replace(
    v_def,
    E'''rule_mode'',v.rule_mode,\n      ''validator_handler''',
    E'''rule_mode'',v.rule_mode,\n      ''failure_route'',v.failure_route,\n      ''validator_handler'''
  );

  v_def:=replace(
    v_def,
    E'''rule_mode'',v.rule_mode,\n    ''validator_handler''',
    E'''rule_mode'',v.rule_mode,\n    ''failure_route'',v.failure_route,\n    ''validator_handler'''
  );

  execute v_def;
end
$patch_rule_admission$;

do $patch_plan_admission$
declare
  v_def text;
  v_sha text;
begin
  select pg_get_functiondef(
           'programacion.fn_programming_simple_plan_admission_v1(text)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'programacion.fn_programming_simple_plan_admission_v1(text)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'008171bb4a0c794a5b82a46274286acf0f2336a57cec4c2d5b8f6107eaed2d4f' then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_PLAN_ADMISSION_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  if position('v.rule_mode=''CHECK_ONLY''' in v_def)=0 then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_PLAN_CHECK_ONLY_ANCHOR_DRIFT';
  end if;

  execute replace(
    v_def,
    'v.rule_mode=''CHECK_ONLY''',
    'v.failure_route=''CHECK_ONLY'''
  );
end
$patch_plan_admission$;

do $patch_unit_bootstrap$
declare
  v_def text;
  v_sha text;
  v_human_anchor text:=E'    if r->>''result''=''FAIL''\n       and a->>''rule_mode''=''HUMAN_DECISION'' then';
  v_human_replacement text:=E'    if r->>''result''=''FAIL''\n       and a->>''failure_route''=''BLOCK'' then\n      return jsonb_build_object(\n        ''schema_version'',''PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1'',\n        ''plan_code'',p_plan_code,\n        ''unit_code'',p_unit_code,\n        ''checkpoint_code'',c.checkpoint_code,\n        ''terminal_action'',''VALIDATION_FAILED_BLOCKED'',\n        ''validation_code'',b.validation_code,\n        ''validation_input'',b.validation_input,\n        ''validation_receipt'',r,\n        ''failure_route'',''BLOCK'',\n        ''human_decision_required'',false,\n        ''next_action'',''REPAIR_OR_UPDATE_CURRENT_SOURCE_THEN_REVALIDATE''\n      );\n    end if;\n\n    if r->>''result''=''FAIL''\n       and a->>''failure_route''=''HUMAN_DECISION'' then';
begin
  select pg_get_functiondef(
           'programacion.fn_programming_simple_unit_bootstrap_v1(bigint,text,text)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'programacion.fn_programming_simple_unit_bootstrap_v1(bigint,text,text)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'527b3d0ea31b9735d413b157a5581197ec630ba28f7eb1f61921b04689c4a72a' then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_BOOTSTRAP_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  v_def:=replace(
    v_def,
    'a->>''rule_mode''=''BLOCKING_AUTOMATIC''',
    'a->>''failure_route''=''AUTO_RESOLVE'''
  );

  if position(v_human_anchor in v_def)=0 then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_BOOTSTRAP_HUMAN_ANCHOR_DRIFT';
  end if;

  v_def:=replace(v_def,v_human_anchor,v_human_replacement);

  v_def:=replace(
    v_def,
    E'''rule_mode'',a->>''rule_mode'',\n    ''reuse_policy''',
    E'''rule_mode'',a->>''rule_mode'',\n    ''failure_route'',a->>''failure_route'',\n    ''reuse_policy'''
  );

  execute v_def;
end
$patch_unit_bootstrap$;

do $patch_validation_record$
declare
  v_def text;
  v_sha text;
begin
  select pg_get_functiondef(
           'programacion.fn_programming_validation_record_v1(bigint,text,text,text,text,text,text,text,jsonb)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'programacion.fn_programming_validation_record_v1(bigint,text,text,text,text,text,text,text,jsonb)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'35d3f01f1b3b5e983d615e428c5850f0583eeb8a0c5be8f15012f2c3b8e010f5' then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_VALIDATION_RECORD_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  if position('a->>''rule_mode''=''BLOCKING_AUTOMATIC''' in v_def)=0 then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_VALIDATION_RECORD_ANCHOR_DRIFT';
  end if;

  execute replace(
    v_def,
    'a->>''rule_mode''=''BLOCKING_AUTOMATIC''',
    'a->>''failure_route''=''AUTO_RESOLVE'''
  );
end
$patch_validation_record$;

do $patch_resolution_record$
declare
  v_def text;
  v_sha text;
begin
  select pg_get_functiondef(
           'programacion.fn_programming_resolution_record_v1(bigint,text,text,text,text,text,text,jsonb)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'programacion.fn_programming_resolution_record_v1(bigint,text,text,text,text,text,text,jsonb)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'785387d83c552e7e76fc6cacd519794535ae940337db2c74bc2bbb70dd10f349' then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_RESOLUTION_RECORD_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  if position('a->>''rule_mode''<>''BLOCKING_AUTOMATIC''' in v_def)=0 then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_RESOLUTION_RECORD_ANCHOR_DRIFT';
  end if;

  execute replace(
    v_def,
    'a->>''rule_mode''<>''BLOCKING_AUTOMATIC''',
    'a->>''failure_route''<>''AUTO_RESOLVE'''
  );
end
$patch_resolution_record$;

do $patch_human_adapter$
declare
  v_def text;
  v_sha text;
begin
  select pg_get_functiondef(
           'private.fn_lf_human_decision_open_programming_v1(bigint,text,text,text,text,text,jsonb,text)'::regprocedure
         ),
         encode(
           extensions.digest(
             convert_to(
               pg_get_functiondef(
                 'private.fn_lf_human_decision_open_programming_v1(bigint,text,text,text,text,text,jsonb,text)'::regprocedure
               ),
               'UTF8'
             ),
             'sha256'
           ),
           'hex'
         )
    into v_def,v_sha;

  if v_sha<>'45124da71a5a130d81d3dfa0b3ad68a3281efbc00394078f247929b3cdb9695c' then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_HUMAN_ADAPTER_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  v_def:=replace(
    v_def,
    E'  v_rule_mode text;\n  v_subject_key text;',
    E'  v_rule_mode text;\n  v_failure_route text;\n  v_subject_key text;'
  );

  v_def:=replace(
    v_def,
    E'  select rule_mode\n    into v_rule_mode\n  from programacion.programming_validation_registry',
    E'  select rule_mode,failure_route\n    into v_rule_mode,v_failure_route\n  from programacion.programming_validation_registry'
  );

  v_def:=replace(
    v_def,
    E'  if v_rule_mode is distinct from ''HUMAN_DECISION'' then\n    raise exception ''PROGRAMMING_HUMAN_DECISION_RULE_MODE_REQUIRED:%'',coalesce(v_rule_mode,''(none)'');\n  end if;',
    E'  if v_failure_route is distinct from ''HUMAN_DECISION'' then\n    raise exception ''PROGRAMMING_HUMAN_DECISION_FAILURE_ROUTE_REQUIRED:%'',coalesce(v_failure_route,''(none)'');\n  end if;'
  );

  v_def:=replace(
    v_def,
    E'''rule_mode'',v_rule_mode,\n      ''validation_code''',
    E'''rule_mode'',v_rule_mode,\n      ''failure_route'',v_failure_route,\n      ''validation_code'''
  );

  if position('v_failure_route' in v_def)=0 then
    raise exception 'PROGRAMMING_FAILURE_ROUTE_HUMAN_ADAPTER_PATCH_FAILED';
  end if;

  execute v_def;
end
$patch_human_adapter$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values(
  'PROGRAMMING-VALIDATION-FAILURE-ROUTE-SEPARATION-001',
  'PROGRAMMING_GOVERNANCE',
  'Deterministic validation nature must be separate from the route taken after FAIL',
  'Programming validators were deterministic and fully proven, but three active validators were registered as HUMAN_DECISION only because no automatic resolver existed. That conflated validation with failure handling and could route ordinary deterministic mismatches to a human.',
  'The original registry encoded validator nature and failure action in one rule_mode enum.',
  'VALIDATOR NATURE = DETERMINISTIC. FAILURE ROUTE = BLOCK | AUTO_RESOLVE | HUMAN_DECISION | CHECK_ONLY. PASS is always current deterministic evidence and continues automatically. BLOCK never enters human routing. AUTO_RESOLVE requires a proven resolver and current failure-bound receipt. HUMAN_DECISION is explicit and separately admitted.',
  'Register deterministic validators as rule_mode=DETERMINISTIC and select failure_route independently. A required checkpoint may not use CHECK_ONLY. Human adapters must require failure_route=HUMAN_DECISION, not merely a deterministic FAIL. Do not turn absence of a resolver into a human decision.',
  'Migration adds failure_route, updates rule admission/bootstrap/validation/resolution/human adapter behavior, and reclassifies the three current deterministic validators to DETERMINISTIC + BLOCK.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261008100000_programming_failure_route_separation_v1.sql',
  now()
)
on conflict(codigo) do update
set descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
