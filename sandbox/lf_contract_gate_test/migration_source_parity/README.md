# MIGRATION_SOURCE_PARITY / SOURCE RECONCILIATION

Esta carpeta contiene capacidades distintas pero relacionadas del dominio de migrations. Comparten contexto, no responsabilidad.

## 1. MIGRATION_SOURCE_PARITY

Control canónico que compara la fuente de migrations en Git con el ledger de Supabase y produce evidencia tipada de PASS/FAIL.

Responsabilidad:

- detectar divergencias Git ↔ Supabase;
- emitir evidencia canónica ligada al exact-head;
- no reparar por sí mismo;
- no fabricar source desde el ledger;
- no delegar su veredicto a un workflow genérico.

El workflow/carrier que lo ejecute es infraestructura de pase y no forma parte de su contrato funcional.

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

### MIGRATION_SOURCE_RECONCILIATION_V1

- `DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `DEPENDE_DE -> MIGRATION_WRITE_AHEAD_V1`.
- `GOBERNADO_POR -> ACT-0001`.
- `RELACIONADO_CAPACIDADES -> MIGRATION_ORCHESTRATED_SAGA_V1` solo por el cierre posterior del pedido.

## Separación de responsabilidades

```text
MIGRATION_SOURCE_PARITY
        │ finding canónico
        ▼
MIGRATION_SOURCE_RECONCILIATION_V1
        │
        ├─ recupera/verifica source
        ├─ delega persistencia a WRITE_AHEAD
        └─ emite SOURCE_REPAIR_PERSISTED
                │
                ▼
        pedido/orquestación superior
                │
                ├─ crea PR si corresponde
                ├─ ejecuta controles de pase
                ├─ obtiene nuevo PARITY PASS
                └─ continúa cierre con Saga
```

## Controles de pase

`CI_FAST_DEEP_LANE_ROUTER`, `S30_BOUNDED_REGRESSION`, E.16, `Validate LF Packs`, `LF DB Regression` y `lf-contract-check` pueden validar un cambio en esta carpeta, pero no son dependencias funcionales de Reconciliation.

## Archivos

- `MIGRATION_SOURCE_RECONCILIATION_V1.md`: contrato funcional de Reconciliation.
- `lf_migration_source_parity_repair.py`: implementación del coordinador de reparación source-only.
- `test_lf_migration_source_parity_repair.py`: pruebas propias.

El validador canónico de parity permanece en `sandbox/lf_contract_gate_test/lf_migration_source_parity.py`.

## Estado

La presencia en `main` documenta y versiona la capacidad. No implica por sí sola activación de runtime, producción ni ejecución automática.
