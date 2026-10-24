-- ACT-0001: resolve Product subject first, then load its aggregate canonical context.
-- target_type remains a semantic hint/consistency check and never selects a search table.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_product_context_v1(
  p_request_text text,
  p_scope jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','lf_design','extensions'
AS $pc$
DECLARE
  v_rs jsonb;
  v_subject jsonb;
  v_subject_count integer := 0;
  v_app_shell_code text;
  v_module_code text;
  v_screen_code text;
  v_screen_name text;
  v_screen_status text;
  v_screen_version text;
  v_contract_version text;
  v_contract jsonb;
  v_elements jsonb := '[]'::jsonb;
  v_full jsonb;
  v_sections jsonb := '[]'::jsonb;
  v_hint text;
  v_scope_hint text;
  v_exact_screen_matches integer := 0;
  v_resolution_method text := 'ROUTER_SUBJECT';
BEGIN
  IF btrim(coalesce(p_request_text,''))='' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status','INVALID_REQUEST',
      'downstream_execution_allowed',false
    );
  END IF;

  v_rs := public.lf_router_resolve_v1(p_request_text);
  v_subject_count := jsonb_array_length(coalesce(v_rs->'subject_candidates','[]'::jsonb));

  v_scope_hint := nullif(btrim(coalesce(p_scope->>'target_hint','')),'');

  IF v_rs->>'subject_binding_state'='RESOLVED'
     AND v_subject_count=1
     AND nullif(v_rs#>>'{subject_candidates,0,screen_code}','') IS NOT NULL THEN
    v_subject := v_rs->'subject_candidates'->0;
  ELSE
    SELECT count(*)
      INTO v_exact_screen_matches
    FROM lf_ops.pantallas p
    WHERE (v_scope_hint IS NOT NULL
           AND (lower(p.codigo)=lower(v_scope_hint) OR lower(p.nombre)=lower(v_scope_hint)))
       OR lower(p_request_text) LIKE '%' || lower(p.codigo) || '%';

    IF v_exact_screen_matches=1 THEN
      SELECT jsonb_build_object(
          'pantalla_id',p.id,
          'screen_code',p.codigo,
          'screen_name',p.nombre,
          'source','EXACT_SCREEN_CODE_OR_SCOPE_HINT'
        )
        INTO v_subject
      FROM lf_ops.pantallas p
      WHERE (v_scope_hint IS NOT NULL
             AND (lower(p.codigo)=lower(v_scope_hint) OR lower(p.nombre)=lower(v_scope_hint)))
         OR lower(p_request_text) LIKE '%' || lower(p.codigo) || '%'
      LIMIT 1;
      v_resolution_method := 'EXACT_SCREEN_CODE_OR_SCOPE_HINT';
    ELSE
      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
        'status',CASE
          WHEN v_subject_count>1 OR v_exact_screen_matches>1 THEN 'AMBIGUOUS_SUBJECT'
          ELSE 'SUBJECT_NOT_RESOLVED'
        END,
        'router_resolve',jsonb_build_object(
          'status',v_rs->>'status',
          'blocking_code',v_rs->>'blocking_code',
          'subject_binding_state',v_rs->>'subject_binding_state',
          'subject_candidates',coalesce(v_rs->'subject_candidates','[]'::jsonb)
        ),
        'exact_screen_matches',v_exact_screen_matches,
        'target_type_hint',upper(nullif(coalesce(p_scope->>'target_type',''),'')),
        'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
        'downstream_execution_allowed',false
      );
    END IF;
  END IF;
  IF nullif(v_subject->>'screen_code','') IS NULL
     OR nullif(v_subject->>'pantalla_id','') IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status','AGGREGATE_CONTEXT_NOT_AVAILABLE_FOR_SUBJECT',
      'subject',v_subject,
      'target_type_hint',upper(nullif(coalesce(p_scope->>'target_type',''),'')),
      'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
      'downstream_execution_allowed',false
    );
  END IF;

  SELECT s.app_shell_code,m.module_code,p.codigo,p.nombre,p.estado,p.version
    INTO v_app_shell_code,v_module_code,v_screen_code,v_screen_name,v_screen_status,v_screen_version
  FROM lf_ops.pantallas p
  JOIN lf_ops.modulos m ON m.module_id=p.module_id
  JOIN lf_ops.app_shells s ON s.app_shell_id=m.app_shell_id
  WHERE p.id=(v_subject->>'pantalla_id')::integer
    AND p.codigo=v_subject->>'screen_code'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status','CANONICAL_SUBJECT_NOT_FOUND',
      'subject',v_subject,
      'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
      'downstream_execution_allowed',false
    );
  END IF;

  SELECT sc.contract_version,sc.contract
    INTO v_contract_version,v_contract
  FROM lf_ops.fn_screen_contract_v1(
    v_app_shell_code,v_module_code,v_screen_code
  ) sc
  LIMIT 1;

  IF v_contract IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status','CANONICAL_CONTEXT_NOT_FOUND',
      'subject_ref',v_screen_code,
      'resolved_target_type','PANTALLA',
      'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
      'downstream_execution_allowed',false
    );
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'element_id',e.element_id,
      'element_code',e.element_code,
      'element_role',e.element_role,
      'context_key',e.context_key,
      'label_visible',e.label_visible,
      'component_token_id',e.component_token_id,
      'component_token_code',ct.component_token_code,
      'component_name',ct.component_name,
      'component_state',ct.component_state,
      'component_token_bindings',ct.token_bindings,
      'semantic_binding_status',e.semantic_binding_status,
      'required_for_implementation',e.required_for_implementation,
      'source_refs',e.source_refs,
      'status',e.status
    ) ORDER BY e.element_id),'[]'::jsonb)
    INTO v_elements
  FROM lf_ops.pantalla_elementos e
  LEFT JOIN lf_design.component_tokens ct
    ON ct.component_token_id=e.component_token_id
  WHERE e.pantalla_id=(v_subject->>'pantalla_id')::integer;

  v_full := v_contract || jsonb_build_object('elements',v_elements);
  SELECT coalesce(jsonb_agg(t.section_key ORDER BY t.section_key),'[]'::jsonb)
    INTO v_sections
  FROM jsonb_object_keys(v_full) AS t(section_key);

  v_hint := upper(nullif(coalesce(p_scope->>'target_type',''),''));

  RETURN jsonb_build_object(
    'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
    'status','RESOLVED',
    'subject_ref',v_screen_code,
    'subject_name',v_screen_name,
    'subject_resolution_method',v_resolution_method,
    'resolved_target_type','PANTALLA',
    'screen_status',v_screen_status,
    'screen_version',v_screen_version,
    'target_type_hint',v_hint,
    'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
    'target_type_hint_consistency',CASE
      WHEN v_hint IS NULL OR v_hint='PANTALLA' THEN 'CONSISTENT'
      ELSE 'MISMATCH_HINT_ONLY'
    END,
    'canonical_context_source',jsonb_build_object(
      'function','lf_ops.fn_screen_contract_v1',
      'app_shell_code',v_app_shell_code,
      'module_code',v_module_code,
      'screen_code',v_screen_code,
      'contract_version',v_contract_version,
      'augmented_with','lf_ops.pantalla_elementos'
    ),
    'context_sections',v_sections,
    'context_summary',jsonb_build_object(
      'elements',jsonb_array_length(coalesce(v_full->'elements','[]'::jsonb)),
      'fields',jsonb_array_length(coalesce(v_full->'fields','[]'::jsonb)),
      'rules',jsonb_array_length(coalesce(v_full->'rules','[]'::jsonb)),
      'errors',jsonb_array_length(coalesce(v_full->'errors','[]'::jsonb)),
      'profiles',jsonb_array_length(coalesce(v_full->'profiles','[]'::jsonb)),
      'analytics',jsonb_array_length(coalesce(v_full->'analytics','[]'::jsonb))
    ),
    'product_context',v_full,
    'downstream_execution_allowed',false
  );
