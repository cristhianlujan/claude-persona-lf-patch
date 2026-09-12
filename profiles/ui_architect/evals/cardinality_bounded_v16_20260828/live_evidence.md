# V16 Cardinality-Bounded Minimal Spec — live evidence

Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260828-007`
Base main: `438e8da709fa391b72cd909aeb9fbfd9f60f6562`
Scope: profile-local only.

## Runtime evidence before write
V15 post-merge Canary B `6edbe5c2-cc41-4531-8cb4-a617df398cc0` / run `33203183618` passed the exact unresolved-authority short-circuit.

V15 post-merge Canary A `7f97961a-3afd-4d8a-9a3c-d08fc4160103` / run `33203177976` was authentic `MODEL_RUNTIME / ZERO_COST_ONLY` and chose the correct semantic direction, but repeated `top_amount_strip` component objects until truncation. The output was incomplete and cannot be treated as semantic/structural PASS.

## V16 correction
V16 keeps the unresolved branch unchanged and changes only the resolved checkout serialization:
- exact `component_tree` cardinality = 2;
- each duplicate component appears once;
- explicit close-after-second-component sentinel;
- one remediation action;
- a shorter validator-compatible Production UI Spec literal;
- root-tail fields remain root siblings;
- no Markdown fences or prose.

No Router, runtime adapter, schema, validator, Supabase schema, production state, VALIDATED state, runtime enablement, or automatic-promotion change is included.

## Closure gate
P1 remains open until exact-head CI, merge/readback, and fresh post-merge zero-cost MODEL_RUNTIME canaries A+B both pass.
