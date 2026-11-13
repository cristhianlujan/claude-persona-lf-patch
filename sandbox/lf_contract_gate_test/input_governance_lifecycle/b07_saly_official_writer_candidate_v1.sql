-- B07 SALY: escritor candidato integrado a ejecución gobernada del mismo motor LF.
-- NO REGISTRA operaciones ni owners; fail-closed hasta que ambos existan por ruta oficial.
-- NO EJECUTAR EN SUPABASE. Se ejecuta exclusivamente en PostgreSQL CI aislado.
-- Requiere B07 UP y bridge V2 LF en la MISMA ventana de despliegue futura.
BEGIN;
DO $gate$
BEGIN
 IF to_regclass('saly.reglas_versiones_b07') IS NULL OR
    to_regclass('public.lf_ig_owner_decision_v2') IS NULL OR
    to_regclass('public.lf_ig_project_owner_v2') IS NULL OR
    to_regclass('public.lf_operation_execution') IS NULL
 THEN RAISE EXCEPTION 'B07_SALY_EXISTING_GOVERNANCE_CONTRACT_MISSING'; END IF;
 IF to_regclass('public.lf_b07_saly_finalization_receipt_v1') IS NOT NULL OR
    to_regprocedure('public.lf_ig_saly_rule_finalize_b07_v1(text)') IS NOT NULL
 THEN RAISE EXCEPTION 'B07_SALY_WRITER_ALREADY_EXISTS'; END IF;
END $gate$;

