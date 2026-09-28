# LF_GOVERNANCE SUPER ADMIN V1

## Identidad

- Código administrativo canónico: `LF_GOVERNANCE`.
- Rol: `SUPER_ADMIN_GOVERNANCE`.
- Estado de esta superficie: `CANDIDATE_READ_ONLY`.
- Changeset Governance conserva la autoridad de aplicabilidad.
- Los carriers son transporte, no ownership.

## Propósito

`LF_GOVERNANCE` es la raíz administrativa única para los controles/capabilities de gobernanza LF que participan en PASE. Centraliza identidad administrativa y política de ownership; no ejecuta controles ni crea capabilities.

Los nombres históricos `LF_GOVERNANCE_*` son scopes/subdominios, no autoridades superiores paralelas. `ACT-0001` permanece `ROUTER_RESOLUTION_ONLY`.

## Modelo probado

El inventario exact-head `pase_control_binding_inventory_v1.json` demostró que un `control_id` CI no equivale automáticamente a una capability standalone. Por tanto:

```text
LF_GOVERNANCE                     super administrador único
       |
       +-- control CI
             |
             +-- INTERNAL_CI_CHECK --------> carrier vigente
             |
             +-- STANDALONE CAPABILITY ----> owner-runner canónico
                                               solo cuando autoridad/binding lo prueban
```

### Regla 1 — owner administrativo

El plan transporta una sola identidad administrativa: `super_admin = LF_GOVERNANCE`.

Si esa identidad falta o es distinta, el consumidor debe bloquear. No se crean 25 owners administrativos.

### Regla 2 — control CI no implica capability

Un `control_id` seleccionado por el Router puede ser un check interno de Contract Check, Validate Packs, DB Regression u otro carrier. La presencia de un ID, script o step de workflow no autoriza crear una nueva capability, owner o owner-runner.

### Regla 3 — owner-runner solo para capability real

Un owner-runner separado se exige únicamente cuando existe una capability standalone demostrada por autoridad canónica y el estado permite ejecutarla.

Para `INTERNAL_CI_CHECK`, `runner_ref` owner-local puede ser N/A. Esto no es `unknown owner` ni `missing runner`: el check sigue siendo ejecutado dentro de su carrier vigente.

### Regla 4 — candidatos y destinos sin cutover

- runner candidato/no canónico: `FORBIDDEN`;
- capability registrada pero `NOT_CUTOVER`: `FORBIDDEN` como destino nuevo;
- mientras no exista cutover calificado, la ejecución continúa únicamente por el carrier actual.

## Unknown owner

La detección de owner desconocido es plan-level:

```text
plan.governance_admin.super_admin missing
OR
plan.governance_admin.super_admin != LF_GOVERNANCE
        -> BLOCK
```

Esto es independiente de la clasificación `control -> capability`. Un check interno no necesita inventar un owner adicional para satisfacer esta regla.

## Separación de responsabilidades

`LF_GOVERNANCE` NO:

- decide aplicabilidad;
- genera el execution plan;
- ejecuta Contract Check, Migration Parity, Validate Packs, Assurance, P0, Runtime, DB Regression u otro dominio;
- convierte controles CI en capabilities por inferencia;
- crea owner-runners para checks internos;
- sustituye contratos/runners de capabilities;
- actúa como carrier;
- hace cutover, rebind, deploy, runtime activation, producción o escrituras Supabase.

## Binding futuro

Cuando una capability real tenga binding canónico, el consumidor debe poder resolver como mínimo:

- `control_id`;
- `super_admin = LF_GOVERNANCE`;
- `capability_id`;
- `runner_ref`;
- `carrier`;
- `state`;
- `source_revision`.

Esta superficie todavía no materializa ese binding E2E. `binding_materialized=false` permanece correcto.

## No alcance

- no edición de `lf_ci_control_impact_registry_v2.json`;
- no edición de `lf-ci-execution-plan/v2` en este PR;
- no modificación de PR #1170;
- no creación de binding registry;
- no normalización live en Supabase;
- no merge/cutover/deploy/producción.
