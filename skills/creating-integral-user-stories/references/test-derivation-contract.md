# Contrato de derivacion de pruebas

Juez asociado: `J10_TEST_COVERAGE`.

## Origen

Cada prueba nace de un criterio de aceptacion, una regla critica, un permiso,
una transicion de estado o un error critico. Ninguna prueba se escribe sin
`criterion_ref` o `rule_ref`.

## Estructura

```text
test_code, family, criterion_ref, rule_ref, preconditions, steps,
expected_result, negative, tenant_scope, actor_profile, evidence_path
```

## Familias

```text
FUNCTIONAL VALIDATION OBSERVATION ERROR PERMISSION TENANT SECURITY STATE
IDEMPOTENCY CONCURRENCY AUDIT ANALYTICS OBSERVABILITY RESPONSIVE
ACCESSIBILITY PERFORMANCE
```

## Cobertura minima

```text
acceptance_criteria_without_test = 0
critical_rule_without_test = 0
permission_without_negative_test = 0
tenant_rule_without_cross_tenant_test = 0
state_transition_without_state_test = 0
idempotent_action_without_duplicate_test = 0
critical_error_without_test = 0
```

## Prohibicion

Esta prohibido modificar la historia o el resultado esperado para que una
prueba pase. La reparacion corrige la implementacion del artefacto, nunca el
criterio.