END
$pc$;

REVOKE ALL ON FUNCTION public.lf_router_product_context_v1(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_router_product_context_v1(text,jsonb) TO service_role;

COMMENT ON FUNCTION public.lf_router_product_context_v1(text,jsonb) IS
'ACT-0001 internal read-only Product context loader. Resolves canonical subject first, then loads aggregate screen context. Stage1 target_type is hint/consistency only, never a search selector or authority.';


CREATE OR REPLACE FUNCTION public.lf_router_product_cycle_v1(
  p_event jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog','public'
AS $cy$
DECLARE
  v_schema text := nullif(p_event->>'schema_version','');
  v_status text;
  v_subject text := nullif(p_event->>'subject_ref','');
  v_current boolean := coalesce((p_event->>'currentness_verified')::boolean,false);
  v_impl boolean := coalesce((p_event->>'implementation_required')::boolean,false);
BEGIN
  IF v_schema='LF_PRODUCT_STRUCTURE_ASSESSMENT_V1' THEN
    v_status := p_event->>'structure_status';

    IF v_status IS NULL OR v_status NOT IN ('FOUND_CANONICAL','FOUND_NON_CANONICAL','STRUCTURAL_GAP','NOT_FOUND') THEN
      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
        'paso','INVALID_PRODUCT_STRUCTURE_ASSESSMENT',
        'subject_ref',v_subject,
        'downstream_execution_allowed',false
      );
    END IF;

    IF v_status='FOUND_CANONICAL' THEN
      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
        'paso','PRODUCTO_VERIFICAR_O_ACTUALIZAR_DEFINICION',
        'canal_siguiente','PRODUCTO',
        'subject_ref',v_subject,
        'structure_status',v_status,
        'return_to_router_required',true,
        'next_contract','LF_PRODUCT_CANONICALIZATION_RESULT_V1',
        'downstream_execution_allowed',false
      );
    END IF;

    IF v_status IN ('FOUND_NON_CANONICAL','STRUCTURAL_GAP') THEN
      IF coalesce((p_event->>'normalization_required')::boolean,false) IS NOT TRUE
         OR p_event->'expected_canonical_location' IS NULL
         OR jsonb_array_length(coalesce(p_event->'observed_locations','[]'::jsonb))=0 THEN
        RETURN jsonb_build_object(
          'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
          'paso','INVALID_PRODUCT_STRUCTURE_ASSESSMENT',
          'subject_ref',v_subject,
          'reason','STRUCTURAL_FINDING_REQUIRES_OBSERVED_LOCATION_EXPECTED_LOCATION_AND_NORMALIZATION',
          'downstream_execution_allowed',false
        );
      END IF;

      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
        'paso','PROGRAMACION_REPARACION_ESTRUCTURAL_REQUERIDA',
        'canal_siguiente','PROGRAMACION',
        'subject_ref',v_subject,
        'structure_status',v_status,
        'repair_scope','STRUCTURE_ONLY_NO_FUNCTIONAL_TRUTH',
        'functional_truth_write_allowed',false,
        'programming_analysis_contract','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
        'programming_entry_contract','PROGRAMMING_ENTRY_CONTRACT_V1',
        'executor_selection','CAPABILITY_SELECTOR',
        'if_no_compatible_capability','CAPABILITY_GAP',
        'return_channel_after_repair','PRODUCTO',
        'return_contract','LF_PRODUCT_STRUCTURAL_REPAIR_RESULT_V1',
        'implementation_after_repair_requires_product_currentness',true,
        'downstream_execution_allowed',false
      );
    END IF;

    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
      'paso','PRODUCTO_PROFUNDIZAR_EVIDENCIA',
      'canal_siguiente','PRODUCTO',
      'subject_ref',v_subject,
      'structure_status',v_status,
      'programming_allowed',false,
      'return_to_router_required',true,
      'downstream_execution_allowed',false
    );
  END IF;

  IF v_schema='LF_PRODUCT_STRUCTURAL_REPAIR_RESULT_V1' THEN
    v_status := p_event->>'repair_status';

    IF v_status='REPAIRED' THEN
      IF p_event->'canonical_structure_ref' IS NULL
         OR jsonb_array_length(coalesce(p_event->'repair_evidence_refs','[]'::jsonb))=0 THEN
        RETURN jsonb_build_object(
          'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
          'paso','REPARACION_ESTRUCTURAL_EVIDENCIA_INSUFICIENTE',
          'subject_ref',v_subject,
          'downstream_execution_allowed',false
        );
      END IF;

      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
        'paso','PRODUCTO_REVALIDACION_POST_REPARACION',
        'canal_siguiente','PRODUCTO',
        'subject_ref',v_subject,
        'canonical_structure_ref',p_event->'canonical_structure_ref',
        'repair_evidence_refs',p_event->'repair_evidence_refs',
        'functional_truth_write_allowed_by_repair',false,
        'next_contract','LF_PRODUCT_CANONICALIZATION_RESULT_V1',
        'downstream_execution_allowed',false
      );
    ELSIF v_status='CAPABILITY_GAP' THEN
      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
        'paso','CAPABILITY_GAP',
        'subject_ref',v_subject,
        'required_capability',p_event->'required_capability',
        'downstream_execution_allowed',false
      );
    ELSE
      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
        'paso','REPARACION_ESTRUCTURAL_BLOQUEADA',
        'subject_ref',v_subject,
        'repair_status',v_status,
        'downstream_execution_allowed',false
      );
    END IF;
  END IF;

  IF v_schema='LF_PRODUCT_CANONICALIZATION_RESULT_V1' THEN
    v_status := p_event->>'canonical_status';

    IF v_status NOT IN ('CANONICAL_CURRENT','CANONICAL_UPDATED')
       OR v_current IS NOT TRUE
       OR p_event->'canonical_definition_ref' IS NULL THEN
      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
        'paso','PRODUCTO_CURRENTNESS_PENDIENTE',
        'canal_siguiente','PRODUCTO',
        'subject_ref',v_subject,
        'canonical_status',v_status,
        'currentness_verified',v_current,
        'downstream_execution_allowed',false
      );
    END IF;

    IF v_impl IS TRUE THEN
      RETURN jsonb_build_object(
        'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
        'paso','PROGRAMACION_PRECHECK_DEFINICION',
        'canal_siguiente','PROGRAMACION',
        'subject_ref',v_subject,
        'canonical_definition_ref',p_event->'canonical_definition_ref',
        'currentness_verified',true,
        'programming_entry_contract','PROGRAMMING_ENTRY_CONTRACT_V1',
        'upstream_required','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
        'downstream_execution_allowed',false
      );
    END IF;

    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
      'paso','PRODUCTO_CERRADO_SIN_IMPLEMENTACION',
      'canal_siguiente',null,
      'subject_ref',v_subject,
      'currentness_verified',true,
      'downstream_execution_allowed',false
    );
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_ROUTER_PRODUCT_CYCLE_V1',
    'paso','INVALID_PRODUCT_CYCLE_EVENT',
    'downstream_execution_allowed',false
  );
