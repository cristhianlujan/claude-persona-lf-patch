# H4 · EX6 → PG-04…PG-14 · resultados reales v1 (candidato, NO ADMITIDO)

**Corte:** 2026-11-09. **PR:** #3740 (draft). **Estado:** H4 PARCIAL; PG-06 C1 bloquea por dependencia PG-01 no acreditada. **No hay v2 nuevo**, porque el único rechazo observado no corresponde a PG-08/PG-09. No declarar el objetivo PG-04→PG-14 completado.

## Procedencia exclusiva de EX6

- Run source: https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42674262914, intento 1/3, resultado público PASS.
- Sandbox base: `53ab6b1a85da95f3e2a38d7f3298af731c6698ab`.
- Commit de propuesta: `13ef9c319fb62f7e08f6f030d447c60ee7bfa7f5`.
- Commit de incorporación a main sandbox: PR #53, `912c4ad9ea71f48edbd1ac58089441f9ed2c3449`.
- `task_pack_sha256`: `31a01a43c13d1a6c8ef5d861825e03211d05566abecded7eeea023dcfaba048e`.
- `proposal_sha256`: `c469a00ebb78d1346cecab0b19bd7c385e13e428a2eaf1fccea61e30dc838d78`.
- `holdout_sha256` público en registro: `c2b583ebcc14e8e73e1b66eff38d86dd3814b75e5f5e1857de65deee5c8b1a57`. El recibo público reporta PASS; ningún archivo, resultado detallado ni comando del examen oculto fue buscado o reconstruido.
- Spec base público **completo**, copiado byte por byte a `evidence/ex6_base_REMINDERS_SPEC.md`, Git blob `01895c09cb6b3983f4fa2ab7fc1db628b2bbaa72`; se extrae Lote D de ese documento fijado.
- Registro EX6 Git blob `15fd94d238215dbbc21a3bdc3cc719028c8513e7`.
- Sobre público de propuesta Git blob `85761b8722f553fe25cf70d937105a4c35ce871e`.

| ZIP original de Actions, **sin edición** | SHA-256 | Git blob |
|---|---|---|
| `native-attempt-proof.zip` (13699547221) | `237baba0c483f1330244dff94314fc883a7321b1f41295686dc501b4f7527114` | `b176e839dab6a526192bb2032e7a03e161667a0a` |
| `native-visible-feedback-and-cost.zip` (13699208046) | `fb76b00b8870ebc0f11b509e5770a185f58e2564b4af8e9fb9349a74e9625e5b` | `ff719db0d05f037a845117810f69bcf95e4289fa` |
| `native-verified-patch.zip` (13699771867) | `57f73f828ec5a926b6f77e712ed952e2a7c79a1471e16f73f6810cb88ec4dd04` | `81549f61cef3de587b136fba8af26a06ea6afd9e` |

Los SHA de miembros originales se validan en `ex6_real_world_v1.py` sin reescribir ZIP:
`attempt-proof.json=e45dd320598739b959849137033e6908fa6a12cfbdb0faacdce1a009f6120336`,
`feedback.json=9b796e549eccc582ee0717d4bcf4a6859237c49eca6699fe403d9075595e66bb`,
`cost.json=78d6445696d10a2b1bb15f1bc936cd05c3882bd64bd5327757d1b7ff0cbffe25`,
`status.json=c2725691a6f941648becd262ff45a51b3bcb1a883ac0fd81b274019edc0cb6af`,
`worker.patch=e0c3675f7bc7b2b80ed199be3cd5fffadae564d8b354da75ef6c56bb21bf7ce5`.

## Origen del alcance y hunks

`tools/ex6_source_truth_v1.py` lee **solo** el spec completo real del commit base y extrae Lote D (REM-D1–D4), `task_spec` EX6, sobre público de propuesta, y los 3 ZIP. Todos los snapshots Git se verifican por blob SHA; el diff real tiene exactamente **tres hunks ADD**, un archivo nuevo por hunk. `authorize_from_real_hunks` liga los 3 a un solo batch `ex6://batch/EX6-SOL-001` y un scope distinto por archivo:

| Archivo | Obligaciones trazadas |
|---|---|
| `ReminderStats.java` | REM-D1 |
| `ReminderStatsService.java` | REM-D2 |
| `ReminderStatsController.java` | REM-D3, REM-D4 |

