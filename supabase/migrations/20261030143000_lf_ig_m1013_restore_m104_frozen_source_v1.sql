-- Restore exactly the immutable M10.4 function definition.
-- Forward-only rollback; retain evidence and leave M10.13 open.
BEGIN;
DO $restore$
DECLARE
 fn text:='programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)';
 a text:='programacion.fn_input_governance_bootstrap_classify_v1_ctx(p_pantalla_id,p_family_code,p_version_id,p_graph)';
 b text:='programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(p_pantalla_id,p_family_code,p_version_id,p_graph)';
 c text:='programacion.fn_input_governance_semantic_probe_v3_ctx(p_pantalla_id,p_family_code,p_version_id,p_graph)';
 d text:='programacion.fn_input_governance_semantic_probe_v3_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph)';
 src text; ddl text; restored text; meta jsonb; n integer; drift integer;
BEGIN
 SELECT p.prosrc,pg_get_functiondef(p.oid) INTO STRICT src,ddl
 FROM pg_proc p WHERE p.oid=to_regprocedure(fn);
 IF md5(src)<>'11bd4af470dffc3d2ae8c1316774c1ba'
 OR (length(src)-length(replace(src,a,'')))<>length(a)
 OR (length(src)-length(replace(src,c,'')))<>length(c)
 THEN RAISE EXCEPTION 'M104_RESTORE_SOURCE_DRIFT'; END IF;
 IF md5(replace(replace(src,a,b),c,d))<>'7257b9bbc86b1f61e5435a37479d63a1'
 THEN RAISE EXCEPTION 'M104_RESTORE_HASH_MISMATCH'; END IF;
 EXECUTE replace(replace(ddl,a,b),c,d);
 SELECT md5(prosrc) INTO restored FROM pg_proc WHERE oid=to_regprocedure(fn);
 IF restored<>'7257b9bbc86b1f61e5435a37479d63a1'
 THEN RAISE EXCEPTION 'M104_RESTORE_READBACK_FAILED'; END IF;

 WITH frozen AS(
 SELECT x.value->>'identity' ident,x.value->>'prosrc_md5' expected
 FROM programacion.engineering_plan_units u
 CROSS JOIN LATERAL jsonb_array_elements(u.unit_metadata#>'{m104_freeze_baseline_v1,legacy_functions}') x
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.4'
 ), live AS(
 SELECT f.expected,md5(p.prosrc) actual FROM frozen f LEFT JOIN LATERAL(
 SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'=f.ident
 ) p ON true
 )
 SELECT count(*),count(*) FILTER(WHERE expected IS DISTINCT FROM actual) INTO n,drift FROM live;
 IF n<>26 OR drift<>0 THEN RAISE EXCEPTION 'M104_FREEZE_DRIFT'; END IF;

 SELECT unit_metadata INTO STRICT meta FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13' FOR UPDATE;
 IF NOT(meta?'cp3_fast_chain_rehome_v1') OR meta?'cp3_frozen_source_restore_v1'
 THEN RAISE EXCEPTION 'M1013_RESTORE_EVIDENCE_DRIFT'; END IF;
 UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(
 unit_metadata,'{cp3_frozen_source_restore_v1}',jsonb_build_object(
 'supersedes','cp3_fast_chain_rehome_v1','reason','M104_FROZEN_SOURCE',
 'restored_md5',restored,'frozen_count',n,'frozen_drift',drift,
 'previous_speed_sample_not_current',true,'cp3_closed',false),true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13'
 AND unit_metadata=meta;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 OR (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
 THEN RAISE EXCEPTION 'M1013_RESTORE_LEDGER_DRIFT'; END IF;
END $restore$;
COMMIT;
