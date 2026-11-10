# Puente experimental PG-04 → PG-07 (candidato, sin autoridad)

**Base exacta:** PR #3666, HEAD `6c91b6fed5d7f1c69c531b12fb076be78c3d66e1`.  
**Alcance:** únicamente esta carpeta `integration/`. `original/`, `test_parity.py`, el selector productivo y los productores PG-04 a PG-14 se dejan intactos.

## Conexión y límites

- **PG-04, declaración por lote:** `declare_pg04_areas` recibe el sobre candidato real `PG04_TO_PG05_EXIT_CANDIDATE_V1`, una declaración por `solution_id`, `project_ref` y la política de rutas del proyecto. Exige cobertura completa, una sola área y no permite inferir el área del nombre de un perfil. Ante mezcla o conflicto responde `LOTE_MULTI_AREA` o `LOTE_ROUTE_CONFLICT`; **no divide automáticamente**. La salida es un *overlay* separado con digest, no un cambio al productor PG-04 ni una admisión.
- **Después de PG-05 C2:** `pg04_area_lot` verifica los digests del paquete PG-04 y `PG05_C2_WRITE_SCOPE_RESOLUTION_CANDIDATE_V1`. Exige que el `write_resource_keys` resuelto sea una lista **exacta de REPO_PATH**, sin DB_OBJECT, sin glob ni rutas fuera del alcance. Genera un lote congelado con área, rutas, política de proyecto y SHA de C2.
- **Puente PG-05:** `assign_pg05` llama a `prepare_v3_exp`, acepta el borrador fijo del modelo solamente como **entrada no confiable**, y llama a `finalize_v2_exp`. Sólo `VALID + SELECTED` produce `PG05_PROFILE_ASSIGNMENT_BRIDGE_V1`; `AMBIGUOUS` y `NO_MATCH` resultan en `REQUIRES_HUMAN_DECISION`. Incluye digests del request, result, catálogo, lote y C2; `production_authority=false`. No hay invocación de IA real.
- **PG-06:** `pg06_currentness` reejecuta el prepare de SQL con el mismo proyecto/área/rutas, compara el request completo (incluyendo perfil/descriptor, catálogo y patrones), reproduce la validación del resultado y rechaza cualquier diferencia; protege contra recomputar el hash de autoridad inyectada.
- **PG-07:** `pg07_worker_projection` prepara un *overlay candidato* para una tarea visible del Worker con `profile_code`, `profile_assignment_sha256`, `write_scope` idéntico a los REPO_PATH de C2 y la huella del spec. Verifica que `write_path_patterns` no excedan ese scope y encadena un `receipt_link_candidate` al hash de asignación. **No genera un recibo Worker verdadero** ni modifica `fn_agent_task_worker_spec`, ejecuta el Worker o habilita dispatch.

Los contratos originales contienen explícitamente `CANDIDATE_NOT_ADMITTED`, `production_authority=false` y `handoff_allowed=false`. Este puente conserva ese estado; no suple las aprobaciones, atestaciones ni revisiones que faltan para la cadena productiva. La política de rutas se toma de la copia experimental de PostgreSQL; ninguna consulta escribe en Supabase.

## Corrección posterior a auditoría de Claude (#3667)

En el HEAD previo `ecf2917`, Claude observó 19 PASS seguidos de un fallo: un borrador con `production_authority` no era rechazado antes de finalizar. Este HEAD aplica las siguientes correcciones:

1. **Modelo estrictamente no confiable:** `assign_pg05` acepta exactamente `decision`, `selected_profile_code`, `ambiguous_profile_codes`, `reason`, `evidence_refs` y `material_ambiguities`. Cualquier clave adicional o ausencia → `BLOCKED / MODEL_DRAFT_FIELD_FORBIDDEN` antes de `finalize`. Cuatro tests inyectan `production_authority`, `route_authority`, `write_scope` y una clave desconocida, con un `finalize` centinela que falla si se invoca.
2. **Productores verdaderos en el arnés:** la prueba importa `build_chain` de `pg05_target_binding_candidate/tests/test_pg05_chain_c1_c5_v1.py`, que llama a `assemble_pg04_exit_candidate` y a `prepare_pg05_c1`/`prepare_pg05_c2` (más la cadena existente). Ya no fabrica sobres PG04/C2 manuales. Los tokens/rutas L3 son **fixtures fuente de ese productor** (`src/SOL-*/...`); el proyecto descartable `bridge_fixture` declara reglas de ruta para esos paths. Un sobre C2 alterado sin actualizar digest se bloquea. **No se afirma autenticidad productiva**: las entradas aguas arriba de esos productores siguen siendo fixtures.
3. **PG-07 real C1/C2:** la prueba ejecuta `prepare_pg07_c1` y `prepare_pg07_c2` desde `pg07_worker_candidate/tools/`. Un spec completo V2 debe ser aceptado por ambos productores; el oráculo oculto debe ser rechazado por C2. El overlay PG07 requiere digest válido de C2 y coincidencia exacta de `worker_visible_task_spec` y `worker_task_spec_sha256`. Para ejercitar C1 se usa un sobre PG06_C5 **sintético no atestado**, explícitamente marcado como fixture; esto no demuestra admisión PG06 ni validez de una tarea Worker productiva.

**Estado:** correcciones implementadas, pendientes de nueva ejecución independiente. La evidencia previa de 19 PASS + fallo **no** se reinterpreta como PASS de este HEAD.

## Pruebas

`test_pg04_pg07_selector_bridge_v1.py` carga el selector original y los datos experimentales en una base vacía `selector_exp_test_*`, usando el mismo `guard` del experimento. Requiere `SELECTOR_EXP_DISPOSABLE_DB=YES`, host de loopback y base sin objetos de usuario. Verifica regresión JSON original 6/6, PG-04 un área, mezcla, conflicto, PG-05 alcance exacto, 2 backend SELECTED, AMBIGUOUS/NO_MATCH humanos, frontend para Java bloqueado, autoridad re-hasheada bloqueada, PG-06 cambios de descriptores/áreas/rutas y asignación manipulada, PG-07 aceptación por los productores reales C1/C2, rechazo de oráculo, tarea y recibo encadenados, scope extra rechazado, cero residuos.

**No se declara PASS de estas pruebas:** corresponde a Claude ejecutar y guardar HEAD, comando y salida literal.

```bash
export SELECTOR_EXP_DISPOSABLE_DB=YES
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_pg04_pg07'
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/integration/test_pg04_pg07_selector_bridge_v1.py
```

Para la paridad original en **otra base fresca**:

```bash
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_parity'
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/tests/test_parity.py
```

Claude debe ejecutar **además** la regresión vigente de PG-04 a PG-14, usando los tests propios de cada etapa y sus fixtures; esta prueba de puente no afirma sustituir ese conjunto ni ejecutar un Worker real.

## Pendientes antes de integración real

1. Probar estos overlays contra los *paquetes genuinos* producidos por PG-04 y PG-05 C2, no solo sobres de ensayo construidos con sus esquemas.
2. Verificar autenticidad de los sobres y reglas de proyecto con fuentes externas; un digest calculado por el mismo llamador no autentica origen.
3. Conectar en una rama gobernada, posterior a los gates de admisión y ejecución. **NO_GO producción, fusión o Worker real con la evidencia de este sandbox únicamente.**
