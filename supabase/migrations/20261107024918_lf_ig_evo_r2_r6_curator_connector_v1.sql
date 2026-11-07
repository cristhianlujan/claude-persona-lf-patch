-- IG-EVO R2-R6 shadow attachment to the native Curator response.
-- Keep 0 new input_gap_proposals until native semantic admission is proven.
-- No change to T_REMED counts, readiness states, Router, rules or policies.
-- SQL migrations 61500 (R1) and 62000 (R2–R6 scanner) are prerequisites.
BEGIN;
DO $patch$
DECLARE
 v_def text; v_orig text;
 v_declare text:='  v_r1_scan jsonb;';
 -- Graph index is bounded diagnostic evidence, never an authority or new writer.
 v_anchor text:=E'  select count(*)\n    into v_close_candidates';
 v_return text:='''ig_evo_proposals_created'',0';
 v_scan text;
BEGIN
 SELECT pg_get_functiondef(
  'programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure)
 INTO v_orig;
 IF v_orig IS NULL
    OR position('IG-EVO R1 shadow' in v_orig)=0
    OR position('v_r1_scan:=programacion.fn_ig_evo_r1_parameter_provenance_v1' in v_orig)=0
    OR position('SHADOW_NON_BLOCKING' in v_orig)=0 THEN
  RAISE EXCEPTION 'IG_EVO_R2_R6_R1_PREREQUISITE_DRIFT';
 END IF;
 IF to_regprocedure('programacion.fn_ig_evo_r2_r6_diagnostics_v1(integer,bigint)') IS NULL THEN
  RAISE EXCEPTION 'IG_EVO_R2_R6_SCANNER_UNAVAILABLE';
 END IF;
 IF to_regprocedure('programacion.fn_ig_evo_rule_graph_inventory_v1(integer,integer,integer)') IS NULL THEN
  RAISE EXCEPTION 'IG_EVO_GRAPH_INVENTORY_UNAVAILABLE';
 END IF;
 IF (length(v_orig)-length(replace(v_orig,v_declare,'')))/length(v_declare)<>1
 OR (length(v_orig)-length(replace(v_orig,v_anchor,'')))/length(v_anchor)<>1
 OR (length(v_orig)-length(replace(v_orig,v_return,'')))/length(v_return)<>1 THEN
  RAISE EXCEPTION 'IG_EVO_R2_R6_CURATOR_UNEXPECTED_SOURCE';
 END IF;
 v_scan:=$scan$
  -- IG-EVO candidate discovery only. Does NOT create or validate proposals.
  v_r2_r6_scan:=programacion.fn_ig_evo_r2_r6_diagnostics_v1(v_run.pantalla_id,p_run_id);
  -- G1: native Curator graph index for bounded R6 source-rule roots only.
  -- Root graph is dynamically discovered on demand; this index is NOT full
  -- rule-universe coverage or a frozen Curator semantic evidence receipt.
  select count(*) into v_ig_evo_graph_total
  from (
    select distinct (c->'source_rule'->>'id')::integer rule_id
    from jsonb_array_elements(coalesce(v_r2_r6_scan->'findings','[]'::jsonb)) f
    cross join lateral jsonb_array_elements(coalesce(f->'cases','[]'::jsonb)) c
    where f->>'detector'='R6'
      and c->'source_rule'->>'id' ~ '^[0-9]{1,9}$'
  ) roots;
  select coalesce(jsonb_agg(jsonb_build_object(
      'root_rule_id',g.rule_id,
      'graph_sha256',programacion.fn_v09_sha256_jsonb(g.doc),
      'graph_schema_version',g.doc->>'schema_version',
      'reference_status',g.doc->>'graph_reference_status',
      'root_explicit_reference_count',g.doc->'root_explicit_reference_count',
      'root_bound_policy_reference_count',g.doc->'root_bound_policy_reference_count',
      'edge_count',jsonb_array_length(coalesce(g.doc->'edges','[]'::jsonb)),
      'narrative_clause_count',jsonb_array_length(coalesce(g.doc->'narrative_clause_inventory','[]'::jsonb)),
      'intent_context_sha256',programacion.fn_v09_sha256_jsonb(g.doc->'intent_context'),
      'semantic_text_signals_status','NOT_TESTED',
      'source_frozen_by_curator',false,
      'semantic_pass_authorized',false,
      'canonical_write_authorized',false)
    order by g.rule_id),'[]'::jsonb)
  into v_ig_evo_graph_index
  from (
    select r.rule_id,
      programacion.fn_ig_evo_rule_graph_inventory_v1(v_run.pantalla_id,r.rule_id,3) doc
    from (
      select distinct (c->'source_rule'->>'id')::integer rule_id
      from jsonb_array_elements(coalesce(v_r2_r6_scan->'findings','[]'::jsonb)) f
      cross join lateral jsonb_array_elements(coalesce(f->'cases','[]'::jsonb)) c
      where f->>'detector'='R6'
        and c->'source_rule'->>'id' ~ '^[0-9]{1,9}$'
      order by rule_id limit 8
    ) r
  ) g;
  if jsonb_typeof(v_ig_evo_graph_index)<>'array'
    or jsonb_array_length(v_ig_evo_graph_index)>8
    or exists (select 1 from jsonb_array_elements(v_ig_evo_graph_index) entry
      where entry->>'canonical_write_authorized'<>'false'
        or entry->>'semantic_pass_authorized'<>'false'
        or entry->>'semantic_text_signals_status'<>'NOT_TESTED') then
    raise exception 'IG_EVO_GRAPH_INDEX_UNSAFE:%',p_run_id;
  end if;


  if v_r2_r6_scan->>'schema_version'<>'IG_EVO_R2_R6_DIAGNOSTICS_V1'
    or (v_r2_r6_scan->>'pantalla_id')::integer is distinct from v_run.pantalla_id
    or (v_r2_r6_scan->>'run_id')::bigint is distinct from p_run_id
    or v_r2_r6_scan->>'canonical_write_authorized'<>'false' then
    raise exception 'IG_EVO_R2_R6_SCAN_CONTRACT_INVALID:%',p_run_id;
  end if;

$scan$;
 v_def:=replace(v_orig,v_declare,v_declare||E'\n  v_r2_r6_scan jsonb;\n  v_ig_evo_graph_index jsonb;\n  v_ig_evo_graph_total integer;');
 v_def:=replace(v_def,v_anchor,v_scan||v_anchor);
 v_def:=replace(v_def,v_return,
   '''ig_evo_graph_index'',v_ig_evo_graph_index,'||E'\n    '||
   '''ig_evo_graph_index_scope'',''R6_DISCOVERED_CASE_ROOTS_ONLY'','||E'\n    '||
   '''ig_evo_graph_total_roots'',v_ig_evo_graph_total,'||E'\n    '||
   '''ig_evo_graph_index_status'',case when v_ig_evo_graph_total>8 then ''TRUNCATED_SEMANTIC_REVIEW_REQUIRED'' else ''PARTIAL_INDEX_NOT_SEMANTIC_PASS'' end,'||E'\n    '||
   '''ig_evo_r2_r6_diagnostics'',v_r2_r6_scan,'||E'\n    '||v_return);
 IF v_def=v_orig THEN RAISE EXCEPTION 'IG_EVO_R2_R6_PATCH_NOOP'; END IF;
 -- Required semicolon after pg_get_functiondef generated DDL.
 EXECUTE rtrim(v_def,';'||E'\n')||';';
