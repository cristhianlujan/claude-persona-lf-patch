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
 $old$      AND source_manifest->>'release_id'=version
      AND scope->>'release_manifest_sha256'=manifest_sha256
      AND source_manifest->>'release_manifest_sha256'=manifest_sha256$old$,
 $new$      AND scope->>'release_manifest_sha256'=manifest_sha256
      AND verified_release_receipt$new$);
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