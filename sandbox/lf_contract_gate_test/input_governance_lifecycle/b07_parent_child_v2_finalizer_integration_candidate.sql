-- B07 PADRE/HIJA — INTEGRACION CANDIDATA DEL FINALIZADOR OFICIAL V2 LF.
-- EJECUTAR SOLO EN POSTGRES AISLADO. No modifica la migración V2 desplegada.
-- Requiere primero b07_parent_child_candidate_up.sql.
BEGIN;
DO $check$
BEGIN
 IF to_regprocedure('public.lf_ig_rule_finalize_v2(text)') IS NULL OR
    to_regclass('lf_ops.reglas_versiones_b07') IS NULL OR
    to_regclass('saly.reglas_versiones_b07') IS NULL
 THEN RAISE EXCEPTION 'B07_V2_OR_HISTORY_MISSING'; END IF;
END $check$;

-- Evita una ruta alternativa de escritura directa por service_role:
-- únicamente FINALIZE_V2 (SECURITY DEFINER y sus gates oficiales) llama el helper privado.
REVOKE ALL ON FUNCTION public.lf_b07_append_version_candidate_v1(
 text,text,text,text,text,text,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.lf_b07_append_after_finalize_v1(p_child text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','extensions'
AS $b07$
DECLARE ch public.lf_ig_rule_change_v2%ROWTYPE;
        d public.lf_ig_owner_decision_v2%ROWTYPE;
        r lf_ops.reglas%ROWTYPE;
        prev_no integer; prev_sha text; now_sha text; next_v integer;
BEGIN
 SELECT * INTO ch FROM public.lf_ig_rule_change_v2
 WHERE child_execution_id=p_child AND state='VIGENTE_VERIFIED'
 AND finalized_snapshot_sha256 IS NOT NULL
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_OFFICIAL_FINALIZER_RECEIPT_MISSING'; END IF;
 SELECT * INTO d FROM public.lf_ig_owner_decision_v2
 WHERE decision_id=ch.owner_decision_id AND verdict='APROBAR'
 AND rule_code=ch.rule_code AND decision_record_sha256 ~ '^[0-9a-f]{64}$'
 AND identity_mode='UNVERIFIED_CHAT_DECLARATION';
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_OWNER_DECISION_RECORD_MISSING'; END IF;
 -- No aceptar llamadas con pasos que no hayan sido verificados por V2.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e
  WHERE e.execution_id=p_child AND e.created_by_execution_id=ch.parent_execution_id
    AND e.status='COMPLETED') OR
 (SELECT count(*) FROM public.lf_operation_execution_steps
    WHERE execution_id=p_child AND status='PASS_CLEAN')<>7
 THEN RAISE EXCEPTION 'B07_FINALIZER_CHILD_CONTRACT_MISSING'; END IF;
 SELECT * INTO r FROM lf_ops.reglas WHERE codigo=ch.rule_code AND estado='VIGENTE'
 AND NOT pendiente_decision FOR UPDATE;
 IF NOT FOUND OR public.lf_asset_snapshot_sha_v1('REGLA',ch.rule_code)
    IS DISTINCT FROM ch.finalized_snapshot_sha256
 THEN RAISE EXCEPTION 'B07_FINALIZER_POSTIMAGE_DRIFT'; END IF;
 SELECT version_no,snapshot_sha256 INTO prev_no,prev_sha FROM lf_ops.reglas_versiones_b07
 WHERE rule_id=r.id ORDER BY version_no DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN
   IF ch.kind<>'CREATE' THEN RAISE EXCEPTION 'B07_PARENT_BASELINE_MISSING'; END IF;
   prev_no:=0; prev_sha:=NULL;
 END IF;
 now_sha:=encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex');
 IF now_sha=prev_sha THEN
    RAISE EXCEPTION 'B07_FINALIZER_HISTORY_ALREADY_SAME'; END IF;
 IF nullif(btrim(d.decisor),'') IS NULL OR d.decision_date IS NULL
 THEN RAISE EXCEPTION 'B07_FINALIZER_DECISION_EVIDENCE_MISSING'; END IF;
 next_v:=prev_no+1;
 INSERT INTO lf_ops.reglas_versiones_b07(
    rule_id,version_no,snapshot,snapshot_sha256,previous_sha256,origin,
    decision_ref,decisor,decision_record_sha256,decided_at,writer_execution_id)
 VALUES(r.id,next_v,to_jsonb(r),now_sha,prev_sha,'GOVERNED_APPEND',
    d.decision_id::text,d.decisor,d.decision_record_sha256,d.decision_date,p_child);
 RETURN jsonb_build_object('version_no',next_v,'sha256',now_sha,
   'identity_verified',false,'source','OFFICIAL_LF_IG_FINALIZER_V2');
END $b07$;
REVOKE ALL ON FUNCTION public.lf_b07_append_after_finalize_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;
-- Modificación controlada de la DEFINICIÓN V2 en copia aislada.
-- Se injerta únicamente llamada posterior al receipt VIGENTE_VERIFIED y previo al RETURN.
-- No permitir que un cambio de fuente V2 pase silenciosamente.
DO $inject$
DECLARE src text; needle text;
BEGIN
 SELECT pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure) INTO src;
 needle:='RETURN jsonb_build_object(''status'',''VIGENTE_VERIFIED'',''rule_code'',ch.rule_code,';
 IF src IS NULL OR strpos(src,needle)=0 OR
    strpos(src,'PERFORM public.lf_b07_append_after_finalize_v1(p_child);')>0
 THEN RAISE EXCEPTION 'B07_V2_FINALIZER_SOURCE_DRIFT_OR_REPLAY'; END IF;
 src:=replace(src,needle,
   'PERFORM public.lf_b07_append_after_finalize_v1(p_child);'||E'\n  '||needle);
 EXECUTE src;
 IF strpos(pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure),
 'PERFORM public.lf_b07_append_after_finalize_v1(p_child);')=0
 THEN RAISE EXCEPTION 'B07_OFFICIAL_FINALIZER_INJECTION_FAILED'; END IF;
END $inject$;

-- RLS: la HIJA solo se consulta por service_role; cero DML directo.
CREATE POLICY lf_b07_history_service_read ON lf_ops.reglas_versiones_b07
 FOR SELECT TO service_role USING (true);
CREATE POLICY saly_b07_history_service_read ON saly.reglas_versiones_b07
 FOR SELECT TO service_role USING (true);
GRANT SELECT ON lf_ops.reglas_versiones_b07,saly.reglas_versiones_b07 TO service_role;
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON
 lf_ops.reglas_versiones_b07,saly.reglas_versiones_b07 FROM PUBLIC,anon,authenticated,service_role;

-- Consumidores protegidos: vistas solo para rol de servicio.
CREATE VIEW public.lf_b07_rules_current_v1 WITH (security_barrier=true)
 AS SELECT r.* FROM lf_ops.reglas r
 WHERE r.estado='VIGENTE' AND NOT r.pendiente_decision;
CREATE VIEW public.saly_b07_rules_current_v1 WITH (security_barrier=true)
 AS SELECT r.* FROM saly.reglas r
 WHERE r.estado='VALIDADO' AND r.vigente=true;
REVOKE ALL ON public.lf_b07_rules_current_v1,public.saly_b07_rules_current_v1
 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.lf_b07_rules_current_v1,public.saly_b07_rules_current_v1
 TO service_role;
COMMIT;
