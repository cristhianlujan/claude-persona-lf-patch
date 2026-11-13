-- B07 PADRE/HIJA CANDIDATO V1, no firmado. NO INSTALAR EN SUPABASE.
-- Sin ALTER TABLE lf_ops.reglas ni saly.reglas. SOLO datos sintéticos en CI.
-- IMPORTANTE: V2 oficial actualiza el padre in situ. Requiere integración
-- transaccional al escritor antes de cualquier despliegue real (NO-GO).
BEGIN;
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
COMMIT;
