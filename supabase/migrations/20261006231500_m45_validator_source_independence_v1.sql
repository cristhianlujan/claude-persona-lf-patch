-- M4.5 root repair: validator source authority must not come from Curator source_refs.
-- Reuse existing family relevance gates + canonical source resolver (T-SOURCE path).

do $pre$
declare
  v_eval_md5 text;
  v_resolver_md5 text;
begin
  v_eval_md5:=md5(pg_get_functiondef(
    'programacion.fn_input_evaluate_assertion(bigint,text,jsonb)'::regprocedure
  ));
  if v_eval_md5 is distinct from 'b6fb526258618fc7e36e79c3f60e14ba' then
    raise exception 'M45_EVALUATOR_BASE_DRIFT expected=b6fb526258618fc7e36e79c3f60e14ba actual=%',v_eval_md5;
  end if;

  v_resolver_md5:=md5(pg_get_functiondef(
    'programacion.fn_input_resolve_source_ref(jsonb,integer,bigint)'::regprocedure
  ));
  if v_resolver_md5 is distinct from '9af332e590d2949766b4f2eb795b594b' then
    raise exception 'M45_SOURCE_RESOLVER_BASE_DRIFT expected=9af332e590d2949766b4f2eb795b594b actual=%',v_resolver_md5;
  end if;
end;
$pre$;

create or replace function programacion.fn_input_evaluate_assertion(
  p_run_id bigint,
  p_family_code text,
  p_assertion jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
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
     or not (p_assertion ? 'operator') then
    raise exception 'ASSERTION_REQUIRED_FIELDS_MISSING:%',p_family_code;
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

  -- M4.5: source admissibility is derived from family semantics, not from
  -- Curator-authored input_family_assessments.source_refs.
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
    'actual',v_actual_db,
    'expected',v_expected,
    'operator',v_operator,
    'source_ref',v_source_ref,
    'path',p_assertion->'path',
    'source_observed_sha256',v_receipt->>'observed_sha256'
  );
end;
$function$;

comment on function programacion.fn_input_evaluate_assertion(bigint,text,jsonb)
is 'M4.5: validates assertion source relevance from family/governance policy, then resolves via canonical source resolver. Curator source_refs are not source authority or allowlist.';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'NEG_CURATOR_REF_INJECTION',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','NEG_CURATOR_REF_INJECTION',
      'checkpoint_title','Negativo: una ref falsa en source_refs del Curator no es usada por el Validator',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','VERIFY_EXACT',
      'precision','EXPLICIT_VALIDATOR_SOURCE_AUTHORITY_INDEPENDENCE',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Validator evaluator does not read Curator source_refs; assertion sources are admitted by family/governance relevance and resolved through canonical source resolution. A 47-family rebind sample remains executable.',
      'verification_queries',jsonb_build_array(
        $q$
with d as (
  select pg_get_functiondef(
    'programacion.fn_input_evaluate_assertion(bigint,text,jsonb)'::regprocedure
  ) as evaluator_def
), latest as (
  select id,supersedes_run_id
  from programacion.input_readiness_runs
  where status='COMPLETED'
    and family_count=47
    and supersedes_run_id is not null
  order by id desc
  limit 1
), fam as materialized (
  select a.family_code,
         programacion.fn_input_v58_build_assertions(
           l.id,l.supersedes_run_id,a.family_code
         ) as assertions
  from latest l
  join programacion.input_family_assessments a on a.run_id=l.id
)
select
  position('from programacion.input_family_assessments' in lower(d.evaluator_def))=0 as no_curator_assessment_read,
  position('jsonb_array_elements(a.source_refs)' in lower(d.evaluator_def))=0 as no_curator_source_ref_allowlist,
  position('fn_input_assertion_is_relevant' in d.evaluator_def)>0 as family_relevance_gate_present,
  position('fn_input_governance_assertion_relevant' in d.evaluator_def)>0 as governance_relevance_gate_present,
  position('fn_input_resolve_source_ref' in d.evaluator_def)>0 as canonical_source_resolver_present,
  (select count(*) from fam)=47 as sample_47_families_present,
  (select count(*) from fam where jsonb_typeof(assertions)='array' and jsonb_array_length(assertions)>0)=47 as sample_47_families_rebound
from d
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'USE_CURATOR_SOURCE_REFS_AS_VALIDATOR_AUTHORITY',
        'ADD_SECOND_SOURCE_RESOLVER',
        'REEXECUTE_DEPENDENCY_OWNED_TEST_CASESET'
      ),
      'contract_correction','VALIDATOR_SOURCE_AUTHORITY_IS_FAMILY_RELEVANCE_PLUS_T_SOURCE_RESOLUTION'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.5';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'INPUT-GOV-VALIDATOR-CURATOR-SOURCE-REF-AUTHORITY-001',
  'INPUT_GOVERNANCE',
  'Validator source authority must not depend on Curator source_refs',
  'fn_input_evaluate_assertion used current input_family_assessments.source_refs as an allowlist before resolving non-canonical assertion sources. This made Curator output part of Validator source authority even though source discovery is owned by T-SOURCE/SOURCE_RESOLUTION_POLICY.',
  'Assertion source admissibility mixed Curator evidence declaration with independent Validator source authority.',
  'VALIDATOR_SOURCE_AUTHORITY_LEAKS_FROM_CURATOR_SOURCE_REFS',
  'Admit assertion sources by the existing family/governance relevance functions and resolve them through fn_input_resolve_source_ref. Never enumerate or authorize Validator sources from Curator source_refs.',
  'M4.5 repair: evaluator no longer references input_family_assessments/source_refs; family/governance relevance gates are mandatory; canonical resolver remains the only non-graph source resolver; bounded 47-family rebind sample must remain green.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_input_evaluate_assertion; supabase://programacion.fn_input_resolve_source_ref; supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M4.5',
  'EXECUTION',
  array['INPUT_VALIDATOR','ENGINEERING_SCHEDULER']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.5 independent source discovery',
  'supabase://programacion.fn_input_evaluate_assertion'
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
