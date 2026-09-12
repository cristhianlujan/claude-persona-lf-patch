# Research Pack — SKILL_GENERACION_PDF_PROFESIONAL_LF

## Estado

- fecha: 2026-06-13
- operation_code: CREACION_SKILL_LF
- estado: CANDIDATO_READ_ONLY
- runtime_estado: NO_HABILITADO
- impacto_automatico: BLOQUEADO

## Capacidad objetivo

Crear una skill LF para PDFs profesionales con pipeline editable, criterio visual, QA obligatorio y readback verificable.

## Fuentes internas verificadas

| Fuente | Uso |
|---|---|
| ACT-0001 | Router rector y entrada obligatoria |
| Supabase / v_lf_fuente_operativa_busqueda | Fuente operativa y duplicidad |
| ACT-0043 | Creador de skills, no impacto automatico |
| ACT-0045 | Research pack, scoring y no duplicidad |
| ACT-0047 | Design System, tokens, componentes y QA visual |
| contrato_skill_lf.yaml | Repo, ruta, estados permitidos y bloqueos |
| judge_contrato_skill_lf.yaml | Pass/fail contractual |
| matriz_repos_lf.yaml | Repo y path autorizados |

## Fuentes externas revisadas como referencia

| Fuente | Uso permitido | Restriccion |
|---|---|---|
| Anthropic Skills / Claude Skills | Patron de carpeta con SKILL.md y recursos | No copiar contenido propietario |
| anthropics/skills repository | Ver estructura de skills documentales | No adoptar runtime externo |
| skills/pdf | Referencia tecnica para operaciones PDF | Gobernanza LF manda |
| skills/docx | Fuente editable y validacion documental | Solo patron, no copia |
| skills/pptx | QA visual render-inspect-fix-verify | Adaptado a PDF LF |
| Agent Skills standard | Portabilidad del paquete | No reemplaza Router LF |
| Research sobre Agent Skills | Riesgos de duplicidad, procedencia y seguridad | Requiere sandbox y judge LF |

## Scoring resumido

| Fuente | Score | Decision |
|---|---:|---|
| ACT-0001 | 5.0 | Rector |
| ACT-0043 | 5.0 | Creador aplicable |
| ACT-0045 | 4.7 | Research gate |
| ACT-0047 | 4.8 | Sistema visual |
| contrato_skill_lf.yaml | 5.0 | Gate obligatorio |
| judge_contrato_skill_lf.yaml | 5.0 | Judge obligatorio |
| skills/pdf | 3.8 | Referencia tecnica |
| skills/docx | 3.8 | Referencia editable |
| skills/pptx | 4.2 | Patron QA visual |
| Agent Skills standard / research | 4.1 | Referencia y riesgos |

## Research to rules matrix

| Hallazgo | Regla LF derivada | Destino |
|---|---|---|
| Toda operacion entra por Router | PDF LF no inicia directo por render | SKILL.md |
| Skill candidata requiere activadores y bloqueos | Definir cuando usar/no usar | SKILL.md |
| Research debe ser trazable | Mantener scoring y riesgos | research_pack.md |
| PDF profesional no es solo conversion | Exigir sistema visual minimo | evals/judge |
| DOCX/PPTX/HTML pueden ser fuentes editables | Seleccionar pipeline por tipo de PDF | SKILL.md |
| QA visual debe revisar render real | Render -> inspeccion -> correccion -> re-render | judge |
| Skills externas tienen riesgos | No usar runtime externo sin sandbox LF | manifest |

## Riesgos y mitigacion

| Riesgo | Mitigacion |
|---|---|
| PDF plano | Componentes visuales y QA obligatorio |
| Falta fuente editable | Editable requerido o NA justificado |
| Duplicidad con ACT-0047 | ACT-0047 visual; esta skill pipeline PDF |
| Uso externo sin gobierno | Solo referencia, no runtime |
| Cierre sin evidencia | Readback y evidence log obligatorios |
| Promocion indebida | Estado maximo CANDIDATO_READ_ONLY |

## Conclusion

Procede regularizar la skill candidata porque resuelve una capacidad recurrente y de alto riesgo: PDFs LF profesionales con pipeline, fuente editable, QA visual y cierre verificable.

Resultado: PASS_CANDIDATO_READ_ONLY.