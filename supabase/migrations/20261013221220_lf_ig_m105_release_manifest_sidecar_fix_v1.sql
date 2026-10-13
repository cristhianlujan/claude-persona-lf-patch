-- IG/M10.5 CP2 only: source_manifest is immutable array; release bound via attested sidecar.
DO $fix$
DECLARE md jsonb; oldq text; newq text; probe jsonb;
BEGIN
 SELECT unit_metadata INTO STRICT md FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' AND work_item_id=477 FOR UPDATE;
 oldq:=md#>>'{action_specs_v1,NEW_RUNS_VNEXT,verification_queries,0}';
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=477
  AND checkpoint_code='NEW_RUNS_VNEXT')<>'PENDING'
 OR md#>>'{m105_cp2_producer_gap_v1,status}'<>'TEST_AUTHORED_PRODUCER_STILL_MISSING'
 OR oldq NOT LIKE '%source_manifest->>''release_id''=version%'
 OR (SELECT jsonb_typeof(source_manifest) FROM programacion.input_readiness_runs WHERE id=930)<>'array'
 THEN RAISE EXCEPTION 'M105_CP2_PRESTATE_DRIFT'; END IF;
 newq:=replace(oldq,
 $old$    EXISTS(SELECT 1 FROM programacion.provenance_receipts pr
      WHERE pr.receipt_kind='EVIDENCE_VERIFICATION'$old$,
 $new$    EXISTS(SELECT 1 FROM programacion.provenance_receipts pr
      WHERE pr.receipt_kind='EVIDENCE_VERIFICATION'
        AND pr.issuer_channel='EVIDENCE_VERIFIER_V1'
        AND pr.subject_type='IG_RELEASE_RUN_BINDING'
        AND pr.subject_ref='input-readiness-run:'||l.run_id
        AND pr.payload->>'verification_status'='VERIFIED'
        AND pr.payload->>'release_id'=b.version
        AND pr.payload->>'release_manifest_sha256'=b.manifest_sha256
        AND pr.payload->>'run_id'=l.run_id::text
        AND pr.payload->>'pantalla_id'=l.pantalla_id::text
        AND pr.payload->>'head_sha'=pr.head_sha
        AND pr.subject_sha256 ~ '^[a-f0-9]{64}$'
        AND pr.receipt_sha256 ~ '^[a-f0-9]{64}$') AS verified_release_receipt,
    EXISTS(SELECT 1 FROM programacion.provenance_receipts pr
      WHERE pr.receipt_kind='EVIDENCE_VERIFICATION'$new$);
 newq:=replace(newq,
 $old$      AND scope->>'release_id'=version
      AND source_manifest->>'release_id'=version
      AND scope->>'release_manifest_sha256'=manifest_sha256
      AND source_manifest->>'release_manifest_sha256'=manifest_sha256$old$,
 $new$      AND verified_release_receipt$new$);
 IF newq=oldq OR newq NOT LIKE '%AS verified_release_receipt%' OR
    newq LIKE '%source_manifest->>''release_id''%' THEN
    RAISE EXCEPTION 'M105_CP2_REPLACEMENT_FAILED'; END IF;
 EXECUTE newq INTO probe;
 IF probe->>'cohort_count'<>'13' OR probe->>'release_bound_count'<>'0'
 OR probe->>'edge_provenance_receipt_count'<>'0' THEN
   RAISE EXCEPTION 'M105_CP2_UNEXPECTED_READBACK:%',probe; END IF;
 md:=jsonb_set(md,'{action_specs_v1,NEW_RUNS_VNEXT,verification_queries}',jsonb_build_array(newq),true);
 md:=jsonb_set(md,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,declared_queries}',jsonb_build_array(newq),true);
 md:=jsonb_set(md,'{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,queries}',jsonb_build_array(newq),true);
 md:=jsonb_set(md,'{m105_cp2_release_transport_v2}',jsonb_build_object(
 'source_manifest_type','IMMUTABLE_ARRAY_OF_SOURCE_RECEIPTS',
 'release_binding_transport','IG_RELEASE_RUN_BINDING_EVIDENCE_VERIFIER_V1',
 'verified_producer_present',false,'runtime_activation',false),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=md
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' AND work_item_id=477;
 IF (SELECT unit_metadata#>>'{action_specs_v1,NEW_RUNS_VNEXT,verification_queries,0}'
     FROM programacion.engineering_plan_units
     WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5') IS DISTINCT FROM newq
 THEN RAISE EXCEPTION 'M105_CP2_READBACK_MISMATCH'; END IF;
END $fix$;
INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT 'IG-M105-ARRAY-SOURCE-MANIFEST-RELEASE-BINDING-003','INPUT_GOVERNANCE',
'M10.5 CP2 source_manifest array vs release identity',
'The immutable source manifest of run 930 is a 9-element JSON array, not a release object.',
'CP2 confused source manifest receipts with post-cutover release provenance.',
'Use independent verified IG_RELEASE_RUN_BINDING receipt keyed by run_id, pantalla, release and manifest SHA. Do not rewrite legacy or infer Edge from scope.runtime.',
'Read-only live query 13 cohort, zero verified vNext, zero verified Edge. CP2 remains PENDING; no promotion.',
'supabase://programacion.input_readiness_runs/930',
'programacion.engineering_plan_units/M10.5/CP2','IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
'ACTIVO','CONTRACT_PREFLIGHT',ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge WHERE codigo='IG-M105-ARRAY-SOURCE-MANIFEST-RELEASE-BINDING-003');

-- M105_COHORT_EVIDENCE_V3: no activation, no checkpoint transition and no family policy weakening.

-- M10.5 unified, read-only evidence projection. One frozen cohort, one release,
-- one latest-run identity per screen. Does not execute, promote or admit a release.
CREATE OR REPLACE VIEW programacion.v_ig_m105_cohort_evidence_v1 WITH (security_invoker=true) AS
WITH cohort AS (
 SELECT jsonb_array_elements_text(u.unit_metadata#>'{m105_scope_v1,screen_ids}')::integer pantalla_id
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.5'
), binding AS (
 SELECT version,previous_version,manifest_sha256,promoted_at
 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE'
), latest AS (
 SELECT c.pantalla_id,r.id run_id,r.status run_status,r.created_at,
        r.family_count,r.curator_identity,r.validator_identity
 FROM cohort c LEFT JOIN LATERAL (
  SELECT id,status,created_at,family_count,curator_identity,validator_identity
  FROM programacion.input_readiness_runs WHERE pantalla_id=c.pantalla_id
  ORDER BY id DESC LIMIT 1
 ) r ON true
)
SELECT l.pantalla_id,l.run_id,l.run_status,l.created_at,l.family_count,
 b.version release_version,b.previous_version,b.manifest_sha256 release_manifest_sha256,
 (l.run_id IS NOT NULL AND l.run_status='COMPLETED' AND b.previous_version IS NOT NULL
  AND b.version IS DISTINCT FROM b.previous_version AND l.created_at>b.promoted_at) fresh_vnext,
 CASE WHEN l.run_id IS NOT NULL THEN programacion.fn_input_run_is_source_current(l.run_id) ELSE false END source_current,
 (l.curator_identity LIKE 'INPUT_CURATOR:EDGE:%'
  AND l.validator_identity LIKE 'INPUT_VALIDATOR:EDGE:%') edge_identities,
 EXISTS(SELECT 1 FROM programacion.provenance_receipts pr
  WHERE pr.subject_type='IG_RELEASE_RUN_BINDING' AND pr.receipt_kind='EVIDENCE_VERIFICATION'
   AND pr.issuer_channel='EVIDENCE_VERIFIER_V1' AND pr.payload->>'verification_status'='VERIFIED'
   AND pr.subject_ref='input-readiness-run:'||l.run_id
   AND pr.payload->>'run_id'=l.run_id::text
   AND pr.payload->>'pantalla_id'=l.pantalla_id::text
   AND pr.payload->>'release_id'=b.version
   AND pr.payload->>'release_manifest_sha256'=b.manifest_sha256
   AND pr.payload->>'head_sha'=pr.head_sha
   AND pr.receipt_sha256 ~ '^[0-9a-f]{64}$' AND pr.subject_sha256 ~ '^[0-9a-f]{64}$'
   AND pr.created_at>=l.created_at) release_bound,
 EXISTS(SELECT 1 FROM programacion.provenance_receipts pr
  WHERE pr.receipt_kind='EVIDENCE_VERIFICATION' AND pr.issuer_channel='EVIDENCE_VERIFIER_V1'
   AND pr.subject_ref='input-readiness-run:'||l.run_id
   AND pr.payload->>'runtime'='input-governance-agent-v1'
   AND pr.payload->>'verification_status'='VERIFIED'
   AND pr.payload->>'release_id'=b.version
   AND pr.receipt_sha256 ~ '^[0-9a-f]{64}$') agent_edge_receipt,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=l.run_id) family_rows,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=l.run_id AND a.validator_outcome IS NOT NULL) assessed_rows,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=l.run_id
    AND a.applicability IS NOT NULL AND a.coverage_status IS NOT NULL
    AND jsonb_typeof(a.validator_findings)='array') classifiable_rows,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=l.run_id
    AND a.coverage_status IN ('MISSING','PARTIAL')) observations,
 (SELECT count(*) FROM programacion.input_family_assessments a WHERE a.run_id=l.run_id
    AND a.validator_outcome='FAIL') validator_failures,
 (SELECT (pr.payload->>'elapsed_ms')::numeric FROM programacion.provenance_receipts pr
  WHERE pr.subject_type='IG_PERFORMANCE_TIMING'
    AND pr.receipt_kind='EVIDENCE_VERIFICATION' AND pr.issuer_channel='EVIDENCE_VERIFIER_V1'
    AND pr.subject_ref='input-readiness-run:'||l.run_id
    AND pr.payload->>'schema_version'='IG_PERFORMANCE_TIMING_RECEIPT_V1'
    AND pr.payload->>'phase'='VALIDATOR'
    AND pr.payload->>'run_id'=l.run_id::text
    AND pr.payload->>'verification_status'='VERIFIED'
    AND pr.payload->>'measurement_method'='CLOCK_TIMESTAMP_OBSERVED'
    AND pr.payload->>'elapsed_ms' ~ '^[0-9]+$'
    AND pr.receipt_sha256 ~ '^[0-9a-f]{64}$'
  ORDER BY pr.id DESC LIMIT 1) validator_elapsed_ms
