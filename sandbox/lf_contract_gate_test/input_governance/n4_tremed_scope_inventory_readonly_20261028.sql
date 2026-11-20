-- IG LF — read-only candidate inventory of CURRENT DERIVED_GLOBAL pairs.
-- No promotion, approval, policy activation, or changes to DB.
-- This is a decision-support dataset; even high usage never determines rule scope.

WITH inherited AS (
  SELECT e.regla_id,
         count(*)::integer AS inherited_screens,
         count(*) FILTER (WHERE p.activa)::integer AS inherited_active_screens,
         count(*) FILTER (WHERE NOT p.activa)::integer AS inherited_inactive_screens,
         array_agg(p.codigo ORDER BY p.codigo) AS inherited_screen_codes
  FROM lf_ops.pantallas p
  CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
  WHERE e.binding_source='DERIVED_GLOBAL'
  GROUP BY e.regla_id
),
own AS (
  SELECT rp.regla_id,
         count(DISTINCT rp.pantalla_id)::integer AS explicit_screens,
         array_agg(DISTINCT m.app_shell_code ORDER BY m.app_shell_code)
           FILTER (WHERE m.app_shell_code IS NOT NULL) AS explicit_shell_codes,
         array_agg(DISTINCT p.module_code ORDER BY p.module_code)
           FILTER (WHERE p.module_code IS NOT NULL) AS explicit_module_codes
  FROM lf_ops.reglas_pantallas rp
  JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
  LEFT JOIN lf_ops.modulos m ON m.module_id=p.module_id
  GROUP BY rp.regla_id
)
SELECT r.id AS rule_id,r.codigo AS rule_code,r.titulo AS rule_title,
       r.categoria AS rule_category,r.estado AS rule_status,
       r.es_transversal AS declaratively_marked_transversal,
       r.pendiente_decision AS existing_pending_decision,
       coalesce(r.valor_config->'applicability_v1'->>'status','ABSENT') AS selector_status,
       coalesce(o.explicit_screens,0) AS explicitly_bound_screens,
       i.inherited_screens,i.inherited_active_screens,i.inherited_inactive_screens,
       o.explicit_shell_codes,o.explicit_module_codes,i.inherited_screen_codes,
       'NEEDS_GOVERNED_SCOPE_EVIDENCE'::text AS review_status
FROM inherited i
JOIN lf_ops.reglas r ON r.id=i.regla_id
LEFT JOIN own o ON o.regla_id=r.id
ORDER BY i.inherited_active_screens DESC,r.codigo;

-- Cohort checks: count distinct rule codes. Do not add totals from overlapping
-- populations (95 unscoped transversal, 18 UNRESOLVED, 241 inherited).
WITH inherited AS (
  SELECT DISTINCT e.regla_id
  FROM lf_ops.pantallas p CROSS JOIN LATERAL
       programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
  WHERE e.binding_source='DERIVED_GLOBAL'
)
SELECT count(*) AS inherited_rules,
       count(*) FILTER (WHERE r.es_transversal) AS inherited_marked_transversal,
       count(*) FILTER (WHERE NOT r.es_transversal) AS inherited_not_marked_transversal,
       count(*) FILTER (WHERE jsonb_typeof(r.valor_config->'applicability_v1')='object')
         AS inherited_with_selector
FROM inherited i JOIN lf_ops.reglas r ON r.id=i.regla_id;
