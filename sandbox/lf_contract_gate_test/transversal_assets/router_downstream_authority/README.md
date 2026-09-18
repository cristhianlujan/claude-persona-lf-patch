# ROUTER_DOWNSTREAM_AUTHORITY

Capability transversal LF: `ROUTER_DOWNSTREAM_AUTHORITY` / `TRANSVERSAL_ROUTER_DOWNSTREAM_AUTHORITY`.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Versión inventariada: `v0.4`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/router_downstream_authority/README.md`

## Propósito

Materializar la decisión explícita de si una salida Router puede ejecutar downstream.

## Cuándo consumirlo

Después de resolver Router y antes de enqueue/dispatch/efecto downstream.

Antes de usarlo, resolver el activo en `public.lf_activos` y confirmar que no esté archivado, que siga `ACTIVO` y que `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

## Cómo consumirlo

1. Resolver primero `ROUTER_DOWNSTREAM_AUTHORITY` en el inventario transversal; no buscar una implementación nueva antes de revisar este activo.
2. Entrar por `ACT-0001 / downstream_execution_allowed` o por la superficie canónica equivalente indicada por el contrato vigente.
3. Conservar la identidad de la operación/consumer, source revision y evidencia que exige el contrato de la capability.
4. Si el resultado es `FAIL` o `BLOCKED`, conservar el diagnóstico durable y seguir la ruta de error gobernada aplicable; no crear un writer o store paralelo.
5. Cerrar únicamente con readback desde la superficie canónica y currentness suficiente para la decisión.

## Superficies canónicas

- `ACT-0001`
- `20260917034500_s30_router_ready_downstream_authority_v1`
- `PR871`

Las superficies anteriores son referencias de consumo/implementación. Si existe discrepancia entre este README y el contrato/runtime vigente, prevalece la autoridad canónica y el README debe actualizarse.

## Fail-closed / límites

READY_TO_EXECUTE sin autoridad downstream explícita no debe interpretarse como permiso.

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
