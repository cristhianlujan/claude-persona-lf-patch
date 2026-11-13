-- B07 official atomic migration candidate. DO NOT DEPLOY WITHOUT OWNER'S EXPLICIT DDL OK.
-- All component files pinned by Git SHA, atomized into one transaction; this file
-- is the exact source the governed Merge Train must carry after the SALY operation
-- and project owner have been admitted in a separate Train. No operation/owner
-- is fabricated in this migration. No historical RUN is altered.
-- Sources (Git blobs):
-- UP d3962191b547d4613198dc68b5d196932a6ab14f
-- V2 bridge aa9f177d4fab048c058c03d8b0bf9ab6d1ac6a90
-- SALY writer ff6d47c70f42f5fb2ad6f8b132caf278ec16c79d
-- Requirements: backup / restore proof + owner DDL confirmation + HEAD exact CI.
BEGIN;
DO $b07_preflight$
BEGIN
  IF to_regclass('public.lf_operation_registry') IS NULL OR
     to_regclass('public.lf_ig_project_owner_v2') IS NULL OR
     to_regclass('public.lf_activos') IS NULL THEN
    RAISE EXCEPTION 'B07_GOVERNANCE_CATALOG_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='ACTUALIZACION_REGLA_SALY'
      AND status='SANDBOX_ACTIVE'
      AND lifecycle_state_code='OP_CANDIDATE'
      AND created_by_execution_id IS NOT NULL
  ) THEN RAISE EXCEPTION 'B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_ig_project_owner_v2 o
    WHERE o.project_code='SALY'
      AND o.status='TEMP_DOCUMENTARY_ACTIVE'
      AND o.identity_mode='UNVERIFIED_CHAT_DECLARATION'
      AND o.authority_receipt_sha256 ~ '^[0-9a-f]{64}$'
      AND EXISTS (SELECT 1 FROM public.lf_activos a
        WHERE a.codigo_activo=o.owner_profile_code
          AND a.tipo_activo='PERFIL' AND a.archived_at IS NULL)
  ) THEN RAISE EXCEPTION 'B07_SALY_OWNER_AND_PROFILE_GOVERNED_REQUIRED'; END IF;
END $b07_preflight$;


-- === COMPONENT 1: sandbox/lf_contract_gate_test/input_governance_lifecycle/b07_parent_child_candidate_up.sql (single Train transaction) ===
-- B07 PADRE/HIJA CANDIDATO V1, no firmado. NO INSTALAR EN SUPABASE.
-- Sin ALTER TABLE lf_ops.reglas ni saly.reglas. SOLO datos sintéticos en CI.
-- IMPORTANTE: V2 oficial actualiza el padre in situ. Requiere integración
-- transaccional al escritor antes de cualquier despliegue real (NO-GO).
DO $check$
BEGIN
  IF to_regclass('lf_ops.reglas') IS NULL OR to_regclass('saly.reglas') IS NULL
     THEN RAISE EXCEPTION 'B07_PARENT_MISSING'; END IF;
  IF to_regclass('lf_ops.reglas_versiones_b07') IS NOT NULL
     OR to_regclass('saly.reglas_versiones_b07') IS NOT NULL
     THEN RAISE EXCEPTION 'B07_HISTORY_ALREADY_EXISTS'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')
     THEN RAISE EXCEPTION 'B07_WRITER_ROLE_MISSING'; END IF;
END $check$;

