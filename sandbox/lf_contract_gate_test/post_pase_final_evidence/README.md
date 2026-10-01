# POST_PASE_FINAL_EVIDENCE_V1

Capability source-only `FINAL_EVIDENCE` para `SADM-PP-L3-016`.

## Entrada

`caller -> ORCHESTRATOR_EXECUTION_GUARD_V1 -> FINAL_EVIDENCE`.

Se requiere ejecución válida del orquestador, `plan_digest` cross-bound y proof de `PLAN_AUTHORITY_DRIFT_GUARD_V1` con decisión `MATCH` o `AUTHORIZED_DELTA`.

## Reutilización obligatoria

- `PLAN_AUTHORITY_DRIFT_GUARD_V1`: identidad/autorización del plan; sigue source-only.
- `EVIDENCE_LEDGER`: receipts append-only existentes; registrado/guarded, sin current pointer.
- `EVIDENCE_RESOLVER_REGISTRY@1.0.0`: resolver trusted provider-bound.
- `TYPED_EVIDENCE_REGISTRY@3.0.0`: schemas tipados.

No se crea evidence store, registry de receipts ni engine paralelo.

## Manifest

`LF_POST_PASE_FINAL_EVIDENCE_MANIFEST_V1` contiene únicamente:

- identidad `post_pase_execution_id`, `orchestrator_execution_id`, `plan_id`, `plan_digest`, `merge_sha`;
- `controls_digest` del conjunto exacto declarado por el plan;
- controles `REQUIRED` y `NOT_APPLICABLE`;
- para cada control REQUIRED: `receipt_id` + `receipt_sha256`;
- `manifest_sha256` sobre JSON canónico.

La evidencia cruda, `verification_payload` y payloads de dominio no se copian al manifest.

## Fail closed

Bloquea si ocurre cualquiera de estos casos:

- entrada del orquestador ausente o cross-bind incorrecto;
- plan proof inválido o controls digest diferente;
- control duplicado/desconocido;
- falta receipt para un REQUIRED;
- receipt adicional o para un NOT_APPLICABLE;
- receipt no `VERIFIED`;
- receipt con `source_head_sha != merge_sha`;
- receipt con `plan_digest` diferente;
- receipt id duplicado o digests inválidos.

## Separación de responsabilidades

FINAL_EVIDENCE no reejecuta controles, no calcula closure verdict, no promueve current pointers, no muta lifecycle y no activa runtime/cutover/producción. `SADM-PP-L3-017` conserva la responsabilidad de Closure Gate.

## Materialización

Esta solución queda source-only. La proyección SQL candidata falla cerrado mientras falten las autoridades live requeridas, incluyendo `PLAN_AUTHORITY_DRIFT_GUARD` y currentness ejecutable del `EVIDENCE_LEDGER`. No aplicar esta proyección dentro de L3-016.

## Test

`python sandbox/lf_contract_gate_test/post_pase_final_evidence/test_final_evidence_v1.py`
