-- IG M10.7 A2 candidate, canonical head gate and no canonical mutation.
DO $pre$
BEGIN
 IF md5(pg_get_functiondef('programacion.fn_input_design_binding_graph_v2(integer)'::regprocedure))<>'15c45a5f0a21eab97961b4906d572546'
 THEN RAISE EXCEPTION 'IG_M107_A2_CANONICAL_PRECONDITION_DRIFT'; END IF;
 IF to_regprocedure('programacion.fn_input_design_binding_graph_v2_candidate_v1(integer)') IS NOT NULL
 THEN RAISE EXCEPTION 'IG_M107_A2_CANDIDATE_EXISTS'; END IF;
END $pre$;

CREATE FUNCTION programacion.fn_input_design_binding_graph_v2_candidate_v1(p_pantalla_id integer)
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
$function$;

REVOKE ALL ON FUNCTION programacion.fn_input_design_binding_graph_v2_candidate_v1(integer) FROM PUBLIC;
COMMENT ON FUNCTION programacion.fn_input_design_binding_graph_v2_candidate_v1(integer)
IS 'IG M10.7 A2 candidate only: one component receipt per distinct token within single invocation. No consumers or cross-call cache.';
DO $bench$
DECLARE
 v_code constant text:='IG-M107-A2-INCALL-RECEIPT-DEDUPE-CANDIDATE-013';
 v_original jsonb;
 v_candidate jsonb;
 v_screen integer;
 v_trial integer;
 v_started timestamptz;
 v_orig_ms numeric;
 v_new_ms numeric;
 v_samples jsonb:='[]'::jsonb;
 v_total integer;
 v_distinct integer;
 v_error_old text;
 v_error_new text;
 v_source_after text;
 v_evidence jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
 THEN RAISE EXCEPTION 'IG_M107_A2_EKB_ALREADY_EXISTS'; END IF;
 SELECT count(*),count(distinct token_id) INTO v_total,v_distinct
 FROM (
   SELECT component_token_id token_id FROM lf_ops.campos_pantallas
    WHERE pantalla_id=43 AND component_token_id IS NOT NULL
   UNION ALL
   SELECT layout_component_token_id FROM lf_ops.pantalla_variantes
    WHERE pantalla_id=43 AND layout_component_token_id IS NOT NULL
   UNION ALL
   SELECT component_token_id FROM lf_ops.pantalla_elementos
    WHERE pantalla_id=43 AND status<>'DEPRECATED' AND component_token_id IS NOT NULL
 ) token_sources;
 IF v_total<>40 OR v_distinct<>12
 THEN RAISE EXCEPTION 'IG_M107_A2_SAMPLE_ASSOCIATIONS_DRIFT:%:%',v_total,v_distinct; END IF;
 FOREACH v_screen IN ARRAY ARRAY[1,43,58] LOOP
   FOR v_trial IN 1..3 LOOP
     IF v_trial%2=1 THEN
       v_started:=clock_timestamp();
       v_original:=programacion.fn_input_design_binding_graph_v2(v_screen);
       v_orig_ms:=round(extract(epoch FROM (clock_timestamp()-v_started))*1000,3);
       v_started:=clock_timestamp();
       v_candidate:=programacion.fn_input_design_binding_graph_v2_candidate_v1(v_screen);
       v_new_ms:=round(extract(epoch FROM (clock_timestamp()-v_started))*1000,3);
     ELSE
       v_started:=clock_timestamp();
       v_candidate:=programacion.fn_input_design_binding_graph_v2_candidate_v1(v_screen);
       v_new_ms:=round(extract(epoch FROM (clock_timestamp()-v_started))*1000,3);
       v_started:=clock_timestamp();
       v_original:=programacion.fn_input_design_binding_graph_v2(v_screen);
       v_orig_ms:=round(extract(epoch FROM (clock_timestamp()-v_started))*1000,3);
     END IF;
     IF v_original IS DISTINCT FROM v_candidate
       OR programacion.fn_v09_sha256_jsonb(v_original)
          IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_candidate)
     THEN RAISE EXCEPTION 'IG_M107_A2_EXACT_PARITY_MISMATCH_SCREEN_%_TRIAL_%',v_screen,v_trial; END IF;
     v_samples:=v_samples||jsonb_build_array(jsonb_build_object(
       'screen_id',v_screen,'trial',v_trial,'canonical_ms',v_orig_ms,
       'candidate_ms',v_new_ms,'exact_json_equal',true,'sha_equal',true));
   END LOOP;
 END LOOP;
 v_error_old:=null;
 v_error_new:=null;
 BEGIN
  PERFORM programacion.fn_input_design_binding_graph_v2(2147483647);
 EXCEPTION WHEN OTHERS THEN v_error_old:=SQLERRM; END;
 BEGIN
  PERFORM programacion.fn_input_design_binding_graph_v2_candidate_v1(2147483647);
 EXCEPTION WHEN OTHERS THEN v_error_new:=SQLERRM; END;
 IF v_error_old IS DISTINCT FROM v_error_new
    OR v_error_old NOT LIKE 'DESIGN_BINDING_SCREEN_NOT_FOUND:%'
 THEN RAISE EXCEPTION 'IG_M107_A2_NEGATIVE_MISSING_SCREEN_NOT_EQUIVALENT'; END IF;
 IF EXISTS (
 SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
 WHERE n.nspname='programacion' AND p.proname='fn_input_design_binding_graph_v2_candidate_v1'
 AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
 ) THEN RAISE EXCEPTION 'IG_M107_A2_PUBLIC_EXECUTE_GRANTED'; END IF;
 SELECT md5(pg_get_functiondef('programacion.fn_input_design_binding_graph_v2(integer)'::regprocedure))
 INTO v_source_after;
 IF v_source_after<>'15c45a5f0a21eab97961b4906d572546'
 THEN RAISE EXCEPTION 'IG_M107_A2_CANONICAL_CHANGED'; END IF;
 v_evidence:=jsonb_build_object(
   'schema','IG_M107_A2_INCALL_COMPONENT_DEDUPE_CANDIDATE_V1',
   'canonical_function_md5',v_source_after,
   'screen43_binding_occurrences',v_total,'screen43_unique_tokens',v_distinct,
   'expected_static_receipt_call_sites',9,
   'positive_screens',jsonb_build_array(1,43,58),
   'per_trial_microbench',v_samples,
   'exact_json_and_sha_equal_every_trial',true,
   'negative_missing_screen_equivalent',true,
   'runtime_consumers_activated',false,
   'cross_call_cache_enabled',false,
   'concurrent_mutation_proven',false,
   'performance_admission',false,
   'cp3_closed',false);
 INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref)
 VALUES (
    gen_random_uuid(),v_code,'GOVERNANCE',
    'A2 candidato deduplicación de recibos de tokens dentro de invocación',
    'Precalcular y compartir recibos por token distinto entre fields, variants, elements e integrity sin cambiar suma por asociación. Compara JSON y SHA contra función vigente en pantallas 1,43,58, 3 ensayos alternados, negativo pantalla inexistente. Sin sustituir función canónica.',
    'Un grafo de pantalla puede resolver múltiples veces el mismo componente; pantalla 43 contiene 40 asociaciones y 12 tokens distintos.',
    'IN_CALL_COMPONENT_RECEIPT_DEDUP_ONLY',
    'No activar hasta equivalencia y seguridad con fuentes concurrentes. No usar caché persistente ni entre llamadas; mantener cálculo de integridad por asociación, comprobar 3 pantallas y resultado exacto. G2B para contexto entre transacciones.',
    'A2 candidato sin usuarios, misma estructura y SHA en muestra; mediciones por ensayo no son p90 ni tiempo total Validator. Prueba negativa equivalente y sin acceso público.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
    v_evidence::text,clock_timestamp(),clock_timestamp(),
    'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
    'A2 candidate exact parity and microbench, no runtime source change',
    'programacion.fn_input_design_binding_graph_v2_candidate_v1(integer)'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
 THEN RAISE EXCEPTION 'IG_M107_A2_EKB_NOT_PERSISTED'; END IF;
END $bench$;