# D09 — Inventario de ejecuciones y recibos canónicos (Paulo)

**Fecha:** 2026-10-31. **Estado:** verificación de catálogo, SOLO LECTURA; no acreditar ni cerrar PG.

## Hallazgos verificados en Supabase RO

| Objeto | Identidad clave | Utilidad y límite |
|---|---|---|
| `public.lf_operation_execution` | `execution_id`, `operation_code`, `target_type`, `target_code`, `manifest`, `request_sha256`, `checkpoint_seq` | Registro genérico de operaciones; no establece por sí solo un `RunContract` PIP-1 |
| `private.lf_orchestrator_dispatch_receipts_v1` | `orchestrator_execution_id`, `consumer_execution_id`, `capability_code`, `plan_digest`, `receipt_sha256` | Recibo de despacho vinculado a un orquestador; no equivale a PASS de un checkpoint PG |
| `programacion.engineering_checkpoint_closure_providers_v1` | `plan_code`, `unit_code`, `checkpoint_code`, `provider_fn`, `binding_state` | Proveedores de cierre existentes; **0 filas** para `PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1` en esta consulta |
| `programacion.programming_simple_runs` | `id`, `plan_code`, `status` | **0 runs** para el plan PG en esta consulta; no interpretar como ausencia de cualquier otro orquestador |
| `programacion.programming_resolution_receipts` | `run_id`, `plan_code`, `unit_code`, `checkpoint_code`, `validation_code`, `failure_receipt_sha256` | Recibos de resolución, no acreditación de PASS por sí mismos |
| `programacion.engineering_work_checkpoints` | `work_item_id`, `checkpoint_code`, `status`, `assertion_receipt`, `assertion_receipt_sha256` | Ledger de estado/recibo. No contiene por sí mismo prueba independiente del proveedor |

## Decisión

- **No crear otro ledger, verificador de hashes o autorizar transiciones usando JSON aportado por el chat.**
- El núcleo `pip1_core` sigue aislado; `operational=True` falla cerrado. Un `RunContract` de fixture NO es el run auténtico del sistema.
- Los jueces existentes de `engineering_checkpoint_closure` son para cierre gobernado y requieren readback de autoridad en runtime. No trasladarlos sin contrato a PIP-1.
- Simple Executor y PIP-1 Carril D no han sido demostrados como el mismo componente. No atribuirle al segundo las 0 ejecuciones del primero.

## Próximo trabajo que desbloquea la ejecución

1. Identificar en el Carril D el dueño previsto del **runtime PIP-1** y su `run_id` canónico, `execution_id`, `inventory_sha256`, `head_sha` y persistencia; verificar si ya hay propuesta en PR/carril antes de crear tablas.
2. Elegir explícitamente quién verifica el recibo independiente de cada checkpoint y con qué contrato de identidad/proveedor, reutilizando la infraestructura de cierre existente cuando aplique.
3. Exigir pruebas negativas: distinto `run_id`, distinto HEAD o inventario, recibo de fixture, proveedor cruzado, replay y readback obsoleto; ningún caso puede acreditar `SUCCEEDED_ACCREDITED`.
4. Construir solo el adaptador faltante y ensayarlo sobre una ejecución sintética aislada; autorización operacional requiere revisión y GO separado.

**Estado del PR:** Draft de programación asistida, no pipeline productivo. Sin SQL de escritura, sin registro de PASS/DONE y sin autoridad del chat.
