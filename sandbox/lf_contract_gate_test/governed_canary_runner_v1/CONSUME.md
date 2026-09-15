# Consume LF_GOVERNED_CANARY_RUNNER_V1

Use this component only after resolving `CAPABILITY.json`. Do not infer availability from the PR, chat history, or the existence of the Python file.

## Resolve first

```bash
python3 sandbox/lf_contract_gate_test/governed_canary_runner_v1/resolve_capability.py --mode REPOSITORY_ONLY
```

Proceed only when the resolver returns `AVAILABLE` for the requested mode. `BLOCKED` and `STALE` are terminal for that invocation.

## Execution contract

The generic runner owns only the safety envelope:

`preflight -> forward -> tests -> rollback(always) -> post_readback -> evidence`

The consumer owns domain semantics through a manifest or adapter. Never patch the generic runner to make one consumer pass.

Required target state:

- sandbox, ephemeral or test environment;
- `production=false`;
- `merge_authorized=false`;
- `automatic_promotion=false`.

Required evidence:

- exact source/runtime fingerprints appropriate to the domain;
- bounded step duration and return status;
- rollback attempted after every forward attempt;
- post-readback from the real destination;
- executable zero-residue assertion;
- sanitized evidence only; no raw secrets or raw stdout/stderr.

## Entrypoint

```bash
python3 sandbox/lf_contract_gate_test/governed_canary_runner_v1/lf_governed_canary_runner.py --manifest <manifest.json>
```

Use `--plan` to validate a manifest without executing it.

## Current availability

Read `CAPABILITY.json` at execution time. Availability is mode-specific. A mode marked `AVAILABLE` does not authorize another mode and never authorizes production or automatic promotion.

## Discovery without prior context

Canonical lookup order:

1. Strategy 28 snapshot id `31`, payload key `lf_governed_canary_runner_v1`.
2. Package locator `CAPABILITY.json`.
3. Run `resolve_capability.py --mode <MODE>`.
4. Read this card and the YAML contract only when the resolver allows the mode.

Aliases for search: `CANARY_RUNNER_LF`, `GOVERNED_CANARY_RUNNER`, `ROLLBACK_CANARY_RUNNER`, `zero-residue`, `rollback canary`.
