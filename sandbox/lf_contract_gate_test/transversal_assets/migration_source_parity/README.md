# MIGRATION_SOURCE_PARITY

Capability transversal LF: `MIGRATION_SOURCE_PARITY` / `TRANSVERSAL_MIGRATION_SOURCE_PARITY`.

## Estado e identidad

- Tipo: `CAPABILITY`.
- Subtipo objetivo: `TRANSVERSAL_GOVERNANCE_CONTROL`.
- Rol: `MIGRATION_GIT_LEDGER_PARITY_GUARD`.
- Owner: `LF_GOVERNANCE_S30_DB`.
- Versión funcional: `1.0.0`.
- Estado operativo vigente: `ACTIVO`.
- Inventory status: `ACTIVE_SHARED_ENFORCEMENT`.
- Autoridad de currentness: `public.lf_activos`.

## Propósito

Comprobar, en modo fail-closed, que un snapshot ya resuelto de migrations en Git y el snapshot correspondiente del ledger `supabase_migrations.schema_migrations` tienen la misma identidad y contenido canónico.

El núcleo funcional valida el conjunto exacto de versiones, nombre exacto por versión, contenido exacto bajo la normalización de transporte vigente y cardinalidad de statements del ledger. Emite `PASS` o un error canónico de parity.

No crea ni modifica migrations, no aplica DDL, no repara source, no crea PR, no decide controles de pase y no administra lifecycle.

## Cuándo consumirlo

- al verificar la consistencia Git ↔ ledger de una migration gobernada;
- antes de que `MIGRATION_ORCHESTRATED_SAGA_V1` cierre `CONSISTENT`;
- al producir el finding que puede habilitar condicionalmente `MIGRATION_SOURCE_RECONCILIATION_V1`;
- desde un control de pase cuando ese control necesite comprobar parity, sin convertir el carrier en autoridad funcional.

## Cómo consumirlo

1. Resolver `MIGRATION_SOURCE_PARITY` desde `public.lf_activos` y comprobar currentness.
2. Para consumo funcional, entregar al core snapshots ya resueltos de Git y ledger.
3. Interpretar únicamente el resultado tipado del core; ningún workflow puede fabricar el veredicto.
4. Si el consumer es CI/PR, usar el adapter existente para obtener contexto del pase y después aplicar el mismo invariante funcional.
5. En `FAIL`, preservar el finding; la reparación corresponde a la capability separada `MIGRATION_SOURCE_RECONCILIATION_V1` cuando sea aplicable.

## Superficies canónicas

### Núcleo funcional

- `sandbox/lf_contract_gate_test/migration_source_parity/migration_source_parity_core.py`
- `sandbox/lf_contract_gate_test/migration_transport_normalization.py`

`migration_source_parity_core.py` recibe snapshots ya resueltos y no conoce GitHub, PRs, workflows, `required_controls`, conexiones DB ni ejecución de procesos.

### Adapter de pase / compatibilidad CI

- `sandbox/lf_contract_gate_test/lf_migration_source_parity.py`

El adapter existente puede resolver contexto de source-first, currentness de owner concurrente y preparar inputs del pase. Ese adapter **no define la responsabilidad del activo**.

`.github/workflows/lf-contract-check.yml`, `GITHUB_CONTRACT_GATE_LF`, `CI_FAST_DEEP_LANE_ROUTER` y S30 son carriers/controles de pase que pueden ejecutar o validar la capability; no son superficies funcionales ni dependencias de `MIGRATION_SOURCE_PARITY`.

## Consumidores y relaciones

Consumidores funcionales conocidos:

- `MIGRATION_ORCHESTRATED_SAGA_V1`: exige parity `PASS` antes de cerrar `CONSISTENT`.
- `MIGRATION_SOURCE_RECONCILIATION_V1`: consume findings de parity y, tras una reparación, parity vuelve a ser el verificador independiente.
- `MIGRATION_WRITE_AHEAD_V1`: capability relacionada; no delega a Parity la persistencia.

Relaciones canónicas:

- `GOBERNADO_POR -> ACT-0001`.
- Las dependencias de Saga y Reconciliation hacia Parity se registran desde los consumidores (`DEPENDE_DE -> MIGRATION_SOURCE_PARITY`).
- No existe dependencia funcional `MIGRATION_SOURCE_PARITY -> lf-contract-check` ni hacia un workflow.

## Fail-closed / límites

- Una diferencia de versión, nombre, contenido o cardinalidad no se convierte en PASS por contexto de CI.
- Parity nunca aplica DDL, escribe Git ni reconstruye source desde el ledger.
- Un finding reparable no autoriza a Parity a modificar nada.
- La clasificación `EXTERNAL_OWNER_PENDING` pertenece al adapter de pase, no al núcleo. Owner ausente, múltiple, cerrado, ambiguo, de otro repositorio, source no equivalente o evidencia incompleta conserva el `FAIL`.
- No hardcodear PR, SHA, migration version o filename para exceptuar divergencias.

## Validación y readback

- Core: `sandbox/lf_contract_gate_test/migration_source_parity/test_migration_source_parity_core.py`.
- Adapter/compatibilidad: tests existentes de `lf_migration_source_parity.py` y transporte.
- Cambios de contrato deben revalidar Saga y Reconciliation como consumidores.
- El readback final debe comprobar tanto source revision como metadata vigente de `public.lf_activos`.

## No duplicación

No crear un segundo activo ni un segundo comparador de transporte. El core y el adapter son dos superficies de la misma capability: el core contiene el invariante funcional; el adapter aporta contexto del pase. La normalización de transporte se reutiliza desde `migration_transport_normalization.py`.

## Currentness

Este README describe el contrato de responsabilidad. El estado efectivo del activo se consulta en `public.lf_activos`; un workflow verde no sustituye el readback de currentness ni convierte el carrier CI en autoridad funcional.
