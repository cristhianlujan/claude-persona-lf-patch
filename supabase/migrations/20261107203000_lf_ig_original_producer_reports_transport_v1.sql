-- LF IG-EVO: capture exactly the Curator/ R1 / R2-R6 / G1 JSON already produced.
-- Reuse existing IG Curator -> Validator -> Perfil, never re-run diagnostics for transport.
-- Never extrapolate source integrity to semantic approval. Not a new orchestration stage.
-- Governance: INPUT GOVERNANCE LF INSTRUCCIONES OPERATIVAS V1.4 sections 5,7,8,9,12,13.
-- EKB: GOV-010 GOV-032 SEC-011 IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015.
BEGIN;

-- A storage receipt, not an extra worker, judge, router or execution path.
CREATE TABLE programacion.input_governance_producer_raw_v1 (
  run_id bigint PRIMARY KEY REFERENCES programacion.input_readiness_runs(id) ON DELETE RESTRICT,
  pantalla_id integer NOT NULL,
  curator_identity text NOT NULL,
  source_snapshot_sha256 text,
  original_curator_output jsonb NOT NULL,
  original_curator_output_sha256 text NOT NULL
    CHECK (original_curator_output_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ig_original_json_object CHECK (jsonb_typeof(original_curator_output)='object'),
  CONSTRAINT ig_original_run_link CHECK (
    (original_curator_output->>'run_id')::bigint IS NOT DISTINCT FROM run_id
  )
);
REVOKE ALL ON programacion.input_governance_producer_raw_v1
  FROM PUBLIC, anon, authenticated, service_role;

-- Read-only, internal and snapshot-bound. A missing historical artifact stays
-- missing; the getter never invokes a detector, graph builder, or Curator.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_producer_raw_read_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion'
AS $raw_get$
DECLARE
 v_run programacion.input_readiness_runs%ROWTYPE;
 v_report programacion.input_governance_producer_raw_v1%ROWTYPE;
 v_pm jsonb;
 v_graph jsonb;
 v_emitted boolean;
BEGIN
 IF p_run_id IS NULL OR p_run_id<1 THEN
   RAISE EXCEPTION 'IG_ORIGINAL_REPORT_RUN_REQUIRED';
 END IF;
 SELECT * INTO v_run FROM programacion.input_readiness_runs WHERE id=p_run_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_RUN_NOT_FOUND:%',p_run_id; END IF;
 IF v_run.invalidated_at IS NOT NULL THEN
   RETURN jsonb_build_object('status','RUN_STALE','run_id',p_run_id,
      'raw_reused',false,'research_reexecuted',false,
      'semantic_pass_authorized',false);
 END IF;
 -- Currentness requires the official check; COMPLETED by itself is not enough.
 -- Checking lineage/currentness is not re-running any R* or Curator analysis.
 IF v_run.status='COMPLETED'
    AND NOT programacion.fn_input_readiness_run_is_current(p_run_id) THEN
   RETURN jsonb_build_object('status','RUN_NOT_CURRENT','run_id',p_run_id,
      'raw_reused',false,'research_reexecuted',false,
      'semantic_pass_authorized',false);
 END IF;
 SELECT * INTO v_report FROM programacion.input_governance_producer_raw_v1
 WHERE run_id=p_run_id;
 IF NOT FOUND THEN
   RETURN jsonb_build_object('status','NOT_CAPTURED_LEGACY_RUN',
     'run_id',p_run_id,'raw_reused',false,'research_reexecuted',false,
     'missing_report_types',jsonb_build_array('CURATOR_ORIGINAL','R1_ORIGINAL',
         'R2_R6_ORIGINAL','G1_ORIGINAL_IF_EMITTED'),
     'semantic_pass_authorized',false);
 END IF;
 IF v_report.pantalla_id IS DISTINCT FROM v_run.pantalla_id
    OR v_report.curator_identity IS DISTINCT FROM v_run.curator_identity
    OR v_report.source_snapshot_sha256 IS DISTINCT FROM v_run.source_snapshot_sha256
    OR v_report.original_curator_output->>'run_id' IS DISTINCT FROM p_run_id::text
    OR v_report.original_curator_output_sha256 IS DISTINCT FROM
       programacion.fn_v09_sha256_jsonb(v_report.original_curator_output)
 THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_INTEGRITY_DRIFT:%',p_run_id; END IF;
 v_pm:=v_report.original_curator_output->'proposal_materialization';
 v_graph:=v_pm->'ig_evo_graph_index';
 v_emitted:=jsonb_typeof(v_pm)='object'
   AND jsonb_typeof(v_pm->'ig_evo_r1_diagnostics')='object'
   AND jsonb_typeof(v_pm->'ig_evo_r2_r6_diagnostics')='object';
 RETURN jsonb_build_object(
   'schema_version','IG_ORIGINAL_PRODUCER_REPORT_TRANSPORT_V1',
   'status',CASE WHEN v_emitted THEN 'ORIGINALS_CAPTURED'
                 ELSE 'PARTIAL_ORIGINALS_NOT_EMITTED' END,
   'run_id',p_run_id,
   'screen_id',v_run.pantalla_id,
   'curator_identity',v_report.curator_identity,
   'raw_report_sha256',v_report.original_curator_output_sha256,
   'source_snapshot_sha256',v_report.source_snapshot_sha256,
   'original_curator_output',v_report.original_curator_output,
   'report_locations',jsonb_build_object(
     'CURATOR','$',
     'R1','$.proposal_materialization.ig_evo_r1_diagnostics',
     'R2_R6','$.proposal_materialization.ig_evo_r2_r6_diagnostics',
     'G1','$.proposal_materialization.ig_evo_graph_index[*].raw_graph'),
   'graph_root_count',v_pm->'ig_evo_graph_total_roots',
   'graph_root_scope',v_pm->'ig_evo_graph_index_status',
   'graph_discovered_root_count',coalesce((v_pm->>'ig_evo_graph_total_roots')::integer,0),
   'graph_captured_root_count',jsonb_array_length(coalesce(v_graph,'[]'::jsonb)),
   'graph_truncated',jsonb_array_length(coalesce(v_graph,'[]'::jsonb))
      < coalesce((v_pm->>'ig_evo_graph_total_roots')::integer,0),
   'raw_reused',true,'research_reexecuted',false,
   'model_has_read_report',false,
   'semantic_quality_evaluated',false,
   'semantic_pass_authorized',false,
   'production_authorized',false);
END;
$raw_get$;
REVOKE ALL ON FUNCTION programacion.fn_input_governance_producer_raw_read_v1(bigint)
  FROM PUBLIC,anon,authenticated,service_role;

-- Modify only currently deployed sources with exact SHA pin, not an alternate
-- Curator/Inspector implementation. Every count and sentinel is fail-closed.
DO $patch$
DECLARE
 v_def text;
 v_new text;
 v_source text;
BEGIN
 SELECT pg_get_functiondef(
 'programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure
 ) INTO v_def;
 IF md5(v_def)<>'9a04278f4a4b7345da88a5ae1d7875e4' THEN
  RAISE EXCEPTION 'IG_ORIGINAL_REPORT_PROPOSAL_WRITER_SOURCE_DRIFT:%',md5(v_def);
 END IF;
 v_new:=replace(v_def,
  $old$      'root_rule_id',g.rule_id,
      'graph_sha256'$old$,
  $new$      'root_rule_id',g.rule_id,
      'raw_graph',g.doc,
      'graph_sha256'$new$);
 IF v_new=v_def OR strpos(v_new,'''raw_graph'',g.doc')=0 THEN
   RAISE EXCEPTION 'IG_ORIGINAL_REPORT_GRAPH_CAPTURE_PATCH_INVALID';
 END IF;
 -- Remove the eight-root sample restriction; process all discovered R6 roots.
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$      order by rule_id limit 8$old$,
   $new$      order by rule_id$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_GRAPH_LIMIT_8_NOT_REMOVED'; END IF;

 -- No fixed upper count; the number captured must exactly equal total roots.
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$    or jsonb_array_length(v_ig_evo_graph_index)>8$old$,
   $new$    or jsonb_array_length(v_ig_evo_graph_index)<>v_ig_evo_graph_total$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_GRAPH_LIMIT_8_GATE_NOT_REMOVED'; END IF;

 -- Scope remains R6-discovered roots, not the entire screen rule universe.
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$'ig_evo_graph_index_status',case when v_ig_evo_graph_total>8 then 'TRUNCATED_SEMANTIC_REVIEW_REQUIRED' else 'PARTIAL_INDEX_NOT_SEMANTIC_PASS' end,$old$,
   $new$'ig_evo_graph_index_status','ALL_R6_DISCOVERED_ROOTS_CAPTURED_NOT_SEMANTIC_PASS',$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_GRAPH_LIMIT_8_STATUS_NOT_REMOVED'; END IF;
 IF strpos(v_new,'order by rule_id limit 8')>0
  OR strpos(v_new,'jsonb_array_length(v_ig_evo_graph_index)>8')>0
  OR strpos(v_new,'TRUNCATED_SEMANTIC_REVIEW_REQUIRED')>0
  OR strpos(v_new,'jsonb_array_length(v_ig_evo_graph_index)<>v_ig_evo_graph_total')=0
 THEN RAISE EXCEPTION 'IG_GRAPH_LIMIT_8_RESIDUAL'; END IF;

 -- pg_get_functiondef omits the terminator on this deployed server.
 -- Preserve the body byte-identically apart from our bounded patches.
 v_new:=rtrim(v_new)||';';
 IF right(btrim(v_new),1)<> ';' THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_GRAPH_SQL_TERMINATOR_MISSING'; END IF;
 EXECUTE v_new;

 SELECT pg_get_functiondef(
 'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
 ) INTO v_def;
 IF md5(v_def)<>'071fdce8c6ac9851e8106afd511fd3fb' THEN
   RAISE EXCEPTION 'IG_ORIGINAL_REPORT_CURATOR_SOURCE_DRIFT:%',md5(v_def);
 END IF;
 v_new:=replace(v_def,
    $old$  v_result jsonb;$old$,
    $new$  v_result jsonb;
  v_full_original_response jsonb;$new$);
 IF v_new=v_def THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_CURATOR_DECLARE_NOT_FOUND'; END IF;
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$  return v_result || jsonb_build_object(
    'performance_observation'$old$,
   $new$  v_full_original_response:=v_result || jsonb_build_object(
    'performance_observation'$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_CURATOR_RETURN_NOT_FOUND'; END IF;
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$  );
exception when others then
  perform set_config('lf.input_curator_family_timings_v1','',true);$old$,
   $new$  );
  IF v_strategy IN ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE') THEN
    INSERT INTO programacion.input_governance_producer_raw_v1(
        run_id,pantalla_id,curator_identity,source_snapshot_sha256,
        original_curator_output,original_curator_output_sha256)
    SELECT v_core_run_id,p_pantalla_id,p_curator_identity,
      r.source_snapshot_sha256,v_full_original_response,
      programacion.fn_v09_sha256_jsonb(v_full_original_response)
    FROM programacion.input_readiness_runs r
    WHERE r.id=v_core_run_id AND r.pantalla_id=p_pantalla_id
      AND r.curator_identity=p_curator_identity;
    IF NOT FOUND THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_CURATOR_CAPTURE_READBACK_MISSING:%',v_core_run_id; END IF;
  END IF;
  RETURN v_full_original_response;
exception when others then
  perform set_config('lf.input_curator_family_timings_v1','',true);$new$);
 IF v_new=v_source OR strpos(v_new,'INSERT INTO programacion.input_governance_producer_raw_v1')=0
 THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_CURATOR_CAPTURE_PATCH_INVALID'; END IF;
 v_new:=rtrim(v_new)||';';
 IF right(btrim(v_new),1)<> ';' THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_CURATOR_SQL_TERMINATOR_MISSING'; END IF;
 EXECUTE v_new;

 SELECT pg_get_functiondef(
 'programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure
 ) INTO v_def;
 IF md5(v_def)<>'ab091d641cc1d3d923d20c0db96d9bc5' THEN
   RAISE EXCEPTION 'IG_ORIGINAL_REPORT_PROFILE_TRANSPORT_SOURCE_DRIFT:%',md5(v_def);
 END IF;
 v_new:=replace(v_def,
  $old$  v_worker jsonb;$old$,
  $new$  v_worker jsonb;
  v_original_reports jsonb;$new$);
 IF v_new=v_def THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_PROFILE_DECLARATION_NOT_FOUND'; END IF;
 v_source:=v_new;
 v_new:=replace(v_new,
  $old$  v_result:=programacion.fn_input_governance_execute(v_pantalla_id,p_consumer);$old$,
  $new$  v_result:=programacion.fn_input_governance_execute(v_pantalla_id,p_consumer);
  IF (v_result->>'run_id') ~ '^[0-9]{1,20}$' THEN
    v_original_reports:=programacion.fn_input_governance_producer_raw_read_v1(
      (v_result->>'run_id')::bigint);
  ELSE
    v_original_reports:=jsonb_build_object(
      'status','RUN_NOT_IDENTIFIED','raw_reused',false,'research_reexecuted',false,
      'semantic_pass_authorized',false);
  END IF;$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_PROFILE_LOOKUP_NOT_FOUND'; END IF;
 v_source:=v_new;
 v_new:=replace(v_new,
  $old$      'governance_result',v_result,$old$,
  $new$      'governance_result',v_result,
      'ig_original_producer_reports',v_original_reports,$new$);
 -- READY, HUMAN_DECISION_REQUIRED and BLOCKED each return the exact envelope.
 IF v_new=v_source OR
    (length(v_source)-length(replace(v_source,'''governance_result'',v_result,','')))
       /length('''governance_result'',v_result,') <> 3
 THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_PROFILE_TRANSPORT_PATCH_INVALID'; END IF;
 v_new:=rtrim(v_new)||';';
 IF right(btrim(v_new),1)<> ';' THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_PROFILE_SQL_TERMINATOR_MISSING'; END IF;
 EXECUTE v_new;
END;
$patch$;

DO $post$
DECLARE v_cur text; v_prop text; v_profile text;
BEGIN
 SELECT pg_get_functiondef('programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure) INTO v_cur;
 SELECT pg_get_functiondef('programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure) INTO v_prop;
 SELECT pg_get_functiondef('programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure) INTO v_profile;
 IF strpos(v_cur,'INSERT INTO programacion.input_governance_producer_raw_v1')=0
 OR strpos(v_prop,'''raw_graph'',g.doc')=0
 OR strpos(v_profile,'''ig_original_producer_reports'',v_original_reports')=0
 THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_NATIVE_TRANSPORT_NOT_INSTALLED'; END IF;
 IF has_function_privilege('anon','programacion.fn_input_governance_producer_raw_read_v1(bigint)'::regprocedure,'EXECUTE')
 OR has_function_privilege('authenticated','programacion.fn_input_governance_producer_raw_read_v1(bigint)'::regprocedure,'EXECUTE')
 OR has_function_privilege('service_role','programacion.fn_input_governance_producer_raw_read_v1(bigint)'::regprocedure,'EXECUTE')
 OR has_table_privilege('anon','programacion.input_governance_producer_raw_v1','SELECT')
 OR has_table_privilege('authenticated','programacion.input_governance_producer_raw_v1','SELECT')
 OR has_table_privilege('service_role','programacion.input_governance_producer_raw_v1','SELECT')
 THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_ACL_UNSAFE'; END IF;
END;
$post$;
COMMIT;
