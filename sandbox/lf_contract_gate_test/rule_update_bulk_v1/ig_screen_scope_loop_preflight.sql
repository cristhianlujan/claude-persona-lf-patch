-- LF Issue #3779 | Deterministic screen-loop scope for rule-source IG.
-- READ ONLY: classification of the CURRENT canonical 578-rule catalog.
-- Not an IG runtime, permission, writer, judge, post-cut currentness receipt, or migration.
-- A screen can be linked to many rules and a rule to many screens.
-- Execute IG ONCE per distinct ACTIVE pantalla_id, using the existing
-- programacion.fn_input_governance_execute(pantalla_id,'CONTEXT_PACK') entrypoint.
-- The executor must preserve official CURRENTNESS_AUTHORITY / freshness gates;
-- do not execute stale recurations blindly. Never activate inactive screens.
-- A rule with no ACTIVE screen is not deemed validated by screen IG.
WITH canonical_rules AS (
  SELECT id,codigo,categoria,estado FROM lf_ops.reglas
),
rule_scope AS (
  SELECT r.id,r.codigo,r.categoria,r.estado,
     count(rp.pantalla_id) AS linked_screens,
     count(rp.pantalla_id) FILTER(WHERE p.activa) AS active_screens,
     count(rp.pantalla_id) FILTER(WHERE NOT p.activa) AS inactive_screens
  FROM canonical_rules r
  LEFT JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
  LEFT JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
  GROUP BY r.id,r.codigo,r.categoria,r.estado
),
classified AS (
  SELECT *,CASE
    WHEN active_screens>0 THEN 'SCREEN_IG_ACTIVE'
    WHEN inactive_screens>0 THEN 'INACTIVE_SCREEN_SCOPE_DECISION_REQUIRED'
    ELSE 'CANONICAL_RULE_NO_SCREEN'
  END AS scope_class
  FROM rule_scope
),
screen_work AS (
 SELECT p.id AS pantalla_id,p.codigo AS screen_code,p.activa,
        count(DISTINCT rp.regla_id) AS linked_rule_count
 FROM lf_ops.pantallas p
 JOIN lf_ops.reglas_pantallas rp ON rp.pantalla_id=p.id
 JOIN canonical_rules r ON r.id=rp.regla_id
 GROUP BY p.id,p.codigo,p.activa
)
SELECT
  (SELECT count(*) FROM canonical_rules) AS canonical_rules,
  (SELECT count(*) FROM classified WHERE scope_class='SCREEN_IG_ACTIVE') AS rules_with_active_screen,
  (SELECT count(*) FROM classified WHERE scope_class='CANONICAL_RULE_NO_SCREEN') AS rules_without_screen,
  (SELECT count(*) FROM classified WHERE scope_class='INACTIVE_SCREEN_SCOPE_DECISION_REQUIRED') AS rules_only_inactive,
  (SELECT count(*) FROM screen_work WHERE activa) AS distinct_active_screens_for_ig_loop,
  (SELECT count(*) FROM screen_work WHERE NOT activa) AS distinct_inactive_screens_do_not_execute,
  (SELECT count(*) FROM lf_ops.reglas_pantallas) AS source_relationship_count,
  (SELECT md5(string_agg(r.id::text||':'||r.codigo,E'\n' ORDER BY r.id)) FROM canonical_rules r)
    AS source_catalog_md5,
  (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'pantalla_id',p.pantalla_id,'screen_code',p.screen_code,
      'rule_count',p.linked_rule_count,'ig_currentness','NOT_CHECKED'
     ) ORDER BY p.screen_code),'[]'::jsonb)
   FROM screen_work p WHERE p.activa) AS screen_loop_scope,
  (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rule_code',r.codigo,'state',r.estado,
      'scope_class',r.scope_class,'active_screens',r.active_screens,
      'inactive_screens',r.inactive_screens
     ) ORDER BY r.codigo),'[]'::jsonb)
   FROM classified r
   WHERE r.scope_class<>'SCREEN_IG_ACTIVE') AS unscreened_rule_scope,
  'PREFLIGHT_CLASSIFIED_NOT_AUTHORIZED' AS decision,
  false AS step40_ready_attested,
  false AS promotion_authorized,
  false AS mutation_authorized;
-- VALIDATOR RULES FOR CONSUMER:
-- 1. Verify catalog count/root, selected rule set & scope before each decision.
-- 2. For 53 ACTIVE screens invoke existing IG once per distinct screen, never
--    per rule-to-screen relation; reuse CURRENT according to SOURCE_PACK/delta.
-- 3. For 64 unscreened rules use governed canonical RULE source validation,
--    never claim IG SCREEN=READY or create placeholder pantalla.
-- 4. B2B-RULE-AUTH-035 has only inactive B2B-AUTH-005: BLOCK until a
--    governed scope decision (no automatic screen activation).
-- 5. All paths must preserve the SAME Product Director parent and judge.
-- 6. An aggregate with any non-CURRENT/blocked/unresolved item is not READY.
-- 7. Final after-cut IG currentness is separately required on affected sources.
