-- M10.7 F: backend-only run snapshot extraction; no consumer activation.
-- Run ONLY in a READ ONLY REPEATABLE READ/SERIALIZABLE transaction.
CREATE FUNCTION programacion.fn_ig_m107_trusted_run_data_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $fn$
DECLARE
 v_run programacion.input_readiness_runs%rowtype;
 v_packet jsonb; v_manifest jsonb; v_graph jsonb; v_graph_receipt jsonb;
 v_rules jsonb; v_contracts jsonb; v_families jsonb;
 n_rules integer; n_contracts integer; n_families integer;
BEGIN
 IF current_setting('transaction_read_only') IS DISTINCT FROM 'on'
    OR current_setting('transaction_isolation') NOT IN ('repeatable read','serializable')
 THEN RAISE EXCEPTION 'IG_M107_TRUSTED_SNAPSHOT_TX_REQUIRED'; END IF;
 IF p_run_id IS NULL OR p_run_id<=0 THEN RAISE EXCEPTION 'IG_M107_TRUSTED_RUN_ID_INVALID'; END IF;
 SELECT * INTO v_run FROM programacion.input_readiness_runs WHERE id=p_run_id;
 IF NOT FOUND OR v_run.status<>'VALIDATING' THEN
   RAISE EXCEPTION 'IG_M107_TRUSTED_RUN_NOT_VALIDATING:%',p_run_id; END IF;
 IF v_run.invalidated_at IS NOT NULL OR v_run.source_snapshot_sha256 IS NULL
    OR v_run.contract_snapshot_sha256 IS NULL OR v_run.source_manifest IS NULL
    OR v_run.curator_identity IS NULL OR v_run.validator_identity IS NULL
    OR v_run.curator_identity=v_run.validator_identity
 THEN RAISE EXCEPTION 'IG_M107_TRUSTED_RUN_NOT_PINNED:%',p_run_id; END IF;
 -- G1 verifies the live authority. The full manifest check below is
 -- separately necessary; source identity alone ignores lifecycle changes.
 v_packet:=programacion.fn_input_governance_run_context_packet_v1(p_run_id);
 IF v_packet->>'run_id' IS DISTINCT FROM p_run_id::text
    OR v_packet->>'source_snapshot_sha256' IS DISTINCT FROM v_run.source_snapshot_sha256
    OR v_packet->>'contract_snapshot_sha256' IS DISTINCT FROM v_run.contract_snapshot_sha256
 THEN RAISE EXCEPTION 'IG_M107_TRUSTED_G1_IDENTITY_MISMATCH:%',p_run_id; END IF;
 v_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
 IF v_manifest IS DISTINCT FROM v_run.source_manifest
    OR programacion.fn_v09_sha256_jsonb(v_manifest) IS DISTINCT FROM v_run.source_snapshot_sha256
 THEN RAISE EXCEPTION 'IG_M107_TRUSTED_FULL_MANIFEST_STALE:%',p_run_id; END IF;
 v_graph_receipt:=(SELECT e.value FROM jsonb_array_elements(v_manifest) e(value)
                   WHERE e.value->'ref'->>'kind'='SCREEN_CANONICAL_GRAPH' LIMIT 1);
 IF v_graph_receipt IS NULL OR v_graph_receipt->>'observed_sha256' IS NULL
 THEN RAISE EXCEPTION 'IG_M107_TRUSTED_GRAPH_RECEIPT_MISSING:%',p_run_id; END IF;
 v_graph:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
 IF programacion.fn_v09_sha256_jsonb(v_graph) IS DISTINCT FROM v_graph_receipt->>'observed_sha256'
 THEN RAISE EXCEPTION 'IG_M107_TRUSTED_CANONICAL_GRAPH_STALE:%',p_run_id; END IF;
 -- Effective links are calculated once; selectors for transport are applied
 -- later, never by silently omitting authority rows in this source dataset.
 WITH links AS MATERIALIZED (
  SELECT l.regla_id,l.binding_source
  FROM programacion.fn_input_effective_rule_links_v1(v_run.pantalla_id,'INPUT_GOVERNANCE') l
 ), rules AS MATERIALIZED (
  SELECT jsonb_build_object('regla_id',r.id,'codigo',r.codigo,
    'valor_config',r.valor_config,'estado',r.estado,'binding_source',l.binding_source) val,r.id
  FROM links l JOIN lf_ops.reglas r ON r.id=l.regla_id
 ), contracts AS MATERIALIZED (
  SELECT jsonb_build_object('contrato_codigo',c.contrato_codigo,'id',c.id,
    'version_id',c.version_id,'fail_closed',c.fail_closed,'estado',c.estado,
    'especificacion',c.especificacion) val,c.contrato_codigo,c.id
  FROM programacion.contratos c
  WHERE c.version_id=v_run.version_id AND c.estado='defined' AND c.fail_closed
 ), families AS MATERIALIZED (
  SELECT jsonb_build_object('family_code',a.family_code,'severity',a.severity,
    'applicability',a.applicability,'source_refs',a.source_refs,
    'negative_requirements',a.negative_requirements,'test_obligations',a.test_obligations,
    'freshness',a.freshness,'coverage_status',a.coverage_status,
    'well_defined_status',a.well_defined_status) val,a.family_code
  FROM programacion.input_family_assessments a WHERE a.run_id=p_run_id
 )
 SELECT (SELECT coalesce(jsonb_agg(val ORDER BY id),'[]'::jsonb) FROM rules),
        (SELECT coalesce(jsonb_agg(val ORDER BY contrato_codigo,id),'[]'::jsonb) FROM contracts),
        (SELECT coalesce(jsonb_agg(val ORDER BY family_code),'[]'::jsonb) FROM families),
        (SELECT count(*) FROM rules),(SELECT count(*) FROM contracts),(SELECT count(*) FROM families)
 INTO v_rules,v_contracts,v_families,n_rules,n_contracts,n_families;
 IF n_rules=0 OR n_contracts=0 OR n_families<>v_run.family_count
    OR (SELECT count(DISTINCT x.value->>'regla_id') FROM jsonb_array_elements(v_rules) x(value))<>n_rules
    OR (SELECT count(DISTINCT x.value->>'contrato_codigo') FROM jsonb_array_elements(v_contracts) x(value))<>n_contracts
    OR (SELECT count(DISTINCT x.value->>'family_code') FROM jsonb_array_elements(v_families) x(value))<>n_families
 THEN RAISE EXCEPTION 'IG_M107_TRUSTED_SNAPSHOT_UNIVERSE_MISMATCH:%',p_run_id; END IF;
 RETURN jsonb_build_object(
   'identity',jsonb_build_object('run_id',v_run.id,'pantalla_id',v_run.pantalla_id,
     'version_id',v_run.version_id,'contract_snapshot_sha256',v_run.contract_snapshot_sha256,
     'source_snapshot_sha256',v_run.source_snapshot_sha256),
   'data',jsonb_build_object('rules',v_rules,'contracts',v_contracts,
     'families',v_families,'graph',v_graph));
