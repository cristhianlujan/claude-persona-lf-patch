# LF IG N-4 / G4 — recurrencia EKB preparada para registro gobernado
Fecha: 2026-10-28 · PR #3269 · **EVIDENCIA VERSIONADA / NO PERSISTIDA EN EKB VIVO**.

## Identidad del incidente
**Observación verificable:** un `source_ref` o una decisión `VIGENTE` sobre una regla no constituye prueba de delegación para **ampliar el alcance de su selector**. Igualmente, los campos de autoridad de una política ACTIVE para otra operación (por ejemplo `POL-PROFILE-UPDATE-PASS` con `OWNER_ROLE_ONLY_NOT_HUMAN_DECISION`) no autorizan cambios `INPUT_GOVERNANCE/RULE_APPLICABILITY_CHANGE`.

**EKB canónicos existentes, sin duplicar codigo:**
1. `HUMAN-DECISION-POLICY-RESOLUTION-NO-PRODUCER-AUTHORITY-001`: productor no puede autoproveer clase, rol o autoridad. Registrar como RECURRENCE con evidencia actual G4.
2. `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`: aplicabilidad gobernada y dinámica, sin derivar GLOBAL de marcas. Vincular la misma constatación de falta de emisor competente.
3. Contexto complementario, no nueva recurrencia obligatoria: `HUMAN-DECISION-AUTHORITY-BINDING-NOT-INFERRED-001` e `IG-TARGETED-EVIDENCE-BEFORE-HUMAN-ESCALATION-001`.

## Evidencia directa
- SQL read-only: `sandbox/lf_contract_gate_test/input_governance/ig_g4_source_authority_reuse_negative_regression_20261028.sql`, ejecutado en Supabase vivo, **5/5 PASS**. Cinco reglas `VIGENTE`, cero políticas de autoridad ACTIVE, cero rutas ACTIVE del asunto `RULE_APPLICABILITY_CHANGE`, cero recibos humanos. Una regla Design System sí referencia una decisión VIGENTE, que **no** vincula una autorización específica de modificar selector.
- PASE del commit `9d7e02612b2c1167bb5425ccd7b03bef03807139`: run `40792607372` SUCCESS; `MIGRATION_SOURCE_PARITY=SKIPPED`.
- Fuentes de diseño: `IG_G4_REGISTRY_REUSE_REAL_AUTHORITY_GAP_20261028.md`, `IG_G4_FUENTES_COMPETENCIA_INSPECCION_CANONICA_20261028.md`, EKB vivo de las dos entradas mencionadas.

## Contenido de recurrencia
- **Descripción:** riesgo de promoción indebida de aplicabilidad por reutilizar autoría, decisión de negocio o etiqueta de dueño de un flujo ajeno como autoridad para modificar el scope de otra regla.
- **Causa raíz:** falta binding exacto y verificable `rule_ref+rule_version+operation+approved_scope+consumer+issuer+policy_version`. El registro central existe, pero ninguna ruta activa del asunto de cambio de scope admite una delegación real.
- **Prevención:** fuente competente y policy versionada de origen consultadas por lector gobernado; recibos auténticos del registro `private.lf_human_decision_*`, currentness, revocación y veto; nunca usar campos del proponente como autoridad, ni activar una ruta genérica o atribuir un rol global a todas las reglas.
- **Validación:** negativos G4 5/5 PASS (detección de HOLD); positivos sintéticos de contrato separados de cualquier aprobación real. Los selectores preexistentes no se revocan; la protección es **forward-only** para cambios futuros.
- **Evidencia:** `github://cristhianlujan/claude-persona-lf-patch/pull/3269`; `github://cristhianlujan/claude-persona-lf-patch/actions/runs/40792607372`; `sandbox/lf_contract_gate_test/input_governance/ig_g4_source_authority_reuse_negative_regression_20261028.sql`.

## Aplicación pendiente, no suplantada
El writer canónico es `public.lf_write_pipeline_ekb_v1(p_operation_code,p_error,p_execution_id)` y exige contrato `PRE_EKB_GATE` activo, `execution_id` legítimo, procedencia y recibo. El acceso actual a Supabase es **solo lectura**. No se invocó el writer, no se aumentó `frecuencia`, no se creó un EKB nuevo ni se simuló un recibo. El owner del carril `ESCRITURA_BASE_CONOCIMIENTO_LF` debe registrar la recurrencia por ruta gobernada cuando exista operación real, y confirmar readback exacto. No usar una operación ajena para forzar la escritura.

**Estado EKB live: PENDING_GOVERNED_WRITE.** Estado diseño G4: HOLD_AUTHORITY para nuevas ampliaciones. Ningún cambio de producción, EKB, roles o selectores.
