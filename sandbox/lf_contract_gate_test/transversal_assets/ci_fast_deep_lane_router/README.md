# CI_FAST_DEEP_LANE_ROUTER

Capability transversal LF: `CI_FAST_DEEP_LANE_ROUTER` / `TRANSVERSAL_CI_FAST_DEEP_LANE_ROUTER`.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/README.md`

## Propósito

Clasificar cambios y seleccionar el carril CI FAST o DEEP sin duplicar validadores.

## Cuándo consumirlo

Antes de ejecutar validaciones CI costosas, para decidir el nivel de profundidad requerido por el cambio.

Antes de usarlo, resolver el activo en `public.lf_activos` y confirmar que no esté archivado, que siga `ACTIVO` y que `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

## Cómo consumirlo

1. Resolver primero `CI_FAST_DEEP_LANE_ROUTER` en el inventario transversal; no buscar una implementación nueva antes de revisar este activo.
2. Entrar por `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py` o por la superficie canónica equivalente indicada por el contrato vigente.
3. Conservar la identidad de la operación/consumer, source revision y evidencia que exige el contrato de la capability.
4. Si el resultado es `FAIL` o `BLOCKED`, conservar el diagnóstico durable y seguir la ruta de error gobernada aplicable; no crear un writer o store paralelo.
5. Cerrar únicamente con readback desde la superficie canónica y currentness suficiente para la decisión.

## Superficies canónicas

- `sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py`
- `test_lf_ci_lane_router.py`
- `.github/workflows/lf-contract-check.yml`

Las superficies anteriores son referencias de consumo/implementación. Si existe discrepancia entre este README y el contrato/runtime vigente, prevalece la autoridad canónica y el README debe actualizarse.

## Fail-closed / límites

Una clasificación desconocida o materialmente compartida no debe degradarse silenciosamente a FAST.

Si falta una dependencia, binding, currentness, permiso o evidencia requerida, el consumidor debe bloquear y reportar el primer punto no satisfecho.

## Validación y readback

- Verificar currentness del activo antes de consumirlo.
- Ejecutar los gates/tests propios de la capability y del consumer; no convertir un test local en cierre global.
- Mantener source revision, execution/consumer identity y referencias de evidencia.
- Leer de vuelta el resultado desde la superficie durable correspondiente.
- Para cambios de contrato o comportamiento, revalidar consumidores afectados y actualizar este README.

## No duplicación

No crear una segunda capability, tabla, runner, registry, writer o contrato que resuelva la misma responsabilidad. Si el contrato actual no cubre un caso válido, extender este activo por su owner y conservar lineage.

## Currentness

Este README describe cómo consumir la capability, pero no fija su estado para siempre. El consumidor debe consultar `public.lf_activos` y la superficie runtime vigente en cada decisión material.
