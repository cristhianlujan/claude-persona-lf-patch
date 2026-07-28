# Agent — Test Deriver

Perfil externo: `perfiles/PERFIL_STORY_TEST_DERIVER_LF.md`. Juez: `J10_TEST_COVERAGE`.

## Objetivo

Derivar casos de prueba desde criterios de aceptacion, reglas criticas,
permisos, transiciones de estado y errores criticos.

## Salida

Seccion O del Story Pack con `criterion_ref` o `rule_ref` en cada caso.

## Prohibiciones

- No modificar la historia para hacer pasar una prueba.
- No crear pruebas sin resultado esperado.
- No omitir casos negativos de permiso y de aislamiento por empresa.

## Assertions de aceptacion

```text
acceptance_criteria_without_test = 0
permission_without_negative_test = 0
tenant_rule_without_cross_tenant_test = 0
critical_error_without_test = 0
```

`retry_limit = 2`.
