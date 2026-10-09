-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M6.2 / GRAPH_SHA_RECEIPT
-- Two live recalculations of one canonical graph are anchored with the already-governed
-- M6.2 EVIDENCE_LEDGER execution. No synthetic producer execution is introduced.
DO $m6_2$
DECLARE
  v_run record;
  v_graph_a jsonb;
  v_graph_b jsonb;
  v_sha_a text;
  v_sha_b text;
  v_a jsonb;
  v_b jsonb;
  v_actor constant text := 'EXEC-IG-M6-2-LEDGER-20261007-CGPT-V1';
  v_source_head constant text := 'af6540c5757b39130c92a8ffd7a61d3cd7b8cb58';
BEGIN
  SELECT id,pantalla_id,version_id,source_snapshot_sha256
    INTO v_run
  FROM programacion.input_readiness_runs
  WHERE id=525 AND status='COMPLETED';

  IF v_run.id IS NULL THEN
    RAISE EXCEPTION 'M6_2_RUN_525_NOT_COMPLETED';
  END IF;

  v_graph_a := programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
  v_graph_b := programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
  v_sha_a := programacion.fn_v09_sha256_jsonb(v_graph_a);
  v_sha_b := programacion.fn_v09_sha256_jsonb(v_graph_b);

  IF v_sha_a IS NULL
     OR v_sha_a !~ '^[0-9a-f]{64}$'
     OR v_sha_a IS DISTINCT FROM v_sha_b
     OR v_graph_a IS DISTINCT FROM v_graph_b THEN
    RAISE EXCEPTION 'M6_2_GRAPH_RECALCULATION_NOT_STABLE';
  END IF;

  v_a := public.fn_lf_evidence_ledger_anchor_v1(
    v_actor,
    'EVIDENCE_LEDGER',
    'IG_GRAPH_SHA_RECEIPT',
    'GRAPH_RECEIPT',
    'IG_SCREEN_GRAPH',
    'supabase://programacion.input_readiness_runs/525#canonical_graph/recalc-1',
    v_sha_a,
    v_source_head,
    'supabase://programacion.fn_input_screen_canonical_graph(integer,bigint)',
    'LF_SUPABASE_READBACK_V1',
    'SUPABASE',
    'supabase://programacion.fn_input_screen_canonical_graph(integer,bigint)',
    'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
    'VERIFIED',
    jsonb_build_object(
      'provider_readback_verified',true,
      'digest_recomputed',true,
      'run_id',v_run.id,
      'pantalla_id',v_run.pantalla_id,
      'version_id',v_run.version_id,
      'source_snapshot_sha256',v_run.source_snapshot_sha256,
      'graph_sha256',v_sha_a,
      'recalculation_ordinal',1,
      'stable_pair',true
    ),
    jsonb_build_object(
      'schema_version','IG_SCREEN_GRAPH_RECEIPT_V1',
      'run_id',v_run.id,
      'pantalla_id',v_run.pantalla_id,
      'version_id',v_run.version_id,
      'graph_sha256',v_sha_a,
      'recalculation_ordinal',1,
      'stable_pair',true
    ),
    v_actor
  );

  v_b := public.fn_lf_evidence_ledger_anchor_v1(
    v_actor,
    'EVIDENCE_LEDGER',
    'IG_GRAPH_SHA_RECEIPT',
    'GRAPH_RECEIPT',
    'IG_SCREEN_GRAPH',
    'supabase://programacion.input_readiness_runs/525#canonical_graph/recalc-2',
    v_sha_b,
    v_source_head,
    'supabase://programacion.fn_input_screen_canonical_graph(integer,bigint)',
    'LF_SUPABASE_READBACK_V1',
    'SUPABASE',
    'supabase://programacion.fn_input_screen_canonical_graph(integer,bigint)',
    'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
    'VERIFIED',
    jsonb_build_object(
      'provider_readback_verified',true,
      'digest_recomputed',true,
      'run_id',v_run.id,
      'pantalla_id',v_run.pantalla_id,
      'version_id',v_run.version_id,
      'source_snapshot_sha256',v_run.source_snapshot_sha256,
      'graph_sha256',v_sha_b,
      'recalculation_ordinal',2,
      'stable_pair',true
    ),
    jsonb_build_object(
      'schema_version','IG_SCREEN_GRAPH_RECEIPT_V1',
      'run_id',v_run.id,
      'pantalla_id',v_run.pantalla_id,
      'version_id',v_run.version_id,
      'graph_sha256',v_sha_b,
      'recalculation_ordinal',2,
      'stable_pair',true
    ),
    v_actor
  );

  IF coalesce(v_a->>'receipt_id','')=''
     OR coalesce(v_b->>'receipt_id','')='' THEN
    RAISE EXCEPTION 'M6_2_GRAPH_RECEIPT_NOT_EMITTED';
  END IF;
END
$m6_2$;
