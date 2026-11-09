# H4 · EX6 → LF PG-04–PG-14 — una pasada, con límites de fuente

**Estado:** CANDIDATO SOURCE-ONLY; **H4 de extremo a extremo NO ADMITIDO**. **PR #3740 en draft**, sin `ready-to-merge`. Corte de diagnóstico: 09/11/2026, evidencia adicional run #42707967927.

Se ejecutó un diagnóstico unificado contra **productores originales v1** (y el único contrato nuevo PG-09 C1 v2) con entradas EX6 verificadas. Se continuó con pruebas **independientes** en etapas posteriores aun cuando la cadena estricta estaba bloqueada; los PASS de esas pruebas no se confunden con una cadena real admitida. Los productores v1 y `vendor/` no se tocaron.

## Evidencia EX6 BUILD/LINT nueva — corrida #42707967927 (09/11/2026)

[GitHub Actions #42707967927](https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42707967927) ejecutó exitosamente el workflow manual sin secretos, sobre `53ab6b1a85da95f3e2a38d7f3298af731c6698ab` y `912c4ad9ea71f48edbd1ac58089441f9ed2c3449`.

**Artefacto fuente:** `ex6-build-lint-aosp-two-snapshots-v1`, ID `13715275651`; **SHA-256 del ZIP original:** `2e8950a77ee9707df3cc7ab77e52e592a96f317fb4cc0736b3c28e8044671769`. **SHA-256 del JSON original:** `5008714c29f55c2813792d6da98002393febdc5adbe5070ae194970742ff9fbd`. El .sha256 interior coincide exactamente.

| Comando | Base real | Candidato EX6 |
|---|---|---|
| `mvn -B -q -f apps/time-service/pom.xml package` | exit `0` | exit `0` |
| AOSP 1.30.0 `--aosp --dry-run --set-exit-if-changed` | exit `0` | **exit `1`** |
| `javac --release 21 -Xlint:all` | exit `0` | exit `0` |
| `python3 apps/time-service/visible-tests/ex6/run_visible.py` | N/A | exit `0`, `EX6_VISIBLE_OK` |

El stdout AOSP del candidato menciona exactamente `ReminderStats.java`, `ReminderStatsService.java` y `ReminderStatsController.java`; ningún otro Java. **No convertir `exit_code=1` en PASS**. `javac -Xlint:all` pasó sin bytes en stdout ni stderr; PG-12 C2 recibe un digest de configuración **derivado de la versión, el SHA del JAR y los flags AOSP realmente registrados**; conserva `CANDIDATE_NOT_ADMITTED` sin alegar readback autenticado.

**Procedencia y límite:** `evidence/ex6_run_42707967927_receipt_index.json` es un índice derivado sin inventar el estado de los comandos. `tools/ex6_build_lint_index_v1.py` bloquea cambios de huellas, salidas contradictorias y escaladas de autoridad; **valida el ZIP original byte por byte desde el propio árbol de este PR**, con Git blob SHA `33ddd1fa34beb2e6da05992f34e2199dec7481ca`, ZIP SHA-256 `2e8950a77ee9707df3cc7ab77e52e592a96f317fb4cc0736b3c28e8044671769`, JSON SHA-256 `5008714c29f55c2813792d6da98002393febdc5adbe5070ae194970742ff9fbd` y cotejo de **todos** los sha256 stdout/stderr registrados. El índice no reemplaza el ZIP ni confiere autoridad. Los productores originales C4/C1/C2 documentan candidatos estructurales, no una admisión productiva.

**REM-D4:** en el Lote D es obligación de proceso. Quedan referenciados el `visible-tests/ex6/run_visible.py` con resultado `EX6_VISIBLE_OK` y el recibo AOSP real. El primero pasa; el segundo reporta diferencias de formato, de modo que el requisito no está totalmente satisfecho para el snapshot `912c4ad`. Cualquier reparación debe conservar este recibo inmutable y crear una nueva evidencia N+1, nunca reescribirlo.

## Fuentes verificables exclusivas de EX6

- Worker `GPT_NATIVE`, [corrida #42674262914](https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42674262914), intento 1/3, estado público PASS, `api_calls=0`, costo **incremental API** = 0, costo de suscripción `NOT_EVALUATED`.
- Commit base de tarea: `53ab6b1a85da95f3e2a38d7f3298af731c6698ab`.
- Commit de propuesta: `13ef9c319fb62f7e08f6f030d447c60ee7bfa7f5`.
- Incorporación del código en sandbox: merge commit `912c4ad9ea71f48edbd1ac58089441f9ed2c3449`, Git tree raíz `72e5f54ca75cb3a1186dbc160469cf8f5dd070c5` (incluye también gobernanza, no solamente los tres Java).
- `task_pack_sha256=31a01a43c13d1a6c8ef5d861825e03211d05566abecded7eeea023dcfaba048e`.
- `proposal_sha256=c469a00ebb78d1346cecab0b19bd7c385e13e428a2eaf1fccea61e30dc838d78`.
- `holdout_sha256=c2b583ebcc14e8e73e1b66eff38d86dd3814b75e5f5e1857de65deee5c8b1a57`, PASS según recibo público. **No** se leyó, buscó ni reconstruyó el examen oculto.

| ZIP de Actions sin modificar | SHA-256 exacto | Git blob OID |
|---|---|---|
| `native-attempt-proof.zip` | `237baba0c483f1330244dff94314fc883a7321b1f41295686dc501b4f7527114` | `b176e839dab6a526192bb2032e7a03e161667a0a` |
| `native-visible-feedback-and-cost.zip` | `fb76b00b8870ebc0f11b509e5770a185f58e2564b4af8e9fb9349a74e9625e5b` | `ff719db0d05f037a845117810f69bcf95e4289fa` |
| `native-verified-patch.zip` | `57f73f828ec5a926b6f77e712ed952e2a7c79a1471e16f73f6810cb88ec4dd04` | `81549f61cef3de587b136fba8af26a06ea6afd9e` |

Los miembros ZIP están verificados individualmente por `ex6_real_world_v1.py`: `attempt-proof.json=e45dd320598739b959849137033e6908fa6a12cfbdb0faacdce1a009f6120336`, `feedback.json=9b796e549eccc582ee0717d4bcf4a6859237c49eca6699fe403d9075595e66bb`, `cost.json=78d6445696d10a2b1bb15f1bc936cd05c3882bd64bd5327757d1b7ff0cbffe25`, `status.json=c2725691a6f941648becd262ff45a51b3bcb1a883ac0fd81b274019edc0cb6af`, `worker.patch=e0c3675f7bc7b2b80ed199be3cd5fffadae564d8b354da75ef6c56bb21bf7ce5`.

La especificación de Lote D se extrae del blob Git `01895c09cb6b3983f4fa2ab7fc1db628b2bbaa72` de `apps/time-service/REMINDERS_SPEC.md` en el commit base; el `task_spec` usa el blob `15fd94d238215dbbc21a3bdc3cc719028c8513e7`. Los **tres hunks reales** solo salen de `native-verified-patch.zip` y están comprobados frente a sus blobs Git originales. Correspondencia: `ReminderStats.java→REM-D1`, `ReminderStatsService.java→REM-D2`, `ReminderStatsController.java→REM-D3,REM-D4`. No se escribió en archivos protegidos.

## Catálogo y BUILD base de PG-06

- `apps/time-service/pom.xml` base: blob `dab45a1d6580ed53ebe67b341312ef588cb80131`; parser extrae **Java 21**, **Spring Boot 4.1.1**. Perfil `stack://java21-maven-spring-boot`.
- Run Worker #42674262914, job `129351701663`: setup Temurin **21.0.13+9** y marcador `EX6_ISOLATED_JAVA21_AND_MAVEN_PASS`; extracto literal `ex6_native_java21_log_excerpt.txt`, blob `8c7254cd16c45ee777bbf219fdc161155ed24743`. El lector calcula SHA-256 del extracto y lo incorpora en el `evidence_ref`.
- El Git tree exacto `apps/time-service/` es `2c199d6c49b76ea8a23e15149425ece0f29e1410` en base `53ab6b1`, PR #51 HEAD `3634fdea8ae63b0f5e48fc4925e7f9dfd0d74f62` y checkout CI `6e5a0a444edaa6fc0ec66d59883c4c83d218717f`.
- [CI #42664733176, job 129325278303](https://github.com/paulozterra/lf-programming-sandbox/actions/runs/42664733176/job/129325278303) informó `backend (Maven verify)=SUCCESS`; ejecutó `mvn -B -q -f apps/time-service/pom.xml test`. Extracto literal `ex6_baseline_ci_log_excerpt.txt`, blob `4913a5ffdf93df35dce52f1cb518e80710b6daaf`.
- **No hay comprobación real de LINT/formato en la base.** El objeto EX6 parcial `EX6_PG06_BASELINE_PARTIAL_V1` conserva `lint_status=pending-execution`. El C4 v1 lo rechaza con **`PG06_C4_OBSERVATION_SCHEMA_INVALID`**. El fixture oficial C4 logra únicamente un **PASS estructural no acreditado**; no constituye prueba de lint.

## Fixtures oficiales y límites no acreditados

La pasada usa por **import directo**, sin sobrescribir valores, los siguientes fixtures test oficiales:

| Identificador | Función original | Uso |
|---|---|---|
| PG01 | `test_pg06_c1_c5_chain_v1.pg01()` | `fixture://pg01/currentness` y todas las huellas |
| PG06_A7 | `test_pg06_c1_c5_chain_v1.a7_and_plans(exit)` | A7 y plan de reversibilidad, ambos sin alterar |
| PG06_LINT_PROBE_ONLY | `test_pg06_c1_c5_chain_v1.baseline(exit)` | C4 estructural, **nunca lint real** |
| PG09_BUDGET_POLICY_UNATTESTED | `test_pg09_iteration_chain_v1.policy()` | Política para probar el gobernador original |
| PG10_SCENARIOS | `test_pg10_decision_chain_v1.scenarios()` | Matriz de escenarios del juez original |

Cada uno es **`FIXTURE_UNATTESTED`**. Las pruebas comparan PG01 y A7/C4 con el objeto oficial y sus huellas; `install()/uninstall()` restaura el entorno de pruebas. Los campos de perfil de contexto, ejemplos de estándar, aprobación del owner y reviewer independiente que EX6 no acredita se declaran `ex6://unattested/` o `ex6://pending-execution/`, **no** como fixtures oficiales ni como evidencia autenticada.

La reversibilidad propia de EX6 sí es inferible de sus hunks: revertir es **eliminar exclusivamente los tres Java agregados**. Se documenta como `SOURCE_DERIVED_NOT_EXECUTED`, sin ejecutar rollback ni alterar el fixture A7.

## Resultado de UNA pasada, productores originales v1 con ZIP EX6 íntegro

[Corrida de diagnóstico #42711181404](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42711181404), ejecutada sobre el HEAD de pruebas `5733d2a5c8aec5cd2b25e6ea9fb5a85854ce4aa4`: **29/29 pruebas EX6**, **15/15 PG-06**, **14/14 PG-08**, **12/12 PG-12**, todas PASS. Se empleó `ex6_one_pass_v1.run_all()` en una sola ejecución. Los PASS son **candidatos fuente**, con flags de autoridad False, no admiten ejecución productiva. Las etapas posteriores sin readback son pruebas originales aisladas, no una cadena autónoma completa.

| Etapa | Resultado v1 después del bundle | v2 | Diagnóstico exacto |
|---|---|---|---|
| PG-04 | **PASS_SOURCE_ONLY** | No requerido | Partición/DoD/exit original, tres hunks EX6 |
| PG-05 | **PASS_SOURCE_ONLY** | No requerido | C1–C5 / exit original, scopes de tres Java |
| PG-06 | **PASS_FIXTURE_UNATTESTED** | No requerido | PG01 y A7 oficiales no acreditados; **C4 real `PASS_SOURCE_ONLY`**, BUILD y LINT base exit 0, sin usar fixture de baseline como evidencia |
| PG-07 | **PASS_FIXTURE_UNATTESTED** | No requerido | C1–C6, task/patch/holdout EX6; perfil/contexto aún declarativos |
| PG-08 | **PASS_FIXTURE_UNATTESTED** (C1+C2 v1) | **No creado** | C1 BUILD `REPORTED_PASS_UNVERIFIED`; C2 observa **AOSP exit 1 / FORMAT FAIL**, javac LINT exit 0. El modo GPT_NATIVE es aceptado por v1 |
| PG-09 | **PASS_FIXTURE_UNATTESTED**, C1 v1 `REQUIRES_DECISION` | **C1 v2 `REPORTED_WITHIN_BUDGET_UNVERIFIED`** | API calls = 0, propuesta SHA ligada y suscripción `NOT_EVALUATED` |
| PG-10 | **PASS_FIXTURE_UNATTESTED** | No requerido | Contratos originales C1–C5, escenarios oficiales no acreditados |
| PG-11 | **PASS_FIXTURE_UNATTESTED** | No requerido | C1–C5 estructurales; **REM-D4 es de proceso**: `visible-tests/ex6` exit 0 y `format_aosp` exit 1, `process_requirement_satisfied=False`. No confundir esto con un cuarto hunk |
| PG-12 | **PASS_SOURCE_ONLY** (C1+C2 v1) | No requerido | Identidad Git de tres blobs; C2 digesto de configuración de linter AOSP real, `CANDIDATE_NOT_ADMITTED`. C3/C4/persistencia aún no ejecutados |
| PG-13 | **BLOCK, productor C1 aislado** | No requerido | `C1_UPSTREAM_SCHEMA`: falta PG-12 C4 persistido/readback, no tag |
| PG-14 | **BLOCK, productor C1 aislado** | No requerido | `C1_UPSTREAM_SCHEMA`: falta PG-13 C3 freeze, no Testing productivo |

**Distinción necesaria:** La hipótesis de que todos los bloqueos anteriores compartían una sola causa se ha probado solo parcialmente. El bundle real resuelve las faltas de comando en **PG-06 C4, PG-08 C1 y PG-12 C2**, pero revela un **fallo de formato AOSP real** y **no sustituye** las evidencias de persistencia PG-12 C4 y congelación PG-13 C3 que siguen exigiendo PG-13/14. No se inventan esos readbacks ni se emite decisión SUPER_ADMIN.

### PG-09 C1 v2, solo donde hubo defecto observado

Archivo **nuevo**, original v1 intacto: `pg09_c1_iteration_cost_governor_candidate_v2.py`. Para `GPT_NATIVE` y `DETERMINISTIC_TOOL` exige `api_calls=0`, propuesta SHA coincidente o recibo de herramienta, referencias de costo/estado, y costo de suscripción `NOT_EVALUATED`; en caso contrario bloquea. El resultado conserva la estructura `PG09_C1...V1` por compatibilidad de lectura con los productores posteriores, con campos adicionales de trazabilidad nativa y hash recomputado. **No autentica recibos**, no habilita intentos y no confiere autoridad. Para `WORKER_API` o sin evidencia nativa delega literalmente al v1: **equivalencia JSON y SHA exactos** confirmada en prueba.

Negativos probados: llamadas API no cero, propuesta faltante, propuesta incorrecta, modo desconocido, ausencia de recibo para herramienta, llamadas contradictorias; positivo determinista con recibo real/declarado. No se construyó PG-08 C1/C8 v2 porque su rechazo EX6 es de recibos incompletos, no de modo.

## Pruebas, gobernanza y seguridad

- [#42711181404](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42711181404): **29/29** pruebas EX6 con readback del ZIP original y **15/15 PG-06**, **14/14 PG-08**, **12/12 PG-12** sintéticas originales; todo SUCCESS. [Corrida anterior #42701124328](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/42701124328) conserva las demás suites PG06–PG14 (sin productores v1 modificados). Todas ejecutadas en procesos separados sin modificar productores.
- Las suites PG04 y PG05 conservaron sus resultados previos (29/29 y 13/13); no se modificaron.
- Valores/refs en salidas de entradas EX6 no contienen `ex5c` ni `lote-c`; exclusivamente los fixtures permitidos están marcados con origen oficial. Todos los flags de autoridad siguen `False`.
- Los tres ZIP se conservan byte por byte. Sin acceso al examen oculto; sin Supabase writes, sin migraciones, sin SUPER_ADMIN, sin cambios en `vendor/` ni productores v1.
- La corrida auxiliares se conserva como evidencia histórica; su workflow temporal se **elimina del PR antes de revisión**. No crear ni activar `ready-to-merge` sin dictamen de Claude. El PR no está listo para fusionar como H4 completo.

## Inventario de archivos (incluye evidencia EX6 original, sin workflow temporal)

Raíz de candidato: `sandbox/lf_contract_gate_test/programming_agent_four_stage/ex6_real_chain_candidate/`.

- `H4_REPORT.md`
- `evidence/ex6_base_REMINDERS_SPEC.md`
- `evidence/ex6_base_pom.xml`
- `evidence/ex6_task_registration.json`
- `evidence/ex6_native_java21_log_excerpt.txt`
- `evidence/ex6_baseline_ci_log_excerpt.txt`
- `evidence/ex6-build-lint-aosp-two-snapshots-v1.zip` — **ZIP original byte por byte**, Git blob `33ddd1fa34beb2e6da05992f34e2199dec7481ca`
- `evidence/ex6_run_42707967927_receipt_index.json` — índice derivado, no sustituye el ZIP
- `evidence/native-attempt-proof.zip`
- `evidence/native-visible-feedback-and-cost.zip`
- `evidence/native-verified-patch.zip`
- `tools/ex6_source_truth_v1.py`
- `tools/ex6_real_world_v1.py`
- `tools/ex6_real_chain_v1.py`
- `tools/ex6_pg06_evidence_v1.py`
- `tools/ex6_build_lint_index_v1.py`
- `tools/ex6_build_lint_inputs_v1.py`
- `tools/ex6_pg07_v1.py`
- `tools/ex6_one_pass_v1.py`
- `tests/test_ex6_evidence_v1.py`
- `tests/test_ex6_chain_v1.py`
- `tests/test_ex6_bundle_index_v1.py`
- `tests/test_ex6_pg09_native_v2.py`
- Fuera del directorio candidato: `sandbox/lf_contract_gate_test/programming_agent_four_stage/pg09_iteration_candidate/tools/pg09_c1_iteration_cost_governor_candidate_v2.py`.

**Pendientes reales antes de una admisión total:** (i) reparar exclusivamente el formato de los tres Java en un ciclo gobernado N+1 con nueva evidencia sin reescribir N; (ii) demostrar el REM-D4 de proceso con visible PASS y AOSP PASS (hoy AOSP FAIL); (iii) identidad/autoría y persistencia PG12 plenamente verificadas; (iv) congelación y recepción/testing reales PG13/PG14. No se sustituyen con fixtures para declarar PASS productivo.
