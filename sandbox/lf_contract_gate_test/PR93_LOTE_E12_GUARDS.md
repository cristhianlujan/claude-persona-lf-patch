# PR #93 · LOTE-E.12 · Cierre CA-N107, CA-N108 y CA-N109

## Alcance

LOTE-E.12 corrige el código de salida del runbook, vincula la sonda opcional de
`system_identifier` con la correlación obligatoria de T1 y completa la cobertura de
hashes del transcript.

No modifica:

- el readback primario de 25 vectores;
- la batería adversarial;
- migraciones;
- Edge;
- workflows;
- `scripts/lf_contract_check.py`;
- código desplegable.

Permanecen abiertos CA-N93, CA-N96, CA-N102 y CA-N103.

## CA-N107 · ausencia de head debe fallar

`PR93_LOTE_E10_RUNBOOK.psql` conserva el nombre histórico, pero su contenido normativo
es E.12.

La comprobación de `E11_HEAD_SHA` usa una excepción SQL antes de `BEGIN`:

```sql
\if :{?E11_HEAD_SHA}
\else
\echo 'E11_HEAD_SHA_REQUIRED'
do $e12_head_guard$
begin
  raise exception 'E11_HEAD_SHA_REQUIRED';
end
$e12_head_guard$;
\endif
```

Con `\set ON_ERROR_STOP on`:

1. se publica `E11_HEAD_SHA_REQUIRED`;
2. no se ejecuta `E11_T1_BEGIN`;
3. no se ejecuta ningún `BEGIN`;
4. `psql` termina con código distinto de cero;
5. la ausencia del head no puede registrarse como éxito.

No se usa `\quit` con argumentos.

## CA-N108 · vínculo de identidad fuerte

La sonda obligatoria continúa sin invocar `pg_control_system()` y funciona con roles
sin privilegios administrativos.

La sonda opcional `PR93_LOTE_E11_SYSTEM_IDENTIFIER_PROBE.sql` se ejecuta únicamente
cuando el capability check publica `true`.

La sonda opcional publica:

- `system_identifier`;
- `cluster_identity_strength=SYSTEM_IDENTIFIER`;
- `runtime_cluster_fingerprint`, calculado con la misma fórmula de la sonda obligatoria;
- `transaction_correlation_id`, calculado con la misma fórmula obligatoria;
- `system_identifier_binding`;
- `backend_pid`;
- `transaction_started_at`;
- componentes de clúster y contexto.

`system_identifier_binding` es:

```text
sha256(
  system_identifier
  || '|'
  || runtime_cluster_fingerprint
  || '|'
  || backend_pid
  || '|'
  || transaction_started_at
)
```

Cuando `optional_system_identifier_probe_required=true`, la plantilla de evidencia
debe registrar:

```json
{
  "optional_system_identifier": "<valor>",
  "optional_system_identifier_binding": "<sha256>",
  "optional_probe_runtime_cluster_fingerprint_match": true,
  "optional_probe_transaction_correlation_id_match": true,
  "optional_probe_backend_pid_match": true,
  "optional_probe_transaction_started_at_timestamptz_match": true
}
```

La identidad fuerte solo se acepta cuando las cuatro comparaciones son verdaderas.
La sonda opcional no reemplaza las tres sondas obligatorias ni la correlación de T1.

Cuando el capability check es falso:

- la sonda opcional no se ejecuta;
- `system_identifier` permanece `null` en la ruta obligatoria;
- `cluster_identity_strength=RUNTIME_FINGERPRINT`;
- T1 continúa.

## CA-N109 · cobertura completa del transcript

El runbook publica:

- `E12_FULL_TRANSCRIPT_BEGIN` antes de validar el head;
- `E12_FULL_TRANSCRIPT_END` después de completar T2.

La captura normativa es:

```bash
HEAD_SHA="$(git rev-parse HEAD)"

psql "$DATABASE_URL" \
  -v E11_HEAD_SHA="$HEAD_SHA" \
  -f PR93_LOTE_E10_RUNBOOK.psql \
  > PR93_E12_FULL_TRANSCRIPT.log 2>&1
```

Se generan tres segmentos:

