-- LF ACT-0001: prevent false READY on all unstructured mutating requests.
-- All exact path, canonical discovery and native operation checks stay intact.
begin;
do $preflight$
begin
  if md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
      <> '2c94edcb7982373d5b761f57ef790741' then
    raise exception 'ROUTER_INTENT_BOUNDARY_SOURCE_DRIFT';
  end if;
end;
$preflight$;

CREATE OR REPLACE FUNCTION public.lf_router_resolve_v1(p_request_text text, p_target_hint text DEFAULT NULL::text, p_action_hint text DEFAULT NULL::text, p_asset_type_hint text DEFAULT NULL::text, p_distribution_mode text DEFAULT 'ROUTER'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_req text;
  v_executor_candidates jsonb := '[]'::jsonb;
  v_screen_subjects jsonb := '[]'::jsonb;
  v_screen_subject_count integer := 0;
  v_target_norm text;
  v_action text;
  v_type_hint text;
  v_candidate_code text;
  v_asset public.lf_activos%rowtype;
  v_asset_found boolean := false;
  v_rule public.lf_router_action_registry%rowtype;
  v_operation public.lf_operation_registry%rowtype;
  v_target_operation public.lf_operation_registry%rowtype;
  v_contract_refs jsonb := '[]'::jsonb;
  v_next_step jsonb := null;
  v_policy_refs jsonb := '[]'::jsonb;
  v_adapters jsonb := '[]'::jsonb;
  v_required_policy_count integer := 0;
  v_resolved_policy_count integer := 0;
  v_contract_count integer := 0;
  v_step_count integer := 0;
  v_input_governance jsonb := null;
  v_exact_asset_candidates jsonb := '[]'::jsonb;
  v_exact_asset_count integer := 0;
  v_artifact_discovery jsonb := null;
  v_discovery_count integer := 0;
begin
  if btrim(coalesce(p_request_text,''))='' then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_EMPTY_REQUEST','router','ACT-0001');
  end if;

  v_req := regexp_replace(translate(lower(coalesce(p_request_text,'')),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g');
  v_req := regexp_replace(v_req,'\s+',' ','g');
  v_target_norm := regexp_replace(translate(lower(coalesce(p_target_hint,'')),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g');

  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint,'')),''));
  if v_type_hint is null then
    if v_req ~ '(^| )(perfil|profile)( |$)' or v_req ~ '(^| )pidele (al|a|el) ' then v_type_hint := 'PERFIL';
    elsif v_req ~ '(^| )skill( |$)' then v_type_hint := 'SKILL';
    elsif v_req ~ '(^| )adapter( |$)' then v_type_hint := 'ADAPTER';
    elsif v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|relacion|link)( |$)' and v_req ~ '(^| )(regla|policy)( |$)' and v_req ~ '(^| )(pantalla|screen)( |$)' then v_type_hint := 'REGLA_PANTALLA_RELATION';
    elsif v_req ~ '(^| )(policy|politica|regla)( |$)' then v_type_hint := 'REGLA';
    elsif v_req ~ '(^| )(estrategia|strategy)( |$)' then v_type_hint := 'STRATEGY';
    elsif v_req ~ '(^| )(doc|documento)( |$)' then v_type_hint := 'DOC';
    end if;
  end if;

  if v_target_norm<>'' then
    if v_type_hint='OPERATION_CODE' then
      select r.* into v_target_operation
      from public.lf_operation_registry r
      where lower(r.operation_code)=lower(btrim(coalesce(p_target_hint,'')))
      order by r.operation_code
      limit 1;
      v_asset_found := found;
      if v_asset_found then v_candidate_code := v_target_operation.operation_code; end if;
    else
      select b.codigo_activo into v_candidate_code
    from public.v_lf_fuente_operativa_busqueda b
    where (v_type_hint is null or b.tipo_activo=v_type_hint)
      and (
        regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        or regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        or exists (
          select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
          where regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        )
      )
      order by b.codigo_activo limit 1;
      v_asset_found := found;
    end if;
  else
    -- Match complete registry identities only; never promote token similarity
    -- or keyword scores into a canonical asset identity.
    select coalesce(jsonb_agg(jsonb_build_object(
             'asset_code',x.codigo_activo,'asset_type',x.tipo_activo
           ) order by x.codigo_activo),'[]'::jsonb), count(*)::integer
      into v_exact_asset_candidates,v_exact_asset_count
    from (
      select distinct b.codigo_activo,b.tipo_activo
      from public.v_lf_fuente_operativa_busqueda b
      where (
          (length(btrim(b.codigo_activo))>=6
            and position(
              ' '||btrim(regexp_replace(translate(lower(b.codigo_activo),
                  'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
              in ' '||v_req||' ')>0)
          or ((v_type_hint is null or b.tipo_activo=v_type_hint)
              and (length(btrim(b.nombre_canonico))>=8
            and position(
              ' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),
                  'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
              in ' '||v_req||' ')>0))
          or ((v_type_hint is null or b.tipo_activo=v_type_hint)
              and exists (
            select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
            where length(btrim(al))>=8
              and position(
                ' '||btrim(regexp_replace(translate(lower(al),
                    'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
                in ' '||v_req||' ')>0
          ))
        )
    ) x;

    if v_exact_asset_count>1 then
      return jsonb_build_object(
        'router','ACT-0001','source','SUPABASE','status','BLOCKED',
        'asset_type',null,'action_code',null,'operation_code',null,
        'blocking_code','BLOCK_MULTIPLE_EXACT_TARGETS_NEED_SCOPE',
        'subject_binding_state','AMBIGUOUS',
        'subject_candidates',v_exact_asset_candidates,
        'semantic_handoff',public.lf_router_intent_handoff_v1(
          p_request_text,v_exact_asset_candidates,'CANONICAL_ASSET'),
        'semantic_gap_code','POSITIVE_NEGATIVE_TARGET_ROLES_UNATTESTED',
        'semantic_resolution_required',true,
        'request_sha256',encode(extensions.digest(
          convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
        'downstream_execution_allowed',false
      );
    elsif v_exact_asset_count=1 then
      v_candidate_code:=v_exact_asset_candidates->0->>'asset_code';
      v_asset_found:=true;
    end if;
  end if;

  if v_asset_found then
    if v_type_hint='OPERATION_CODE' then
      v_asset.codigo_activo := v_target_operation.operation_code;
      v_asset.nombre_canonico := v_target_operation.operation_code;
      v_asset.tipo_activo := 'OPERATION_CODE';
      v_asset.subtipo_activo := v_target_operation.operation_type;
      v_asset.estado_documental := v_target_operation.lifecycle_state_code;
      v_asset.estado_operativo := v_target_operation.status;
      v_asset.version := v_target_operation.version;
    else
      select a.* into v_asset from public.lf_activos a
      where a.codigo_activo=v_candidate_code and a.archived_at is null limit 1;
      if not found then
        return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_MASTER_ASSET_HYDRATION_FAILED','router','ACT-0001','asset_code',v_candidate_code);
      end if;
      v_type_hint := v_asset.tipo_activo;
    end if;
  end if;

  v_action := upper(nullif(btrim(coalesce(p_action_hint,'')),''));
  if v_action is null then
    if v_req ~ '(^| )(consulta|consultar|estado|metadata|existe)( |$)' then v_action:='ASSET_INSPECTION';
    elsif v_type_hint='REGLA_PANTALLA_RELATION' and v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|relacion|link)( |$)' then v_action:='REGLA_PANTALLA_LINK';
    elsif v_type_hint='CAPABILITY'
      and v_asset_found
      and v_asset.codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|realiza|realizar)( |$)'
      then v_action:='INPUT_GOVERNANCE_EXECUTION';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|continua|continuar|retoma|retomar)( |$)' then v_action:='STRATEGY_EXECUTION';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(cierra|cerrar|cierre|finaliza|finalizar)( |$)' then v_action:='STRATEGY_CLOSE';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then v_action:='STRATEGY_CREATE';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then v_action:='STRATEGY_UPDATE';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then v_action:='PROFILE_CREATE';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then v_action:='PROFILE_UPDATE';
    elsif v_type_hint='PERFIL' and v_asset_found then v_action:='PROFILE_EXECUTION';
    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; elsif v_type_hint='REGLA' then v_action:='REGLA_CREATE'; else v_action:='CREATE'; end if;
    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE'; elsif v_type_hint='REGLA' then v_action:='REGLA_UPDATE'; else v_action:='UPDATE'; end if;
    else v_action:='ASSET_INSPECTION'; end if;
  end if;

  -- Repository paths are working subjects, never profile/skill executors.
  -- Read only the exact governed checkpoint artifact declarations.
  if nullif(btrim(coalesce(p_target_hint,'')),'') is null
     and p_request_text ~ '[[:alnum:]_.-]+(/[[:alnum:]_.-]+)+[.][[:alnum:]_-]+'
  then
    v_artifact_discovery:=public.lf_router_declared_artifact_candidates_v1(
      p_request_text
    );
    v_discovery_count:=coalesce((v_artifact_discovery->>'match_count')::integer,0);
    return jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code',case
        when v_discovery_count=1 then 'BLOCK_ARTIFACT_CONSUMER_UNATTESTED'
        when v_discovery_count>1 then 'BLOCK_MULTIPLE_ARTIFACT_TARGETS'
        else 'BLOCK_EXACT_ARTIFACT_BINDING_UNRESOLVED' end,
      'asset_type',null,'subject_type','REPOSITORY_ARTIFACT',
      'action_code',v_action,'operation_code',null,
      'subject_binding_state',case when v_discovery_count=1 then 'RESOLVED'
        when v_discovery_count>1 then 'AMBIGUOUS' else 'UNRESOLVED' end,
      'subject_candidates',v_artifact_discovery->'matches',
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,v_artifact_discovery->'matches','REPOSITORY_ARTIFACT'),
      'subject_resolution_source','programacion.engineering_plan_units.action_specs_v1',
      'next_governance_entrypoint',case when v_discovery_count=1 then
        'programacion.fn_engineering_unit_bootstrap_v3' else null end,
      'executor_selection_state','NOT_SELECTED',
      'semantic_gap_code','EXECUTOR_AND_REQUEST_SCOPE_UNATTESTED',
      'semantic_resolution_required',true,
      'request_sha256',encode(extensions.digest(
        convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false
    );
  end if;

  -- Actor-role guard after canonical discovery, before operation resolution.
  -- A screen / subject change does not update a profile, skill or adapter.
  -- Lexical matches are evidence candidates, never execution authority.
  IF nullif(btrim(coalesce(p_target_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_asset_type_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_action_hint,'')),'') IS NULL
     AND (
       v_type_hint IN ('PERFIL','SKILL','ADAPTER')
       OR (
         v_type_hint is null
         and v_req ~ '(^| )(pantalla|screen)( |$)'
       )
     )
     AND v_req ~ '^(por favor )?(cambiar|cambia|modificar|modifica|actualizar|actualiza|corregir|corrige|ajustar|ajusta|editar|edita|reemplazar|reemplaza|renombrar|renombra)( |$)'
     AND NOT v_req ~ '(^| )(perfil|profile|skill|adapter)( |$)'
     AND NOT EXISTS (
       SELECT 1 FROM public.v_lf_fuente_operativa_busqueda b
       WHERE b.codigo_activo=v_asset.codigo_activo
         AND (
           position(' '||btrim(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
           OR position(' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
           OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
               WHERE length(btrim(al))>=8
                 AND position(' '||btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0)
         )
     )
  THEN
    SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.keyword_match_count DESC,c.asset_code),'[]'::jsonb)
      INTO v_executor_candidates
    FROM (
      SELECT b.codigo_activo AS asset_code, b.tipo_activo AS asset_type,
             b.estado_operativo AS operational_status,
             count(DISTINCT kw.keyword) AS keyword_match_count,
             jsonb_agg(DISTINCT kw.keyword) AS matching_keywords
      FROM public.v_lf_fuente_operativa_busqueda b
      CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw(keyword)
      WHERE b.tipo_activo IN ('PERFIL','SKILL')
        AND length(btrim(kw.keyword))>=3
        AND position(' '||btrim(regexp_replace(translate(lower(kw.keyword),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
      GROUP BY b.codigo_activo,b.tipo_activo,b.estado_operativo
      ORDER BY count(DISTINCT kw.keyword) DESC,b.codigo_activo
      LIMIT 5
    ) c;
    -- Subject discovery is not executor selection. Match canonical screen
    -- names as complete normalized phrases, not individual lexical keywords.
    SELECT count(*),
           coalesce(jsonb_agg(jsonb_build_object(
             'screen_code',p.codigo,
             'pantalla_id',p.id,
             'screen_name',p.nombre,
             'screen_state',p.estado,
             'module_code',p.module_code
           ) ORDER BY p.codigo),'[]'::jsonb)
      INTO v_screen_subject_count,v_screen_subjects
    FROM lf_ops.pantallas p
    WHERE p.activa
      AND length(btrim(p.nombre))>=8
      AND position(
        ' '||btrim(regexp_replace(
          translate(lower(p.nombre),'áéíóúüñ','aeiouun'),
          '[^a-z0-9_]+',' ','g'
        ))||' '
        IN ' '||v_req||' '
      )>0;

    RETURN jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_EXECUTOR_CAPABILITY_UNATTESTED',
      'asset_type',NULL,'action_code','UPDATE','operation_code',NULL,
      'subject_binding_state',case
        when v_screen_subject_count=1 then 'RESOLVED'
        when v_screen_subject_count>1 then 'AMBIGUOUS'
        else 'UNRESOLVED'
      end,
      'subject_candidates',v_screen_subjects,
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,v_screen_subjects,'CANONICAL_SCREEN'),
      'executor_selection_state','CANDIDATES_ONLY_NOT_AUTHORIZED',
      'executor_candidates',v_executor_candidates,
      'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'semantic_resolution_required',true,
      'semantic_gap_code','TARGET_VS_EXECUTOR_ROLE_UNATTESTED',
      'downstream_execution_allowed',false
    );
  END IF;

  -- Negative/exclusion expressions are a trigger for independent semantic
  -- resolution, NEVER a classifier or authority to accept/reject a target.
  -- This also applies when callers give explicit typed hints: hints cannot
  -- override the literal user's forbidden scope.
  if v_action <> 'ASSET_INSPECTION'
     and v_req ~ '(^| )(sin|no|excepto|excluye|excluir|excluyendo|excluido|excluida)( |$)'
  then
    return jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_SCOPE_SEMANTICS_UNATTESTED',
      'action_code',v_action,'asset_type',v_type_hint,
      'operation_code',null,
      'subject_binding_state',case when v_asset_found then 'CANDIDATE'
                                   else 'UNRESOLVED' end,
      'subject_candidates',case when v_asset_found then
        jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,
          'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,case when v_asset_found then
          jsonb_build_array(jsonb_build_object(
            'asset_code',v_asset.codigo_activo,
            'asset_type',v_asset.tipo_activo))
          else '[]'::jsonb end,'CANONICAL_ASSET'),
      'semantic_resolution_required',true,
      'semantic_gap_code','POSITIVE_NEGATIVE_SCOPE_NOT_BOUND',
      'request_sha256',encode(extensions.digest(
        convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'executor_selection_state','NOT_SELECTED',
      'downstream_execution_allowed',false
    );
  end if;

  -- Guard EVERY unstructured mutation before any operation can become READY.
  -- The inferred verb/type is ONLY a candidate; not independent intent or
  -- scope authority. Fully typed callers retain existing downstream gates.
  if v_action <> 'ASSET_INSPECTION'
     and (
       nullif(btrim(coalesce(p_target_hint,'')),'') is null
       or nullif(btrim(coalesce(p_action_hint,'')),'') is null
       or nullif(btrim(coalesce(p_asset_type_hint,'')),'') is null
     )
  then
    return jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED',
      'asset_type',null,'action_code',null,'operation_code',null,
      'candidate_asset_type',v_type_hint,
      'candidate_action_code',v_action,
      'subject_binding_state',case when v_asset_found then 'CANDIDATE'
                                   else 'UNRESOLVED' end,
      'subject_candidates',case when v_asset_found then
        jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,
          'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
      'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,
        case when v_asset_found then jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
        'CANONICAL_ASSET'),
      'semantic_gap_code','NATURAL_LANGUAGE_ACTION_SCOPE_NOT_ATTESTED',
      'semantic_resolution_required',true,
      'next_governance_entrypoint','GOVERNED_SEMANTIC_CONSUMER_REQUIRED',
      'request_sha256',encode(extensions.digest(
        convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false
    );
  end if;

  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE') and v_asset_found and v_target_norm='' then
    if not exists (
      select 1 from public.v_lf_fuente_operativa_busqueda b
      where b.codigo_activo=v_asset.codigo_activo
        and (
          position(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
          or position(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
          or exists (select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0)
        )
    ) then v_asset_found := false; end if;
  end if;

  -- ACT-0001 R5: lexical candidate discovery is not identity evidence.
  -- Fail closed for inferred updates and existing-target operations lacking identity
  -- mention. A governed semantic consumer may resolve a gap and resubmit
  -- explicit typed inputs; this SQL never manufactures semantic authority.
  if v_target_norm=''
     and nullif(btrim(coalesce(p_asset_type_hint,'')),'') is null
     and (
       v_action in ('UPDATE','PROFILE_UPDATE','SKILL_UPDATE','ADAPTER_UPDATE',
                    'REGLA_UPDATE','STRATEGY_UPDATE','APP_SHELL_UPDATE',
                    'RUNTIME_UPDATE')
       or (
         v_asset_found and exists (
           select 1 from public.lf_router_action_registry action_route
           where action_route.asset_type=v_type_hint
             and action_route.action_code=v_action
             and action_route.status='ACTIVE'
             and action_route.requires_existing_target
         )
       )
     )
  then
    if not v_asset_found or not exists (
      select 1
      from public.v_lf_fuente_operativa_busqueda b
      where b.codigo_activo=v_asset.codigo_activo
        and (
          position(
            ' '||btrim(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
            in ' '||v_req||' '
          )>0
          or position(
            ' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
            in ' '||v_req||' '
          )>0
          or exists (
            select 1
            from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
            where length(btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g')))>=8
              and btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g')) <> lower(b.tipo_activo)
              and position(
                ' '||btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' '
                in ' '||v_req||' '
              )>0
          )
        )
    ) then
      return jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED',
        'router','ACT-0001',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'candidate_asset_code',case when v_asset_found then v_asset.codigo_activo else null end,
        'semantic_gap_code','NON_DERIVABLE_TARGET_IDENTITY',
        'semantic_resolution_required',true,
        'downstream_execution_allowed',false
      );
    end if;
  end if;
  if v_type_hint is null then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED','router','ACT-0001','action_code',v_action);
  end if;

  select * into v_rule from public.lf_router_action_registry where asset_type=v_type_hint and action_code=v_action and status='ACTIVE';
  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_NOT_REGISTERED','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,'asset_code',case when v_asset_found then v_asset.codigo_activo else null end);
  end if;
  if v_rule.requires_existing_target and not v_asset_found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_NOT_FOUND','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action); end if;
  if v_rule.requires_missing_target and v_asset_found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_TARGET_ALREADY_EXISTS','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,'asset_code',v_asset.codigo_activo); end if;

  if v_rule.operation_resolution='NONE' then
    if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;
    return jsonb_build_object('status','READY_INSPECTION','router','ACT-0001','source','SUPABASE','discovery_source',case when v_type_hint='OPERATION_CODE' then 'public.lf_operation_registry' else 'public.v_lf_fuente_operativa_busqueda' end,'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,'asset_type',v_type_hint,'action_code',v_action,'operation_code',null,'adapters',v_adapters,'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'));
  end if;

  select * into v_operation from public.lf_operation_registry where operation_code=v_rule.operation_code;
  if not found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_REGISTRY_MISSING','router','ACT-0001','operation_code',v_rule.operation_code); end if;
  if v_operation.applies_to_asset_type is not null and v_operation.applies_to_asset_type<>v_type_hint then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_ASSET_TYPE_MISMATCH','router','ACT-0001','asset_type',v_type_hint,'operation_code',v_operation.operation_code,'applies_to_asset_type',v_operation.applies_to_asset_type); end if;

  if exists (
    select 1 from public.lf_test_requirement_bindings b
    where b.subject_type='OPERATION' and b.subject_code=v_operation.operation_code
      and b.status='ACTIVE' and b.required and b.effective_from<=clock_timestamp()
  ) then
    if v_operation.lifecycle_state_code is distinct from public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION') then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_NOT_OPERATIONAL','router','ACT-0001','operation_code',v_operation.operation_code,'operation_lifecycle_state',v_operation.lifecycle_state_code);
    end if;
    if v_operation.operation_code<>'EJECUCION_ESTRATEGIA_LF'
       and not public.lf_qualification_current_v1('OPERATION',v_operation.operation_code,public.lf_operation_revision_sha256_v1(v_operation.operation_code)) then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_QUALIFICATION_REQUIRED','router','ACT-0001','operation_code',v_operation.operation_code,'operation_revision_sha256',public.lf_operation_revision_sha256_v1(v_operation.operation_code));
    end if;
  end if;

  -- Strategy26 G-A: the profile asset itself must be runtime-authorized before
  -- EJECUCION_PERFIL_LF can proceed. Runtime capability is not authority.
  if v_operation.operation_code = 'EJECUCION_PERFIL_LF' and v_asset_found then
    if nullif(btrim(coalesce(v_asset.runtime_estado, '')), '') is null
       or nullif(btrim(coalesce(v_asset.estado_operativo, '')), '') is null
       or nullif(btrim(coalesce(v_asset.estado_documental, '')), '') is null then
      return jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_STATE_INCOMPLETE',
        'router','ACT-0001',
        'source','SUPABASE',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'operation_code',v_operation.operation_code,
        'asset_code',v_asset.codigo_activo,
        'downstream_execution_allowed',false
      );
    end if;

    if upper(v_asset.runtime_estado) in ('NO_HABILITADO','NO_APLICA')
       or upper(v_asset.estado_operativo) in ('BLOQUEADO','ELIMINADO')
       or upper(v_asset.estado_documental) = 'ELIMINADO' then
      return jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED',
        'router','ACT-0001',
        'source','SUPABASE',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'operation_code',v_operation.operation_code,
        'asset_code',v_asset.codigo_activo,
        'profile_state',jsonb_build_object(
          'estado_documental',v_asset.estado_documental,
          'estado_operativo',v_asset.estado_operativo,
          'runtime_estado',v_asset.runtime_estado,
          'impacto_automatico',v_asset.impacto_automatico
        ),
        'downstream_execution_allowed',false
      );
    end if;
  end if;

  select count(*), coalesce(jsonb_agg(jsonb_build_array(c.contract_code,c.contract_sha) order by c.contract_code),'[]'::jsonb)
    into v_contract_count,v_contract_refs
  from public.lf_operation_contracts c
  where c.operation_code=v_operation.operation_code and c.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_contract_count=0 then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ACTIVE_CONTRACT_MISSING','router','ACT-0001','operation_code',v_operation.operation_code); end if;

  select count(*) into v_step_count from public.lf_operation_step_contracts s
  where s.operation_code=v_operation.operation_code and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_step_count=0 then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ACTIVE_STEPS_MISSING','router','ACT-0001','operation_code',v_operation.operation_code); end if;

  select jsonb_build_object(
      'step_id',s.step_id,'execution_order',s.execution_order,'contract_code',s.contract_code,
      'blocking_code',s.blocking_code,'status',s.status,'resolver_ref',s.resolver_ref,
      'required_evidence_keys',s.required_evidence_keys,'next_if_pass',s.next_if_pass,'next_if_blocked',s.next_if_blocked
    ) into v_next_step
  from public.lf_operation_step_contracts s
  where s.operation_code=v_operation.operation_code and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
  order by coalesce(s.execution_order,s.step_order),s.step_id limit 1;

  select count(*) filter (where p.required) into v_required_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));

  select count(*) filter (where p.required and p.policy_sha is not null) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));
  if v_required_policy_count>v_resolved_policy_count then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_REQUIRED_POLICY_MISSING','router','ACT-0001','operation_code',v_operation.operation_code,'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count);
  end if;

  select coalesce(jsonb_agg(jsonb_build_array(p.policy_code,p.policy_version,p.policy_sha) order by p.policy_role,p.policy_code),'[]'::jsonb) into v_policy_refs
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));

  if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;

  if exists (select 1 from jsonb_array_elements(v_adapters) e(value) left join public.v_lf_fuente_operativa f on f.codigo_activo=e.value->>'adapter_code' where lower(coalesce(e.value#>>'{adapter_metadata,router_discoverable}','false'))='true' and (lower(coalesce(e.value#>>'{adapter_metadata,runtime_enabled}','false'))<>'true' or f.codigo_activo is null or upper(coalesce(f.runtime_estado,''))='NO_HABILITADO')) then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ADAPTER_RUNTIME_NOT_AUTHORIZED','router','ACT-0001','source','SUPABASE','asset_type',v_type_hint,'action_code',v_action,'operation_code',v_operation.operation_code,'adapters',v_adapters,'adapter_runtime_authority_source','public.v_lf_fuente_operativa','downstream_execution_allowed',false);
  end if;

  if jsonb_array_length(v_adapters)>0 then
    v_input_governance := programacion.fn_lf_router_input_governance_resolve_v1(
      p_request_text,
      v_adapters,
      case when v_operation.operation_code = 'EJECUCION_PERFIL_LF' then 'CONTEXT_PACK' else 'STORY_CREATOR' end
    );

    -- PROFILE_EXECUTION is strictly read-only. If the reviewed subject is not a canonical screen,
    -- keep the same Router/Input Governance path but switch governance to advisory artifact mode.
    -- Exact artifact identity remains mandatory downstream; this does not create or promote canon.
    if v_operation.operation_code = 'EJECUCION_PERFIL_LF'
       and v_operation.status = 'PRODUCCION_CONTROLADA_READ_ONLY'
       and coalesce(v_input_governance->>'blocking_code','') = 'BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED' then
      v_input_governance := jsonb_build_object(
        'applicable',true,
        'status','ADVISORY_READ_ONLY',
        'blocking_code',null,
        'decision','ADVISORY',
        'continuation_allowed',true,
        'subject_mode','NON_CANONICAL_ARTIFACT',
        'required_by_adapters',coalesce(v_input_governance->'required_by_adapters','[]'::jsonb),
        'required_artifact_binding',jsonb_build_array('artifact_ref','artifact_sha256','dimensions'),
        'constraints',jsonb_build_object(
          'operation_must_equal','EJECUCION_PERFIL_LF',
          'read_only',true,
          'no_write',true,
          'no_promotion',true,
          'canonical_registration_required',false,
          'artifact_binding_required_before_profile_execution',true
        ),
        'resume_via','EJECUCION_PERFIL_LF/input_validate'
      );
    end if;

    if v_input_governance is null or not (v_input_governance ? 'applicable') then
      v_input_governance := jsonb_build_object('applicable',true,'status','BLOCKED','blocking_code','BLOCK_INPUT_GOVERNANCE_RESOLUTION_INVALID','decision','BLOCKED','continuation_allowed',false);
    end if;
    if coalesce((v_input_governance->>'applicable')::boolean,false) then
      if not coalesce((v_input_governance->>'continuation_allowed')::boolean,false) then
        return jsonb_build_object(
          'status',v_input_governance->>'status','blocking_code',v_input_governance->>'blocking_code','router','ACT-0001','source','SUPABASE',
          'discovery_source',case when v_type_hint='OPERATION_CODE' then 'public.lf_operation_registry' else 'public.v_lf_fuente_operativa_busqueda' end,
          'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,
          'asset_type',v_type_hint,'action_code',v_action,'operation_code',v_operation.operation_code,
          'operation_status',v_operation.status,'operation_lifecycle_state',v_operation.lifecycle_state_code,'operation_applies_to_asset_type',v_operation.applies_to_asset_type,
          'contract_count',v_contract_count,'contract_refs',v_contract_refs,'step_count',v_step_count,'next_step',v_next_step,
          'next_step_ref',v_operation.operation_code||'/'||(v_next_step->>'step_id'),
          'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count,'policy_refs',v_policy_refs,
          'policy_stale_guard','public.lf_operation_policy_snapshot_guard_v1','adapters',v_adapters,
          'input_governance',v_input_governance,'downstream_execution_allowed',false,
          'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'),
          'composition_order',jsonb_build_array('SHELL','PROFILE','ADAPTER','POLICY_AND_CONTRACT_GATES')
        );
      end if;
    else
      v_input_governance := null;
    end if;
  end if;

  return jsonb_build_object(
    'status','READY_TO_EXECUTE','router','ACT-0001','source','SUPABASE','discovery_source',case when v_type_hint='OPERATION_CODE' then 'public.lf_operation_registry' else 'public.v_lf_fuente_operativa_busqueda' end,
    'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,
    'asset_type',v_type_hint,'action_code',v_action,'operation_code',v_operation.operation_code,
    'operation_status',v_operation.status,'operation_lifecycle_state',v_operation.lifecycle_state_code,'operation_applies_to_asset_type',v_operation.applies_to_asset_type,
    'contract_count',v_contract_count,'contract_refs',v_contract_refs,
    'step_count',v_step_count,'next_step',v_next_step,'next_step_ref',v_operation.operation_code||'/'||(v_next_step->>'step_id'),
    'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count,'policy_refs',v_policy_refs,
    'policy_stale_guard','public.lf_operation_policy_snapshot_guard_v1','adapters',v_adapters,
    'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'),
    'composition_order',jsonb_build_array('SHELL','PROFILE','ADAPTER','POLICY_AND_CONTRACT_GATES'),
    'downstream_execution_allowed',true
  ) || case when v_input_governance is null then '{}'::jsonb else jsonb_build_object('input_governance',v_input_governance) end;
end;
$function$;

-- Apply-time regression probes: fail the migration transaction on false READY.
do $intent_tests$
declare
  v jsonb;
begin
  v:=public.lf_router_resolve_v1('Crear una regla y una skill');
  if v->>'blocking_code' is distinct from
      'BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED'
     or v->>'downstream_execution_allowed' is distinct from 'false'
  then
    raise exception 'ROUTER_MULTIOBJECT_FALSE_READY:%',v;
  end if;

  v:=public.lf_router_resolve_v1(
    'Actualizar ACT-0053 únicamente si todas sus pruebas pasan'
  );
  if v->>'blocking_code' is distinct from
      'BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED'
     or v->>'downstream_execution_allowed' is distinct from 'false'
  then
    raise exception 'ROUTER_CONDITIONAL_FALSE_READY:%',v;
  end if;

  v:=public.lf_router_resolve_v1(
    'Actualizar ACT-0053 dejando otros archivos intactos'
  );
  if v->>'blocking_code' is distinct from
      'BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED'
     or v->>'downstream_execution_allowed' is distinct from 'false'
  then
    raise exception 'ROUTER_UNEXPRESSED_EXCLUSION_FALSE_READY:%',v;
  end if;

  v:=public.lf_router_resolve_v1(
    'Actualizar exclusivamente el archivo sandbox/lf_contract_gate_test/engineering_checkpoints/m10_7/no_false_pass.py sin modificar runtime'
  );
  if v->>'blocking_code' is distinct from
      'BLOCK_ARTIFACT_CONSUMER_UNATTESTED'
     or v->>'downstream_execution_allowed' is distinct from 'false'
  then
    raise exception 'ROUTER_EXACT_ARTIFACT_REGRESSED:%',v;
  end if;

  v:=public.lf_router_resolve_v1(
    'Inspeccionar el perfil UI Architect para inventario de arquitectura',
    'PERFIL-UI-ARCHITECT','ASSET_INSPECTION','PERFIL','DIRECT'
  );
  if v->>'status' is distinct from 'READY_INSPECTION'
  then
    raise exception 'ROUTER_POSITIVE_INSPECTION_REGRESSED:%',v;
  end if;
end;
$intent_tests$;


insert into public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
  validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,
  source_ref
)
select gen_random_uuid(),
 'LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002',
 'ROUTER','Unstructured multi-object and conditional updates returned READY',
 'ACT-0001 converted inferred natural language action into READY_TO_EXECUTE without independent scope or binding.',
 'Full target identity is not sufficient to prove an action, a conditional clause, or negative scopes; multi-object create lost a second requested object.',
 'R5_EROSION_PROCESO',
 'For unstructured mutations, return candidate-only semantics and preserve the verbatim request; continue only via independently governed semantic consumer and pre-write admission.',
 'Live negative probes MUST not return READY_TO_EXECUTE. Structured read-only inspections continue to work.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'LF_ROUTER_ACT0001_TRANSVERSAL_INTENT','ACTIVO',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2867'
where not exists(
 select 1 from public.lf_error_knowledge
 where codigo='LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002'
);

-- Reconcile the previous source reference after Train retimestamp.
-- PR URL is stable across canonical migration renumbering.
update public.lf_error_knowledge
   set source_ref='https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2864'
 where codigo='LF-ROUTER-ACT0001-LEXICAL-ARTIFACT-MISIDENTITY-20261017-001'
   and source_ref='github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261017033000_lf_router_exact_identity_structured_discovery_v1.sql';

commit;
