-- M4.8 REMOVE_LITERALS
-- Replace numeric screen identity in the active validator template/rebind path
-- with canonical screen codes derived from the supplied pantalla_id/run.
-- No new resolver is introduced; lf_ops.pantallas remains canonical authority.

do $m48$
declare
  v_def text;
  v_new text;
  v_actual text;
begin
  -- v5.8 template
  v_actual:=md5(pg_get_functiondef(
    'programacion.fn_input_v58_assertion_template(integer,text,jsonb)'::regprocedure
  ));
  if v_actual is distinct from 'fe756e847398595c0c94eede625b2ec4' then
    raise exception 'M48_BASE_DRIFT:v58_template:%',v_actual;
  end if;

  v_def:=pg_get_functiondef(
    'programacion.fn_input_v58_assertion_template(integer,text,jsonb)'::regprocedure
  );
  v_new:=v_def;

  v_new:=replace(
    v_new,
    'v_kind text := coalesce(p_assertion->''source_ref''->>''kind'','''');'||chr(10)||'begin',
    'v_kind text := coalesce(p_assertion->''source_ref''->>''kind'','''');'||chr(10)||
    '  v_screen_code text;'||chr(10)||
    'begin'||chr(10)||
    '  select p.codigo into v_screen_code from lf_ops.pantallas p where p.id=p_pantalla_id;'||chr(10)||
    '  if v_screen_code is null then raise exception ''V58_TEMPLATE_SCREEN_NOT_FOUND:%'',p_pantalla_id; end if;'
  );

  v_new:=replace(v_new,'p_pantalla_id in (51,52,53,54,56)',
    'v_screen_code in (''B2B-AUTH-001'',''B2B-AUTH-002'',''B2B-AUTH-003'',''B2B-AUTH-004'',''B2B-AUTH-006'')');
  v_new:=replace(v_new,'p_pantalla_id in (52,53,56)',
    'v_screen_code in (''B2B-AUTH-002'',''B2B-AUTH-003'',''B2B-AUTH-006'')');
  v_new:=replace(v_new,'p_pantalla_id in (52,56)',
    'v_screen_code in (''B2B-AUTH-002'',''B2B-AUTH-006'')');
  v_new:=replace(v_new,'p_pantalla_id=51','v_screen_code=''B2B-AUTH-001''');
  v_new:=replace(v_new,'p_pantalla_id=52','v_screen_code=''B2B-AUTH-002''');
  v_new:=replace(v_new,'p_pantalla_id=53','v_screen_code=''B2B-AUTH-003''');
  v_new:=replace(v_new,'p_pantalla_id=54','v_screen_code=''B2B-AUTH-004''');
  v_new:=replace(v_new,'p_pantalla_id=56','v_screen_code=''B2B-AUTH-006''');

  v_new:=replace(v_new,'''pantalla_id'',54','''pantalla_id'',p_pantalla_id');
  v_new:=replace(v_new,'''pantalla_id'',56','''pantalla_id'',p_pantalla_id');
  v_new:=replace(v_new,'fn_input_screen_canonical_graph(56,19)','fn_input_screen_canonical_graph(p_pantalla_id,19)');

  if v_new=v_def then
    raise exception 'M48_PATCH_NOT_APPLIED:v58_template';
  end if;
  execute v_new;

  -- v5.12 template
  v_actual:=md5(pg_get_functiondef(
    'programacion.fn_input_v512_assertion_template(integer,text,jsonb)'::regprocedure
  ));
  if v_actual is distinct from '495ce1f56c22c8f10a19ff3ff565bdfa' then
    raise exception 'M48_BASE_DRIFT:v512_template:%',v_actual;
  end if;

  v_def:=pg_get_functiondef(
    'programacion.fn_input_v512_assertion_template(integer,text,jsonb)'::regprocedure
  );
  v_new:=v_def;

  v_new:=replace(
    v_new,
    'declare v jsonb;'||chr(10)||'begin',
    'declare v jsonb; v_screen_code text;'||chr(10)||
    'begin'||chr(10)||
    '  select p.codigo into v_screen_code from lf_ops.pantallas p where p.id=p_pantalla_id;'||chr(10)||
    '  if v_screen_code is null then raise exception ''V512_TEMPLATE_SCREEN_NOT_FOUND:%'',p_pantalla_id; end if;'
  );

  v_new:=replace(v_new,'p_pantalla_id in (53,56)',
    'v_screen_code in (''B2B-AUTH-003'',''B2B-AUTH-006'')');
  v_new:=replace(v_new,'p_pantalla_id=52','v_screen_code=''B2B-AUTH-002''');
  v_new:=replace(v_new,'p_pantalla_id=54','v_screen_code=''B2B-AUTH-004''');
  v_new:=replace(v_new,'''pantalla_id'',52','''pantalla_id'',p_pantalla_id');

  if v_new=v_def then
    raise exception 'M48_PATCH_NOT_APPLIED:v512_template';
  end if;
  execute v_new;

  -- v5.8 builder
  v_actual:=md5(pg_get_functiondef(
    'programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure
  ));
  if v_actual is distinct from 'af95bfa42f649250c3585db9a6cb35fb' then
    raise exception 'M48_BASE_DRIFT:v58_builder:%',v_actual;
  end if;

  v_def:=pg_get_functiondef(
    'programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure
  );
  v_new:=v_def;

  v_new:=replace(
    v_new,
    'v_pantalla_id integer;'||chr(10),
    'v_pantalla_id integer;'||chr(10)||'  v_screen_code text;'||chr(10)
  );
  v_new:=replace(
    v_new,
    'if v_pantalla_id is null then raise exception ''V58_ASSERTION_NEW_RUN_NOT_FOUND:%'',p_new_run_id; end if;',
    'if v_pantalla_id is null then raise exception ''V58_ASSERTION_NEW_RUN_NOT_FOUND:%'',p_new_run_id; end if;'||chr(10)||
    '  select p.codigo into v_screen_code from lf_ops.pantallas p where p.id=v_pantalla_id;'||chr(10)||
    '  if v_screen_code is null then raise exception ''V58_ASSERTION_SCREEN_NOT_FOUND:%'',v_pantalla_id; end if;'
  );

  v_new:=replace(v_new,'v_pantalla_id=51','v_screen_code=''B2B-AUTH-001''');
  v_new:=replace(v_new,'''pantalla_id'',51','''pantalla_id'',v_pantalla_id');

  if v_new=v_def then
    raise exception 'M48_PATCH_NOT_APPLIED:v58_builder';
  end if;
  execute v_new;

  -- owner-decision assertion builder
  v_actual:=md5(pg_get_functiondef(
    'programacion.fn_input_owner_decision_assertions(bigint,bigint,text)'::regprocedure
  ));
  if v_actual is distinct from 'faaf7a7e0b6da0ac40eb740ecfda064a' then
    raise exception 'M48_BASE_DRIFT:owner_decision:%',v_actual;
  end if;

  v_def:=pg_get_functiondef(
    'programacion.fn_input_owner_decision_assertions(bigint,bigint,text)'::regprocedure
  );
  v_new:=v_def;

  v_new:=replace(
    v_new,
    'v_screen integer;'||chr(10),
    'v_screen integer;'||chr(10)||'  v_screen_code text;'||chr(10)
  );
  v_new:=replace(
    v_new,
    'select pantalla_id into v_screen from programacion.input_readiness_runs where id=p_new_run_id;',
    'select pantalla_id into v_screen from programacion.input_readiness_runs where id=p_new_run_id;'||chr(10)||
    '  select p.codigo into v_screen_code from lf_ops.pantallas p where p.id=v_screen;'||chr(10)||
    '  if v_screen_code is null then raise exception ''OWNER_DECISION_SCREEN_NOT_FOUND:%'',v_screen; end if;'
  );

  v_new:=replace(v_new,'v_screen=51','v_screen_code=''B2B-AUTH-001''');
  v_new:=replace(v_new,'v_screen=52','v_screen_code=''B2B-AUTH-002''');
  v_new:=replace(v_new,'v_screen=54','v_screen_code=''B2B-AUTH-004''');
  v_new:=replace(v_new,'v_screen=56','v_screen_code=''B2B-AUTH-006''');
  v_new:=replace(v_new,'''pantalla_id'',51','''pantalla_id'',v_screen');
  v_new:=replace(v_new,'''pantalla_id'',52','''pantalla_id'',v_screen');
  v_new:=replace(v_new,'''pantalla_id'',56','''pantalla_id'',v_screen');

  if v_new=v_def then
    raise exception 'M48_PATCH_NOT_APPLIED:owner_decision';
  end if;
  execute v_new;

end;
$m48$;

comment on function programacion.fn_input_v58_assertion_template(integer,text,jsonb)
is 'M4.8: screen-specific template branches use canonical screen_code resolved from the supplied pantalla_id; no numeric screen control-flow identity.';

comment on function programacion.fn_input_v512_assertion_template(integer,text,jsonb)
is 'M4.8: screen-specific v5.12 branches use canonical screen_code resolved from the supplied pantalla_id.';

comment on function programacion.fn_input_v58_build_assertions(bigint,bigint,text)
is 'M4.8: successor screen identity is derived from run pantalla_id and canonical screen code; B2B-AUTH-001 visual rebinding no longer hardcodes numeric screen identity.';

comment on function programacion.fn_input_owner_decision_assertions(bigint,bigint,text)
is 'M4.8: owner-decision assertion branching uses canonical screen_code resolved from the run instead of numeric screen identity.';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'REMOVE_LITERALS',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','REMOVE_LITERALS',
      'checkpoint_title','Sustituir literales por resolución desde registry/run (component_id y pantalla por parámetro)',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','VERIFY_EXACT',
      'precision','EXPLICIT_POST_MATERIALIZATION_LITERAL_READBACK',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Active Validator paths have no numeric component_id assignment and active v58/v512 template-builder control flow has no numeric pantalla_id equality/IN identity; screen identity comes from run/parameter plus lf_ops.pantallas.codigo.',
      'verification_queries',jsonb_build_array(
        $q$
with f as (
  select p.proname,p.prosrc
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_governance_validator_rebind_v1',
      'fn_input_governance_validate_v2',
      'fn_input_governance_bootstrap_validate_v1',
      'fn_input_v58_assertion_template',
      'fn_input_v512_assertion_template',
      'fn_input_v58_build_assertions',
      'fn_input_owner_decision_assertions'
    )
)
select
  count(*) filter(where prosrc ~* 'component_id\s*=\s*[0-9]+')=0 as zero_component_assignment_literals,
  count(*) filter(where prosrc ~* '(p_|v_)?pantalla_id\s*=\s*[0-9]+')=0 as zero_screen_equality_literals,
  count(*) filter(where prosrc ~* '(p_|v_)?pantalla_id\s+in\s*\([^)]*[0-9]')=0 as zero_screen_in_literals,
  count(*) filter(where proname in ('fn_input_v58_assertion_template','fn_input_v512_assertion_template','fn_input_v58_build_assertions','fn_input_owner_decision_assertions')
                   and prosrc ilike '%lf_ops.pantallas%')=4 as canonical_screen_registry_bound,
  count(*) filter(where proname='fn_input_owner_decision_assertions' and prosrc ~* 'v_screen\\s*=\\s*[0-9]+')=0 as zero_owner_screen_equality_literals
from f
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'CREATE_PARALLEL_SCREEN_REGISTRY',
        'REWRITE_NON_SCREEN_NUMERIC_IDS',
        'INFER_SCREEN_FROM_HISTORICAL_NUMERIC_ID'
      ),
      'contract_correction','SCREEN_IDENTITY_FROM_RUN_PARAMETER_PLUS_CANONICAL_SCREEN_CODE'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.8';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'INPUT-GOV-VALIDATOR-NUMERIC-SCREEN-IDENTITY-001',
  'INPUT_GOVERNANCE',
  'Validator template control flow must not depend on numeric screen IDs',
  'Active v58/v512 template and successor-builder branches used numeric pantalla IDs to select screen-specific semantics, coupling Validator behavior to historical row IDs.',
  'Screen identity was encoded as numeric control-flow literals instead of resolving the supplied pantalla_id to the canonical screen code.',
  'NUMERIC_SCREEN_ID_DRIVES_VALIDATOR_TEMPLATE_CONTROL_FLOW',
  'Use the pantalla_id supplied by the run/parameter for reads and evidence, resolve lf_ops.pantallas.codigo for semantic branching, and keep unrelated route/error/policy/field IDs untouched.',
  'M4.8 readback requires zero numeric component assignments, zero numeric pantalla_id equality/IN control-flow literals, and registry binding in v58/v512 templates/builders.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_input_v58_assertion_template; supabase://programacion.fn_input_v512_assertion_template; supabase://programacion.fn_input_v58_build_assertions',
  'EXECUTION',
  array['INPUT_VALIDATOR','ENGINEERING_SCHEDULER']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.8 REMOVE_LITERALS',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M4.8'
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
