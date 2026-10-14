# Profile Updater — composición adaptativa, ruta única candidata

**Estado:** `CANDIDATE_SOURCE_ONLY`. Este PR no habilita runtime, escritura de perfiles, registro de métodos ni producción.

## Arquitectura reconciliada

`PROFILE_ASSESSMENT v1` → `CAPABILITY_SELECTOR v2` (reutiliza `CAPABILITY_SELECTOR v1`) → `plan_profile_evolution.py`. No existe un segundo consumidor/compositor: `profile_method_composition_v1.py` y su test sintético quedaron retirados del PR.

- Fuente de métodos: `sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json` (catálogo **candidato de repositorio**, no una autoridad Supabase vigente verificada).
- El selector v1 canónico permanece intacto; su blob SHA era `d0624beacb1ee68b349bfa23a274b52c92d1c9aa` al preflight.
- `CAPABILITY_SELECTOR v2` compone por señales del assessment, método, precondiciones, referencias de evidencia y presupuesto; no usa el ID del caso para decidir.
- Las referencias `precondition_evidence` y `method_evidence` salen de `assessment_payload`; el planificador las transmite al v2. **No** constituyen atestación independiente. Método sin precondiciones o evidencia = no elegible, pero no bloquea otras capacidades aplicables.
- Las capacidades compatibles solo se añaden si aparecen en el catálogo de capacidades con estado AVAILABLE; la salida es asesoría sin permisos de ejecución.
- La composición con lista vacía es permitida si la evaluación demuestra que no necesita opciones; vacío por ausencia de información no prueba suficiencia. El contrato de NO_ADDITIONAL_CAPABILITY_NEEDED debe mantenerse en la evaluación final.

## Pruebas

`python skills/profile_creator/evals/test_profile_evolution_reconciliation_v1.py`

Prueba ruta local con el registro JSON candidato, `PROFILE_ASSESSMENT` y el planificador; controles positivos/negativos: precondición ausente, evidencia ausente, presupuesto insuficiente/inválido, registro alterado, duplicidad, 12 patrones y separación de autoridad.

Durante la reconciliación se ejecutaron 10 tests de lógica y 3 de planificación localmente, empleando copias byte-exactas de `capability_selector_v1.py`, `capability_selector_v2.py`, `profile_assessment_v1.py` y `plan_profile_evolution.py` (SHA Git blob coincidentes). Los 13 pasaron. El archivo de prueba del PR fue añadido para replay; su ejecución mediante Train/CI no queda declarada hasta observar recibos reales.

## Pendientes para integración operativa

1. Resolver fuente/versión/revisión de `METHOD_PACK_REGISTRY` en Supabase. La existencia del JSON de GitHub no equivale a registro gobernado.
2. Resolver evidencia y fuentes reales de `PROFILE_ASSESSMENT`; una referencia sintética o una bandera declarada por caller no valida procedencia.
3. Ejecutar el paquete en Train y comprobar proyecto/candidato, source projection, readback y pruebas de regresión antes de pasar de draft.
4. Conservar `INDEPENDENT_ASSURANCE` y demás aprobaciones existentes; no inferir PE10_C3 PASS de una prueba de selector.
