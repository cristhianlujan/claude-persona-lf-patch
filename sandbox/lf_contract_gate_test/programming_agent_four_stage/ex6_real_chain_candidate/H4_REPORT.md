# H4 · EX6 → PG-04…PG-14 · resultados reales v1 (candidato, NO ADMITIDO)

**Corte:** 2026-11-09. **PR:** #3740 (draft). **Estado:** H4 PARCIAL; PG-06 C1 pasa usando exclusivamente el fixture oficial PG-01 marcado `FIXTURE_UNATTESTED`, pero PG-06 C2 supera el chequeo de catálogo/observación con evidencia real de Java 21; PG-06 C3 bloquea por A7 no acreditado. **No hay v2 nuevo**, porque el único rechazo observado no corresponde a PG-08/PG-09. No declarar el objetivo PG-04→PG-14 completado.

## Procedencia exclusiva de EX6

- Run source: https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42674262914, intento 1/3, resultado público PASS.
- Sandbox base: `53ab6b1a85da95f3e2a38d7f3298af731c6698ab`.
- Commit de propuesta: `13ef9c319fb62f7e08f6f030d447c60ee7bfa7f5`.
- Commit de incorporación a main sandbox: PR #53, `912c4ad9ea71f48edbd1ac58089441f9ed2c3449`.
- `task_pack_sha256`: `31a01a43c13d1a6c8ef5d861825e03211d05566abecded7eeea023dcfaba048e`.
- `proposal_sha256`: `c469a00ebb78d1346cecab0b19bd7c385e13e428a2eaf1fccea61e30dc838d78`.
- `holdout_sha256` público en registro: `c2b583ebcc14e8e73e1b66eff38d86dd3814b75e5f5e1857de65deee5c8b1a57`. El recibo público reporta PASS; ningún archivo, resultado detallado ni comando del examen oculto fue buscado o reconstruido.
- Lote D público del spec base, fijado en `evidence/lote_d_spec.md`; derivado de `apps/time-service/REMINDERS_SPEC.md` en el commit base `53ab6b1a85da95f3e2a38d7f3298af731c6698ab` (blob original `01895c09cb6b3983f4fa2ab7fc1db628b2bbaa72`).
- Registro EX6 Git blob `15fd94d238215dbbc21a3bdc3cc719028c8513e7`.
- El SHA de propuesta se toma del recibo `status.json`; el sobre de propuesta no se utiliza como fuente de hunks ni se incluye en el PR.

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

`tools/ex6_source_truth_v1.py` lee **solo** el Lote D (REM-D1–D4), el `task_spec` EX6 y los 3 ZIP originales. Todos los snapshots Git se verifican por blob SHA; el diff real tiene exactamente **tres hunks ADD**, un archivo nuevo por hunk. `authorize_from_real_hunks` liga los 3 a un solo batch `ex6://batch/EX6-SOL-001` y un scope distinto por archivo:

| Archivo | Obligaciones trazadas |
|---|---|
| `ReminderStats.java` | REM-D1 |
| `ReminderStatsService.java` | REM-D2 |
| `ReminderStatsController.java` | REM-D3, REM-D4 |

Las rutas existentes permanecen protegidas, con escritura restringida a estos tres archivos. Los hunks se extraen **únicamente** de `native-verified-patch.zip`, verificando los blobs de Git. Ninguna línea de fuente es normalizada.

## Evidencia independiente de toolchain y base EX6 (C2/C4)

Fuente C2: `apps/time-service/pom.xml` del commit base `53ab6b1a85da95f3e2a38d7f3298af731c6698ab`, Git blob `dab45a1d6580ed53ebe67b341312ef588cb80131`. El parser XML obtiene `java.version=21` y Spring Boot parent `4.1.1` (sin configurar la versión Java desde un fixture). El perfil solicitado es `stack://java21-maven-spring-boot`, y el catálogo se liga al blob original.

