# PLAN_AUTHORITY_DRIFT_GUARD_V1

## Propósito

`SADM-PP-L1-010` generaliza el patrón `anchor inmutable + readback live + digest` sin crear un segundo motor de currentness.

Flujo:

`caller -> ORCHESTRATOR_ENTRY_GUARD -> PLAN_AUTHORITY_DRIFT_GUARD -> CURRENTNESS_AUTHORITY receipt -> anchor/delta reconciliation -> typed receipt`

Sin `ORCHESTRATOR_ENTRY_ACCEPTED` el guard bloquea. La validación local de shape no sustituye al guard live.

## Autoridades reutilizadas

- Anchor: parámetro resolver-backed con identidad/digests inmutables.
- Fixture bootstrap verificado: `lf_eventos #19435`, `LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1`.
- Currentness: `CURRENTNESS_AUTHORITY` v1.0.0; este adapter consume su receipt y no reimplementa su engine.
- Envelope común: `CAPABILITY_EXECUTION_CONTRACT_V1`.
- Administración: `LF_GOVERNANCE` / Super Admin.

## Bootstrap verificado

Desde el payload inmutable #19435 se reprodujeron exactamente:

- `workstream_sha256 = 5c0e0be6536ad6dd602327b3ffb95955f471bce8b88afad18c0918108820311b`
- `work_items_sha256 = 67f64cdb37232bc34f77719988dfc47a9f1b9072cf1c0e358ff092d23256d744`
- `dependencies_sha256 = c136092312436cfce82e9e1ea5d7448b9fc036a8c88de3dc93f7f7f2555725e5`

Cada componente es `SHA-256(UTF-8(jsonb::text))`.

El composite histórico `plan_digest = 9b234da6cdec56c141cc452e3997650c93cdf3a27f64d9b5858bea311476c648` se conserva como token inmutable de autoridad porque su fórmula de composición no está documentada en source. Esta solución no inventa esa fórmula.

El runtime no hardcodea #19435 ni el plan ID: ambos llegan en el anchor validado. El test incluye otro plan/evento para demostrarlo.

## Decisiones

- `MATCH`: hashes live iguales al anchor y `request.plan_digest` igual al token anchor.
- `AUTHORIZED_DELTA`: live difiere, pero una cadena append-only con receipts de autoridad válidos parte del anchor, termina en `request.plan_digest` y sus hashes finales coinciden con live.
- `UNREGISTERED_DRIFT`: falta o falla prueba de entrada, currentness, identidad, autoridad, componentes o deltas. `ready=false`.

## Autorización de delta

Un delta no es autorizado por declararse a sí mismo. Cada delta debe incluir `authorization_proof` con schema `LF_PLAN_DELTA_AUTHORITY_READBACK_V1`, authority `PLAN_AUTHORITY` y decisión `AUTHORIZED_PLAN_DELTA`.

El receipt:
- cross-bindea event id, plan id, previous digest y next digest;
- tiene digest determinista propio;
- debe estar también en `request.authority_refs.plan_delta_authority_receipt_digests`.

Si falta esa ligadura, el resultado es `UNREGISTERED_DRIFT`. La validación de shape local nunca es autoridad.

## Input live canónico

El adapter hashea strings canónicos emitidos por readback DB (`jsonb::text`) en lugar de emular la serialización JSONB de PostgreSQL en Python.

Campos requeridos:
- `plan_id`
- `workstream_canonical_text`
- `work_items_canonical_text`
- `dependencies_canonical_text`

## Integridad de delta

Cada delta cross-bindea `delta_event_id`, `plan_id`, `previous_plan_digest`, `next_plan_digest`, los tres hashes componentes y el digest del receipt de autorización. `delta_digest` usa `LF_PLAN_AUTHORITY_DELTA_SHA256_V1`. Cadena rota, tampering, proof inválido, proof no ligado al request, delta faltante o request ligado a otro digest bloquean.

## Owner / runner / carrier

El asset queda source-ready pero `CANDIDATE_READ_ONLY`. `OWNER_RUNNER_CARRIER_AUTHORITY_V1` exige que un standalone resuelva por autoridad canónica; por eso esta unidad no declara runner ejecutable ni cutover.

La proyección source-only falla cerrada si `LF_GOVERNANCE`, `CAPABILITY_EXECUTION_CONTRACT` o `CURRENTNESS_AUTHORITY` no están materializados en `lf_activos`.

## Test

`python sandbox/lf_contract_gate_test/plan_authority/test_plan_authority_drift_guard_v1.py`

Esperado: `PASS_PLAN_AUTHORITY_DRIFT_GUARD_V1 checks=13`.

## No hace

- no crea tabla/RPC/ledger;
- no edita anchors;
- no acepta deltas solo por shape;
- no ejecuta runtime;
- no activa producción;
- no crea current pointer;
- no sustituye `CURRENTNESS_AUTHORITY`.
