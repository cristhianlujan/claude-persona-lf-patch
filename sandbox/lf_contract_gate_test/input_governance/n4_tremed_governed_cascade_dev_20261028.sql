-- LF / IG / N-4 + T-REMED — DEVELOPMENT CANDIDATE, 2026-10-28.
-- DO NOT DEPLOY. Stored outside supabase/migrations. NO Router and NO DB changes in this dev stage.
-- This script deliberately ends in ROLLBACK; it is an isolated transaction-shaped proposal.
-- EKB: IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001; CI-MIGRATION-SOURCE-PARITY-001.
--
-- Intent: preserve contextual inheritance via N-4's authoritative selector; do not
-- import T-REMED's frequency-derived "global" recommendations into executable scope.
-- Candidate explicit bindings remain visible to IG discovery and the contracts, but
-- candidate policy references are not executable authorities.
-- No rule IDs, screen IDs, fixed scope enum or 25%-usage threshold in runtime logic.
-- Contract versioning, owner approval, canaries, and migration-source parity are
-- REQUIRED BEFORE any future production migration; this is not that migration.

BEGIN;

DO $preflight$
DECLARE
  v_id regprocedure;
  v_seen text;
  v_expected text;
  v_ekb integer;
BEGIN
  SELECT count(*) INTO v_ekb FROM transversal.error_knowledge
  WHERE codigo='IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001'
    AND lower(estado)='activo';
  IF v_ekb<>1 THEN RAISE EXCEPTION 'N4_TREMED_EKB_NOT_CURRENT'; END IF;

  FOR v_id,v_expected IN
    SELECT x.id,x.expected FROM (VALUES
      ('programacion.fn_input_effective_rule_links_v1(integer,text)'::regprocedure,'156247a925d74c6f4accd7a6d2508489'),
      ('lf_ops.fn_screen_contract_v1(text,text,text)'::regprocedure,'7817a728991b66865b9f144c658512be'),
      ('lf_ops.fn_b2b_backoffice_login_contract(text,text,text)'::regprocedure,'6fceb03a6fbb79f98f612d51cae3facf')
    ) AS x(id,expected)
  LOOP
    SELECT md5(pg_get_functiondef(v_id)) INTO v_seen;
    IF v_seen IS DISTINCT FROM v_expected THEN
      RAISE EXCEPTION 'N4_TREMED_SOURCE_DRIFT proc=% expected=% observed=%',v_id,v_expected,v_seen;
    END IF;
  END LOOP;
END;
$preflight$;

