-- IG M10.7 A2: versioned promotion only after exact-parity G0 candidate.
-- Contains canonical function replacement, no other function/trigger/rule mutation.
DO $pre$
DECLARE
 v_id int;
 v_a jsonb;
 v_b jsonb;
BEGIN
 IF md5(pg_get_functiondef('programacion.fn_input_design_binding_graph_v2(integer)'::regprocedure))
    <>'15c45a5f0a21eab97961b4906d572546'
    OR md5(pg_get_functiondef('programacion.fn_input_design_binding_graph_v2_candidate_v1(integer)'::regprocedure))
    <>'d5e23d3335b1f59f0c831ac68303efb4'
 THEN RAISE EXCEPTION 'IG_M107_A2_PROMOTION_SOURCE_PRECONDITION_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='IG-M107-A2-INCALL-RECEIPT-DEDUPE-CANDIDATE-013' AND estado='ACTIVO'
 AND evidencia::jsonb->>'exact_json_and_sha_equal_every_trial'='true'
 AND evidencia::jsonb->>'runtime_consumers_activated'='false')
 THEN RAISE EXCEPTION 'IG_M107_A2_PARITY_EVIDENCE_NOT_ADMITTED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='IG-M107-A2-INCALL-PROMOTION-014')
 THEN RAISE EXCEPTION 'IG_M107_A2_PROMOTION_ALREADY_APPLIED'; END IF;
 FOREACH v_id IN ARRAY ARRAY[1,43,58] LOOP
   v_a:=programacion.fn_input_design_binding_graph_v2(v_id);
   v_b:=programacion.fn_input_design_binding_graph_v2_candidate_v1(v_id);
   IF v_a IS DISTINCT FROM v_b
     OR programacion.fn_v09_sha256_jsonb(v_a)
       IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_b)
   THEN RAISE EXCEPTION 'IG_M107_A2_SOURCE_PARITY_PRE_PROMOTION_FAILED_SCREEN_%',v_id; END IF;
 END LOOP;
END $pre$;

