# PR #93 · LOTE-E.14 · Controles normativos

## Entry points

Solo se aceptan:

1. `PR93_LOTE_E14_CAPTURE.py`
2. `PR93_LOTE_E14_VERIFY.py` con SHA-256 del recibo anclado fuera del bundle
3. `PR93_LOTE_E14_NEGATIVE_TESTS.py`

Los seis entry points Python E.13/E.13.1 y el runbook E.10 son stubs fail-closed que deben terminar con código no cero y dirigir a E.14.

## CA-N116 · conexión

`DATABASE_URL` se entrega a libpq únicamente mediante `psql --dbname <URI>` y nunca mediante `PGDATABASE`. Antes de crear el directorio de salida se ejecuta `select 1` con salida exacta `1`. El fallo de conectividad devuelve código 21, no crea bundle ni recibo y no imprime la URI.

## CA-N117 y CA-N122 · creación exclusiva

El capturador rechaza un output existente antes de conectar. Tras el preflight crea el directorio una sola vez. Cada evidencia, recibo y sidecar se escribe con creación exclusiva. El recibo canónico se ensambla en memoria y se escribe exactamente una vez. No se reutiliza ni reescribe evidencia previa.

## CA-N118 y CA-N123 · matriz negativa

El runner autoritativo usa `sys.executable`, captura toda salida auxiliar y localiza el JSON del preflight buscando exactamente un objeto JSON dentro del segmento delimitado.

Actualizado por LOTE-E.15 (CA-N125 y CA-N126): el contador E.13 queda retirado
porque E.14 no ejecuta esa matriz, y el contador E.14 se deriva de los casos
realmente ejecutados contra el verificador en subproceso. Al cierre emite:

```text
E13_NEGATIVE_MATRIX=NOT_EXECUTED_BY_E14
PASS_E14_NEGATIVE_MATRIX=<rechazados>/<ejecutados>
```

Ver `PR93_LOTE_E15_GUARDS.md`. Los casos de marcadores rechazan heads cruzados entre T1, T2 y el sobre.

## CA-N119 · material de clave

El readback sigue siendo una sola sentencia SELECT-only. Antes de calcular el digest del rowset de claves sustituye `key_material` por:

- `key_material_sha256`
- `key_material_is_null`

Nunca publica material secreto ni hashes individuales; solo el digest final del rowset. Todo cambio de material, incluso con igual cardinalidad, debe cambiar el digest. `state_strength` debe ser `ROWSET_SHA256_WITH_KEY_MATERIAL_DIGEST`.

## CA-N120, CA-N121 y CA-N124

El runbook E.10 nombra `PR93_LOTE_E14_CAPTURE.py`. Todos los módulos aceptados y stubs fijan `sys.dont_write_bytecode = True`. T1 rechaza marcadores `E13_T2_HEAD_SHA=` o `E14_HEAD_SHA=`; T2 rechaza marcadores `E13_T1_HEAD_SHA=` o `E14_HEAD_SHA=`.

## Aceptación

El capturador y el verificador recalculan independientemente la semántica T1: contexto, correlación, preflight, exactamente 25 vectores PASS, binder, trigger, addendum y `failure_domain=NONE`.

T2 se ejecuta en proceso separado mediante su wrapper. El rollback es:

- `EXPLICIT`: exit 0, un `ROLLBACK` literal y estado exacto
- `IMPLICIT_ON_DISCONNECT`: exit no cero, cero rollback literal y estado exacto
- `NOT_VERIFIED`: lectura fallida, estado distinto o marcadores ambiguos

El resultado global PASS exige T1 PASS, T2 PASS y `EXPLICIT`.

El recibo vincula head, blobs y SHA-256 de fuentes, hashes de evidencias, preflight de conexión, semántica T1, estado T2 y readbacks. El sidecar local es informativo; el verificador exige el digest recibido desde un ancla externa.

## Fuera de alcance

Permanecen abiertos CA-N93 y CA-N96, runtime sobre baseline LF autorizado, comparación Edge/PostgreSQL, ruleset, revisor independiente, controles administrativos y limpieza de refs temporales. Este lote no autoriza merge, despliegue ni runtime PASS.
