-- LF Input Governance / P10 — PROCESS CHANGE, not historical reclassification.
-- ISOLATED PostgreSQL 17.6 EXECUTION ONLY. This source is deliberately ROLLBACK.
-- Source-first production release requires a separately approved, exact migration.
-- EKB: IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001;
--      INPUT-GOV-CONSUMER-BINDING-001; IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001.
-- No business rule code, category/shell scope enum, or rule/screen ID in this source.
-- Snapshot records *existing effective links*, not certified scope authority.
-- Future scope cannot be created from T-REMED frequency/PASS_GLOBAL.
BEGIN;

-- Serialize snapshot creation against concurrent input changes before
-- inspecting any rows. Fail quickly rather than freezing inconsistent scope.
SET LOCAL lock_timeout = '5s';
LOCK TABLE lf_ops.reglas, lf_ops.reglas_pantallas, lf_ops.pantallas,
  lf_ops.modulos IN SHARE MODE;

DO $preflight$
BEGIN
 IF current_database() IS DISTINCT FROM 'lf_ig_n4_isolated_ci'
   OR current_setting('server_version_num')::integer <> 170006
 THEN RAISE EXCEPTION 'IG_P10_NOT_ISOLATED_PG17'; END IF;
 IF to_regclass('programacion.ig_n4_legacy_scope_frozen_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'IG_P10_BASELINE_ALREADY_EXISTS'; END IF;
 IF md5(pg_get_functiondef('programacion.fn_input_effective_rule_links_v1(integer,text)'::regprocedure))
   IS DISTINCT FROM '156247a925d74c6f4accd7a6d2508489'
 OR md5(pg_get_functiondef('programacion.fn_t_remed_effective_rules_v1(integer,numeric)'::regprocedure))
   IS DISTINCT FROM 'ad5aecf15e12be5b55fdd1e8dac00295'
 OR md5(pg_get_functiondef('programacion.fn_t_remed_global_rules_v1(numeric)'::regprocedure))
   IS DISTINCT FROM '7d8b7a58f16bc5b53867c3322fd1befb'
 OR md5(pg_get_functiondef('programacion.fn_t_remed_scope_judge_v1(numeric)'::regprocedure))
   IS DISTINCT FROM '433445c108c36b25cf26f5a1bddb7a99'
 THEN RAISE EXCEPTION 'IG_P10_SOURCE_DRIFT_BEFORE_FREEZE'; END IF;
END
$preflight$;

-- Fail before freeze if raw physical bindings are ambiguous. A frozen
-- historical pair is NOT authority; duplication also breaks exact parity.
DO $physical_uniqueness$
DECLARE duplicate_pairs bigint;
BEGIN
 SELECT count(*) INTO duplicate_pairs FROM (
  SELECT rp.regla_id,rp.pantalla_id
  FROM lf_ops.reglas_pantallas rp
  GROUP BY rp.regla_id,rp.pantalla_id
  HAVING count(*)>1
 ) d;
 IF duplicate_pairs<>0 THEN
   RAISE EXCEPTION 'IG_P10_PHYSICAL_BINDING_DUPLICATES:%',duplicate_pairs;
 END IF;
END
$physical_uniqueness$;

-- Capture original output with labels. No update to historical source rows.
CREATE TEMP TABLE ig_p10_before ON COMMIT DROP AS
 SELECT 'IG'::text resolver,p.id::integer pantalla_id,
        x.regla_id::integer regla_id,x.binding_source::text origin
 FROM lf_ops.pantallas p
 CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(
   p.id,'INPUT_GOVERNANCE') x
 UNION ALL
 SELECT 'TREMED'::text,p.id::integer,
        x.regla_id::integer,x.origin::text
 FROM lf_ops.pantallas p
 CROSS JOIN LATERAL programacion.fn_t_remed_effective_rules_v1(p.id,0.25) x;

CREATE TABLE programacion.ig_n4_legacy_scope_frozen_v1 (
 source_code text NOT NULL CHECK (source_code IN ('IG_LEGACY','IG_DERIVED','TREMED_OWN','TREMED_GLOBAL')),
 pantalla_id integer NOT NULL,
 regla_id integer NOT NULL,
 frozen_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY (source_code,pantalla_id,regla_id)
);
REVOKE ALL ON TABLE programacion.ig_n4_legacy_scope_frozen_v1 FROM PUBLIC;

INSERT INTO programacion.ig_n4_legacy_scope_frozen_v1
 (source_code,pantalla_id,regla_id)
SELECT CASE
 WHEN resolver='IG' AND origin='LEGACY_EXPLICIT' THEN 'IG_LEGACY'
 WHEN resolver='IG' AND origin='DERIVED_GLOBAL' THEN 'IG_DERIVED'
 WHEN resolver='TREMED' AND origin='OWN' THEN 'TREMED_OWN'
 WHEN resolver='TREMED' AND origin='GLOBAL' THEN 'TREMED_GLOBAL'
 END AS source_code,pantalla_id,regla_id
FROM ig_p10_before
WHERE (resolver='IG' AND origin IN ('LEGACY_EXPLICIT','DERIVED_GLOBAL'))
   OR (resolver='TREMED' AND origin IN ('OWN','GLOBAL'))
GROUP BY resolver,origin,pantalla_id,regla_id;

-- The existing implicit AND explicit binding pairs are frozen as a boundary,
-- not as approval. Newly inserted candidate physical links remain in the
-- raw authoring table but not the effective reader until governed publication.
-- A newly promoted rule, newly added screen, changed category, or changed
-- PASS_GLOBAL recommendation CANNOT add an implicit effective pair.
-- Existing historical explicit/declared paths retain original status semantics.
CREATE OR REPLACE FUNCTION programacion.fn_input_effective_rule_links_v1(
 p_pantalla_id integer,p_consumer text DEFAULT 'INPUT_GOVERNANCE')
RETURNS TABLE(pantalla_id integer,regla_id integer,binding_source text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $function$
 WITH legacy AS (
  SELECT rp.pantalla_id,rp.regla_id,'LEGACY_EXPLICIT'::text binding_source
  FROM programacion.ig_n4_legacy_scope_frozen_v1 f
  JOIN lf_ops.reglas_pantallas rp
    ON rp.pantalla_id=f.pantalla_id AND rp.regla_id=f.regla_id
  JOIN lf_ops.reglas r ON r.id=rp.regla_id
  WHERE f.source_code='IG_LEGACY'
    AND f.pantalla_id=p_pantalla_id
    AND jsonb_typeof(r.valor_config->'applicability_v1') IS DISTINCT FROM 'object'
 ), declared AS (
  SELECT d.pantalla_id,d.regla_id,d.binding_source
  FROM programacion.fn_input_declared_rule_links_v1(p_pantalla_id,p_consumer) d
 ), frozen_inherited AS (
  SELECT p_pantalla_id AS pantalla_id,f.regla_id,'DERIVED_GLOBAL'::text binding_source
  FROM programacion.ig_n4_legacy_scope_frozen_v1 f
  JOIN lf_ops.reglas r ON r.id=f.regla_id
  WHERE f.source_code='IG_DERIVED'
    AND f.pantalla_id=p_pantalla_id
    AND r.estado='VIGENTE'
    AND jsonb_typeof(r.valor_config->'applicability_v1') IS DISTINCT FROM 'object'
    AND EXISTS(SELECT 1 FROM lf_ops.pantallas p WHERE p.id=p_pantalla_id)
    AND NOT EXISTS(
      SELECT 1 FROM lf_ops.reglas_pantallas z
      WHERE z.pantalla_id=p_pantalla_id AND z.regla_id=f.regla_id)
 )
 SELECT * FROM legacy
 UNION ALL SELECT * FROM declared
 UNION ALL SELECT * FROM frozen_inherited
$function$;

-- Legacy T-REMED entrypoint is also bounded by the SAME frozen evidence.
-- Diagnostic fn_t_remed_global_rules_v1 remains unchanged and is NOT
-- an admission authority. Non-default p_min_share may further RESTRICT,
-- never expand, the frozen 0.25 baseline.
CREATE OR REPLACE FUNCTION programacion.fn_t_remed_effective_rules_v1(
 p_pantalla_id integer,p_min_share numeric DEFAULT 0.25)
RETURNS TABLE(regla_id bigint,origin text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $function$
 SELECT z.regla_id::bigint,'OWN'::text
 FROM programacion.ig_n4_legacy_scope_frozen_v1 f
 JOIN lf_ops.reglas_pantallas z
   ON z.pantalla_id=f.pantalla_id AND z.regla_id=f.regla_id
 WHERE f.source_code='TREMED_OWN'
   AND z.pantalla_id=p_pantalla_id
   AND EXISTS(SELECT 1 FROM lf_ops.pantallas WHERE id=p_pantalla_id)
 UNION
 SELECT f.regla_id::bigint,'GLOBAL'::text
 FROM programacion.ig_n4_legacy_scope_frozen_v1 f
 JOIN lf_ops.reglas r ON r.id=f.regla_id
 WHERE f.source_code='TREMED_GLOBAL'
   AND r.estado='VIGENTE'
   AND f.pantalla_id=p_pantalla_id
   AND EXISTS(SELECT 1 FROM lf_ops.pantallas WHERE id=p_pantalla_id)
   AND NOT EXISTS(
      SELECT 1 FROM lf_ops.reglas_pantallas z
      WHERE z.pantalla_id=p_pantalla_id AND z.regla_id=f.regla_id)
   AND (coalesce(p_min_share,0.25) <= 0.25
      OR EXISTS(
        SELECT 1 FROM programacion.fn_t_remed_global_rules_v1(p_min_share) g
        WHERE g.regla_id=f.regla_id))
$function$;

-- FORWARD publication guard. No existing ACTIVE selector is re-reviewed or
-- rewritten. New/changed ACTIVE JSON is held until G4 binds competent real
-- authority to rule/version/consumer/scope; self-declared JSON is NOT a receipt.
CREATE OR REPLACE FUNCTION programacion.fn_ig_p10_forward_selector_admission_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $guard$
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.estado='VIGENTE'
   AND NEW.valor_config->'applicability_v1'->>'status'='ACTIVE'
  THEN RAISE EXCEPTION 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_NEW_ACTIVE_SELECTOR'
    USING ERRCODE='P0001'; END IF;
 ELSIF TG_OP='UPDATE' THEN
  -- A VIGENTE rule changing selector semantics can revoke historical scope
  -- or expand operational scope. Neither is an unreviewed text edit.
  IF OLD.estado='VIGENTE' AND NEW.estado='VIGENTE'
     AND OLD.valor_config->'applicability_v1'
           IS DISTINCT FROM NEW.valor_config->'applicability_v1'
  THEN RAISE EXCEPTION 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_SELECTOR_CHANGE'
    USING ERRCODE='P0001'; END IF;
  IF NEW.estado='VIGENTE' AND OLD.estado IS DISTINCT FROM NEW.estado
     AND EXISTS(SELECT 1 FROM lf_ops.reglas_pantallas z WHERE z.regla_id=NEW.id)
  THEN RAISE EXCEPTION 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_CANDIDATE_PROMOTION'
    USING ERRCODE='P0001'; END IF;
  IF NEW.estado='VIGENTE'
   AND NEW.valor_config->'applicability_v1'->>'status'='ACTIVE'
   AND (
    OLD.valor_config->'applicability_v1'
      IS DISTINCT FROM NEW.valor_config->'applicability_v1'
    OR OLD.estado IS DISTINCT FROM NEW.estado
   )
  THEN RAISE EXCEPTION 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_SELECTOR_PUBLICATION'
    USING ERRCODE='P0001'; END IF;
 END IF;
 RETURN NEW;
END
$guard$;

CREATE TRIGGER trg_ig_p10_future_selector_admission_v1
BEFORE INSERT OR UPDATE OF valor_config,estado ON lf_ops.reglas
FOR EACH ROW EXECUTE FUNCTION programacion.fn_ig_p10_forward_selector_admission_v1();

-- Future physical bindings are a SEPARATE source of effective scope.
-- Keep CANDIDATO links as analysis data, but disallow publishing new
-- links to a VIGENTE rule before the competent G4 publication gate exists.
CREATE OR REPLACE FUNCTION programacion.fn_ig_p10_forward_binding_admission_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $guard$
DECLARE v_state text;
BEGIN
 IF TG_OP='UPDATE'
   AND NEW.regla_id IS NOT DISTINCT FROM OLD.regla_id
   AND NEW.pantalla_id IS NOT DISTINCT FROM OLD.pantalla_id
 THEN RETURN NEW; END IF;
 SELECT r.estado INTO v_state FROM lf_ops.reglas r WHERE r.id=NEW.regla_id;
 IF v_state='VIGENTE' THEN
   RAISE EXCEPTION 'IG_P10_SCOPE_AUTHORITY_REQUIRED_ON_NEW_PHYSICAL_LINK'
      USING ERRCODE='P0001';
 END IF;
 RETURN NEW;
END
$guard$;
CREATE TRIGGER trg_ig_p10_future_binding_admission_v1
BEFORE INSERT OR UPDATE OF regla_id,pantalla_id ON lf_ops.reglas_pantallas
FOR EACH ROW EXECUTE FUNCTION programacion.fn_ig_p10_forward_binding_admission_v1();

-- Candidate rule links may have been recorded for analysis. Promoting such
-- a rule changes those links into potential operational scope. Hold that
-- promotion until G4 verifies competent authority and future publication.
-- No re-review of an unchanged VIGENTE historical rule is attempted.


-- Baseline must be bitwise identical for all PREEXISTING targets under both
-- root consumers. Never accept a sum-only parity assertion.
DO $assert$
DECLARE v_missing bigint;v_extra bigint;v_ig bigint;v_total bigint;
BEGIN
 WITH after_links AS MATERIALIZED (
   SELECT 'IG'::text resolver,p.id::integer pantalla_id,
     x.regla_id::integer regla_id,x.binding_source::text origin
   FROM lf_ops.pantallas p CROSS JOIN LATERAL
       programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') x
   UNION ALL
   SELECT 'TREMED'::text,p.id::integer,x.regla_id::integer,x.origin::text
   FROM lf_ops.pantallas p CROSS JOIN LATERAL
       programacion.fn_t_remed_effective_rules_v1(p.id,0.25) x
 ), missing AS MATERIALIZED (
  SELECT * FROM ig_p10_before EXCEPT ALL SELECT * FROM after_links
 ), extra AS MATERIALIZED (
  SELECT * FROM after_links EXCEPT ALL SELECT * FROM ig_p10_before
 )
 SELECT (SELECT count(*) FROM missing),(SELECT count(*) FROM extra)
 INTO v_missing,v_extra;
 IF v_missing<>0 OR v_extra<>0
 THEN RAISE EXCEPTION 'IG_P10_FROZEN_BASELINE_DRIFT missing=% extra=%',
       v_missing,v_extra; END IF;
 SELECT count(*) INTO v_ig
 FROM programacion.ig_n4_legacy_scope_frozen_v1 WHERE source_code='IG_DERIVED';
 SELECT count(*) INTO v_total FROM ig_p10_before WHERE resolver='IG' AND origin='DERIVED_GLOBAL';
 IF v_ig<>v_total
 THEN RAISE EXCEPTION 'IG_P10_SNAPSHOT_ROW_COUNT_DRIFT expected=% got=%',
 v_total,v_ig; END IF;
 RAISE NOTICE 'IG_P10_FROZEN_BASELINE_PASS|legacy_ig=%|missing=0|extra=0',v_ig;
END
$assert$;

-- This source CANNOT modify production. Isolated standalone execution only;
-- deployment source requires technical, G4 authority, and source-first approval.
ROLLBACK;