FROM latest l CROSS JOIN binding b;
DO $m105v3$
DECLARE m jsonb; wd bigint; c text; q text; prev text; n integer:=0; proof jsonb;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT wd,m
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' FOR UPDATE;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=wd)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=wd AND status='DONE')<>1
 OR (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=wd AND checkpoint_code='NEW_RUNS_VNEXT')<>'PENDING'
 THEN RAISE EXCEPTION 'M105_V3_CURRENTNESS_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.v_ig_m105_cohort_evidence_v1)<>13
 OR (SELECT count(*) FROM programacion.v_ig_m105_cohort_evidence_v1 WHERE release_bound OR agent_edge_receipt)<>0
 THEN RAISE EXCEPTION 'M105_V3_LIVE_PRESTATE_UNEXPECTED'; END IF;

 c:='NEW_RUNS_VNEXT'; q:=$cpquery_0$SELECT jsonb_build_object(
'schema_version','IG_M105_CP2_RELEASE_READBACK_V1',
'scope_origin','M105_SCOPE_SNAPSHOT_V1',
'readback_provider','SUPABASE_CANONICAL_READONLY',
'source_kind','LIVE_DB_QUERY',
'current_release',max(release_version),'previous_release',max(previous_version),
'current_manifest_sha256',max(release_manifest_sha256),
'cohort_count',count(*),
'fresh_completed_count',count(*) FILTER(WHERE fresh_vnext),
'release_bound_count',count(*) FILTER(WHERE release_bound),
'source_current_count',count(*) FILTER(WHERE source_current),
'validator_assessed_count',count(*) FILTER(WHERE family_count>0 AND family_rows=family_count AND assessed_rows=family_count),
'edge_identity_count',count(*) FILTER(WHERE edge_identities),
'edge_provenance_receipt_count',count(*) FILTER(WHERE agent_edge_receipt),
'family_classification_count',count(*) FILTER(WHERE family_count>0 AND classifiable_rows=family_count),
'family_observations_recorded',coalesce(sum(observations),0),
'not_a_production_authorization',true
) AS readback FROM programacion.v_ig_m105_cohort_evidence_v1$cpquery_0$;
 prev:=m#>>ARRAY['action_specs_v1',c,'verification_queries','0'];
 IF prev IS NULL OR prev='' THEN RAISE EXCEPTION 'M105_V3_UNBOUND_CHECKPOINT:%',c; END IF;
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'verification_queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'expected'],to_jsonb('13 genuine vNext runs with independent release binding, source currentness, verified Edge identities/receipts, classified assessments; observation count reported, not silently green'::text),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],
 coalesce(m#>ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'target','declared_objects'],
 coalesce(m#>ARRAY['action_specs_v1',c,'target','declared_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 IF c IN ('NEW_RUNS_VNEXT','NEG_STALE_RUN') THEN
  m:=jsonb_set(m,ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],
  coalesce(m#>ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],'[]'::jsonb)
  || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 END IF;
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'test_execution_contract','declared_queries'],jsonb_build_array(q),true);
 n:=n+1;


 c:='SUITE_M7_GREEN'; q:=$cpquery_1$WITH cohort AS (
 SELECT * FROM programacion.v_ig_m105_cohort_evidence_v1
), eligible_suite AS (
 SELECT s.suite_run_id,s.commit_sha,s.metadata,s.tests_total,s.tests_passed
 FROM public.lf_test_suite_runs s
 WHERE s.suite_code='INPUT_GOVERNANCE_REGRESSION' AND s.status='PASSED'
  AND s.commit_sha ~ '^[0-9a-f]{40}$' AND s.tests_total>=(SELECT count(*) FROM cohort)
  AND s.tests_total=s.tests_passed AND s.tests_failed=0 AND s.tests_blocked=0
  AND s.metadata->>'full_catalog_evaluated'='true'
  AND s.metadata->>'source_manifest_sha256'=(SELECT max(release_manifest_sha256) FROM cohort)
  AND s.metadata->>'source_version'='INPUT_GOVERNANCE@'||(SELECT max(release_version) FROM cohort)
  AND jsonb_typeof(s.metadata->'run_ids')='array'
), candidates AS (
 SELECT s.suite_run_id,
 (SELECT count(DISTINCT (CASE WHEN value ~ '^[0-9]+$' THEN value::bigint END))
  FROM jsonb_array_elements_text(s.metadata->'run_ids') x(value)) suite_run_count,
 (SELECT count(*) FROM cohort v WHERE NOT EXISTS(
  SELECT 1 FROM public.lf_test_runs t
  WHERE t.suite_run_id=s.suite_run_id AND t.input_payload->>'run_id'=v.run_id::text
   AND EXISTS(SELECT 1 FROM jsonb_array_elements_text(s.metadata->'run_ids') rid(value) WHERE rid.value=v.run_id::text)
   AND t.status='PASSED'
   AND EXISTS (SELECT 1 FROM public.lf_test_assertion_results a
    WHERE a.test_run_id=t.test_run_id AND a.status='PASS' AND a.assertion_code ILIKE '%APPLICAB%')
   AND EXISTS (SELECT 1 FROM public.lf_test_assertion_results a
    WHERE a.test_run_id=t.test_run_id AND a.status='PASS' AND a.assertion_code ILIKE '%FINDING%')
   AND NOT EXISTS (SELECT 1 FROM public.lf_test_assertion_results a
    WHERE a.test_run_id=t.test_run_id AND a.status IN ('FAIL','BLOCKED','REVIEW_REQUIRED'))
  )) missing_screen_proofs,
 (SELECT count(*) FROM cohort v WHERE v.family_rows=v.family_count AND
 v.assessed_rows=v.family_count AND v.classifiable_rows=v.family_count) classified_screens
 FROM eligible_suite s
)
SELECT CASE WHEN (SELECT count(*) FROM cohort)=13
 AND EXISTS(SELECT 1 FROM candidates WHERE suite_run_count=13 AND missing_screen_proofs=0 AND classified_screens=13)
 THEN 'PASS' ELSE 'FAIL' END verdict,
 (SELECT count(*) FROM eligible_suite) candidate_suite_count,
 (SELECT count(*) FROM cohort) required_screens,
 (SELECT coalesce(sum(observations),0) FROM cohort) classified_observations,
 (SELECT count(*) FROM candidates WHERE suite_run_count=13 AND missing_screen_proofs=0 AND classified_screens=13) eligible_suite_count$cpquery_1$;
 prev:=m#>>ARRAY['action_specs_v1',c,'verification_queries','0'];
 IF prev IS NULL OR prev='' THEN RAISE EXCEPTION 'M105_V3_UNBOUND_CHECKPOINT:%',c; END IF;
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'verification_queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'expected'],to_jsonb('M7 full regression on exact 13 current run IDs + commit/release manifest, independent per-screen applicability and findings assertions; observations classified, never silently PASS'::text),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],
 coalesce(m#>ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'target','declared_objects'],
 coalesce(m#>ARRAY['action_specs_v1',c,'target','declared_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 IF c IN ('NEW_RUNS_VNEXT','NEG_STALE_RUN') THEN
  m:=jsonb_set(m,ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],
  coalesce(m#>ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],'[]'::jsonb)
  || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 END IF;
 
 n:=n+1;


 c:='PERF_M8_GREEN'; q:=$cpquery_2$WITH cohort AS (SELECT * FROM programacion.v_ig_m105_cohort_evidence_v1),
qualified AS (SELECT validator_elapsed_ms FROM cohort
 WHERE fresh_vnext AND source_current AND release_bound AND edge_identities AND agent_edge_receipt
 AND validator_elapsed_ms IS NOT NULL)
SELECT CASE WHEN (SELECT count(*) FROM cohort)=13 AND (SELECT count(*) FROM qualified)=13
 AND (SELECT percentile_cont(0.95) WITHIN GROUP(ORDER BY validator_elapsed_ms) FROM qualified)<=150000
 AND EXISTS(SELECT 1 FROM programacion.fn_ig_performance_timing_metrics_v1() m WHERE m.scope='SUMMARY' AND m.status='PUBLISHED' AND m.sample_count>0)
 THEN 'PASS' ELSE 'FAIL' END verdict,
 (SELECT count(*) FROM cohort) cohort_count,
 (SELECT count(*) FROM qualified) verified_validator_receipts,
 (SELECT percentile_cont(0.95) WITHIN GROUP(ORDER BY validator_elapsed_ms) FROM qualified) cohort_validator_p95_ms,
 150000::int budget_ms$cpquery_2$;
 prev:=m#>>ARRAY['action_specs_v1',c,'verification_queries','0'];
 IF prev IS NULL OR prev='' THEN RAISE EXCEPTION 'M105_V3_UNBOUND_CHECKPOINT:%',c; END IF;
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'verification_queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'expected'],to_jsonb('13 exact-run independently verified VALIDATOR phase timing receipts, only after authenticated vNext Edge; cohort p95<=150000 ms'::text),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],
 coalesce(m#>ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'target','declared_objects'],
 coalesce(m#>ARRAY['action_specs_v1',c,'target','declared_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 IF c IN ('NEW_RUNS_VNEXT','NEG_STALE_RUN') THEN
  m:=jsonb_set(m,ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],
  coalesce(m#>ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],'[]'::jsonb)
  || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 END IF;
 
 n:=n+1;


 c:='NEG_STALE_RUN'; q:=$cpquery_3$WITH e AS (SELECT * FROM programacion.v_ig_m105_cohort_evidence_v1)
SELECT count(*) AS total_screens,
count(*) FILTER(WHERE NOT source_current OR NOT fresh_vnext) AS observed_stale_or_legacy,
count(*) FILTER(WHERE (NOT source_current OR NOT fresh_vnext) AND release_bound AND edge_identities AND agent_edge_receipt) AS invalid_provenance_attempts,
jsonb_agg(jsonb_build_object('pantalla_id',pantalla_id,'run_id',run_id,'source_current',source_current,
'fresh_vnext',fresh_vnext,'release_bound',release_bound,'edge_identities',edge_identities,'agent_edge_receipt',agent_edge_receipt)
ORDER BY pantalla_id) AS observed_cases,
'OBSERVATION_ONLY_NEGATIVE_TEST_REQUIRED'::text AS classification
FROM e$cpquery_3$;
 prev:=m#>>ARRAY['action_specs_v1',c,'verification_queries','0'];
 IF prev IS NULL OR prev='' THEN RAISE EXCEPTION 'M105_V3_UNBOUND_CHECKPOINT:%',c; END IF;
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'verification_queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'expected'],to_jsonb('Observe stale/legacy examples for the bounded adversarial executable test; readback observations are not themselves PASS'::text),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],
 coalesce(m#>ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'target','declared_objects'],
 coalesce(m#>ARRAY['action_specs_v1',c,'target','declared_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 IF c IN ('NEW_RUNS_VNEXT','NEG_STALE_RUN') THEN
  m:=jsonb_set(m,ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],
  coalesce(m#>ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],'[]'::jsonb)
  || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 END IF;
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'test_execution_contract','declared_queries'],jsonb_build_array(q),true);
 n:=n+1;


 c:='E2E_READBACK'; q:=$cpquery_4$WITH cohort AS (SELECT * FROM programacion.v_ig_m105_cohort_evidence_v1),
checkpoints AS (SELECT checkpoint_code,status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=(SELECT work_item_id FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5')),
aggregate AS (
 SELECT count(*) screen_count,count(DISTINCT pantalla_id) distinct_screens,
 count(DISTINCT run_id) distinct_runs,
 count(*) FILTER(WHERE fresh_vnext AND source_current AND release_bound
   AND edge_identities AND agent_edge_receipt AND family_rows=family_count
   AND assessed_rows=family_count AND classifiable_rows=family_count) admitted_runs,
 coalesce(sum(observations),0) observations
 FROM cohort
)
SELECT CASE WHEN a.screen_count=13 AND a.distinct_screens=13 AND a.distinct_runs=13
 AND a.admitted_runs=13 AND
 (SELECT count(*) FROM checkpoints
   WHERE checkpoint_code IN ('NEW_RUNS_VNEXT','SUITE_M7_GREEN','PERF_M8_GREEN','NEG_STALE_RUN')
     AND status='DONE')=4
 THEN 'PASS' ELSE 'FAIL' END verdict,
 a.screen_count,a.admitted_runs,a.observations,
 (SELECT jsonb_agg(jsonb_build_object('pantalla_id',pantalla_id,'run_id',run_id,
 'release',release_version,'manifest_sha256',release_manifest_sha256,'provenance',release_bound,
 'observations',observations) ORDER BY pantalla_id) FROM cohort) screen_evidence,
 (SELECT count(*) FROM checkpoints WHERE checkpoint_code IN ('NEW_RUNS_VNEXT','SUITE_M7_GREEN','PERF_M8_GREEN','NEG_STALE_RUN')
 AND status='DONE') upstream_done
FROM aggregate a$cpquery_4$;
 prev:=m#>>ARRAY['action_specs_v1',c,'verification_queries','0'];
 IF prev IS NULL OR prev='' THEN RAISE EXCEPTION 'M105_V3_UNBOUND_CHECKPOINT:%',c; END IF;
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'verification_queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'expected'],to_jsonb('13 exact latest run IDs and typed provenance, classified family observations, all CP2..CP5 genuinely DONE; no synthetic cutover'::text),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],
 coalesce(m#>ARRAY['source_pack_v1','checkpoint_inputs',c,'inputs','db_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 m:=jsonb_set(m,ARRAY['action_specs_v1',c,'target','declared_objects'],
 coalesce(m#>ARRAY['action_specs_v1',c,'target','declared_objects'],'[]'::jsonb)
 || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 IF c IN ('NEW_RUNS_VNEXT','NEG_STALE_RUN') THEN
  m:=jsonb_set(m,ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],
  coalesce(m#>ARRAY['action_specs_v1',c,'test_execution_contract','declared_objects'],'[]'::jsonb)
  || jsonb_build_array('programacion.v_ig_m105_cohort_evidence_v1'),true);
 END IF;
 
 n:=n+1;

 m:=jsonb_set(m,'{action_specs_v1,NEG_STALE_RUN,test_execution_contract,negative_required}','true'::jsonb,true);
 IF n<>5 THEN RAISE EXCEPTION 'M105_V3_INCOMPLETE_UPDATE'; END IF;
 m:=jsonb_set(m,'{m105_validation_contract_v3}',jsonb_build_object(
 'schema_version','M105_COHORT_EVIDENCE_V3','phase','OPERATIONAL_POST_CUTOVER',
 'scope_origin','M105_SCOPE_SNAPSHOT_V1',
 'shared_readback','programacion.v_ig_m105_cohort_evidence_v1',
 'execution_gate','REAL_EDGES_AND_ATTESTED_RELEASE_REQUIRED',
 'semantic_gate','EXACT_COHORT_SUITE_APPLICABILITY_AND_FINDINGS_PROVEN',
 'observations_policy','PERSIST_AND_CLASSIFY_NOT_AUTOMATIC_BLOCK',
 'performance_gate','COHORT_BOUND_VERIFIED_VALIDATOR_P95',
 'negative_gate','REAL_STALE_ADVERSARIAL_TEST_NOT_READBACK_ALONE',
 'admission','NO_PRODUCTION_AUTHORIZATION',
 'impact','CONTRACT_AND_CHECKPOINT_VALIDATOR_ONLY'),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m,
 exit_criterion='13 current post-cutover vNext Edge runs with authenticated provenance, M7 cohort-bound semantic suite, M8 exact-run p95, stale negative and terminal readback; findings classified without automatic conflation'
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' AND work_item_id=wd;
 UPDATE programacion.engineering_work_items SET expected_result=
 '13 authentic post-cutover Edge runs; M7 exact-cohort functional assurance, M8 exact-cohort timing, adversarial stale rejection and terminal reconciliation; observations recorded not automatic gate',
 acceptance_criteria=jsonb_build_array(
 '13 genuine post-cutover run IDs current and release-attested by independent receipt on exact vNext manifest',
 'M7: full regression bound to exact run IDs and governed applicability/finding assertions for each screen',
 'M8: independently measured VALIDATOR timing per run, cohort p95 in budget and M8 published summary',
 'Negative stale or legacy run rejected by executable adversarial test',
 'Terminal readback reconciles the same 13 run IDs; classify observations without automatic blocking')
 WHERE id=wd;
 IF (SELECT unit_metadata#>>'{m105_validation_contract_v3,schema_version}'
 FROM programacion.engineering_plan_units WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5')
 IS DISTINCT FROM 'M105_COHORT_EVIDENCE_V3' THEN RAISE EXCEPTION 'M105_V3_READBACK_FAILED'; END IF;
END $m105v3$;

INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT 'IG-M105-COHORT-VALIDATION-DRIFT-004','INPUT_GOVERNANCE',
'M10.5 CP2-CP6 unbound suite, global timing and invalid release scope',
'CP2 counted validators but not findings; CP3 accepted a global suite without 13-run linkage; CP4 global M8; CP5/6 read release from a JSON source receipt array.',
'Contracts and validators were not tied to the exact same versioned cohort; observation status was conflated with the execution gate.',
'Read-only shared M10.5 cohort view; genuine release+Edge receipts, per-screen M7 applicability and finding assertions, exact-run M8 timing, bounded stale adversarial and final reconciliation. Report observations without accidental PASS or blanket BLOCK.',
'Before Train: live read-only projections 13 cohort, 0 authentic vNext, 0 M7 qualified, 0 vNext validator timing, CP6 FAIL. Production unchanged.',
'github://cristhianlujan/claude-persona-lf-patch/pull/2486',
'programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5','ACTIVO','CONTRACT_PREFLIGHT',ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='IG-M105-COHORT-VALIDATION-DRIFT-004');
