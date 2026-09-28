-- LF Input Governance contract revision 5.13
-- Purpose:
--   1) give a new revision identity to semantic changes that were materialized after run 191
--      while the contract label remained 5.12;
--   2) allow the existing governed curator/validator runtime to create a successor under 5.13;
--   3) preserve fail-closed behavior, independent validation, and production_authorized=false.
--
-- This does not invent new business semantics. It versions the current live semantic contract
-- and makes the existing governed recuration runtime compatible with that revision.

begin;

do $contract_revision$
declare
  v_before_sha text;
  v_rows integer;
begin
  select programacion.fn_v09_sha256_jsonb(
           jsonb_build_object(
             'id',c.id,
             'version_id',c.version_id,
             'contrato_codigo',c.contrato_codigo,
             'fail_closed',c.fail_closed,
             'estado',c.estado,
             'especificacion',c.especificacion
           )
         )
    into v_before_sha
  from programacion.contratos c
  where c.version_id=19
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined'
    and c.fail_closed;

  if v_before_sha is distinct from '55e67871bd13b203927ed0b5978128d6462807481c1a062e2a6ac1a3092bddca' then
    raise exception 'INPUT_READINESS_513_SOURCE_DRIFT:%',coalesce(v_before_sha,'<NULL>');
  end if;

  update programacion.contratos c
  set especificacion =
      jsonb_set(
        jsonb_set(
          c.especificacion,
          '{contract_revision}',
          '"5.13"'::jsonb,
          true
        ),
        '{revision_lineage}',
        coalesce(c.especificacion->'revision_lineage','{}'::jsonb)
        || jsonb_build_object(
             'previous_revision','5.12',
             'previous_contract_sha256',v_before_sha,
             'revision_reason','POST_5_12_SEMANTIC_CHANGES_REQUIRED_NEW_REVISION_IDENTITY',
             'migration_mode','GOVERNED_CONTRACT_REVISION',
             'production_authorized',false
           ),
        true
      )
  where c.version_id=19
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined'
    and c.fail_closed
    and c.especificacion->>'contract_revision'='5.12';

  get diagnostics v_rows = row_count;
  if v_rows<>1 then
    raise exception 'INPUT_READINESS_513_REVISION_UPDATE_CARDINALITY:%',v_rows;
  end if;
end;
$contract_revision$;

-- Runtime compatibility: the semantic policies implemented for 5.12 remain active in 5.13.
-- We only extend revision guards; no fail-closed check is removed.
do $runtime_revision_guards$
declare
  r record;
  v_def text;
  v_new text;
begin
  for r in
    select *
    from (
      values
        ('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)'),
        ('programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)'),
        ('programacion.fn_input_governance_recurate_v2(integer,text,text)'),
        ('programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)')
    ) as x(sig)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;
    if v_def is null then
      raise exception 'INPUT_READINESS_513_REQUIRED_FUNCTION_MISSING:%',r.sig;
    end if;
    v_new:=replace(
      v_def,
      'v_contract_revision<>''5.12''',
      'v_contract_revision not in (''5.12'',''5.13'')'
    );
    if v_new=v_def and position('5.13' in v_def)=0 then
      raise exception 'INPUT_READINESS_513_GUARD_PATCH_SOURCE_DRIFT:%',r.sig;
    end if;
    if v_new<>v_def then execute v_new; end if;
  end loop;
end;
$runtime_revision_guards$;

do $assessment_revision_guards$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('programacion.fn_guard_input_family_semantic_depth_v510()'::regprocedure)
    into v_def;
  v_new:=replace(
    v_def,
    'v_revision not in (''5.10'',''5.11'',''5.12'')',
    'v_revision not in (''5.10'',''5.11'',''5.12'',''5.13'')'
  );
  if v_new=v_def and position('5.13' in v_def)=0 then
    raise exception 'INPUT_READINESS_513_SEMANTIC_DEPTH_GUARD_SOURCE_DRIFT';
  end if;
  if v_new<>v_def then execute v_new; end if;

  select pg_get_functiondef('programacion.fn_guard_input_stage_earliest_boundary()'::regprocedure)
    into v_def;
  v_new:=replace(
    v_def,
    'v_revision not in (''5.10'',''5.11'',''5.12'')',
    'v_revision not in (''5.10'',''5.11'',''5.12'',''5.13'')'
  );
  if v_new=v_def and position('5.13' in v_def)=0 then
    raise exception 'INPUT_READINESS_513_STAGE_GUARD_SOURCE_DRIFT';
  end if;
  if v_new<>v_def then execute v_new; end if;

  select pg_get_functiondef('programacion.fn_guard_input_na_positive_authority_v512()'::regprocedure)
    into v_def;
  v_new:=replace(
    v_def,
    'v_revision is distinct from ''5.12''',
    '(v_revision is null or v_revision not in (''5.12'',''5.13''))'
  );
  if v_new=v_def and position('5.13' in v_def)=0 then
    raise exception 'INPUT_READINESS_513_NA_AUTHORITY_GUARD_SOURCE_DRIFT';
  end if;
  if v_new<>v_def then execute v_new; end if;

  select pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure)
    into v_def;
  v_new:=replace(
    v_def,
    'v_revision is distinct from ''5.12''',
    '(v_revision is null or v_revision not in (''5.12'',''5.13''))'
  );
  if v_new=v_def and position('5.13' in v_def)=0 then
    raise exception 'INPUT_READINESS_513_VALIDATOR_GUARD_SOURCE_DRIFT';
  end if;
  if v_new<>v_def then execute v_new; end if;
