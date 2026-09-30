# TYPED_EVIDENCE_REGISTRY

Capability transversal LF: `TYPED_EVIDENCE_REGISTRY` / `TRANSVERSAL_TYPED_EVIDENCE_REGISTRY`.

## Estado

- Owner transversal: `SUPER_ADMIN`.
- Estado operativo esperado: `ACTIVO`.
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`.
- Versión funcional inventariada: `v3`; versión normalizada en capability registry: `3.0.0`.
- Punto de entrada común para consumo gobernado: `public.fn_lf_capability_bind_from_orchestrator_v1`.
- Guard obligatorio: `ORCHESTRATOR_EXECUTION_GUARD_V1`.
- Autoridad de currentness: capability registry/current + `public.lf_activos` como inventario/lineage.

## Punto de entrada

Consumo explícito:
`caller -> orchestrator -> dispatch receipt -> ORCHESTRATOR_EXECUTION_GUARD_V1 -> capability binding -> TYPED_EVIDENCE_REGISTRY`.

El trigger interno que protege `lf_eventos` sigue siendo enforcement pasivo del motor canónico; no constituye un entrypoint alternativo para que un consumer se autoautorice.

## Propósito

Registrar y validar schemas tipados de evidencia compartida antes de aceptar evidencia gobernada.

## Cómo consumirlo

1. El orquestador emite dispatch receipt ligado a consumer execution, capability y plan digest.
2. El consumer obtiene binding mediante `fn_lf_capability_bind_from_orchestrator_v1`.
3. La validación usa `private.fn_lf_typed_evidence_payload_valid_v3` y el schema registry vigente.
4. Payload no registrado o estructuralmente inválido debe bloquear.
5. No degradar a JSON libre ni crear un registry paralelo.

## Superficies canónicas

- `private.lf_typed_evidence_schema_registry_v3`
- `private.fn_lf_typed_evidence_payload_valid_v3`
- `private.fn_enforce_typed_evidence_registry_v3`

## Fail-closed / límites

- Schema desconocido o payload inválido = `BLOCK`.
- No decide aplicabilidad, cierre, promoción ni lifecycle.
- El trigger pasivo valida persistencia; no sustituye la admisión del consumer por el orquestador.

## No duplicación

No crear una segunda capability, tabla, runner, registry, writer o contrato para esta responsabilidad. Extender este activo conservando lineage.
