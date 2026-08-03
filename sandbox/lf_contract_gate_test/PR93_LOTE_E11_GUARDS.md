# PR #93 · LOTE-E.11 · Cierre CA-N101, CA-N104, CA-N105 y CA-N106

## Alcance

LOTE-E.11 corrige el único defecto bloqueante de E.10 y normaliza la captura de
transcripts. No modifica el readback primario de 25 vectores, la batería adversarial,
migraciones, Edge, workflows, `scripts/lf_contract_check.py` ni código desplegable.

Permanecen abiertos:

- CA-N93: inventario autenticado de checks `push`;
- CA-N96: manejo explicable de `payload.before` inalcanzable;
- CA-N102: semántica de rollback cuando T2 aborta;
- CA-N103: guarda estructural dentro de la batería adversarial.

## CA-N101 · degradación segura sin privilegio

`PR93_LOTE_E10_CORRELATION_READBACK.sql` conserva su nombre histórico, pero su
contenido normativo es E.11.

La sonda obligatoria:

1. no contiene ninguna llamada a `pg_catalog.pg_control_system()`;
2. calcula de forma segura `system_identifier_available` mediante
   `pg_catalog.has_function_privilege`;
3. publica siempre `system_identifier=null`;
4. publica `cluster_identity_strength=RUNTIME_FINGERPRINT`;
5. devuelve una fila aun cuando el rol no tenga privilegios administrativos;
6. conserva fingerprint, PID, timestamp y contexto transaccional.

El fingerprint degradado usa:

- nombre y OID de base;
- versión del servidor;
- inicio del postmaster;
- dirección y puerto, o el marcador `UNIX_SOCKET`.

No se presenta como identidad criptográfica permanente del clúster.

### Sonda opcional

`PR93_LOTE_E11_SYSTEM_IDENTIFIER_PROBE.sql` contiene la única referencia E.11 a
`pg_catalog.pg_control_system()`.

Solo puede ejecutarse cuando el capability check del runbook devuelve `true`.
Cuando se ejecuta satisfactoriamente, permite elevar la evidencia a:

`cluster_identity_strength=SYSTEM_IDENTIFIER`.

Cuando el check devuelve `false`, el runbook publica el marcador:

`E11_T1_OPTIONAL_SYSTEM_IDENTIFIER_SKIPPED_NO_PRIVILEGE`

y continúa con la cadena obligatoria.

## Runbook normativo E.11

Archivo:

`PR93_LOTE_E10_RUNBOOK.psql`

El nombre se conserva por trazabilidad, pero E.11 reemplaza su contenido.

Invocación obligatoria desde la carpeta de los artefactos:

```bash
HEAD_SHA="$(git rev-parse HEAD)"
psql "$DATABASE_URL" \
  -v E11_HEAD_SHA="$HEAD_SHA" \
  -f PR93_LOTE_E10_RUNBOOK.psql \
  2>&1 | tee PR93_E11_FULL_TRANSCRIPT.log
```

El runbook aborta antes de ejecutar SQL cuando falta `E11_HEAD_SHA` y publica:

`E11_HEAD_SHA=<sha>`

T1 continúa bajo `REPEATABLE READ`, read-only y `search_path=pg_catalog`, termina en
`ROLLBACK` y solo entonces comienza T2.

## CA-N104 · separación y hash de transcripts

El transcript completo debe dividirse mediante los marcadores normativos:

```bash
awk '
  /E11_T1_BEGIN/ {capture=1}
  capture {print}
  /E11_T1_ROLLBACK_COMPLETE/ {capture=0}
' PR93_E11_FULL_TRANSCRIPT.log > PR93_E11_T1_TRANSCRIPT.log

awk '
  /E11_T2_ADVERSARIAL_BATTERY_BEGIN/ {capture=1}
  capture {print}
' PR93_E11_FULL_TRANSCRIPT.log > PR93_E11_T2_TRANSCRIPT.log

sha256sum \
  PR93_E11_T1_TRANSCRIPT.log \
  PR93_E11_T2_TRANSCRIPT.log
```

La plantilla de evidencia debe registrar:

```json
{
  "head_sha": "<sha publicado por el runbook>",
  "t1_transcript_sha256": "<sha256>",
  "t2_transcript_sha256": "<sha256>",
  "t1_rollback_status": "EXPLICIT",
  "t2_rollback_status": "EXPLICIT|IMPLICIT_ON_DISCONNECT|NOT_VERIFIED"
}
```

Reglas:

1. `head_sha` debe coincidir con el commit auditado;
2. `t1_rollback_status=EXPLICIT` requiere el marcador
   `E11_T1_ROLLBACK_COMPLETE`;
3. `t2_rollback_status=EXPLICIT` requiere evidencia literal del `ROLLBACK` interno;
4. si T2 aborta antes de su rollback, no se permite declarar `EXPLICIT`;
5. `IMPLICIT_ON_DISCONNECT` exige readback de no persistencia en una sesión nueva;
6. `NOT_VERIFIED` bloquea la aceptación de T2.

CA-N102 no se declara cerrado: E.11 únicamente normaliza cómo reportar sus estados.

## Correlación normativa de T1

Las tres sondas obligatorias deben coincidir en:

- `runtime_cluster_fingerprint`;
- `transaction_correlation_id`;
- `backend_pid`;
- `transaction_started_at`, comparado como `timestamptz`;
- `postmaster_started_at`, comparado como `timestamptz`;
- `database_name` y `database_oid`.

Cuando la sonda opcional se ejecuta, su `system_identifier` debe conservarse como
evidencia adicional; no reemplaza la correlación transaccional obligatoria.

## CA-N105 · fuerza del fingerprint degradado

`RUNTIME_FINGERPRINT` es una identidad operacional de la instancia observada, no un
identificador permanente:

- sobre socket Unix, dirección y puerto pueden ser `null`;
- un reinicio cambia `postmaster_started_at` y por tanto cambia el fingerprint;
- no se comparan capturas separadas por un reinicio como si pertenecieran a la misma
  instancia;
- cuando existe permiso, la sonda opcional aporta identidad fuerte adicional.

## CA-N106 · normalización editorial

Las guardas vigentes no reproducen literalmente la grafía histórica incorrecta.
Los controles de texto deben buscar únicamente la forma normativa `transacción`.

## Checks y bloqueos

Los checks `pull_request` no sustituyen el inventario completo. CA-N93 permanece
abierto mientras no se puedan leer y conservar también los runs `push`.

Antes del merge siguen pendientes:

1. auditoría estática independiente de E.11;
2. ejecución T1/T2 en entorno real aislado;
3. cierre de CA-N93, CA-N96, CA-N102 y CA-N103;
4. prueba Edge/PostgreSQL;
5. ruleset nativo, revisor independiente y controles administrativos;
6. eliminación de la rama auxiliar `tmp-e10-ignore`.

## Prohibiciones

- No ejecutar la sonda opcional cuando el capability check sea falso.
- No afirmar que `RUNTIME_FINGERPRINT` es identidad permanente.
- No declarar rollback explícito de T2 sin verlo en el transcript.
- No presentar solo checks verdes.
- No declarar runtime PASS, merge autorizado o producción.
