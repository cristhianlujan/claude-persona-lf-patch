-- M10.11 ONLY: current SQL proof overlay over historical M10.10 classification.
-- NO REVOKE, DROP, GRANT, checkpoint transition, blocker resolution or runtime.
-- EKB: IG-M1011-REMOVE-READY-EMPTY-001, IG-CALLER-NAME-NOT-USAGE-001,
-- SQL-015, IG-M99-JSONB-PARENT-NULL-ASSERTION-001.
-- Classification authority remains M10.10; this overlay is SQL-only evidence,
-- explicitly not a multi-surface signed retirement admission.
DO $m1011$
DECLARE
 v_event_id bigint;
 v_historical_count integer;
 v_report jsonb;
 v_count integer;
 v_sql_callers integer;
 v_client_grants integer;
 v_gov_version text;
 v_payload jsonb;
 v_updated integer;
BEGIN
 SELECT max(id) INTO v_event_id
 FROM public.lf_eventos
 WHERE entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
 IF v_event_id IS NULL THEN
   RAISE EXCEPTION 'M1011_CLASSIFICATION_SOURCE_MISSING';
 END IF;
 IF (SELECT w.status FROM programacion.engineering_plan_units u
     JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
   IS DISTINCT FROM 'IN_PROGRESS' THEN
   RAISE EXCEPTION 'M1011_UNIT_PRESTATE_DRIFT';
 END IF;
 IF (SELECT u.unit_metadata#>>'{m1011_retirement_governance_v1,scope}'
     FROM programacion.engineering_plan_units u
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
   IS DISTINCT FROM 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.11_ONLY' THEN
   RAISE EXCEPTION 'M1011_LOCAL_GOVERNANCE_NOT_CURRENT';
 END IF;
 IF (SELECT u.unit_metadata#>>'{action_specs_v1,REVOKE_MIGRATION,status}'
     FROM programacion.engineering_plan_units u
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
   IS DISTINCT FROM 'BLOCK_NO_CURRENT_REMOVE_READY' THEN
   RAISE EXCEPTION 'M1011_REVOKE_GATE_PRESTATE_DRIFT';
 END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(
      (SELECT payload->'matrix' FROM public.lf_eventos WHERE id=v_event_id)) x
      WHERE x->>'class'='REMOVE_READY') <> 0 THEN
   RAISE EXCEPTION 'M1011_TARGETS_EXIST_DO_NOT_USE_ZERO_TARGET_OVERLAY';
 END IF;
 SELECT count(*) INTO v_historical_count
 FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x
 WHERE e.id=v_event_id AND x->>'class'='LEGACY_UNREFERENCED';
 IF v_historical_count=0 THEN
   RAISE EXCEPTION 'M1011_NO_HISTORICAL_CANDIDATES_TO_RECHECK';
 END IF;
 SELECT c.version INTO v_gov_version
 FROM public.lf_capability_current c
 JOIN public.lf_capability_version_registry v
   ON v.capability_code=c.capability_code AND v.version=c.version
 WHERE c.capability_code='ASSET_RETIREMENT_GOVERNANCE'
   AND v.release_state='RELEASED';
 IF v_gov_version IS DISTINCT FROM '1.0.0' THEN
   RAISE EXCEPTION 'M1011_GOVERNANCE_VERSION_DRIFT:%',v_gov_version;
 END IF;

 -- Fresh SQL source + effective privileges, identity deduped by precise
 -- catalog schema + proname; historical category is not retirement authority.
 WITH historic AS (
   SELECT x->>'item_identity' AS historic_signature,
          split_part(x->>'item_identity','.',1) AS schema_name,
          split_part(split_part(x->>'item_identity','.',2),'(',1) AS fn_name
   FROM public.lf_eventos e
   CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x
   WHERE e.id=v_event_id AND x->>'class'='LEGACY_UNREFERENCED'
 ), resolved AS (
   SELECT h.*,p.oid,p.prosrc,p.proowner,
          (SELECT coalesce(jsonb_agg(q.oid::regprocedure::text ORDER BY q.oid::regprocedure::text),'[]'::jsonb)
           FROM pg_proc q JOIN pg_namespace qn ON qn.oid=q.pronamespace
           WHERE qn.nspname IN ('programacion','public')
             AND q.oid IS DISTINCT FROM p.oid
             AND q.prosrc ~* ('(^|[^a-z0-9_])'||h.fn_name||'[[:space:]]*[(]')
          ) AS sql_callers
   FROM historic h
   LEFT JOIN pg_namespace pn ON pn.nspname=h.schema_name
   LEFT JOIN pg_proc p ON p.pronamespace=pn.oid AND p.proname=h.fn_name
 )
 SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'historical_identity',historic_signature,
      'observed_signature',CASE WHEN oid IS NULL THEN NULL ELSE oid::regprocedure::text END,
      'function_source_md5',md5(coalesce(prosrc,'')),
      'sql_callers',sql_callers,
      'effective_execute',CASE WHEN oid IS NULL THEN NULL ELSE jsonb_build_object(
        'anon',has_function_privilege('anon',oid,'EXECUTE'),
        'authenticated',has_function_privilege('authenticated',oid,'EXECUTE'),
        'service_role',has_function_privilege('service_role',oid,'EXECUTE')) END,
      'retirement_admission','NOT_ADMITTED_SQL_ONLY',
      'external_surfaces','UNVERIFIED'
    ) ORDER BY historic_signature),'[]'::jsonb)
 INTO v_report FROM resolved;

 v_count:=jsonb_array_length(v_report);
 IF v_count IS DISTINCT FROM v_historical_count THEN
   RAISE EXCEPTION 'M1011_COVERAGE_MISMATCH historical=% observed=%',v_historical_count,v_count;
 END IF;
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_report) r
            WHERE r->>'observed_signature' IS NULL) THEN
   RAISE EXCEPTION 'M1011_HISTORICAL_FUNCTION_MISSING_RECLASSIFY_AT_SOURCE';
 END IF;
 IF (SELECT count(DISTINCT r->>'observed_signature')
     FROM jsonb_array_elements(v_report) r) IS DISTINCT FROM v_count THEN
   RAISE EXCEPTION 'M1011_SIGNATURE_COLLISION';
 END IF;
 SELECT count(*) INTO v_sql_callers FROM jsonb_array_elements(v_report) r
 WHERE jsonb_array_length(r->'sql_callers')>0;
 SELECT count(*) INTO v_client_grants FROM jsonb_array_elements(v_report) r
 WHERE r#>>'{effective_execute,anon}'='true'
   AND r#>>'{effective_execute,authenticated}'='true';
 -- Independent negative assertion: any SQL caller MUST remain non-admitted.
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_report) r
            WHERE jsonb_array_length(r->'sql_callers')>0
              AND r->>'retirement_admission' <> 'NOT_ADMITTED_SQL_ONLY') THEN
    RAISE EXCEPTION 'M1011_NEGATIVE_CALLER_GUARD_FAILED';
 END IF;
 -- Independent negative assertion: unknown Edge/Router/Git cannot be a pass.
 IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_report) r
            WHERE r->>'external_surfaces'='UNVERIFIED'
              AND r->>'retirement_admission' IN ('REMOVE_READY','PASS')) THEN
    RAISE EXCEPTION 'M1011_UNKNOWN_EXTERNAL_SURFACE_FALSE_PASS';
 END IF;
 v_payload:=jsonb_build_object(
    'schema_version','IG_M1011_LIVE_SQL_RECHECK_V2',
    'scope','IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.11_ONLY',
    'source_unit','M10.10',
    'historical_event_id',v_event_id,
    'observed_at',clock_timestamp(),
    'authority','PG_CATALOG_CURRENT_SQL_ONLY',
    'observed_count',v_count,
    'historical_unreferenced_count',v_historical_count,
    'sql_caller_positive_count',v_sql_callers,
    'anon_and_authenticated_effective_count',v_client_grants,
    'report_digest_md5',md5(v_report::text),
    'functions',v_report,
    'currentness',jsonb_build_object(
       'SQL','LIVE_VERIFIED',
       'GIT','PENDING_INDEPENDENT_PROOF',
       'EDGE','PENDING_INDEPENDENT_PROOF',
       'ROUTER','PENDING_INDEPENDENT_PROOF',
       'CONTRACTS','PENDING_INDEPENDENT_PROOF'),
    'governance_current',jsonb_build_object(
       'capability','ASSET_RETIREMENT_GOVERNANCE','version',v_gov_version),
    'revoke_authorized',false,
    'checkpoint_completion_authorized',false,
    'acl_mutated',false,
    'next_action','Complete other source readbacks before ZERO eligibility is signed, then use canonical blocker/transition APIs; NEVER execute REVOKE without actual targets.'
 );

 UPDATE programacion.engineering_plan_units u
 SET unit_metadata = jsonb_set(
   jsonb_set(
     u.unit_metadata,
     '{m1011_live_sql_recheck_v2}',v_payload,true),
     '{m1011_retirement_governance_v1,live_recheck_status}',
     to_jsonb('SQL_CURRENT_OTHER_SOURCES_PENDING'::text),true)
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11';
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 IF v_updated IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'M1011_UNIT_SCOPE_UPDATE_EXPECTED_ONE'; END IF;
 IF (SELECT u.unit_metadata#>>'{m1011_live_sql_recheck_v2,report_digest_md5}'
     FROM programacion.engineering_plan_units u
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
    IS DISTINCT FROM md5(v_report::text) THEN
    RAISE EXCEPTION 'M1011_SQL_READBACK_DIGEST_MISMATCH';
 END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=(SELECT work_item_id FROM programacion.engineering_plan_units
                         WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11')
       AND checkpoint_code IN ('GRANTS_ASIS','REUSE_RETIREMENT_GOV') AND status='DONE')
    IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'M1011_DONE_PRECHECKPOINT_DRIFT';
 END IF;
END;
$m1011$;
