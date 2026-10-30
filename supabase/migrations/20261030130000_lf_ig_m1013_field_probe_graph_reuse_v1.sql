-- IG M10.13: use the supplied canonical graph in two existing field probes.
-- Preserve existing runtime consumers. CP3 remains pending.
BEGIN;
DO $repair$
DECLARE
  ident text := 'programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)';
  old_call text := 'programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id)';
  new_call text := 'programacion.fn_input_governance_field_reference_probe_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph)';
  source_sql text;
  source_body text;
  h text;
  blob jsonb;
  items jsonb;
  new_items jsonb;
  graph jsonb;
  rec record;
  n int;
BEGIN
  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
    THEN RAISE EXCEPTION 'IG_CP3_STATE_CHANGED'; END IF;
  SELECT pg_get_functiondef(p.oid),p.prosrc INTO source_sql,source_body
    FROM pg_proc p WHERE p.oid=to_regprocedure(ident);
  IF md5(source_body)<>'8ab045c21218f92ade1f3a6ee017e32b'
     OR length(source_body)-length(replace(source_body,old_call,''))<>2*length(old_call)
    THEN RAISE EXCEPTION 'IG_SOURCE_CHANGED'; END IF;
  EXECUTE replace(source_sql,old_call,new_call);
  SELECT md5(prosrc) INTO h FROM pg_proc WHERE oid=to_regprocedure(ident);
  FOR rec IN SELECT * FROM (VALUES
      (43,19::bigint,'FIELDS'),(43,19::bigint,'VALIDATIONS'),
      (2,19::bigint,'FIELDS'),(2,19::bigint,'VALIDATIONS')
    ) t(screen_id,version_id,family) LOOP
    graph:=programacion.fn_input_screen_canonical_graph(rec.screen_id,rec.version_id);
    IF programacion.fn_input_governance_semantic_probe_v3_ctx(rec.screen_id,rec.family,rec.version_id,graph)
      IS DISTINCT FROM
       programacion.fn_input_governance_semantic_probe_v3_cached_v1(rec.screen_id,rec.family,rec.version_id,graph)
      THEN RAISE EXCEPTION 'IG_SEMANTIC_PARITY_FAILED'; END IF;
  END LOOP;
  SELECT unit_metadata INTO blob FROM programacion.engineering_plan_units
    WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13' FOR UPDATE;
  items:=blob->'cp3_current_caller_classifications_v1';
  SELECT count(*) INTO n FROM jsonb_array_elements(items) x
    WHERE x->>'signature'=ident AND x->>'source_md5'='2eec94aaeafcd10ac38519d1ca0d53b0'
      AND x->>'cleanup_action'='RETAIN_CURRENT';
  IF n<>1 THEN RAISE EXCEPTION 'IG_SOURCE_CLASSIFICATION_DRIFT'; END IF;
  SELECT jsonb_agg(CASE WHEN x->>'signature'=ident
    THEN jsonb_set(x,'{source_md5}',to_jsonb(h),false) ELSE x END ORDER BY ord)
    INTO new_items FROM jsonb_array_elements(items) WITH ORDINALITY t(x,ord);
  UPDATE programacion.engineering_plan_units SET
    unit_metadata=jsonb_set(
      jsonb_set(unit_metadata,'{cp3_current_caller_classifications_v1}',new_items,false),
      '{cp3_field_graph_reuse_readback_v1}',
      jsonb_build_object('source_md5',h,'checked_cases',4,
          'outputs_equal',true,'retirement_authorized',false),true)
    WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND unit_code='M10.13' AND unit_metadata=blob;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>1 THEN RAISE EXCEPTION 'IG_LEDGER_READBACK_FAILED'; END IF;
END
$repair$;
COMMIT;
