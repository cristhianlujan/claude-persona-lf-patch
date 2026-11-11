# IG LF — R2–R6 | Checklist de diagnósticos existentes

**Fecha:** 2026-11-07 · **Estado:** AUDITORÍA DE CONTRATO ESTÁTICO / SIN REEJECUTAR DETECTORES / RUNTIME NOT_TESTED.  
**Fuente original desplegada:** `programacion.fn_ig_evo_r2_r6_diagnostics_v1(p_pantalla_id integer,p_run_id bigint)`, MD5 SQL `d0502a31a7c99ff29b0159a65c2f493c`.  
**Motivo:** verificar estructura, limitaciones y transporte del informe **que el Curator ya produjo**, sin forzar una nueva investigación, escritura ni un Validator alternativo.

## Contrato de entrada, ejecución y salida

- **Entrada:** pantalla y RUN explícitos. En la función ya desplegada se valida que el RUN exista, pertenezca a la pantalla, no esté invalidado y tenga exactamente una evaluación `SECURITY`. La lectura de reglas usa `fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE')`.
- **Proceso:** cinco ramas de diagnóstico declaradas en una **misma función**. No existen cinco ejecuciones independientes de R2...R6 que deban repetirse.
- **Salida RAW:** `IG_EVO_R2_R6_DIAGNOSTICS_V1`, `pantalla_id`, `run_id`, `run_source_snapshot_sha256`, `previous_run_id`, comparación de snapshot, `finding_count`, `findings[]` ordenado por detector. Cada finding conserva `detector, family_code, proposal_kind, gap_code, cases[], case_count, affected_entity_count, detector_root_key`.
- **Autoridad:** `canonical_write_authorized=false`, `semantic_quality_evaluated=false`; cada finding `auto_apply=false`, `semantic_pass_authorized=false` y `decision=EVIDENCE_OR_SEMANTIC_REVIEW_REQUIRED`.

## Checklist funcional de cada rama (solo lectura de código)

| Rama | Detecta exactamente | Estado | Lo que NO acredita |
|---|---|---|---|
| **R2** | `ALLOW` versus `DENY` sobre el **mismo control explícito** entre regla y política SECURITY de la misma pantalla | PASS de alcance estático | No detecta contradicciones semánticas generales ni equivale a dictamen independiente |
| **R3** | Referencias de reglas `VIGENTE` hacia reglas `CANDIDATO`, por `_rule_id` o `_rule_code` | PASS de alcance estático | No autoriza promoción de la regla referida |
| **R4** | Reglas con título equivalente y configuraciones diferentes | PASS de alcance estático | `true_duplicate=NOT_PROVEN`; mismo título no justifica merge |
| **R5** | Reglas transversales con `applicability_v1.status != ACTIVE`, agrupadas por `binding_source` y estado del selector | PASS de alcance estático | `global_applicability=NOT_PROVEN`; una agrupación no elimina los detalles: `rule_ids[]`, `rule_codes[]` y `rule_count` siguen presentes |
| **R6** | Riesgos/casos sobre políticas de autenticación y antiabuso, catálogos de amenazas `SECURITY`, referencias `CANDIDATO`, implementación pendiente y falsos `MISSING` | PASS de alcance estático | `risk_confirmed=false`, escenarios `NOT_TESTED`, `implementation_evidence=NOT_PROVEN`; no certifica control servidor ni QA |

## Validaciones tipo checklist

| Control | Resultado |
|---|---|
| Función vigente y firma con identidad RUN+pantalla | **PASS estático** |
| Selección canónica y exclusión de `DERIVED_GLOBAL` en comparaciones que requieren vínculo atestado | **PASS estático** (R5 **reporta** estos vínculos como pendiente de autoridad) |
| Fuente de amenazas desde `input_family_assessments.SECURITY.threat_coverage` del mismo RUN | **PASS estático** |
| Cada resultado conserva `cases[]`, conteos y tipo de propuesta | **PASS estático** |
| Negativas explícitas de promoción/aplicación | **PASS estático** |
| R6 incorpora hipótesis y objetivos positivos/negativos para LOGIN/OTP | **PASS de definición; pruebas reales NOT_TESTED** |
| Snapshots históricos vs actual | **REFERENCIA únicamente**: el detector selecciona RUN anterior `COMPLETED`; equivalencia de snapshot NO autoriza reutilizar RAW entre RUNs |
| Informe RAW ya emitido almacenado individualmente por RUN | **NOT_TESTED / NO ARCHIVO HISTÓRICO ACREDITADO**: RUN 949 no conserva `ig_evo_r2_r6_diagnostics` directamente en assessments ni propuestas. El archivo futuro es candidato en #3694 |
| Calidad semántica y resistencia adversarial de cada finding | **NOT_TESTED**: aplicar controles EKB GOV-032 e IG-M46, no inferir PASS |
| Compilación o ejecución del SQL candidato #3694 | **NOT_TESTED**; las 21 pruebas estructurales anteriores corresponden al contrato Curator, no a R2–R6 runtime |
| Modificación oficial | **NINGUNA**; solo auditoría de fuente y documentación candidata |

## Regla de transporte y reutilización

```text
Curator ejecuta R2–R6 una vez → conserva JSON completo en proposal_materialization
→ archivo inmutable del envelope por RUN (PR #3694, NO desplegado)
→ siguiente lector obtiene SHA + RAW tal cual
→ Validator y consolidación siguen su flujo oficial
→ Perfil al final, nunca antes de estabilizar el contrato upstream
```

En `REBIND` y `NOOP` no reejecutar diagnósticos para rellenar un informe inexistente. Si el RAW del RUN histórico no fue archivado, declarar `NOT_CAPTURED_LEGACY_RUN`; no reconstruirlo ni usar el resultado de otro RUN sin prueba y autoridad.

**Decisión:** revisión estática de R2–R6 **lista para pasar a G1**; no significa que R2–R6 estén funcionalmente verificados ni permite activación productiva. Próximo lote G1: cobertura de raíces atestadas, `DERIVED_GLOBAL`, límite interno 128/512 y profundidad, integridad JSON/hash y scope real frente al inventario completo de la pantalla.

**EKB aplicable:** GOV-010, GOV-032, IG-M46-TRUE-CROSS-FAMILY-RECOVERY-SESSION-001, SEC-011, IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015.
