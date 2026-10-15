# M10.7 A4 — resolvedor de reglas API una vez por invocación

## Alcance
Optimizar exclusivamente `programacion.fn_input_api_contract_resolution(integer)`: actualmente llama dos veces a `fn_input_effective_rule_links_v1` en sentencias distintas. Consolidar ambas consultas con una CTE `MATERIALIZED` en la misma sentencia. No compartir datos entre llamadas o transacciones.

## Admisión
EKB leído: IG-M107-ALL-STAGES-QUERY-INVENTORY-007, IG-M107-A3-INCALL-CANONICAL-PROMOTION-016. Migración por Router ACT-0001 / LF Migration Merge Train. MD5 preflight y rollback transaccional. Pruebas materiales con cinco pantallas, igualdad JSONB y SHA, controles negativos, integridad de contrato API y permisos originales.

## No hacer
No modificar reglas, triggers, contratos, controles de vigencia, perfiles, funciones ajenas ni producción de forma directa. No atribuir ahorro total del Validator ni cerrar CP3 por microbenchmark de función.

## Criterio de cierre
PR fusionado a main, versión exacta en ledger, función canónica de una sola resolución, EKB de prueba y readback de permisos; luego pasar al siguiente frente M10.7.