CREATE OR REPLACE FUNCTION programacion.fn_input_design_binding_graph_v2(p_pantalla_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops', 'lf_design'
AS $function$
declare
  v_design_resolution jsonb;
  v_design_system_id bigint;
  v_receipts jsonb:='{}'::jsonb;
  v_screen jsonb; v_fields jsonb; v_variants jsonb; v_elements jsonb;
  v_field_count integer; v_field_bound integer; v_field_semantic_pending integer; v_variant_count integer; v_variant_bound integer;
  v_element_count integer; v_element_required integer; v_element_bound integer; v_element_semantic_pending integer; v_integrity_failures integer;
begin
  select to_jsonb(p) into v_screen from lf_ops.pantallas p where p.id=p_pantalla_id;
  if v_screen is null then raise exception 'DESIGN_BINDING_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  v_design_resolution:=programacion.fn_input_design_system_resolution_v1(p_pantalla_id);
  v_design_system_id:=(v_design_resolution->>'design_system_id')::bigint;

  -- One receipt per unique token in THIS function invocation; no cross-call cache.
  WITH token_ids AS (
    SELECT cp.component_token_id AS token_id
      FROM lf_ops.campos_pantallas cp
     WHERE cp.pantalla_id=p_pantalla_id AND cp.component_token_id IS NOT NULL
    UNION
    SELECT pv.layout_component_token_id
      FROM lf_ops.pantalla_variantes pv
     WHERE pv.pantalla_id=p_pantalla_id AND pv.layout_component_token_id IS NOT NULL
    UNION
    SELECT pe.component_token_id
      FROM lf_ops.pantalla_elementos pe
     WHERE pe.pantalla_id=p_pantalla_id AND pe.status<>'DEPRECATED'
       AND pe.component_token_id IS NOT NULL
  )
  SELECT coalesce(jsonb_object_agg(token_id::text,
           programacion.fn_input_component_binding_receipt(token_id,v_design_system_id)),
           '{}'::jsonb)
    INTO v_receipts
    FROM token_ids;


  select count(*),count(*) filter(where cp.component_token_id is not null),count(*) filter(where coalesce(cp.nota,'')~*'PENDING_VISUAL_COMPONENT'),
         coalesce(jsonb_agg(jsonb_build_object(
           'screen_field_link_id',cp.id,'field_id',c.id,'field_code',c.codigo,'context_key',cp.context_key,
           'component_token_id',cp.component_token_id,'component_token_code',cp.component_token_code,'source_note',cp.nota,
           'semantic_binding_pending',coalesce(cp.nota,'')~*'PENDING_VISUAL_COMPONENT',
           'binding_status',case when cp.component_token_id is null then 'MISSING' when coalesce(cp.nota,'')~*'PENDING_VISUAL_COMPONENT' then 'PENDING_SEMANTIC_COMPONENT' else 'RESOLVED_ID' end,
           'component_receipt',case when cp.component_token_id is null then null else (v_receipts->(cp.component_token_id::text)) end
         ) order by cp.orden_visual,cp.id),'[]'::jsonb)
    into v_field_count,v_field_bound,v_field_semantic_pending,v_fields
  from lf_ops.campos_pantallas cp join lf_ops.campos c on c.id=cp.campo_id where cp.pantalla_id=p_pantalla_id;

  select count(*),count(*) filter(where pv.layout_component_token_id is not null),
         coalesce(jsonb_agg(jsonb_build_object(
           'variant_id',pv.variant_id,'variant_code',pv.variant_code,'responsive_token_id',pv.responsive_token_id,'theme_binding_id',pv.theme_binding_id,
           'layout_component_token_id',pv.layout_component_token_id,'layout_component_token_code',pv.layout_component_token_code,'source_decision_id',pv.source_decision_id,
           'binding_status',case when pv.layout_component_token_id is null then 'MISSING' else 'RESOLVED_ID' end,
           'layout_component_receipt',case when pv.layout_component_token_id is null then null else (v_receipts->(pv.layout_component_token_id::text)) end
         ) order by pv.variant_id),'[]'::jsonb)
    into v_variant_count,v_variant_bound,v_variants
  from lf_ops.pantalla_variantes pv where pv.pantalla_id=p_pantalla_id;

  select count(*),count(*) filter(where pe.required_for_implementation),count(*) filter(where pe.component_token_id is not null),
         count(*) filter(where pe.semantic_binding_status='PENDING_SEMANTIC_COMPONENT'),
         coalesce(jsonb_agg(jsonb_build_object(
           'element_id',pe.element_id,'element_code',pe.element_code,'element_role',pe.element_role,'context_key',pe.context_key,
           'required_for_implementation',pe.required_for_implementation,'semantic_binding_status',pe.semantic_binding_status,'component_token_id',pe.component_token_id,
           'status',pe.status,'source_refs',pe.source_refs,
           'component_receipt',case when pe.component_token_id is null then null else (v_receipts->(pe.component_token_id::text)) end
         ) order by pe.element_id),'[]'::jsonb)
    into v_element_count,v_element_required,v_element_bound,v_element_semantic_pending,v_elements
  from lf_ops.pantalla_elementos pe where pe.pantalla_id=p_pantalla_id and pe.status<>'DEPRECATED';

  select coalesce(sum(x.failures),0)::integer into v_integrity_failures
  from (
    select case when cp.component_token_id is null then 0 else (((v_receipts->(cp.component_token_id::text))->>'unresolved_expected_ref_count')::integer+((v_receipts->(cp.component_token_id::text))->>'ambiguous_expected_ref_count')::integer) end failures
      from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id
    union all
    select case when pv.layout_component_token_id is null then 0 else (((v_receipts->(pv.layout_component_token_id::text))->>'unresolved_expected_ref_count')::integer+((v_receipts->(pv.layout_component_token_id::text))->>'ambiguous_expected_ref_count')::integer) end
      from lf_ops.pantalla_variantes pv where pv.pantalla_id=p_pantalla_id
    union all
    select case when pe.component_token_id is null then 0 else (((v_receipts->(pe.component_token_id::text))->>'unresolved_expected_ref_count')::integer+((v_receipts->(pe.component_token_id::text))->>'ambiguous_expected_ref_count')::integer) end
      from lf_ops.pantalla_elementos pe where pe.pantalla_id=p_pantalla_id and pe.status<>'DEPRECATED'
  ) x;

  return jsonb_build_object(
    'graph_contract','DESIGN_BINDING_GRAPH_V4',
    'pantalla_id',p_pantalla_id,
    'screen_code',v_screen->>'codigo',
    'design_system_id',v_design_system_id,
    'design_system_resolution',v_design_resolution,
    'fields',v_fields,'variants',v_variants,'elements',v_elements,
    'summary',jsonb_build_object(
      'field_count',v_field_count,'field_component_binding_count',v_field_bound,'field_component_missing_count',v_field_count-v_field_bound,'field_semantic_component_pending_count',v_field_semantic_pending,
      'variant_count',v_variant_count,'variant_layout_binding_count',v_variant_bound,'variant_layout_missing_count',v_variant_count-v_variant_bound,
      'element_inventory_count',v_element_count,'element_required_count',v_element_required,'element_component_binding_count',v_element_bound,
      'element_required_missing_component_count',(select count(*) from lf_ops.pantalla_elementos pe where pe.pantalla_id=p_pantalla_id and pe.status<>'DEPRECATED' and pe.required_for_implementation and (pe.component_token_id is null or pe.semantic_binding_status<>'RESOLVED_ID')),
      'element_semantic_component_pending_count',v_element_semantic_pending,'referential_integrity_failure_count',v_integrity_failures
    )
  );
end;
$function$
;


DO $post$
DECLARE
  v_id int;
  v_a jsonb;
  v_b jsonb;
  v_code constant text:='IG-M107-A2-INCALL-PROMOTION-014';
  v_new_md5 text;
  v_evidence jsonb;
  v_failed_original text;
  v_failed_candidate text;
BEGIN
  FOREACH v_id IN ARRAY ARRAY[1,43,58] LOOP
    v_a:=programacion.fn_input_design_binding_graph_v2(v_id);
    v_b:=programacion.fn_input_design_binding_graph_v2_candidate_v1(v_id);
    IF v_a IS DISTINCT FROM v_b
       OR programacion.fn_v09_sha256_jsonb(v_a)
          IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_b)
    THEN RAISE EXCEPTION 'IG_M107_A2_POST_PROMOTION_PARITY_FAILED_SCREEN_%',v_id; END IF;
  END LOOP;
  v_failed_original:=NULL; v_failed_candidate:=NULL;
  BEGIN
    PERFORM programacion.fn_input_design_binding_graph_v2(2147483647);
  EXCEPTION WHEN OTHERS THEN v_failed_original:=SQLERRM; END;
  BEGIN
    PERFORM programacion.fn_input_design_binding_graph_v2_candidate_v1(2147483647);
  EXCEPTION WHEN OTHERS THEN v_failed_candidate:=SQLERRM; END;
  IF v_failed_original IS DISTINCT FROM v_failed_candidate
     OR v_failed_original NOT LIKE 'DESIGN_BINDING_SCREEN_NOT_FOUND:%'
  THEN RAISE EXCEPTION 'IG_M107_A2_POST_PROMOTION_NEGATIVE_MISMATCH'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE n.nspname='programacion'
      AND p.proname='fn_input_design_binding_graph_v2'
      AND a.grantee=0 AND a.privilege_type='EXECUTE'
  ) THEN RAISE EXCEPTION 'IG_M107_A2_PUBLIC_EXECUTE_DRIFT'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='programacion'
      AND p.proname='fn_input_design_binding_graph_v2'
      AND p.prosecdef=true AND p.provolatile='v'
      AND p.proowner='postgres'::regrole
      AND p.proconfig @> ARRAY['search_path=pg_catalog, programacion, lf_ops, lf_design']::text[]
  ) THEN RAISE EXCEPTION 'IG_M107_A2_CANONICAL_SECURITY_METADATA_DRIFT'; END IF;
  SELECT md5(pg_get_functiondef('programacion.fn_input_design_binding_graph_v2(integer)'::regprocedure))
    INTO v_new_md5;
  IF v_new_md5='15c45a5f0a21eab97961b4906d572546'
  THEN RAISE EXCEPTION 'IG_M107_A2_NO_EFFECT'; END IF;
  v_evidence:=jsonb_build_object(
    'schema','IG_M107_A2_INCALL_PROMOTION_V1',
    'canonical_old_md5','15c45a5f0a21eab97961b4906d572546',
    'canonical_new_md5',v_new_md5,
    'candidate_md5','d5e23d3335b1f59f0c831ac68303efb4',
    'evidence_source','IG-M107-A2-INCALL-RECEIPT-DEDUPE-CANDIDATE-013',
    'screens',jsonb_build_array(1,43,58),
    'before_and_after_json_sha_equal',true,
    'negative_missing_screen_equivalent',true,
    'public_execute',false,
    'security_definer_preserved',true,
    'cross_call_caching_enabled',false,
    'source_mutation_tested',false,
    'trigger_changes',false,'rule_changes',false,
    'validator_time_reduction_proven',false,
    'cp3_closed',false);
  INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref
  ) VALUES(
    gen_random_uuid(),v_code,'GOVERNANCE',
    'A2 deduplicación en el grafo canónico dentro de una invocación',
    'Cambio transversal en fn_input_design_binding_graph_v2. Reutiliza recibos de token por identidad local de una evaluación, conservando integrity per-association y resultados exactos de JSON/SHA en pantallas 1,43,58. Contrato y permisos sin cambios, negativo inexistente preservado.',
    'Repetición de fn_input_component_binding_receipt por componente durante preparación y sumatoria de integridad; 40 asociaciones con 12 tokens en pantalla 43.',
    'CANONICAL_DESIGN_RECEIPT_INCALL_DEDUP',
    'No reutilizar entre transacciones hasta G2B; conservar source-currentness y triggers de evaluación, resolver por token una vez solo por invocación. Cambios concurrentes exigen guard actual, no inferir garantía de concurrencia de este microbenchmark.',
    'G1 candidato y prueba 9/9 exactas en PR #2750; pre+post SQL igualdad en 3 pantallas y negativo; mejora puntual de tiempo del grafo, no Validator; CP3 sigue pendiente.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
    v_evidence::text,clock_timestamp(),clock_timestamp(),
    'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
    'In-call dedupe canonical promotion via LF Migration Train',
    'programacion.fn_input_design_binding_graph_v2(integer)'
  );
  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
  THEN RAISE EXCEPTION 'IG_M107_A2_EKB_READBACK_INVALID'; END IF;
END $post$;
