# LF_GOVERNANCE SUPER ADMIN V1

## Identidad

- Código administrativo canónico: `LF_GOVERNANCE`.
- Rol: `SUPER_ADMIN_GOVERNANCE`.
- Estado de esta superficie: `CANDIDATE_READ_ONLY`.
- Autoridad operacional de activos sigue en Supabase; esta superficie Git define el contrato candidato antes de cualquier registro/promoción.

## Propósito

`LF_GOVERNANCE` es la raíz administrativa única para los controles/capabilities de gobernanza LF que forman parte del PASE. Centraliza identidad administrativa y bindings; no ejecuta controles.

No crea un owner distinto por cada control. Los nombres históricos `LF_GOVERNANCE_*` representan scopes/subdominios y no se convierten por sí solos en autoridades superiores paralelas.

## Separación de responsabilidades

`LF_GOVERNANCE` NO:

- decide aplicabilidad del changeset;
- genera el `lf-ci-execution-plan/v2`;
- ejecuta Contract Check, Migration Parity, Validate Packs, Assurance, P0, Runtime, DB Regression u otro control;
- sustituye el contrato funcional de una capability;
- sustituye el runner owner-local de una capability;
- actúa como carrier;
- hace cutover, deploy, runtime activation, producción o escrituras Supabase.

Changeset Governance conserva la autoridad de aplicabilidad. `PASE_ORCHESTRATOR_V1` consume el plan y delega. Cada capability conserva su lógica y runner. Los carriers son transporte, no ownership.

## Modelo administrativo

```text
LF_GOVERNANCE                  super administrador único
        |
        +-- control binding
                |
                +-- capability_id
                +-- runner_ref / estado transicional
                +-- carrier (resuelto SOLO desde impact registry)
```

El catálogo del contrato materializa una fila administrativa para cada `control_id` vigente, pero deliberadamente NO duplica `carrier`. `carrier` sigue siendo autoridad exclusiva de `lf_ci_control_impact_registry_v2.json`.

El binding que finalmente recibe un consumidor debe poder resolver:

- `control_id`;
- `super_admin = LF_GOVERNANCE`;
- `capability_id`;
- `runner_ref`;
- `carrier`;
- `state`;
- `source_revision`.

## Estados transicionales

- `LEGACY_CARRIER`: todavía no existe runner owner-local probado. El carrier vigente sigue ejecutando; no se inventa capability/runner.
- `OWNER_RUNNER_ACTIVE_LEGACY_CARRIER`: existe runner propio vigente, pero el impact registry aún conserva el carrier histórico.
- `REGISTERED_NOT_CUTOVER`: existe capability/runner registrado como destino, pero no está autorizado usarlo todavía.
- `CANDIDATE_NOT_CANONICAL`: existe un runner probado en PR abierto, pero no es autoridad canónica ni ejecutable desde PASE.

`CANDIDATE_NOT_CANONICAL` y `REGISTERED_NOT_CUTOVER` son informativos para migración y deben seguir delegando por el carrier actual hasta un cutover separado y calificado.

## Estado de materialización

`binding_catalog.catalog_materialized=true` significa únicamente que los controles actuales tienen una fila administrativa explícita y trazable.

`binding_materialized=false` se mantiene porque el binding todavía no ha sido propagado/validado end-to-end hasta el Orquestador. `owner_runner_migration_complete=false` porque la mayoría de controles continúa en carriers legacy.

Por tanto:

```text
CATÁLOGO MATERIALIZADO != BINDING E2E ACTIVO != CUTOVER
```

## Invariantes

1. El súper administrador debe ser exactamente `LF_GOVERNANCE`.
2. `super_admin` no es `carrier` ni `runner_ref`.
3. El catálogo debe cubrir exactamente el universo vigente del impact registry, sin controles extra o faltantes.
4. El catálogo no almacena `carrier`; el carrier se resuelve del impact registry para evitar doble autoridad.
5. Estado `LEGACY_CARRIER` permite `runner_ref=null` explícitamente; cualquier estado que declare destino requiere runner y capability.
6. Un runner candidato nunca es ejecutable mientras el estado sea `CANDIDATE_NOT_CANONICAL`.
7. Un destino `REGISTERED_NOT_CUTOVER` nunca es ejecutable antes del cutover calificado.
8. Los aliases/subscopes `LF_GOVERNANCE_*` no crean súper autoridades adicionales.
9. `ACT-0001` permanece `ROUTER_RESOLUTION_ONLY`.
10. Control desconocido, super-admin ausente/incorrecto, binding faltante, estado inválido o carrier drift deben fallar cerrado en el consumidor.
11. Qualification, binding, activation, cutover y legacy retirement son estados distintos.

## Relación con PASE_ORCHESTRATOR_V1

Este contrato elimina la necesidad de múltiples owners administrativos. El Orquestador deberá validar el `super_admin` único y el binding resuelto por control, sin interpretar carriers como owners ni seleccionar runners candidatos/no-cutover.

Este PR todavía NO modifica `PASE_ORCHESTRATOR_V1` ni hace que el execution plan consuma el catálogo.

## No alcance

- no edición de `lf_ci_control_impact_registry_v2.json`;
- no cambio de aplicabilidad;
- no modificación de runners/capabilities de dominio;
- no modificación de PR #1170;
- no normalización live de `owner_name` en Supabase;
- no merge/cutover/deploy/producción;
- no retiro de carriers o scopes históricos.
