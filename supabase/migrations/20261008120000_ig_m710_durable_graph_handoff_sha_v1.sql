-- M7.10: bind canonical graph SHA to existing append-only Curator handoff.
-- Preserve exact installed functions and grants; no duplicate transport table.
DO $mig$
DECLARE
  v_name text;
  v_fn oid;
  v_def text;
  v_subject_key text := '''schema_version'',''INPUT_GOVERNANCE_CURATOR_HANDOFF_V1'',';
  v_graph_key text := '''graph_sha256'',programacion.fn_v09_sha256_jsonb(programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id)),';
  v_return_key text;
BEGIN
  IF EXISTS (SELECT 1 FROM programacion.provenance_receipts
             WHERE subject_type='input_governance_curator_handoff') THEN
    RAISE EXCEPTION 'M710_EXISTING_HANDOFF_RECEIPTS_NEED_COMPATIBILITY_REVIEW';
  END IF;
  FOREACH v_name IN ARRAY ARRAY[
    'programacion.fn_input_governance_curator_handoff_receipt_v1(bigint,text)',
    'programacion.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)'
  ] LOOP
    v_fn:=to_regprocedure(v_name);
    IF v_fn IS NULL THEN RAISE EXCEPTION 'M710_MISSING_HANDOFF_FUNCTION:%',v_name; END IF;
    v_def:=pg_get_functiondef(v_fn);
    IF (length(v_def)-length(replace(v_def,v_subject_key,'')))<>length(v_subject_key)
       OR position('''graph_sha256''' IN v_def)>0 THEN
      RAISE EXCEPTION 'M710_HANDOFF_DEFINITION_DRIFT:%',v_name;
    END IF;
    v_def:=replace(v_def,v_subject_key,v_subject_key||E'\n    '||v_graph_key);
    v_return_key:=CASE WHEN v_name LIKE '%curator_handoff_receipt%'
      THEN '''schema_version'',''INPUT_GOVERNANCE_CURATOR_HANDOFF_RECEIPT_V1'','
      ELSE '''schema_version'',''INPUT_GOVERNANCE_VALIDATOR_HANDOFF_ASSERT_V1'',' END;
    IF (length(v_def)-length(replace(v_def,v_return_key,'')))<>length(v_return_key) THEN
      RAISE EXCEPTION 'M710_RETURN_DEFINITION_DRIFT:%',v_name;
    END IF;
    v_def:=replace(v_def,v_return_key,
      v_return_key||E'\n    '||'''graph_sha256'',v_subject->>''graph_sha256'',');
    EXECUTE v_def;
  END LOOP;
  v_fn:=to_regprocedure(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)');
  IF v_fn IS NULL THEN RAISE EXCEPTION 'M710_CURATOR_OWNER_MISSING'; END IF;
  v_def:=pg_get_functiondef(v_fn);
  v_subject_key:='if v_handoff_receipt->>''status'' is distinct from ''PERSISTED''';
  IF (length(v_def)-length(replace(v_def,v_subject_key,'')))<>length(v_subject_key)
    THEN RAISE EXCEPTION 'M710_CURATOR_OWNER_DRIFT'; END IF;
  v_def:=replace(v_def,v_subject_key,
    'if v_handoff_receipt->>''graph_sha256'' is distinct from v_context->>''graph_sha256'' then'||E'\n'||
    '      raise exception ''M710_CONSUMED_GRAPH_SHA_MISMATCH:%'',v_core_run_id;'||E'\n'||
    '    end if;'||E'\n    '||v_subject_key);
  EXECUTE v_def;
END $mig$;