CREATE TABLE public.lf_b07_saly_finalization_receipt_v1 (
 child_execution_id text PRIMARY KEY REFERENCES public.lf_operation_execution(execution_id) ON DELETE RESTRICT,
 rule_id bigint NOT NULL REFERENCES saly.reglas(id) ON DELETE RESTRICT,
 owner_decision_id uuid NOT NULL REFERENCES public.lf_ig_owner_decision_v2(decision_id) ON DELETE RESTRICT,
 source_snapshot_sha256 text NOT NULL CHECK(source_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 finalized_snapshot_sha256 text NOT NULL CHECK(finalized_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 version_no integer NOT NULL CHECK(version_no>1),
 identity_verified boolean NOT NULL DEFAULT false CHECK(identity_verified=false),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT b07_saly_unique_version_receipt UNIQUE(rule_id,version_no),
 CONSTRAINT b07_saly_distinct_source CHECK(source_snapshot_sha256<>finalized_snapshot_sha256)
);
ALTER TABLE public.lf_b07_saly_finalization_receipt_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_b07_saly_finalization_receipt_v1 FROM PUBLIC,anon,authenticated,service_role;
CREATE POLICY b07_saly_receipt_service_select ON public.lf_b07_saly_finalization_receipt_v1
 FOR SELECT TO service_role USING (true);
GRANT SELECT ON public.lf_b07_saly_finalization_receipt_v1 TO service_role;

-- SOLO operación SALY gobernada completa + recibo V2 SALY ligado a owner/decisión nativa SALY.
-- La única función que escribe PADRE y HIJA es esta, sin DML otorgado a service_role.
-- Dependencia real: ACTUALIZACION_REGLA_SALY no está registrada hoy; el registro
-- oficial y el owner SALY se deben tramitar separados por la ruta EKB (NO-GO live).
CREATE FUNCTION public.lf_ig_saly_rule_finalize_b07_v1(p_child text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','saly','extensions'
AS $writer$
DECLARE e public.lf_operation_execution%ROWTYPE;
 par public.lf_operation_execution%ROWTYPE;
 d public.lf_ig_owner_decision_v2%ROWTYPE;
 own public.lf_ig_project_owner_v2%ROWTYPE;
 native_dec record;
 r saly.reglas%ROWTYPE;
 h saly.reglas_versiones_b07%ROWTYPE;
 receipt public.lf_b07_saly_finalization_receipt_v1%ROWTYPE;
 changes jsonb;
 before_sha text; after_sha text; v_no integer;
BEGIN
 IF p_child IS NULL OR btrim(p_child)='' THEN RAISE EXCEPTION 'B07_SALY_CHILD_REQUIRED'; END IF;
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_child FOR UPDATE;
 IF NOT FOUND OR e.operation_code<>'ACTUALIZACION_REGLA_SALY' OR e.status<>'COMPLETED'
 THEN RAISE EXCEPTION 'B07_SALY_REGISTERED_CHILD_REQUIRED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_registry cat
     WHERE cat.operation_code='ACTUALIZACION_REGLA_SALY'
     AND cat.status='SANDBOX_ACTIVE')
 THEN RAISE EXCEPTION 'B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED'; END IF;
 SELECT * INTO par FROM public.lf_operation_execution
 WHERE execution_id=e.created_by_execution_id
 AND operation_code='EJECUCION_PERFIL_LF'
 AND status='IN_PROGRESS'
 AND manifest->>'project_code'='SALY'
 AND manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true';
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_SALY_ROUTER_PROFILE_RUN_REQUIRED'; END IF;
 IF (SELECT count(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=p_child AND s.status='PASS_CLEAN')<>7 OR
    (SELECT count(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=p_child)<>7
 THEN RAISE EXCEPTION 'B07_SALY_CHILD_SEVEN_CLEAN_STEPS_REQUIRED'; END IF;
 SELECT * INTO d FROM public.lf_ig_owner_decision_v2
 WHERE parent_execution_id=par.execution_id
 AND project_code='SALY' AND rule_code=e.target_code
 AND verdict='APROBAR' AND kind='CORRECT_VIGENTE';
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_SALY_V2_OWNER_DECISION_REQUIRED'; END IF;
 SELECT * INTO own FROM public.lf_ig_project_owner_v2
 WHERE project_code='SALY' AND owner_sub=d.owner_sub
 AND owner_name=d.decisor AND status='TEMP_DOCUMENTARY_ACTIVE'
 AND identity_mode='UNVERIFIED_CHAT_DECLARATION';
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_SALY_OWNER_REGISTRY_MISSING'; END IF;
 IF d.identity_mode<>'UNVERIFIED_CHAT_DECLARATION' OR d.decision_date IS NULL
 OR d.decision_record IS NULL OR d.literal_phrase IS NULL OR
 length(btrim(d.literal_phrase))<6 OR d.proponente=d.decisor OR
 d.decision_record_sha256 IS DISTINCT FROM
 encode(extensions.digest(convert_to(d.decision_record::text,'UTF8'),'sha256'),'hex')
 THEN RAISE EXCEPTION 'B07_SALY_DECISION_EVIDENCE_INCOMPLETE'; END IF;
 SELECT * INTO r FROM saly.reglas
 WHERE codigo=e.target_code AND estado='VALIDADO' AND vigente=true
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_SALY_VALIDADO_PARENT_REQUIRED'; END IF;
 SELECT dec.id,dec.estado,dec.vigente INTO native_dec FROM saly.decisiones dec
 WHERE dec.id=r.decision_id AND dec.estado='VALIDADO' AND dec.vigente=true;
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_SALY_NATIVE_DECISION_MISSING'; END IF;
 IF d.decision_record->>'saly_decision_id' IS DISTINCT FROM r.decision_id::text OR
    d.decision_record->>'rule_code' IS DISTINCT FROM r.codigo OR
    d.decision_record->>'source_sha256' IS DISTINCT FROM d.source_sha256
 THEN RAISE EXCEPTION 'B07_SALY_NATIVE_DECISION_LINK_MISMATCH'; END IF;
 SELECT * INTO receipt FROM public.lf_b07_saly_finalization_receipt_v1
 WHERE child_execution_id=p_child FOR UPDATE;
 IF FOUND THEN
   SELECT * INTO h FROM saly.reglas_versiones_b07
     WHERE rule_id=r.id ORDER BY version_no DESC LIMIT 1;
   after_sha:=encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex');
   IF receipt.rule_id<>r.id OR receipt.owner_decision_id<>d.decision_id OR
     receipt.finalized_snapshot_sha256<>after_sha OR h.version_no<>receipt.version_no OR
     h.snapshot_sha256<>after_sha
   THEN RAISE EXCEPTION 'B07_SALY_REPLAY_SOURCE_DRIFT'; END IF;
   RETURN jsonb_build_object('status','VALIDADO_VERIFIED','replay',true,
     'rule_code',r.codigo,'version',receipt.version_no,
     'snapshot_sha256',after_sha,'identity_verified',false);
 END IF;
 SELECT * INTO h FROM saly.reglas_versiones_b07
 WHERE rule_id=r.id ORDER BY version_no DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_SALY_BASELINE_MISSING'; END IF;
 before_sha:=encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex');
 IF before_sha<>h.snapshot_sha256 OR to_jsonb(r) IS DISTINCT FROM h.snapshot OR
    d.source_sha256<>before_sha
 THEN RAISE EXCEPTION 'B07_SALY_STALE_PARENT_HASH'; END IF;
 IF d.approved_patch->>'change_kind'<>'DOCUMENTARY_ONLY'
 OR jsonb_typeof(d.approved_patch->'changes') IS DISTINCT FROM 'object'
 OR d.proposal_sha256 IS DISTINCT FROM
   encode(extensions.digest(convert_to(d.approved_patch::text,'UTF8'),'sha256'),'hex')
 THEN RAISE EXCEPTION 'B07_SALY_APPROVED_PATCH_EVIDENCE_INVALID'; END IF;
 changes:=d.approved_patch->'changes';
 IF changes='{}'::jsonb OR EXISTS(
   SELECT 1 FROM jsonb_object_keys(changes) AS key(name)
   WHERE name NOT IN ('titulo','razon','fuente'))
 THEN RAISE EXCEPTION 'B07_SALY_DOCUMENTARY_ONLY_SCOPE'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(changes) AS v(key,val)
   WHERE jsonb_typeof(v.val) NOT IN ('string','null'))
 THEN RAISE EXCEPTION 'B07_SALY_DOCUMENTARY_VALUE_INVALID'; END IF;
 -- No se modifica regla, estado, vigente, decision_id, valor_config ni código.
 UPDATE saly.reglas SET
    titulo=COALESCE(changes->>'titulo',titulo),
    razon=CASE WHEN changes ? 'razon' THEN changes->>'razon' ELSE razon END,
    fuente=CASE WHEN changes ? 'fuente' THEN changes->>'fuente' ELSE fuente END,
    updated_at=now()
 WHERE id=r.id AND estado='VALIDADO' AND vigente=true AND decision_id=r.decision_id
 RETURNING * INTO r;
 IF NOT FOUND THEN RAISE EXCEPTION 'B07_SALY_PARENT_UPDATE_REJECTED'; END IF;
 after_sha:=encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex');
 IF after_sha=before_sha THEN RAISE EXCEPTION 'B07_SALY_UNCHANGED_RULE'; END IF;
 v_no:=h.version_no+1;
 INSERT INTO saly.reglas_versiones_b07(
 rule_id,version_no,snapshot,snapshot_sha256,previous_sha256,origin,
 decision_ref,decisor,decision_record_sha256,decided_at,writer_execution_id)
 VALUES(r.id,v_no,to_jsonb(r),after_sha,before_sha,'GOVERNED_APPEND',
 d.decision_id::text,d.decisor,d.decision_record_sha256,d.decision_date,p_child);
 INSERT INTO public.lf_b07_saly_finalization_receipt_v1(
 child_execution_id,rule_id,owner_decision_id,source_snapshot_sha256,
 finalized_snapshot_sha256,version_no)
 VALUES(p_child,r.id,d.decision_id,before_sha,after_sha,v_no);
 RETURN jsonb_build_object('status','VALIDADO_VERIFIED','replay',false,
   'rule_code',r.codigo,'version',v_no,'previous_sha256',before_sha,
   'snapshot_sha256',after_sha,'owner_decision_id',d.decision_id,
   'identity_verified',false,'production_authorized',false);
END $writer$;
REVOKE ALL ON FUNCTION public.lf_ig_saly_rule_finalize_b07_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_saly_rule_finalize_b07_v1(text) TO service_role;

-- SQL candidato *NO* materializa la operación ni la identidad SALY en tablas vivas.
-- Sin owner+operación SALY oficiales, el único RPC permanece fail-closed.
COMMIT;
