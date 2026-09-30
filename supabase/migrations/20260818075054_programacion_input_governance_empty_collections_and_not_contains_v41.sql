create or replace function programacion.fn_input_resolve_source_ref(p_ref jsonb, p_pantalla_id integer, p_version_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops','transversal'
as $$
declare
  v_kind text := p_ref->>'kind';
  v_observed jsonb;
  v_code text;
  v_codes text[];
  v_ids bigint[];
  v_expected integer;
  v_actual integer;
  v_capability text;
  v_relations jsonb := '[]'::jsonb;
  v_rules jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_ref) <> 'object' or coalesce(v_kind,'')='' then raise exception 'INVALID_STRUCTURED_SOURCE_REF'; end if;

  case v_kind
    when 'SCREEN' then
      select to_jsonb(p) into v_observed from lf_ops.pantallas p where p.id=p_pantalla_id;
      if v_observed is null then raise exception 'SOURCE_REF_UNRESOLVED:SCREEN:%',p_pantalla_id; end if;
    when 'SCREEN_RULE_SET' then
      select jsonb_build_object('screen',to_jsonb(p),'rules',coalesce((
        select jsonb_agg(jsonb_build_object('link',to_jsonb(rp),'rule',to_jsonb(r)) order by r.id)
        from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id where rp.pantalla_id=p.id
      ),'[]'::jsonb)) into v_observed from lf_ops.pantallas p where p.id=p_pantalla_id;
      if v_observed is null then raise exception 'SOURCE_REF_UNRESOLVED:SCREEN_RULE_SET:%',p_pantalla_id; end if;
    when 'RULE' then
      v_code:=p_ref->>'codigo';
      select to_jsonb(r) into v_observed from lf_ops.reglas r where r.codigo=v_code;
      if v_observed is null then raise exception 'SOURCE_REF_UNRESOLVED:RULE:%',coalesce(v_code,'NULL'); end if;
    when 'ROUTE_SET' then
      select array_agg(x::bigint order by x::bigint) into v_ids from jsonb_array_elements_text(p_ref->'ids') x;
      if v_ids is null or cardinality(v_ids)=0 then raise exception 'INVALID_ROUTE_SET_REF'; end if;
      v_expected:=cardinality(v_ids);
      select count(*),jsonb_agg(to_jsonb(r) order by r.route_id) into v_actual,v_observed from lf_ops.rutas r where r.route_id=any(v_ids);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:ROUTE_SET expected=% actual=%',v_expected,v_actual; end if;
    when 'SECURITY_POLICY_SET' then
      select array_agg(x::bigint order by x::bigint) into v_ids from jsonb_array_elements_text(p_ref->'ids') x;
      if v_ids is null or cardinality(v_ids)=0 then raise exception 'INVALID_SECURITY_POLICY_SET_REF'; end if;
      v_expected:=cardinality(v_ids);
      select count(*),jsonb_agg(to_jsonb(s) order by s.security_policy_id) into v_actual,v_observed from lf_ops.politicas_seguridad s where s.security_policy_id=any(v_ids);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:SECURITY_POLICY_SET expected=% actual=%',v_expected,v_actual; end if;
    when 'TRANSITION_SET' then
      select array_agg(x::bigint order by x::bigint) into v_ids from jsonb_array_elements_text(p_ref->'ids') x;
      if v_ids is null or cardinality(v_ids)=0 then raise exception 'INVALID_TRANSITION_SET_REF'; end if;
      v_expected:=cardinality(v_ids);
      select count(*),jsonb_agg(to_jsonb(t) order by t.transition_id) into v_actual,v_observed from lf_ops.estados_transiciones t where t.transition_id=any(v_ids);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:TRANSITION_SET expected=% actual=%',v_expected,v_actual; end if;
    when 'SCREEN_STATE_SET' then
      if not exists(select 1 from lf_ops.pantallas p where p.id=p_pantalla_id) then raise exception 'SOURCE_REF_UNRESOLVED:SCREEN_STATE_SET_SCREEN:%',p_pantalla_id; end if;
      select coalesce(jsonb_agg(to_jsonb(s) order by s.state_id),'[]'::jsonb) into v_observed from lf_ops.pantallas_estados s where s.pantalla_id=p_pantalla_id;
    when 'CURRENT_VISUAL_ARTIFACT' then
      if not exists(select 1 from lf_ops.pantallas p where p.id=p_pantalla_id) then raise exception 'SOURCE_REF_UNRESOLVED:CURRENT_VISUAL_ARTIFACT_SCREEN:%',p_pantalla_id; end if;
      select coalesce(jsonb_agg(jsonb_build_object(
        'artifact',to_jsonb(a),
        'storage_exists',case when a.storage_bucket is not null and a.storage_object_path is not null
          then exists(select 1 from storage.objects o where o.bucket_id=a.storage_bucket and o.name=a.storage_object_path)
          else false end
      ) order by a.id),'[]'::jsonb) into v_observed
      from lf_ops.pantalla_artefactos a where a.pantalla_id=p_pantalla_id and a.is_current=true;
    when 'EKB_ERROR_SET' then
      select array_agg(x order by x) into v_codes from jsonb_array_elements_text(p_ref->'codes') x;
      if v_codes is null or cardinality(v_codes)=0 then raise exception 'INVALID_EKB_ERROR_SET_REF'; end if;
      v_expected:=cardinality(v_codes);
      select count(*),jsonb_agg(to_jsonb(e) order by e.codigo) into v_actual,v_observed from transversal.error_knowledge e where e.codigo=any(v_codes);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:EKB_ERROR_SET expected=% actual=%',v_expected,v_actual; end if;
    when 'EKB_PREVENTION_SET' then
      select array_agg(x order by x) into v_codes from jsonb_array_elements_text(p_ref->'codes') x;
      if v_codes is null or cardinality(v_codes)=0 then raise exception 'INVALID_EKB_PREVENTION_SET_REF'; end if;
      v_expected:=cardinality(v_codes);
      select count(*),jsonb_agg(to_jsonb(e) order by e.regla_codigo) into v_actual,v_observed from transversal.prevention_rules e where e.regla_codigo=any(v_codes);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:EKB_PREVENTION_SET expected=% actual=%',v_expected,v_actual; end if;
    when 'EKB_DECISION_SET' then
      select array_agg(x order by x) into v_codes from jsonb_array_elements_text(p_ref->'adrs') x;
      if v_codes is null or cardinality(v_codes)=0 then raise exception 'INVALID_EKB_DECISION_SET_REF'; end if;
      v_expected:=cardinality(v_codes);
      select count(*),jsonb_agg(to_jsonb(d) order by d.adr) into v_actual,v_observed from transversal.decision_log d where d.adr=any(v_codes);
      if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:EKB_DECISION_SET expected=% actual=%',v_expected,v_actual; end if;
    when 'CONTRACT' then
      v_code:=p_ref->>'codigo';
      select to_jsonb(c) into v_observed from programacion.contratos c where c.version_id=p_version_id and c.contrato_codigo=v_code;
      if v_observed is null then raise exception 'SOURCE_REF_UNRESOLVED:CONTRACT:%',coalesce(v_code,'NULL'); end if;
    when 'CAPABILITY_ABSENCE' then
      v_capability:=upper(p_ref->>'capability');
      if v_capability not in ('FEATURE_FLAGS','I18N_FORMATS') then raise exception 'UNSUPPORTED_CAPABILITY_ABSENCE:%',coalesce(v_capability,'NULL'); end if;
      if v_capability='FEATURE_FLAGS' then
        select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname) order by n.nspname,c.relname),'[]'::jsonb) into v_relations
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('lf_ops','lf_design') and c.relkind in ('r','v','m') and lower(c.relname) ~ '(feature.*flag|flag.*feature)';
        select coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'categoria',r.categoria) order by r.codigo),'[]'::jsonb) into v_rules
        from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
        where rp.pantalla_id=p_pantalla_id and r.codigo<>'B2B-RULE-STORY-READINESS-001'
          and (upper(coalesce(r.categoria,'')) in ('FEATURE_FLAG','FEATURE_FLAGS') or upper(r.codigo) like '%FEATURE%FLAG%');
      else
        select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname) order by n.nspname,c.relname),'[]'::jsonb) into v_relations
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('lf_ops','lf_design') and c.relkind in ('r','v','m') and lower(c.relname) ~ '(i18n|locale|localization|localisation)';
        select coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'categoria',r.categoria) order by r.codigo),'[]'::jsonb) into v_rules
        from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
        where rp.pantalla_id=p_pantalla_id and r.codigo<>'B2B-RULE-STORY-READINESS-001'
          and upper(coalesce(r.categoria,'')) in ('I18N','LOCALIZATION','LOCALISATION','LOCALE');
      end if;
      if jsonb_array_length(v_relations)>0 or jsonb_array_length(v_rules)>0 then raise exception 'CAPABILITY_ABSENCE_ASSERTION_FALSE:%',v_capability; end if;
      v_observed:=jsonb_build_object('capability',v_capability,'matching_relations',v_relations,'matching_linked_rules',v_rules,'pantalla_id',p_pantalla_id);
    else raise exception 'UNSUPPORTED_SOURCE_REF_KIND:%',v_kind;
  end case;
  return jsonb_build_object('ref',p_ref,'observed',v_observed,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed));
