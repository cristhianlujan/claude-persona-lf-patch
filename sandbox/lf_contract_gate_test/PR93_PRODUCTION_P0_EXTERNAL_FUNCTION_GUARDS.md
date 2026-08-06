# PR93 · Production readiness P0 · external function search paths

## Objective

Fix mutable `search_path` on the 12 externally executable non-trigger functions reported by the Security Advisor, without expanding schema access or inventing callers.

## Classification

### Pure/read functions

The following functions retain their existing EXECUTE behavior and receive only a fixed search path:

- `lf_ops.fn_b2b_native_numeric_id`
- `lf_ops.fn_normalize_relation_segment`
- `lf_ops.fn_relation_code`
- `public.fn_kb_quality_score`
- `public.lf_validar_cierre_verificacion`
- five `sbx_lf_validation_engine_*` validators.

The `lf_ops` schema remains unavailable to `anon`, `authenticated` and `service_role`; no `USAGE` grant is introduced.

### State-mutating functions

`public.fn_restock_url_queue` writes queue records. Its established controlled caller is `service_role`:

- `anon EXECUTE=false`;
- `authenticated EXECUTE=false`;
- `service_role EXECUTE=true`.

`public.lf_register_strategy_event` writes canonical events. `service_role` cannot satisfy the private event-contract trigger under the current grants. Rather than opening the private schema, execution is restricted to the owner/admin path:

- `anon EXECUTE=false`;
- `authenticated EXECUTE=false`;
- `service_role EXECUTE=false`.

## Search paths

- `lf_ops` helpers: `pg_catalog, lf_ops`;
- public functions: `pg_catalog, public`.

Function bodies, signatures, volatility and return types remain unchanged.

## Preflight evidence

The complete lot was executed inside a transaction and rolled back:

- target set: 12/12;
- fixed search paths: 12/12;
- pure functions and validators executed successfully;
- empty queue restock executed as `service_role` with zero writes;
- strategy function resolved its objects and reached the canonical event-contract gate;
- no `lf_ops` schema grant was added;
- final ACL state matched the intended minimum callers.

## Excluded

Trigger functions are handled in a separate lot because they are not ordinary RPCs and require trigger-dependency verification. This lot does not authorize runtime, readiness, merge, deployment or production.
