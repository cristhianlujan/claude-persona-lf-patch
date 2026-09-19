# MIGRATION_SOURCE_PARITY

Capability transversal LF: `MIGRATION_SOURCE_PARITY` / `TRANSVERSAL_MIGRATION_SOURCE_PARITY`.

## Estado

- Estado operativo esperado: `ACTIVO`
- Inventory status requerido: `ACTIVE_SHARED_ENFORCEMENT`
- Autoridad de currentness: `public.lf_activos`
- README de consumo: `sandbox/lf_contract_gate_test/transversal_assets/migration_source_parity/README.md`

## Propósito

Exigir paridad source-first exacta entre migraciones Git y el ledger Supabase.

## Cuándo consumirlo

En PRs o cierres que tocan o dependen de migraciones gobernadas.

Antes de usarlo, resolver el activo en `public.lf_activos` y confirmar que no esté archivado, que siga `ACTIVO` y que `metadata.transversal_inventory.inventory_status=ACTIVE_SHARED_ENFORCEMENT`.

## Cómo consumirlo

1. Resolver primero `MIGRATION_SOURCE_PARITY` en el inventario transversal; no buscar una implementación nueva antes de revisar este activo.
2. Entrar por `sandbox/lf_contract_gate_test/lf_migration_source_parity.py` o por la superficie canónica equivalente indicada por el contrato vigente.
3. Conservar la identidad de la operación/consumer, source revision y evidencia que exige el contrato de la capability.
4. Si el resultado es `FAIL` o `BLOCKED`, conservar el diagnóstico durable y seguir la ruta de error gobernada aplicable; no crear un writer o store paralelo.
5. Cerrar únicamente con readback desde la superficie canónica y currentness suficiente para la decisión.

## Superficies canónicas

- `sandbox/lf_contract_gate_test/lf_migration_source_parity.py`
- `.github/workflows/lf-contract-check.yml`
- `GITHUB_CONTRACT_GATE_LF`

Las superficies anteriores son referencias de consumo/implementación. Si existe discrepancia entre este README y el contrato/runtime vigente, prevalece la autoridad canónica y el README debe actualizarse.

## Independencia entre owners

Un `remote-only` no se atribuye automáticamente al PR que está siendo validado.

Puede clasificarse como `EXTERNAL_OWNER_PENDING` únicamente cuando la evidencia current demuestra, para la misma identidad `version + name + path`:

- exactamente una ejecución owner `ACTUALIZACION_DB_LF` en estado `IN_PROGRESS`;
- exactamente un PR abierto del mismo repositorio que contiene ese path;
- head SHA válido y distinto del exact-head que está siendo validado;
- source del head owner accesible;
- contenido del source owner equivalente al ledger remoto bajo el comparador de transporte vigente.

Ese `remote-only` queda fuera de la paridad del PR ajeno porque pertenece a otro carril demostrado. No se copia su migration ni se absorbe su owner.

Cuando el owner es ausente, múltiple, cerrado, ambiguo, de otro repositorio, el source no coincide con Supabase o la evidencia de PRs abiertos está incompleta, el resultado sigue siendo `FAIL`.

## Fail-closed / límites

No aplicar DDL remoto para hacer verde el gate ni reconstruir source desde el ledger vivo.

No hardcodear número de PR, migration version, filename, SHA u owner para exceptuar un `remote-only`. La clasificación se resuelve en cada corrida desde ejecución gobernada + PR abierto + source exacto + ledger.

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
