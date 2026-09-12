# PR #93 · LOTE-E.7 · Cierre CA-N84 a CA-N88

## Alcance

Este lote endurece el addendum final, actualiza el preflight y corrige documentación.
No modifica el readback primario de 25 vectores, migraciones, batería adversarial,
Edge, workflows ni código desplegable. No autoriza conexión a Supabase, ejecución SQL
contra el proyecto LF, claves, baseline o merge.

## Orden obligatorio de ejecución

En un entorno aislado autorizado:

```sql
begin;
set local search_path = pg_catalog;
-- ejecutar PR93_LOTE_E6_DEPENDENCY_PREFLIGHT.sql
-- ejecutar PR93_LOTE_C_EVIDENCE_READBACK.sql
-- ejecutar PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql
-- ejecutar PR93_WRITER_V7_ADVERSARIAL_TESTS.sql
rollback;
```

La fijación del `search_path` es defensa adicional del runbook. El addendum E.7 no
depende de ella para operadores, agregados, tipos o catálogos: esos elementos están
calificados explícitamente.

## CA-N84 · independencia del search_path

El addendum califica:

- todos los operadores de igualdad con `OPERATOR(pg_catalog.=)`;
- todos los operadores bit a bit con `OPERATOR(pg_catalog.&)`;
- `pg_catalog.count`, `pg_catalog.min`, `pg_catalog.bool_and` y
  `pg_catalog.jsonb_agg`;
- tipos `pg_catalog.text`, `pg_catalog.name`, `pg_catalog.int2`,
  `pg_catalog.int8`, `pg_catalog.int2vector`, `pg_catalog.jsonb` y
  `pg_catalog."char"`;
- relaciones y funciones de catálogo con `pg_catalog`;
- el hash con `pg_catalog.sha256(bytea)`.

Un esquema previo en el `search_path` no puede sustituir los operadores usados para
comparar el digest, los OID, el inventario o los nombres. La sesión debe mantener de
todos modos `SET LOCAL search_path = pg_catalog` para que la evidencia completa,
incluido el readback primario heredado, se ejecute bajo un contexto reproducible.

## CA-N85 · reglas, forma de tabla, partición e herencia

El addendum publica `gate_table` y exige simultáneamente:

- `present=true`;
- `ordinary_table=true`, equivalente a `relkind='r'`;
- `without_rules=true`, equivalente a `relhasrules=false`;
- `not_partition=true`, equivalente a `relispartition=false`;
- `without_inheritance=true`, sin filas en `pg_catalog.pg_inherits` donde la tabla sea
  hija o padre.

Una regla `DO INSTEAD`, una vista o tabla particionada, una partición, o cualquier
vínculo de herencia produce `binder_and_trigger_integrity=false`.

## CA-N86 · cardinalidad sin pgcrypto

El addendum ya no invoca `extensions.digest` para calcular el pin. Utiliza la función
núcleo de PostgreSQL 16:

`pg_catalog.sha256(pg_catalog.convert_to(prosrc,'UTF8'))`

Por ello puede devolver una fila aunque `extensions.digest(bytea,text)` no exista. La
dependencia de pgcrypto sigue publicada como `primary_digest_available` y forma parte
del booleano compuesto porque el readback primario aún la requiere. Si falta, el
addendum devuelve una fila con `binder_and_trigger_integrity=false`.

## CA-N87 · enmienda sobre duplicados homónimos

PostgreSQL no permite dos triggers con el mismo nombre sobre una misma tabla. La frase
de LOTE-E.5 que trataba ese escenario como reproducible queda sustituida por esta regla:

- `count(*)=1` filtrado por el nombre esperado demuestra presencia única del binder;
- el riesgo real es otro trigger relevante con un nombre distinto;
- ese riesgo se controla mediante el inventario completo de triggers no internos
  `BEFORE INSERT/UPDATE`.

## CA-N88 · continuidad nominal del addendum

El archivo conserva el nombre histórico
`PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql` para no romper referencias de evidencia ya
versionadas. Desde LOTE-E.7 su alias JSON es
`pr93_lote_e7_final_integrity_readback`. El archivo es el addendum acumulativo vigente
de E.5, E.6 y E.7; el head exacto determina su versión normativa.

## Contrato compuesto de LOTE-E.7

`binder_and_trigger_integrity=true` exige:

1. dependencias del contrato acumulado presentes;
2. digest exacto del binder calculado con SHA-256 núcleo;
3. tabla privada existente y ordinaria;
4. tabla sin reglas de reescritura;
5. tabla no particionada y sin herencia;
6. trigger esperado presente una sola vez;
7. `ENABLE ALWAYS`;
8. `BEFORE INSERT OR UPDATE`;
9. `FOR EACH ROW`;
10. ausencia de `WHEN`;
11. ausencia de lista `UPDATE OF`;
12. enlace exacto al binder fijado;
13. owner `lf_governance_owner_v3`;
14. inventario sin triggers adicionales relevantes.

Ningún subcampo aislado sustituye el booleano compuesto ni los campos obligatorios del
readback primario.

## Run histórico 574

La auditoría de E.6 identificó el fallo en `Validate LF contract`, comando
`python3 scripts/lf_contract_check.py`. El log autenticado no estuvo disponible y la
causa raíz no se determinó. El mismo árbol pasó localmente y el run `push` 576 del head
E.6 pasó con el mismo script. Se registra como fallo histórico no reproducible, sin
relación demostrada con LOTE-E.5. Antes del gate administrativo debe conservarse esta
constancia junto con la imposibilidad de recuperar el log, salvo que un operador con
permisos logre obtenerlo.

## Evidencia pendiente

1. auditoría estática independiente del head de LOTE-E.7;
2. ejecución del runbook completo en entorno aislado autorizado;
3. captura conjunta del preflight, readback primario, addendum y batería adversarial;
4. test Edge y comparación Edge/PostgreSQL;
5. controles administrativos previos al merge.
