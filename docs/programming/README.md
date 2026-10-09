# Programming Governance Docs

## Start here

### Reusable validators and resolvers

Canonical guide:

- `PROGRAMMING_VALIDATORS_AND_RESOLVERS_GUIDE_V1.md`

Supabase discovery capability:

- `PROGRAMMING_VALIDATOR_RESOLVER_CATALOG`

Live registries:

- `programacion.programming_validation_registry`
- `programacion.programming_resolver_registry`
- `programacion.programming_checkpoint_bindings`
- `programacion.programming_resolution_receipts`

Rule of use:

```text
SEARCH EXISTING VALIDATOR
        ↓
same deterministic procedure?
   YES -> reuse + validation_input
   NO  -> qualify a new validator
        ↓
always execute against current state
        ↓
new current-run receipt
```

Never use a prior runtime PASS to close a new checkpoint.

### Simple executor

- `PROGRAMMING_SIMPLE_EXECUTOR_V1.md`

This executor uses the validator/resolver registries above and keeps dependencies as state preconditions only.
