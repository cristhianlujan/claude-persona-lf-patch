-- IG M4.4: readonly canonical source adapter for the dedicated OTP RATE_LIMIT shadow oracle.
-- Supply selected_run_id from the existing random-screen selector. DO NOT use a
-- hardcoded screen, Curator source_refs, or Curator semantic classifications.
-- The resulting JSON is an observation, not a certificate of independent
-- evidence provenance. Resolve T-SOURCE currentness/receipt separately.
SELECT jsonb_build_object(
  'run_id',run.id,
  'pantalla_id',run.pantalla_id,
  'screen_code',pantalla.codigo,
  'version_id',run.version_id,
  'family_code','RATE_LIMIT',
  'rule_bindings',(
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'rule_code',rule.codigo,
      'status',rule.estado,
      'category',rule.categoria,
      'rule_config',rule.valor_config,
      'policy',(
         SELECT jsonb_build_object(
           'policy_code',policy.policy_code,
           'status',policy.status,
           'resource_code',policy.resource_code,
           'window_seconds',policy.window_seconds,
           'max_requests',policy.max_requests,
           'burst_limit',policy.burst_limit,
           'scope_key',policy.scope_key,
           'error_code',policy.error_code
         )
         FROM lf_ops.politicas_rate_limit policy
         WHERE policy.policy_code=rule.valor_config->>'canonical_rate_policy_code'
      )
    ) ORDER BY rule.codigo),'[]'::jsonb)
    FROM lf_ops.reglas_pantallas binding
    JOIN lf_ops.reglas rule ON rule.id=binding.regla_id
    WHERE binding.pantalla_id=run.pantalla_id
      AND rule.categoria='rate_limiting'
  )
) AS oracle_input
FROM programacion.input_readiness_runs run
JOIN lf_ops.pantallas pantalla ON pantalla.id=run.pantalla_id
WHERE run.id=:selected_run_id
  AND EXISTS (
    SELECT 1 FROM programacion.input_family_assessments a
    WHERE a.run_id=run.id AND a.family_code='RATE_LIMIT'
  );
