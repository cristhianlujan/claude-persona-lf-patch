\set ON_ERROR_STOP on
-- Isolated PostgreSQL fixture: NEVER point this at a production DSN.
CREATE SCHEMA programacion;
CREATE SCHEMA extensions;
CREATE SCHEMA lf_ops;
CREATE SCHEMA transversal;
CREATE TABLE programacion.componentes (
 id bigint primary key,version_id bigint,componente_codigo text);
CREATE TABLE programacion.input_readiness_runs(
 id bigint primary key, version_id bigint, status text,pantalla_id integer,
 supersedes_run_id bigint,family_count integer,curator_identity text,
 validator_identity text,validator_component_id bigint,contract_revision text,
 source_snapshot_sha256 text,validator_completed_at timestamptz,scope jsonb);
CREATE TABLE programacion.input_family_assessments (
 id bigint generated always as identity primary key,run_id bigint,family_code text,
 validator_outcome text,curator_evidence jsonb,curator_sha256 text,
 semantic_depth_sha256 text, validator_findings jsonb,validator_evidence jsonb,
 validator_identity text, validator_assessed_at timestamptz);
CREATE TABLE programacion.input_validator_assertion_sets_v1(
 assertion_set_sha256 text primary key,assertions jsonb not null);
CREATE TABLE programacion.contratos(
 id bigint generated always as identity,version_id bigint,contrato_codigo text,
 estado text,fail_closed boolean,especificacion jsonb);
CREATE TABLE programacion.fixture_expected(
 run_id bigint,family_code text,expected text,primary key(run_id,family_code));
CREATE TABLE programacion.fixture_proposal_calls(
 run_id bigint,called_at timestamptz default now());
CREATE FUNCTION public.fn_lf_version_compatibility_current_version_id_v1(text,text,text)
RETURNS bigint LANGUAGE sql AS $$ SELECT 19::bigint $$;
CREATE FUNCTION programacion.fn_input_governance_ekb_checkpoint(text,integer,bigint)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"pass":true}'::jsonb $$;
CREATE FUNCTION programacion.fn_v09_sha256_jsonb(jsonb)
RETURNS text LANGUAGE sql AS $$ SELECT md5($1::text) $$;
CREATE FUNCTION programacion.fn_input_screen_canonical_graph(integer,bigint)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"OK"}'::jsonb $$;
CREATE FUNCTION programacion.fn_input_assertion_is_relevant(text,jsonb,jsonb)
RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE FUNCTION programacion.fn_input_governance_assertion_relevant(text,jsonb,jsonb)
RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE FUNCTION programacion.fn_input_resolve_source_ref(jsonb,integer,bigint)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"observed":{"status":"OK"}}'::jsonb $$;
CREATE FUNCTION programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT case when $1 ? 'assertions' then $1 else $1||jsonb_build_object(
 'assertions',(select s.assertions from programacion.input_validator_assertion_sets_v1 s
  where s.assertion_set_sha256=$1->>'assertion_set_sha256')) end
$$;
CREATE FUNCTION programacion.fn_input_v58_build_assertions(bigint,bigint,text)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_array(jsonb_build_object(
   'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH'),
   'path',jsonb_build_array('observed','status'),
   'actual','OK','expected',e.expected,'operator','EQ',
   'assertion_class','CURRENT_CANONICAL_READBACK'
 ))
 FROM programacion.fixture_expected e
 WHERE e.run_id=$1 AND e.family_code=$3
$$;
CREATE FUNCTION programacion.fn_input_governance_bootstrap_assertions_v1(bigint,text)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT programacion.fn_input_v58_build_assertions($1,800,$2)
$$;
CREATE FUNCTION programacion.fn_input_governance_validate_gap_proposals_v1(bigint,text)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 IF (select status from programacion.input_readiness_runs where id=$1)<>'VALIDATING' then
   raise exception 'PROPOSAL_BEFORE_VALIDATING'; END IF;
 INSERT INTO programacion.fixture_proposal_calls(run_id) values ($1);
 RETURN jsonb_build_object('validated_proposal_count',0,'run_id',$1);
