# CONSUMER_BINDINGS cutover v1

`SADM-PP-L5-022` isolated cutover 15.

Materializes the already-verified `CONSUMER_BINDINGS_V1` contract and the canonical relations from `POST_PASE_ORCHESTRATOR` to the seven POST-PASE capabilities. It does not create another capability/binding registry: resolution remains `public.lf_capability_registry` + `public.lf_capability_current` through `public.fn_lf_capability_bind_from_orchestrator_v1` and `OWNER_RUNNER_CARRIER_AUTHORITY_V1`.

Functional source is unchanged from terminal merge `4d0d7ef97d9cd1b1aa802f8d20264ef34e59f73f`: core blob `0a8897b96c75818414606186944e25fcdb791ee6`, validator blob `7388fcaf929c5723c67fa722695a842c124451af`, 45 prior deterministic checks, terminal event `#19671`, reconciliation event `#19678`.

The old execution path is retained. No owner recalculation, binding bypass, applicability rediscovery, runtime/deploy/production, bulk cutover, or ZIP authority.

Rollback deletes only relations created by this cutover batch and restores the `CONSUMER_BINDINGS` asset to candidate/read-only; pre-existing relations and canonical capability authority remain untouched.
