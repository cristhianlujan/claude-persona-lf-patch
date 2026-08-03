# PR #93 · LOTE-E.10 · Cierre CA-N95, CA-N97, CA-N98 y CA-N99

## Alcance

LOTE-E.10 corrige el runbook operativo y la semántica de correlación. No modifica el
readback primario de 25 vectores, las migraciones, la batería adversarial, Edge,
workflows ni código desplegable.

CA-N93 permanece abierto hasta inventariar checks `push`. CA-N96 permanece fuera de
este lote porque requiere modificar `scripts/lf_contract_check.py`.

## CA-N95 · separación obligatoria T1/T2

El archivo normativo ejecutable es:

`PR93_LOTE_E10_RUNBOOK.psql`

### T1 · evidencia atómica y read-only

T1 contiene exclusivamente:

1. sonda de correlación anterior al snapshot;
2. snapshot de contexto;
3. sonda anterior al preflight;
4. preflight;
5. readback primario de 25 vectores;
6. sonda anterior al addendum;
7. addendum final;
8. `ROLLBACK`.

T1 usa:

```sql
begin;
set transaction read only, isolation level repeatable read;
set local search_path = pg_catalog;
```

`SERIALIZABLE` también es válido cuando se ejecuta manualmente.

### T2 · batería adversarial read-write

T2 comienza únicamente después de `E10_T1_ROLLBACK_COMPLETE`.

`PR93_WRITER_V7_ADVERSARIAL_TESTS.sql` conserva su `BEGIN/ROLLBACK` propio. No puede
incluirse dentro de T1 y no participa de la correlación transaccional de T1.

La evidencia debe publicar por separado:

- `t1_transcript_sha256`;
- `t1_rollback_verified`;
- `t2_transcript_sha256`;
- `t2_internal_rollback_verified`;
- resultado de bloques adversariales.

## CA-N97 · clasificación de fallos push

Se eliminan clasificaciones ambiguas. Los únicos rótulos permitidos son:

- `NON_FAST_FORWARD_BEFORE_UNREACHABLE`: el objeto `payload.before` no está disponible
  y `git diff` no puede construir el rango;
- `COMPACTION_DIFF_SCOPE_OVERREACH`: ambos objetos existen, pero el rango contiene
  rutas fuera del alcance permitido;
- `PUSH_FAILURE_UNCLASSIFIED_NO_LOG`: no existe log suficiente para discriminar.

Los runs 574 y 582 deben permanecer como
`PUSH_FAILURE_UNCLASSIFIED_NO_LOG` hasta obtener evidencia autenticada.

## CA-N98 · semántica de comparación y clúster

`PR93_LOTE_E10_CORRELATION_READBACK.sql` publica:

- `system_identifier`, cuando `pg_control_system()` está disponible y autorizado;
- `runtime_cluster_fingerprint`;
- `database_name` y `database_oid`;
- `postmaster_started_at`;
- dirección y puerto del servidor cuando existen;
- `backend_pid`;
- `transaction_started_at`;
- `transaction_correlation_id`;
- contexto de search path, read-only y aislamiento.

La sonda se ejecuta tres veces dentro de T1.

### Comparaciones normativas

La plantilla de evidencia debe interpretar:

- `transaction_started_at` y `postmaster_started_at` como `timestamptz`;
- `backend_pid` como entero;
- fingerprints e identificadores como hexadecimal exacto;
- valores `null` como distintos de cualquier valor no nulo.

Se exige:

```json
{
  "correlation": {
    "runtime_cluster_fingerprint_match": true,
    "transaction_correlation_id_match": true,
    "backend_pid_match": true,
    "transaction_started_at_timestamptz_match": true,
    "ordered_t1_transcript_verified": true,
    "t1_rollback_verified": true,
    "all_match": true
  }
}
```

`all_match=true` requiere las seis condiciones anteriores.

Cuando `system_identifier_available=true`, los tres `system_identifier` deben ser
idénticos. Cuando sea `false`, la evidencia debe declarar
`cluster_identity_strength=RUNTIME_FINGERPRINT` y conservar los componentes usados en
el fingerprint.

No se acepta mezclar resultados de clústeres, sesiones o transacciones diferentes.

## CA-N99 · corrección editorial

La forma normativa es `transacción`. La grafía histórica `transacsión` queda corregida
y no debe reutilizarse.

## Contrato de aceptación de E.10

La cadena se acepta únicamente cuando:

1. el head SHA coincide con el auditado;
2. T1 fue ejecutada mediante el runbook E.10 o secuencia equivalente;
3. las tres sondas publican `context_valid=true`;
4. las tres sondas pertenecen al mismo clúster, backend y transacción;
5. snapshot, preflight y addendum publican sus booleanos obligatorios;
6. el readback primario conserva 25/25;
7. T1 termina en `ROLLBACK`;
8. T2 comienza después del cierre de T1;
9. T2 termina en su `ROLLBACK` interno;
10. se conservan hashes separados de los transcripts T1 y T2.

## Checks y CA-N93

No presentar solo checks `pull_request`. El expediente debe incluir todos los runs
`push` y `pull_request` del head.

Si los runs `push` no pueden leerse, CA-N93 continúa abierto y el gate administrativo
permanece bloqueado.

## CA-N96 · lote separado

La reparación de `scripts/lf_contract_check.py` debe:

1. comprobar la alcanzabilidad de `payload.before`;
2. capturar `CalledProcessError`;
3. emitir un código gobernado y explicable;
4. usar una base segura cuando el commit anterior sea inalcanzable;
5. incluir pruebas para fast-forward, force-push y creación de rama.

No se modifica el script en E.10.

## Prohibiciones

- No ejecutar T2 dentro de T1.
- No aceptar una captura bajo `READ COMMITTED`.
- No comparar timestamps como strings.
- No aceptar piezas sin fingerprint de clúster y correlación transaccional.
- No declarar CA-N93 cerrado sin inventario de checks.
- No declarar runtime PASS, merge autorizado o producción.