END $$;
INSERT INTO programacion.componentes VALUES (111,19,'INPUT_VALIDATOR');
INSERT INTO programacion.contratos(version_id,contrato_codigo,estado,fail_closed,especificacion)
VALUES (19,'INPUT_FAMILY_POLICY_REGISTRY','defined',true,
'{"families":{"F_A":{"validator_oracle_strategy":{"strategy":"SCOPE_GATE"}},
"F_B":{"validator_oracle_strategy":{"strategy":"SCOPE_GATE"}},
"F_C":{"validator_oracle_strategy":{"strategy":"SCOPE_GATE"}},
"F_D":{"validator_oracle_strategy":{"strategy":"SCOPE_GATE"}}}}'::jsonb);

-- The following two functions are copied from the live governed source at test authoring,
-- not rewritten with simplified business behavior; production drift requires recheck.
CREATE OR REPLACE FUNCTION programacion.fn_input_validator_semantic_scope_v1(p_run_id bigint)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_scope jsonb;
  v_selection jsonb;
  v_version bigint;
  v_families jsonb;
  v_result text[]:=ARRAY[]::text[];
  v_code text;
  v_mode text;
BEGIN
  SELECT r.scope,r.version_id INTO v_scope,v_version
  FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATOR_SCOPE_RUN_NOT_FOUND:%',p_run_id;
  END IF;

  -- Every run must state its intended validation mode. Absence is not
  -- equivalent to "no independent semantic proof needed".
  -- SOURCE_INTEGRITY_ONLY is an explicit, non-promotable test mode.
  -- SELECTED_SEMANTIC_COMPARISON must enumerate the selected families.
  -- Neither mode grants APPLIED / N/A or production readiness.
  v_mode:=v_scope->>'validator_semantic_mode';
  v_selection:=v_scope->'validator_semantic_comparison_families';
  IF v_mode IS NULL OR v_selection IS NULL THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_SCOPE_UNDECLARED:%',p_run_id;
  END IF;
  IF v_mode NOT IN ('SOURCE_INTEGRITY_ONLY','SELECTED_SEMANTIC_COMPARISON')
      OR jsonb_typeof(v_selection) IS DISTINCT FROM 'array'
      OR v_scope->>'semantic_promotion_authorized' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_SCOPE_MODE_INVALID:%',p_run_id;
  END IF;
  IF v_mode='SOURCE_INTEGRITY_ONLY' AND jsonb_array_length(v_selection)<>0 THEN
    RAISE EXCEPTION 'VALIDATOR_SOURCE_ONLY_SCOPE_MUST_BE_EMPTY:%',p_run_id;
  END IF;
  IF v_mode='SELECTED_SEMANTIC_COMPARISON'
     AND jsonb_array_length(v_selection)=0 THEN
    RAISE EXCEPTION 'VALIDATOR_SELECTED_SEMANTIC_FAMILIES_REQUIRED:%',p_run_id;
  END IF;

  SELECT c.especificacion->'families' INTO v_families
  FROM programacion.contratos c
  WHERE c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    AND c.version_id=v_version AND c.estado='defined'
  ORDER BY c.id DESC LIMIT 1;
  IF v_families IS NULL OR jsonb_typeof(v_families)<>'object' THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_FAMILY_REGISTRY_MISSING:%',p_run_id;
  END IF;

  IF EXISTS(
    SELECT 1 FROM jsonb_array_elements(v_selection) t(value)
    WHERE jsonb_typeof(value)<>'string'
       OR value#>>'{}' !~ '^[A-Z][A-Z0-9_]*$'
  ) THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_COMPARISON_FAMILY_INVALID:%',p_run_id;
  END IF;
  FOR v_code IN SELECT x.value FROM jsonb_array_elements_text(v_selection) x(value) LOOP
    IF v_code=ANY(v_result) THEN
      RAISE EXCEPTION 'VALIDATOR_SEMANTIC_COMPARISON_DUPLICATE:%',v_code;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM programacion.input_family_assessments a
      WHERE a.run_id=p_run_id AND a.family_code=v_code
    ) OR coalesce(v_families->v_code->'validator_oracle_strategy'->>'strategy','')='' THEN
      RAISE EXCEPTION 'VALIDATOR_SEMANTIC_COMPARISON_FAMILY_UNREGISTERED:%',v_code;
    END IF;
    v_result:=array_append(v_result,v_code);
  END LOOP;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_evaluate_assertion(p_run_id bigint, p_family_code text, p_assertion jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
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