-- The existing function's 3-column signature, SECURITY DEFINER, volatility, and
-- search_path remain unchanged. Only authority for one union branch changes.
CREATE OR REPLACE FUNCTION programacion.fn_input_effective_rule_links_v1(
    p_pantalla_id integer,
    p_consumer text DEFAULT 'INPUT_GOVERNANCE'
)
RETURNS TABLE(pantalla_id integer,regla_id integer,binding_source text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $function$
  WITH legacy AS (
    SELECT rp.pantalla_id,rp.regla_id,'LEGACY_EXPLICIT'::text AS binding_source
    FROM lf_ops.reglas_pantallas rp
    JOIN lf_ops.reglas r ON r.id=rp.regla_id
    WHERE rp.pantalla_id=p_pantalla_id
      AND jsonb_typeof(r.valor_config->'applicability_v1') IS DISTINCT FROM 'object'
  ), declared AS (
    SELECT d.pantalla_id,d.regla_id,d.binding_source
    FROM programacion.fn_input_declared_rule_links_v1(p_pantalla_id,p_consumer) d
  )
  SELECT * FROM legacy
  UNION ALL
  SELECT * FROM declared
$function$;

-- Keep candidates visible in attached_rules for IG analysis and contracts.
-- Policy references in contract JSON, however, MUST come only from VIGENTE rules.
-- Both consumers use the same canonical N-4 resolver rather than mixing physical
-- links with a standalone DERIVED_GLOBAL branch.
DO $contract_alignment$
DECLARE
  v_proc regprocedure;
  v_source text;
  v_before text := E'attached_rules as (\n  select rp.pantalla_id, r.*\n  from lf_ops.reglas_pantallas rp\n  join lf_ops.reglas r on r.id = rp.regla_id\n  join ctx c on c.pantalla_id = rp.pantalla_id\n  union all\n  select l.pantalla_id, r.*\n  from ctx c\n  cross join lateral programacion.fn_input_effective_rule_links_v1(c.pantalla_id, ''INPUT_GOVERNANCE'') l\n  join lf_ops.reglas r on r.id = l.regla_id\n  where l.binding_source = ''DERIVED_GLOBAL''\n)';
  v_after text := E'attached_rules as (\n  select l.pantalla_id, r.*\n  from ctx c\n  cross join lateral programacion.fn_input_effective_rule_links_v1(c.pantalla_id, ''INPUT_GOVERNANCE'') l\n  join lf_ops.reglas r on r.id = l.regla_id\n)';
  v_numeric text := 'and e.value ~ ''^[0-9]+$''';
  v_occurrences int;
BEGIN
  FOR v_proc IN SELECT unnest(ARRAY[
    'lf_ops.fn_screen_contract_v1(text,text,text)'::regprocedure,
    'lf_ops.fn_b2b_backoffice_login_contract(text,text,text)'::regprocedure
  ]) LOOP
    SELECT pg_get_functiondef(v_proc) INTO v_source;
    IF strpos(v_source,v_before)=0 THEN
      RAISE EXCEPTION 'N4_TREMED_CONTRACT_SHAPE_DRIFT:%',v_proc;
    END IF;
    v_occurrences := (length(v_source)-length(replace(v_source,v_numeric,''))) / length(v_numeric);
    IF v_occurrences<>4 THEN
      RAISE EXCEPTION 'N4_TREMED_CONTRACT_POLICY_GUARD_COUNT:% count=%',v_proc,v_occurrences;
    END IF;
    v_source := replace(v_source,v_before,v_after);
    v_source := replace(v_source,v_numeric,
      v_numeric || E'\n    and r.estado = ''VIGENTE''\n    and not coalesce(r.pendiente_decision,false)'
    );
    -- pg_get_functiondef yields the exact original function signature and body.
    EXECUTE v_source;
  END LOOP;
END;
$contract_alignment$;

-- Transaction-local assertions only: no special business rule codes in runtime.
DO $assert$
DECLARE
  v_count integer;
  v_missing integer;
  v_extra integer;
  v_pantalla integer;
  v_contract record;
  v_rules integer;
BEGIN
  SELECT count(*) INTO v_count FROM lf_ops.pantallas p
  CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
  WHERE e.binding_source='DERIVED_GLOBAL';
  IF v_count<>0 THEN RAISE EXCEPTION 'N4_TREMED_INFERRED_GLOBAL_EXECUTABLE:%',v_count; END IF;

  -- Current initial positive binding set must be preserved, INCLUDING candidates
  -- as data for IG discovery. New authorised selectors may create NEW matches later,
  -- so do not reuse this check as an invariant for future new screens.
  WITH expected AS (
    SELECT rp.pantalla_id,rp.regla_id FROM lf_ops.reglas_pantallas rp
  ), actual AS (
    SELECT p.id AS pantalla_id,e.regla_id FROM lf_ops.pantallas p
    CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
  )
  SELECT
    (SELECT count(*) FROM (SELECT * FROM expected EXCEPT SELECT * FROM actual) z),
    (SELECT count(*) FROM (SELECT * FROM actual EXCEPT SELECT * FROM expected) z)
  INTO v_missing,v_extra;
  IF v_missing<>0 OR v_extra<>0 THEN
    RAISE EXCEPTION 'N4_TREMED_BASELINE_BINDING_DRIFT missing=% extra=%',v_missing,v_extra;
  END IF;

  -- A contract only has the entries returned by the selector; candidates still
  -- exist as review data and are filtered from operational policy ID sources.
  FOR v_contract IN
    SELECT x.* FROM lf_ops.fn_b2b_backoffice_login_contract() x
  LOOP
    v_pantalla := v_contract.pantalla_id;
    SELECT count(*) INTO v_rules
    FROM programacion.fn_input_effective_rule_links_v1(v_pantalla,'INPUT_GOVERNANCE');
    IF jsonb_array_length(v_contract.contract->'rules')<>v_rules THEN
      RAISE EXCEPTION 'N4_TREMED_LOGIN_CONTRACT_SCOPE_MISMATCH';
    END IF;
  END LOOP;

  SELECT count(*) INTO v_count FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname='lf_ops' AND p.proname IN ('fn_screen_contract_v1','fn_b2b_backoffice_login_contract') AND p.prosrc LIKE '%DERIVED_GLOBAL%')
     OR (n.nspname='programacion' AND p.proname='fn_input_effective_rule_links_v1' AND p.prosrc LIKE '%DERIVED_GLOBAL%');
  IF v_count>0 THEN
    RAISE EXCEPTION 'N4_TREMED_LEGACY_DERIVED_BRANCH_LEFT_IN_CONSUMER:%',v_count;
  END IF;
END;
$assert$;

-- Fails safely if run accidentally. A governed migration needs a SEPARATE,
-- newly versioned source, approvals and the full 58-screen / 13x47 regression suite.
ROLLBACK;
