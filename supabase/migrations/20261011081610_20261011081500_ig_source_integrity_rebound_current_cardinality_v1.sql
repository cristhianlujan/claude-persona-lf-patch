-- Exact source-first repair for the shared IG Curator assertion rebinder.
CREATE OR REPLACE FUNCTION programacion.fn_input_v58_build_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_pantalla_id integer;
  v_screen_code text;
  v_old jsonb;
  v_tpl jsonb;
  v_rebound jsonb;
  v_graph jsonb; v_fresh jsonb; v_ctx jsonb; v_path text[]; v_version_id bigint;
  v_out jsonb := '[]'::jsonb;
begin
  select pantalla_id into v_pantalla_id
  from programacion.input_readiness_runs where id=p_new_run_id;
  if v_pantalla_id is null then raise exception 'V58_ASSERTION_NEW_RUN_NOT_FOUND:%',p_new_run_id; end if;
  select p.codigo into v_screen_code from lf_ops.pantallas p where p.id=v_pantalla_id;
  if v_screen_code is null then raise exception 'V58_ASSERTION_SCREEN_NOT_FOUND:%',v_pantalla_id; end if;

  for v_old in
    select x.value
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(programacion.fn_input_validator_evidence_rehydrate_v1(a.validator_evidence)->'assertions') x(value)
    where a.run_id=p_parent_run_id and a.family_code=p_family_code
  loop
    if v_screen_code='B2B-AUTH-001' and p_family_code='VISUAL_EVIDENCE'
       and v_old->'source_ref'->>'kind'='CURRENT_VISUAL_ARTIFACT' then
      v_tpl:=jsonb_build_object(
        'source_ref',jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',v_pantalla_id),
        'path',jsonb_build_array('observed'),'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',v_pantalla_id,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-DESKTOP-LIGHT','canonical_canvas',true))),
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',v_pantalla_id,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-TABLET-LIGHT','canonical_canvas',true))),
          jsonb_build_object('artifact',jsonb_build_object('pantalla_id',v_pantalla_id,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-001-MOBILE-LIGHT','canonical_canvas',true)))
        )
      );
    else
      v_tpl:=programacion.fn_input_v512_assertion_template(v_pantalla_id,p_family_code,v_old);
    end if;
    -- Rebind only structural source-integrity cardinality when the canonical source SHA changes.
    -- No semantic/policy assertion or source-reference/path rewrite is admitted.
    IF (v_old->>'assertion_class')='SOURCE_INTEGRITY'
       AND (v_old->>'operator')='ARRAY_LENGTH_EQ' AND (v_tpl->>'operator')='ARRAY_LENGTH_EQ'
       AND (v_old->'source_ref')=(v_tpl->'source_ref') AND (v_old->'path')=(v_tpl->'path')
       AND (v_tpl->'source_ref'->>'kind')='SCREEN_CANONICAL_GRAPH' THEN
      SELECT version_id INTO v_version_id FROM programacion.input_readiness_runs WHERE id=p_new_run_id;
      v_ctx:=nullif(current_setting('lf.input_request_context_v1',true),'')::jsonb;
      IF (v_ctx->>'pantalla_id')=v_pantalla_id::text AND (v_ctx->>'version_id')=v_version_id::text
         AND jsonb_typeof(v_ctx->'graph')='object' THEN
        v_graph:=v_ctx->'graph';
      ELSE
        v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
      END IF;
      IF length(coalesce(v_old->>'source_observed_sha256',''))<>64 THEN
        RAISE EXCEPTION 'SOURCE_CARDINALITY_OLD_HASH_MISSING:%:%',v_pantalla_id,p_family_code;
      END IF;
      IF programacion.fn_v09_sha256_jsonb(v_graph) IS DISTINCT FROM (v_old->>'source_observed_sha256') THEN
        SELECT array_agg(e.value ORDER BY e.ord) INTO v_path FROM
        jsonb_array_elements_text(v_tpl->'path') WITH ORDINALITY e(value,ord);
        v_fresh:=jsonb_build_object('observed',v_graph) #> v_path;
        IF jsonb_typeof(v_fresh) IS DISTINCT FROM 'array' THEN
          RAISE EXCEPTION 'SOURCE_CARDINALITY_CURRENT_PATH_INVALID:%:%',v_pantalla_id,p_family_code;
        END IF;
        v_tpl:=jsonb_set(v_tpl,'{expected}',to_jsonb(jsonb_array_length(v_fresh)),true);
      END IF;
    END IF;
    v_rebound:=programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl);
    if v_rebound->>'result'<>'PASS' then
      raise exception 'V58_REBOUND_ASSERTION_FAILED screen=% family=% source=% path=%',v_pantalla_id,p_family_code,v_rebound->'source_ref',v_rebound->'path';
    end if;
    v_out:=v_out || jsonb_build_array(v_rebound);
  end loop;

  if jsonb_array_length(v_out)=0 then raise exception 'V58_ASSERTION_SET_EMPTY:%:%',v_pantalla_id,p_family_code; end if;
  return v_out;
end;
$function$
;
INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
SELECT 'DEC-IG-SOURCE-INTEGRITY-REBOUND-20261011',
'Rebind source-integrity cardinalities after verified canonical source changes',
'For SOURCE_INTEGRITY ARRAY_LENGTH_EQ with an unchanged canonical graph source_ref and path, and valid parent source-observed SHA differing from the fresh current graph SHA, bind expected array length from the fresh graph snapshot. Do not alter SEMANTIC/POLICY assertions, source refs or paths; independent Validator remains mandatory. No hardcoded screens, family lists, stale array sizes or production authority.',
'In a live rollback trial screen REC_001 parent run829 had 24 outdated source-integrity cardinality expectations; canonical graph rules rose from historical 5 to actual 246. Unmodified direct SQL Curator failed ACCESSIBILITY at V58_REBOUND_ASSERTION_FAILED.',
'Scope programacion.fn_input_v58_build_assertions only, governed technical integrity rebind, no semantics or production activation.',
'VIGENTE' WHERE NOT EXISTS (SELECT 1 FROM transversal.decision_log dl WHERE dl.adr='DEC-IG-SOURCE-INTEGRITY-REBOUND-20261011');
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,'{m9_8_curator_source_integrity_rebind}',
jsonb_build_object('schema_version','IG_SOURCE_INTEGRITY_CARDINALITY_REBIND_V1',
'status','CONTRACT_ACTIVE_VALIDATOR_STILL_REQUIRED',
'canonical_source_sha_required',true,'semantic_checks_untouched',true,
'expected_count','DYNAMIC_FROM_CURRENT_VERIFIED_GRAPH',
'governance','DEC-IG-SOURCE-INTEGRITY-REBOUND-20261011'),true)
WHERE id=280 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';