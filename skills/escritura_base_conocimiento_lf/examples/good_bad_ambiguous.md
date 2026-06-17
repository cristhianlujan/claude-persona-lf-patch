# Ejemplos -- SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF

## CASO BUENO -- PASS_FULL_SKILL_RUN

**Upstream decision:** ALLOW_PROD_GATE (de ACT-0056)
**topic:** reinsercion_financiera
**source_url:** https://finanty.pe/reinsercion
**kb_category:** EDUCACION_FINANCIERA
**kb_subcategory:** REINSERCION_CREDITICIA
**summary:** Finanty ofrece enfoque documental para recuperacion financiera sin promesas de eliminacion.
**key_insights:** ["Enfoque humano sin claim sensible", "Diferenciador vs competidores que prometen eliminar deuda"]
**quality_score:** 8.5
**consumer_ready:** false (DRY_RUN)
**resultado:** PASS_FULL_SKILL_RUN -- kb_id generado, readback OK

---

## CASO MALO -- BLOCKED

**Upstream decision:** BLOCK_OR_HITL (de ACT-0056)
**Resultado:** BLOCKED_UPSTREAM_DECISION_NOT_ALLOW
**Razon:** Solo ALLOW_PROD_GATE puede entrar a KB -- contenido bloqueado no se persiste.

---

## CASO AMBIGUO -- NEEDS_REPAIR

**Upstream decision:** ALLOW_PROD_GATE
**topic:** educacion_crediticia
**visible_text:** (muy corto, insuficiente para summary)
**Resultado:** NEEDS_REPAIR -- summary vacio, key_insights insuficientes
**Accion:** Volver a S5-A con mas contexto o marcar para research adicional.
