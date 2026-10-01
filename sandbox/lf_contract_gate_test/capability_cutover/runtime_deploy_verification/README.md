# RUNTIME_DEPLOY_VERIFICATION cutover v1

`SADM-PP-L5-022` isolated capability cutover.

This cutover registers only the existing read-only verifier. It does not deploy code, restart services, switch release symlinks, mutate profile assets, or activate production.

Exact functional identities at source revision `19dac34c45b41f0416e254e1ae2dc45a33d84444`:

- core blob `af53b9221d15d27a8ff016e3ec1ada804594867a`;
- validator blob `6d9ff2a581840eee8844836d4099cd70b513fe3b` — 19 deterministic checks.

The existing deploy effect owner and `services/profile_runtime_api/scripts/install.sh` remain untouched. The capability only consumes an exact deployment receipt and read-only manifest/health/state observations.

`RUNTIME_DEPLOY_VERIFICATION_cutover_rollback_v1.sql` removes only the exact current pointer, marks new binding authority non-active, and returns the asset to candidate read-only state. Immutable version history and deploy/runtime paths remain.

Required evidence before apply: exact-head PASE, source/blob identity, representative DB ROLLBACK, and post-apply registry/current/assets readback. No ZIP is terminal authority.
