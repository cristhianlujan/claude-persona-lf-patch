# PR #93 · LOTE-E.8 · Cierre CA-N89 a CA-N91

## Alcance

Este lote no modifica el readback primario de 25 vectores. Se adopta expresamente la
segunda corrección permitida por CA-N89: su salida solo es evidencia válida cuando se
captura junto con el contexto efectivo de ejecución, dentro de la misma transacción
read-only y con `search_path=pg_catalog`. Se añaden autodocumentación y separación
explícita entre fallos de dependencias, contexto e integridad.

No se modifican migraciones, batería adversarial, Edge, workflows ni código
desplegable. No autoriza Supabase, SQL contra el proyecto LF, claves, baseline o merge.

## Runbook normativo de LOTE-E.8

```sql
begin;
set transaction read only;
set local search_path = pg_catalog;
-- 1. PR93_LOTE_E8_EXECUTION_CONTEXT_READBACK.sql
-- 2. PR93_LOTE_E6_DEPENDENCY_PREFLIGHT.sql
-- 3. PR93_LOTE_C_EVIDENCE_READBACK.sql
-- 4. PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql
-- 5. PR93_WRITER_V7_ADVERSARIAL_TESTS.sql
rollback;
```

La captura es válida únicamente si:

1. el snapshot E.8 publica `context_valid=true`;
2. el preflight publica `preflight_ready=true`;
3. el addendum publica `evidence_chain_ready=true`;
4. `backend_pid` y `transaction_started_at` coinciden en snapshot, preflight y addendum;
5. el transcript conserva el orden de ejecución y el `ROLLBACK` final.

Una salida aislada del readback primario, sin estas piezas, es evidencia inválida.

## CA-N89 · readback primario heredado

El archivo `PR93_LOTE_C_EVIDENCE_READBACK.sql` conserva intactos sus 25 vectores y su
semántica ya auditada. No se declara independiente del `search_path`. Su protección es
procedimental y verificable: debe ejecutarse entre dos piezas autocontenidas que
publican el contexto efectivo de la misma transacción.

El criterio de aceptación exige `effective_search_path=pg_catalog`,
`transaction_read_only=on` y coincidencia de `backend_pid` y
`transaction_started_at`. Ejecutarlo fuera del runbook invalida la evidencia aunque su
payload contenga campos favorables.

Esta decisión evita reescribir la batería ya auditada y hace explícita la frontera de
confianza, tal como permitía la corrección mínima de CA-N89.

## CA-N90 · autodocumentación del contexto

El snapshot, preflight y addendum publican:

- `effective_search_path`;
- `transaction_read_only`;
- `transaction_isolation`;
- `server_version_num` y `server_version`;
- `current_user`;
- `backend_pid`;
- `transaction_started_at`.

El contexto se obtiene exclusivamente mediante funciones y operadores de
`pg_catalog`. El snapshot y el addendum no dependen del `search_path` para validar el
propio contexto.

## CA-N91 · separación de dominios de fallo

El addendum conserva `binder_and_trigger_integrity` con su semántica acumulada y añade:

- `integrity_status.contract_dependencies_ready`;
- `integrity_status.execution_context_valid`;
- `integrity_status.core_binder_trigger_integrity`;
- `integrity_status.failure_domain`;
- `evidence_chain_ready`.

`failure_domain` toma uno de cuatro valores:

- `EXECUTION_CONTEXT`;
- `DEPENDENCY`;
- `INTEGRITY`;
- `NONE`.

La ausencia de `extensions.digest` se clasifica como fallo de dependencia del contrato
primario, no como corrupción del binder o del trigger. El booleano normativo para la
captura acumulada pasa a ser `evidence_chain_ready`.

## Cardinalidad y seguridad

Los tres archivos E.8/preexistentes modificados son una sola sentencia `SELECT`,
devuelven una fila, no contienen DML/DDL y son compatibles con una transacción
read-only. Ninguna pieza modifica GUCs; el runbook los fija antes de ejecutar los
readbacks.

## Evidencia pendiente

1. auditoría estática independiente del head E.8;
2. revalidación de los 25 vectores bajo `search_path=pg_catalog` y bajo esquema hostil;
3. ejecución del runbook completo en entorno aislado autorizado;
4. batería adversarial completa terminando en `ROLLBACK`;
5. test Edge y comparación Edge/PostgreSQL;
6. controles administrativos previos al merge.
