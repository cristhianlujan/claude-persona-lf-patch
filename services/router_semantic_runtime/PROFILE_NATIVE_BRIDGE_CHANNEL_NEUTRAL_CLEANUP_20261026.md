# GPT Native bridge channel-neutral cleanup — 2026-10-26

Scope: remove the remaining PRODUCTO-only wiring from the GPT Native profile bridge after ACT-0001 profile administration was opened to PRODUCTO, PROGRAMACION and OPERACIONES.

Canonical runtime path:
- Stage1 is the sole source of channel, business and scope.
- public.lf_router_profile_after_selection_v1 is the canonical post-selection continuation.
- public.lf_router_profile_gate2_result_from_selection_v1 is the canonical deterministic Gate2 derivation.
- public.lf_router_profile_execution_after_gate2_v1 materializes EJECUCION_PERFIL_LF with the service identity.
- public.lf_profile_native_bridge_prepare_v1 continues the same authorized GPT Native execution.

Retired legacy entrypoints:
- public.lf_router_product_profile_after_selection_v1 is removed.
- public.lf_router_product_profile_after_selection_raw_v1 is removed.
- public.lf_router_product_gate2_result_from_selection_v1 is removed.
- Historical migrations may still mention these names because they describe prior schema states; no current runtime API may expose or call them.
- PRODUCTO, PROGRAMACION and OPERACIONES all use `LF_ROUTER_CHANNEL_PROFILE_AFTER_SELECTION_V1`; the former PRODUCTO-specific schema identifier is retired from runtime output.

Security:
- no new GRANT is given to supabase_read_only_user;
- lf_profile_native_bridge_begin_v1 remains service_role-only;
- profile admission remains separate from PostgreSQL execution identity;
- Gate2 carries authorization while the runtime supplies the technical service identity.

Acceptance:
- PROGRAMACION + PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF + GPT_NATIVE reaches NATIVE_EXECUTION_READY in a rollback-only migration postcheck;
- the bridge contains no active calls to product-specific continuation/Gate2 functions;
- the three product-specific legacy entrypoints do not exist in the current schema;
- no active PostgreSQL function source references those retired names;
- postcheck leaves no execution residue.
