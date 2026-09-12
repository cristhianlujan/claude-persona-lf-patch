# Final Skill Judge — SKILL_ANALISIS_RIESGO_CONTENIDO_LF

**Judge code:** FINAL_SKILL_JUDGE_ANALISIS_RIESGO_CONTENIDO_LF_V0_1

## Condiciones para PASS_FULL_SKILL_RUN

- executed_steps_count = required_steps_count (9)
- missing_steps = []
- blocked_steps = [] o todos justificados
- external_writes = 0
- validated_writes = 0
- decision en valores permitidos
- evidence_pack completo
- lf_content_decisions con registro del run

## Condiciones para NEEDS_REPAIR

- missing_steps no vacío pero sin bloqueo crítico
- evidence_pack incompleto pero recuperable

## Condiciones para BLOCKED

- P0/P1 detectado sin HITL
- external_writes > 0
- validated_writes > 0
- decision fuera de schema

## Condiciones para FAIL_SKILL_RUN

- executed_steps_count < required_steps_count
- Múltiples steps bloqueados sin resolución

## Output esperado

```json
{
  "final_skill_result": "PASS_FULL_SKILL_RUN | NEEDS_REPAIR | BLOCKED | NEEDS_HITL | FAIL_SKILL_RUN",
  "executed_steps_count": 9,
  "missing_steps": [],
  "blocked_steps": [],
  "repair_required": false,
  "next_step": "GATE_APROBADO | SANDBOX_ADICIONAL | HITL"
}
```
