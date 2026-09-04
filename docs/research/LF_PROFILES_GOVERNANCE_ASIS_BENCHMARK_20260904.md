# LF Profiles Governance — AS-IS + benchmark 2026

Fecha de corte: 2026-09-04 (America/Lima)
Base GitHub: `c7b18a46a5b4897f7266ffc62de33dbed36c407a`
Estado del artefacto: INVESTIGACION / READ_ONLY / NO_PROMOTION

## Objetivo

Determinar la gobernanza real antes de modificar Profiles. Este documento no habilita runtime, promoción ni impacto automático.

Principio rector: no crear una capa nueva cuando una autoridad, contrato, binding, receipt o tabla existente puede extenderse.

## Readback vivo

### Autoridad

- `ACT-0001` en `public.v_lf_fuente_operativa`: documental `VIGENTE`, operativo `ACTIVO`, control `RECTOR`, runtime `RUNTIME_OPERATIVO`, impacto automático `BLOQUEADO`.
- `ACT-0045` en `public.v_lf_fuente_operativa`: documental/operativo `APROBADO`, control `PRODUCCION_CONTROLADA`, runtime `APROBADO_PRODUCCION_CONTROLADA_READ_ONLY`, impacto automático `BLOQUEADO`.
- GitHub es capa técnica; el estado observado del repositorio no reemplaza el readback vivo de Supabase.

### Profiles

Perfiles reales observados bajo `profiles/` (excluyendo `_template`): 7.

La estructura no es uniforme. `evidence_lineage_reviewer_lf` se aproxima al superset del template; otros perfiles omiten distintas carpetas o manifests. `ui_architect`, por ejemplo, tiene `SKILL.md`, contratos, schemas, judges, evals, examples y validators, pero no replica el árbol completo del `_template`.

El `Profile Creator` moderno ya define la madurez por capacidades y evidencia, no solo por presencia nominal de archivos. Además, su CI descubre perfiles que publican `profiles/<slug>/validators/validate_pack.py`; perfiles sin ese entrypoint quedan fuera de esa frontera determinística y no deben considerarse validados implícitamente.

### Cards

- GitHub contiene una card mínima (`learning_competitive/campanas_y_ofertas`) y un pack mucho más desarrollado (`marketplace_lf/decision_product_experience`).
- `public.lf_cards` mantiene un registro plano con estados/tipos heterogéneos.
- El pack `decision_product_experience` no fue encontrado en `public.lf_cards` al readback de esta investigación.
- No se encontró evidencia de que el runtime de Profiles consuma ese pack o emita un receipt de Cards.

Conclusión: Cards existe como activo documental/ejecutable candidato, pero no está materializado en la trayectoria runtime de la familia elegida.

### Adapters

Adapters centrales observados en `adapters/`: `lf_shell_profile_adapter`, `marketplace_lf_cx_trust`, `marketplace_lf_ux`, `project_brand_mockup_render_lf`.

`public.v_lf_router_adapter_bindings` es una autoridad central ya existente. `ADAPTER-LF-SHELL-PROFILE-20260827` está ligado, entre otros, a `PERFIL-UI-ARCHITECT`, `PERFIL-PRODUCT-DIRECTOR-LF` y `PERFIL-GAMIFICATION-SYSTEM-ARCHITECT`.

Por tanto, replicar adapters dentro de cada Profile por obligación estructural duplicaría una responsabilidad ya centralizada.

### Input Governance

`INPUT_GOVERNANCE_AGENT` existe en `programacion.agentes`. La revisión observada más reciente del `INPUT_READINESS_CONTRACT` es `5.12`.

El conjunto vivo incluye contratos de readiness, manifest, freshness/delta, retrieval handles y module health. El diseño ya favorece referencias, snapshot hashes, recuperación JIT, secciones selectivas y fail-closed.

Sin embargo, el `INPUT_GOVERNANCE_EXECUTION_CONTRACT` observado declara `production_authorized=false`, `promotion_authorized=false` y `runtime_binding_status=UNBOUND_SEMANTIC_RUNTIME`.

Conclusión: la política es rica; el hueco es de binding E2E, no de falta de otra capa de políticas.

### Runtime

PR #503 endureció el transporte: HETZNER es el target principal/default y `GITHUB_ACTIONS` queda como backup explícito. Una petición HETZNER sin `runtime_request_envelope` bloquea; no existe downgrade silencioso permitido.

