# MIGRATION_SOURCE_PARITY / SOURCE RECONCILIATION

Esta carpeta contiene capacidades relacionadas del dominio de migrations, pero con responsabilidades separadas.

## 1. MIGRATION_SOURCE_PARITY

Capability canónica que compara un snapshot ya resuelto de fuente Git con el ledger de Supabase y produce un resultado tipado de parity.

### Responsabilidad funcional

- detectar divergencias de versión, nombre o contenido Git ↔ Supabase;
- reconocer únicamente representaciones de transporte explícitamente soportadas;
- emitir `PASS` o error canónico fail-closed;
- no reparar por sí misma;
- no fabricar source desde el ledger;
- no aplicar DDL ni mutar el ledger;
- no decidir qué controles de pase deben ejecutarse.

### Núcleo funcional

- `migration_source_parity_core.py`: invariante puro de parity sobre snapshots ya resueltos.
- `../migration_transport_normalization.py`: comparador canónico de representación de transporte.
- `test_migration_source_parity_core.py`: positivos, negativos y prueba de ausencia de acoplamiento CI/process.

### Adapter de pase existente

`../lf_migration_source_parity.py` conserva el contexto específico de PR/CI necesario para el carrier actual: source-first pendiente, currentness de owner concurrente y preparación de inputs.

El adapter no cambia la responsabilidad del activo. `CI_FAST_DEEP_LANE_ROUTER`, S30, `lf-contract-check`, `Validate LF Packs` y `LF DB Regression` pertenecen al plano de pase.

## 2. MIGRATION_SOURCE_RECONCILIATION_V1

Capacidad condicional que actúa solo cuando `MIGRATION_SOURCE_PARITY` produce un finding reparable V1: una única versión `remote_only`, sin `local_only`, bajo `FAIL_LF_MIGRATION_VERSION_PARITY`.

Responsabilidad propia:

1. validar finding + evidencia canónica de parity;
2. recuperar y verificar el source exacto;
3. persistirlo mediante `MIGRATION_WRITE_AHEAD_V1`;
4. emitir `SOURCE_REPAIR_PERSISTED` + `pr_request`;
5. terminar.

No abre PR directamente, no ejecuta CI, no reejecuta DDL, no muta el ledger y no ejecuta Saga.

## Relaciones canónicas

### MIGRATION_SOURCE_PARITY

- `GOBERNADO_POR -> ACT-0001`.
- `MIGRATION_ORCHESTRATED_SAGA_V1 DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `MIGRATION_SOURCE_RECONCILIATION_V1 DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `MIGRATION_WRITE_AHEAD_V1 RELACIONADO_CAPACIDADES -> MIGRATION_SOURCE_PARITY`.

### MIGRATION_SOURCE_RECONCILIATION_V1

- `DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `DEPENDE_DE -> MIGRATION_WRITE_AHEAD_V1`.
- `GOBERNADO_POR -> ACT-0001`.
- `RELACIONADO_CAPACIDADES -> MIGRATION_ORCHESTRATED_SAGA_V1` solo por el cierre posterior del pedido.

## Separación de responsabilidades

```text
Git snapshot + Supabase ledger snapshot
                │
                ▼
      MIGRATION_SOURCE_PARITY
          functional core
                │
        PASS / finding
          ┌─────┴─────────┐
          │               │
          ▼               ▼
        SAGA       RECONCILIATION
                          │
                          └─ solo si finding reparable

Plano de pase separado:
PR/change -> CI router -> carrier -> parity adapter -> core
```

## Controles de pase

`CI_FAST_DEEP_LANE_ROUTER`, `S30_BOUNDED_REGRESSION`, E.16, `Validate LF Packs`, `LF DB Regression` y `lf-contract-check` pueden validar o transportar la ejecución, pero no son dependencias funcionales de Parity ni de Reconciliation.

## Archivos

- `migration_source_parity_core.py`: core funcional de Parity.
- `test_migration_source_parity_core.py`: tests del core.
- `MIGRATION_SOURCE_RECONCILIATION_V1.md`: contrato funcional de Reconciliation.
- `lf_migration_source_parity_repair.py`: coordinador de reparación source-only.
- `test_lf_migration_source_parity_repair.py`: pruebas de Reconciliation.
- `../lf_migration_source_parity.py`: adapter de PR/CI existente para Parity.

## Estado

La documentación y código en una rama/PR no cambian por sí solos la autoridad vigente de `public.lf_activos`. La metadata canónica de Supabase debe actualizarse únicamente al source revision que corresponda al estado aceptado; no implica activación runtime ni productiva.
