# Lote A — P07: inventario y clasificación estructural de herencias

**Corte observado:** 28-oct-2026. Fuente: Supabase solo lectura. PR #3269 en rama de desarrollo. Ninguna regla fue publicada, revocada o cambiada.

## Universo

241 definiciones de reglas originan 8.852 relaciones `DERIVED_GLOBAL`. La clasificación siguiente analiza la **procedencia estructural**, no la pertinencia semántica ni la autoridad de heredar.

| Cohorte excluyente por relación derivada | Relaciones | Evidencia / interpretación |
|---|---:|---|
| Destino sin shell verificable | 2.201 | 16 pantallas carecen de módulo vinculado. No asignar un módulo/shell ficticio |
| Origen sin shell verificable (destino conocido) | 42 | 1 regla sin shell de origen identificable entre sus vínculos físicos |
| Destino fuera de los shells observados en vínculos propios | 5.230 | 240 reglas muestran expansión a otro shell; **posible sobreamplitud**, no prueba de invalidez |
| Destino dentro de los shells observados en vínculos propios | 1.379 | Mismo shell no equivale a autorización: pueden existir condiciones internas |
| **Total** | **8.852** | Partición exhaustiva: `partition_complete=true` en SELECT ejecutado |

La prueba también devuelve: 241 reglas distintas, 16 pantallas con shell desconocido. No forzar clasificaciones de alcance a partir de supuestos. Las 95 reglas transversales sin selector (92 dentro del conjunto de herencia) y las 18 `UNRESOLVED` con selector se gestionan como colas separadas.

## Evidencia ya versionada

- Inventario de 241 filas: `docs/t-remed/IG_LOTE_A_P07_INVENTARIO_241_EVIDENCIA_20261028.csv`.
- SQL de dos consultas SELECT: `sandbox/lf_contract_gate_test/input_governance/ig_lote_a_p07_alcance_readonly_20261028.sql`. **Ambas fueron ejecutadas en lectura**, y el segundo resultado confirmó 8.852/241 y `partition_complete=true`.
- Casos piloto de P01: `docs/t-remed/IG_LOTE_A_P01_CASOS_OBSERVADOS_20261028.md`.
- P02, condiciones existentes y ausencia de módulos: `docs/t-remed/IG_LOTE_A_P02_CONTEXTO_OPCIONAL_PRUEBAS_20261028.md`.

## Método de revisión que sigue (sin motor paralelo)

1. Seleccionar reglas candidatas por contradicción de procedencia, dominio funcional y criticidad. La cantidad de pantallas es una **señal de descubrimiento**, nunca una probabilidad ni permiso.
2. Recuperar intención/condiciones y autoridad de cada regla contra EKB, owner, fuentes de políticas y contexto destino.
3. Validar positivos, negativos y atributos faltantes del destino (sin agregar contexto obligatorio a todas las pantallas).
4. Ratificar selector permitido por gobernanza existente; guardar recibo y versión cuando el carril de autoridad corresponda.
5. Comparar el resultado N-4 con el baseline y todos los consumidores. Solo tras esto se podrá considerar un cutover gradual.

**P07 estado:** inventario y partición exhaustiva PASS en lectura; **clasificación semántica 241/241 y decisiones 0/241, pendiente**. El SQL de sandbox que elimina `DERIVED_GLOBAL` en bloque continúa NO-GO.
