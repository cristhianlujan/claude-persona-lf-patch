# PG-07_C3 — Proyección del contexto por tarea (2026-11-03)

## Objetivo

Preparar un contexto acotado para cada tarea del Worker, **sin cargar el repositorio entero, sin reenviar toda la especificación y sin truncar información material**, conforme al checkpoint PG-07_C3. La selección debe permitir reglas puntuales de backend, frontend, base de datos y contratos compartidos según la tarea, en lugar de documentos completos por defecto.

## Reutilización transversal

Se reutiliza `CONTEXT_BUDGET_GOVERNANCE`, documentado en `sandbox/lf_contract_gate_test/transversal_assets/context_budget_governance/README.md`. La autoridad activa compila `lf-context-admission/v1` mediante `public.fn_lf_router_preflight_v1(text)`, registra eventos en `private.lf_context_budget_events_v2` y permite readback por `public.v_lf_context_budget_latest_v2`. No crear un segundo motor ni un ledger alternativo.

La documentación transversal menciona estimación `UTF8_BYTES_DIV_4`, con respuestas `GREEN`, `YELLOW` y `RED` y límite configurable. **Los valores históricos no prevalecen** sobre la política CURRENT; no se codifican como máximos universales de modelo. La selección PG-07_C3 solo prepara insumos y no sustituye el preflight transversal.

## Componente candidato

`tools/pg07_c3_context_budget_projection_v1.py` expone:

`prepare_pg07_c3(pg07_c1, pg07_c2, model_context_profile, task_context_selections)`

- Valida los sobres C1/C2, hashes, identidad de corrida y ausencia de autoridad de despacho.
- Exige perfil explícito con proveedor, modelo, tamaño de ventana y reservas de salida, sistema y margen de seguridad. Los límites se derivan del **perfil declarado del modelo**, no de una cifra fija.
- Exige selección por cada solución, con un catálogo tipado de referencias `BACKEND_RULE`, `FRONTEND_RULE`, `DATABASE_RULE`, `STD`, `SKILL`, `CONTRACT`, `REQUIREMENT`, `ACCEPTANCE`, `TARGET_FILE` u otros materiales.
- Cada referencia incluye `ref_id`, `source_ref`, digest SHA256, obligatoriedad, `EAGER` o `JIT` y estimaciones de bytes/tokens. Prohíbe degradar referencias materiales obligatorias a opcionales.
- Mantiene un listado de contexto estable reutilizable entre lotes: `REGULATIONS`, `TECHNICAL_PROFILE` y `SOURCE_PACKAGE`, con referencias de caché, **sin afirmar aciertos reales de caché**.
- Calcula demanda estimada inmediata y máxima incluyendo JIT. Si excede la ventana de entrada declarada o los bytes máximos de la especificación del Worker, devuelve `BLOCK_CONTEXT_BUDGET`, sin autorizar truncamiento, y sugiere **repartir otra vez en PG-04 o recuperar la referencia exacta cuando corresponda**.
- Una proyección dentro de límites se marca `ESTIMATE_WITHIN_DECLARED_BOUNDS_UNVERIFIED`: **no es un PASS ni autoriza el despacho**.

### Límites de evidencia

El componente no abre archivos, no verifica que las referencias seleccionadas representen toda la materia obligatoria del paquete real, no mide el tokenizador del proveedor, no llama a `fn_lf_router_preflight_v1` y no lee `lf_context_budget_events_v2`. La completitud se evalúa **solo dentro del catálogo declarado**. Por lo tanto, el runtime gobernado debe comparar esa selección con el paquete fuente íntegro y el catálogo de reglas vigentes, ejecutar el control de presupuesto transversal y obtener un recibo CURRENT antes de entregar el contexto al modelo.

Flags de salida: `reference_sources_verified=false`, `token_estimates_authenticity_verified=false`, `active_policy_readback_verified=false`, `router_context_admission_executed=false`, `context_budget_ledger_receipts_verified=false`, `material_truncation_allowed=false`, `dispatch_allowed=false`, `worker_invoked=false`, `production_authority=false`.

## Estado

`PG07_C3_SOURCE_CONTEXT_PROJECTION_READY / LIVE_CONTEXT_GOVERNANCE_NOT_RUN / MATERIAL_COMPLETENESS_UNVERIFIED / OFFICIAL_PENDING`.

La instrucción del Owner de aplazar las pruebas sigue vigente. No se modifican Análisis, Supabase, main ni las rutas de runtime. Siguiente: PG-07_C4, contrato primero, estándares y formateo antes de entregar un patch.
