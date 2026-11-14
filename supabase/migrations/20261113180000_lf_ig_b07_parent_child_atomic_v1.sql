-- B07 LF-only DDL candidate. HOLD: explicit owner DDL authorization required.
-- No SALY objects, writes, caller, history or Train. One transaction; no existing RUN updates.
BEGIN;
DO $guard$ BEGIN
  IF to_regclass('public.lf_operation_registry') IS NULL OR
     to_regclass('public.lf_ig_project_owner_v2') IS NULL OR
     to_regclass('public.lf_activos') IS NULL OR
     to_regclass('lf_ops.reglas') IS NULL
  THEN RAISE EXCEPTION 'B07_LF_GOVERNANCE_CATALOG_MISSING'; END IF;
  IF to_regclass('lf_ops.reglas_versiones_b07') IS NOT NULL OR
     to_regclass('public.lf_b07_project_gate_v1') IS NOT NULL
  THEN RAISE EXCEPTION 'B07_LF_HISTORY_OR_GATE_ALREADY_EXISTS'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')
  THEN RAISE EXCEPTION 'B07_LF_WRITER_ROLE_MISSING'; END IF;
END $guard$;

-- Data-driven project admission. The ONLY enabled row is LF.
-- Future projects require their own governed registration, writer and migration.
CREATE TABLE public.lf_b07_project_gate_v1 (
 project_code text PRIMARY KEY,
 required_operation_codes text[] NOT NULL CHECK (array_length(required_operation_codes,1)>0),
 owner_status text NOT NULL,
 identity_mode text NOT NULL,
 parent_relation text NOT NULL,
 enabled boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.lf_b07_project_gate_v1
 (project_code,required_operation_codes,owner_status,identity_mode,parent_relation,enabled)
VALUES ('LF',ARRAY['CREACION_REGLA_LF','ACTUALIZACION_REGLA_LF'],
 'TEMP_DOCUMENTARY_ACTIVE','UNVERIFIED_CHAT_DECLARATION','lf_ops.reglas',true);
ALTER TABLE public.lf_b07_project_gate_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_b07_project_gate_v1 FROM PUBLIC,anon,authenticated,service_role;
CREATE POLICY lf_b07_gate_service_select ON public.lf_b07_project_gate_v1
 FOR SELECT TO service_role USING (true);
GRANT SELECT ON public.lf_b07_project_gate_v1 TO service_role;

CREATE FUNCTION public.lf_b07_project_preflight_v1(p_project_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','extensions'
AS $preflight$
DECLARE cfg public.lf_b07_project_gate_v1%ROWTYPE; operation_name text;
BEGIN
  SELECT * INTO cfg FROM public.lf_b07_project_gate_v1
  WHERE project_code=p_project_code AND enabled=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'B07_PROJECT_NOT_ENABLED'; END IF;
  IF to_regclass(cfg.parent_relation) IS NULL
  THEN RAISE EXCEPTION 'B07_PROJECT_PARENT_MISSING'; END IF;
  FOREACH operation_name IN ARRAY cfg.required_operation_codes LOOP
    IF NOT EXISTS(SELECT 1 FROM public.lf_operation_registry r
      WHERE r.operation_code=operation_name
      AND r.status='SANDBOX_ACTIVE'
      AND r.lifecycle_state_code='OP_CANDIDATE'
      AND r.created_by_execution_id IS NOT NULL)
    THEN RAISE EXCEPTION 'B07_PROJECT_OPERATION_NOT_REGISTERED:%',operation_name; END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM public.lf_ig_project_owner_v2 o
     JOIN public.lf_activos a ON a.codigo_activo=o.owner_profile_code
     WHERE o.project_code=cfg.project_code AND o.status=cfg.owner_status
       AND o.identity_mode=cfg.identity_mode
       AND o.authority_receipt_sha256 ~ '^[0-9a-f]{64}$'
       AND a.tipo_activo='PERFIL' AND a.archived_at IS NULL)
  THEN RAISE EXCEPTION 'B07_PROJECT_OWNER_AND_PROFILE_REQUIRED'; END IF;
  RETURN jsonb_build_object('status','PREFLIGHT_PASS','project_code',cfg.project_code,
    'identity_verified',false,'ddl_authorized',false);
END $preflight$;
REVOKE ALL ON FUNCTION public.lf_b07_project_preflight_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_b07_project_preflight_v1(text) TO service_role;
DO $admission$ BEGIN
  PERFORM public.lf_b07_project_preflight_v1('LF');
END $admission$;

-- LF history; baseline is CURRENT snapshot only, never fabricated past history.
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

CREATE INDEX lf_b07_versions_latest ON lf_ops.reglas_versiones_b07(rule_id,version_no DESC);
ALTER TABLE lf_ops.reglas_versiones_b07 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON lf_ops.reglas_versiones_b07 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO lf_ops.reglas_versiones_b07(rule_id,version_no,snapshot,snapshot_sha256,origin)
SELECT r.id,1,to_jsonb(r),
 encode(extensions.digest(convert_to(to_jsonb(r)::text,'UTF8'),'sha256'),'hex'),
 'BASELINE_CURRENT_ONLY' FROM lf_ops.reglas r;

-- Deferred invariant at COMMIT; no direct parent mutation may bypass history.
CREATE FUNCTION public.lf_b07_assert_parent_latest_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public','lf_ops','extensions'
AS $inv$
DECLARE rid integer; got jsonb; latest jsonb;
BEGIN
 IF TG_TABLE_SCHEMA<>'lf_ops' THEN RAISE EXCEPTION 'B07_PROJECT_SCOPE_DENIED'; END IF;
 IF TG_TABLE_NAME='reglas' THEN rid:=COALESCE(NEW.id,OLD.id);
 ELSE rid:=COALESCE(NEW.rule_id,OLD.rule_id); END IF;
 SELECT to_jsonb(r) INTO got FROM lf_ops.reglas r WHERE r.id=rid;
 SELECT h.snapshot INTO latest FROM lf_ops.reglas_versiones_b07 h
 WHERE h.rule_id=rid ORDER BY h.version_no DESC LIMIT 1;
 IF got IS NULL OR latest IS NULL OR got IS DISTINCT FROM latest
 THEN RAISE EXCEPTION 'B07_PARENT_LATEST_MISMATCH:LF:%',rid; END IF;
 RETURN NULL;
END $inv$;
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

CREATE TRIGGER lf_b07_history_immutable BEFORE UPDATE OR DELETE
 ON lf_ops.reglas_versiones_b07 FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_block_history_mutation_v1();

CREATE TRIGGER lf_b07_history_no_truncate BEFORE TRUNCATE
 ON lf_ops.reglas_versiones_b07 FOR EACH STATEMENT
 EXECUTE FUNCTION public.lf_b07_block_history_truncate_v1();

CREATE CONSTRAINT TRIGGER lf_b07_parent_match AFTER INSERT OR UPDATE OR DELETE
 ON lf_ops.reglas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_assert_parent_latest_v1();
CREATE CONSTRAINT TRIGGER lf_b07_child_match AFTER INSERT OR UPDATE OR DELETE
 ON lf_ops.reglas_versiones_b07 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
 EXECUTE FUNCTION public.lf_b07_assert_parent_latest_v1();


DO $readback$ BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas_versiones_b07)<>(SELECT count(*) FROM lf_ops.reglas)
 OR EXISTS(SELECT 1 FROM lf_ops.reglas p
   LEFT JOIN lf_ops.reglas_versiones_b07 h ON h.rule_id=p.id
   WHERE h.rule_id IS NULL OR h.version_no<>1 OR h.origin<>'BASELINE_CURRENT_ONLY'
   OR to_jsonb(p) IS DISTINCT FROM h.snapshot)
 THEN RAISE EXCEPTION 'B07_LF_BACKFILL_READBACK_MISMATCH'; END IF;
END $readback$;
DO $v2check$ BEGIN
 IF to_regprocedure('public.lf_ig_rule_finalize_v2(text)') IS NULL
 THEN RAISE EXCEPTION 'B07_LF_FINALIZER_V2_MISSING'; END IF;
END $v2check$;

-- Only V2 official finalizer appends LF history in the same transaction.
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

CREATE POLICY lf_b07_history_service_read ON lf_ops.reglas_versiones_b07
 FOR SELECT TO service_role USING (true);
GRANT SELECT ON lf_ops.reglas_versiones_b07 TO service_role;
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON lf_ops.reglas_versiones_b07
 FROM PUBLIC,anon,authenticated,service_role;
CREATE VIEW public.lf_b07_rules_current_v1 WITH (security_barrier=true)
 AS SELECT r.* FROM lf_ops.reglas r
 WHERE r.estado='VIGENTE' AND NOT r.pendiente_decision;
REVOKE ALL ON public.lf_b07_rules_current_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.lf_b07_rules_current_v1 TO service_role;
COMMIT;
