# ACT-0001 — profile selection across all channels (2026-10-26)

Profiles are transversal resources and may administer work classified as PRODUCTO, PROGRAMACION or OPERACIONES.

The common sequence is:
1. Stage 1 classifies channel/business/scope.
2. Stage 2 exposes the same deterministic profile catalog.
3. Semantic selection chooses among CURRENT eligible profiles.
4. Gate 2 authorizes only EJECUCION_PERFIL_LF with effect_authority=false.
5. The selected profile performs bounded read-only investigation/administration.
6. Any channel effect remains governed separately.

Channel preconditions remain authoritative:
- PRODUCTO: any mutation still requires its separate governed operation.
- PROGRAMACION: exact canonical definition/currentness, PROGRAMMING_ENTRY_CONTRACT_V1 and ANALYSIS_IMPLEMENTATION_PACKAGE_V1 remain required before implementation/test/deploy effects.
- OPERACIONES: ACTIVE capability plus actor/scope authorization remain required before operational effects.

The signed router_action_binding carries channel_precondition so the selected profile receives the constraint without ACT-0001 executing the channel effect.

Compatibility:
- existing PRODUCTO selection remains supported;
- old product-specific continuation functions remain untouched;
- common continuation entrypoint is public.lf_router_profile_after_selection_raw_v1;
- common Gate2 derivation entrypoint is public.lf_router_profile_gate2_result_from_selection_v1.