END $fn$;
REVOKE ALL ON FUNCTION programacion.fn_ig_m107_trusted_run_data_v1(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
DO $verify$
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
  ('IG-M107-RUN-PROJECTION-PROVIDER-026','IG-M107-LOT-A-PROFILE-027'))<>2
 THEN RAISE EXCEPTION 'IG_M107_F_PRIOR_EKB_MISSING'; END IF;
 IF has_function_privilege('anon','programacion.fn_ig_m107_trusted_run_data_v1(bigint)','EXECUTE')
   OR has_function_privilege('authenticated','programacion.fn_ig_m107_trusted_run_data_v1(bigint)','EXECUTE')
   OR has_function_privilege('service_role','programacion.fn_ig_m107_trusted_run_data_v1(bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'IG_M107_F_BACKEND_ONLY_ACL_FAILED'; END IF;
 BEGIN
  PERFORM programacion.fn_ig_m107_trusted_run_data_v1(933);
  RAISE EXCEPTION 'IG_M107_F_TX_NEGATIVE_NOT_REJECTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'IG_M107_TRUSTED_SNAPSHOT_TX_REQUIRED' THEN RAISE; END IF;
 END;
END $verify$;
INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
 frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
 lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
VALUES (
 gen_random_uuid(),'IG-M107-F-TRUSTED-BACKEND-LOADER-028','GOVERNANCE',
 'M10.7 F: loader backend canónico (candidato aislado)',
 'Extractor SQL backend de reglas, contratos, familias y grafo por run con identidad pin y verificación de manifiesto completo.',
 'Proveedor selectivo carecía de un origen SQL confiable y congelado por ejecución.',
 'RUN_SCOPED_BACKEND_TRUSTED_DATA_EXTRACTION',
 'Usar transacción READ ONLY REPEATABLE READ y currentness original, manifiesto íntegro y grafo hash. No otorgar accesos públicos ni conectar consumidores sin autorización.',
 'Función SQL, permisos y negativo transaccional comprobados en Train; tests JS candidatos. Sin prueba positiva de run VALIDATING, ni rendimiento total, ni CP3/G3.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_F','ACTIVO',
 jsonb_build_object('schema_version','IG_M107_F_TRUSTED_BACKEND_LOADER_V1',
   'status','BACKEND_ONLY_CANDIDATE','sql_function','programacion.fn_ig_m107_trusted_run_data_v1(bigint)',
   'consumer_wired',false,'runtime_deployed',false,'positive_live_run_verified',false,
   'grant_public',false,'grant_service_role',false,'cp3_closed',false,'g3_active',false)::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'Candidato dormante; no ejecutar desde HTTP ni uso productivo',
 'docs/ig/IG_M107_F_TRUSTED_BACKEND_LOADER_V1.md');
