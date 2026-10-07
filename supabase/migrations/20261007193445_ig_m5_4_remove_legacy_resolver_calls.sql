-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.4 / NEGATIVE_NO_CLASSIFY repair.
-- Remove hardcoded legacy resolver calls from Curator paths.
-- Resolver implementations are resolved from current INPUT_FAMILY_POLICY_REGISTRY.

do $patch_bootstrap$
declare
  v_def text;
  v_pos integer;
  v_old text := '    v_class:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,v_version);';
  v_new text := E'    v_m54_policy:=v_m54_policy_registry->''families''->v_family;\n'
    || E'    v_m54_resolver:=v_m54_policy#>>''{deterministic_resolver,function}'';\n'
    || E'    v_m54_resolver_oid:=to_regprocedure(v_m54_resolver);\n'
    || E'    if v_m54_resolver_oid is null or not exists (select 1 from pg_proc p where p.oid=v_m54_resolver_oid and p.pronargs=3 and p.prorettype=''jsonb''::regtype) then\n'
    || E'      raise exception ''INPUT_GOVERNANCE_DETERMINISTIC_RESOLVER_INVALID:%:%'',v_family,coalesce(v_m54_resolver,''<NULL>'');\n'
    || E'    end if;\n'
    || E'    execute format(''select %s($1,$2,$3)'',v_m54_resolver_oid::regproc)\n'
    || E'      using p_pantalla_id,v_family,v_version into v_class;';
  v_loop text := '  for v_family in select value from jsonb_array_elements_text(v_families) loop';
  v_loop_new text := E'  select c.especificacion into v_m54_policy_registry\n'
    || E'  from programacion.contratos c\n'
    || E'  where c.version_id=public.fn_lf_version_compatibility_current_version_id_v1(''PROGRAMACION_CONTRACT'',''INPUT_FAMILY_POLICY_REGISTRY'',null)\n'
    || E'    and c.contrato_codigo=''INPUT_FAMILY_POLICY_REGISTRY'' and c.estado=''defined'' and c.fail_closed\n'
    || E'  order by c.id desc limit 1;\n'
    || E'  if v_m54_policy_registry is null then raise exception ''INPUT_FAMILY_POLICY_REGISTRY_UNRESOLVED''; end if;\n'
    || E'  for v_family in select value from jsonb_array_elements_text(v_families) loop';
begin
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)'::regprocedure) into v_def;
  if position('v_m54_policy_registry jsonb;' in v_def)=0 then
    v_pos:=position(E'\ndeclare\n' in v_def);
    if v_pos=0 then raise exception 'M54_BOOTSTRAP_DECLARE_ANCHOR_MISSING'; end if;
    v_def:=overlay(v_def placing E'\ndeclare\n  v_m54_policy_registry jsonb;\n  v_m54_policy jsonb;\n  v_m54_resolver text;\n  v_m54_resolver_oid oid;\n' from v_pos for length(E'\ndeclare\n'));
  end if;
  if position(v_loop in v_def)=0 or position(v_old in v_def)=0 then
    raise exception 'M54_BOOTSTRAP_RESOLVER_ANCHOR_MISSING';
  end if;
  v_def:=replace(v_def,v_loop,v_loop_new);
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end;
$patch_bootstrap$;

do $patch_rebind$
declare
  v_def text;
  v_pos integer;
  v_old text := E'    v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(\n      p_pantalla_id,a.family_code,v_version\n    );';
  v_new text := E'    v_m54_policy:=v_m54_policy_registry->''families''->a.family_code;\n'
    || E'    v_m54_resolver:=v_m54_policy#>>''{deterministic_resolver,function}'';\n'
    || E'    v_m54_resolver_oid:=to_regprocedure(v_m54_resolver);\n'
    || E'    if v_m54_resolver_oid is null or not exists (select 1 from pg_proc p where p.oid=v_m54_resolver_oid and p.pronargs=3 and p.prorettype=''jsonb''::regtype) then\n'
    || E'      raise exception ''INPUT_GOVERNANCE_DETERMINISTIC_RESOLVER_INVALID:%:%'',a.family_code,coalesce(v_m54_resolver,''<NULL>'');\n'
    || E'    end if;\n'
    || E'    execute format(''select %s($1,$2,$3)'',v_m54_resolver_oid::regproc)\n'
    || E'      using p_pantalla_id,a.family_code,v_version into v_classifier;';
  v_loop text := '  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code';
  v_loop_new text := E'  select c.especificacion into v_m54_policy_registry\n'
    || E'  from programacion.contratos c\n'
    || E'  where c.version_id=public.fn_lf_version_compatibility_current_version_id_v1(''PROGRAMACION_CONTRACT'',''INPUT_FAMILY_POLICY_REGISTRY'',null)\n'
    || E'    and c.contrato_codigo=''INPUT_FAMILY_POLICY_REGISTRY'' and c.estado=''defined'' and c.fail_closed\n'
    || E'  order by c.id desc limit 1;\n'
    || E'  if v_m54_policy_registry is null then raise exception ''INPUT_FAMILY_POLICY_REGISTRY_UNRESOLVED''; end if;\n'
    || E'  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code';
