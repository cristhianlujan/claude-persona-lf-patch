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

- exactamente un receipt durable `lf-migration-owner-currentness/v1` en `lf_operation_effect_guard`, emitido por `ACTUALIZACION_DB_LF`;
- el receipt está `SUCCEEDED`, con `write_readback=PASS`, `currentness_result=OWNER_PR_EXACT_OPEN` y `ddl_replayed=false`;
- el PR indicado por el receipt sigue abierto en GitHub y su head SHA sigue siendo exactamente el registrado;
- ese PR contiene exactamente el path esperado con el Git blob registrado;
- el head SHA es distinto del exact-head que está siendo validado;
- source del head owner accesible;
- contenido del source owner equivalente al ledger remoto bajo el comparador de transporte vigente.

La búsqueda de ownership es dirigida por esos receipts; no se enumeran todos los PRs abiertos del repositorio.

Ese `remote-only` queda fuera de la paridad del PR ajeno porque pertenece a otro carril demostrado. No se copia su migration ni se absorbe su owner.

Cuando el owner es ausente, múltiple, cerrado, ambiguo, de otro repositorio, el source no coincide con Supabase o la evidencia de PRs abiertos está incompleta, el resultado sigue siendo `FAIL`.

## Recuperación forense de source huérfano

El carril normal sigue siendo `source-first` y un `remote-only` sin owner continúa bloqueando.

Solo cuando una búsqueda exhaustiva demuestra que el source original no existe en `main`, ramas remotas, refs de PR, commits recuperables ni artefactos privados, puede abrirse `FORENSIC_RECOVERY_OWNER`. Este modo no declara que el archivo recuperado sea el source original: materializa un mirror forense explícito para restaurar trazabilidad y source parity sin reejecutar DDL.

Requiere simultáneamente:

- receipt durable `lf-migration-source-recovery-currentness/v1` bajo `ACTUALIZACION_DB_LF`;
- `ownership_mode=FORENSIC_RECOVERY_OWNER` y `currentness_result=FORENSIC_RECOVERY_PR_EXACT_OPEN`;
- búsqueda original completa y negativa con `source_search_evidence_ref`;
- EKB del gap de procedencia mediante `provenance_gap_ekb_code`;
- `ddl_replayed=false`;
- PR recovery abierto, head exacto y blob exacto;
- ledger con exactamente un statement y comparación `DIRECT_SOURCE`;
- `source_recovery_basis=SINGLE_STATEMENT_SOURCE_PRESERVING_LEDGER_MIRROR`;
- `source_materialization_mode=FORENSIC_LEDGER_MIRROR_NOT_ORIGINAL_SOURCE`.

Cualquier migration multi-statement, representación transformada, source original encontrado, evidencia incompleta, receipt stale, PR cerrado, blob distinto o intento de replay sigue fallando.

## Fail-closed / límites

No aplicar DDL remoto para hacer verde el gate. No reconstruir source desde el ledger vivo fuera del carril forense gobernado anterior, y nunca presentar un mirror forense como source original.

No hardcodear número de PR, migration version, filename, SHA u owner para exceptuar un `remote-only`. La clasificación se resuelve en cada corrida desde ejecución gobernada + PR abierto + source exacto/forense explícito + ledger.

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