END $patch$;

DO $post$
DECLARE v_doc jsonb; v_fn text;
BEGIN
 v_doc:=programacion.fn_ig_evo_r2_r6_diagnostics_v1(51,949);
 IF v_doc->>'schema_version'<>'IG_EVO_R2_R6_DIAGNOSTICS_V1'
    OR jsonb_typeof(v_doc->'findings')<>'array'
    OR v_doc->>'canonical_write_authorized'<>'false' THEN
  RAISE EXCEPTION 'IG_EVO_R2_R6_SCAN_SHAPE_INVALID';
 END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_doc->'findings') f
    WHERE f->>'detector'='R2') THEN
  RAISE EXCEPTION 'IG_EVO_R2_TEMPORARY_IP_FALSE_POSITIVE';
 END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_doc->'findings') f
    WHERE f->>'auto_apply'<>'false' OR f->>'semantic_pass_authorized'<>'false') THEN
  RAISE EXCEPTION 'IG_EVO_R2_R6_UNAUTHORIZED_PROMOTION';
 END IF;
 SELECT pg_get_functiondef(
  'programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure)
 INTO v_fn;
 IF position('fn_ig_evo_r1_parameter_provenance_v1' in v_fn)=0
 OR position('fn_ig_evo_r2_r6_diagnostics_v1' in v_fn)=0
 OR position('ig_evo_r2_r6_diagnostics' in v_fn)=0
 OR position('fn_ig_evo_rule_graph_inventory_v1' in v_fn)=0
 OR position('ig_evo_graph_index' in v_fn)=0
 OR position('SHADOW_NON_BLOCKING' in v_fn)=0 THEN
  RAISE EXCEPTION 'IG_EVO_CURATOR_DIAGNOSTICS_NOT_CONNECTED';
 END IF;
END $post$;
COMMIT;
