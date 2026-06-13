# Research Pack — SKILL_GENERACION_PDF_PROFESIONAL_LF

## Fuentes externas revisadas

1. Anthropic — Introducing Agent Skills
   - URL: https://claude.com/blog/skills
   - Uso: confirmar que Skills son carpetas con instrucciones, scripts y recursos cargados bajo demanda.

2. Claude Code Docs — Extend Claude with skills
   - URL: https://code.claude.com/docs/en/skills
   - Uso: estructura SKILL.md, frontmatter, supporting files, invocacion, ciclo de contexto y permisos.

3. Agent Skills standard
   - URL: https://agentskills.io/home
   - Uso: formato portable: carpeta + SKILL.md + scripts/references/assets opcionales.

4. anthropics/skills — repositorio publico
   - URL: https://github.com/anthropics/skills
   - Uso: referencia de patrones y existencia de document skills: pdf, docx, pptx, xlsx.

5. anthropics/skills — skills/pdf/SKILL.md
   - repo: anthropics/skills
   - path: skills/pdf/SKILL.md
   - blob_sha: d3e046a5ae107a6cb23cfb16c219837094ab35d3
   - Uso: referencia tecnica para operaciones PDF. No copiado.

6. anthropics/skills — skills/pdf/reference.md
   - repo: anthropics/skills
   - path: skills/pdf/reference.md
   - blob_sha: 41400bf4fc67f15fb062d43695ec92f078226023
   - Uso: referencia de librerias y renderizado. No copiado.

7. anthropics/skills — skills/docx/SKILL.md
   - repo: anthropics/skills
   - path: skills/docx/SKILL.md
   - blob_sha: 2951e559989765293b6fbf83942378a3c2d0cba6
   - Uso: referencia para fuente editable y validacion documental. No copiado.

8. anthropics/skills — skills/pptx/SKILL.md
   - repo: anthropics/skills
   - path: skills/pptx/SKILL.md
   - blob_sha: df5000e17ef60ecf400e65bfcd3c58ff88b604c3
   - Uso: referencia de QA visual y ciclo fix-and-verify. No copiado.

9. Agent Skills: Data-Driven Analysis
   - URL: https://arxiv.org/abs/2602.08004
   - Uso: riesgo de redundancia, concentracion y seguridad en ecosistemas de skills.

10. Under the Hood of SKILL.md
   - URL: https://arxiv.org/abs/2605.11418
   - Uso: riesgo supply-chain semantico en SKILL.md; justificar governance y no confiar en terceros sin sandbox.

## Fuentes internas LF verificadas

| Fuente | Evidencia |
|---|---|
| ACT-0001 | Router vigente, activo, rector |
| v_lf_fuente_operativa_busqueda | No existe skill PDF LF especifica encontrada |
| ACT-0043 | Skill Creator LF vigente READ_ONLY |
| ACT-0045 | Skill creadora perfiles/cards vigente READ_ONLY |
| ACT-0047 | Design System multicanal candidato READ_ONLY |
| contrato_skill_lf.yaml | Repo/path/status/runtime/impact rules |
| judge_contrato_skill_lf.yaml | Pass/fail gates |

## Regla de uso

Este research pack habilita solo creacion candidata. No habilita runtime, produccion, VALIDATED ni VIGENTE.
