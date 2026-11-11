# Paso 3 — revisión de diseño, selector experimental por datos

**No desplegar en producción.** Archivos nuevos y modificados solo en `experimental/` y `tests/test_experimental.py`. `original/` y `tests/test_parity.py` no cambiaron.

## Corrección 1: no preseleccionar por nombre

`lf_profile_area_policy_exp` contiene `profile_code` y `areas jsonb`, declarados explícitamente. El selector filtra TODOS los perfiles seleccionables cuyo descriptor está CURRENT, canal PROGRAMACION, entrada DIRECT y área declarada coincide. No se deriva el área del nombre del perfil ni se elige un perfil antes del juicio semántico. `validate_v2_exp` repite `prepare_v3_exp`, exige que el perfil elegido sea candidato y esté autorizado por la declaración de área; no adjudica autoridad de ejecución.

Se agregaron `PERFIL-PROG-BACKEND-SPRING-EXP` (segundo BACKEND) y `PERFIL-PROG-BACKEND-NAME-FRONTEND-EXP` (nombre engañoso, **área declarada FRONTEND**). El runner prueba dos SELECTED válidos y AMBIGUOUS sobre ambos backend, y que el nombre engañoso no ingresa a Java.

## Corrección 2: reglas de ruta por proyecto

`lf_project_area_pattern_exp(project_ref,area,path_prefix)` es la única fuente de reglas. `prepare_v3_exp(literal_request,project_ref,area,paths)` resuelve todas las rutas en esa tabla; rechaza patrones sin coincidencia, rutas con mezcla de áreas y áreas discordantes. Pone `project_ref`, `project_rules` y las rutas en el request. `validate_v2_exp` vuelve a preparar el request y bloquea cambios posteriores a políticas, catálogo o rutas.

Fixtures de dos proyectos:
- `lf_java`: `src/main/java/` BACKEND, `web/src/` FRONTEND, `db/migration/` DATA.
- `lf_python`: `api/app/` BACKEND, `ui/src/` FRONTEND, `alembic/versions/` DATA.

## Comandos para Claude (desde raíz del repositorio)

Usar un PostgreSQL descartable **local**, con base vacía y distinta de la de paridad anterior. Psql debe estar en PATH.

```bash
export SELECTOR_EXP_DISPOSABLE_DB=YES
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_step3'
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/tests/test_experimental.py
```

Después, con otra base recién creada y vacía, verificar regresión independiente:

```bash
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_parity'
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/tests/test_parity.py
```

Registrar HEAD, comandos, salida literal y verificación de cero residuos. **No hay PASS independiente de esta revisión hasta la ejecución por Claude.** No fusionar ni enviar a Cristhian como solución aprobada antes de auditar el dictamen.