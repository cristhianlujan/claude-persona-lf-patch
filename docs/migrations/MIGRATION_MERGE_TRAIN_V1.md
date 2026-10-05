# LF Migration Merge Train V1

Estado inicial: **DRY_RUN**.

## Frontera de seguridad
El workflow corre con `pull_request_target`, pero solo hace checkout de `main`. Nunca hace checkout ni ejecuta código del PR. La migration del PR se lee por GitHub API como blob del head SHA y se trata como dato.

## Cola
Todos los PR etiquetados `ready-to-merge` comparten:
- `concurrency.group: lf-migrations`
- `queue: max`
- `cancel-in-progress: false`

PRs sin migration usan la misma cola y omiten assign/apply/parity.

## Secuencia objetivo REAL
1. admisión del actor/repo/base/draft;
2. sincronización con main;
3. `lf_migration_assign_version.py`;
4. `lf_migration_version_order_check.py`;
5. persistencia exacta con `lf_migration_git_persist.py`;
6. state-gate Saga `READY_TO_APPLY` sin bind;
7. apply exact-version con `lf_migration_exact_apply.py` / DB_WRITE_TRANSPORT;
8. ledger readback;
9. parity changeset-scoped desde código confiable de main;
10. merge exact-head;
11. post-merge readback.

## PASE-GLOBAL-04 hook
Mientras `MIGRATION_WRITE_AHEAD_V1` y `MIGRATION_ORCHESTRATED_SAGA_V1` sigan bajo la contención global, se usan sus scripts directamente. Cuando `PASE-GLOBAL-04-ACTIVATION-CONTRACT` reactive sus entry guards/current pointers, el workflow conserva la misma secuencia y agrega dispatch/bind/evidencia gobernada sin cambiar el contrato de cola.

No se fabrica un `CONSISTENT` de Saga: ese cierre requiere evidencia canónica `LF_GATE_ERROR_V1` producida por observabilidad. Hasta que esa evidencia se conecte, la secuencia queda garantizada por el workflow y Saga se usa solo en estados que no requieran evidencia fabricada.

## Token REAL
REAL requiere un GitHub App instalado en el repo con permisos mínimos:
- Contents: Read & write
- Pull requests: Read & write
- Issues: Read & write
- Actions: Read
- Checks: Read

Secrets:
- `LF_MIGRATION_TRAIN_APP_ID`
- `LF_MIGRATION_TRAIN_APP_PRIVATE_KEY`

El App token es obligatorio porque cambios/merge hechos con `GITHUB_TOKEN` no deben ser la autoridad del flujo real: los eventos derivados de `GITHUB_TOKEN` no disparan normalmente nuevos workflows.

## Activación
FASE 4 mantiene `LF_MIGRATION_TRAIN_MODE=DRY_RUN`.
FASE 5 arma REAL en un PR separado después de tres dry-runs correctos y de validar los secrets/App.
