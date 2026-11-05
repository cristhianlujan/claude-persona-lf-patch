# Tres perfiles programadores de ensayo — SIN activación

**Estado de cada paquete:** `CANDIDATE_SANDBOX_ONLY`; `runtime_enabled=false`; `promotion_allowed=false`. No crea perfiles en `profiles/`, no toca Supabase y no ejecuta Worker, modelo, parches, commits ni PRs.

## Origen y límites

Se conserva la lista de **23 archivos** exigidos por `profiles/_template/validators/validate_pack.py`, más `contracts/runtime_binding.json` por perfil. La arquitectura del pack toma `skills/profile_creator/SKILL.md` y `profiles/ui_architect` como referentes de profundidad y de un gate temprano. La salida canónica **no** es código ni el resultado del Profile Creator: es la **especificación visible V2** que consume `cristhianlujan/programming-agent/docs/WORKER.md` y que debe pasar el productor real `pg07_worker_candidate/tools/pg07_c2_task_batch_projection_v1.py`.

| Pack | Área | Enfoque | Referencia al catálogo PG-00 |
|---|---|---|---|
| `prog_backend_exp` | BACKEND | Java/Spring, capas y API REST | `STD-BE` |
| `prog_frontend_exp` | FRONTEND | Angular, componentes, estados, accesibilidad | `STD-FE` |
| `prog_data_exp` | DATA | Flyway, migraciones reversibles y sin pérdida de datos | `STD-DB` |

**Fuente de gobernanza PG-00:** `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql` y catálogo versionado que gobierna PG-00. Estas referencias son familias, **no sustituyen la lectura de cada estándar vigente**; sin texto/versión actual y política L3 no se autoriza al Worker a escribir. No se inventan obligaciones específicas de STD-BE/FE/DB.

## Contrato Worker

`schemas/output.schema.json` exige la especificación visible de Worker v0.8: `context_path_patterns`, `write_path_patterns` y `files_expected` iguales a las rutas exactas del lote; `protected_path_patterns` para pruebas protegidas; `required_tests` y `acceptance_commands` no vacíos; HEAD y snapshot; recursos máximos positivos; `allow_deletions=false`. Ni la especificación ni el modelo reciben `hidden_oracle_ref`, `hidden_oracle_sha256`, `oracle_envelope` o autoridad. Las rutas de prueba protegidas quedan fuera del write scope.

## Descriptor source-first

`selector_descriptor_from_skill.py` extrae `PROFILE_SELECTION_DESCRIPTION`, `PROFILE_SELECTION_EVIDENCE_KIND`, `PROFILE_SELECTION_EVIDENCE_SECTION` y `DECLARED_AREA` del SKILL.md real de cada pack. En PostgreSQL **exclusivamente local y desechable** llama a la función original `lf_profile_selector_descriptor_sync_v1` con `source_kind=GITHUB_SKILL`, URL y commit exactos. Esto reemplaza en el ensayo los descriptores de `PERFIL-PROG-BACKEND-EXP`, `PERFIL-PROG-FRONTEND-EXP` y `PERFIL-PROG-DATA-EXP`. El perfil BACKEND-SPRING y el de nombre engañoso permanecen únicamente como contrapruebas heredadas para que los negativos del puente #3667 no pierdan cobertura.

## Comandos para Claude

Desde el checkout exacto de este PR:

```bash
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/programmer_profiles_exp/test_profile_packs.py
```

El comando anterior ejecuta los tres validadores, **6 evaluaciones por perfil** (positivo, fuera de lote, pruebas vacías, exposición del oráculo, otra área, autoridad inyectada) y alimenta la **especificación visible de cada pack** al productor real PG-07 C2; no necesita PostgreSQL.

Regresión del puente #3667 con resync original del descriptor, en una base local fresca y vacía:

```bash
export SELECTOR_EXP_DISPOSABLE_DB=YES
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_profile_bridge'
export PROFILE_CANDIDATE_HEAD_SHA="$(git rev-parse HEAD)"
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/integration/test_pg04_pg07_selector_bridge_v1.py
```

Repetir `test_experimental.py`, `test_parity.py` y regresión existente PG-04…PG-14 en **bases nuevas** donde aplique. Registrar HEAD exacto, comando, salida literal, cero residuos y cualquier bloqueo. No usar DSN de Supabase.

## Límites de calificación

El validado local estructural no es `DEPTH_READY_FOR_SEMANTIC_REVIEW` ni aprobación independiente. El validador general de Profile Creator fue construido para el **sobre de creación de perfiles** (`status`, `evidence_map`), mientras este `schemas/output.schema.json` es deliberadamente un **WorkerTaskSpec V2**; no sustituir uno por otro ni alegar que pasó el gate de Creator sin un artefacto de creación específico. El sandbox mantiene todo el tiempo `production_authority=false`, Worker no invocado, y promoción bloqueada.
