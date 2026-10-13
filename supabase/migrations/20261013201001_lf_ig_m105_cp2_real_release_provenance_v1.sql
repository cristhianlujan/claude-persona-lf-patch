-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.5 / CP2 only.
-- Readback contract repair. Never creates vNext, invokes Edge, closes CP2
-- or reclassifies an operational E2E test as a sandbox-only PASS.
DO $m105_cp2$
DECLARE
  v_plan CONSTANT text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit CONSTANT text := 'M10.5';
  v_query text;
  v_meta jsonb;
  v_old jsonb;
  v_test_path CONSTANT text :=
    'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_5/new_runs_vnext.py';
  v_probe jsonb;
  v_pre jsonb;
  v_post jsonb;
  v_ready jsonb;
  v_count integer;
BEGIN
  v_pre := programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_pre->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_pre#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NEW_RUNS_VNEXT'
    OR v_pre#>>'{state,progress_pct}'::numeric IS DISTINCT FROM 15::numeric
  THEN RAISE EXCEPTION 'M105_CP2_BOOTSTRAP_PRESTATE_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=477 AND checkpoint_code='POST_CUTOVER_ASIS' AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=477 AND checkpoint_code<>'POST_CUTOVER_ASIS' AND status='PENDING')<>5
  THEN RAISE EXCEPTION 'M105_CP2_CHECKPOINT_PRESTATE_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_meta FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=477 FOR UPDATE;
  v_old:=v_meta#>'{action_specs_v1,NEW_RUNS_VNEXT}';
  IF v_old->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
    OR v_old#>>'{test_execution_contract,test_path}' IS DISTINCT FROM v_test_path
    OR v_meta#>>'{m105_scope_v1,schema_version}' IS DISTINCT FROM 'M105_SCOPE_SNAPSHOT_V1'
  THEN RAISE EXCEPTION 'M105_CP2_CONTRACT_PRESTATE_DRIFT'; END IF;

  -- Live database is the producer of these values. The Python file is
  -- only a bounded predicate consumer; unauthenticated fixture JSON is not
  -- a provider-bound receipt and cannot authorize the assertion recorder.
  v_query:=$q$