Observación C2: corrida [worker-native #42674262914](https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42674262914), job `129351701663`: el log original muestra `Resolved Java 21.0.13+9 from tool-cache`, Temurin `21.0.13-9`, y `EX6_ISOLATED_JAVA21_AND_MAVEN_PASS`. Extracto **literal** preservado en `evidence/ex6_native_java21_log_excerpt.txt`, blob Git `8c7254cd16c45ee777bbf219fdc161155ed24743`; `ex6_pg06_evidence_v1.py` calcula su SHA-256 en cada lectura y lo introduce en el `evidence_ref`. El productor C2 v1 devuelve `MATCH_REPORTED_UNVERIFIED`, `CANDIDATE_NOT_ADMITTED` y autoridad False: **no** autentica la ejecución como un juicio productivo.

La comparación independiente de árboles Git da **el mismo árbol** `apps/time-service/` en la base, el HEAD #51 y el checkout merge usado realmente por CI:

| Referencia | Commit | SHA del árbol `apps/time-service/` |
|---|---|---|
| EX6 base | `53ab6b1a85da95f3e2a38d7f3298af731c6698ab` | `2c199d6c49b76ea8a23e15149425ece0f29e1410` |
| PR #51 HEAD | `3634fdea8ae63b0f5e48fc4925e7f9dfd0d74f62` | `2c199d6c49b76ea8a23e15149425ece0f29e1410` |
| PR #51 test merge ref | `6e5a0a444edaa6fc0ec66d59883c4c83d218717f` | `2c199d6c49b76ea8a23e15149425ece0f29e1410` |

C4: [CI #42664733176, job 129325278303](https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42664733176/job/129325278303) check `backend (Maven verify)` = `SUCCESS`, ejecutó `mvn -B -q -f apps/time-service/pom.xml test` sobre el checkout merge equivalente. Extracto literal: `evidence/ex6_baseline_ci_log_excerpt.txt`, Git blob `4913a5ffdf93df35dce52f1cb518e80710b6daaf`, con SHA-256 computado por el lector. **No hay observación de lint/formato de la base** ni SHA autenticado del stdout/stderr íntegros: `lint_status=pending-execution`, `command_results=[]` y esquema deliberado `EX6_PG06_BASELINE_PARTIAL_V1`. Esto no se presenta como un `PG06_UNCHANGED_TARGET_BASELINE_OBSERVATION_CANDIDATE_V1` válido ni se hace pasar por un PASS de C4. La ejecución real C4 está pendiente de C3 y de completar BUILD+LINT.

## Corrida original de productores v1 · antes/después

La corrida [#42697234378](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42697234378) ejecutó las pruebas EX6 (13/13 PASS), la cadena v1 en fuente real y las pruebas sintéticas PG-06 originales (15/15 PASS), sin cambiar productor alguno. El fixture oficial PG-01 sigue con estado `FIXTURE_UNATTESTED`, idéntico al de los ensayos anteriores. Después de completar C2, el primer bloqueo concreto ahora es C3.

| Etapa | Antes de v2 · EX6 | Después de v2 | Código exacto o límite |
|---|---|---|---|
| PG-04 | **PASS_SOURCE_ONLY** | SIN_V2 | Candidato original no admitido |
| PG-05 | **PASS_SOURCE_ONLY** | SIN_V2 | Candidato original no admitido |
| PG-06 C1 | **PASS_SOURCE_ONLY** | SIN_V2 | PG01=`FIXTURE_UNATTESTED`, importado sin cambios |
| PG-06 C2 | **PASS_SOURCE_ONLY** | SIN_V2 | `MATCH_REPORTED_UNVERIFIED`, candidato no admitido |
| PG-06 C3 | **BLOCK** | SIN_V2 | `PG06_C3_A7_COVERAGE_SHAPE_INVALID` |
| PG-06 C4 | **NOT_RUN** | NOT_RUN | Baseline BUILD visible; LINT `pending-execution`; falta upstream C3 |
| PG-06 C5 | **NOT_RUN** | NOT_RUN | Upstream C3 |
| PG-07 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | `UPSTREAM_BLOCKED:PG-06:PG06_C3_A7_COVERAGE_SHAPE_INVALID` |
| PG-08 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo |
| PG-09 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo; sin rechazo de costo observado |
| PG-10 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo |
| PG-11 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo |
| PG-12 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo |
| PG-13 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo |
| PG-14 | **NOT_RUN_UPSTREAM_BLOCKED** | NOT_RUN | Mismo bloqueo |

**Importante:** el PG-01 importado no prueba una vinculación real a Análisis. Los campos de manifiesto A9/PG03 son explícitamente `ex6://unattested/`. La autorización H4 productiva no está demostrada. El C3 original exige una cobertura A7 `MATERIAL_FRONT_COVERAGE_V1` con fuente y huellas que **no aparecen en EX6**; se pasó `None` y `[]` (no se importó el A7 sintético), obteniendo `PG06_C3_A7_COVERAGE_SHAPE_INVALID`.

## Costos y autoridad

En `cost.json`: `api_calls=0`, `real_api_usage=false`, `total_usd=0`, `cost_scope=incremental_api`, `subscription_cost=NOT_EVALUATED`. No equivale a costo total cero. `executor_mode=GPT_NATIVE`. Todos los flags `production_authority`, `handoff_allowed` y `receipt_authenticated` quedan `False`.

## Pruebas ejecutadas sin contaminar suites

- [#42697234378](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42697234378): **13/13 tests EX6** y **15/15 PG-06 sintéticas** PASS; tests incluyen equivalencia de fuente, C2 real, base C4 parcial y compatibilidad de fixture PG-01. Los productores v1 no fueron modificados.
- `install()/uninstall()` conserva `sys.path` de las suites sintéticas. Los tres ZIP originales, hunks y huellas se siguen verificando. Las entradas EX6 no contienen datos de otros ejercicios, salvo el único fixture PG-01 autorizado.
- La fuente PG06 C2 usa XML/CI originales sin reescribir resultados. El manifiesto C4 distingue `SUCCESS` del check CI de `LINT=pending-execution`.

## Rechazo exacto que impide la continuación

**PG06_C3_A7_COVERAGE_SHAPE_INVALID**. Se requiere un recibo de cobertura A7 real y una planificación de reversibilidad atribuibles a EX6, o una decisión gobernada sobre cómo representar justificadamente `not-applicable`; no se debe inventar ni copiar otro A7. La comprobación formal de C4 requiere además lint de la base. No hay evidencia todavía para crear PG-08/PG-09 v2: sus productores no fueron ejecutados.

**No se crearon v2 sin prueba. No hay SUPABASE writes, SUPER_ADMIN, merge, Train, cambios a `main`, cambios v1 ni `vendor/`. No poner `ready-to-merge`.**
