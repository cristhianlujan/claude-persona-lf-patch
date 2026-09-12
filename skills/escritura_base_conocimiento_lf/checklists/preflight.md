# Preflight Checklist -- SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF

## Router y upstream

- [ ] Router verificado contra v_lf_fuente_operativa
- [ ] ACT-0057 estado = CANDIDATO o superior
- [ ] ACT-0056 emitio decision ALLOW_PROD_GATE verificada
- [ ] decision_id de lf_content_decisions disponible
- [ ] execution_mode declarado (DRY_RUN / SANDBOX / PROD_CONTROLLED)

## Restricciones activas

- [ ] impacto_automatico = BLOQUEADO confirmado
- [ ] No escritura automatica sin GO explicito
- [ ] DRY_RUN no escribe a lf_knowledge_base real

## Steps obligatorios

- [ ] S1-A Router
- [ ] S2-A Upstream Decision Read
- [ ] S3-A Content Validation
- [ ] S4-A KB Classification
- [ ] S5-A Summary Generation
- [ ] S6-A Dedup Check
- [ ] S7-A KB Write
- [ ] S8-A Readback Verification
- [ ] S9-A Evidence Close

## Post-run

- [ ] lf_knowledge_base tiene registro (si no DRY_RUN)
- [ ] lf_eventos tiene evento de cierre
- [ ] Final skill judge = PASS_FULL_SKILL_RUN
