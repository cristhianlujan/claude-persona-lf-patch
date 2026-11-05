# ROLES + STACK SKILLS — sandbox de Programación LF

**PR experimental #3672**, encima del PR #3667. Todos los artefactos se mantienen en `sandbox/`. **Estado: CANDIDATE_SANDBOX_ONLY / no producción**; runtime desactivado, promoción prohibida y sin autoridad de escritura.

## Separación obligatoria

**ROLES:** `prog_backend_exp`, `prog_frontend_exp`, `prog_data_exp`. Cada uno conserva los 23 archivos de `profiles/_template` más `contracts/runtime_binding.json`. Los SKILL.md y contratos de los roles no incorporan Spring, Angular, Flyway, FastAPI ni otra tecnología. Solo vigilan área, alcance exacto PG-05 C2, pruebas visibles, ausencia de invención, falta de información y autoridad. Los ejemplos de rutas son genéricos.

**CONOCIMIENTO:** `stack_skills_exp/{springboot_exp,angular_exp,flyway_exp,fastapi_exp}/` (cada skill incluye SKILL.md, contracts/, examples/ y evals/). El conocimiento técnico está en esas skills, que citan documentación oficial. No puede seleccionarlas el modelo por palabras clave.

**VÍNCULO DEL PROYECTO:** `stack_skills_exp/project_stack_binding_exp.sql` crea una tabla **solo local** `public.project_stack_binding_exp(project_ref,area,skill_code,skill_sha256)`. Los datos de `project_stack_binding_fixtures.json` especifican `lf_java/BACKEND→SPRINGBOOT_EXP`, `lf_java/FRONTEND→ANGULAR_EXP`, `lf_java/DATA→FLYWAY_EXP`, `lf_python/BACKEND→FASTAPI_EXP`, además del proyecto de prueba `bridge_fixture/BACKEND→SPRINGBOOT_EXP`. No hay vínculo `lf_python/FRONTEND`. `seed_local_binding_table` calcula el SHA-256 **exacto del SKILL.md** y almacena la fila en la base desechable. `read_sql_binding` consulta **la tabla**, rechaza filas ausentes, skill de otra área y discrepancia entre hash almacenado y archivo.

## PG-07 — tarea visible para Worker v0.8

El puente, que permanece candidato, ahora exige `role`, `skill` y la fila de binding. El campo `worker_spec.functional_contract.role_and_stack` incluye el texto e identidad del **rol genérico**, el texto e identidad de la **skill del proyecto**, y sus SHA-256. Se envía ese mismo WorkerTaskSpec al productor PG-07 C2 real, que verifica el formato visible sin abrir el oráculo. La proyección de tarea y el recibo **candidato**, NO auténtico, encadenan `profile_sha256` y `skill_sha256` con el SHA de asignación. No hay despacho ni parche.

**Estándares PG-00:** solo se hallaron las referencias a familias `STD-BE`, `STD-FE`, `STD-DB` en el archivo fuente `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`. **Ese archivo no contiene el texto normativo completo de las tres familias.** Por eso `pg00_catalog_sources_exp.json` fija las referencias verificadas, `pg00_source_status` devuelve `PG00_STANDARD_TEXT_UNAVAILABLE` y no se afirma que haya normas L1/L2 resueltas. Las skills incluyen conocimiento de sus **fuentes oficiales**, separado de estándares LF. **No permitir una ejecución real hasta conseguir el catálogo normativo versionado con contenido y huellas.** No sustituirlo por suposiciones.

## Ampliación — múltiples skills versionadas, prioridad y criterio experto

La tabla local `project_stack_binding_exp` incorpora `skill_version` y `priority`, con clave de identidad `(project_ref,area,skill_code,skill_version)`. Una combinación proyecto/área puede tener varias filas. El orden es determinista: **prioridad 1 primero**, los demás números crecientes después; no se pierden las skills secundarias. Sin prioridad o con dos filas de igual prioridad, **BLOCK**. Una versión inexistente para un código vinculado produce `SKILL_VERSION_MISMATCH`. Cada fila se comprueba contra el hash del `SKILL.md` de esa versión.

