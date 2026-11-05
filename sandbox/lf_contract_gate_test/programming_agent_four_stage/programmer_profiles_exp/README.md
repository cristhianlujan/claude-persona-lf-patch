# Tres perfiles de programación — ensayo sin runtime

Estado: **CANDIDATE_SANDBOX_ONLY**, sin creación de activos en Supabase ni archivos dentro de `profiles/`.

## Fuente y estructura

Cada pack (`prog_backend_exp`, `prog_frontend_exp`, `prog_data_exp`) replica los **23 archivos** de `profiles/_template` (mismas subcarpetas y rutas), con dos archivos adicionales: `runtime_binding.json` y `evals/run_cases.py`. Las convenciones de `skills/profile_creator/SKILL.md` y la profundidad de `profiles/ui_architect` inspiran el gate JSON, contratos, validators, jueces y evals.

El pack produce **solamente una especificación visible estricta WorkerTaskSpecV2 (27 claves exactas)**, nunca código, patch ni recibo de ejecución. En `schemas/output.schema.json` se exige el shape V2 consumible por `pg07_worker_candidate/tools/pg07_c2_task_batch_projection_v1.py` y la coincidencia exacta de `write_path_patterns` con el lote, protección de tests, aceptación visible y límites. Se excluye todo oráculo oculto.

Fuentes verificables:
- `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`: origen del plan PG-00, C3 catálogo versionado, C6 skills por stack.
- `sandbox/lf_contract_gate_test/programming_agent_four_stage/pg07_worker_candidate/PG07_C4_CONTRACT_FIRST_STANDARDS_20261103.md`: contrato primero y necesidad de fuente C6 vigente.
- `skills/profile_creator/SKILL.md`: profundidad y validación de candidato.
- `cristhianlujan/programming-agent/docs/WORKER.md`: Worker v0.8 y aislamiento obligatorio del oráculo.

Las familias STD-BE/STD-API, STD-FE y STD-DB se **referencian**, no se reconstruye contenido ni se atribuye un ID concreto/version que no se haya leído del catálogo C6 vigente. `standards_catalog_resolved=false` mantiene el bloqueo de promoción.

## Comandos de Claude

Desde la raíz del checkout:

```bash
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/programmer_profiles_exp/run_all_profiles.py
```

Cada pack ejecuta su `validators/validate_pack.py` (positivo estructural, rutas, limites) y `evals/run_cases.py` con los seis casos: positivo, fuera de lote, pruebas vacías, oráculo, otra área y autoridad inyectada. Son 18 evaluaciones.

**Limitación de compatibilidad de source binding:** la función original `lf_profile_execution_source_eligibility_v1` considera elegibles únicamente entradas cuyo `metadata.repo_path` tiene la forma `profiles/<slug>`. Este ensayo no crea esas carpetas. Para reproducir la ruta de resync en PostgreSQL descartable, el adaptador declara un **alias virtual** `profiles/<slug>` dentro de los registros ficticios y deja en `source_ref` la ruta verdadera de `SKILL.md` en sandbox con el sufijo `LOCAL_VIRTUAL_ALIAS`. Esto prueba semántica de descriptor y compatibilidad del selector, **no prueba la procedencia real de un perfil en `profiles/` ni autoriza su registro**.

El puente #3667, modificado **solo en el nuevo PR apilado**, tras cargar los fixtures `_exp_` usa `integration/profile_pack_selector_fixture.py` para leer las secciones Purpose de los tres SKILL.md y pasarlas a **la función ORIGINAL `lf_profile_selector_descriptor_sync_v1` en PostgreSQL local desechable exclusivamente**. No escribe en Supabase. Reemplaza los tres descriptores simulados por descriptores derivados del pack; otros perfiles experimentales (Spring y nombre engañoso) siguen siendo fixtures de las pruebas de clasificación. El selected backend produce un JSON de este pack que debe ser validado tanto por el validador propio como por los productores reales PG-07 C1/C2.

En una base vacía distinta, prefijo `selector_exp_test_*`, bajo loopback:

```bash
export SELECTOR_EXP_DISPOSABLE_DB=YES
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_profiles'
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/integration/test_pg04_pg07_selector_bridge_v1.py
```

Después repetir `tests/test_experimental.py` y `tests/test_parity.py` en **bases frescas separadas**, más la regresión PG-04→PG-14. No se cambian los tests originales ni las funciones `_exp_`.

## Límites de esta evidencia

Un pack válido es **un candidato de especificación**, no un agente que programa, no un Worker invocado y no un perfil activo. El ejemplo `profile_assignment_sha256` es sintético y se reemplaza por el digest de asignación del ensayo. La admisión PG-07, reglas C6 actuales, revisión semántica y promoción son decisiones posteriores, no resultados de este PR. Registrar HEAD, comando, PASS/FAIL literal y cero residuos antes de cualquier propuesta adicional.

**Shape estricto verificado contra fuente:** `cristhianlujan/programming-agent/src/programming_agent_runner/worker_task_spec.py` (`_REQUIRED_KEYS` y `_parse`). Este módulo rechaza campos extra; por ello `profile_code` y `profile_assignment_sha256` son metadatos del overlay de PG-07, **no** campos de `schemas/output.schema.json`.
