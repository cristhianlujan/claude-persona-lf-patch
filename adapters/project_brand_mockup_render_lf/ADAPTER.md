---
name: project-brand-mockup-render-lf
type: ADAPTER
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
impacto_automatico: BLOQUEADO
version: v0.1-candidato
assurance_revision: v2
project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
---

# ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF

## Propósito
Resolver marca, tokens, especificaciones visuales y política de mockup por proyecto antes de producir artefactos visuales. El adapter no diseña el producto ni sustituye a UI Architect; normaliza fuentes visuales gobernadas para el worker que renderiza.

## Regla madre
**Usar marca/tokens/specs del proyecto cuando existen. Nunca convertir un fallback o mockup genérico en autoridad canónica.**

## Aplicabilidad
Aplica a entregables con pantallas, onboarding, journey UX, dashboard, mockups, design system, flujos UI, PDF/PPTX/HTML/brandbook con UI.

Una solicitud directa no es una invocación. La invocación válida debe ser resuelta por Router para el proyecto/entregable y registrada exactamente una vez.

## Ruta v2
`request -> ACT-0001 Router -> resolve project binding -> input governance preflight -> resolve design_system/tokens/screen specs -> load compact capsule in SAME worker execution -> produce project_brand_mockup_binding -> validate -> record lf_adapter_invocation -> render -> QA/readback`

No ejecutar una llamada LLM separada propia del adapter.

## Binding de gobernanza de inputs
Referencia única: `gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md`.

Cuando el input incluye requisitos funcionales, fuente/autoridad, freshness, requisitos negativos, conflictos/precedencia o readiness, resolver la revisión vigente de `INPUT_READINESS_CONTRACT` y consumir solo las secciones necesarias entre `APPLICABILITY_READINESS`, `SOURCE_AUTHORITY_PROVENANCE`, `FRESHNESS_INVALIDATION`, `NEGATIVE_REQUIREMENTS` y `CONFLICT_PRECEDENCE`.

Persistir `governance_receipt`. Solo `decision=PASS` permite aplicar la normalización/render técnico. `PARTIAL` o `NEGATIVE_CONFIRMED` bloquean/retornan con razón gobernada. `N/A` solo es válido cuando `input_governance_applicable=false`. No copiar ni forkar la lógica del agente dentro del adapter.

## Precedencia de autoridad
1. proyecto/producto/flow/screen resueltos en fuente operativa;
2. design system vigente del proyecto;
3. route/theme/component/color/spacing/typography/responsive tokens aplicables;
4. `screen_visual_specs` para pantallas concretas;
5. upstream UI/Product contracts cuando definan intención o jerarquía;
6. fallback aprobado y explícitamente etiquetado;
7. propuesta exploratoria no canónica.

Nunca mezclar tokens entre proyectos.

## Entrada mínima
- `project_code`
- `output_target`: `PDF`, `PPTX`, `HTML`, `BRANDBOOK`
- `router_binding_ref`
- `invocation_id`
- `product_code`, `flow_code`, `screen_id` cuando apliquen
- `upstream_refs`
- `input_governance_applicable`

## Salida obligatoria
Emitir `project_brand_mockup_binding` conforme a `schemas/project_brand_mockup_binding.schema.json` con:
- proyecto/design system resueltos;
- source refs;
- tokens y screen specs usados;
- mockup policy/frame spec;
- fallback mode explícito;
- QA requirements;
- blockers;
- handoff.

Cuando aplica, registrar exactamente un `lf_adapter_invocation` y un `governance_receipt` —incluido N/A gobernado cuando corresponda— dentro del envelope validado por `validators/validate_project_brand_mockup_adapter.py`.

## Contrato de invocación
- `activation_source=ROUTER` obligatorio;
- binding Router obligatorio;
- exactamente un receipt LF cuando aplica;
- `BLOCK_MISSING_ADAPTER_INVOCATION` si falta;
- `BLOCK_DUPLICATE_ADAPTER_INVOCATION` si se duplica;
- `BLOCK_UNBOUND_ADAPTER_INVOCATION` ante llamada suelta;
- el receipt LF no reutiliza el `adapter_id` técnico del proveedor/model runtime.

## Presupuesto de contexto
La ejecución normal carga solo `runtime/runtime_capsule.yaml`.
- máximo 1600 caracteres UTF-8;
- máximo 10 reglas materiales;
- references/templates/examples/judges quedan fuera del prompt normal y se usan solo cuando la tarea lo exige o durante validación.

## Fail closed
Bloquear si:
- falta proyecto cuando puede cambiar marca;
- se inventa paleta/token y se etiqueta canónico;
- se contaminan tokens entre proyectos;
- se ignora una `screen_visual_spec` aplicable;
- un fallback se presenta como marca vigente;
- una pantalla se representa solo como tabla cuando se requiere mockup;
- falta QA/readback visual material;
- falta o se duplica la invocación gobernada;
- input funcional relevante carece de governance binding/receipt;
- se intenta aplicar con decisión de gobernanza distinta de PASS o sin snapshot/source refs verificables;
- se forkea `INPUT_READINESS_CONTRACT` o se usa un agente ad hoc;
- la cápsula excede presupuesto;
- el adapter intenta una segunda llamada LLM propia;
- se declara producción, runtime habilitado, VALIDATED o promoción automática.

## Modos de salida
- `BOUND`
- `BOUND_WITH_APPROVED_FALLBACK`
- `RETURN_TO_ORCHESTRATOR_MISSING_SOURCE`
- `BLOCKED_SOURCE_CONFLICT`
- `BLOCKED_PROJECT_UNRESOLVED`
- `BLOCK_MISSING_ADAPTER_INVOCATION`
- `BLOCK_DUPLICATE_ADAPTER_INVOCATION`
- `BLOCK_UNBOUND_ADAPTER_INVOCATION`
- `BLOCK_INPUT_GOVERNANCE`
- `BLOCK_CONTEXT_BUDGET_EXCEEDED`

## Validación
- schema estructural;
- validator determinístico;
- judge de marca/linaje/invocación;
- positivos, negativos, adversariales y holdout;
- QA/readback exact-head.

## Cierre permitido
`CANDIDATO_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION`.