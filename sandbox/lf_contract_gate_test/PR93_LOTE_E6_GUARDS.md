# PR #93 · LOTE-E.6 · Cierre CA-N77 a CA-N83

## Alcance

Este lote endurece únicamente el addendum final de integridad y añade un preflight
SELECT-only. No modifica el readback primario de 25 vectores, migraciones, batería
adversarial, Edge, workflows ni código desplegable. No autoriza Supabase, SQL contra
el proyecto LF, claves, baseline o merge.

## Orden obligatorio de ejecución

1. `PR93_LOTE_E6_DEPENDENCY_PREFLIGHT.sql`;
2. `PR93_LOTE_C_EVIDENCE_READBACK.sql`;
3. `PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql`;
4. `PR93_WRITER_V7_ADVERSARIAL_TESTS.sql`.

El preflight y ambos readbacks deben emitir sus campos obligatorios en `true`. La
batería adversarial debe ejecutarse únicamente en un entorno aislado autorizado y
terminar en `ROLLBACK`.

## CA-N77 · trigger por fila

`binder_and_trigger_integrity` exige `(tgtype & 1)=1`, publicado como
`gate_trigger.for_each_row`. Un trigger `FOR EACH STATEMENT` produce `false`.

## CA-N78 · ausencia de cláusula WHEN

El veredicto exige `pg_trigger.tgqual IS NULL`, publicado como
`gate_trigger.without_when_clause`. Cualquier condición `WHEN (...)` produce `false`,
aunque el resto del trigger coincida.

## CA-N79 · todos los UPDATE

El veredicto exige `tgattr=''::pg_catalog.int2vector`, publicado como
`gate_trigger.all_update_columns`. Un trigger `UPDATE OF columna` no satisface el
contrato, porque el binder debe ejecutarse ante cualquier actualización.

## CA-N80 y CA-N81 · inventario completo de triggers

PostgreSQL no permite dos triggers homónimos sobre la misma tabla. Por ello,
`count(*)=1` sobre el nombre esperado demuestra presencia, no discrimina duplicados
homónimos.

El riesgo relevante es otro trigger no interno que se ejecute `BEFORE INSERT` o
`BEFORE UPDATE`. El addendum publica:

- `table_trigger_inventory.before_insert_update_count`;
- `table_trigger_inventory.before_insert_update_names`;
- `table_trigger_inventory.only_expected_before_insert_update`.

El veredicto solo es `true` cuando el inventario contiene exactamente:

`trg_05_bind_gate_writer_nonce_v7`

Cualquier trigger adicional relevante produce `false`, incluso si está deshabilitado.

## CA-N82 · dependencias y catálogo

`PR93_LOTE_E6_DEPENDENCY_PREFLIGHT.sql` verifica antes del addendum:

- `extensions.digest(bytea,text)`;
- `private.fn_bind_gate_writer_nonce_v7()`;
- rol `lf_governance_owner_v3`;
- tabla `private.lf_gate_test_runs_v3`.

El addendum mantiene fallo cerrado si una dependencia desaparece. Las relaciones,
funciones y tipos de catálogo se califican con `pg_catalog` para evitar depender del
`search_path`. `extensions.digest` conserva su esquema explícito.

## CA-N83 · owner del SECURITY DEFINER

El owner deja de ser meramente informativo. El addendum publica
`gate_trigger.function_owner_is_governance` y exige que `pg_proc.proowner` sea
exactamente el rol resuelto por:

`pg_catalog.to_regrole('lf_governance_owner_v3')`

La ausencia del rol o un owner diferente producen `false`.

## Contrato compuesto de LOTE-E.6

`binder_and_trigger_integrity=true` exige simultáneamente:

1. dependencias presentes;
2. digest exacto del binder;
3. trigger esperado presente una sola vez;
4. `ENABLE ALWAYS`;
5. `BEFORE INSERT OR UPDATE`;
6. `FOR EACH ROW`;
7. ausencia de `WHEN`;
8. ausencia de lista `UPDATE OF`;
9. enlace exacto a `private.fn_bind_gate_writer_nonce_v7()`;
10. owner `lf_governance_owner_v3`;
11. inventario sin triggers adicionales `BEFORE INSERT/UPDATE`.

Ningún subcampo aislado sustituye el booleano compuesto ni los campos obligatorios del
readback primario.

## Digest vigente

`3927d2b5bc724f10d5f3db09ad204e3212060c30242ccab7b9501869d6396293`

La rotación continúa sujeta al procedimiento reproducible y auditoría independiente
documentados en LOTE-E.5.

## Run 574

El head de LOTE-E.5 tuvo un run `push` 574 fallido y un run `pull_request` 575 exitoso.
La causa del run 574 no queda resuelta por el árbol: los pasos deterministas fueron
reproducidos por la auditoría y pasaron, mientras que los logs no estuvieron
disponibles. Antes de cualquier gate administrativo debe revisarse el log autenticado del run 574 o dejar constancia verificable de su indisponibilidad. Los checks nuevos de
LOTE-E.6 no sustituyen esa trazabilidad histórica.

## Evidencia pendiente

1. auditoría estática independiente del head de LOTE-E.6;
2. ejecución del preflight, readbacks y batería en entorno aislado;
3. revisión autenticada o cierre documentado del run 574;
4. test Edge y comparación Edge/PostgreSQL;
5. controles administrativos previos al merge.
