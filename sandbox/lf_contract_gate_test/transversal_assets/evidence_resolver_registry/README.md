# EVIDENCE_RESOLVER_REGISTRY

Capability transversal LF: `EVIDENCE_RESOLVER_REGISTRY` / `TRANSVERSAL_EVIDENCE_RESOLVER_REGISTRY`.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Versión inventariada: `v1`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/evidence_resolver_registry/README.md`

## Propósito

Resolver de forma gobernada qué resolver de evidencia corresponde a cada tipo de evidencia.

El registry gobierna identidad, provider, método de verificación y trust del resolver. **No es por sí mismo un cliente HTTP ni un transport de GitHub.** El transporte compartido de GitHub usado por `lf-contract-check` pertenece a `GITHUB_CONTRACT_GATE_LF` y debe conservar la identidad de este registry cuando corresponda anclar evidencia durable.

## Cuándo consumirlo

Cuando una operación necesita convertir una referencia de evidencia en un readback verificable o anclar un readback provider-bound en el evidence ledger.

Antes de usarlo, resolver el activo en `public.lf_activos` y confirmar que no esté archivado, que siga `ACTIVO` y que `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

## Cómo consumirlo

1. Resolver primero `EVIDENCE_RESOLVER_REGISTRY` en el inventario transversal; no buscar una implementación nueva antes de revisar este activo.
2. Entrar por `private.lf_evidence_resolver_registry_v1` o por la superficie canónica equivalente indicada por el contrato vigente.
3. Seleccionar únicamente un `resolver_id` cuya semántica corresponda al tipo de evidencia; provider coincidente no basta.
4. Conservar la identidad de la operación/consumer, source revision y evidencia que exige el contrato de la capability.
5. Si el resultado es `FAIL` o `BLOCKED`, conservar el diagnóstico durable y seguir la ruta de error gobernada aplicable; no crear un writer, store o resolver paralelo.
6. Cerrar únicamente con readback desde la superficie canónica y currentness suficiente para la decisión.

## GitHub transport compartido

Para consumers de `GITHUB_CONTRACT_GATE_LF`, el acceso HTTP al provider GitHub se centraliza en:

`sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/github_api_readback_v1.py`

Ese boundary implementa retry/backoff y clasificación común de `BLOCKED_INFRA_DNS`, `BLOCKED_GITHUB_API`, `FAIL_AUTH`, `FAIL_GITHUB_API` y `FAIL_EVIDENCE_MISMATCH`.

El boundary **no puede inventar un resolver**. En particular, `LF_GITHUB_SOURCE_READBACK_V1` conserva su semántica de source readback + hash y no debe reutilizarse para Actions inventory u otra evidencia solo porque el provider también sea GitHub. Si falta un resolver compatible para un anclaje durable, bloquear y ampliar este registry mediante su owner/gobernanza; no degradar la semántica.

## Superficies canónicas

- `private.lf_evidence_resolver_registry_v1`
- `private.fn_lf_evidence_resolver_registry_immutable_v1`

Las superficies anteriores son referencias de consumo/implementación. Si existe discrepancia entre este README y el contrato/runtime vigente, prevalece la autoridad canónica y el README debe actualizarse.

## Fail-closed / límites

No crear resolvers ad hoc en consumidores cuando existe un registro canónico; el registry es inmutable para update/delete por el camino vigente.

No seleccionar un resolver por `provider` solamente. Deben coincidir también el propósito y el método de verificación requeridos por la evidencia.

Si falta una dependencia, binding, currentness, permiso, resolver semánticamente compatible o evidencia requerida, el consumidor debe bloquear y reportar el primer punto no satisfecho.

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
