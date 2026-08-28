# UI V16 Runtime Repeat Guard — 2026-08-28

Canonical profile update execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`.

## Reproduced runtime evidence

- V15 Canary B `6edbe5c2-cc41-4531-8cb4-a617df398cc0` / run `33203183618`: PASS, exact unresolved-authority fail-closed output on `main@438e8da709fa391b72cd909aeb9fbfd9f60f6562`.
- V15 Canary A `7f97961a-3afd-4d8a-9a3c-d08fc4160103` / run `33203177976`: authentic `ZERO_COST_ONLY` MODEL_RUNTIME on the same main. It selected the correct semantic direction and started the governed Production UI Spec, but repeatedly emitted the identical `top_amount_strip` component until the 2048-token output was truncated.

## V16 change

The pinned GitHub-hosted llama.cpp adapter adds an explicit, attested sampling guard:

- `--repeat-penalty 1.15`
- `--repeat-last-n 256`

The verifier requires the same values in the runtime attestation. No model, model digest, source commit, zero-cost policy, profile contract, Router, Supabase schema, or lifecycle state changes.

## Acceptance

Fresh post-merge A+B must both execute on the exact merged main SHA with verified zero-cost attestation. A must produce one complete executable JSON object without component repetition or truncation; B must preserve the exact unresolved-authority Missing Input State.