begin
  select pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure) into v_def;
  if position('v_m54_policy_registry jsonb;' in v_def)=0 then
    v_pos:=position(E'\ndeclare\n' in v_def);
    if v_pos=0 then raise exception 'M54_REBIND_DECLARE_ANCHOR_MISSING'; end if;
    v_def:=overlay(v_def placing E'\ndeclare\n  v_m54_policy_registry jsonb;\n  v_m54_policy jsonb;\n  v_m54_resolver text;\n  v_m54_resolver_oid oid;\n' from v_pos for length(E'\ndeclare\n'));
  end if;
  if position(v_loop in v_def)=0 or position(v_old in v_def)=0 then
    raise exception 'M54_REBIND_RESOLVER_ANCHOR_MISSING';
  end if;
  v_def:=replace(v_def,v_loop,v_loop_new);
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end;
$patch_rebind$;

do $patch_stale$
declare
  v_def text;
  v_pos integer;
  v_old text := '    v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph);';
  v_new text := E'    v_m54_policy:=v_m54_policy_registry->''families''->v_family;\n'
    || E'    v_m54_resolver:=v_m54_policy#>>''{deterministic_resolver,function}'';\n'
    || E'    v_m54_resolver_oid:=to_regprocedure(v_m54_resolver);\n'
    || E'    if v_m54_resolver_oid is null or not exists (select 1 from pg_proc p where p.oid=v_m54_resolver_oid and p.pronargs=3 and p.prorettype=''jsonb''::regtype) then\n'
    || E'      raise exception ''INPUT_GOVERNANCE_DETERMINISTIC_RESOLVER_INVALID:%:%'',v_family,coalesce(v_m54_resolver,''<NULL>'');\n'
    || E'    end if;\n'
    || E'    execute format(''select %s($1,$2,$3)'',v_m54_resolver_oid::regproc)\n'
    || E'      using p_pantalla_id,v_family,v_version into v_class;';
  v_loop text := E'  for v_family in\n    select value from jsonb_array_elements_text((select valor_config->''families'' from lf_ops.reglas where codigo=''B2B-RULE-STORY-READINESS-001''))\n  loop';
  v_loop_new text := E'  select c.especificacion into v_m54_policy_registry\n'
    || E'  from programacion.contratos c\n'
    || E'  where c.version_id=public.fn_lf_version_compatibility_current_version_id_v1(''PROGRAMACION_CONTRACT'',''INPUT_FAMILY_POLICY_REGISTRY'',null)\n'
    || E'    and c.contrato_codigo=''INPUT_FAMILY_POLICY_REGISTRY'' and c.estado=''defined'' and c.fail_closed\n'
    || E'  order by c.id desc limit 1;\n'
    || E'  if v_m54_policy_registry is null then raise exception ''INPUT_FAMILY_POLICY_REGISTRY_UNRESOLVED''; end if;\n'
    || v_loop;
