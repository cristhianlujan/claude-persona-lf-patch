# ASSET_RETIREMENT_GOVERNANCE

Capability transversal LF para retirar, reemplazar o deprecar activos sin dejar consumidores, rutas, receipts, relaciones o metadata obsoleta.

- Código: `ASSET_RETIREMENT_GOVERNANCE`
- Nombre canónico: `TRANSVERSAL_ASSET_RETIREMENT_GOVERNANCE`
- Estado candidato: `CANDIDATO / READ_ONLY` hasta merge + readback autorizado
- Autoridad operativa: `public.lf_activos` + GitHub `main`
- Drive: soporte de inventario/consulta, nunca autoridad
- No implementa runtime, router, judge ni engine nuevo

## Propósito

Establecer un único procedimiento reutilizable para retirar activos de LF de forma comprobable. Evita dos fallos recurrentes: borrar la superficie visible pero dejar consumidores ocultos, o conservar responsabilidades válidas dentro de un carrier obsoleto por miedo a retirarlo.

## Cuándo consumirlo

Antes de declarar `RETIRADO`, `DEPRECADO`, eliminar/renombrar un workflow, capability, policy, operación, perfil, card, skill, adapter, contrato o carrier; y también cuando una auditoría detecte un activo sin consumidor claro o una capacidad duplicada.

## Lifecycle canónico

`DISCOVER → MAP_CONSUMERS → CLASSIFY_RESPONSIBILITIES → DISCONNECT → REHOME → GUARD → PROMOTE → POST_PROMOTION_READBACK → CLOSE`

No se puede saltar de `DISCOVER` a eliminación física.

## Cómo consumirlo

1. Resolver identidad canónica, aliases, rutas físicas, estado y owner en `public.lf_activos` y GitHub.
2. Inventariar consumidores directos y transitivos en código, registries, manifests, required checks, receipts, metadata, relaciones y PRs/branches abiertos.
3. Consultar EKB para reconstruir incidentes y consumidores históricos que ya hayan dejado evidencia.
4. Clasificar cada responsabilidad del activo como `RETIRE`, `KEEP_AND_REHOME` o `HISTORICAL_ONLY`.
5. Desconectar primero cada consumidor; no borrar el carrier antes de llegar a cero consumidores operativos.
6. Reubicar responsabilidades válidas bajo un owner/carrier natural existente; no crear capas paralelas.
7. Añadir guardias anti-reintroducción cuando el activo retirado pueda volver por branches, registries o configuración heredada.
8. Ejecutar CI exact-head y readback de autoridad.
9. Promover solo con autorización aplicable.
10. Ejecutar readback post-promoción y cerrar únicamente con prueba de cero residuos operativos.

## Superficies que siempre deben inventariarse

- GitHub: workflows, scripts, source, registries, manifests, tests, README, required checks, receipts y PRs/branches descendientes de autoridad anterior.
- Supabase: `public.lf_activos`, `public.lf_activo_relaciones`, `metadata.canonical_dependencies`, metadata de consumers/owners y EKB (`public.lf_error_knowledge`).
- CI: routing, `required_controls`, carrier ownership, receipts y currentness.
- Evidencia histórica: EKB, receipts y metadata histórica inmutable.
- Drive: inventarios y mapas de soporte únicamente; nunca sustituye GitHub/Supabase.

## Criterios de cierre

Un retiro es `COMPROBADO` solo si todos aplican:

1. `ZERO_OPERATIONAL_CONSUMERS = YES`
2. `ZERO_STALE_ROUTING = YES`
3. `ZERO_STALE_RECEIPT_CONSUMERS = YES`
4. `ZERO_STALE_RELATIONS = YES`
5. `ZERO_STALE_CANONICAL_DEPENDENCIES = YES`
6. `ZERO_RETIRED_ASSET_IDENTITY_ROWS = YES`, salvo registro histórico explícitamente modelado como tal
7. responsabilidades válidas reubicadas con owner único
8. `REINTRODUCTION_GUARD = ACTIVE` cuando corresponda
9. CI exact-head compatible con el cambio
10. post-promotion readback de GitHub + Supabase
11. PRs/branches antiguos capaces de reintroducir el activo reconciliados o bloqueados
12. evidencia del retiro persistida y enlazada desde el inventario transversal

Las menciones históricas no cuentan como residuo si están dentro de EKB, receipts, metadata de reconciliación o guardias negativas y no tienen poder operativo.

## Modelo de evidencia

Cada retiro debe persistir un paquete machine-readable bajo `evidence/` con:

- identidad y aliases retirados;
- autoridad base y revisión promovida;
- mapa de consumidores directos/transitivos/históricos;
- responsabilidades retiradas y reubicadas;
- PR/commit/runs de CI;
- readback de workflow/rutas;
- contadores de cero residuos;
- referencias EKB;
- inventarios auxiliares usados;
- resultado y límites de la comprobación.

El primer caso canónico es `LF_BOOTSTRAP_REPRODUCIBILITY`; ver `evidence/lf_bootstrap_reproducibility_retirement_20260923.json`.

## Relaciones

Las relaciones de esta capability se registran en `public.lf_activo_relaciones` usando tipos existentes siempre que expresen correctamente el vínculo. El detalle histórico del activo retirado puede vivir en metadata/evidencia cuando no exista una entidad activa que pueda actuar como FK/owner.

Esta capability se relaciona con, pero no reemplaza:

- `CI_FAST_DEEP_LANE_ROUTER`: applicability/routing CI;
- `GITHUB_CONTRACT_GATE_LF`: enforcement/consumer CI;
- `FULL_REGRESSION`: verificación downstream del plan;
- `CURRENTNESS_AUTHORITY`: vigencia de autoridad;
- EKB: aprendizaje y prevención.

## Fail-closed / límites

Bloquear cierre si falta inventario de una superficie material, aparece un consumidor no clasificado, una responsabilidad válida queda sin owner, un PR antiguo puede reintroducir el activo, o el readback post-promoción no coincide con la evidencia.

No convertir este contrato en un runtime. No crear otro Router, currentness engine, registry de CI, judge ni reconciliador. Esta capability define lifecycle, evidencia y obligaciones; los engines existentes ejecutan sus responsabilidades actuales.

## Validación y readback

La validación mínima combina:

- búsqueda GitHub de identidad/aliases/rutas retiradas;
- readback de `public.lf_activos` y `public.lf_activo_relaciones`;
- expansión de `metadata.canonical_dependencies`;
- EKB sweep histórico;
- revisión de PRs/branches con base anterior;
- CI exact-head;
- readback de `main` después de promoción;
- comparación contra inventarios auxiliares de Drive sin tratarlos como autoridad.

## No duplicación

No crear una capability por cada retiro. Cada retiro es una instancia/evidencia de este mismo contrato transversal.

## Currentness

El contrato se resuelve desde `refs/heads/main` y `public.lf_activos`. Los SHAs, run IDs y conteos de cero residuos dentro de una evidencia son observaciones históricas y no deben reescribirse para aparentar vigencia. Si cambia una superficie canónica, se genera nueva evidencia/readback sin destruir la anterior.
