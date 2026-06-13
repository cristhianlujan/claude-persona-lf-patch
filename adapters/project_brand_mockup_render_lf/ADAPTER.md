---
name: project-brand-mockup-render-lf
type: ADAPTER
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
impacto_automatico: BLOQUEADO
version: v0.1-candidato
project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
---

# ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF

## Proposito

Resolver marca, tokens, especificaciones visuales y mockups por proyecto antes de generar PDFs, decks o brandbooks con pantallas.

## Activacion obligatoria

Activar cuando un entregable incluya:

- pantallas de app;
- onboarding;
- journey UX;
- dashboard;
- mockups;
- design system;
- flujo con UI;
- PDF ejecutivo con pantallas.

## Regla madre

Si existen tokens o specs visuales del proyecto, se deben usar. No inventar paleta ni usar mockups genericos.

## Ruta

Router -> fuente operativa -> resolver proyecto -> resolver design_system -> resolver tokens -> resolver screen_visual_specs -> seleccionar mockup template -> render -> QA visual -> readback.

## Inputs

- project_code
- product_code opcional
- flow_code opcional
- screen_id opcional
- output_target: PDF, PPTX, HTML, brandbook

## Outputs

- brand tokens resueltos
- mockup policy
- screen frame spec
- visual QA checklist
- blocker list

## Bloqueos

- sin tokens y sin fallback aprobado;
- colores inventados;
- mockup sin frame de app cuando hay pantallas;
- no leer screen_visual_specs;
- no leer route_theme_tokens;
- no QA visual;
- declarar produccion.

## Cierre permitido

CANDIDATO_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION.