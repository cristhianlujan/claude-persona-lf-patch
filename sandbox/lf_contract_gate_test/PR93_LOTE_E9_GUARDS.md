# PR #93 · LOTE-E.9 · Cierre CA-N92 a CA-N94

## Alcance

Este lote endurece únicamente la atomicidad y la correlación de la cadena de evidencia.
No modifica el readback primario de 25 vectores, migraciones, batería adversarial, Edge,
workflows ni código desplegable. No autoriza Supabase, SQL contra el proyecto LF,
claves, baseline o merge.

## Runbook normativo de LOTE-E.9

```sql
begin;
set transaction read only, isolation level repeatable read;
set local search_path = pg_catalog;
-- 1. PR93_LOTE_E8_EXECUTION_CONTEXT_READBACK.sql
-- 2. PR93_LOTE_E6_DEPENDENCY_PREFLIGHT.sql
-- 3. PR93_LOTE_C_EVIDENCE_READBACK.sql
-- 4. PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql
-- 5. PR93_WRITER_V7_ADVERSARIAL_TESTS.sql
rollback;
```

También se admite `SERIALIZABLE`. `READ COMMITTED` y `READ UNCOMMITTED` no constituyen
contexto válido para esta cadena, aunque la transacsión sea read-only.

## CA-N92 · snapshot transaccional estable

Snapshot, preflight y addendum publican `transaction_isolation_valid`.

El valor es `true` únicamente cuando `transaction_isolation` es:

- `repeatable read`; o
- `serializable`.

`context_valid`, `preflight_ready` y `evidence_chain_ready` consumen esta condición.
Por tanto, una captura bajo `READ COMMITTED` falla en el dominio
`EXECUTION_CONTEXT`.

El objetivo es que preflight, readback primario, addendum y batería observen el mismo
snapshot de catálogo y datos durante toda la transacsión.

## CA-N93 · runs push 574 y 582

Los dos fallos históricos ocurrieron después de compactaciones que reemplazaron un
commit técnico intermedio por un commit único no descendiente directo del ref previo.

El workflow usa `fetch-depth: 0`. El validador `scripts/lf_contract_check.py`, para
eventos `push`, calcula las rutas mediante:

```text
git diff --name-only <payload.before> <payload.after>
```

La evidencia disponible permite clasificar el patrón como:

```text
NON_FAST_FORWARD_COMPACTION_DIFF_CONTEXT
```

No se conserva el stderr autenticado de los runs 574 y 582, por lo que no se atribuye
un mensaje de error literal no observado. La relación operacional se sustenta en:

1. ambos fallos siguen una reescritura para compactar commits;
2. el mismo árbol pasa al ejecutarse localmente;
3. los runs `pull_request` del mismo head pasan;
4. los pushes fast-forward de E.6 y E.7 pasan;
5. E.9 se publica mediante un único avance fast-forward, sin commit técnico intermedio.

Antes del gate administrativo, el expediente debe conservar:

- runs 574 y 582 como fallos históricos;
- ausencia de logs por permisos;
- clasificación anterior;
- resultado del `push` de E.9;
- prohibición de presentar solo checks verdes.

## CA-N94 · plantilla obligatoria de correlación

La aceptación no se decide leyendo una pieza aislada. El transcript debe completar
esta plantilla:

```json
{
  "head_sha": "<sha exacto>",
  "transcript_sha256": "<sha256 del transcript íntegro>",
  "snapshot": {
    "backend_pid": 0,
    "transaction_started_at": "<timestamp>",
    "context_valid": true,
    "transaction_isolation_valid": true
  },
  "preflight": {
    "backend_pid": 0,
    "transaction_started_at": "<timestamp>",
    "preflight_ready": true
  },
  "addendum": {
    "backend_pid": 0,
    "transaction_started_at": "<timestamp>",
    "evidence_chain_ready": true,
    "failure_domain": "NONE"
  },
  "correlation": {
    "backend_pid_match": true,
    "transaction_started_at_match": true,
    "ordered_transcript_verified": true,
    "rollback_verified": true,
    "all_match": true
  },
  "evidence_chain_accepted": true
}
```

`evidence_chain_accepted=true` es válido únicamente cuando:

1. los tres `backend_pid` son idénticos;
2. los tres `transaction_started_at` son idénticos;
3. snapshot, preflight y addendum publican sus booleanos obligatorios en `true`;
4. el transcript conserva el orden normativo;
5. existe `ROLLBACK` final;
6. `transcript_sha256` corresponde al transcript completo;
7. el head coincide con el SHA auditado.

Cada SQL sigue siendo SELECT-only y no puede autocorrelacionar resultados de ejecuciones
anteriores sin introducir estado. La plantilla y el transcript son parte obligatoria de
la evidencia, no una revisión opcional.

## Cardinalidad y seguridad

Snapshot, preflight y addendum:

- son una sola sentencia `SELECT`;
- devuelven una fila;
- no contienen DML ni DDL;
- no modifican GUCs;
- funcionan dentro de la transacción read-only;
- califican las validaciones de contexto con `pg_catalog`.

## Evidencia pendiente

1. auditoría estática independiente del head E.9;
2. ejecución del runbook bajo `REPEATABLE READ` y prueba negativa bajo `READ COMMITTED`;
3. revalidación de los 25 vectores;
4. captura correlacionada con la plantilla anterior y `ROLLBACK`;
5. batería adversarial completa;
6. test Edge y comparación Edge/PostgreSQL;
7. controles administrativos previos al merge.
