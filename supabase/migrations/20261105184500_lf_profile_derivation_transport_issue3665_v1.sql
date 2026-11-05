-- lf_profile_derivation_transport_issue3665_v1
-- Issue #3665: exactly six existing FUNCTION UPDATEs, no ACL / policies / new routes.
-- Apply only as one migration via ACTUALIZACION_DB_LF / LF Migration Merge Train.
-- No direct Supabase write. Atomic DO rolls back all six edits if any gate fails.
DO $lf3665$
DECLARE
  rec record;
  current_def text;
  edited_def text;
  found_count integer;
  v_id constant text:='EXEC-PROFILE-GATE2-43633381F2A1B84882FB9010';
  v_original text;
  v_sha text;
  v_ready jsonb;
  v_null jsonb;
  v_fake jsonb;
  v_changed jsonb;
  v_incomplete jsonb;
  v_non_direct jsonb;
  v_full_stage1 jsonb;
  v_route jsonb;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
    ('public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)','55511725602b989238f9629a27f1ddd5',$lf3665_old_0$    v_stage1_literal:=
      'Solicitud original: '||p_original_request
      ||E'\n\nRetorno gobernado del perfil '
      ||p_profile_code
      ||': '
      ||v_payload::text;$lf3665_old_0$,$lf3665_new_0$    -- Preserve the original request identity; keep unresolved_payload separate.
    v_stage1_literal:=p_original_request;$lf3665_new_0$,1),
    ('public.lf_profile_result_router_return_prepare_v1(text)','8bf503bf17f038a18124783c038d9793',$lf3665_old_1$  v_decision:=public.lf_profile_result_router_return_classify_v1($lf3665_old_1$,$lf3665_new_1$  -- Fail closed if historical manifest and canonical request hash disagree.
  IF v_original_request IS NULL OR e.request_sha256 IS DISTINCT FROM
    encode(extensions.digest(convert_to(v_original_request,'UTF8'),'sha256'),'hex')
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_PREPARE_V1',
      'status','BLOCKED','code','PROFILE_RESULT_RETURN_ORIGINAL_REQUEST_SHA_MISMATCH',
      'execution_id',p_execution_id
    );
  END IF;
  v_decision:=public.lf_profile_result_router_return_classify_v1($lf3665_new_1$,1),
    ('public.lf_router_route_v1(jsonb,jsonb,boolean)','4e5c9a76a48769dea3ec72faf5ebceb7',$lf3665_old_2$NULL::jsonb, p_stage1);$lf3665_old_2$,$lf3665_new_2$CASE
          WHEN nullif(btrim(coalesce(p_stage1#>>'{alcance,source_execution_id}','')),'') IS NOT NULL
          THEN jsonb_build_object('source_execution_id',p_stage1#>>'{alcance,source_execution_id}')
          ELSE NULL::jsonb
        END, p_stage1);$lf3665_new_2$,3),
    ('public.lf_router_profile_after_selection_v1(jsonb,jsonb)','1f84204588c130148c33746a901f580b',$lf3665_old_3$NULL::jsonb, p_stage1);$lf3665_old_3$,$lf3665_new_3$CASE
          WHEN nullif(btrim(coalesce(p_stage1#>>'{alcance,source_execution_id}','')),'') IS NOT NULL
          THEN jsonb_build_object('source_execution_id',p_stage1#>>'{alcance,source_execution_id}')
          ELSE NULL::jsonb
        END, p_stage1);$lf3665_new_3$,1),
    ('public.lf_router_profile_after_selection_raw_v1(jsonb,text)','40009812ec47f4e93b7d52a9d807b779',$lf3665_old_4$NULL::jsonb, p_stage1);$lf3665_old_4$,$lf3665_new_4$CASE
          WHEN nullif(btrim(coalesce(p_stage1#>>'{alcance,source_execution_id}','')),'') IS NOT NULL
          THEN jsonb_build_object('source_execution_id',p_stage1#>>'{alcance,source_execution_id}')
          ELSE NULL::jsonb
        END, p_stage1);$lf3665_new_4$,1),
    ('public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)','af1e2fd3675de05d0f421f6f76270364',$lf3665_old_5$    if v_ok is true then v_deriv:=jsonb_build_object('source_execution_id',v_src); end if;$lf3665_old_5$,$lf3665_new_5$    -- Only canonical one-field envelope; DB proves COMPLETED, DIRECT and same SHA.
    IF v_ok IS TRUE AND jsonb_typeof(p_derivation)='object'
       AND (SELECT count(*) FROM jsonb_object_keys(p_derivation))=1
    THEN
      v_deriv:=jsonb_build_object('source_execution_id',v_src);
    END IF;$lf3665_new_5$,1)
    ) AS patches(signature,expected_md5,old_fragment,new_fragment,expected_occurrences)
  LOOP
    SELECT pg_get_functiondef(rec.signature::regprocedure) INTO current_def;
    IF md5(current_def) IS DISTINCT FROM rec.expected_md5 THEN
      RAISE EXCEPTION 'LF3665_SOURCE_MD5_DRIFT:%',rec.signature;
    END IF;
    found_count := (length(current_def)-length(replace(current_def,rec.old_fragment,''))) / length(rec.old_fragment);
    IF found_count<>rec.expected_occurrences THEN
      RAISE EXCEPTION 'LF3665_SOURCE_ANCHOR_DRIFT:% expected % observed %',rec.signature,rec.expected_occurrences,found_count;
    END IF;
    edited_def:=replace(current_def,rec.old_fragment,rec.new_fragment);
    IF edited_def IS NOT DISTINCT FROM current_def THEN
      RAISE EXCEPTION 'LF3665_NO_SOURCE_DELTA:%',rec.signature;
    END IF;
    EXECUTE edited_def;
  END LOOP;

  -- All following reads execute in the SAME atomic DO as the six replacements.
  SELECT e.manifest#>>'{router_profile_handoff,literal_request}',e.request_sha256
    INTO v_original,v_sha FROM public.lf_operation_execution e
  WHERE e.execution_id=v_id AND e.operation_code='EJECUCION_PERFIL_LF'
    AND e.status='COMPLETED' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF';
  IF v_original IS NULL OR v_sha IS NULL
     OR v_sha<>encode(extensions.digest(convert_to(v_original,'UTF8'),'sha256'),'hex')
     OR NOT EXISTS (SELECT 1 FROM public.lf_profile_selector_policy_v1 p
                    WHERE p.profile_code='PERFIL-PRODUCT-DIRECTOR-LF' AND p.entry_policy='DIRECT') THEN
    RAISE EXCEPTION 'LF3665_EVIDENCE_SOURCE_NOT_CURRENT';
  END IF;

  v_ready:=public.lf_profile_selector_semantic_prepare_v2(v_original,'PRODUCTO',
    jsonb_build_object('source_execution_id',v_id), NULL::jsonb);
  v_null:=public.lf_profile_selector_semantic_prepare_v2(v_original,'PRODUCTO',NULL::jsonb,NULL::jsonb);
  v_fake:=public.lf_profile_selector_semantic_prepare_v2(v_original,'PRODUCTO',
    jsonb_build_object('source_execution_id','EXEC-INVALID-ISSUE3665'),NULL::jsonb);
  v_changed:=public.lf_profile_selector_semantic_prepare_v2('Solicitud original: '||v_original,
    'PRODUCTO',jsonb_build_object('source_execution_id',v_id),NULL::jsonb);
  v_incomplete:=public.lf_profile_selector_semantic_prepare_v2(v_original,'PRODUCTO',
    jsonb_build_object('source_execution_id',''),NULL::jsonb);
  v_non_direct:=public.lf_profile_selector_semantic_prepare_v2(v_original,'PRODUCTO',
    jsonb_build_object('source_execution_id',v_id,'entry_policy','DERIVATION_ONLY'),NULL::jsonb);

  IF v_ready->'derivation' IS DISTINCT FROM jsonb_build_object('source_execution_id',v_id)
     OR v_ready->>'request_sha256' IS DISTINCT FROM v_sha
     OR v_ready->>'catalog_profile_count' IS DISTINCT FROM '8' THEN
    RAISE EXCEPTION 'LF3665_VALID_DERIVATION_INVARIANT_FAILED';
  END IF;
  IF v_null->'derivation' IS DISTINCT FROM 'null'::jsonb
     OR v_null->>'catalog_profile_count'<>'5'
     OR v_fake->'derivation' IS DISTINCT FROM 'null'::jsonb
     OR v_fake->>'catalog_profile_count'<>'5'
     OR v_changed->'derivation' IS DISTINCT FROM 'null'::jsonb
     OR v_changed->>'catalog_profile_count'<>'5'
     OR v_incomplete->'derivation' IS DISTINCT FROM 'null'::jsonb
     OR v_incomplete->>'catalog_profile_count'<>'5'
     OR v_non_direct->'derivation' IS DISTINCT FROM 'null'::jsonb
     OR v_non_direct->>'catalog_profile_count'<>'5' THEN
    RAISE EXCEPTION 'LF3665_NEGATIVE_DERIVATION_INVARIANT_FAILED';
  END IF;

  -- The already existing Stage1 shape carries return provenance inside alcance.
  -- This is a candidate only; ACT-0001 remains DERIVE_ONLY.
  v_full_stage1:=jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2','texto_original',v_original,
    'es_operacion',true,'respuesta_directa',false,'ambiguo',false,
    'accion','revisar','sujeto','login B2B',
    'formas_busqueda',jsonb_build_array('login B2B'),
    'alternativas','[]'::jsonb,'correcciones','[]'::jsonb,
    'pregunta_usuario',NULL,'capability_hint',NULL,
    'downstream_execution_allowed',false,'canal_candidato','PRODUCTO',
    'negocio_codigo','LF','negocios_afectados','[]'::jsonb,
    'razon_seleccion','Regresión técnica LF3665',
    'alcance',jsonb_build_object('target_type','FUNCTION','source_execution_id',v_id)
  );
  IF (public.lf_router_stage1_validate_v2(v_full_stage1)->>'valid')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'LF3665_STAGE1_VALIDATION_FAILED';
  END IF;
  v_route:=public.lf_router_route_v1(v_full_stage1,'{}'::jsonb,false);
  IF v_route#>>'{profile_selection_request,catalog_profile_count}'<>'8'
     OR v_route#>'{profile_selection_request,derivation}'
        IS DISTINCT FROM jsonb_build_object('source_execution_id',v_id) THEN
    RAISE EXCEPTION 'LF3665_ROUTE_DERIVATION_INVARIANT_FAILED';
  END IF;
END
$lf3665$;