WITH cohort AS (
  SELECT jsonb_array_elements_text(unit_metadata#>'{m105_scope_v1,screen_ids}')::integer AS pantalla_id
  FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5'
), binding AS (
  SELECT capability_code,version,previous_version,manifest_sha256,promoted_at
  FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE'
), latest AS (
  SELECT c.pantalla_id,r.id AS run_id,r.created_at,r.status,r.family_count,
         r.scope,r.source_manifest,r.curator_identity,r.validator_identity
  FROM cohort c LEFT JOIN LATERAL (
    SELECT id,created_at,status,family_count,scope,source_manifest,
           curator_identity,validator_identity
    FROM programacion.input_readiness_runs
    WHERE pantalla_id=c.pantalla_id ORDER BY id DESC LIMIT 1
  ) r ON true
), checked AS (
  SELECT l.*,b.version,b.previous_version,b.manifest_sha256,b.promoted_at,
    CASE WHEN l.run_id IS NULL THEN false
         ELSE programacion.fn_input_run_is_source_current(l.run_id) END AS source_is_current,
    (SELECT count(*) FROM programacion.input_family_assessments a
     WHERE a.run_id=l.run_id AND a.validator_outcome IS NOT NULL) AS assessed_families,
    EXISTS(SELECT 1 FROM programacion.provenance_receipts pr
      WHERE pr.receipt_kind='EVIDENCE_VERIFICATION'
        AND pr.issuer_channel='EVIDENCE_VERIFIER_V1'
        AND pr.subject_ref='input-readiness-run:'||l.run_id
        AND pr.payload->>'runtime'='input-governance-agent-v1'
        AND pr.payload->>'release_id'=b.version
        AND pr.receipt_sha256 ~ '^[a-f0-9]{64}$') AS real_edge_agent_receipt
  FROM latest l CROSS JOIN binding b
)
SELECT jsonb_build_object(
  'schema_version','IG_M105_CP2_RELEASE_READBACK_V1',
  'scope_origin','M105_SCOPE_SNAPSHOT_V1',
  'readback_provider','SUPABASE_CANONICAL_READONLY',
  'source_kind','LIVE_DB_QUERY',
  'current_release',max(version),
  'previous_release',max(previous_version),
  'current_manifest_sha256',max(manifest_sha256),
  'cohort_count',count(*),
  'fresh_completed_count',count(*) FILTER (
    WHERE status='COMPLETED' AND previous_version IS NOT NULL
      AND created_at > promoted_at),
  'release_bound_count',count(*) FILTER (
    WHERE previous_version IS NOT NULL
      AND scope->>'release_id'=version
      AND source_manifest->>'release_id'=version
      AND scope->>'release_manifest_sha256'=manifest_sha256
      AND source_manifest->>'release_manifest_sha256'=manifest_sha256),
  'source_current_count',count(*) FILTER (WHERE source_is_current),
  'validator_assessed_count',count(*) FILTER (
    WHERE family_count>0 AND assessed_families=family_count
      AND validator_identity IS NOT NULL),
  'edge_identity_count',count(*) FILTER (
    WHERE curator_identity LIKE 'INPUT_CURATOR:EDGE:%'
      AND validator_identity LIKE 'INPUT_VALIDATOR:EDGE:%'),
  'edge_provenance_receipt_count',count(*) FILTER (WHERE real_edge_agent_receipt)
) AS readback
FROM checked
$q$;

  v_meta:=jsonb_set(v_meta,
    '{action_specs_v1,NEW_RUNS_VNEXT,verification_queries}',jsonb_build_array(v_query),true);
  v_meta:=jsonb_set(v_meta,
    '{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,declared_queries}',
    jsonb_build_array(v_query),true);
  v_meta:=jsonb_set(v_meta,
    '{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,declared_objects}',
    jsonb_build_array('programacion.engineering_plan_units',
      'programacion.input_readiness_runs','programacion.input_family_assessments',
      'programacion.provenance_receipts','public.lf_capability_current',
      'programacion.fn_input_run_is_source_current'),true);
  v_meta:=jsonb_set(v_meta,
    '{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}',
    jsonb_build_array('programacion.engineering_plan_units',
      'programacion.input_readiness_runs','programacion.input_family_assessments',
      'programacion.provenance_receipts','public.lf_capability_current'),true);
  v_meta:=jsonb_set(v_meta,
    '{action_specs_v1,NEW_RUNS_VNEXT,expected}',
    to_jsonb('13 fresh COMPLETED source-current run IDs, exact vNext release+manifest on each run, 13 validator-complete, 13 genuinely Edge-sourced, 13 verified Agent provenance receipts; otherwise FAIL CLOSED'::text),true);
  v_meta:=jsonb_set(v_meta,
    '{action_specs_v1,NEW_RUNS_VNEXT,test_scope_contract,proof_phase}',
    '"OPERATIONAL_POST_CUTOVER_NOT_SANDBOX_DRILL"'::jsonb,true);
  v_meta:=jsonb_set(v_meta,
    '{action_specs_v1,NEW_RUNS_VNEXT,assertion_contract,pass_when}',
    jsonb_build_object('test_passed',true,'test_exit_code',0,
       'semantic_authority_bound',true,'post_cutover_real_vnext',true,
       'release_bound_count',13,'edge_verified_count',13),true);
  v_meta:=jsonb_set(v_meta,
    '{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,queries}',
    jsonb_build_array(v_query),true);
  v_meta:=jsonb_set(v_meta,
    '{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,db_objects}',
    jsonb_build_array('programacion.engineering_plan_units',
      'programacion.input_readiness_runs','programacion.input_family_assessments',
      'programacion.provenance_receipts','public.lf_capability_current'),true);
  v_meta:=jsonb_set(v_meta,'{m105_cp2_producer_gap_v1}',
    jsonb_build_object(
      'status','TEST_AUTHORED_PRODUCER_STILL_MISSING',
      'real_release_candidate_state','NOT_VERIFIED',
      'source','SUPABASE_CANONICAL_READONLY',
      'required','13 RUN_ID+RELEASE_ID+MANIFEST_SHA+ACTUAL_EDGE+EVIDENCE_VERIFIER receipts',
      'publisher','OPERATIONAL_RELEASE_CUTOVER_NOT_ENABLED_BY_THIS_REPAIR',
      'self_test_is_not_pass',true,'cutover_must_remain_unchanged',true),true);

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=v_meta
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=477;

  EXECUTE v_query INTO v_probe;
  IF v_probe->>'schema_version' IS DISTINCT FROM 'IG_M105_CP2_RELEASE_READBACK_V1'
    OR v_probe->>'cohort_count' IS DISTINCT FROM '13'
  THEN RAISE EXCEPTION 'M105_CP2_READBACK_SCOPE_BROKEN:%',v_probe; END IF;

  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(
    v_plan,v_unit,'NEW_RUNS_VNEXT');
  IF v_ready->>'status' IS DISTINCT FROM 'READY'
  THEN RAISE EXCEPTION 'M105_CP2_PACKET_NOT_READY:%',v_ready; END IF;

  v_post:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_post->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_post#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NEW_RUNS_VNEXT'
    OR v_post#>>'{state,progress_pct}'::numeric IS DISTINCT FROM 15::numeric
  THEN RAISE EXCEPTION 'M105_CP2_PREMATURE_DONE_OR_BOOTSTRAP_DRIFT'; END IF;
END
$m105_cp2$;

INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,
  source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT
 'IG-M105-CP2-READINESS-WITHOUT-PROVENANCE-002','INPUT_GOVERNANCE',
 'M10.5 CP2 READY compiler falsely suggests E2E producer exists',
 'NEW_RUNS_VNEXT had generic last-20-run queries and a test path absent from Git. Current registry holds only INPUT_GOVERNANCE 1.0.0, with no authentic release-bound vNext runs. scope.runtime does not prove Edge execution when runtime identities are SQL.',
 'Action spec compilation checks file/query shape, not existence of a release candidate, exact run-to-release provenance, real Edge actor receipts, or complete 13-screen post-cutover results.',
 'Before a post-cutover checkpoint, freeze the cohort and exact release/manifest identity; verify run freshness, source currentness, full validator coverage, Edge identities AND independently issued agent receipts. A local test predicate passing on JSON is NOT canonical proof; require original provider evidence and canonical assertion before DONE. Do not downgrade operational post-cutover to a sandbox drill.',
 'Migration binds exact provider readback and preserves CP2 PENDING with M10.5 15 percent; Git test artifact includes 11 logic assertions (local only), live run must fail until real release and Edge evidence exist.',
 'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5/NEW_RUNS_VNEXT;github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m10_5/new_runs_vnext.py',
 'programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
 'ACTIVO','CONTRACT_PREFLIGHT',ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS (
 SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M105-CP2-READINESS-WITHOUT-PROVENANCE-002'
);
