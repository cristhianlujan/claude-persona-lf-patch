# PR #93 · LOTE-E.9 · Cierre CA-N92 a CA-N94

## Estado de este documento

El runbook monolítico publicado originalmente en LOTE-E.9 queda **sustituido** por
LOTE-E.10. No debe ejecutarse la batería adversarial dentro de la transacción read-only
de la cadena de evidencia.

La autoridad operativa vigente es:

- `PR93_LOTE_E10_RUNBOOK.psql`;
- `PR93_LOTE_E10_CORRELATION_READBACK.sql`;
- `PR93_LOTE_E10_GUARDS.md`.

Las condiciones de aislamiento introducidas por E.9 permanecen vigentes.

## Alcance

Este lote endurece la atomicidad y la correlación de la cadena de evidencia. No modifica
el readback primario de 25 vectores, migraciones, Edge ni código desplegable. No
autoriza Supabase, SQL contra el proyecto LF, claves, baseline o merge.

## Runbook normativo corregido

### T1 · cadena de evidencia atómica

```sql
begin;
set transaction read only, isolation level repeatable read;
set local search_path = pg_catalog;
-- correlation probe 1
-- snapshot
-- correlation probe 2
-- preflight
-- readback primario
-- correlation probe 3
-- addendum final
rollback;
```

También se admite `SERIALIZABLE`. `READ COMMITTED` y `READ UNCOMMITTED` no constituyen
contexto válido, aunque la transacción sea read-only.

### T2 · batería adversarial

La batería se ejecuta después de cerrar T1:

```text
PR93_WRITER_V7_ADVERSARIAL_TESTS.sql
```

La batería conserva su propia transacción read-write y su propio `ROLLBACK`. No forma
parte de la correlación PID/timestamp de T1.

## CA-N92 · snapshot transaccional estable

Snapshot, preflight y addendum publican `transaction_isolation_valid`.

El valor es `true` únicamente cuando `transaction_isolation` es:

- `repeatable read`; o
- `serializable`.

`context_valid`, `preflight_ready` y `evidence_chain_ready` consumen esta condición.
Una captura bajo `READ COMMITTED` falla en `EXECUTION_CONTEXT`.

El objetivo es que snapshot, preflight, readback primario y addendum observen el mismo
snapshot durante T1.

## CA-N93 · runs push 574 y 582

Sin los logs autenticados no se atribuye una causa literal definitiva.

Deben distinguirse dos modos:

```text
NON_FAST_FORWARD_BEFORE_UNREACHABLE
```

El `payload.before` no está disponible en el checkout y `git diff before after` termina
con `bad object` o una excepción equivalente.

```text
COMPACTION_DIFF_SCOPE_OVERREACH
```

Ambos commits existen, pero el rango calculado incluye rutas ajenas al lote y el
validador emite un código `FAIL_*` gobernado.

Los runs 574 y 582 permanecen históricos y no se asignan definitivamente a uno de esos
modos sin log. La clasificación anterior
`NON_FAST_FORWARD_COMPACTION_DIFF_CONTEXT` queda reemplazada por esta separación.

CA-N93 no se cierra hasta inventariar los runs `push` reales o registrar formalmente la
indisponibilidad de esa evidencia en el gate administrativo.

## CA-N94 · correlación obligatoria

LOTE-E.10 añade tres sondas de correlación dentro de T1. La aceptación exige igualdad
de:

- `runtime_cluster_fingerprint`;
- `transaction_correlation_id`;
- `backend_pid`;
- `transaction_started_at`.

`transaction_started_at` se compara después de parsear cada valor como PostgreSQL
`timestamptz`; no se permite una comparación textual dependiente del formato JSON.

El transcript debe conservar el orden de T1 y su `ROLLBACK`. T2 tiene transcript y
resultado propios.

## Cardinalidad y seguridad

Snapshot, preflight, addendum y sonda E.10:

- son una sola sentencia `SELECT`;
- devuelven una fila;
- no contienen DML ni DDL;
- no modifican GUCs;
- funcionan dentro de T1;
- califican controles sensibles mediante `pg_catalog`.

## Evidencia pendiente

1. auditoría estática independiente del head E.10;
2. ejecución de T1 bajo `REPEATABLE READ` y prueba negativa bajo `READ COMMITTED`;
3. revalidación de los 25 vectores;
4. captura correlacionada de T1 con `ROLLBACK`;
5. ejecución separada de T2;
6. inventario autenticado de checks `push`;
7. corrección separada de `scripts/lf_contract_check.py`;
8. test Edge y controles administrativos previos al merge.
