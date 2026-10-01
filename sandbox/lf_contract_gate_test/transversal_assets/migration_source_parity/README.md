# MIGRATION_SOURCE_PARITY

Capability transversal LF: `MIGRATION_SOURCE_PARITY` / `TRANSVERSAL_MIGRATION_SOURCE_PARITY`.

## Estado e identidad

- Tipo: `CAPABILITY`.
- Subtipo objetivo: `TRANSVERSAL_GOVERNANCE_CONTROL`.
- Rol: `MIGRATION_GIT_LEDGER_PARITY_GUARD`.
- Owner canónico: `SUPER_ADMIN`.
- Owner legacy previo al cutover: `LF_GOVERNANCE_S30_DB`.
- Versión funcional: `1.0.0`.
- Estado operativo vigente: `ACTIVO`.
- Inventory status: `ACTIVE_SHARED_ENFORCEMENT`.
- Registry: `public.lf_capability_registry` / `public.lf_capability_current`.
- Autoridad de currentness: `CURRENTNESS_AUTHORITY` + readback de registry.

## Punto de entrada obligatorio

Todo caller debe entrar por el mismo contrato transversal:

```text
CALLER
  |
  v
ORCHESTRATOR DISPATCH
  |
  v
ORCHESTRATOR_EXECUTION_GUARD_V1
  |
  +-- dispatch receipt ausente/inválido -> BLOCK
  +-- orchestrator no operacional -> BLOCK
  +-- capability/consumer/plan_digest mismatch -> BLOCK
  |
  v
public.fn_lf_capability_bind_from_orchestrator_v1
  |
  v
MIGRATION_SOURCE_PARITY
```

Reglas:

- nuevas entradas directas por `public.fn_lf_capability_bind_current_v1` deben bloquearse;
- el artefacto no hardcodea un operation code de orquestador;
- el guard resuelve la autoridad desde `lf_operation_registry` con `operation_family='ORCHESTRATION'` y lifecycle operacional;
- el dispatch receipt debe estar cross-bound a `orchestrator_execution_id`, `consumer_execution_id`, `capability_code` y `plan_digest`;
- la capability no decide aplicabilidad ni puede auto-admitirse.

## Propósito

Comprobar, en modo fail-closed, que un snapshot ya resuelto de migrations en Git y el snapshot correspondiente del ledger `supabase_migrations.schema_migrations` tienen la misma identidad y contenido canónico.

El núcleo funcional valida el conjunto exacto de versiones, nombre exacto por versión, contenido exacto bajo la normalización de transporte vigente y cardinalidad de statements del ledger. Emite `PASS` o un error canónico de parity.

No crea ni modifica migrations, no aplica DDL, no repara source, no crea PR, no decide controles de pase y no administra lifecycle.

## Cuándo consumirlo

- al verificar la consistencia Git ↔ ledger de una migration gobernada;
- antes de que `MIGRATION_ORCHESTRATED_SAGA_V1` cierre `CONSISTENT`;
- al producir el finding que puede habilitar condicionalmente `MIGRATION_SOURCE_RECONCILIATION_V1`;
- desde PASE, POST-PASE, Assurance u otro consumidor solo cuando el orquestador lo haya incluido en su plan.

## Cómo consumirlo

1. El Router/consumer determina aplicabilidad; `MIGRATION_SOURCE_PARITY` no la recalcula.
2. El Orquestador emite un dispatch receipt exacto para la ejecución consumidora.
3. Entrar por `public.fn_lf_capability_bind_from_orchestrator_v1`.
4. Resolver currentness/version de `MIGRATION_SOURCE_PARITY` desde el capability registry.
5. Entregar al core snapshots ya resueltos de Git y ledger.
6. Interpretar únicamente el resultado tipado del core; ningún workflow puede fabricar el veredicto.
7. En `FAIL`, preservar el finding; la reparación corresponde a `MIGRATION_SOURCE_RECONCILIATION_V1` cuando sea aplicable.

## Superficies canónicas

### Núcleo funcional

- `sandbox/lf_contract_gate_test/migration_source_parity/migration_source_parity_core.py`
- `sandbox/lf_contract_gate_test/migration_transport_normalization.py`

`migration_source_parity_core.py` recibe snapshots ya resueltos y no conoce GitHub, PRs, workflows, `required_controls`, conexiones DB ni ejecución de procesos.

### Adapter de pase / compatibilidad CI

- `sandbox/lf_contract_gate_test/lf_migration_source_parity.py`

El adapter existente puede preparar inputs/contexto. No define ownership, aplicabilidad ni entry authority.

`.github/workflows/lf-contract-check.yml`, `GITHUB_CONTRACT_GATE_LF`, `CI_FAST_DEEP_LANE_ROUTER` y S30 son carriers/controles históricos que pueden ejecutar o validar la capability; no son superficies funcionales ni autoridades de entrada.

### Registry projection

- `sandbox/lf_contract_gate_test/transversal_assets/migration_source_parity/MIGRATION_SOURCE_PARITY_registry_projection_v1.sql`

## Consumidores y relaciones

Consumidores funcionales conocidos:

- `MIGRATION_ORCHESTRATED_SAGA_V1`.
- `MIGRATION_SOURCE_RECONCILIATION_V1`.
- `MIGRATION_WRITE_AHEAD_V1` es capability relacionada; no delega persistencia a Parity.

Relaciones canónicas:

- `OWNER -> SUPER_ADMIN`.
- `GOBERNADO_POR -> ACT-0001`.
- `ENTRY_GUARD -> ORCHESTRATOR_EXECUTION_GUARD_V1`.
- Las dependencias de Saga/Reconciliation hacia Parity se registran desde los consumidores.
- No existe dependencia funcional `MIGRATION_SOURCE_PARITY -> lf-contract-check` ni hacia un workflow.

## Fail-closed / límites

- Una diferencia de versión, nombre, contenido o cardinalidad no se convierte en PASS por contexto de CI.
- Parity nunca aplica DDL, escribe Git ni reconstruye source desde el ledger.
- Un finding reparable no autoriza a Parity a modificar nada.
- Owner/orquestador/receipt ausente, ambiguo o no vigente bloquea antes de ejecutar el core.
- No hardcodear PR, SHA, migration version o filename para exceptuar divergencias.

## Validación y readback

- Core: `sandbox/lf_contract_gate_test/s30_migration_source_parity/test_migration_source_parity_core.py`.
- Adapter/compatibilidad: tests existentes de `lf_migration_source_parity.py` y transporte.
- Cambios de contrato deben revalidar Saga y Reconciliation como consumidores.
- Readback final: registry/current pointer + `lf_activos` + entry guard + source revision.

## No duplicación

No crear un segundo activo ni un segundo comparador de transporte. El core y el adapter son dos superficies de la misma capability; el guard de entrada también es transversal y compartido, no se reimplementa dentro del core.
