# web_article_capture — Adapter hijo

> Owner Supabase: SKILL_EXTRACCION_FUENTES_DIGITALES_LF · ACT-0052
> Owner GitHub interno: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
> Estado: CANDIDATO_READ_ONLY

---

## Orden de lectura por perfil

Operador humano nuevo:
- domain/SKILL.md
- permissions/roles_matrix.md
- RUNBOOK.md
- commands/capture_web_article/input_contract.yaml

Agente ejecutando:
- RUNBOOK.md
- commands/capture_web_article/input_contract.yaml
- schemas/db_field_mapping.yaml
- fixtures/antiduplicate_hashes.yaml
- commands/capture_web_article/gates.md

Agente homologando futuro:
- commands/capture_web_article/judge.yaml
- commands/capture_web_article/evals.yaml

---

## Alcance

Este adapter es la implementación actual para artículos web dentro de la skill madre canónica SKILL_EXTRACCION_FUENTES_DIGITALES_LF.

## Límites

CANDIDATO_READ_ONLY. Solo sandbox.