Caso `lf_java/BACKEND`: `SPRINGBOOT_EXP@3` prioridad 1 y `KAFKA_EXP@3` prioridad 2. Ambos contenidos pasan a `WorkerTaskSpec.functional_contract.role_and_stack.skills` con versión, orden, SHA y por lo menos **tres reglas expertas identificadas por ID, texto exacto y fuente oficial**. El primario se conserva para compatibilidad del puente anterior, pero no descarta Kafka. `skill_set_sha256` fija orden e identidades; PG-07 lo incorpora junto al SHA de rol y las skills en tarea y recibo **candidato**, sin autorizar ejecución.

Reglas expertas versionadas en `stack_skills_exp/*/contracts/expert_rules.json`, sincronizadas con su `SKILL.md`:
- **Spring Boot @3:** controller/service/repository, DTO vs entidad, Bean Validation, @ControllerAdvice/@ExceptionHandler, @Transactional, @WebMvcTest, @DataJpaTest y @SpringBootTest.
- **Angular @1:** componentes, signals, semántica y accesibilidad, teclado/foco, pruebas de componentes.
- **Flyway @1:** migraciones versionadas, validate/checksum, riesgos de pérdida, límites de Undo y rollback compatible.
- **FastAPI @1:** dependencias, response_model, excepciones HTTP, TestClient/pytest, override/limpieza de dependencias.
- **Kafka @3 (adicional):** particiones y orden, idempotencia, offsets/consumer groups, compatibilidad de mensajes y recuperación.

Cada skill tiene ejemplo `good_output.json`, `bad_output.json` y evals. `validate_visible_skill_rules` rechaza una tarea con menos de tres reglas distintas o una regla con texto/fuente alterados. Los tests locales y el puente PG-07 real agregan negativos para prioridades, versiones y reglas.

**Bloqueo normativo sin cambios:** el texto completo de STD-BE, STD-FE, STD-DB no está disponible en la fuente verificada; mantener `PG00_STANDARD_TEXT_UNAVAILABLE`. Las reglas técnicas oficiales de stack **no** sustituyen L1/L2 de LF.

## Comandos para Claude

Desde la raíz del repositorio, en el checkout del HEAD auditado:

```bash
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/programmer_profiles_exp/test_profile_packs.py
```

Este test usa productor real PG-07 C1/C2 con entradas candidatas; evalúa cada pack, fuente de la skill, Backend con dos proyectos y tres negativos de binding. No ejecuta Worker.

Para paridad del puente y consultas SQL de binding, con PostgreSQL **localhost** desechable y base **recién creada, vacía**:

```bash
export SELECTOR_EXP_DISPOSABLE_DB=YES
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_role_stack'
export PROFILE_CANDIDATE_HEAD_SHA="$(git rev-parse HEAD)"
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/integration/test_pg04_pg07_selector_bridge_v1.py
```

Repetir `test_experimental.py`, `test_parity.py` en bases frescas y la regresión PG-04…PG-14. Cero residuos al finalizar. Claude aportará salida literal, comando, HEAD y bloqueantes. **No declarar PASS de este HEAD antes de la ejecución independiente.**

## Fronteras

No modificar `profiles/` ni `skills/` productivos, original/, test_parity.py, funciones `_exp_`, Supabase, Análisis, Testing ni main. El resync del descriptor original usa alias `profiles/` exclusivamente en la DB local por la restricción de elegibilidad del selector; la fuente verdadera y su SHA están en el descriptor. No implica registro productivo, legitimidad de source_ref ni instalación.

## Corrección de rutas canónicas (auditoría Worker @298307e)

Todos los perfiles expresan el directorio protegido completo como `tests/protected/**`, **nunca** `tests/protected/`. La barra final no es canónica según `canonical_relative_path` del Worker real. `pack_validation_common.py` valida los patrones y el caso `NON_CANONICAL_PATH` comprueba que `tests/protected/` se bloquea sin normalizarlo. Esta prueba es adicional a los seis casos existentes y no reemplaza al parser real del adaptador.
