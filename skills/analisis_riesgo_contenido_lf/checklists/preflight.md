# Preflight Checklist — SKILL_ANALISIS_RIESGO_CONTENIDO_LF

Completar antes de cada run de la skill.

## Router y fuente

- [ ] Router verificado contra v_lf_fuente_operativa
- [ ] ACT-0056 estado = CANDIDATO o superior
- [ ] operation_code = ANALISIS_RIESGO_CONTENIDO_LF confirmado
- [ ] execution_mode declarado (DRY_RUN / SANDBOX / PRODUCTION_CONTROLLED)

## Input del caso

- [ ] case_id o source_ref presente
- [ ] source_url disponible o gap declarado
- [ ] visible_text disponible o research_required declarado
- [ ] Corpus de referencia verificado (eventos 198/201 para DRY_RUN)

## Restricciones activas

- [ ] impacto_automatico = BLOQUEADO confirmado
- [ ] No hay intento de escritura automática
- [ ] No hay intento de declarar VALIDATED / APROBADO sin evidencia
- [ ] No hay intento de merge/GitHub sin CI verde y GO explícito

## Steps obligatorios

- [ ] S1-A Router
- [ ] S2-A Case Read
- [ ] S3-A Visible Evidence
- [ ] S4-A Classification
- [ ] S5-A Grounding
- [ ] S6-A Risk Judge
- [ ] S7-A HITL Judge
- [ ] S8-A Decision Matrix
- [ ] S9-A Evidence Close

## Post-run

- [ ] lf_content_decisions contiene registro del run
- [ ] lf_eventos tiene evento de cierre
- [ ] Final skill judge = PASS_FULL_SKILL_RUN
