---
name: generacion-pdf-profesional-lf
description: Skill LF candidata para PDFs profesionales con pipeline, layout, QA visual bug-hunt, templates, script de render/auditoria y adapter de mockups por marca/proyecto.
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
automatic_impact: BLOQUEADO
operation_code: CREACION_SKILL_LF
version: v0.3-adapter-gated
last_updated: 2026-06-13
---

# SKILL_GENERACION_PDF_PROFESIONAL_LF

## Regla madre

No cerrar un PDF por existir. Cerrar solo si hay pipeline correcto, fuente editable, layout/template, PDF renderizado, paginas exportadas a imagen, QA bug-hunt, fixes cuando aplique y readback.

Si falta cualquiera: RETURN_TO_WORKER.

## Gate de pantallas y mockups

Si el PDF contiene pantallas, onboarding, dashboard, journey UX, app flow o mockups, debe activar:

`adapters/project_brand_mockup_render_lf/ADAPTER.md`

Antes de diseñar debe resolver:

- project_code;
- design_system_code;
- tokens de marca;
- screen_visual_specs;
- mockup template;
- QA visual de mockup.

Si hay tokens del proyecto, esta prohibido inventar paleta. Si una pantalla clave se presenta solo como tabla, devolver RETURN_TO_WORKER.

## Archivos obligatorios

- references/pdf_pipeline_decision.md
- references/executive_pdf_layouts.md
- references/visual_qa_bug_hunt.md
- templates/report_exec_16x9.md
- templates/flow_review_report.md
- scripts/render_and_audit_pdf.py
- evals/pdf_quality_checklist.yaml
- quality/pdf_professional_gate.yaml
- examples/input_brief.md
- examples/output_expected.md
- judges/judge_pdf_profesional_lf.yaml
- adapters/project_brand_mockup_render_lf/ADAPTER.md cuando hay pantallas

## Pipeline

- ejecutivo: PPTX 16:9 o HTML/CSS premium.
- flujo/onboarding: PPTX 16:9 o HTML/CSS premium paginado.
- pantallas/mockups: activar adapter de marca y mockup.
- brandbook: HTML/CSS premium o PPTX visual.
- informe largo: DOCX o Markdown.
- PDF pobre: extraer, reconstruir fuente editable, redisenar y renderizar.

ReportLab plano no es default para PDF ejecutivo.

## Gates bloqueantes

- pipeline no justificado: BLOCKED_PIPELINE_DECISION_MISSING
- sin template/layout: BLOCKED_TEMPLATE_NOT_USED
- sin fuente editable: BLOCKED_EDITABLE_SOURCE_MISSING
- sin imagenes de paginas: BLOCKED_VISUAL_RENDER_MISSING
- sin bug-hunt: BLOCKED_VISUAL_QA_NOT_DONE
- PDF basico: FAIL_VISUAL_QUALITY
- pantallas sin adapter: BLOCKED_MOCKUP_ADAPTER_NOT_APPLIED
- colores inventados: FAIL_BRAND_MISMATCH
- pantalla clave solo como tabla: FAIL_GENERIC_MOCKUP
- sin readback: BLOCKED_READBACK_MISSING

## Cierre permitido

PASS_CANDIDATO_READ_ONLY_REPAIRED, PASS_WITH_OBSERVATIONS_CANDIDATO_READ_ONLY, RETURN_TO_WORKER, FAIL_VISUAL_QUALITY o BLOCKED.

Runtime sigue NO_HABILITADO e impacto automatico BLOQUEADO.