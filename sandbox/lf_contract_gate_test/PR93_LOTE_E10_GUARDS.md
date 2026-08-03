# PR #93 · LOTE-E.10 · Cierre CA-N95, CA-N97, CA-N98 y CA-N99

## Alcance

LOTE-E.10 corrige el runbook operativo y la semántica de correlación. No modifica el
readback primario de 25 vectores, las migraciones, la batería adversarial, Edge,
workflows ni código desplegable.

CA-N93 permanece abierto hasta inventariar checks `push`. CA-N96 permanece fuera de
este lote porque requiere modificar `scripts/lf_contract_check.py`.

## CA-N95 · separación obligatoria T1/T2

El archivo normativo ejecutable de E.10 fue:

`PR93_LOTE_E10_RUNBOOK.psql`

La auditoría E.10 confirmó la separación T1/T2 y luego abrió CA-N101 a CA-N106.
Desde LOTE-E.11, el runbook normativo vigente sustituye al de E.10. Esta sección se
conserva únicamente como trazabilidad histórica.

### T1 · evidencia atómica y read-only

T1 contiene exclusivamente la cadena de evidencia y termina en `ROLLBACK`. Usa:

```sql
begin;
set transaction read only, isolation level repeatable read;
set local search_path = pg_catalog;
```

`SERIALIZABLE` también es válido cuando se ejecuta manualmente.

### T2 · batería adversarial read-write

T2 comienza únicamente después del cierre comprobado de T1.
`PR93_WRITER_V7_ADVERSARIAL_TESTS.sql` conserva su transacción propia y no participa
de la correlación transaccional de T1.

## CA-N97 · clasificación de fallos push

Los únicos rótulos permitidos son:

- `NON_FAST_FORWARD_BEFORE_UNREACHABLE`;
- `COMPACTION_DIFF_SCOPE_OVERREACH`;
- `PUSH_FAILURE_UNCLASSIFIED_NO_LOG`.

Los runs 574 y 582 permanecen como `PUSH_FAILURE_UNCLASSIFIED_NO_LOG` hasta obtener
evidencia autenticada.

## CA-N98 · correlación y clúster

La sonda E.10 introdujo fingerprint, PID, timestamp y comparación tipada. La auditoría
confirmó seis escenarios y detectó que la llamada obligatoria a
`pg_catalog.pg_control_system()` abortaba con roles sin privilegio.

LOTE-E.11 sustituye esa implementación: la sonda obligatoria ya no referencia
`pg_control_system()` y la identidad fuerte se obtiene mediante una sonda opcional,
ejecutada solo después de un capability check seguro.

## CA-N99 · corrección editorial

La forma normativa es `transacción`. La grafía histórica incorrecta queda retirada de
las guardas vigentes y no debe reutilizarse.

## Contrato vigente

El contrato normativo posterior es `PR93_LOTE_E11_GUARDS.md`. CA-N93, CA-N96,
CA-N102 y CA-N103 permanecen abiertos hasta sus lotes específicos.

## Prohibiciones

- No ejecutar T2 dentro de T1.
- No aceptar una captura bajo `READ COMMITTED`.
- No comparar timestamps como strings.
- No ejecutar la sonda opcional de system identifier sin capability check favorable.
- No declarar CA-N93 o CA-N96 cerrados.
- No declarar runtime PASS, merge autorizado o producción.