end;
$$;

create or replace function programacion.fn_input_evaluate_assertion(p_run_id bigint, p_family_code text, p_assertion jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
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
begin
  if jsonb_typeof(p_assertion)<>'object' then raise exception 'ASSERTION_NOT_OBJECT:%',p_family_code; end if;
  if not (p_assertion ? 'source_ref') or not (p_assertion ? 'path') or not (p_assertion ? 'actual') or not (p_assertion ? 'expected') or not (p_assertion ? 'operator') then raise exception 'ASSERTION_REQUIRED_FIELDS_MISSING:%',p_family_code; end if;
  v_source_ref:=p_assertion->'source_ref';
  if jsonb_typeof(v_source_ref)<>'object' then raise exception 'ASSERTION_SOURCE_REF_INVALID:%',p_family_code; end if;
  if jsonb_typeof(p_assertion->'path')<>'array' or jsonb_array_length(p_assertion->'path')=0 then raise exception 'ASSERTION_PATH_INVALID:%',p_family_code; end if;
  select r.pantalla_id,r.version_id into v_pantalla_id,v_version_id from programacion.input_readiness_runs r where r.id=p_run_id;
  if v_pantalla_id is null then raise exception 'ASSERTION_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_source_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
    v_allowed:=true;
    v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
    v_receipt:=jsonb_build_object('ref',v_source_ref,'observed',v_graph,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph));
  else
    select exists(select 1 from programacion.input_family_assessments a cross join lateral jsonb_array_elements(a.source_refs) e(ref)
      where a.run_id=p_run_id and a.family_code=p_family_code and e.ref=v_source_ref) into v_allowed;
    if not v_allowed then raise exception 'ASSERTION_SOURCE_NOT_DECLARED:%',p_family_code; end if;
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
  end if;
  select array_agg(x.value order by x.ord) into v_path from jsonb_array_elements_text(p_assertion->'path') with ordinality x(value,ord);
  v_actual_db:=v_receipt #> v_path;
  v_actual_claim:=p_assertion->'actual';
  v_expected:=p_assertion->'expected';
  v_operator:=upper(p_assertion->>'operator');
  if v_actual_claim is distinct from v_actual_db then raise exception 'ASSERTION_ACTUAL_NOT_SOURCE_DERIVED:%',p_family_code; end if;
  case v_operator
    when 'EQ' then v_pass:=v_actual_db=v_expected;
    when 'NE' then v_pass:=v_actual_db is distinct from v_expected;
    when 'CONTAINS' then v_pass:=coalesce(v_actual_db @> v_expected,false);
    when 'NOT_CONTAINS' then v_pass:=not coalesce(v_actual_db @> v_expected,false);
    when 'ARRAY_LENGTH_EQ' then
      if jsonb_typeof(v_actual_db)<>'array' or jsonb_typeof(v_expected)<>'number' then raise exception 'ASSERTION_ARRAY_LENGTH_TYPES_INVALID:%',p_family_code; end if;
      v_pass:=jsonb_array_length(v_actual_db)=(v_expected #>> '{}')::integer;
    else raise exception 'ASSERTION_OPERATOR_UNSUPPORTED:%:%',p_family_code,v_operator;
  end case;
  return jsonb_build_object('passed',v_pass,'actual',v_actual_db,'expected',v_expected,'operator',v_operator,'source_ref',v_source_ref,'path',p_assertion->'path','source_observed_sha256',v_receipt->>'observed_sha256');
end;
$$;

revoke all on function programacion.fn_input_resolve_source_ref(jsonb,integer,bigint) from public;
revoke all on function programacion.fn_input_evaluate_assertion(bigint,text,jsonb) from public;
grant execute on function programacion.fn_input_resolve_source_ref(jsonb,integer,bigint) to postgres;
grant execute on function programacion.fn_input_evaluate_assertion(bigint,text,jsonb) to postgres;

update programacion.contratos
set especificacion=jsonb_set(
  jsonb_set(especificacion,'{contract_revision}','"4.1"'::jsonb,true),
  '{empty_collection_semantics}','"CANONICAL_EMPTY_ARRAY_IS_RESOLVABLE_EVIDENCE"'::jsonb,true
)
where version_id=12 and contrato_codigo='INPUT_READINESS_CONTRACT';