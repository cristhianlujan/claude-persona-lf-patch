# Ejemplos — SKILL_ANALISIS_RIESGO_CONTENIDO_LF v0.2

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
**kb_polarity_suggested:** POSITIVO
**kb_dimension_suggested:** EDUCATIVO
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
**kb_polarity_suggested:** NEGATIVO
**kb_dimension_suggested:** ALERTA
**reason:** Claim de eliminación garantizada es P0 — alto riesgo regulatorio y de engaño al usuario.

---

## CASO ALERTA — ALERT_CAPTURE (nuevo en v0.2)

**Actor:** Empresa "Quita Deudas Peru SAC"
**Tema:** practica_abusiva_deudores
**visible_text:** "Cobramos S/500 adelantados para negociar tu deuda. Cientos de clientes satisfechos."
**claim_type:** COBRO_ADELANTADO_SIN_RESPALDO
**risk_level:** HIGH
**p0_p1_flags:** ["P1_COBRO_ADELANTADO", "P1_TARGET_POBLACION_VULNERABLE"]
**grounding_status:** GROUNDED
**hitl_required:** false
**decision:** ALERT_CAPTURE
**kb_polarity_suggested:** NEGATIVO
**kb_dimension_suggested:** ALERTA
**alert_actor:** "Quita Deudas Peru SAC"
**alert_evidence_url:** "https://www.indecopi.gob.pe/resoluciones/..."
**reason:** Empresa cobra adelantado sin servicio verificable. Patrón de estafa a deudores vulnerables.
**accion:** Entra al KB como registro NEGATIVO/ALERTA — usado para proteger usuarios LF.

---

## CASO REGULATORIO — ALLOW_PROD_GATE

**Fuente:** SBS Perú
**Tema:** prescripcion_deudas_peru
**visible_text:** Resolución SBS sobre plazos de prescripción de deudas en el sistema financiero peruano.
**claim_type:** NORMATIVA_OFICIAL
**risk_level:** LOW
**p0_p1_flags:** []
**grounding_status:** GROUNDED
**hitl_required:** false
**decision:** ALLOW_PROD_GATE
**kb_polarity_suggested:** NEUTRAL
**kb_dimension_suggested:** REGULATORIO
**reason:** Fuente oficial SBS. Contenido normativo sin claims sensibles.

---

## CASO SEÑAL_MERCADO — ALLOW_PROD_GATE

**Fuente:** Reddit r/PERU
**Tema:** experiencia_negativa_empresa_deudas
**visible_text:** "Pagué S/800 a empresa que prometió negociar mi deuda y desaparecieron."
**claim_type:** TESTIMONIO_USUARIO
**risk_level:** MEDIUM
**p0_p1_flags:** []
**grounding_status:** RESEARCH_REQUIRED
**hitl_required:** false
**decision:** ALLOW_PROD_GATE
**kb_polarity_suggested:** NEGATIVO
**kb_dimension_suggested:** SEÑAL_MERCADO
**reason:** Señal de demanda real + alerta de mercado. Útil para contenido de protección LF.

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
**kb_polarity_suggested:** NEUTRAL
**kb_dimension_suggested:** EDUCATIVO
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
**kb_polarity_suggested:** NEUTRAL
**kb_dimension_suggested:** EDUCATIVO
**reason:** Target de población vulnerable (registrados en Infocorp) requiere revisión humana.
