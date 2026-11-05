# Paso 3 — Selector experimental por área (candidato, NO productivo)

Se añadieron **solo archivos nuevos** en `experimental/` y `tests/test_experimental.py`.
Las siete funciones originales, `original/` y `tests/test_parity.py` permanecen intactos.

## Contratos experimentales

- `seed_profiles_exp.sql`: PERFIL-PROG-BACKEND-EXP, PERFIL-PROG-FRONTEND-EXP y PERFIL-PROG-DATA-EXP; descriptores de prueba, política DIRECT y canal PROGRAMACION. La existencia del perfil NO confiere permisos de escritura.
- `lf_profile_selector_catalog_v2_exp(text DEFAULT NULL)`: consulta el catálogo original y evalúa cada descriptor de forma individual por canal. Devuelve `blocked_profiles`, `profiles` y `selectable_profile_count`; no usa la barrera global de descriptores para bloquear canales ajenos.
- `lf_profile_selector_semantic_prepare_v3_exp(text, text, jsonb)`: solicitud literal, área BACKEND|FRONTEND|DATA y array de rutas. Reglas: `src/main/java/**` → BACKEND, `web/src/**` → FRONTEND, `db/migration/**` → DATA. Mezcla → `LOTE_MULTI_AREA_BLOCKED`; área sin perfil CURRENT seleccionable → `NO_PROFILE_FOR_AREA`; rutas no clasificadas o incompatibles bloqueadas. Devuelve un `request` experimental solo si está READY.
- `lf_profile_selector_semantic_validate_v2_exp(jsonb,jsonb)`: vuelve a preparar el request para detectar alteraciones/catálogo viejo y verifica binding, SHA del recibo, evidencia, prohibición de autoridad y que el perfil seleccionado corresponde al área determinada.
- `lf_profile_selector_semantic_finalize_v2_exp(jsonb,jsonb)`: helper para construir un resultado con hash de recibo siguiendo el patrón de la función original, y verificarlo usando `validate_v2_exp`.

**Limitación intencional:** para un lote válido solo el perfil experimental de su área queda como candidato. Este gate es anterior a una eventual decisión semántica de IA; no crea worker, Skills productivas ni autoridad de ejecución.

## Ejecución por Claude

Usar una **base vacía y descartable** distinta de la utilizada para `test_parity.py`. Requiere PostgreSQL y `psql`.

```bash
export SELECTOR_EXP_DISPOSABLE_DB=YES
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_step3'
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/tests/test_experimental.py
```

El script verifica opt-in, base local vacía y prefijo de nombre; carga los artefactos originales, prueba las seis referencias originales, añade los perfiles y funciones experimentales, ejecuta rutas positivas y adversariales, repite los **siete** escenarios de validación original sobre PROGRAMACION, comprueba aislamiento de descriptores obsoletos, elimina los perfiles ficticios, vuelve a comprobar 6/6 referencias y finaliza con limpieza de esquemas.

Prueba de paridad original, **sin cambiar** `test_parity.py` (requiere otra base fresca después de la limpieza):

```bash
export SELECTOR_EXP_TEST_DSN='postgresql://postgres:LOCAL_PASSWORD@127.0.0.1:5432/selector_exp_test_parity'
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/selector_experimental/tests/test_parity.py
```

**Estado actual:** código disponible en GitHub para auditoría y prueba; no se declara PASS de Paso 3 o 4 hasta que Claude lo ejecute en PostgreSQL y presente HEAD, comando y salida literal. No ejecutar estos SQL en Supabase.
