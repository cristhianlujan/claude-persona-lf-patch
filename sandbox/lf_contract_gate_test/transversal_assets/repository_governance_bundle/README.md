# REPOSITORY_GOVERNANCE_BUNDLE

Capability transversal LF: `REPOSITORY_GOVERNANCE_BUNDLE` / `TRANSVERSAL_REPOSITORY_GOVERNANCE_BUNDLE`.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Versión inventariada: `v4`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/repository_governance_bundle/README.md`

## Propósito

Entregar un bundle canónico y verificable de gobernanza del repositorio.

## Cuándo consumirlo

Cuando una operación necesita currentness/policies/repositorio sin recomponer manualmente múltiples fuentes.

Antes de usarlo, resolver el activo en `public.lf_activos` y confirmar que no esté archivado, que siga `ACTIVO` y que `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

## Cómo consumirlo

1. Resolver primero `REPOSITORY_GOVERNANCE_BUNDLE` en el inventario transversal; no buscar una implementación nueva antes de revisar este activo.
2. Entrar por `public.get_lf_repository_governance_bundle_v4` o por la superficie canónica equivalente indicada por el contrato vigente.
3. Conservar la identidad de la operación/consumer, source revision y evidencia que exige el contrato de la capability.
4. Si el resultado es `FAIL` o `BLOCKED`, conservar el diagnóstico durable y seguir la ruta de error gobernada aplicable; no crear un writer o store paralelo.
5. Cerrar únicamente con readback desde la superficie canónica y currentness suficiente para la decisión.

## Superficies canónicas

- `private.lf_repository_governance_bundle_v4`
- `private.fn_guard_repository_governance_bundle_v4`
- `public.get_lf_repository_governance_bundle_v4`

Las superficies anteriores son referencias de consumo/implementación. Si existe discrepancia entre este README y el contrato/runtime vigente, prevalece la autoridad canónica y el README debe actualizarse.

## Fail-closed / límites

Consumir el bundle current; no copiar sus reglas a contratos locales ni mutar la fuente privada desde consumidores.

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
