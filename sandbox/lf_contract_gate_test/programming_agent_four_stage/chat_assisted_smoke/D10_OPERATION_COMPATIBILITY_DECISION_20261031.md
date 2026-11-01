# D10 — Dictamen de compatibilidad PIP-1 / operaciones LF (Paulo)

**Fecha:** 2026-10-31. **Estado:** AUDITORÍA SOLO LECTURA; SIN GO OPERACIONAL.

## Resultado central

El candidato `pip1_operation_preflight.py` (PR #3402) compara un RunContract PIP-1 con un *manifiesto propuesto* dentro de `public.lf_operation_execution`. **No es el contrato real de persistencia de Carril D**. Su requisito `operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'` no demuestra que el plan PIP-1 deba usar esa operación. Tampoco se debe sustituir silenciosamente por `ORQUESTACION_PIPELINE_LF`.

## Consultas reales de Supabase RO

- Existe `public.lf_operation_execution`; `ORQUESTACION_PIPELINE_LF` aparece con **159** registros.
- No se encontraron ejecuciones para `CIERRE_CHECKPOINT_INGENIERIA_LF` en la consulta de código exacto.
- `programacion.engineering_checkpoint_closure_providers_v1` tiene un ejemplo ajeno: plan `IG_CURATOR_VALIDATOR_REFACTOR_V2`, checkpoint `NEW_RUNS_VNEXT`, estado `CANDIDATE`, provider `fn_ig_m105_cp2_closure_proof_v1`.
- **0** bindings de proveedores de cierre para `PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1` (lectura anterior).
- El núcleo puro de Carril D `RunContract` no implementa un writer de `lf_operation_execution`, y su `operational=True` sigue bloqueado.

## Prohibición de inferencias

1. `159` operaciones genéricas de orquestación no equivalen a `159` runs PIP-1.
2. La existencia de una operación de cierre no acredita la capacidad de cerrar PG.
3. Que el preflight local pase tests de fixtures no valida el código de operación propuesto.
4. No crear tabla nueva, cambiar `operation_code`, o inventar campos de manifiesto sin identificar autoridad contractual.

## Decisión sobre el PR #3402

- **Mantener Draft**, revisión pendiente.
- Clasificar `pip1_operation_preflight.py` como **SYNTHETIC_SHAPE_EXPERIMENT_ONLY**, no como integración operativa ni blueprint aceptado.
- Seguir usando los adaptadores de consulta exclusivamente para observación, sin elevar `DONE` a `SUCCEEDED_ACCREDITED`.

## Dependencia exacta para GO

Carril D/autoridad LF debe aportar o identificar:
- Código de operación/capacidad autorizado para PIP-1.
- Source of truth de `run_id` y `execution_id` y su vínculo verificable.
- Manifest versión/scheme y pins: HEAD, digest completo del inventario, contrato y catálogo.
- Writer, persistencia y lectura independiente del recibo por checkpoint, sin reuso de PASS.
- Conjunto de negative tests de drift, suplantación y replay.
- Revisión independiente + PASE exact-HEAD antes de habilitar efectos.

## Ruta recomendada

Confrontar la rama de Carril D, los contratos en main y el owner de gobernanza **antes de programar el runtime**. Después hacer un único conector en torno al mecanismo escogido, no otro orquestador.

**Ninguna escritura SQL, merge, activación, ni checkpoint DONE en este corte.**