END
$cy$;

REVOKE ALL ON FUNCTION public.lf_router_product_cycle_v1(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_product_cycle_v1(jsonb) TO service_role;

COMMENT ON FUNCTION public.lf_router_product_cycle_v1(jsonb) IS
'ACT-0001 Product structural loop. Structural repair may create/normalize the technical container only; after REPAIRED the flow must return to PRODUCTO to establish/verify functional truth before any implementation.';

CREATE OR REPLACE FUNCTION public.lf_router_route_v1(
  p_stage1 jsonb,
  p_caller jsonb DEFAULT '{}'::jsonb,
  p_nivel2_consentido boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $f$
DECLARE
  v_rs jsonb;
  v jsonb;
  v_formas text[];
  v_hint text;
  v_cands jsonb;
  v_n int;
  v_l2 jsonb;
  v_d jsonb;
  v_schema text;
  v_channel text;
  v_business text;
  v_scope jsonb;
  v_transversal text;
  v_is_v2 boolean := false;
  v_base jsonb;
  v_pc jsonb;
BEGIN
  v_schema := p_stage1->>'schema_version';
  v_is_v2 := v_schema='LF_ROUTER_STAGE1_V2';

  IF v_is_v2 THEN
    v := public.lf_router_stage1_validate_v2(p_stage1);
  ELSE
    v := public.lf_router_stage1_validate_v1(p_stage1);
  END IF;

  v_base := jsonb_build_object(
    'schema_version','LF_ROUTER_ROUTE_V1',
    'router','ACT-0001',
    'stage1_schema_version',v_schema,
    'downstream_execution_allowed',false
  );

  IF (v->>'valid')::boolean IS NOT TRUE THEN
    RETURN v_base || jsonb_build_object(
      'paso',CASE WHEN v_is_v2 THEN 'INVALID_STAGE1_V2' ELSE 'INVALID_STAGE1' END,
      'codigos',v->'codes',
      'motivo_es','La salida de la etapa 1 no cumple el contrato.',
      'siguiente_paso_es','Rehacer la etapa 1 corrigiendo los codigos indicados.'
    );
  END IF;

  IF (p_stage1->>'es_operacion')::boolean IS FALSE THEN
    RETURN v_base || jsonb_build_object(
      'paso','DIRECT_ANSWER',
      'motivo_es','No es una operacion: se responde sin inventario.',
      'siguiente_paso_es','Responder directamente al usuario.'
    );
  END IF;

  IF (p_stage1->>'ambiguo')::boolean IS TRUE THEN
    RETURN v_base || jsonb_build_object(
      'paso','ASK_USER',
      'pregunta_usuario',p_stage1->'pregunta_usuario',
      'alternativas',p_stage1->'alternativas',
      'motivo_es','La solicitud tiene mas de una lectura posible.',
      'siguiente_paso_es','Hacer esa unica pregunta y repetir la etapa 1.'
    );
  END IF;

  IF v_is_v2 THEN
    v_channel := nullif(p_stage1->>'canal_candidato','');
    v_business := nullif(p_stage1->>'negocio_codigo','');
    v_scope := p_stage1->'alcance';
    v_transversal := nullif(p_stage1->>'ruta_transversal','');

    v_base := v_base || jsonb_build_object(
      'canal_candidato',v_channel,
      'negocio_codigo',v_business,
      'alcance',v_scope,
      'ruta_transversal',v_transversal
    );

    IF jsonb_array_length(coalesce(p_stage1->'negocios_afectados','[]'::jsonb))>0 THEN
      RETURN v_base || jsonb_build_object(
        'paso','MULTINEGOCIO_PENDIENTE',
        'negocios_afectados',p_stage1->'negocios_afectados',
        'motivo_es','La fase actual esta cerrada a LF.',
        'siguiente_paso_es','Resolver autoridad por negocio antes de habilitar una ruta transversal.'
      );
    END IF;

    IF v_business IS DISTINCT FROM 'LF' THEN
      RETURN v_base || jsonb_build_object(
        'paso','NEGOCIO_NO_HABILITADO',
        'motivo_es','La fase actual del Router atiende exclusivamente LF.',
        'siguiente_paso_es','No despachar; otros negocios se habilitan en una fase separada.'
      );
    END IF;

    IF v_transversal='GESTION_ACTIVOS_IA' THEN
      v_rs := public.lf_router_resolve_v1(p_stage1->>'texto_original');
      RETURN v_base || jsonb_build_object(
        'paso','RUTA_TRANSVERSAL_GESTION_ACTIVOS_IA',
        'router_resolve',v_rs,
        'motivo_es','Gestionar el propio perfil o skill es una ruta transversal, no un cuarto canal.',
        'siguiente_paso_es','Seguir la operacion gobernada exacta que determine ACT-0001.'
      );
    END IF;

    IF v_channel='PROGRAMACION' THEN
      RETURN v_base || jsonb_build_object(
        'paso','PROGRAMACION_PRECHECK_DEFINICION',
        'precondicion_requerida','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
        'si_definicion_falta_o_difiere','PRODUCTO_PRIMERO',
        'si_definicion_vigente','PROGRAMACION_ADMISION_REQUERIDA',
        'contrato_entrada_despues_precheck','PROGRAMMING_ENTRY_CONTRACT_V1',
        'upstream_requerido_despues_precheck','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
        'alcance_requiere_ready',v_scope IS NOT NULL,
        'motivo_es','Antes de Programacion se verifica la definicion funcional canonica. Si falta o difiere, Producto la corrige primero; si coincide, continua la admision tecnica.',
        'siguiente_paso_es','Verificar la fuente canonica y su currentness; solo con definicion vigente continuar a PG-01.'
      );
    END IF;

    IF v_channel='OPERACIONES' THEN
      RETURN v_base || jsonb_build_object(
        'paso','OPERACIONES_CAPACIDAD_REQUERIDA',
        'capability_hint_candidato',nullif(p_stage1->>'capability_hint',''),
        'capability_hint_autoridad','CANDIDATE_ONLY',
        'alcance_requiere_autorizacion',v_scope IS NOT NULL,
        'motivo_es','Operaciones solo usa capacidades existentes y autorizadas para actor y alcance.',
        'siguiente_paso_es','Resolver una capacidad ACTIVE y su identidad/tenant/alcance; si no existe, devolver brecha.'
      );
    END IF;

    IF v_channel='PRODUCTO' THEN
      v_pc := public.lf_router_product_context_v1(
        p_stage1->>'texto_original',
        v_scope
      );

      IF v_pc->>'status'='RESOLVED' THEN
        RETURN v_base || jsonb_build_object(
          'paso','PRODUCTO_CONTEXTO_CANONICO',
          'contexto_producto',v_pc-'product_context',
          'target_type_uso','HINT_ONLY_NOT_SEARCH_SELECTOR',
          'clasificacion_pendiente','PRODUCT_STRUCTURE_ASSESSMENT',
          'product_profile_hint',jsonb_build_object(
            'codigo_activo','PERFIL-PRODUCT-DIRECTOR-LF',
            'authority','CANDIDATE_ONLY',
            'mode','READ_ONLY',
            'selection_must_be_revalidated_by_router',true
          ),
          'assessment_contract',jsonb_build_object(
            'schema_version','LF_PRODUCT_STRUCTURE_ASSESSMENT_V1',
            'allowed_structure_status',jsonb_build_array(
              'FOUND_CANONICAL','FOUND_NON_CANONICAL','STRUCTURAL_GAP','NOT_FOUND'
            ),
            'required_fields',jsonb_build_array(
              'subject_ref','structure_status','observed_locations',
              'expected_canonical_location','normalization_required'
            ),
            'resume_entrypoint','public.lf_router_product_cycle_v1',
            'return_to_router_required',true
          ),
          'context_loader',jsonb_build_object(
            'function','public.lf_router_product_context_v1',
            'read_only',true,
            'contains_full_context',true
          ),
          'motivo_es','Producto resolvio primero el sujeto y su contexto. El perfil de Producto debe distinguir contenido canonico, contenido no canonico, brecha estructural o ausencia real.',
          'siguiente_paso_es','Devolver LF_PRODUCT_STRUCTURE_ASSESSMENT_V1 al Router. Una reparacion estructural vuelve obligatoriamente a Producto antes de implementar funcionalidad.'
        );
      END IF;
    END IF;

    -- If no exact aggregate product context is available, preserve the bounded
    -- canonical search fallback. target_type never narrows the search by itself.
    v_hint := NULL;
  ELSE
    -- Legacy V1 compatibility only. V2 never reads or emits this field.
    IF p_stage1->>'sistema'<>'LF' THEN
      RETURN v_base || jsonb_build_object(
        'paso','SYSTEM_NOT_SUPPORTED',
        'sistema',p_stage1->'sistema',
        'motivo_es','El contrato V1 heredado solo atiende LF.',
        'siguiente_paso_es','Informar al usuario; no despachar.'
      );
    END IF;

    v_hint := nullif(p_stage1->>'capability_hint','');
    IF v_hint IS NOT NULL THEN
      v_d := public.lf_router_dispatch_v1(
        p_stage1->>'texto_original',
        v_hint,
        coalesce(p_caller,'{}'::jsonb)
      );
      RETURN v_base || jsonb_build_object(
        'paso','DISPATCHED',
        'despacho',v_d,
        'motivo_es','Se conserva el despacho del contrato V1 heredado.',
        'siguiente_paso_es','Seguir el resultado del despacho.'
      );
    END IF;
  END IF;

  IF coalesce(p_stage1->>'accion','') ~* '(cambi|modific|actualiz|edit|correg|renombr|update|change|modify|fix|rename)' THEN
    v_rs := public.lf_router_resolve_v1(p_stage1->>'texto_original');
    IF v_rs->>'subject_binding_state'='RESOLVED'
       AND jsonb_array_length(coalesce(v_rs->'executor_candidates','[]'::jsonb))>0
       AND v_rs->>'blocking_code'='BLOCK_EXECUTOR_CAPABILITY_UNATTESTED' THEN
      RETURN v_base || jsonb_build_object(
        'paso','PROPUESTA_PERFIL',
        'sujeto',v_rs->'subject_candidates',
        'perfil_candidato',v_rs#>'{executor_candidates,0}',
        'modo','PROPUESTA_SOLO_LECTURA',
        'instruccion_literal',p_stage1->>'texto_original',
        'router_resolve',jsonb_build_object(
          'status',v_rs->>'status',
          'blocking_code',v_rs->>'blocking_code',
          'semantic_gap_code',v_rs->>'semantic_gap_code',
          'request_sha256',v_rs->>'request_sha256'
        ),
        'siguiente_operacion',jsonb_build_object(
          'operation_code','EJECUCION_PERFIL_LF',
          'entrypoint','ROUTER_ONLY',
          'executor_mode','GPT_NATIVE',
          'read_only',true,
          'no_write',true
        ),
        'motivo_es','El sujeto esta resuelto y el perfil candidato solo puede trabajar en propuesta.',
        'siguiente_paso_es','Trabajar la propuesta y volver al Router para cualquier efecto.'
      );
    END IF;
  END IF;

  SELECT array_agg(e#>>'{}')
  INTO v_formas
  FROM jsonb_array_elements(p_stage1->'formas_busqueda') e;

  SELECT coalesce(
    jsonb_agg(
      x ORDER BY
      (x->>'exacto')::boolean DESC,
      (x->>'cobertura')::numeric DESC,
      (x->>'apariciones')::int DESC,
      (x->>'mejor_posicion')::int ASC,
      x->>'codigo'
    ),
    '[]'::jsonb
  )
  INTO v_cands
  FROM (
    SELECT jsonb_build_object(
      'origen',min(c->>'origen'),
      'codigo',c->>'codigo',
      'tipo',min(c->>'tipo'),
      'titulo',min(c->>'titulo'),
      'exacto',bool_or((c->>'exacto')::boolean),
      'cobertura',round(max((c->>'coinciden')::numeric/nullif((c->>'de')::numeric,0)),2),
      'apariciones',count(*),
      'mejor_posicion',min(pos)
    ) AS x
    FROM unnest(v_formas) f,
         LATERAL jsonb_array_elements(public.lf_router_search_v1(f,5)->'candidatos')
           WITH ORDINALITY AS t(c,pos)
    GROUP BY c->>'codigo'
  ) s;

  v_n := jsonb_array_length(v_cands);
  IF v_n=1 OR (
    v_n>1
    AND (v_cands->0->>'exacto')::boolean IS TRUE
    AND (v_cands->1->>'exacto')::boolean IS NOT TRUE
  ) THEN
    RETURN v_base || jsonb_build_object(
      'paso','CANDIDATO_UNICO',
      'candidatos',jsonb_build_array(v_cands->0),
      'motivo_es','El nivel 1 dio un candidato unico o exacto. Es una pista, no autoridad.',
      'siguiente_paso_es','Confirmar identidad y continuar por la autoridad correspondiente.'
    );
  ELSIF v_n>1 THEN
    RETURN v_base || jsonb_build_object(
      'paso','ELEGIR_O_PROFUNDIZAR',
      'candidatos',v_cands,
      'sondeo_sugerido',jsonb_build_object(
        'leer_juntos',(
          SELECT jsonb_agg(x->>'codigo')
          FROM (SELECT x FROM jsonb_array_elements(v_cands) x LIMIT 3) t
        ),
        'max_sondeos_por_duda',3,
        'cuarto_sondeo_requiere_autorizacion_del_propietario',true,
        'solo_lectura',true
      ),
      'motivo_es','El nivel 1 dio varios candidatos.',
      'siguiente_paso_es','Elegir con evidencia acotada; preguntar solo si persiste ambiguedad material.'
    );
  END IF;

  IF NOT coalesce(p_nivel2_consentido,false) THEN
    RETURN v_base || jsonb_build_object(
      'paso','NIVEL_2_CONSENTIMIENTO',
      'candidatos','[]'::jsonb,
      'pregunta_usuario','Busque en el inventario y no lo encuentro. ¿Busco fuera del inventario (repo y tablas, solo lectura)?',
      'motivo_es','El nivel 1 no dio candidatos.',
      'siguiente_paso_es','Pedir consentimiento antes del nivel 2.'
    );
  END IF;

  SELECT coalesce(
    jsonb_agg(x ORDER BY (x->>'coinciden')::int DESC,x->>'ref'),
    '[]'::jsonb
  )
  INTO v_l2
  FROM (
    SELECT DISTINCT ON (c->>'ref') c AS x
    FROM unnest(v_formas) f,
         LATERAL jsonb_array_elements(public.lf_router_search_nivel2_v1(f,5)->'candidatos') c
    ORDER BY c->>'ref',(c->>'coinciden')::int DESC
  ) d;

  RETURN v_base || jsonb_build_object(
    'paso','NIVEL_2_RESULTADO',
    'resultado',CASE
      WHEN jsonb_array_length(v_l2)>0 THEN 'ENCONTRADO_FUERA_DE_INVENTARIO'
      ELSE 'NO_ENCONTRADO_EN_INDICE'
    END,
    'candidatos',(
      SELECT coalesce(jsonb_agg(x),'[]'::jsonb)
      FROM (SELECT x FROM jsonb_array_elements(v_l2) x LIMIT 5) t
    ),
    'downstream_execution_allowed',false
  );
END
$f$;

COMMENT ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) IS
'Punto unico Stage2 ACT-0001. PRODUCTO resuelve sujeto/contexto, clasifica estructura y usa ciclo PRODUCTO->reparacion estructural->PRODUCTO antes de implementacion. target_type es hint/control. PROGRAMACION requiere definicion vigente; OPERACIONES exige capacidad y alcance autorizados.';

DO $t$
DECLARE
  pc jsonb;
  r_screen jsonb;
  r_rule_hint jsonb;
  submit jsonb;
BEGIN
  pc := public.lf_router_product_context_v1(
    'Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a Acceder, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.',
    '{"target_type":"PANTALLA","target_hint":"Login B2B","resolution_status":"UNRESOLVED"}'::jsonb
  );

  IF pc->>'status' IS DISTINCT FROM 'RESOLVED'
     OR pc->>'subject_ref' IS DISTINCT FROM 'B2B-AUTH-001'
     OR pc->>'resolved_target_type' IS DISTINCT FROM 'PANTALLA'
     OR pc->>'target_type_authority' IS DISTINCT FROM 'HINT_ONLY_NOT_SEARCH_SELECTOR'
     OR pc->>'target_type_hint_consistency' IS DISTINCT FROM 'CONSISTENT' THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_SCREEN_RESOLUTION:%',pc-'product_context';
  END IF;

  SELECT x INTO submit
  FROM jsonb_array_elements(pc#>'{product_context,elements}') x
  WHERE x->>'element_code'='B2B_AUTH001_SUBMIT'
  LIMIT 1;

  IF submit IS NULL OR submit->>'label_visible' IS DISTINCT FROM 'Acceder' THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_ELEMENT_MISSING:%',submit;
  END IF;

  r_screen := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a Acceder, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.",
    "es_operacion":true,"respuesta_directa":false,
    "accion":"cambiar definición visual","sujeto":"botón principal de Iniciar sesión B2B",
    "correcciones":[],"formas_busqueda":["Login B2B","botón principal Acceder"],
    "ambiguo":false,"alternativas":[],"pregunta_usuario":null,"capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PRODUCTO","negocio_codigo":"LF","negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Cambio de definición de producto.",
    "alcance":{"target_type":"PANTALLA","target_hint":"Login B2B","resolution_status":"UNRESOLVED"}
  }'::jsonb);

  r_rule_hint := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a Acceder, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.",
    "es_operacion":true,"respuesta_directa":false,
    "accion":"cambiar definición visual","sujeto":"botón principal de Iniciar sesión B2B",
    "correcciones":[],"formas_busqueda":["Login B2B","botón principal Acceder"],
    "ambiguo":false,"alternativas":[],"pregunta_usuario":null,"capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PRODUCTO","negocio_codigo":"LF","negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Cambio de definición de producto.",
    "alcance":{"target_type":"REGLA","target_hint":"Login B2B","resolution_status":"UNRESOLVED"}
  }'::jsonb);

  IF r_screen->>'paso' IS DISTINCT FROM 'PRODUCTO_CONTEXTO_CANONICO'
     OR r_rule_hint->>'paso' IS DISTINCT FROM 'PRODUCTO_CONTEXTO_CANONICO' THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_ROUTE_NOT_USED:%:%',r_screen,r_rule_hint;
  END IF;

  IF r_screen#>>'{contexto_producto,subject_ref}' IS DISTINCT FROM 'B2B-AUTH-001'
     OR r_rule_hint#>>'{contexto_producto,subject_ref}' IS DISTINCT FROM 'B2B-AUTH-001' THEN
    RAISE EXCEPTION 'TARGET_TYPE_CHANGED_SUBJECT_SEARCH:%:%',r_screen,r_rule_hint;
  END IF;

  IF r_screen#>>'{contexto_producto,target_type_hint_consistency}' IS DISTINCT FROM 'CONSISTENT'
     OR r_rule_hint#>>'{contexto_producto,target_type_hint_consistency}' IS DISTINCT FROM 'MISMATCH_HINT_ONLY' THEN
    RAISE EXCEPTION 'TARGET_TYPE_HINT_SEMANTICS:%:%',r_screen,r_rule_hint;
  END IF;

  IF r_screen ? 'candidatos' OR r_rule_hint ? 'candidatos' THEN
    RAISE EXCEPTION 'BROAD_SEARCH_SHOULD_NOT_COMPETE_AFTER_SUBJECT_RESOLUTION:%:%',r_screen,r_rule_hint;
  END IF;

  IF r_screen#>'{contexto_producto}' ? 'product_context'
     OR r_rule_hint#>'{contexto_producto}' ? 'product_context' THEN
    RAISE EXCEPTION 'FULL_CONTEXT_MUST_NOT_BLOAT_ROUTE_RESPONSE';
  END IF;

  IF (r_screen->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR (r_rule_hint->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_EFFECT_AUTHORITY';
  END IF;
END
$t$;

DO $cascade$
DECLARE
  pc jsonb;
  h jsonb;
  a jsonb;
  repair_route jsonb;
  post_repair jsonb;
  final_route jsonb;
BEGIN
  pc := public.lf_router_product_context_v1(
    'Agregar pestañas al detalle y trazabilidad del lote B2B-CARGA-003 sin inventar una estructura fuera de la definición canónica.',
    '{"target_type":"PANTALLA","target_hint":"B2B-CARGA-003","resolution_status":"UNRESOLVED"}'::jsonb
  );

  IF pc->>'status' IS DISTINCT FROM 'RESOLVED'
     OR pc->>'subject_ref' IS DISTINCT FROM 'B2B-CARGA-003'
     OR pc->>'subject_resolution_method' IS DISTINCT FROM 'EXACT_SCREEN_CODE_OR_SCOPE_HINT' THEN
    RAISE EXCEPTION 'CASCADE_SUBJECT_RESOLUTION:%',pc-'product_context';
  END IF;

  SELECT x INTO h
  FROM jsonb_array_elements(pc#>'{product_context,elements}') x
  WHERE x->>'element_role'='PAGE_HEADER'
  LIMIT 1;

  IF h IS NULL
     OR position('TABS_IF_APPLICABLE' in coalesce(h->'component_token_bindings'->'slots','[]'::jsonb)::text)=0 THEN
    RAISE EXCEPTION 'CASCADE_TAB_SUPPORT_NOT_OBSERVED:%',h;
  END IF;

  a := jsonb_build_object(
    'schema_version','LF_PRODUCT_STRUCTURE_ASSESSMENT_V1',
    'subject_ref','B2B-CARGA-003',
    'structure_status','STRUCTURAL_GAP',
    'observed_locations',jsonb_build_array(
      jsonb_build_object(
        'kind','COMPONENT_SLOT',
        'ref','b2b_page_header_default:TABS_IF_APPLICABLE'
      )
    ),
    'expected_canonical_location',jsonb_build_object(
      'status','MISSING',
      'concept','SCREEN_TABS'
    ),
    'normalization_required',true,
    'normalization_proposal',jsonb_build_object(
      'goal','CREATE_CANONICAL_TAB_STRUCTURE_WITHOUT_INVENTING_FUNCTIONAL_VALUES'
    )
  );

  repair_route := public.lf_router_product_cycle_v1(a);
  IF repair_route->>'paso' IS DISTINCT FROM 'PROGRAMACION_REPARACION_ESTRUCTURAL_REQUERIDA'
     OR repair_route->>'repair_scope' IS DISTINCT FROM 'STRUCTURE_ONLY_NO_FUNCTIONAL_TRUTH'
     OR repair_route->>'return_channel_after_repair' IS DISTINCT FROM 'PRODUCTO'
     OR (repair_route->>'functional_truth_write_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CASCADE_REPAIR_ROUTE:%',repair_route;
  END IF;

  post_repair := public.lf_router_product_cycle_v1(jsonb_build_object(
    'schema_version','LF_PRODUCT_STRUCTURAL_REPAIR_RESULT_V1',
    'subject_ref','B2B-CARGA-003',
    'repair_status','REPAIRED',
    'canonical_structure_ref',jsonb_build_object(
      'kind','CANONICAL_STRUCTURE',
      'ref','candidate://screen-tabs-structure'
    ),
    'repair_evidence_refs',jsonb_build_array(
      'readback://schema/screen-tabs-structure',
      'test://B2B-CARGA-003/tab-structure'
    )
  ));

  IF post_repair->>'paso' IS DISTINCT FROM 'PRODUCTO_REVALIDACION_POST_REPARACION'
     OR post_repair->>'canal_siguiente' IS DISTINCT FROM 'PRODUCTO' THEN
    RAISE EXCEPTION 'CASCADE_MUST_RETURN_TO_PRODUCT:%',post_repair;
  END IF;

  final_route := public.lf_router_product_cycle_v1(jsonb_build_object(
    'schema_version','LF_PRODUCT_CANONICALIZATION_RESULT_V1',
    'subject_ref','B2B-CARGA-003',
    'canonical_status','CANONICAL_UPDATED',
    'canonical_definition_ref',jsonb_build_object(
      'kind','PRODUCT_DEFINITION',
      'ref','candidate://B2B-CARGA-003/tabs'
    ),
    'currentness_verified',true,
    'implementation_required',true
  ));

  IF final_route->>'paso' IS DISTINCT FROM 'PROGRAMACION_PRECHECK_DEFINICION'
     OR final_route->>'canal_siguiente' IS DISTINCT FROM 'PROGRAMACION'
     OR (final_route->>'currentness_verified')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CASCADE_IMPLEMENTATION_ONLY_AFTER_PRODUCT:%',final_route;
  END IF;
END
$cascade$;

COMMIT;