end;
$assessment_revision_guards$;

-- Keep generated probes/rationale aligned with the revision actually consumed by new runs.
do $classifier_revision_labels$
declare
  r record;
  v_def text;
  v_new text;
begin
  for r in
    select *
    from (
      values
        ('programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)'),
        ('programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(integer,text,bigint,jsonb)'),
        ('programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb)'),
        ('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'),
        ('programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(integer,text,bigint,jsonb)'),
        ('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)')
    ) as x(sig)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;
    if v_def is null then
      raise exception 'INPUT_READINESS_513_CLASSIFIER_FUNCTION_MISSING:%',r.sig;
    end if;
    v_new:=replace(v_def,'''revision'',''5.12''','''revision'',''5.13''');
    v_new:=replace(v_new,'INPUT_READINESS_CONTRACT 5.12:','INPUT_READINESS_CONTRACT 5.13:');
    if v_new<>v_def then execute v_new; end if;
  end loop;
end;
$classifier_revision_labels$;

-- A known 5.13 contract hash change is a governed recuration trigger.
-- Unknown future revisions keep the prior fail-closed semantic-review response.
do $curator_contract_migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(
           'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure
         )
    into v_def;

  v_old :=
$old$if v_parent_contract_sha is distinct from v_contract_sha then
    return jsonb_build_object($old$;

  v_new :=
$new$if v_parent_contract_sha is distinct from v_contract_sha then
    if v_contract_revision='5.13' then
      return programacion.fn_input_governance_recurate_v2(
        p_pantalla_id,p_consumer,p_curator_identity
      );
    end if;
    return jsonb_build_object($new$;

  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'INPUT_READINESS_513_CURATOR_MIGRATION_SOURCE_DRIFT';
    end if;
    v_def:=replace(v_def,v_old,v_new);
    execute v_def;
  end if;
end;
$curator_contract_migration$;

do $postconditions$
declare
  v_revision text;
  v_sha text;
  v_worker jsonb;
  v_def text;
begin
  select c.especificacion->>'contract_revision',
         programacion.fn_v09_sha256_jsonb(
           jsonb_build_object(
             'id',c.id,
             'version_id',c.version_id,
             'contrato_codigo',c.contrato_codigo,
             'fail_closed',c.fail_closed,
             'estado',c.estado,
             'especificacion',c.especificacion
           )
         )
    into v_revision,v_sha
  from programacion.contratos c
  where c.version_id=19
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined'
    and c.fail_closed;

  if v_revision<>'5.13' or v_sha='55e67871bd13b203927ed0b5978128d6462807481c1a062e2a6ac1a3092bddca' then
    raise exception 'INPUT_READINESS_513_CONTRACT_POSTCONDITION_FAILED:%:%',v_revision,v_sha;
  end if;

  select pg_get_functiondef('programacion.fn_input_governance_recurate_v2(integer,text,text)'::regprocedure)
    into v_def;
  if position('5.13' in v_def)=0 then
    raise exception 'INPUT_READINESS_513_RECURATION_NOT_ENABLED';
  end if;

  select pg_get_functiondef(
           'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure
         )
    into v_def;
  if position('v_contract_revision=''5.13''' in v_def)=0
     or position('fn_input_governance_recurate_v2' in v_def)=0 then
    raise exception 'INPUT_READINESS_513_CURATOR_ROUTE_NOT_ENABLED';
  end if;

  v_worker:=programacion.fn_input_governance_worker_spec(51,'MANUAL');
  if v_worker->>'screen_code'<>'B2B-AUTH-001'
     or v_worker->>'readiness_contract_revision'<>'5.13'
     or v_worker->>'required_role'<>'INPUT_CURATOR' then
    raise exception 'INPUT_READINESS_513_WORKER_POSTCONDITION_FAILED:%',v_worker;
  end if;
end;
$postconditions$;

commit;
