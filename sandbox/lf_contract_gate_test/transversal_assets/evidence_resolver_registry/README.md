# EVIDENCE_RESOLVER_REGISTRY

Capability transversal LF: `EVIDENCE_RESOLVER_REGISTRY` / `TRANSVERSAL_EVIDENCE_RESOLVER_REGISTRY`.

## Estado

- Owner transversal: `SUPER_ADMIN`.
- Estado operativo esperado: `ACTIVO`.
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`.
- Versión funcional inventariada: `v1`; versión normalizada en capability registry: `1.0.0`.
- Punto de entrada común para consumo gobernado: `public.fn_lf_capability_bind_from_orchestrator_v1`.
- Guard obligatorio: `ORCHESTRATOR_EXECUTION_GUARD_V1`.
- Autoridad de currentness: capability registry/current + `public.lf_activos` como inventario/lineage.

## Punto de entrada

Cualquier consumidor que necesite esta capability debe llegar mediante una ejecución válida del orquestador:

`caller -> orchestrator -> dispatch receipt -> ORCHESTRATOR_EXECUTION_GUARD_V1 -> capability binding -> EVIDENCE_RESOLVER_REGISTRY`.

Un caller no puede crear un binding nuevo directamente. La tabla privada continúa siendo la implementación canónica, no un entrypoint alternativo para consumidores.

## Propósito

Resolver de forma gobernada qué resolver de evidencia corresponde a cada tipo de evidencia.

## Cómo consumirlo

1. El orquestador resuelve la capability y emite un dispatch receipt ligado a consumer execution, capability y plan digest.
2. El consumer entra por `fn_lf_capability_bind_from_orchestrator_v1`.
3. Tras el binding/currentness válido, la implementación consulta `private.lf_evidence_resolver_registry_v1`.
4. Conservar execution/consumer identity, source revision y referencias de evidencia.
5. Si falta binding/currentness/resolver trusted o evidencia requerida: `BLOCK`; no crear resolver paralelo.

## Superficies canónicas

- `private.lf_evidence_resolver_registry_v1`
- `private.fn_lf_evidence_resolver_registry_immutable_v1`

## Fail-closed / límites

- Resolver identity debe provenir del registro trusted; no del payload candidato.
- No crear resolvers ad hoc en consumidores.
- El registry es inmutable por la ruta gobernada.
- No decide aplicabilidad, cierre, promoción ni lifecycle del consumer.

## No duplicación

No crear una segunda capability, tabla, runner, registry, writer o contrato para esta responsabilidad. Extender este activo conservando lineage.