CREATE TABLE lf_ops.reglas_versiones_b07 (
  version_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rule_id integer NOT NULL REFERENCES lf_ops.reglas(id) ON DELETE RESTRICT,
  version_no integer NOT NULL CHECK (version_no>0),
  snapshot jsonb NOT NULL,
  snapshot_sha256 text NOT NULL CHECK (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  previous_sha256 text CHECK (previous_sha256 IS NULL OR previous_sha256 ~ '^[0-9a-f]{64}$'),
  origin text NOT NULL CHECK (origin IN ('BASELINE_CURRENT_ONLY','GOVERNED_APPEND')),
  decision_ref text,
  decisor text,
  decision_record_sha256 text,
  decided_at timestamptz,
  writer_execution_id text,
  identity_verified boolean NOT NULL DEFAULT false CHECK (identity_verified=false),
  captured_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lf_b07_history_unique_version UNIQUE (rule_id,version_no),
  CONSTRAINT lf_b07_history_unique_snapshot UNIQUE (rule_id,snapshot_sha256),
  CONSTRAINT lf_b07_history_sha CHECK (
    snapshot_sha256=encode(extensions.digest(convert_to(snapshot::text,'UTF8'),'sha256'),'hex')),
  CONSTRAINT lf_b07_history_evidence CHECK (
    (origin='BASELINE_CURRENT_ONLY' AND version_no=1 AND previous_sha256 IS NULL
      AND decision_ref IS NULL AND decisor IS NULL AND decided_at IS NULL
      AND decision_record_sha256 IS NULL AND writer_execution_id IS NULL)
    OR
    (origin='GOVERNED_APPEND' AND version_no>=1 AND
      ((version_no=1 AND previous_sha256 IS NULL) OR
       (version_no>1 AND previous_sha256 IS NOT NULL))
      AND nullif(btrim(decision_ref),'') IS NOT NULL
      AND nullif(btrim(decisor),'') IS NOT NULL
      AND nullif(btrim(writer_execution_id),'') IS NOT NULL
      AND decision_record_sha256 ~ '^[0-9a-f]{64}$' AND decided_at IS NOT NULL))
);
CREATE TABLE saly.reglas_versiones_b07 (
  version_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rule_id bigint NOT NULL REFERENCES saly.reglas(id) ON DELETE RESTRICT,
  version_no integer NOT NULL CHECK (version_no>0),
  snapshot jsonb NOT NULL,
  snapshot_sha256 text NOT NULL CHECK (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  previous_sha256 text CHECK (previous_sha256 IS NULL OR previous_sha256 ~ '^[0-9a-f]{64}$'),
  origin text NOT NULL CHECK (origin IN ('BASELINE_CURRENT_ONLY','GOVERNED_APPEND')),
  decision_ref text,
  decisor text,
  decision_record_sha256 text,
  decided_at timestamptz,
  writer_execution_id text,
  identity_verified boolean NOT NULL DEFAULT false CHECK (identity_verified=false),
  captured_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT saly_b07_history_unique_version UNIQUE (rule_id,version_no),
  CONSTRAINT saly_b07_history_unique_snapshot UNIQUE (rule_id,snapshot_sha256),
  CONSTRAINT saly_b07_history_sha CHECK (
    snapshot_sha256=encode(extensions.digest(convert_to(snapshot::text,'UTF8'),'sha256'),'hex')),
  CONSTRAINT saly_b07_history_evidence CHECK (
    (origin='BASELINE_CURRENT_ONLY' AND version_no=1 AND previous_sha256 IS NULL
      AND decision_ref IS NULL AND decisor IS NULL AND decided_at IS NULL
      AND decision_record_sha256 IS NULL AND writer_execution_id IS NULL)
    OR
    (origin='GOVERNED_APPEND' AND version_no>=1 AND
      ((version_no=1 AND previous_sha256 IS NULL) OR
       (version_no>1 AND previous_sha256 IS NOT NULL))
      AND nullif(btrim(decision_ref),'') IS NOT NULL
      AND nullif(btrim(decisor),'') IS NOT NULL
      AND nullif(btrim(writer_execution_id),'') IS NOT NULL
      AND decision_record_sha256 ~ '^[0-9a-f]{64}$' AND decided_at IS NOT NULL))
);
CREATE INDEX lf_b07_versions_latest ON lf_ops.reglas_versiones_b07(rule_id,version_no DESC);
CREATE INDEX saly_b07_versions_latest ON saly.reglas_versiones_b07(rule_id,version_no DESC);
ALTER TABLE lf_ops.reglas_versiones_b07 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.reglas_versiones_b07 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON lf_ops.reglas_versiones_b07,saly.reglas_versiones_b07 FROM PUBLIC,anon,authenticated,service_role;

-- Captura EXACTAMENTE el padre observado HOY; no inventa autor, firma ni versiones previas.
INSERT INTO lf_ops.reglas_versiones_b07(rule_id,version_no,snapshot,snapshot_sha256,origin)
SELECT r.id,1,to_jsonb(r),
  encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex'),
  'BASELINE_CURRENT_ONLY'
FROM lf_ops.reglas r;
INSERT INTO saly.reglas_versiones_b07(rule_id,version_no,snapshot,snapshot_sha256,origin)
SELECT r.id,1,to_jsonb(r),
  encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex'),
  'BASELINE_CURRENT_ONLY'
FROM saly.reglas r;

-- El padre debe igualar en COMMIT a la ultima version hija.
CREATE FUNCTION public.lf_b07_assert_parent_latest_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','saly','extensions'
AS $fn$
DECLARE rid bigint; got jsonb; latest jsonb;
BEGIN
  IF TG_TABLE_NAME='reglas' THEN
    rid:=COALESCE(NEW.id,OLD.id);
  ELSE
    rid:=COALESCE(NEW.rule_id,OLD.rule_id);
  END IF;
  IF TG_TABLE_SCHEMA='lf_ops' THEN
    SELECT to_jsonb(r) INTO got FROM lf_ops.reglas r WHERE r.id=rid;
    SELECT h.snapshot INTO latest FROM lf_ops.reglas_versiones_b07 h
       WHERE h.rule_id=rid ORDER BY h.version_no DESC LIMIT 1;
  ELSIF TG_TABLE_SCHEMA='saly' THEN
    SELECT to_jsonb(r) INTO got FROM saly.reglas r WHERE r.id=rid;
    SELECT h.snapshot INTO latest FROM saly.reglas_versiones_b07 h
       WHERE h.rule_id=rid ORDER BY h.version_no DESC LIMIT 1;
  ELSE RAISE EXCEPTION 'B07_SCHEMA_UNSUPPORTED'; END IF;
  IF got IS NULL OR latest IS NULL OR got IS DISTINCT FROM latest THEN
    RAISE EXCEPTION 'B07_PARENT_LATEST_MISMATCH:%:%',TG_TABLE_SCHEMA,rid;
  END IF;
  RETURN NULL;
END $fn$;
CREATE FUNCTION public.lf_b07_block_history_mutation_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path='pg_catalog','public'
AS $fn$ BEGIN
  RAISE EXCEPTION 'B07_HISTORY_IMMUTABLE';
END $fn$;
CREATE FUNCTION public.lf_b07_block_history_truncate_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path='pg_catalog','public'
AS $fn$ BEGIN
  RAISE EXCEPTION 'B07_HISTORY_TRUNCATE_BLOCKED';
END $fn$;

-- Seguridad: usuario del RPC = service_role; dentro actúa como owner privilegiado.
-- NO se autoriza como escritor oficial hasta el futuro contrato de integración.
CREATE FUNCTION public.lf_b07_append_version_candidate_v1(
  p_project text,p_rule_code text,p_expected_sha256 text,
  p_decision_ref text,p_decisor text,p_decision_record_sha256 text,
  p_decided_at timestamptz,p_writer_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','saly','extensions'
AS $fn$
DECLARE rid bigint; prev_sha text; n integer; s jsonb; new_sha text; v_state text;
BEGIN
  IF p_project NOT IN ('LF','SALY') THEN RAISE EXCEPTION 'B07_PROJECT_UNSUPPORTED'; END IF;
  IF p_expected_sha256 !~ '^[0-9a-f]{64}$' OR p_expected_sha256 IS NULL
    THEN RAISE EXCEPTION 'B07_EXPECTED_SHA_MISSING'; END IF;
  IF nullif(btrim(coalesce(p_decision_ref,'')),'') IS NULL OR
     nullif(btrim(coalesce(p_decisor,'')),'') IS NULL OR
     nullif(btrim(coalesce(p_writer_execution_id,'')),'') IS NULL OR
     p_decision_record_sha256 !~ '^[0-9a-f]{64}$' OR
     p_decision_record_sha256 IS NULL OR p_decided_at IS NULL
     THEN RAISE EXCEPTION 'B07_DECISION_EVIDENCE_INCOMPLETE'; END IF;
  IF p_project='LF' THEN
    SELECT r.id,to_jsonb(r),r.estado INTO rid,s,v_state
      FROM lf_ops.reglas r WHERE r.codigo=p_rule_code FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'B07_LF_PARENT_NOT_FOUND'; END IF;
    IF v_state<>'VIGENTE' THEN RAISE EXCEPTION 'B07_LF_NOT_VIGENTE'; END IF;
    -- Fuentes V2: decision_id documental existente, no firma humana verificada.
    IF NOT EXISTS (
      SELECT 1 FROM public.lf_ig_owner_decision_v2 d
      WHERE d.decision_id::text=p_decision_ref
        AND d.rule_code=p_rule_code AND d.decisor=p_decisor
        AND d.decision_record_sha256=p_decision_record_sha256
        AND d.verdict='APROBAR'
    ) THEN RAISE EXCEPTION 'B07_LF_OWNER_DECISION_RECEIPT_MISSING'; END IF;
    SELECT h.snapshot_sha256,h.version_no INTO prev_sha,n
      FROM lf_ops.reglas_versiones_b07 h WHERE h.rule_id=rid
      ORDER BY h.version_no DESC LIMIT 1 FOR UPDATE;
  ELSE
    SELECT r.id,to_jsonb(r),r.estado INTO rid,s,v_state
      FROM saly.reglas r WHERE r.codigo=p_rule_code FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'B07_SALY_PARENT_NOT_FOUND'; END IF;
    IF v_state<>'VALIDADO' THEN RAISE EXCEPTION 'B07_SALY_NOT_VALIDADO'; END IF;
    -- SALY decision_id existente, sin acreditar humano físico.
    IF NOT EXISTS (
      SELECT 1 FROM saly.decisiones d JOIN saly.reglas r ON r.decision_id=d.id
      WHERE r.id=rid AND d.id::text=p_decision_ref AND d.estado='VALIDADO'
    ) THEN RAISE EXCEPTION 'B07_SALY_DECISION_RECEIPT_MISSING'; END IF;
    SELECT h.snapshot_sha256,h.version_no INTO prev_sha,n
      FROM saly.reglas_versiones_b07 h WHERE h.rule_id=rid
      ORDER BY h.version_no DESC LIMIT 1 FOR UPDATE;
  END IF;
  IF prev_sha IS DISTINCT FROM p_expected_sha256
     THEN RAISE EXCEPTION 'B07_STALE_PARENT_HASH'; END IF;
  new_sha:=encode(extensions.digest(convert_to(s::text,'UTF8'),'sha256'),'hex');
  IF new_sha=prev_sha THEN RAISE EXCEPTION 'B07_SNAPSHOT_UNCHANGED'; END IF;
  IF p_project='LF' THEN
    INSERT INTO lf_ops.reglas_versiones_b07(
      rule_id,version_no,snapshot,snapshot_sha256,previous_sha256,
      origin,decision_ref,decisor,decision_record_sha256,decided_at,writer_execution_id)
    VALUES(rid,n+1,s,new_sha,prev_sha,'GOVERNED_APPEND',
      p_decision_ref,p_decisor,p_decision_record_sha256,p_decided_at,p_writer_execution_id);
  ELSE
    INSERT INTO saly.reglas_versiones_b07(
      rule_id,version_no,snapshot,snapshot_sha256,previous_sha256,
      origin,decision_ref,decisor,decision_record_sha256,decided_at,writer_execution_id)
    VALUES(rid,n+1,s,new_sha,prev_sha,'GOVERNED_APPEND',
      p_decision_ref,p_decisor,p_decision_record_sha256,p_decided_at,p_writer_execution_id);
  END IF;
  RETURN jsonb_build_object('status','CANDIDATE_VERSION_APPENDED',
      'project',p_project,'rule_code',p_rule_code,'version',n+1,
      'previous_sha256',prev_sha,'snapshot_sha256',new_sha,
      'identity_verified',false,'production_authorized',false);
END $fn$;
REVOKE ALL ON FUNCTION public.lf_b07_append_version_candidate_v1(
  text,text,text,text,text,text,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_b07_append_version_candidate_v1(
  text,text,text,text,text,text,timestamptz,text) TO service_role;

CREATE TRIGGER lf_b07_history_immutable BEFORE UPDATE OR DELETE
 ON lf_ops.reglas_versiones_b07 FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_block_history_mutation_v1();
CREATE TRIGGER saly_b07_history_immutable BEFORE UPDATE OR DELETE
 ON saly.reglas_versiones_b07 FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_block_history_mutation_v1();
CREATE TRIGGER lf_b07_history_no_truncate BEFORE TRUNCATE
 ON lf_ops.reglas_versiones_b07 FOR EACH STATEMENT
 EXECUTE FUNCTION public.lf_b07_block_history_truncate_v1();
CREATE TRIGGER saly_b07_history_no_truncate BEFORE TRUNCATE
 ON saly.reglas_versiones_b07 FOR EACH STATEMENT
 EXECUTE FUNCTION public.lf_b07_block_history_truncate_v1();

CREATE CONSTRAINT TRIGGER lf_b07_parent_match AFTER INSERT OR UPDATE OR DELETE
 ON lf_ops.reglas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_assert_parent_latest_v1();
CREATE CONSTRAINT TRIGGER lf_b07_child_match AFTER INSERT OR UPDATE OR DELETE
 ON lf_ops.reglas_versiones_b07 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_assert_parent_latest_v1();
CREATE CONSTRAINT TRIGGER saly_b07_parent_match AFTER INSERT OR UPDATE OR DELETE
 ON saly.reglas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_assert_parent_latest_v1();
CREATE CONSTRAINT TRIGGER saly_b07_child_match AFTER INSERT OR UPDATE OR DELETE
 ON saly.reglas_versiones_b07 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_assert_parent_latest_v1();

DO $check$
BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas_versiones_b07) <>
    (SELECT count(*) FROM lf_ops.reglas)
 OR (SELECT count(*) FROM saly.reglas_versiones_b07) <>
    (SELECT count(*) FROM saly.reglas)
 OR EXISTS (SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_versiones_b07 h
    ON h.rule_id=r.id WHERE to_jsonb(r) IS DISTINCT FROM h.snapshot)
 OR EXISTS (SELECT 1 FROM saly.reglas r JOIN saly.reglas_versiones_b07 h
    ON h.rule_id=r.id WHERE to_jsonb(r) IS DISTINCT FROM h.snapshot)
 THEN RAISE EXCEPTION 'B07_BACKFILL_READBACK_MISMATCH'; END IF;
END $check$;


-- === COMPONENT 2: sandbox/lf_contract_gate_test/input_governance_lifecycle/b07_parent_child_v2_finalizer_integration_candidate.sql (single Train transaction) ===
-- B07 PADRE/HIJA — INTEGRACION CANDIDATA DEL FINALIZADOR OFICIAL V2 LF.
-- EJECUTAR SOLO EN POSTGRES AISLADO. No modifica la migración V2 desplegada.
-- Requiere primero b07_parent_child_candidate_up.sql.
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


-- === COMPONENT 3: sandbox/lf_contract_gate_test/input_governance_lifecycle/b07_saly_official_writer_candidate_v1.sql (single Train transaction) ===
-- B07 SALY: escritor candidato integrado a ejecución gobernada del mismo motor LF.
-- NO REGISTRA operaciones ni owners; fail-closed hasta que ambos existan por ruta oficial.
-- NO EJECUTAR EN SUPABASE. Se ejecuta exclusivamente en PostgreSQL CI aislado.
-- Requiere B07 UP y bridge V2 LF en la MISMA ventana de despliegue futura.
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
