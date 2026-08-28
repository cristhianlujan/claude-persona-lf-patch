---
name: lf-shell-profile-adapter
type: ADAPTER
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
impacto_automatico: BLOQUEADO
version: v0.1-candidato
project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
---

# ADAPTER_LF_SHELL_PROFILE

## Propósito

Conectar perfiles especialistas con las pantallas de Libertad Financiera sin permitir que cada perfil reconstruya, duplique o contradiga el Shell canónico.

El adapter traduce decisiones semánticas del perfil a un `shell_binding` verificable. No sustituye al perfil especialista ni al Design System.

## Regla madre

**El perfil decide QUÉ cambia dentro de su autoridad. El Shell y el Design System determinan CÓMO se estructura LF. El adapter resuelve y limita DÓNDE puede aplicarse el cambio.**

Nunca copiar al adapter una versión fija del Shell como autoridad. Resolverla desde la fuente canónica vigente en cada ejecución.

## Activación obligatoria

Activar cuando un perfil:

- crea, evalúa o remedia una pantalla LF;
- define una decisión que afecta layout, navegación, componentes, estados, copy visible o tokens de una pantalla LF;
- convierte una especificación UI en prototipo/frontend;
- añade gamificación u otra capa funcional dentro de una pantalla LF existente;
- recibe una pantalla LF por Router o por activación directa.

No activar para trabajo sin superficie UI ni relación con una pantalla LF.

## Fuentes canónicas mínimas

Resolver en este orden:

1. `lf_ops.pantallas` para identidad, módulo, estado, dependencias y perfiles permitidos.
2. `lf_ops.modulos` para `module_code -> app_shell_code`.
3. `lf_ops.app_shells` para Shell, versión y estado operativo.
4. `lf_ops.pantalla_variantes` y `lf_ops.pantalla_elementos` cuando existan para layout/elementos específicos.
5. `lf_design.component_tokens`, `spacing_tokens`, `color_tokens`, `typography_tokens` y `responsive_tokens` cuando apliquen.
6. Contratos upstream de Product Director y UI Architect.
7. Solo después, propuesta exploratoria del perfil cuando la autoridad canónica no defina el valor y el riesgo permita explorar.

Los campos heredados de Drive no son autoridad del adapter. Su existencia en una fila no reemplaza las fuentes canónicas anteriores.

## Pipeline

`request -> Router/direct profile -> resolve pantalla -> resolve module -> resolve app_shell -> resolve tokens/variants/elements -> classify locked shell vs writable screen delta -> run specialist profile -> normalize decision -> validate authority -> shell_binding -> downstream worker/readback`

## Contrato con UI Architect

UI Architect conserva su contrato actual y su autoridad visual. Para pantallas LF:

- `Production UI Spec` sigue siendo el formato de producción visual.
- `remediation_actions` sigue siendo obligatorio en evaluación/remediación de pantalla existente.
- cada `execution.target_component_id` debe clasificarse como `SHELL_LOCKED`, `SCREEN_COMPONENT` o `SCREEN_SLOT` antes de ejecutarse;
- las reglas de `precision_basis`, autoridad semántica, defecto -> corrección -> postcondición y consistencia Router/directo se conservan sin reinterpretación;
- un target `SHELL_LOCKED` no puede modificarse por una remediation action normal. Debe retornar `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED` con evidencia del Shell afectado;
- un valor canónico resuelto debe usarse como `CANONICAL_TOKEN`/`UPSTREAM_VALUE`; no se reemplaza por precisión inventada;
- ausencia de token no bloquea una decisión visual exploratoria de bajo riesgo: usar `EXPLORATORY_PROPOSAL` o `RELATIVE_GUIDANCE` tal como exige UI Architect.

## Contrato común de entrada

- `profile_id`
- `screen_code` o evidencia suficiente para resolver la pantalla
- `request_delta`
- `router_context` opcional
- `upstream_refs` opcional
- `target_mode`: `EVALUATE`, `REMEDIATE`, `CREATE_SPEC`, `IMPLEMENT_PROTOTYPE`, `REVIEW`

## Salida obligatoria

Emitir un `shell_binding` conforme a `schemas/lf_shell_binding.schema.json` con:

- identidad y estado del Shell resuelto;
- referencias canónicas usadas;
- zonas/targets protegidos;
- slots/componentes escribibles;
- delta normalizado del perfil;
- base de precisión;
- conflictos o faltantes materiales;
- handoff permitido.

## Límites de autoridad

- El adapter no inventa negocio, rutas, claims, CTA intent ni reglas de producto.
- El adapter no rediseña visualmente la pantalla: esa autoridad permanece en UI Architect.
- El adapter no genera HTML/CSS: eso corresponde a Frontend Prototype Architect LF cuando recibe especificaciones upstream suficientes.
- El adapter no convierte un Shell `CANDIDATO` en `VIGENTE` ni habilita producción.
- El adapter no cambia registros canónicos de Supabase.

## Estados de salida

- `BOUND`: Shell resuelto y delta aplicable.
- `BOUND_CANDIDATE_ONLY`: Shell o superficie candidata; trabajo solo candidato/read-only.
- `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`: falta una decisión upstream material.
- `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED`: el pedido requiere alterar una zona protegida del Shell.
- `BLOCKED_SOURCE_CONFLICT`: fuentes canónicas se contradicen y no existe precedencia suficiente.
- `BLOCKED_SCREEN_UNRESOLVED`: no puede resolverse la superficie objetivo con evidencia disponible.

## Hard fail

Fallar si:

- se omite la resolución `pantalla -> módulo -> app_shell` cuando los datos existen;
- se toma Drive como autoridad sobre Supabase para Shell/tokens;
- se duplica localmente un Shell vigente en vez de referenciarlo;
- un perfil modifica `SHELL_LOCKED` sin escalamiento explícito;
- se inventa un token o valor y se presenta como canónico;
- Frontend cambia jerarquía/CTA/producto sin autoridad upstream;
- Product Director, gamificación u otro perfil se atribuye autoridad visual de UI Architect;
- Router y activación directa producen deltas materiales distintos con el mismo contexto;
- se marca producción, runtime habilitado o VALIDATED desde este adapter.

## Cierre permitido

`CANDIDATO_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION` hasta que exista validación y promoción separadas.