```bash
awk '
  /E11_T1_BEGIN/ {exit}
  {print}
' PR93_E12_FULL_TRANSCRIPT.log \
  > PR93_E12_PREAMBLE_TRANSCRIPT.log

awk '
  /E11_T1_BEGIN/ {capture=1}
  capture {print}
  /E11_T1_ROLLBACK_COMPLETE/ {capture=0}
' PR93_E12_FULL_TRANSCRIPT.log \
  > PR93_E12_T1_TRANSCRIPT.log

awk '
  /E11_T2_ADVERSARIAL_BATTERY_BEGIN/ {capture=1}
  capture {print}
' PR93_E12_FULL_TRANSCRIPT.log \
  > PR93_E12_T2_TRANSCRIPT.log
```

Se calculan cuatro hashes:

```bash
sha256sum \
  PR93_E12_FULL_TRANSCRIPT.log \
  PR93_E12_PREAMBLE_TRANSCRIPT.log \
  PR93_E12_T1_TRANSCRIPT.log \
  PR93_E12_T2_TRANSCRIPT.log
```

La cobertura de líneas se verifica con:

```bash
full_lines="$(wc -l < PR93_E12_FULL_TRANSCRIPT.log)"
preamble_lines="$(wc -l < PR93_E12_PREAMBLE_TRANSCRIPT.log)"
t1_lines="$(wc -l < PR93_E12_T1_TRANSCRIPT.log)"
t2_lines="$(wc -l < PR93_E12_T2_TRANSCRIPT.log)"

test "$full_lines" -eq "$((preamble_lines + t1_lines + t2_lines))"
```

La aceptación exige:

```json
{
  "full_transcript_sha256": "<sha256>",
  "preamble_transcript_sha256": "<sha256>",
  "t1_transcript_sha256": "<sha256>",
  "t2_transcript_sha256": "<sha256>",
  "transcript_line_coverage_complete": true,
  "full_transcript_begin_verified": true,
  "full_transcript_end_verified": true
}
```

Reglas:

1. el transcript completo incluye toda salida anterior a T1;
2. T1 incluye desde `E11_T1_BEGIN` hasta `E11_T1_ROLLBACK_COMPLETE`;
3. T2 incluye desde `E11_T2_ADVERSARIAL_BATTERY_BEGIN` hasta EOF;
4. la suma de líneas de los tres segmentos debe ser igual al total;
5. cualquier línea sin asignar invalida la evidencia;
6. el hash completo es obligatorio aunque T1 y T2 tengan hashes propios;
7. una corrida sin `E12_FULL_TRANSCRIPT_END` no puede declararse completa;
8. si T2 aborta, se conserva el transcript completo y se aplica CA-N102:
   `EXPLICIT`, `IMPLICIT_ON_DISCONNECT` o `NOT_VERIFIED`.

## Estado de T2

LOTE-E.12 no modifica la batería adversarial.

Por tanto:

- CA-N102 permanece abierto;
- CA-N103 permanece abierto;
- no se declara rollback explícito si no aparece literalmente;
- no existe todavía una aserción estructural propia en la batería que prohíba
  ejecutarla dentro de T1.

## Checks y CA-N93

Los checks `pull_request` no sustituyen el inventario completo de runs.

CA-N93 permanece abierto mientras no se inventaríen los eventos `push` asociados al
head y a sus commits.

## CA-N96

La reparación de `scripts/lf_contract_check.py` continúa en un lote separado y debe
cubrir:

1. `payload.before` alcanzable;
2. `payload.before` inalcanzable;
3. creación de rama;
4. fast-forward;
5. force-push;
6. error gobernado y explicable.

## Cardinalidad y seguridad

La sonda opcional:

- es una sola sentencia `SELECT`;
- devuelve una fila cuando el capability check es verdadero;
- no contiene DML ni DDL;
- no modifica GUCs;
- funciona dentro de T1 read-only;
- califica funciones, tipos, catálogos y operadores con `pg_catalog`.

## Prohibiciones

- No ejecutar la sonda opcional cuando el capability check sea falso.
- No aceptar identidad fuerte sin comparar fingerprint, correlación, PID y timestamp.
- No aceptar una corrida sin hash del transcript completo.
- No aceptar cobertura de líneas incompleta.
- No declarar CA-N93, CA-N96, CA-N102 o CA-N103 cerrados.
- No declarar runtime PASS, merge autorizado o producción.