Readback de `private.lf_profile_runtime_queue_v1` durante esta investigación:

- `GITHUB_ACTIONS / SUCCEEDED`: 119.
- `GITHUB_ACTIONS / BLOCKED`: 39.
- `GITHUB_ACTIONS / PENDING`: 2.
- filas con `runtime_target='HETZNER'`: 0.

Las ejecuciones visibles de UI Architect/Product Director muestran trazabilidad de Profile + Adapter en el backup, pero no prueban HETZNER principal, Cards ni Input Governance dentro de la misma trayectoria.

## Matriz AS-IS → benchmark 2026 → GAP → recomendación

| Área | AS-IS LF | Benchmark 2026 | GAP | Recomendación mínima |
|---|---|---|---|---|
| Autoridad | Router + Supabase + ACT-0045 existen; docs GitHub pueden quedar desfasados | Una fuente de política compartida y contexto de ejecución separado del contexto LLM | Drift entre estado vivo y etiquetas del repo | Resolver autoridad viva al inicio y registrar ref/revisión/hash consumidos; no copiar estado canónico |
| Lifecycle Profile | Profile Creator moderno + template/standard antiguo más rígido | Pocas primitivas; lifecycle gobernado por resultados y gates, no por scaffolding nominal | Dos nociones de “pack completo” | `skills/profile_creator/contracts/main_contract.md` como mínimo técnico canónico; `_template` como superset de referencia |
| Policy inheritance | Existen mother rules, Input Governance y bindings | Política común compartida; herramientas/handoffs adaptan la misma política | Riesgo de forks locales | Referenciar contrato común y registrar receipt; prohibir copiar/reimplementar política salvo extensión explícita |
| Profiles | 7 perfiles con estructuras diferentes | Contratos/capacidades explícitas + validación observable | Cobertura CI desigual | Cada perfil gobernado publica validator local cuando se repare; no crear carpetas vacías solo para parecerse al template |
| Cards | Packs muy dispares; card robusta no está en `lf_cards` ni runtime | Contexto especializado recuperable JIT con provenance | Cards fuera de la trayectoria E2E | Extender el envelope/receipt existente con refs/hash/secciones de card; no crear un “Card Agent” nuevo |
| Adapters | Packs centrales + bindings Router canónicos | Capabilities pequeñas/componibles; no duplicar mediación | Template antiguo induce adapters locales | Adapter central por binding; Profile solo declara/consume el binding. Adapter local únicamente si hay transformación realmente específica |
| Input Governance | 5.12, JIT/ref/snapshot, pero semantic runtime unbound | Guardrails/policies en fronteras claras y fail-fast | Política existe pero no llega probada al runtime | Materializar `governance_receipt` en la misma ejecución antes de Profile/model; PASS-only cuando aplica |
| Runtime | HETZNER endurecido como principal; sin filas HETZNER observadas | Durable execution + evidencia del recorrido real | Transporte definido, E2E principal aún no demostrado | Golden Family debe producir una ejecución HETZNER real con persistence + readback; backup no satisface readiness principal |
| Evaluation | Validators/judges y pruebas aisladas existen | Evaluar trayectoria + outcome; múltiples graders/trials; capability y regression suites | No hay score familiar E2E común | Matriz inicial ~30 casos, pero solo después de Golden Family E2E; incluir assertions por etapa y estado final |
| Observability | Queue/receipt/attestation existen; adapter receipt visible en backup | Una traza E2E con spans y métricas por frontera | Cards/Input Gov/tokens/latencia no están completos en una sola traza | Reusar `request_id` como correlación raíz y persistir métricas por etapa; no crear almacén paralelo |
| Context efficiency | Input Gov ya propone selective/JIT; adapter capsule compacta | Menor conjunto de tokens de alta señal; recuperación JIT | Falta presupuesto medido por fuente/card/policy | Inyectar refs + secciones necesarias; medir tokens de input/output/cache y contribución por componente |

## Qué reutilizar / consolidar / retirar / crear

### Reutilizar

