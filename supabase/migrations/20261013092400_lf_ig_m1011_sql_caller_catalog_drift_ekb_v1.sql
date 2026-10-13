-- EKB only: M10.11 live currentness lesson, no unit mutation or grants.
DO $m1011_ekb$
DECLARE
 v_proof jsonb;
 v_count int;
 v_sql_positive int;
 v_client_acl int;
BEGIN
 SELECT unit_metadata#>'{m1011_live_sql_recheck_v2}' INTO v_proof
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11';
 IF v_proof IS NULL OR v_proof->>'authority' IS DISTINCT FROM 'PG_CATALOG_CURRENT_SQL_ONLY' THEN
   RAISE EXCEPTION 'M1011_EKB_REQUIRES_LIVE_SQL_PROOF';
 END IF;
 SELECT count(*) INTO v_count
 FROM jsonb_array_elements(v_proof->'functions');
 SELECT count(*) INTO v_sql_positive
 FROM jsonb_array_elements(v_proof->'functions') f
 WHERE jsonb_array_length(f->'sql_callers')>0;
 SELECT count(*) INTO v_client_acl
 FROM jsonb_array_elements(v_proof->'functions') f
 WHERE f#>>'{effective_execute,anon}'='true'
   AND f#>>'{effective_execute,authenticated}'='true';
 IF v_count IS DISTINCT FROM (v_proof->>'observed_count')::int
    OR v_sql_positive IS DISTINCT FROM (v_proof->>'sql_caller_positive_count')::int
    OR v_client_acl IS DISTINCT FROM (v_proof->>'anon_and_authenticated_effective_count')::int
    OR v_sql_positive=0 THEN
   RAISE EXCEPTION 'M1011_EKB_EVIDENCE_DRIFT_OR_NO_COUNTEREXAMPLE';
 END IF;
 IF v_proof->>'revoke_authorized' IS DISTINCT FROM 'false'
    OR v_proof->>'checkpoint_completion_authorized' IS DISTINCT FROM 'false' THEN
   RAISE EXCEPTION 'M1011_EKB_CANNOT_CERTIFY_RETIREMENT';
 END IF;
 INSERT INTO transversal.error_knowledge(
   codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,
   source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
 SELECT
  'IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001',
  'INPUT_GOVERNANCE',
  'Una funcion legacy historicamente unreferenced aun tiene un caller SQL en fuente viva',
  'M10.10 catalogo historico del 2026-10-04 contiene 14 LEGACY_UNREFERENCED. La refrescada M10.11 detecto al menos una referencia SQL real en pg_proc: fn_input_gov_gold_b_prepare_review_v1 invoca fn_input_readiness_run_is_current_cached_v2. Esto refuta la interpretacion de zero SQL references. La presencia de referencia en fuente tampoco prueba liveness efectiva: es un candidato para verificar, no permiso para borrar ni cambiar clasificacion por intuicion.',
  'El snapshot LEGACY_UNREFERENCED se trato como autoridad vigente sin comparar fuentes actuales. Los grants y los callers fueron inferidos por nombre/conteos de foto en vez de verificar ACL efectiva y fuente SQL real.',
  'Para retirar funciones IG: EKB antes de ejecutar; consumir M10.10 como evidencia historica, resolver identidad canonica de funcion desde pg_proc, verificar fuente SQL de callers excluyendo self y permisos reales con has_function_privilege por rol, deduplicar identidades y calcular cardinalidades dinamicas. Registrar digest de resultados; verificar Edge/Router/Git/Contracts independientemente. Cualquier caller positivo o superficie desconocida => no REMOVE_READY. Un no-op puede pasar NOT_APPLICABLE solo con evidencia fresh signed y readback sin ACL delta; no sintetizar PASS ni revocar por prefijo. Contrato, gobierno y validador del mismo owner coordinados.',
  'Supabase M10.11 PR2402: prueba readonly SQL con 14 firmas actuales, 1 referencia SQL positiva, 3 funciones con EXECUTE efectivo tanto para anon como authenticated. Hash del reporte y 14 fingerprints fuente persistidos en unit_metadata.m1011_live_sql_recheck_v2, currentness externo PENDING, revoke_authorized=false, checkpoint_completion_authorized=false. Prueba estatica negativa de REVOKE/GRANT/DROP PASS, migracion por Merge Train y readback exacto. Estos resultados NO validan que las demas superficies tengan cero consumidores, ni cierran checkpoints.',
  'GitHub PR #2402; Supabase exact ledger 20261013163001 / gitblob:b055ab2b0ee5ff4c4284d0a02cfc9c993a7098fb; initial catalog event public.lf_eventos/20193; source programacion.engineering_plan_units/M10.11',
  'programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.11',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.11',
  'ACTIVO','VERIFY_AND_PREVENT',ARRAY['Architect','Builder','Auditor','Judge']::text[]
 WHERE NOT EXISTS (
  SELECT 1 FROM transversal.error_knowledge
  WHERE codigo='IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001'
 );
 IF (SELECT count(*) FROM transversal.error_knowledge
     WHERE codigo='IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001') IS DISTINCT FROM 1 THEN
   RAISE EXCEPTION 'M1011_EKB_READBACK_NOT_UNIQUE';
 END IF;
END;
$m1011_ekb$;
