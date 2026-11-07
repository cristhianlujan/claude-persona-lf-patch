# IG LF — Checklist de evaluaciones por familia (readback, no aprobación semántica)

**Fecha:** 2026-11-07 · **Estado:** REVISIÓN ESTRUCTURAL COMPLETADA / PASO R1 HABILITADO SOLO PARA AUDITORÍA · **RUN de referencia:** 949, pantalla `B2B-AUTH-001` (id 51).  
**Medio:** SQL SELECT de solo lectura sobre `lf_ops`, sin ejecutar Curator, R1–R6, G1, Validator ni escribir RUN.  
**Límite:** el RUN 949 es histórico; no se acreditó vigencia canónica `fn_input_readiness_run_is_current(949)` ni source readback completo. La migración candidata #3693 sigue DRAFT; **no desplegada**.

## Checklist, entrada → salida

| Control | Resultado | Evidencia observada | Lectura correcta |
|---|---|---|---|
| Contrato de readiness activo | **PASS estructural** | `programacion.contratos`, `INPUT_READINESS_CONTRACT`, id 37, version_id 19, revision `5.13.1`, `defined`, `fail_closed=true` | No presume evaluación semántica |
| Universo por RUN | **PASS estructural** | RUN 949 `family_count=47`, 47 assessments, 47 códigos distintos | No sustituye consulta de vigencia |
| Fuentes explícitas | **PASS de presencia** | 47/47 `source_refs` no vacías; 47/47 hashes Curator con forma SHA256 | No acredita lectura íntegra/autoridad de cada referencia |
| Racional y obligaciones negativas | **PASS de presencia** | 47/47 `rationale` no vacío; 47/47 `negative_requirements` no vacías | No prueba que se hayan ensayado los negativos |
| Cobertura y aplicabilidad | **REPORTAR ESTADOS** | 35 APPLICABLE/COMPLETE; 10 APPLICABLE/PARTIAL; 2 NOT_APPLICABLE | PARTIAL no equivale a COMPLETE |
| Pruebas declaradas *dentro* del assessment | **SIN VINCULACIÓN DIRECTA** | 47/47 `test_obligations=[]`; no afirmar que no existen tests | Ligar test-suite externa por código+familia+RUN es un control distinto, aún no probado |
| Prueba de piso por familia (fuente alternativa real) | **PASS de existencia** | `programacion.fn_input_family_test_floor_check_v1()` = 47/47 familias OK, 300/300 tipos/celdas requeridos-presentes, 0 faltantes, 0 huérfanos | Revisa catálogo `public.lf_test_suite_cases`, no ejecución E2E ni cumplimiento del assessment |
| Validator: identidad vinculada | **PASS estructural** | 47/47 `validator_outcome=PASS`, `validator_identity` presente; 47/47 `execution_mode=INDEPENDENT_VALIDATOR`, `validated_curator_execution_id` coincide con el `execution_id` del Curator y hash SHA referenciado coincide | No demuestra llamada independiente fresca ni calidad semántica |
| Estado implementación/QA/producción | **BLOQUEOS PRESERVADOS** | 20 READY/READY/READY; 20 NOT_READY/BLOCKED/BLOCKED; 4 READY/BLOCKED/BLOCKED; 2 N/A; 1 READY/READY/NOT_READY | Validator PASS no levanta bloqueos de QA/producción |
| Evidencia de propuesta, seguridad y casos adversariales | **NOT_TESTED** | Este lote no ejecutó benchmark positivo/negativo ni evaluador semántico | GOV-032 exige prueba de calidad separada |
| Función de explicación por familia | **PERMISSION_DENIED** | `SELECT programacion.fn_input_explain_family_assessment(949,'SECURITY')` responde SQLSTATE **42501** por falta de EXECUTE | No ampliar GRANT ni inventar recibo; acceso únicamente por vía gobernada |
| Fuente canónica y límites | **PASS de separación** | `INPUT_FAMILY_POLICY_REGISTRY` es contrato en `programacion.contratos`, no una tabla con ese nombre; `fn_input_family_test_floor_check_v1` consume el catálogo vigente | Mantener versión/pin por RUN, no copiar familias fijas |
| RAW emitido y transportado | **NOT_TESTED** | No hay readback nuevo de PR #3693 ni del archivo RAW candidato #3694 en producción | No concluir integridad del informe final ni aplicar migración |

## Lectura de los cinco controles críticos (RUN 949)

| Familia | Cobertura | Implementación | QA | Producción | Validator |
|---|---|---|---|---|---|
| SECURITY | COMPLETE | NOT_READY | BLOCKED | BLOCKED | PASS documental |
| RATE_LIMIT | COMPLETE | NOT_READY | BLOCKED | BLOCKED | PASS documental |
| SESSION | COMPLETE | NOT_READY | BLOCKED | BLOCKED | PASS documental |
| PRIVACY_PII | PARTIAL | NOT_READY | BLOCKED | BLOCKED | PASS documental |
| TESTING_OBLIGATIONS | PARTIAL | READY | BLOCKED | BLOCKED | PASS documental |

**Punto de decisión:** las 47 evaluaciones son suficientes para **continuar una auditoría de solo lectura de R1**, sin requerir nueva investigación histórica. NO autorizan READY global, promoción, escritura de reglas, despliegue ni cierre funcional de la skill.

## Siguiente lote, en orden: R1

1. Inspeccionar definición y contrato actual `fn_ig_evo_r1_parameter_provenance_v1` sin invocarlo sobre un RUN histórico.
2. Validar entradas: pantalla, RUN, fuente y snapshot; diagnosticar alcance real de parámetros.
3. Revisar estructura RAW, evidencias por caso, fuente política y manejo de `NOT_TESTED`/no aplicabilidad.
4. Identificar registro y transporte del informe **ya emitido**, sin reescanear reglas.
5. Dejar los ajustes de R2–R6 y G1 para después de cerrar el checklist de R1, y Perfil al final.

**Gates EKB:** GOV-010 (preflight), GOV-032 (provenance ≠ semántica), SEC-011 (ACL/definer), IG-M46 (cross-family), IG-M107-A3 (selectores canónicos y fallos cerrados).  
**Trazabilidad:** PR #3693 (familias), PR #3694 (Curator e informe original). Ninguno está autorizado a merge/despliegue por este documento.
