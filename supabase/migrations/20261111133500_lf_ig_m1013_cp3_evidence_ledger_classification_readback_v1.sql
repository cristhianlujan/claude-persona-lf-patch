-- LF IG M10.13 CP3 | reconciliation: evidence ledger current vs historical freeze.
-- Source-first; ACTUALIZACION_DB_LF -> DB_WRITE_TRANSPORT -> LF Migration Merge Train PR #3791.
-- Only change: M10.13 metadata currentness observation + official non-terminal event.
-- Preserve 26/26 M10.4 frozen sources, EVIDENCE_LEDGER, ACLs, 79+ ledger receipts, Router and checkpoints.
-- No retirement/adjudication: owner LF_GOVERNANCE / SUPER_ADMIN remains authoritative.
BEGIN;
SET LOCAL lock_timeout = '2000ms';
SET LOCAL statement_timeout = '30000ms';
DO $ig_m1013_evidence_ledger_classify$
DECLARE
 v_op text;
 v_old jsonb;
 v_after jsonb;
 v_freeze_before jsonb;
 v_historical jsonb;
 v_reconciliation jsonb;
 v_payload jsonb;
 v_callers jsonb;
 v_anchor_md5 text;
 v_freeze_count integer;
 v_freeze_matching integer;
 v_external_edges integer;
 v_frozen_to_frozen integer;
 v_other_external integer;
 v_receipt_count integer;
 v_event_id bigint;
 v_rows integer;
