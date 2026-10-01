# MIGRATION_SOURCE_RECONCILIATION_V1

## Identidad y estado

- Tipo: `CAPABILITY` transversal.
- Owner canónico: `SUPER_ADMIN`.
- Owner legacy previo: `LF_GOVERNANCE_S30_DB`.
- Versión funcional: `1.0.0`.
- Estado funcional actual: `READ_ONLY` / runtime no activado.
- Registry state objetivo de este cutover: `REGISTERED_GUARDED_NOT_CURRENT`.
- Current pointer: **no debe existir** hasta una activación separada y explícita.

## Punto de entrada obligatorio

```text
CALLER
  |
  v
ORCHESTRATOR DISPATCH
  |
  v
ORCHESTRATOR_EXECUTION_GUARD_V1
  |
  +-- receipt ausente/inválido -> BLOCK
  +-- orchestrator no operacional -> BLOCK
  +-- capability/consumer/plan_digest mismatch -> BLOCK
  |
  v
public.fn_lf_capability_bind_from_orchestrator_v1
  |
  +-- capability sin current pointer -> BLOCK_NO_CURRENT_CAPABILITY
  |
  v
MIGRATION_SOURCE_RECONCILIATION_V1
```

El guard de entrada se comparte con las demás capacidades; no se reimplementa dentro del coordinador. Registrar la capability **no** activa runtime, producción ni autorización de reparación.

## Objetivo

Reconciliar únicamente una divergencia Git ↔ Supabase que `MIGRATION_SOURCE_PARITY` haya identificado canónicamente como fuente remota faltante en Git, recuperando y persistiendo los bytes exactos sin reejecutar DDL ni mutar el migration ledger.

## Entrada canónica

El reconciliador consume evidencia `LF_GATE_ERROR_V1` producida por `LF_GATE_CHECK_OBSERVABILITY_V1` para `MIGRATION_SOURCE_PARITY`.

No depende de `lf-contract-check` ni de un workflow/carrier específico. La evidencia debe estar ligada al mismo exact-head y a un único check canónico de `sandbox/lf_contract_gate_test/lf_migration_source_parity.py`.

## Aplicabilidad

Único caso reparable V1:

- `FAIL_LF_MIGRATION_VERSION_PARITY`;
- exactamente una versión `remote_only`;
- cero versiones `local_only`.

Cualquier otro caso queda `NOT_APPLICABLE` o bloqueado para su owner. La capability no descubre aplicabilidad por sí sola: el orquestador solo la despacha cuando el plan ya la declaró aplicable.

## Dependencias obligatorias

1. `MIGRATION_SOURCE_PARITY` — detector/verificador canónico.
2. `MIGRATION_WRITE_AHEAD_V1` — persistencia del source recuperado.
3. `CURRENTNESS_AUTHORITY` — currentness del material/capability.
4. `ORCHESTRATOR_EXECUTION_GUARD_V1` — admisión transversal.

`MIGRATION_ORCHESTRATED_SAGA_V1` es una capacidad relacionada del cierre posterior; no es dependencia interna.

## Flujo propio

1. Validar evidencia canónica de `MIGRATION_SOURCE_PARITY` y su digest/head.
2. Extraer la única versión `remote_only` del finding exacto.
3. Usar receipts históricos solo como locators.
4. Releer source exacto desde Git.
5. Revalidar bytes contra ledger vivo con comparador transport-aware existente.
6. Delegar persistencia a `MIGRATION_WRITE_AHEAD_V1`.
7. Emitir `SOURCE_REPAIR_PERSISTED` con `pr_request` y requisitos posteriores.
8. Terminar.

## Invariantes

- una sola identidad/version por reparación;
- `ddl_replayed=false`;
- `ledger_mutated=false`;
- no direct-main write;
- no merge propio;
- no apertura directa de PR;
- locator ambiguo o source mismatch = bloqueo;
- ningún segundo motor de parity ni writer paralelo;
- no PASS fabricado para Saga;
- sin current pointer, una entrada guardada termina `BLOCK_NO_CURRENT_CAPABILITY`.

## Implementación

- Coordinator: `lf_migration_source_parity_repair.py`.
- Tests: `test_lf_migration_source_parity_repair.py`.
- Persistencia Git reutilizada: `MIGRATION_WRITE_AHEAD_V1` / `lf_migration_git_persist.py`.
- Registry projection: `MIGRATION_SOURCE_RECONCILIATION_V1_registry_projection.sql`.
- Inventory/readback: `MIGRATION_SOURCE_RECONCILIATION_V1_inventory_v1.json`.

## Relaciones canónicas

- `OWNER -> SUPER_ADMIN`.
- `ENTRY_GUARD -> ORCHESTRATOR_EXECUTION_GUARD_V1`.
- `DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `DEPENDE_DE -> MIGRATION_WRITE_AHEAD_V1`.
- `GOBERNADO_POR -> ACT-0001`.
- `RELACIONADO_CAPACIDADES -> MIGRATION_ORCHESTRATED_SAGA_V1`.

No existe dependencia funcional hacia S30, E.16, `lf-contract-check` ni carriers CI.

## Activación

Este cutover solo registra ownership/version/entry guard. No crea `lf_capability_current` para esta capability. La activación runtime/current pointer requiere un paso separado con evidencia y autorización específica.
