# Final Skill Judge -- SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF

**Judge code:** FINAL_SKILL_JUDGE_ESCRITURA_BASE_CONOCIMIENTO_LF_V0_1

## PASS_FULL_SKILL_RUN si

- executed_steps_count = 9
- missing_steps = []
- blocked_steps = [] o justificados
- kb_id retornado y verificado en readback
- evidence_pack completo
- evento registrado en lf_eventos

## NEEDS_REPAIR si

- missing_steps no vacio pero recuperable
- dedup flag presente pero sin bloqueo critico

## BLOCKED si

- upstream decision != ALLOW_PROD_GATE
- write sin execution_mode autorizado
- readback falla

## FAIL_SKILL_RUN si

- executed_steps_count < 9
- kb_id no retornado

## Output esperado

```json
{
  "final_skill_result": "PASS_FULL_SKILL_RUN",
  "executed_steps_count": 9,
  "missing_steps": [],
  "blocked_steps": [],
  "kb_id": "<uuid>",
  "next_step": "GATE_APROBADO o SANDBOX_ADICIONAL"
}
```
