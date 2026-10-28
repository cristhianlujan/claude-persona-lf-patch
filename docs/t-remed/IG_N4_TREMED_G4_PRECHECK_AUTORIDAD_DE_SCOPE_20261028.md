# LF IG — G4: prechequeo del contrato existente de decisiones (solo lectura)

**Estado:** EXPLORATORIO / G4 PENDING / NO HUMAN APPROVAL / NO RECLASSIFICATION. Fecha: 2026-10-28.

## Evidencia verificada

La base contiene `programacion.human_decisions` (`execution_id`, `head_sha`, `actor_identity`, `approval_ref`, `authority_receipt_id`); `programacion.authority_attestations` (`authority_role`, `head_sha`, desafío y prueba); y `lf_ops.system_audit_human_decisions` (`campaign_id`, `work_id`, `finding_id`, `question`, `options`, `decision_value`).

Los triggers `programacion.fn_guard_human_decision` y `programacion.fn_guard_human_decision_authority_receipt` **se vinculan a `execution_id`**. Se verificaron las definiciones y hashes, no su aptitud funcional para autorizar la expansión de una regla:
- `fn_guard_human_decision`: MD5 `bbf0ce4fbe4a8fa72478b01cd5c1c9a6`.
- `fn_guard_human_decision_authority_receipt`: MD5 `d26263461214739da86ae76914fabdf2`.

Una migración existente de IG sobre **release** identifica `human_authority_scope=INPUT_GOVERNANCE_EXACT_RELEASE`; **esa autoridad de liberación no prueba autorización de alcance de regla**.

## Prueba de reutilización antes de diseñar otra tabla

1. Identificar registro canónico de `owner` y su delegación para el ámbito **de una regla específica**; no presumir que el aprobador de un release lo es de cualquier regla.
2. Verificar si el registro existente puede ligar `rule_ref + rule_definition_hash + applicability_selector_hash + consumer + evidence_refs + expiry/revocation` sin violar su finalidad o permisos.
3. Verificar si la autoridad competente para Seguridad/Legal puede objetar y si el veto es validado antes de publicar.
4. Registrar aceptación/denegación/condiciones y readback ligados a un HEAD verificable. No atribuir decisiones a actores inexistentes.
5. Si ninguno de los registros existentes tiene ese contrato, documentar **MODEL_GAP/AUTHORITY_BINDING_GAP**, evaluar la extensión mínima del mecanismo ya existente y nuevas pruebas; no crear un motor gerencial independiente.

## Contrato conceptual de la ficha de aprobación

`rule_ref`, `rule_sha`, `selector_sha`, `authority_ref`, `owner_role`, `competence_scope`, `negative_examples_sha`, `evidence_refs`, `decision_type`, `conditions`, `validity`, `actor_identity`, `receipt_ref`, `approval_status`.

**Sin verificación de esa vinculación: HOLD del cambio de alcance**. La gerencia no autoriza por conversación ni por score; no se altera ninguna regla o selector. Un selector previamente gobernado puede seguir aplicando a destinos compatibles mientras su fuente y versión sigan vigentes; esto no concede nuevas excepciones.

**G4 resultado:** NO_VERIFICADO. Se verificaron estructuras y triggers, no se identificó ni se ratificó un canal concreto de autorización de *scope por regla*. Antes de continuar a G5 hay que obtenerlo y probarlo, sin pasar por Router durante esta etapa de diseño.
