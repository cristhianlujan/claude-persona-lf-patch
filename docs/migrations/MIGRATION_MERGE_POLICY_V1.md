# Migration Merge Train — política de merge a main

Estado: PREPARADO, NO APLICADO.

## Flujo normal

1. Abrir PR contra `main`.
2. Esperar los checks ordinarios del PR.
3. Colocar la etiqueta `ready-to-merge`.
4. El PR entra a la cola global `lf-migrations`.
5. El job requerido `lf-migration-merge-train` debe terminar PASS sobre el head exacto.
6. En modo REAL, el workflow aplica la migration exact-version si existe y luego realiza el merge exact-head.
7. No hacer merge manual fuera de este flujo.

Los PRs sin migration usan la misma cola, pero omiten persist/apply/parity.

## Ruleset

Ruleset existente: `protect-main`, id `20571741`.

Cambio propuesto:
- conservar deletion/non-fast-forward/pull-request actuales;
- `strict_required_status_checks_policy=true`;
- required check: commit status `lf-merge-train/verified`, publicado por `lf-migration-train`;\n- `integration_id` se resuelve desde `LF_MIGRATION_TRAIN_APP_ID` al aplicar el JSON; ningún otro actor puede satisfacer el contexto;
- bypass de emergencia, limitado a PR:
  - Paulo / user id `66433825`;
  - Cristhian / user id `259964988`.

No se añade bypass para GitHub Actions/GitHub App por defecto. El App de la fila debe cumplir el required check normalmente. Si un piloto REAL demuestra que el App no puede completar el merge aun con el check verde, ese caso se audita y recién entonces se evalúa un bypass `Integration`.

## Emergencia

El bypass no autoriza un apply informal. D4 sigue vigente: migrations solo por exact-version/DB_WRITE_TRANSPORT; `apply_migration` MCP permanece prohibido.

En emergencia:
1. abrir/mantener PR;
2. documentar la causa;
3. Paulo o Cristhian usan el bypass del PR;
4. si hubo apply DB, preservar identidad exacta y ejecutar fail-forward/readback.

## Rollback del ruleset

Archivo canónico:
`docs/migrations/protect-main-migration-train-ruleset-v1.json`.

El bloque `rollback` restaura exactamente el estado observado antes de FASE 6:
- `bypass_actors=[]`;
- `required_status_checks=[]`;
- resto de reglas de `protect-main` sin cambios.

## Aplicación manual

El conector de esta sesión puede leer rulesets pero no administrar rulesets/secrets. Un administrador debe actualizar el ruleset `20571741` usando exactamente el objeto `update` del JSON canónico, después de que FASE 5 complete los dos pilotos REAL.
