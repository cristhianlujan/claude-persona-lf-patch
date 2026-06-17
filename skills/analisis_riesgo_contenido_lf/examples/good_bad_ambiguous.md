# Ejemplos — SKILL_ANALISIS_RIESGO_CONTENIDO_LF

## CASO BUENO — ALLOW_CANDIDATE_READ_ONLY

**Competidor:** Finanty  
**Tema:** reinsercion_financiera  
**visible_text:** "Ayudamos a personas con historial crediticio difícil a recuperar su posición financiera."  
**claim_type:** EDUCATIVO_INFORMATIVO  
**risk_level:** LOW  
**p0_p1_flags:** []  
**grounding_status:** GROUNDED  
**hitl_required:** false  
**decision:** ALLOW_CANDIDATE_READ_ONLY  
**reason:** Fuente educativa/documental sin promesa de eliminación ni urgencia.

---

## CASO MALO — BLOCK_OR_HITL (PeruDeudas pattern)

**Competidor:** PeruDeudas  
**Tema:** eliminacion_deudas  
**visible_text:** "Eliminamos tus deudas de Infocorp de forma legal. ¡Garantizado!"  
**claim_type:** PROMESA_RESULTADO_GARANTIZADO  
**risk_level:** CRITICAL  
**p0_p1_flags:** ["P0_PROMESA_ELIMINACION", "P1_GARANTIA_SIN_SUSTENTO"]  
**grounding_status:** INSUFFICIENT  
**hitl_required:** true  
**decision:** BLOCK_OR_HITL  
**reason:** Claim de eliminación garantizada es P0 — alto riesgo regulatorio y de engaño al usuario.

---

## CASO AMBIGUO — RESEARCH_OR_HITL

**Competidor:** Reevalua  
**Tema:** prestamo_personal  
**visible_text:** "Obtén tu préstamo con las mejores condiciones del mercado."  
**claim_type:** COMPARATIVO_SIN_EVIDENCIA  
**risk_level:** MEDIUM  
**p0_p1_flags:** []  
**grounding_status:** RESEARCH_REQUIRED  
**hitl_required:** false  
**decision:** RESEARCH_OR_HITL  
**reason:** Landing financiera requiere revisar claim/CTA visible antes de uso — grounding insuficiente.

---

## CASO HITL_REQUIRED — Préstamo con garantía Infocorp

**Competidor:** RTC  
**Tema:** prestamo_con_garantia  
**visible_text:** "Préstamos estando en Infocorp. Soluciones para tu historial."  
**claim_type:** PRODUCTO_FINANCIERO_SENSIBLE  
**risk_level:** HIGH  
**p0_p1_flags:** ["P1_TARGET_POBLACION_VULNERABLE"]  
**grounding_status:** GROUNDED  
**hitl_required:** true  
**decision:** HITL_REQUIRED  
**reason:** Target de población vulnerable (registrados en Infocorp) requiere revisión humana.
