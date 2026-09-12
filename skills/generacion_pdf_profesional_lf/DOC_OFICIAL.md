# DOC_OFICIAL — SKILL_GENERACION_PDF_PROFESIONAL_LF v0.2 CANDIDATO READ_ONLY

## Estado

- proyecto: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
- activo: SKILL_GENERACION_PDF_PROFESIONAL_LF_v0.2_CANDIDATO
- estado_documental: CANDIDATO
- estado_operativo: READ_ONLY
- runtime_estado: NO_HABILITADO
- impacto_automatico: BLOQUEADO
- operation_code: CREACION_SKILL_LF
- fecha_reparacion: 2026-06-13

## Reparacion v0.2

La skill queda reforzada con reglas de pipeline, layout y QA visual.

Archivos de control:

- references/pdf_pipeline_decision.md
- references/executive_pdf_layouts.md
- references/visual_qa_bug_hunt.md
- evals/pdf_quality_checklist.yaml
- judges/judge_pdf_profesional_lf.yaml
- examples/input_brief.md
- examples/output_expected.md

## Matriz de decision

| Caso | Pipeline |
|---|---|
| ejecutivo | PPTX 16:9 o HTML/CSS premium |
| flujo | PPTX 16:9 o HTML/CSS premium paginado |
| brandbook | HTML/CSS premium o PPTX visual |
| informe largo | DOCX o Markdown |
| PDF pobre | reconstruir fuente editable |

## Cierre

Cierre maximo permitido: PASS_CANDIDATO_READ_ONLY_REPAIRED.

No habilita runtime ni produccion.