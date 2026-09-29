# GITHUB_PROVIDER_READBACK_V1

## Alcance

Una sola solución transversal: centralizar el transporte/readback HTTP de GitHub consumido por `GITHUB_CONTRACT_GATE_LF` y E.16, evitando clientes ad hoc por consumer.

## Autoridades

- Router de entrada: `ACT-0001`.
- Operación de actualización del activo registrado: `ACTUALIZACION_DB_LF` para `CAPABILITY/UPDATE`, según `public.lf_router_action_registry`.
- Owner del transport/readback GitHub del contract gate: `GITHUB_CONTRACT_GATE_LF`.
- Registry de identidad/trust de resolvers de evidencia: `EVIDENCE_RESOLVER_REGISTRY`.
- El registry no es un transport HTTP y el transport no inventa `resolver_id`.

## Flujo

```text
ACT-0001
  -> GITHUB_CONTRACT_GATE_LF
  -> github_api_readback_v1.py
  -> GitHub provider
  -> respuesta autenticada
  -> consumer E.16 valida exact-head/matriz
```

Cuando el resultado deba anclarse en el evidence ledger:

```text
consumer
  -> EVIDENCE_RESOLVER_REGISTRY
  -> resolver_id semánticamente compatible
  -> evidence ledger
```

Si no existe resolver compatible, `BLOCKED`; no reutilizar `LF_GITHUB_SOURCE_READBACK_V1` para Actions inventory.

## Resiliencia

- 3 intentos máximos.
- Backoff determinista y acotado.
- Retry: red, 408, 429, 500, 502, 503, 504.
- No retry: 401/403, JSON/shape/tamaño inválido, HTTP no transitorio.
- Clasificación: `BLOCKED_INFRA_DNS`, `BLOCKED_GITHUB_API`, `FAIL_AUTH`, `FAIL_GITHUB_API`, `FAIL_EVIDENCE_MISMATCH`.
- Todo agotamiento o error permanece fail-closed.

## Pruebas

`test_github_api_readback_v1.py` cubre success, DNS agotado, HTTP transitorio con recuperación, auth sin retry, evidencia mal formada y HTTP no reintentable.

E.16 mantiene sus matrices existentes y delega únicamente transporte/retry al boundary.

## Límites

- No merge.
- No producción/runtime activation.
- No nuevo Router, writer, registry ni engine de gates.
- No modificación de Supabase en este PR candidato.
- No cambio de semántica de los resolvers existentes.
