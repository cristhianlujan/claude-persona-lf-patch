# CAPABILITY_EXECUTION_CONTRACT_V1

Contrato transversal de invocación/receipt para capacidades consumidas por PASE, POST-PASE, Assurance y otros orquestadores gobernados.

## Punto de entrada único

```text
Cualquier caller
     |
     v
CAPABILITY_EXECUTION_CONTRACT
     |
     +-- ¿trae ejecución/dispatch receipt válido del ORQUESTADOR?
     |       |
     |       +-- NO -> BLOCK
     |       +-- SI
     |
     v
request envelope exacto
     |
     v
capability owner/runner
     |
     v
receipt exacto + Evidence Ledger
```

La autenticidad no la decide este código. La autoridad live sigue siendo:

- `public.fn_lf_orchestrator_dispatch_receipt_v1`;
- `public.fn_lf_capability_orchestrator_entry_guard_v1`;
- `public.fn_lf_capability_bind_from_orchestrator_v1`.

La validación local del `entry_guard_readback` solo comprueba forma y cross-binding. Nunca convierte un JSON en autoridad.

## Autoridades reutilizadas

- owner administrativo: `LF_GOVERNANCE_SUPER_ADMIN_V1`;
- owner/runner/carrier: `OWNER_RUNNER_CARRIER_AUTHORITY_V1`;
- dispatch receipt: `private.lf_orchestrator_dispatch_receipts_v1`;
- ejecución: `public.lf_operation_execution`;
- evidencia: `private.lf_evidence_ledger_v1` + `public.fn_lf_evidence_ledger_anchor_v1`.

No se crea otro registry de owners, otro receipt store ni otro evidence ledger.

## Request envelope

`LF_CAPABILITY_EXECUTION_REQUEST_V1` cross-bindea:

- `orchestrator_execution_id`;
- `consumer_execution_id`;
- `capability_code`;
- `plan_digest`;
- `dispatch_receipt_id`;
- `dispatch_scope` + digest;
- `authority_refs` con revision y digest;
- `input_ref` + `input_digest`;
- `source_revision`;
- `request_digest` canónico.

## Receipt envelope

`LF_CAPABILITY_EXECUTION_RECEIPT_V1` consume el `request_digest` exacto y preserva todos los cross-bindings. Agrega:

- `output_ref` + `output_digest`;
- `evidence_refs` con digest;
- `receipt_digest` canónico.

El receipt no autoriza downstream y no puede autocertificarse.

## Boundary

Este paquete define/valida el envelope. No:

- decide applicability;
- crea un Orchestrator receipt;
- autentica por sí solo un receipt;
- registra una capability en `lf_capability_registry`;
- activa CURRENT;
- ejecuta carriers;
- hace cutover;
- activa runtime o producción.

## Relación con L1-008

`OWNER_RUNNER_CARRIER_AUTHORITY_V1` resuelve quién debe ejecutar y dónde vive el carrier. Este contrato transporta esa resolución dentro de una ejecución exacta; no la reemplaza.

## Relación con Evidence Ledger

El receipt final referencia evidencia, pero la verificación/provider binding y la composición anti-replay siguen siendo autoridad de Evidence Ledger. El contrato no emite verdicts globales por sí mismo.

## Estado

`CANDIDATE_READ_ONLY`. La proyección SQL es source-only y debe fallar si las dependencias de inventario aún no están materializadas. No hay aplicación Supabase, cutover, runtime ni producción autorizados por este artefacto.
