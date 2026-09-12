---
name: lf-shell-profile-adapter
type: ADAPTER
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
impacto_automatico: BLOQUEADO
version: v0.1-candidato
assurance_revision: v2
project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
---

# ADAPTER_LF_SHELL_PROFILE

## Propósito
Conectar perfiles especialistas con pantallas LF sin permitir que cada perfil reconstruya, duplique o contradiga el Shell canónico. El perfil conserva la decisión semántica; Shell/Design System conservan estructura y tokens; el adapter resuelve DÓNDE puede aplicarse el delta.

## Regla madre
**Perfil = QUÉ. Shell/Design System = CÓMO. Adapter = DÓNDE + límites de aplicación.** Nunca copiar un Shell vigente al adapter como autoridad; resolverlo desde Supabase en cada ejecución gobernada.

## Activación aplicable
El adapter aplica cuando una decisión afecta una pantalla LF: layout, navegación, componentes, estados, copy visible, tokens, prototipo/frontend o gamificación visible. No aplica a trabajo sin superficie UI.

Una solicitud puede originarse en usuario o perfil, pero eso NO constituye una invocación. La única invocación válida es resuelta por Router mediante el binding operativo vigente.

## Contrato de invocación v2
Ruta obligatoria:

`request -> ACT-0001 Router -> resolve profile -> resolve adapter binding -> input governance preflight -> load runtime capsule + profile in SAME model execution -> produce shell_binding -> validate -> record lf_adapter_invocation -> downstream/readback`

Reglas:
- el perfil no auto-invoca el adapter;
- el usuario no invoca el adapter como worker suelto;
- el adapter no genera una segunda llamada LLM propia;
- si el binding aplica, debe existir exactamente un `lf_adapter_invocation` conforme a `schemas/lf_adapter_invocation.schema.json`;
- si aplica y falta receipt: `BLOCK_MISSING_ADAPTER_INVOCATION`;
- si aparece más de una invocación para el mismo adapter/target: `BLOCK_DUPLICATE_ADAPTER_INVOCATION`;
- si no existe binding Router vigente: `BLOCK_UNBOUND_ADAPTER_INVOCATION`;
- usar `lf_adapter_invocation`, nunca el campo genérico `adapter_id` del runtime/model provider.

## Binding de gobernanza de inputs
Referencia única: `gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md`.

Cuando el input contiene requisitos funcionales, autoridad/provenance, freshness, requisitos negativos, conflictos/precedencia o readiness, resolver la revisión vigente de `INPUT_READINESS_CONTRACT` y consumir solo las secciones necesarias entre `APPLICABILITY_READINESS`, `SOURCE_AUTHORITY_PROVENANCE`, `FRESHNESS_INVALIDATION`, `NEGATIVE_REQUIREMENTS` y `CONFLICT_PRECEDENCE`.

Persistir `governance_receipt`. Solo `decision=PASS` permite aplicar el delta técnico. `PARTIAL` o `NEGATIVE_CONFIRMED` bloquean/retornan con razón gobernada. `N/A` solo es válido si `input_governance_applicable=false` con razón explícita. El adapter no copia, forkea ni sustituye la lógica de `INPUT_READINESS_CONTRACT`.

## Presupuesto de contexto
Runtime carga `runtime/runtime_capsule.yaml`, no el pack completo. Límite determinístico: máximo 1800 caracteres UTF-8 para la cápsula y máximo 12 reglas materiales. El pack completo (contratos, examples, evals y judge) se usa para validación/evidencia, no como prompt normal.

## Fuentes canónicas mínimas
Resolver en este orden:
1. `lf_ops.pantallas`.
2. `lf_ops.modulos` para `module_code -> app_shell_code`.
3. `lf_ops.app_shells`.
4. `lf_ops.pantalla_variantes` / `lf_ops.pantalla_elementos` cuando existan.
5. `lf_design.component_tokens`, `spacing_tokens`, `color_tokens`, `typography_tokens`, `responsive_tokens` cuando apliquen.
6. Contratos upstream Product Director / UI Architect.
7. Solo después, propuesta exploratoria de bajo riesgo.

Drive o campos heredados no desplazan estas fuentes.

## Contrato con perfiles
- UI Architect mantiene autoridad visual y su `Production UI Spec`.
- Product Director no adquiere autoridad visual.
- Gamification entrega delta semántico; UI resuelve jerarquía visual final.
- Frontend implementa specs suficientes; no inventa producto, CTA ni jerarquía.
- `SHELL_LOCKED` siempre retorna al orquestador; no se ejecuta como remediation normal.
- valores canónicos usan `CANONICAL_TOKEN`/`UPSTREAM_VALUE`; precisión no gobernada solo puede quedar como `EXPLORATORY_PROPOSAL` o `RELATIVE_GUIDANCE`.

## Entrada mínima
- `profile_id`
- `screen_code` o evidencia suficiente para resolver pantalla
- `request_delta`
- `target_mode`: `EVALUATE`, `REMEDIATE`, `CREATE_SPEC`, `IMPLEMENT_PROTOTYPE`, `REVIEW`
- `router_binding_ref`
- `invocation_id`
- `upstream_refs` cuando apliquen
- `input_governance_applicable`

## Salida
1. `shell_binding` conforme a `schemas/lf_shell_binding.schema.json`.
2. Exactamente un `lf_adapter_invocation` cuando el binding aplica.
3. Un `governance_receipt` cuando el adapter aplica, incluyendo N/A gobernado si corresponde.

El binding conserva identidad/estado del Shell, fuentes, targets protegidos/escribibles, delta del perfil, conflictos y handoff.

## Estados
- `BOUND`
- `BOUND_CANDIDATE_ONLY`
- `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`
- `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED`
- `BLOCKED_SOURCE_CONFLICT`
- `BLOCKED_SCREEN_UNRESOLVED`
- `BLOCK_MISSING_ADAPTER_INVOCATION`
- `BLOCK_DUPLICATE_ADAPTER_INVOCATION`
- `BLOCK_UNBOUND_ADAPTER_INVOCATION`
- `BLOCK_INPUT_GOVERNANCE`
- `BLOCK_CONTEXT_BUDGET_EXCEEDED`

## Hard fail
Fallar si:
- falta resolución `pantalla -> módulo -> app_shell` cuando existe;
- Drive desplaza autoridad Supabase;
- se duplica localmente un Shell vigente como canónico;
- se modifica `SHELL_LOCKED` sin escalamiento;
- se inventa token/valor y se marca canónico;
- un perfil expande su autoridad;
- hay auto-invocación/direct-call sin binding Router;
- falta, se duplica o colisiona el receipt LF;
- input funcional relevante carece de governance binding/receipt;
- se aplica con decisión de gobernanza distinta de PASS o sin snapshot/source refs verificables;
- se forkea `INPUT_READINESS_CONTRACT` o se usa gobernanza ad hoc;
- la cápsula excede presupuesto;
- el adapter habilita runtime, producción, VALIDATED o promoción automática.

## Validación
- schema de binding;
- schema de invocation receipt;
- `validators/validate_lf_shell_profile_adapter.py`;
- judge semántico;
- positivos, negativos, adversariales y holdout;
- readback exact-head.

## Cierre permitido
`CANDIDATO_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION` hasta promoción separada.