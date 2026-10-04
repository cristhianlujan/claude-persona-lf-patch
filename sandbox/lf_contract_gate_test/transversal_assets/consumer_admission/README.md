# CONSUMER_ADMISSION

Capacidad transversal LF para admisión gobernada por consumer. Extrae el patrón reusable demostrado por N-13 y N-15 sin reabrir ni modificar esas unidades.

## Estado y ownership

- Capability: `CONSUMER_ADMISSION`.
- Owner scope: `SUPER_ADMIN`.
- Versión inicial: `1.0.0`.
- IG role: `CONSUMER`, nunca owner.
- Entrada gobernada: `ORCHESTRATOR_EXECUTION_GUARD_V1`.
- Runtime/production activation: no incluida en T-CONS-ADM.

## Autoridades reutilizadas

`CONSUMER_ADMISSION` no replica semántica de vigencia, compatibilidad o retiro:

- `CURRENTNESS_AUTHORITY`: prueba de vigencia mediante receipt `LF_CURRENTNESS_AUTHORITY_RECEIPT_V1`.
- `CAPABILITY_VERSION_COMPATIBILITY`: identidad/versionado resuelto por `lf_capability_current` + `lf_capability_version_registry`.
- `ASSET_RETIREMENT_GOVERNANCE`: hook gobernado para drain/retirement, reutilizado desde T-CONSUMERS.

Los pins de estas dependencias viven en el manifest versionado de `CONSUMER_ADMISSION`; drift de versión o manifest de una dependencia produce `UNKNOWN` y no false-green.

## Contrato genérico

Input por consumer:

```json
{
  "consumer_ref": "OPAQUE_CONSUMER_ID",
  "applicability": "APPLICABLE|NOT_APPLICABLE|UNKNOWN",
  "requiredness": "REQUIRED|OPTIONAL|NOT_APPLICABLE",
  "capability": {
    "code": "CAPABILITY_CODE",
    "version": "x.y.z",
    "manifest_sha256": "64-hex"
  },
  "currentness": {
    "schema_version": "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1",
    "authority_layer": "CURRENTNESS_AUTHORITY",
    "decision": "CURRENT|CURRENT_REBOUND|STALE_AFFECTED|UNKNOWN_FAIL_CLOSED",
    "ready": true
  },
  "receiver_status": {
    "state": "PASS|HOLD|BLOCK|UNKNOWN",
    "receipt_ref": "..."
  }
}
```

Output gobernado: exactamente uno de `PASS`, `HOLD`, `BLOCK`, `NOT_REQUIRED`, `UNKNOWN`.

- `PASS`: consumer aplicable, capability/version exacta y current, receipt de currentness válido/current y receiver `PASS` con receipt.
- `HOLD`: consumer aplicable no requerido o receiver en hold; no autoriza aggregate PASS si es `REQUIRED`.
- `BLOCK`: consumer `REQUIRED` con capability/version/currentness o receiver materialmente no admitido.
- `NOT_REQUIRED`: consumer no aplicable y no contradictorio con requiredness.
- `UNKNOWN`: autoridad, applicability, currentness o identidad no resoluble. Se conserva como desconocido; no se transforma en autorización.

## Truthful aggregate

`public.lf_consumer_admission_aggregate_v1` aplica estas reglas:

1. Cualquier `REQUIRED` en `BLOCK` impide aggregate `PASS`.
2. Cualquier `REQUIRED` en `HOLD` impide aggregate `PASS`.
3. `REQUIRED + UNKNOWN` es fail-closed por policy por defecto y retorna aggregate `BLOCK`.
4. `OPTIONAL`/`NOT_APPLICABLE` no vetan globalmente por defecto.
5. Un veto de `OPTIONAL` solo existe si `optional_nonpass_veto=true` y hay `policy_proof_ref` explícita.

## False-green y stale history

- Misma value/receiver status no prueba compatibilidad.
- Una versión o manifest stale nunca produce `PASS`, aunque el receiver declare el mismo valor y `PASS`.
- Historia stale es legible como evidencia histórica, nunca como autorización actual.
- No existe fallback semántico local por igualdad de valores.

## Drain / retirement

El resultado expone `retirement_hook=ASSET_RETIREMENT_GOVERNANCE`.

`CONSUMER_ADMISSION` no decide ni ejecuta retirement. La capacidad de retiro existente debe verificar drain/zero-residual y la autoridad de cutover correspondiente. N-15 permanece prior art histórico; T-CONS-ADM solo generaliza su patrón.

## Pruebas obligatorias incluidas

La migración fuente ejecuta pruebas fail-fast para:

- IG consumer positivo usando el mismo contrato transversal.
- Segundo consumer fuera de IG: `GITHUB_CONTRACT_GATE_LF`.
- misma value + versión stale => no `PASS`.
- `REQUIRED HOLD` + otros consumers `PASS` => aggregate no `PASS`.
- `OPTIONAL HOLD` no veta sin policy proof.
- `REQUIRED UNKNOWN` => aggregate fail-closed según policy.
- binding IG mediante dispatch receipt + `fn_lf_capability_bind_from_orchestrator_v1`, con exact current readback.

## Prior art preservado

- `N-13 / PAULO-178`: currentness en continuation + aggregate requiredness.
- `N-15 / PAULO-180`: capability/version-aware consumers, false-green prevention y drain explícito.
- `T-CONSUMERS / PAULO-026`: autoridad reusable de retirement.

N-13 y N-15 no son modificados por esta entrega.

## Fuentes

- `supabase/migrations/20261004145730_t_cons_adm_consumer_admission_v1.sql`
- `sandbox/lf_contract_gate_test/transversal_assets/consumer_admission/README.md`
