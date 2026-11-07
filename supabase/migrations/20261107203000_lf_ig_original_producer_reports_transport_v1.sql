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
 v_curator_strategy text;
 v_parent_source_sha256 text;
 v_parent_raw_stored boolean := false;
 v_r1_emitted boolean := false;
 v_r2_r6_emitted boolean := false;
 v_g1_emitted boolean := false;
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
 v_curator_strategy:=v_report.original_curator_output#>>'{performance_observation,strategy}';
 v_r1_emitted:=coalesce(jsonb_typeof(v_pm->'ig_evo_r1_diagnostics')='object',false);
 v_r2_r6_emitted:=coalesce(jsonb_typeof(v_pm->'ig_evo_r2_r6_diagnostics')='object',false);
 v_g1_emitted:=coalesce(jsonb_typeof(v_graph)='array',false);
 -- REBIND can invoke FULL_RECURATE internally when the contract changed;
 -- determine what was emitted from the source payload, not a name alone.
 v_emitted:=coalesce(jsonb_typeof(v_pm)='object',false)
   AND v_r1_emitted AND v_r2_r6_emitted AND v_g1_emitted;
 IF v_run.supersedes_run_id IS NOT NULL THEN
   SELECT parent.source_snapshot_sha256 INTO v_parent_source_sha256
     FROM programacion.input_readiness_runs parent
    WHERE parent.id=v_run.supersedes_run_id AND parent.pantalla_id=v_run.pantalla_id;
   SELECT EXISTS(
      SELECT 1 FROM programacion.input_governance_producer_raw_v1 older
       WHERE older.run_id=v_run.supersedes_run_id
         AND older.pantalla_id=v_run.pantalla_id
   ) INTO v_parent_raw_stored;
 END IF;
 RETURN jsonb_build_object(
   'schema_version','IG_ORIGINAL_PRODUCER_REPORT_TRANSPORT_V1',
   'status',CASE WHEN v_emitted THEN 'ORIGINALS_CAPTURED'
                  WHEN v_curator_strategy='REBIND'
                    AND NOT v_r1_emitted AND NOT v_r2_r6_emitted AND NOT v_g1_emitted
                    THEN 'ORIGINALS_NOT_EMITTED_FOR_REBIND'
                  ELSE 'PARTIAL_ORIGINALS_NOT_EMITTED' END,
   'curator_strategy',v_curator_strategy,
   'producer_emission',jsonb_build_object(
      'CURATOR','CAPTURED_AS_EMITTED',
      'R1',CASE WHEN v_r1_emitted THEN 'EMITTED_IN_THIS_RUN'
         WHEN v_curator_strategy='REBIND' THEN 'NOT_EMITTED_FOR_REBIND'
         ELSE 'NOT_EMITTED_IN_THIS_RUN' END,
      'R2_R6',CASE WHEN v_r2_r6_emitted THEN 'EMITTED_IN_THIS_RUN'
         WHEN v_curator_strategy='REBIND' THEN 'NOT_EMITTED_FOR_REBIND'
         ELSE 'NOT_EMITTED_IN_THIS_RUN' END,
      'G1',CASE WHEN v_g1_emitted THEN 'EMITTED_IN_THIS_RUN'
         WHEN v_curator_strategy='REBIND' THEN 'NOT_EMITTED_FOR_REBIND'
         ELSE 'NOT_EMITTED_IN_THIS_RUN' END),
   'source_lineage',jsonb_build_object(
      'parent_run_id',v_run.supersedes_run_id,
      'parent_raw_archive_present',v_parent_raw_stored,
      'parent_source_snapshot_sha256',v_parent_source_sha256,
      'snapshot_equivalence',CASE
        WHEN v_run.supersedes_run_id IS NULL THEN 'NO_PARENT'
        WHEN v_report.source_snapshot_sha256 IS NULL OR v_parent_source_sha256 IS NULL
          THEN 'SOURCE_SNAPSHOT_NOT_ATTESTED'
        WHEN v_report.source_snapshot_sha256=v_parent_source_sha256
          THEN 'SAME_SOURCE_SNAPSHOT_NOT_RUN_EQUIVALENCE'
        ELSE 'SOURCE_SNAPSHOT_CHANGED' END,
      'historical_parent_research_reexecution_required',false,
      'automatic_parent_raw_as_current_run_authorized',false),
   'all_producers_emitted_in_this_run',v_emitted,
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
   'graph_root_scope',v_pm->'ig_evo_graph_index_scope',
   'graph_coverage_status',v_pm->'ig_evo_graph_index_status',
   'graph_eligible_rule_count',coalesce((v_pm->>'ig_evo_graph_total_attested_rules')::integer,0),
   'graph_total_linked_rule_count',coalesce((v_pm->>'ig_evo_graph_total_linked_rules')::integer,0),
   'graph_derived_global_unattested_count',coalesce((v_pm->>'ig_evo_graph_unattested_global_count')::integer,0),
   'graph_derived_global_status',v_pm->'ig_evo_graph_derived_global_status',
   'graph_derived_global_retrieval_ref',v_pm->'ig_evo_graph_derived_global_retrieval_ref',
   'graph_discovered_root_count',coalesce((v_pm->>'ig_evo_graph_total_roots')::integer,0),
   'graph_captured_root_count',jsonb_array_length(coalesce(v_graph,'[]'::jsonb)),
   'graph_internal_truncation_count',coalesce((v_pm->>'ig_evo_graph_internal_truncation_count')::integer,0),
   'graph_internal_truncated_rule_ids',coalesce(v_pm->'ig_evo_graph_internal_truncated_rule_ids','[]'::jsonb),
   'graph_truncated',jsonb_array_length(coalesce(v_graph,'[]'::jsonb))
      < coalesce((v_pm->>'ig_evo_graph_total_roots')::integer,0),
   'raw_reused',true,'research_reexecuted',false,
   'reuse_scope','EXACT_SAME_RUN_ORIGINAL_ARCHIVE_ONLY',
   'historical_raw_as_current_evidence_authorized',false,
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
 -- G1 selection is now independent of R6. Reuse generated raw JSON as-is.
 v_source:=v_new;
 v_new:=replace(v_new,$old_count$  select count(*) into v_ig_evo_graph_total
  from (
    select distinct (c->'source_rule'->>'id')::integer rule_id
    from jsonb_array_elements(coalesce(v_r2_r6_scan->'findings','[]'::jsonb)) f
    cross join lateral jsonb_array_elements(coalesce(f->'cases','[]'::jsonb)) c
    where f->>'detector'='R6'
      and c->'source_rule'->>'id' ~ '^[0-9]{1,9}$'
  ) roots;$old_count$,$new_count$  select count(distinct e.regla_id) into v_ig_evo_graph_total
  from programacion.fn_input_effective_rule_links_v1(v_run.pantalla_id,'INPUT_GOVERNANCE') e
  join lf_ops.reglas rr on rr.id=e.regla_id
  where e.pantalla_id=v_run.pantalla_id
    and e.binding_source<>'DERIVED_GLOBAL'
    and rr.estado in ('VIGENTE','CANDIDATO');$new_count$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_G1_COUNT_SOURCE_MISSING'; END IF;
 v_source:=v_new;
 v_new:=replace(v_new,$old_roots$      select distinct (c->'source_rule'->>'id')::integer rule_id
      from jsonb_array_elements(coalesce(v_r2_r6_scan->'findings','[]'::jsonb)) f
      cross join lateral jsonb_array_elements(coalesce(f->'cases','[]'::jsonb)) c
      where f->>'detector'='R6'
        and c->'source_rule'->>'id' ~ '^[0-9]{1,9}$'
      order by rule_id limit 8$old_roots$,$new_roots$      select distinct e.regla_id AS rule_id
      from programacion.fn_input_effective_rule_links_v1(v_run.pantalla_id,'INPUT_GOVERNANCE') e
      join lf_ops.reglas rr on rr.id=e.regla_id
      where e.pantalla_id=v_run.pantalla_id
        and e.binding_source<>'DERIVED_GLOBAL'
        and rr.estado in ('VIGENTE','CANDIDATO')
      order by rule_id$new_roots$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_G1_ROOT_SOURCE_MISSING'; END IF;

 -- No fixed upper count; captured graphs must equal eligible screen rules.
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$    or jsonb_array_length(v_ig_evo_graph_index)>8$old$,
   $new$    or jsonb_array_length(v_ig_evo_graph_index)<>v_ig_evo_graph_total$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_GRAPH_LIMIT_8_GATE_NOT_REMOVED'; END IF;

 -- G1 covers all canonically effective rules, independent from R6 findings.
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$'ig_evo_graph_index_status',case when v_ig_evo_graph_total>8 then 'TRUNCATED_SEMANTIC_REVIEW_REQUIRED' else 'PARTIAL_INDEX_NOT_SEMANTIC_PASS' end,$old$,
   $new$'ig_evo_graph_index_status','ALL_G1_ATTESTED_SCREEN_RULES_CAPTURED_NOT_SEMANTIC_PASS',$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_G1_STATUS_REBIND_MISSING'; END IF;
 v_source:=v_new;
 v_new:=replace(v_new,$old$'ig_evo_graph_index_scope','R6_DISCOVERED_CASE_ROOTS_ONLY',$old$,
                     $new$'ig_evo_graph_index_scope','ALL_G1_ATTESTED_SCREEN_RULES',$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_G1_SCOPE_REBIND_MISSING'; END IF;
 v_source:=v_new;
 v_new:=replace(v_new,$old$'ig_evo_graph_total_roots',v_ig_evo_graph_total,$old$,
                     $new$'ig_evo_graph_total_roots',v_ig_evo_graph_total,
                       'ig_evo_graph_total_attested_rules',v_ig_evo_graph_total,
                       'ig_evo_graph_captured_rule_count',jsonb_array_length(v_ig_evo_graph_index),$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_G1_METRICS_REBIND_MISSING'; END IF;

 -- DERIVED_GLOBAL links are discoverable as contextual references, but G1
 -- explicitly does not attest them as screen-bound root rules. Account for
 -- their presence instead of claiming that all returned links were analyzed.
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$'ig_evo_graph_total_attested_rules',v_ig_evo_graph_total,$old$,
   $new$'ig_evo_graph_total_attested_rules',v_ig_evo_graph_total,
     'ig_evo_graph_total_linked_rules',(select count(distinct e.regla_id) from programacion.fn_input_effective_rule_links_v1(v_run.pantalla_id,'INPUT_GOVERNANCE') e where e.pantalla_id=v_run.pantalla_id),
     'ig_evo_graph_unattested_global_count',(select count(distinct e.regla_id) from programacion.fn_input_effective_rule_links_v1(v_run.pantalla_id,'INPUT_GOVERNANCE') e where e.pantalla_id=v_run.pantalla_id and e.binding_source='DERIVED_GLOBAL'),
     'ig_evo_graph_derived_global_status','UNATTESTED_SCREEN_APPLICABILITY_NOT_G1_ROOT_ELIGIBLE',
     'ig_evo_graph_derived_global_retrieval_ref','programacion.fn_input_effective_rule_links_v1:DERIVED_GLOBAL',$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_G1_UNATTESTED_GLOBAL_ACCOUNTING_MISSING'; END IF;

 -- A root graph can itself be truncated by its *internal* exploration budget.
 -- Preserve the original graph and mark that loss explicitly, using already
 -- materialized JSON, not a second graph invocation.
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$'ig_evo_graph_captured_rule_count',jsonb_array_length(v_ig_evo_graph_index),$old$,
   $new$'ig_evo_graph_captured_rule_count',jsonb_array_length(v_ig_evo_graph_index),
    'ig_evo_graph_internal_truncation_count',(select count(*) from jsonb_array_elements(v_ig_evo_graph_index) q(value) where q.value->'raw_graph'->>'graph_limit_hit'='true'),
    'ig_evo_graph_internal_truncated_rule_ids',(select coalesce(jsonb_agg((q.value->>'root_rule_id')::integer order by (q.value->>'root_rule_id')::integer),'[]'::jsonb) from jsonb_array_elements(v_ig_evo_graph_index) q(value) where q.value->'raw_graph'->>'graph_limit_hit'='true'),$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_G1_INTERNAL_TRUNCATION_METADATA_MISSING'; END IF;
 v_source:=v_new;
 v_new:=replace(v_new,
   $old$'ig_evo_graph_index_status','ALL_G1_ATTESTED_SCREEN_RULES_CAPTURED_NOT_SEMANTIC_PASS',$old$,
   $new$'ig_evo_graph_index_status',case
        when exists(select 1 from jsonb_array_elements(v_ig_evo_graph_index) g(value)
          where g.value->'raw_graph'->>'graph_limit_hit'='true')
          then 'ALL_G1_ATTESTED_RULE_ROOTS_CAPTURED_WITH_INTERNAL_TRUNCATION'
        else 'ALL_G1_ATTESTED_SCREEN_RULES_CAPTURED_NOT_SEMANTIC_PASS' end,$new$);
 IF v_new=v_source THEN RAISE EXCEPTION 'IG_G1_TRUNCATION_STATUS_MISSING'; END IF;
 IF strpos(v_new,'order by rule_id limit 8')>0
  OR strpos(v_new,'jsonb_array_length(v_ig_evo_graph_index)>8')>0
  OR strpos(v_new,'TRUNCATED_SEMANTIC_REVIEW_REQUIRED')>0
  OR strpos(v_new,'R6_DISCOVERED_CASE_ROOTS_ONLY')>0
  OR strpos(v_new,'select distinct (c->''source_rule''->>''id'')::integer')>0
  OR strpos(v_new,'jsonb_array_length(v_ig_evo_graph_index)<>v_ig_evo_graph_total')=0
  OR strpos(v_new,'ALL_G1_ATTESTED_SCREEN_RULES')=0
  OR strpos(v_new,'ig_evo_graph_total_attested_rules')=0
 THEN RAISE EXCEPTION 'IG_G1_ROOT_SCOPE_RESIDUAL'; END IF;

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
 -- READY/HUMAN_DECISION_REQUIRED/BLOCKED indent differently; match the field
 -- rather than leading whitespace. Gate both original and inserted counts.
 IF (length(v_source)-length(replace(v_source,'''governance_result'',v_result,','')))
       /length('''governance_result'',v_result,') <> 3
 THEN RAISE EXCEPTION 'IG_ORIGINAL_REPORT_PROFILE_BRANCH_COUNT_INVALID'; END IF;
 v_new:=replace(v_new,
  $old$'governance_result',v_result,$old$,
  $new$'governance_result',v_result,
      'ig_original_producer_reports',v_original_reports,$new$);
 IF v_new=v_source OR
    (length(v_new)-length(replace(v_new,'''ig_original_producer_reports'',v_original_reports,','')))
       /length('''ig_original_producer_reports'',v_original_reports,') <> 3
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
 OR strpos(v_prop,'ig_evo_graph_total_attested_rules')=0
 OR strpos(v_prop,'ig_evo_graph_unattested_global_count')=0
 OR strpos(v_prop,'UNATTESTED_SCREEN_APPLICABILITY_NOT_G1_ROOT_ELIGIBLE')=0
 OR strpos(v_prop,'ALL_G1_ATTESTED_SCREEN_RULES')=0
 OR strpos(v_prop,'ALL_G1_ATTESTED_SCREEN_RULES_CAPTURED_NOT_SEMANTIC_PASS')=0
 OR strpos(v_prop,'ALL_G1_ATTESTED_RULE_ROOTS_CAPTURED_WITH_INTERNAL_TRUNCATION')=0
 OR strpos(v_prop,'ig_evo_graph_internal_truncated_rule_ids')=0
 OR strpos(v_prop,'fn_input_effective_rule_links_v1(v_run.pantalla_id')=0
 OR (length(v_profile)-length(replace(v_profile,
     '''ig_original_producer_reports'',v_original_reports,','')))
     /length('''ig_original_producer_reports'',v_original_reports,') <> 3
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