BEGIN
 SELECT e.execution_id INTO v_op FROM public.lf_operation_execution e
 WHERE e.operation_code='ACTUALIZACION_DB_LF' AND e.target_type='MIGRATION'
   AND e.target_code ~ '^[0-9]{14}_lf_ig_m1013_cp3_evidence_ledger_classification_readback_v1$'
   AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
   AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
   AND e.manifest->>'producer'='lf-migration-merge-train'
   AND e.manifest->>'pr'='3791' AND e.status='IN_PROGRESS'
 ORDER BY e.created_at DESC LIMIT 1;
 IF v_op IS NULL THEN RAISE EXCEPTION 'IG_CP3_LEDGER_GOVERNED_TRAIN_REQUIRED'; END IF;
 IF (SELECT w.status FROM programacion.engineering_work_items w WHERE w.id=474) IS DISTINCT FROM 'IN_PROGRESS'
   OR (SELECT status FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') IS DISTINCT FROM 'PENDING'
   OR (SELECT status FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=474 AND checkpoint_code='AUD045_EVIDENCE') IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_UNIT_STATE_DRIFT'; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM public.lf_activos a
   WHERE a.id=136 AND a.codigo_activo='EVIDENCE_LEDGER'
     AND a.nombre_canonico='TRANSVERSAL_EVIDENCE_LEDGER'
     AND a.estado_operativo='ACTIVO' AND a.estado_documental='VIGENTE'
     AND a.archived_at IS NULL AND a.owner_name='LF_GOVERNANCE'
     AND a.raw_payload->'assets' @> '["public.fn_lf_evidence_ledger_anchor_v1"]'::jsonb
 ) OR NOT EXISTS (
   SELECT 1 FROM public.lf_capability_registry r
   JOIN public.lf_capability_current c USING (capability_code)
   WHERE r.capability_code='EVIDENCE_LEDGER'
     AND r.status='ACTIVE' AND r.owner_scope='LF_GOVERNANCE'
     AND c.version='1.1.0'
     AND c.manifest_sha256='b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982'
 ) OR NOT EXISTS (
   SELECT 1 FROM public.lf_capability_registry r
   WHERE r.capability_code='ASSET_RETIREMENT_GOVERNANCE'
     AND r.status='ACTIVE' AND r.owner_scope='SUPER_ADMIN'
 ) THEN RAISE EXCEPTION 'IG_CP3_LEDGER_CANONICAL_AUTHORITY_NOT_CURRENT'; END IF;

 SELECT x.value INTO STRICT v_historical
 FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(value)
 WHERE e.id=20193 AND x.value->>'item_identity' LIKE 'public.fn_lf_evidence_ledger_anchor_v1(%';
 IF v_historical->>'class' IS DISTINCT FROM 'LEGACY_REFERENCED'
   OR v_historical->'evidence'->>'liveness' IS DISTINCT FROM 'ACTIVE_ONLY_VIA_UNUSED'
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_HISTORICAL_EVIDENCE_DRIFT'; END IF;

 SELECT unit_metadata->'m104_freeze_baseline_v1'
 INTO STRICT v_freeze_before
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.4';
 SELECT count(*)::integer, count(*) FILTER(WHERE p.oid IS NOT NULL AND md5(p.prosrc)=f.value->>'prosrc_md5')::integer
 INTO v_freeze_count,v_freeze_matching
 FROM jsonb_array_elements(v_freeze_before->'legacy_functions') f(value)
 LEFT JOIN LATERAL (
   SELECT p.oid,p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
     =f.value->>'identity'
 ) p ON true;
 IF v_freeze_count<>26 OR v_freeze_matching<>26
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_M104_FREEZE_DRIFT:count=%,equal=%',v_freeze_count,v_freeze_matching; END IF;
 SELECT md5(p.prosrc) INTO STRICT v_anchor_md5 FROM pg_proc p
 WHERE p.oid='public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)'::regprocedure;
 IF v_anchor_md5 IS DISTINCT FROM '730d37e8698885335228c91d00231b1f'
   OR NOT has_function_privilege('service_role',
     'public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)','EXECUTE')
   OR has_function_privilege('anon',
     'public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)','EXECUTE')
   OR has_function_privilege('authenticated',
     'public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)','EXECUTE')
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_ANCHOR_SOURCE_OR_ACL_DRIFT'; END IF;

 -- No unknown nonfrozen callers to any M10.4 function, besides the exact
 -- four canonical Evidence Ledger consumers. Internal historical edges are not ignored.
 WITH frozen AS (
   SELECT split_part(f.value->>'identity','(',1) AS routine
   FROM jsonb_array_elements(v_freeze_before->'legacy_functions') f(value)
 ), live AS (
   SELECT n.nspname||'.'||p.proname AS routine,p.oid::regprocedure::text AS signature,
          md5(p.prosrc) AS source_md5,p.prosrc
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','programacion','lf_ops')
 ), edges AS (
   SELECT l.routine AS caller,l.signature,l.source_md5,f.routine AS target,own.routine AS frozen_caller
   FROM frozen f JOIN live l ON l.routine<>f.routine AND strpos(l.prosrc,f.routine||'(')>0
   LEFT JOIN frozen own ON own.routine=l.routine
 )
 SELECT count(*) FILTER(WHERE frozen_caller IS NULL)::int,
        count(*) FILTER(WHERE frozen_caller IS NOT NULL)::int,
        count(*) FILTER(WHERE frozen_caller IS NULL AND target<>'public.fn_lf_evidence_ledger_anchor_v1')::int,
        jsonb_agg(jsonb_build_object('signature',signature,'source_md5',source_md5) ORDER BY signature)
          FILTER(WHERE frozen_caller IS NULL)
 INTO v_external_edges,v_frozen_to_frozen,v_other_external,v_callers
 FROM edges;
 IF v_external_edges<>4 OR v_frozen_to_frozen<>15 OR v_other_external<>0
   OR v_callers IS DISTINCT FROM jsonb_build_array(
     jsonb_build_object('signature','lf_record_independent_review_step_v3(text,text,text,jsonb,text,text)','source_md5','3e73aace98776b5f65c0dc05e76801c2'),
     jsonb_build_object('signature','programacion.fn_ig_graph_receipt_emit_per_run_v1(bigint,text,text,text,text)','source_md5','18fe88230f954a1d22ecf54fa679773b'),
     jsonb_build_object('signature','programacion.fn_ig_spec_traversal_emit_per_run_v1(bigint,text,text,text)','source_md5','0e8d978c0f28a77dab8230a0c3cc00b6'),
     jsonb_build_object('signature','programacion.fn_input_governance_shadow_receipt_emit_v1(jsonb,jsonb)','source_md5','f566ae975f30cdcc370c4134fe5746e5')
   )
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_UNEXPECTED_CALLER_GRAPH:external=%,internal=%,nonledger=%',
    v_external_edges,v_frozen_to_frozen,v_other_external; END IF;

 SELECT count(*)::int INTO v_receipt_count FROM private.lf_evidence_ledger_v1;
 IF v_receipt_count<79 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_RECEIPT_COUNT_REGRESSION'; END IF;

 SELECT unit_metadata INTO STRICT v_old
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND unit_code='M10.13' AND work_item_id=474 AND disposition='ASSIGNED'
 FOR UPDATE;
 IF v_old ? 'cp3_evidence_ledger_currentness_reconciliation_v1'
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_RECONCILIATION_ALREADY_REGISTERED'; END IF;

 -- A currentness observation, NOT an owner-issued replacement or freeze rewrite.
 v_reconciliation:=jsonb_build_object(
   'schema_version','IG_M1013_CP3_EVIDENCE_LEDGER_CURRENTNESS_RECONCILIATION_V1',
   'status','CURRENT_SHARED_OBSERVED_OWNER_ADJUDICATION_PENDING',
   'asset_code','EVIDENCE_LEDGER','asset_id',136,
   'current_class','CURRENT_SHARED_OBSERVED',
   'historical_class','LEGACY_REFERENCED',
   'historical_evidence_event_id',20193,
   'historical_liveness','ACTIVE_ONLY_VIA_UNUSED',
   'capability_version','1.1.0',
   'capability_manifest_sha256','b9c21eaa0cb4eceec3e6a0ae78272ed2da84e408e804c127ed6e43d1360f0982',
   'owner_scope','LF_GOVERNANCE',
   'source_md5',v_anchor_md5,
   'callers_current_sql_exact',v_callers,
   'current_sql_external_to_freeze',v_external_edges,
   'frozen_to_frozen_edges',v_frozen_to_frozen,
   'frozen_sources_unchanged',v_freeze_matching,
   'retained_evidence_ledger_receipts',v_receipt_count,
   'm104_baseline_modified',false,
   'source_function_modified',false,
   'runtime_function_changed',false,
   'owner_adjudication','PENDING',
   'external_dynamic_consumers','NOT_PROVEN_ABSENT',
   'retirement_authorized',false,
   'cp3_zero_callers_established',false,
   'checkpoint_pass',false,
   'execution_id',v_op,
   'observed_at',clock_timestamp()
 );
 UPDATE programacion.engineering_plan_units u
 SET unit_metadata=jsonb_set(v_old,'{cp3_evidence_ledger_currentness_reconciliation_v1}',v_reconciliation,true)
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND u.unit_code='M10.13' AND u.work_item_id=474
   AND u.unit_metadata=v_old;
 GET DIAGNOSTICS v_rows=ROW_COUNT;
 IF v_rows<>1 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_METADATA_WRITE_NOT_EXACT'; END IF;
 SELECT unit_metadata INTO STRICT v_after FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13' AND work_item_id=474;
 IF v_after-'cp3_evidence_ledger_currentness_reconciliation_v1' IS DISTINCT FROM v_old
   OR v_after->'cp3_evidence_ledger_currentness_reconciliation_v1' IS DISTINCT FROM v_reconciliation
   OR (SELECT unit_metadata->'m104_freeze_baseline_v1' FROM programacion.engineering_plan_units
       WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.4')
       IS DISTINCT FROM v_freeze_before
   OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
       'public.fn_lf_evidence_ledger_anchor_v1(text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,text)'::regprocedure)
       IS DISTINCT FROM v_anchor_md5
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_RECONCILIATION_READBACK_FAILED'; END IF;

 v_payload:=jsonb_build_object(
   'evidence_schema_version','operational-event/v2',
   'execution_id',v_op,
   'producer','LF_MIGRATION_TRAIN_IG_M1013_CP3_CURRENTNESS',
   'purpose','Reconcile historical M10.10 liveness with current EVIDENCE_LEDGER capability source without editing M10.4',
   'acceptance_declared',false,'occurred_at',clock_timestamp(),
   'asset_code','EVIDENCE_LEDGER',
   'historical_event_id',20193,
   'historical_class','LEGACY_REFERENCED',
   'current_class','CURRENT_SHARED_OBSERVED',
   'current_capability_version','1.1.0',
   'anchor_source_md5',v_anchor_md5,
   'current_external_callers',v_external_edges,
   'historical_internal_edges',v_frozen_to_frozen,
   'ledger_rows_observed',v_receipt_count,
   'owner_adjudication','PENDING',
   'retirement_authorized',false,
   'production_code_mutation','NONE_METADATA_AND_RECEIPT_ONLY',
   'm104_freeze_unchanged',true,
   'checkpoint_code','ZERO_LEGACY_CALLERS',
   'checkpoint_pass',false,
   'semantic_independence_credited',false
 );
 IF private.fn_lf_event_acceptance_signal_v2(
   'ARTIFACT_RECONCILED','IG_M1013_CP3_EVIDENCE_LEDGER_CURRENTNESS_V1',
   'Evidence Ledger historical/current classification observed; owner adjudication pending',v_payload
 ) IS NOT NULL THEN RAISE EXCEPTION 'IG_CP3_LEDGER_FALSE_ACCEPTANCE_SIGNAL'; END IF;
 INSERT INTO public.lf_eventos(
   evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
   created_by_execution_id,payload
 ) VALUES(
   'ARTIFACT_RECONCILED','PROGRAM_PLAN',
   'IG_M1013_CP3_EVIDENCE_LEDGER_CURRENTNESS_V1',
   'Evidence Ledger historical/current classification observed; owner adjudication pending',
   'INFO','DERIVE_FROM_EXECUTION_ID',v_op,v_payload
 ) RETURNING id INTO v_event_id;
 IF NOT EXISTS(SELECT 1 FROM public.lf_eventos WHERE id=v_event_id
   AND payload->>'checkpoint_pass'='false'
   AND payload->>'owner_adjudication'='PENDING'
   AND payload->>'current_external_callers'='4'
   AND payload->>'m104_freeze_unchanged'='true')
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_OFFICIAL_RECEIPT_READBACK_FAILED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'IG_CP3_LEDGER_CHECKPOINT_FALSE_TERMINAL_CHANGE'; END IF;
END;
$ig_m1013_evidence_ledger_classify$;
COMMIT;
