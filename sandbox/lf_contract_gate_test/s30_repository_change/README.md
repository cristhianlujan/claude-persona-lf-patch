# S30 — REPOSITORY_CHANGE_LF source candidate

This package defines the transversal governance envelope for repository mutation. It deliberately does **not** implement another Git transport, another source-attestation system, or another currentness engine.

## Live problem

Seven operational LF operations currently carry active `github_write` followed by `github_readback` steps:

- `ACTUALIZACION_ADAPTER_LF`
- `ACTUALIZACION_PERFIL_LF`
- `ACTUALIZACION_SKILL_LF`
- `CREACION_CARD_LF`
- `CREACION_ESTRATEGIA_LF`
- `CREACION_PERFIL_LF`
- `CREACION_SKILL_LF`

Their business payloads differ, which is legitimate, but they repeat the repository-mutation responsibility. Two creation lanes (`CREACION_CARD_LF`, `CREACION_SKILL_LF`) also currently lack active judge bindings for those GitHub steps; that owner gap is recorded here and is **not** silently repaired by this package.

`GITHUB_CONTRACT_GATE_LF` is an operational read-only contract gate, not a generic repository writer.

## Existing transport reused

S30 already has `S30_GIT_WRITE_BROKER_V2` in `.github/workflows/validate-lf-packs.yml`. Its governed path proves several important properties: exact main/base binding, exact staging SHA, ancestry, bounded changed paths, governed DeployKey use, protected S30 target namespace, and post-push remote SHA readback.

That broker is intentionally scoped to `lf/s30-*`; this package does not relabel it as a universal LF writer.

S31 PR #778 is separately productizing material currentness/source-attestation semantics. `REPOSITORY_CHANGE_LF` consumes an authority receipt from that layer rather than reimplementing it.

## Contract boundary

A repository change has two durable objects:

1. `LF_REPOSITORY_CHANGE_REQUEST_V1` — binds owner, operation, execution, repository, target branch, expected HEAD, allowed/requested paths, idempotency key, canonical request SHA, governed transport provider, and authority receipt.
2. `LF_REPOSITORY_CHANGE_RECEIPT_V1` — binds the same request identity to before/after heads, exact changed paths, content/blob readback, provider version, and remote-head readback.

The request SHA is computed from canonical sorted-key UTF-8 JSON **excluding the `request_sha256` field itself**.

## Unknown outcomes

An ambiguous transport result must not be converted into a guessed PASS or an automatic retry. It emits:

`RECONCILIATION_REQUIRED_UNKNOWN_OUTCOME`

In that state the receipt must not assert `after_head`, remote head, changed paths, or content readback. A later reconciler determines what actually happened. Blind redispatch is forbidden.

## Merge separation

A successful repository write never authorizes merge to `main`. `merge_authorized` is explicitly false in the receipt contract. Merge remains a separate authority/human gate.

## Claim ceiling

`SOURCE_CANDIDATE_NO_REPOSITORY_MUTATION`.

This package performs no Git write, no Supabase mutation, no migration apply, no runtime/production/Golden activation, and no merge-main.