- `ACT-0001` y `public.v_lf_fuente_operativa`.
- `ACT-0045`.
- `skills/profile_creator/**` y su deterministic depth gate.
- `INPUT_READINESS_CONTRACT 5.12` y contratos asociados.
- `public.v_lf_router_adapter_bindings`.
- adapters centrales existentes.
- `private.lf_profile_runtime_queue_v1`, `receipt`, `runtime_attestation` y `runtime_request_envelope`.

### Consolidar

- Mínimo técnico de Profile en el `Profile Creator main_contract`.
- `_template` como referencia superset, no como lista universal de carpetas obligatorias.
- Binding de Input Governance y Cards dentro del envelope/receipt existente.
- Trazabilidad con un único `request_id` de punta a punta.

### Retirar como criterio

- “Todos los perfiles deben tener exactamente el mismo árbol”.
- Adapters locales duplicados cuando ya existe binding central.
- Copias completas de políticas/context packs en cada prompt.
- PASS por presencia de archivos.
- Uso de GitHub Actions como prueba del runtime principal.

### Crear solamente

- Contrato/fixture de **Golden Family** dentro de la capa de pruebas existente.
- Los campos/receipts mínimos que falten dentro del envelope/receipt actual.
- Validators locales faltantes al reparar cada Profile.

No crear: otro governance agent, otro router, otra tabla de trazas, otro registry de adapters o una segunda memoria paralela.

## Golden Family propuesta

`PERFIL-UI-ARCHITECT`
→ Card candidata `cards/marketplace_lf/decision_product_experience`
→ Adapter central `ADAPTER-LF-SHELL-PROFILE-20260827`
→ `INPUT_READINESS_CONTRACT 5.12` cuando aplique
→ HETZNER
→ modelo
→ validators/judges
→ `private.lf_profile_runtime_queue_v1`
→ readback del mismo `request_id`.

Razón: UI Architect ya tiene evidencia real de Profile + adapter en el runtime backup y tiene un caso de uso natural para la Card de decisión de producto/experiencia. El objetivo de Golden Family no es declarar que hoy está completa, sino cerrar exactamente los tramos faltantes y convertirla en patrón verificable antes de tocar las demás familias.

## Gate de éxito familiar

No declarar E2E PASS salvo que la misma ejecución pruebe:

1. Router decision.
2. Input Governance receipt o N/A gobernado.
3. Profile ref/version/hash.
4. Card refs/version/hash/secciones consumidas o N/A gobernado.
5. Adapter resolution + invocation receipt o N/A gobernado.
6. `runtime_target=HETZNER` para prueba del principal.
7. provider/model y resultado observable.
8. validators/judges ejecutados y resultados.
9. persistencia durable.
10. readback por el mismo `request_id`.
11. calidad/profundidad.
12. latencia por etapa y total.
13. tokens input/output/cache cuando el provider los exponga.
14. provenance/source snapshot.

Un PASS estructural, un merge, un resultado semántico aislado o una corrida en backup no sustituye este gate.

## Benchmark externo usado

Fuentes oficiales consultadas:

- OpenAI Agents SDK — pocas abstracciones, guardrails y tracing integrado: https://openai.github.io/openai-agents-python/
- OpenAI Agents SDK — tracing E2E con spans de agent/model/tool/handoff/guardrail: https://openai.github.io/openai-agents-python/tracing/
- OpenAI Agents SDK — separación entre local application context y LLM context: https://openai.github.io/openai-agents-python/context/
- Anthropic — Demystifying evals for AI agents (2026-01-09): https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents
- Anthropic — Harness design for long-running application development (2026-03-24): https://www.anthropic.com/engineering/harness-design-long-running-apps
- Anthropic — Effective context engineering for AI agents (2025-09-29, práctica vigente 2026): https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- OpenTelemetry — GenAI semantic conventions / usage and agent attributes: https://opentelemetry.io/docs/specs/semconv/registry/attributes/gen-ai/

## Siguiente secuencia gobernada

`Gobernanza transversal mínima`
→ `Golden Family contract`
→ `E2E Hetzner real`
→ `reparar Profile + Cards + Adapters usando evidencia de la Golden`
→ `matriz ~30 casos`
→ `actualizar perfiles existentes`
→ `crear nuevos perfiles`.

Bloqueo actual antes del E2E PASS: no se observó ninguna fila HETZNER en la cola y no se observó Cards/Input Governance materializados dentro de la misma trayectoria runtime.