begin
  select pg_get_functiondef('programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure) into v_def;
  if position('v_m54_policy_registry jsonb;' in v_def)=0 then
    v_pos:=position(E'\ndeclare\n' in v_def);
    if v_pos=0 then raise exception 'M54_STALE_DECLARE_ANCHOR_MISSING'; end if;
    v_def:=overlay(v_def placing E'\ndeclare\n  v_m54_policy_registry jsonb;\n  v_m54_policy jsonb;\n  v_m54_resolver text;\n  v_m54_resolver_oid oid;\n' from v_pos for length(E'\ndeclare\n'));
  end if;
  if position(v_loop in v_def)=0 or position(v_old in v_def)=0 then
    raise exception 'M54_STALE_RESOLVER_ANCHOR_MISSING';
  end if;
  v_def:=replace(v_def,v_loop,v_loop_new);
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end;
$patch_stale$;

do $patch_recurate$
declare
  v_def text;
  v_pos integer;
  v_old text := '    v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph);';
  v_new text := E'    v_m54_policy:=v_m54_policy_registry->''families''->v_family;\n'
    || E'    v_m54_resolver:=v_m54_policy#>>''{deterministic_resolver,function}'';\n'
    || E'    v_m54_resolver_oid:=to_regprocedure(v_m54_resolver);\n'
    || E'    if v_m54_resolver_oid is null or not exists (select 1 from pg_proc p where p.oid=v_m54_resolver_oid and p.pronargs=3 and p.prorettype=''jsonb''::regtype) then\n'
    || E'      raise exception ''INPUT_GOVERNANCE_DETERMINISTIC_RESOLVER_INVALID:%:%'',v_family,coalesce(v_m54_resolver,''<NULL>'');\n'
    || E'    end if;\n'
    || E'    execute format(''select %s($1,$2,$3)'',v_m54_resolver_oid::regproc)\n'
    || E'      using p_pantalla_id,v_family,v_version into v_class;';
  v_loop text := '  for v_family in select value from jsonb_array_elements_text((select valor_config->''families'' from lf_ops.reglas where codigo=''B2B-RULE-STORY-READINESS-001'')) loop';
  v_loop_new text := E'  select c.especificacion into v_m54_policy_registry\n'
    || E'  from programacion.contratos c\n'
    || E'  where c.version_id=public.fn_lf_version_compatibility_current_version_id_v1(''PROGRAMACION_CONTRACT'',''INPUT_FAMILY_POLICY_REGISTRY'',null)\n'
    || E'    and c.contrato_codigo=''INPUT_FAMILY_POLICY_REGISTRY'' and c.estado=''defined'' and c.fail_closed\n'
    || E'  order by c.id desc limit 1;\n'
    || E'  if v_m54_policy_registry is null then raise exception ''INPUT_FAMILY_POLICY_REGISTRY_UNRESOLVED''; end if;\n'
    || v_loop;
begin
  select pg_get_functiondef('programacion.fn_input_governance_recurate_v2(integer,text,text)'::regprocedure) into v_def;
  if position('v_m54_policy_registry jsonb;' in v_def)=0 then
    v_pos:=position(E'\ndeclare\n' in v_def);
    if v_pos=0 then raise exception 'M54_RECURATE_DECLARE_ANCHOR_MISSING'; end if;
    v_def:=overlay(v_def placing E'\ndeclare\n  v_m54_policy_registry jsonb;\n  v_m54_policy jsonb;\n  v_m54_resolver text;\n  v_m54_resolver_oid oid;\n' from v_pos for length(E'\ndeclare\n'));
  end if;
  if position(v_loop in v_def)=0 or position(v_old in v_def)=0 then
    raise exception 'M54_RECURATE_RESOLVER_ANCHOR_MISSING';
  end if;
  v_def:=replace(v_def,v_loop,v_loop_new);
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end;
$patch_recurate$;

do $patch_materializer_semantic$
declare
  v_def text;
  v_old text := E'      if v_semantic_resolver is distinct from ''programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)''\n'
    || E'         or to_regprocedure(v_semantic_resolver) is null then\n'
    || E'        raise exception ''M5_4_SEMANTIC_RESOLVER_UNSUPPORTED:%:%'',v_core_assessment.family_code,v_semantic_resolver;\n'
    || E'      end if;\n'
    || E'      v_semantic_probe:=programacion.fn_input_governance_semantic_probe_v3(\n'
    || E'        p_pantalla_id,v_core_assessment.family_code,v_version\n'
    || E'      );';
  v_new text := E'      v_m54_semantic_resolver_oid:=to_regprocedure(v_semantic_resolver);\n'
    || E'      if v_m54_semantic_resolver_oid is null or not exists (select 1 from pg_proc p where p.oid=v_m54_semantic_resolver_oid and p.pronargs=3 and p.prorettype=''jsonb''::regtype) then\n'
    || E'        raise exception ''M5_4_SEMANTIC_RESOLVER_UNSUPPORTED:%:%'',v_core_assessment.family_code,coalesce(v_semantic_resolver,''<NULL>'');\n'
    || E'      end if;\n'
    || E'      execute format(''select %s($1,$2,$3)'',v_m54_semantic_resolver_oid::regproc)\n'
    || E'        using p_pantalla_id,v_core_assessment.family_code,v_version into v_semantic_probe;';
  v_decl_anchor text := '  v_semantic_resolver text;';
begin
  select pg_get_functiondef('programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure) into v_def;
  if position('v_m54_semantic_resolver_oid oid;' in v_def)=0 then
    if position(v_decl_anchor in v_def)=0 then raise exception 'M54_MATERIALIZER_DECL_ANCHOR_MISSING'; end if;
    v_def:=replace(v_def,v_decl_anchor,v_decl_anchor||E'\n  v_m54_semantic_resolver_oid oid;');
  end if;
  if position(v_old in v_def)=0 then
    raise exception 'M54_MATERIALIZER_SEMANTIC_ANCHOR_MISSING';
  end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end;
$patch_materializer_semantic$;

do $verify$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_governance_curator_materialize_v1',
      'fn_input_governance_curator_rebind_v1',
      'fn_input_governance_bootstrap_materialize_v2',
      'fn_input_governance_recurate_source_stale_v1',
      'fn_input_governance_recurate_v2'
    )
    and (
      lower(p.prosrc) ~ 'classify_v[12]'
      or lower(p.prosrc) ~ 'probe_v[123]'
    );
  if v_bad<>0 then
    raise exception 'M54_LEGACY_RESOLVER_REFERENCE_REMAINS:%',v_bad;
  end if;
end;
$verify$;
