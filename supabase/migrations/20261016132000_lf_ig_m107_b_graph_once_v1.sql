-- IG M10.7/B: no new triggers or global cache. Pin and reuse one verified
-- graph only inside a trusted READ ONLY REPEATABLE READ source load.
-- F loader must already be present, including its backend-only ACL.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m107_trusted_run_data_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $fn$
DECLARE
 v_run programacion.input_readiness_runs%rowtype;
 v_packet jsonb; v_manifest jsonb; v_graph jsonb; v_graph_receipt jsonb;
 v_graph_sha text; v_prior_context text:=current_setting('lf.input_request_context_v1',true);
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
 IF nullif(v_prior_context,'') IS NOT NULL THEN
   RAISE EXCEPTION 'IG_M107_B_PREEXISTING_GRAPH_CONTEXT_FORBIDDEN'; END IF;
 -- Existing canonical graph builder recognizes an SHA-bound request context.
 -- Scoped here to a single READ ONLY REPEATABLE READ load, not a session cache.
 v_graph:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
 v_graph_sha:=programacion.fn_v09_sha256_jsonb(v_graph);
 PERFORM set_config('lf.input_request_context_v1',
   jsonb_build_object('schema_version','INPUT_GOVERNANCE_REQUEST_CONTEXT_V1',
     'pantalla_id',v_run.pantalla_id,'version_id',v_run.version_id,
     'graph',v_graph,'graph_sha256',v_graph_sha)::text,true);
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
 -- Reuse the verified graph built before G1; same transaction snapshot.
 IF v_graph_sha IS DISTINCT FROM v_graph_receipt->>'observed_sha256'
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
 PERFORM set_config('lf.input_request_context_v1',coalesce(v_prior_context,''),true);
 RETURN jsonb_build_object(
   'identity',jsonb_build_object('run_id',v_run.id,'pantalla_id',v_run.pantalla_id,
     'version_id',v_run.version_id,'contract_snapshot_sha256',v_run.contract_snapshot_sha256,
     'source_snapshot_sha256',v_run.source_snapshot_sha256),
   'data',jsonb_build_object('rules',v_rules,'contracts',v_contracts,
     'families',v_families,'graph',v_graph));
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('lf.input_request_context_v1',coalesce(v_prior_context,''),true);
 RAISE;
END $fn$;
DO $probe$
DECLARE v_graph jsonb; v_copy jsonb; v_sha text; v_ctx jsonb;
        v_builds_before integer; v_builds_after integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-F-TRUSTED-BACKEND-LOADER-028')
 THEN RAISE EXCEPTION 'IG_M107_B_LOADER_DEPENDENCY_MISSING'; END IF;
 IF nullif(current_setting('lf.input_request_context_v1',true),'') IS NOT NULL
 THEN RAISE EXCEPTION 'IG_M107_B_CONTEXT_DIRTY_PRETEST'; END IF;
 PERFORM set_config('lf.input_request_graph_build_count_v1','0',true);
 v_graph:=programacion.fn_input_screen_canonical_graph(43,19);
 v_sha:=programacion.fn_v09_sha256_jsonb(v_graph);
 v_builds_before:=current_setting('lf.input_request_graph_build_count_v1',true)::integer;
 v_ctx:=jsonb_build_object('schema_version','INPUT_GOVERNANCE_REQUEST_CONTEXT_V1',
   'pantalla_id',43,'version_id',19,'graph',v_graph,'graph_sha256',v_sha);
 PERFORM set_config('lf.input_request_context_v1',v_ctx::text,true);
 v_copy:=programacion.fn_input_screen_canonical_graph(43,19);
 PERFORM programacion.fn_input_screen_canonical_graph(43,19);
 v_builds_after:=current_setting('lf.input_request_graph_build_count_v1',true)::integer;
 IF v_copy IS DISTINCT FROM v_graph OR v_sha IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_copy)
    OR v_builds_before<>1 OR v_builds_after<>1
 THEN RAISE EXCEPTION 'IG_M107_B_SINGLE_GRAPH_BUILD_OR_PARITY_FAILED:%:%',v_builds_before,v_builds_after; END IF;
 -- Tampered SHA must fail closed; the request context never bypasses integrity.
 PERFORM set_config('lf.input_request_context_v1',(v_ctx||jsonb_build_object('graph_sha256',repeat('0',64)))::text,true);
 BEGIN
   PERFORM programacion.fn_input_screen_canonical_graph(43,19);
   RAISE EXCEPTION 'IG_M107_B_TAMPER_NOT_REJECTED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'INPUT_REQUEST_CONTEXT_GRAPH_SHA_MISMATCH:43:19' THEN RAISE; END IF;
 END;
 PERFORM set_config('lf.input_request_context_v1','',true);
 PERFORM set_config('lf.input_request_graph_build_count_v1','',true);
 IF has_function_privilege('service_role','programacion.fn_ig_m107_trusted_run_data_v1(bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'IG_M107_B_ACL_DRIFT'; END IF;
END $probe$;

INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
 frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
 lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
VALUES (
 gen_random_uuid(),'IG-M107-B-GRAPH-INVOKE-REUSE-029','GOVERNANCE',
 'M10.7 B: reuso SHA-bound del grafo en un loader read-only',
 'El loader F crea un grafo por ejecucion y lo reusa durante las comprobaciones G1 y full-manifest del mismo snapshot PostgreSQL.',
 'Sin un request context, G1 y el chequeo completo reconstruian el grafo de la pantalla multiples veces.',
 'RUN_SCOPED_GRAPH_ONCE_SHA_VERIFIED',
 'Cache unicamente de llamada, solo transaccion READ ONLY REPEATABLE READ, SHA correcto, cleanup en exito/error. Mantener full manifest, currentness, ACL y Q0-Q8. No tocar triggers ni extrapolar ahorro al Validator.',
 'Train verifica 1 construccion para 3 lecturas, JSONB y SHA iguales, alteracion SHA rechazada y ACL intacta. Sin test de runtime VALIDATING ni benchmark comparable; B aun no esta cerrado.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_B','ACTIVO',
 jsonb_build_object('schema_version','IG_M107_B_GRAPH_REUSE_V1',
    'scope','BACKEND_ONLY_LOADER','graph_builds_sample',1,'graph_reads_sample',3,
    'tamper_sha_rejected',true,'full_manifest_guard_retained',true,
    'g1_currentness_retained',true,'trigger_modified',false,'runtime_wired',false,
    'B_complete',false,'cp3_closed',false)::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'Per-invocation graph optimization candidate; no consumer activation',
 'docs/ig/IG_M107_F_TRUSTED_BACKEND_LOADER_V1.md');