Las rutas existentes permanecen protegidas, con escritura restringida a estos tres archivos. El sobre original y el diff de Git tienen idénticas líneas de código: la comparación permite quitar **únicamente** las tres líneas añadidas `index 0000000..OID` de metadatos Git para cotejarlos. Ninguna línea de fuente es normalizada.

## Corrida original de productores v1 · antes/después

Evidencia de ejecución: workflow temporal de diagnóstico `H4 temporary original producer execution`, corridas [#42694308943](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42694308943) y [#42695047716](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42695047716), que ejecutó los productores originales PG-04, PG-05 y PG-06 C1. Las pruebas pasan, y luego el workflow temporal se elimina del PR (no se cambia la allowlist de PASE).

| Etapa | Antes de v2 · productor real EX6 | Después de v2 | Código exacto o límite |
|---|---|---|---|
| PG-04 | **PASS_SOURCE_ONLY** | SIN_V2, mismo candidato | Partition, DoD, coverage, review request y exit originales; sin autoridad |
| PG-05 | **PASS_SOURCE_ONLY** | SIN_V2, mismo candidato | C1–C5 y handoff originales; sin locks ni permisos de escritura |
| PG-06 | **BLOCK** | SIN_V2 · BLOCK | `PG06_C1_PG01_DECISION_BINDING_INCOMPLETE` |
| PG-07 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | `UPSTREAM_BLOCKED:PG-06:PG06_C1_PG01_DECISION_BINDING_INCOMPLETE` |
| PG-08 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo ascendente |
| PG-09 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo ascendente; v1 costo nativo **no probado con EX6 aún** |
| PG-10 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo ascendente |
| PG-11 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo ascendente |
| PG-12 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo ascendente |
| PG-13 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo ascendente |
| PG-14 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo ascendente |

**Importante:** los campos de manifiesto A9/PG03 usados para construir el paquete source-only PG-04 son candidatos explícitamente `ex6://unattested/`; **no son certificaciones de origen, decisiones de Análisis ni autenticación**. El contrato original PG-04 devuelve `CANDIDATE_NOT_ADMITTED`. No se debe confundir ese PASS estructural con un cierre de PG-04 productivo.

**PG-06 C1:** se pasó `pg01_currentness_binding=None` explícitamente, porque ninguno de los artefactos públicos EX6 es un recibo `CURRENTNESS_AUTHORITY` de PG-01. El productor **real** devolvió `PG06_C1_PG01_DECISION_BINDING_INCOMPLETE`. Sustituirlo por hashes inventados permitiría simular avance de PG-06 a PG-14, violando el mandato.

## Costos y autoridad

En `cost.json`: `api_calls=0`, `real_api_usage=false`, `total_usd=0`, `cost_scope=incremental_api`, `subscription_cost=NOT_EVALUATED`. No equivale a costo total cero. `executor_mode=GPT_NATIVE`. Todos los flags `production_authority`, `handoff_allowed` y `receipt_authenticated` quedan `False`.

## Pruebas ejecutadas sin contaminar suites

- [#42695047716](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42695047716): 10/10 tests EX6; 29/29 tests sintéticos PG-04 v1; 13/13 tests sintéticos PG-05 v1. Todos SUCCESS tras fijar el spec completo del commit base. Los productores v1 y las pruebas originales no se modificaron.
- `install()/uninstall()` restaura `sys.path`; no hay cambios de funciones/constantes sintéticas.
- Anticontaminación: los campos del resultado de `source_truth()` no contienen `ex5c` ni `lote-c`. Fuente de verdad EX6 no lee bundles del ejercicio previo.
- Fallo de un byte de cualquiera de los ZIP originales se rechaza. Sobre y parche se atan por SHA y por código byte-a-byte salvo metadatos `index`.

## Rechazo que sí justifica trabajo siguiente

**Bloqueo de procedencia de PG-01**, no un defecto en contratos v1 PG-08/PG-09. Antes de crear PG-09 C1 v2 o PG-08 C1/C8 v2, se necesita una vinculación PG-01 real y autorizada —o una decisión gobernada que permita un marcador `unattested`—, sin tocar Análisis productivo. Luego se reejecuta PG-06→PG-14 para observar el siguiente rechazo exacto. La necesidad funcional prevista de costo API conocido 0 en PG-09 sigue siendo hipótesis de revisión estática hasta esa prueba.

**No se crearon v2 sin prueba. No hay SUPABASE writes, SUPER_ADMIN, merge, Train, cambios a `main`, cambios v1 ni `vendor/`. No poner `ready-to-merge`.**
