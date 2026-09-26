# MIGRATION_SOURCE_RECONCILIATION_V1

## Objetivo

Reconciliar únicamente una divergencia Git ↔ Supabase que `MIGRATION_SOURCE_PARITY` haya identificado canónicamente como fuente remota faltante en Git, recuperando y persistiendo los bytes exactos sin reejecutar DDL ni mutar el migration ledger.

## Entrada canónica

El reconciliador consume una evidencia `LF_GATE_ERROR_V1` producida por `LF_GATE_CHECK_OBSERVABILITY_V1` para el control `MIGRATION_SOURCE_PARITY`.

No depende de `lf-contract-check` ni de ningún workflow/carrier específico. El carrier puede cambiar; la evidencia del control es la interfaz.

La evidencia debe estar ligada al mismo exact-head y a un único check canónico de `sandbox/lf_contract_gate_test/lf_migration_source_parity.py`.

## Aplicabilidad

Único caso reparable en V1:

- `FAIL_LF_MIGRATION_VERSION_PARITY`;
- exactamente una versión `remote_only`;
- cero versiones `local_only`.

No son responsabilidad de este proceso:

- `FAIL_UNCLASSIFIED_POST_CUTOVER_MIGRATION` y otros fallos de clasificación/ownership;
- múltiples versiones remotas en un solo intento;
- divergencias no respaldadas por evidencia canónica;
- reparaciones DDL o mutaciones del ledger.

Esos casos quedan `NOT_APPLICABLE` o bloqueados para su owner correspondiente.

## Dependencias obligatorias

1. `MIGRATION_SOURCE_PARITY` como detector/verificador canónico del finding reparable.
2. `MIGRATION_WRITE_AHEAD_V1` para persistir el source recuperado.

`MIGRATION_ORCHESTRATED_SAGA_V1` no es dependencia interna del reconciliador: es una capacidad relacionada del cierre posterior del pedido una vez que la reparación vuelve al flujo normal.

## Flujo propio

1. Validar la evidencia canónica de `MIGRATION_SOURCE_PARITY` y su digest/head.
2. Extraer la única versión `remote_only` del finding exacto; no escanear timestamps globales del artifact.
3. Usar receipts históricos solo como locators, nunca como autoridad vigente.
4. Releer `source_sha + source_blob + path` exactos desde Git.
5. Revalidar los bytes contra el ledger vivo con el comparador transport-aware existente.
6. Persistir el source mediante `MIGRATION_WRITE_AHEAD_V1` en `lf/migration-source-repair/*`.
7. Emitir un resultado `SOURCE_REPAIR_PERSISTED` con `pr_request` y requisitos posteriores.
8. Terminar.

## Salida

El resultado contiene, como mínimo:

- `parity_failure_head` y `parity_evidence_sha256`;
- version/name;
- branch y `persisted_head_sha`;
- source blob/hash y representación validada;
- `ddl_replayed=false`;
- `ledger_mutated=false`;
- `pr_request` para que el pedido/orquestación superior cree el PR draft;
- requisitos posteriores: evidencia canónica `MIGRATION_SOURCE_PARITY=PASS` y `MIGRATION_ORCHESTRATED_SAGA_V1=CONSISTENT`.

El reconciliador no ejecuta esas acciones posteriores.

## Invariantes

- una sola identidad/version por reparación;
- `ddl_replayed=false`;
- `ledger_mutated=false`;
- no direct-main write;
- no merge;
- no apertura directa de PR;
- locator ambiguo o source mismatch = bloqueo;
- ningún segundo motor de parity ni writer paralelo;
- no PASS fabricado para Saga;
- no dependencia funcional de S30, E.16, `Validate LF Packs`, `LF DB Regression` ni `lf-contract-check`.

## Implementación

- Coordinator: `lf_migration_source_parity_repair.py`.
- Tests propios: `test_lf_migration_source_parity_repair.py`.
- Persistencia Git reutilizada: `MIGRATION_WRITE_AHEAD_V1` / `lf_migration_git_persist.py`.

No existe workflow propio de Reconciliation: la admisión, creación de PR y controles de pase pertenecen al pedido y a las capacidades transversales correspondientes.

## Relaciones canónicas

- `DEPENDE_DE -> MIGRATION_SOURCE_PARITY`.
- `DEPENDE_DE -> MIGRATION_WRITE_AHEAD_V1`.
- `GOBERNADO_POR -> ACT-0001`.
- `RELACIONADO_CAPACIDADES -> MIGRATION_ORCHESTRATED_SAGA_V1` únicamente porque Saga forma parte del cierre posterior del pedido; Reconciliation no la invoca.

No existe dependencia funcional hacia S30, E.16 ni carriers CI.

## Activación

Candidato únicamente mientras el PR no esté integrado a `main`. El merge documental/código no implica activación de runtime ni producción.
