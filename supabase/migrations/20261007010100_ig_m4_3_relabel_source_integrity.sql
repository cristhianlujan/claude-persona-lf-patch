-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M4.3 / PAULO-057
-- Checkpoint: RELABEL_SOURCE_INTEGRITY
-- Classify every current Validator assertion explicitly; no unclassified assertion remains.

create or replace function programacion.fn_input_evaluate_assertion(
  p_run_id bigint,
  p_family_code text,
  p_assertion jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $function$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_source_ref jsonb;
  v_receipt jsonb;
  v_graph jsonb;
  v_path text[];
  v_actual_db jsonb;
  v_actual_claim jsonb;
  v_expected jsonb;
  v_operator text;
  v_assertion_class text;
  v_pass boolean:=false;
  v_allowed boolean:=false;
  v_governance_family boolean:=false;
begin
  if jsonb_typeof(p_assertion)<>'object' then
    raise exception 'ASSERTION_NOT_OBJECT:%',p_family_code;
  end if;

  if not (p_assertion ? 'source_ref')
     or not (p_assertion ? 'path')
     or not (p_assertion ? 'actual')
     or not (p_assertion ? 'expected')
     or not (p_assertion ? 'operator')
     or not (p_assertion ? 'assertion_class') then
    raise exception 'ASSERTION_REQUIRED_FIELDS_MISSING:%',p_family_code;
  end if;

  v_assertion_class:=nullif(btrim(coalesce(p_assertion->>'assertion_class','')),'');
  if v_assertion_class is null then
    raise exception 'ASSERTION_CLASS_REQUIRED:%',p_family_code;
  end if;

  v_source_ref:=p_assertion->'source_ref';
  if jsonb_typeof(v_source_ref)<>'object' then
    raise exception 'ASSERTION_SOURCE_REF_INVALID:%',p_family_code;
  end if;

  if jsonb_typeof(p_assertion->'path')<>'array'
     or jsonb_array_length(p_assertion->'path')=0 then
    raise exception 'ASSERTION_PATH_INVALID:%',p_family_code;
  end if;

  select r.pantalla_id,r.version_id
    into v_pantalla_id,v_version_id
  from programacion.input_readiness_runs r
  where r.id=p_run_id;

  if v_pantalla_id is null then
    raise exception 'ASSERTION_RUN_NOT_FOUND:%',p_run_id;
  end if;

  v_governance_family:=p_family_code in (
    'SOURCE_AUTHORITY_PROVENANCE',
    'FRESHNESS_INVALIDATION',
    'NEGATIVE_REQUIREMENTS',
    'CONFLICT_PRECEDENCE',
    'APPLICABILITY_READINESS'
  );

  if v_governance_family then
    v_allowed:=programacion.fn_input_governance_assertion_relevant(
      p_family_code,v_source_ref,p_assertion->'path'
    );
  else
    v_allowed:=programacion.fn_input_assertion_is_relevant(
      p_family_code,v_source_ref,p_assertion->'path'
    );
  end if;

  if not coalesce(v_allowed,false) then
    raise exception 'ASSERTION_SOURCE_NOT_RELEVANT:%:%',p_family_code,v_source_ref;
  end if;

  if v_source_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
    v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
    v_receipt:=jsonb_build_object(
      'ref',v_source_ref,
      'observed',v_graph,
      'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph)
    );
  else
    v_receipt:=programacion.fn_input_resolve_source_ref(
      v_source_ref,v_pantalla_id,v_version_id
    );
  end if;

  select array_agg(x.value order by x.ord)
    into v_path
  from jsonb_array_elements_text(p_assertion->'path')
       with ordinality x(value,ord);

  v_actual_db:=v_receipt #> v_path;
  v_actual_claim:=p_assertion->'actual';
  v_expected:=p_assertion->'expected';
  v_operator:=upper(p_assertion->>'operator');

  if v_actual_claim is distinct from v_actual_db then
    raise exception 'ASSERTION_ACTUAL_NOT_SOURCE_DERIVED:%',p_family_code;
  end if;

  case v_operator
    when 'EQ' then
      v_pass:=v_actual_db=v_expected;
    when 'NE' then
      v_pass:=v_actual_db is distinct from v_expected;
    when 'CONTAINS' then
      v_pass:=coalesce(v_actual_db @> v_expected,false);
    when 'NOT_CONTAINS' then
      v_pass:=not coalesce(v_actual_db @> v_expected,false);
    when 'ARRAY_LENGTH_EQ' then
      if jsonb_typeof(v_actual_db)<>'array'
         or jsonb_typeof(v_expected)<>'number' then
        raise exception 'ASSERTION_ARRAY_LENGTH_TYPES_INVALID:%',p_family_code;
      end if;
      v_pass:=jsonb_array_length(v_actual_db)=(v_expected #>> '{}')::integer;
    else
      raise exception 'ASSERTION_OPERATOR_UNSUPPORTED:%:%',p_family_code,v_operator;
  end case;

  return jsonb_build_object(
    'passed',v_pass,
    'assertion_class',v_assertion_class,
    'actual',v_actual_db,
    'expected',v_expected,
    'operator',v_operator,
    'source_ref',v_source_ref,
    'path',p_assertion->'path',
    'source_observed_sha256',v_receipt->>'observed_sha256'
  );
end;
$function$;

create or replace function programacion.fn_input_governance_bootstrap_assertions_v1(
  p_run_id bigint,
  p_family_code text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $function$
declare
  v_pantalla_id integer; v_version_id bigint; v_source_ref jsonb; v_receipt jsonb;
  v_path text[]; v_actual jsonb; v_expected jsonb; v_operator text:='EQ';
  v_assertion jsonb; v_eval jsonb;
begin
  select pantalla_id,version_id into v_pantalla_id,v_version_id
  from programacion.input_readiness_runs where id=p_run_id;
  if v_pantalla_id is null then raise exception 'BOOTSTRAP_ASSERTION_RUN_NOT_FOUND:%',p_run_id; end if;

  if p_family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS') then
    v_source_ref:=jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033'));
    v_path:=array['observed']; v_operator:='CONTAINS';
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    v_actual:=v_receipt #> v_path;
    v_expected:=jsonb_build_array(jsonb_build_object('adr','ADR-EKB-033','estado','vigente'));
  elsif p_family_code='EKB' then
    v_source_ref:=jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-GOV-010'));
    v_path:=array['observed']; v_operator:='CONTAINS';
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    v_actual:=v_receipt #> v_path;
    v_expected:=jsonb_build_array(jsonb_build_object('regla_codigo','PRV-GOV-010','activa',true));
  elsif p_family_code='CONTEXT_BUDGET_RETRIEVAL_POLICY' then
    v_source_ref:=jsonb_build_object('kind','CONTRACT','codigo','INPUT_READINESS_CONTRACT');
    v_path:=array['observed','especificacion','contract_revision'];
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    v_actual:=v_receipt #> v_path; v_expected:=v_actual;
  elsif p_family_code in ('STATES','TRANSITIONS') then
    v_source_ref:=jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',v_pantalla_id);
    v_path:=array['observed']; v_operator:='ARRAY_LENGTH_EQ';
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    v_actual:=v_receipt #> v_path;
    v_expected:=to_jsonb(jsonb_array_length(coalesce(v_actual,'[]'::jsonb)));
  else
    v_source_ref:=jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_pantalla_id);
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    case p_family_code
      when 'SCREEN_IDENTITY' then v_path:=array['observed','screen_code'];
      when 'OBJECTIVE_OUTCOMES' then v_path:=array['observed','canonical_contract','context','screen','objective'];
      when 'FIELDS','VALIDATIONS' then v_path:=array['observed','canonical_contract','fields']; v_operator:='ARRAY_LENGTH_EQ';
      when 'PROFILES' then v_path:=array['observed','canonical_contract','profiles']; v_operator:='ARRAY_LENGTH_EQ';
      when 'PERMISSIONS' then v_path:=array['observed','screen_permissions']; v_operator:='ARRAY_LENGTH_EQ';
      when 'ERRORS' then v_path:=array['observed','canonical_contract','errors']; v_operator:='ARRAY_LENGTH_EQ';
      when 'UI_MESSAGES' then v_path:=array['observed','messages']; v_operator:='ARRAY_LENGTH_EQ';
      when 'ANALYTICS' then v_path:=array['observed','canonical_contract','analytics']; v_operator:='ARRAY_LENGTH_EQ';
      when 'RESPONSIVE' then v_path:=array['observed','canonical_contract','visual','variants']; v_operator:='ARRAY_LENGTH_EQ';
      when 'DESIGN_SYSTEM' then v_path:=array['observed','canonical_contract','visual','design_bindings','summary'];
      when 'ASSETS_ICONS' then v_path:=array['observed','canonical_contract','visual','components']; v_operator:='ARRAY_LENGTH_EQ';
      when 'API_DATA_CONTRACT' then v_path:=array['observed','canonical_contract','api_contract_resolution','implementation_gate'];
      when 'DEPENDENCIES' then v_path:=array['observed','canonical_contract','context','screen','dependencies']; v_operator:='ARRAY_LENGTH_EQ';
      when 'VISUAL_EVIDENCE' then v_path:=array['observed','canonical_contract','evidence']; v_operator:='ARRAY_LENGTH_EQ';
      else v_path:=array['observed','canonical_contract','rules']; v_operator:='ARRAY_LENGTH_EQ';
    end case;
    v_actual:=v_receipt #> v_path;
    if v_operator='ARRAY_LENGTH_EQ' then
      v_expected:=to_jsonb(jsonb_array_length(coalesce(v_actual,'[]'::jsonb)));
    else
      v_expected:=v_actual;
    end if;
  end if;

  v_assertion:=jsonb_build_object(
    'assertion_class','SOURCE_INTEGRITY',
    'source_ref',v_source_ref,
    'path',to_jsonb(v_path),
    'actual',v_actual,
    'expected',v_expected,
    'operator',v_operator
  );
  v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_assertion);
  return jsonb_build_array(v_assertion||jsonb_build_object(
    'result',case when coalesce((v_eval->>'passed')::boolean,false) then 'PASS' else 'FAIL' end,
    'source_observed_sha256',v_eval->>'source_observed_sha256'
  ));
end;
$function$;

create or replace function programacion.fn_input_rebind_assertion(
  p_run_id bigint,
  p_family_code text,
  p_assertion jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $function$
declare
  v_pantalla_id integer; v_version_id bigint; v_source_ref jsonb; v_receipt jsonb; v_graph jsonb;
  v_path text[]; v_actual jsonb; v_candidate jsonb; v_eval jsonb;
begin
  select r.pantalla_id,r.version_id into v_pantalla_id,v_version_id
  from programacion.input_readiness_runs r where r.id=p_run_id;
  if v_pantalla_id is null then raise exception 'ASSERTION_REBIND_RUN_NOT_FOUND:%',p_run_id; end if;

  v_source_ref:=p_assertion->'source_ref';
  if v_source_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
    v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
    v_receipt:=jsonb_build_object(
      'ref',v_source_ref,'observed',v_graph,
      'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph)
    );
  else
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
  end if;

  select array_agg(x.value order by x.ord) into v_path
  from jsonb_array_elements_text(p_assertion->'path') with ordinality x(value,ord);
  v_actual:=v_receipt #> v_path;
  if v_actual is null then
    raise exception 'ASSERTION_REBIND_PATH_NOT_RESOLVABLE:%:%',p_family_code,p_assertion->'path';
  end if;

  v_candidate:=(p_assertion - 'actual' - 'result' - 'source_observed_sha256')
    || jsonb_build_object(
      'actual',v_actual,
      'assertion_class',coalesce(nullif(btrim(p_assertion->>'assertion_class'),''),'SOURCE_INTEGRITY')
    );
  v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_candidate);
  return v_candidate || jsonb_build_object(
    'result',case when coalesce((v_eval->>'passed')::boolean,false) then 'PASS' else 'FAIL' end,
    'source_observed_sha256',v_eval->>'source_observed_sha256'
  );
end;
$function$;

create or replace function programacion.fn_input_rebind_assertion_specs(
  p_run_id bigint,
  p_family_code text,
  p_specs jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $function$
declare s jsonb; r jsonb; outj jsonb:='[]'::jsonb;
begin
  for s in select value from jsonb_array_elements(p_specs) loop
    r:=programacion.fn_input_rebind_assertion(p_run_id,p_family_code,s);
    if r->>'result'<>'PASS' then
      raise exception 'ASSERTION_SPEC_FAILED run=% family=% source=% path=% expected=% actual=%',
        p_run_id,p_family_code,r->'source_ref',r->'path',r->'expected',r->'actual';
    end if;
    outj:=outj||jsonb_build_array(r);
  end loop;
  return outj;
end
$function$;

do $readback$
declare
  v_run_id bigint;
  v_assertions jsonb;
begin
  select id into v_run_id
  from programacion.input_readiness_runs
  order by id desc
  limit 1;

  if v_run_id is null then
    raise exception 'BLOCK_M4_3_NO_READINESS_RUN_FOR_READBACK';
  end if;

  v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(v_run_id,'SCREEN_IDENTITY');

  if jsonb_typeof(v_assertions)<>'array'
     or jsonb_array_length(v_assertions)=0
     or exists(
       select 1
       from jsonb_array_elements(v_assertions) a
       where nullif(btrim(a->>'assertion_class'),'') is null
          or a->>'assertion_class'<>'SOURCE_INTEGRITY'
     ) then
    raise exception 'BLOCK_M4_3_ASSERTION_CLASS_READBACK';
  end if;
end
$readback$;
