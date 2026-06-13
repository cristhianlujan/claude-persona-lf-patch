---
name: generacion-pdf-profesional-lf
description: Skill LF candidata para generar PDFs profesionales con pipeline ejecutable, referencias de layout, QA visual bug-hunt y gates bloqueantes. Usar para PDF ejecutivo, reporte, brandbook, flujo, propuesta, auditoria o reconstruccion de PDF basico. No usar para runtime productivo ni cierre validado.
status: CANDIDATO
estado_documental: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
automatic_impact: BLOQUEADO
owner_project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
operation_code: CREACION_SKILL_LF
version: v0.2-return-to-worker-repaired
last_updated: 2026-06-13
---

# SKILL_GENERACION_PDF_PROFESIONAL_LF

## Estado y bloqueo

Esta skill queda en `CANDIDATO_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION`.

No marcar `VALIDATED`, `VIGENTE`, `APROBADO`, `PRODUCCION`, `RUNTIME_READY` ni `PASS_PRODUCTIVO`.

## Regla madre

Un PDF profesional no se cierra por existir. Se cierra solo si:

1. el pipeline correcto fue elegido con evidencia;
2. se uso layout/template aplicable;
3. se genero fuente editable;
4. se renderizo PDF;
5. se convirtieron paginas clave a imagen;
6. el QA visual busco fallas, no confirmacion;
7. hubo fix-and-verify cuando aparecieron issues;
8. el readback enumera paginas revisadas, issues y fixes.

Si falta cualquiera: `RETURN_TO_WORKER`.

## Ruta LF obligatoria

```text
Router -> ACT-0001 -> Supabase / v_lf_fuente_operativa -> activo vigente aplicable -> contrato CREACION_SKILL_LF -> duplicidad -> research pack -> matriz research_to_rules -> matriz decision -> diseño canonico -> pack profundo -> eval -> judge -> render/QA -> readback -> evidencia -> cierre candidato
```

## Archivos que deben leerse antes de ejecutar

| Archivo | Uso obligatorio |
|---|---|
| `references/pdf_pipeline_decision.md` | decidir DOCX, PPTX, HTML/CSS, ReportLab o reconstruccion |
| `references/executive_pdf_layouts.md` | seleccionar layout, densidad y componentes por pagina |
| `references/visual_qa_bug_hunt.md` | ejecutar QA visual bloqueante |
| `examples/input_brief.md` | plantilla de intake y page-map minimo |
| `examples/output_expected.md` | contrato de salida esperada y readback |
| `evals/pdf_quality_checklist.yaml` | scoring operativo de calidad |
| `judges/judge_pdf_profesional_lf.yaml` | veredicto bloqueante |

Si alguno falta o no se lee: `BLOCKED_PACK_DEPTH_NOT_CLEAN`.

## Decisor de pipeline

Regla dura:

```text
Si el PDF es ejecutivo, visual, flujo, directorio, propuesta o brandbook: usar PPTX 16:9 -> PDF o HTML/CSS premium paginado.
No usar ReportLab plano salvo tablas/documento formal o justificacion escrita.
```

| Caso | Pipeline obligatorio | Bloquear si |
|---|---|---|
| informe formal largo | DOCX/Markdown -> PDF | no hay TOC, estilos, tablas legibles |
| ejecutivo/directorio | PPTX 16:9 -> PDF | usa pagina plana tipo informe |
| flujo/onboarding | PPTX 16:9 o HTML/CSS premium -> PDF | flujo queda comprimido en una pagina |
| brandbook | HTML/CSS premium o PPTX visual -> PDF | no hay paleta, tokens, componentes |
| PDF basico existente | extraer -> reconstruir fuente editable -> rediseñar -> PDF | se maquilla encima del PDF pobre |

## Procedimiento ejecutable

1. Clasificar entregable y audiencia.
2. Leer `pdf_pipeline_decision.md` y declarar pipeline elegido.
3. Leer layout aplicable.
4. Definir mapa de paginas antes de renderizar.
5. Aplicar maximo de densidad: una idea principal por pagina; maximo 6 cards o 8 filas por pagina.
6. Crear fuente editable.
7. Renderizar PDF.
8. Convertir paginas clave a imagen.
9. Aplicar `visual_qa_bug_hunt.md`: buscar fallas.
10. Si no se detectan fallas en primer render, revisar otra vez; cero fallas en primer intento es sospechoso.
11. Corregir y re-renderizar cuando exista cualquier observacion.
12. Cerrar solo con readback trazable.

## Gates bloqueantes

| Gate | Bloqueo |
|---|---|
| pipeline no justificado | `BLOCKED_PIPELINE_DECISION_MISSING` |
| layout/template no usado | `BLOCKED_TEMPLATE_NOT_USED` |
| sin fuente editable | `BLOCKED_EDITABLE_SOURCE_MISSING` |
| sin render a imagen | `BLOCKED_VISUAL_RENDER_MISSING` |
| sin bug-hunt QA | `BLOCKED_VISUAL_QA_NOT_DONE` |
| PDF se ve basico | `FAIL_VISUAL_QUALITY` |
| primer QA sin issues y sin segunda revision | `BLOCKED_QA_CONFIRMATION_BIAS` |
| sin fix-and-verify cuando aplica | `BLOCKED_FIX_VERIFY_MISSING` |
| sin readback | `BLOCKED_READBACK_MISSING` |

## Cierre permitido

Veredictos permitidos:

- `PASS_CANDIDATO_READ_ONLY_REPAIRED`
- `PASS_WITH_OBSERVATIONS_CANDIDATO_READ_ONLY`
- `RETURN_TO_WORKER`
- `FAIL_VISUAL_QUALITY`
- `BLOCKED`

Todo cierre debe incluir: pipeline, fuente editable, paginas renderizadas, paginas revisadas, issues encontrados, fixes aplicados, pendientes y estado no productivo.