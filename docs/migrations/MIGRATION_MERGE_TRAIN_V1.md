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


## Requisito de Actions policy

Este repositorio público depende de `pull_request_target` para mantener el workflow y los secretos en código confiable de `main`. GitHub anunció enforcement del bloqueo por defecto de `pull_request_target` en repos públicos desde 2026-11-02. Antes de esa fecha, el administrador debe crear una Actions workflow-execution policy aplicable a este workflow que permita explícitamente el evento `pull_request_target`.

No habilitar `allow-unsafe-pr-checkout`. Este workflow no hace checkout ni ejecución del head del PR.

## Configuración previa a REAL

1. GitHub App instalado en el repo.
2. Secrets `LF_MIGRATION_TRAIN_APP_ID` y `LF_MIGRATION_TRAIN_APP_PRIVATE_KEY`.
3. El secret existente `LF_SUPABASE_DB_PASSWORD`.
4. Actions event policy que permita `pull_request_target`.
5. Label `ready-to-merge`.
6. Opcional: variable `LF_MIGRATION_TRAIN_ALLOWED_ACTORS` para identidades de agentes adicionales; Paulo y Cristhian están admitidos explícitamente.


## Seguridad de shell y DRY_RUN

`pull_request_target` es privilegiado. Ningún valor de `github.event.*` se interpola dentro de un bloque `run:`; los datos del PR entran por `env:` y el shell los consume como variables citadas. El lint del workflow falla si aparece `${{ github.event` dentro de un `run:`.

DRY_RUN es totalmente no-mutante:
- GitHub: solo GET/readback; no comments, labels, branch updates ni merge.
- Supabase: solo SELECT/readback del ledger; no DDL/DML.
- Salida: logs y `$GITHUB_STEP_SUMMARY`.

## Inventario de workflows `push -> main` y decisión del token

Foto revisada al 2026-10-05:

- `lf-external-currentness-detector.yml`: **activo**, `push` a `main` sin filtro de paths. Debe observar cada nuevo `main`.
- `pase.yml`: escucha `push main`, pero los jobs PASE/POST-PASE están temporalmente en `if:false`.
- `lf-input-governance-recurate-dispatch.yml`: `push main` limitado a sus propios workflows y además condicionado.
- `story-agent-evidence-verifier.yml`: `push main` limitado a su workflow, función y migration específica.
- `asset-smoke-test.yml`: `push` con filtros de docs/assets/tests; no es un consumidor general de migrations.

Por tanto REAL conserva GitHub App: un merge/push efectuado con el `GITHUB_TOKEN` del workflow no debe suprimir el `push` que necesita `LF External Currentness Detector`. El job REAL declara además los permisos mínimos explícitos `contents:write`, `pull-requests:write`, `issues:write`, `actions:read`, `checks:read`.
