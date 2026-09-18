# CONTEXT_BUDGET_GOVERNANCE

Inventory status: `ACTIVE_SHARED_ENFORCEMENT`.

## Propósito

Capability transversal que hace observable y fail-closed el tamaño del contexto compilado antes de entregarlo al modelo. Reutiliza el ledger existente y el Router context admission; no es un segundo engine de contexto.

## Cuándo consumirlo

En toda ejecución que produzca un `lf-context-admission/v1` receipt. El budget se evalúa después de resolver BASE + sets condicionales y antes de entregar contexto al modelo.

## Cómo consumirlo

1. `public.fn_lf_router_preflight_v1(text)` compila el receipt.
2. Estima tokens con `UTF8_BYTES_DIV_4`.
3. Registra el resultado en `private.lf_context_budget_events_v2`.
4. `GREEN`: continuar.
5. `YELLOW`: evitar prefetch adicional y preferir JIT.
6. `RED`: bloquear con `BLOCK_CONTEXT_BUDGET_HARD_LIMIT`.
7. Consultar `public.v_lf_context_budget_latest_v2` para readback.

## Superficies canónicas

- Compiler/enforcement: `public.fn_lf_router_preflight_v1(text)`
- Ledger: `private.lf_context_budget_events_v2`
- Latest readback: `public.v_lf_context_budget_latest_v2`
- Policy config: `POL-LF-POLICY-CONSUMPTION v1.2-context-admission`
- Asset inventory: `public.lf_activos.codigo_activo=CONTEXT_BUDGET_GOVERNANCE`

## Fail-closed / límites

El soft limit actual es 1.500 tokens estimados y el hard limit 3.000. RED bloquea. No usar prompt caching como sustituto de reducción de contexto. No hidratar policies, EKB o README completos sólo para medirlos.

## Validación y readback

Exigir evento de budget por preflight, `context_status`, `estimated_tokens`, source `ROUTER_CONTEXT_ADMISSION_V1` y vínculo al evidence event. Validar canarios GREEN y un negativo que exceda hard limit y bloquee.

## No duplicación

No crear otra tabla de budget, otro contador de tokens o un segundo context compiler. Esta capability envuelve las superficies existentes.

## Currentness

Releer `public.lf_activos`, la policy de consumo activa, la definición de `fn_lf_router_preflight_v1` y el latest budget readback. Un límite histórico no prevalece sobre la policy activa.
