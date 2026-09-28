# LF_GOVERNANCE SUPER ADMIN V1

## Identidad

- Código administrativo canónico: `LF_GOVERNANCE`.
- Rol: `SUPER_ADMIN_GOVERNANCE`.
- Estado de esta superficie: `CANDIDATE_READ_ONLY`.
- Autoridad operacional de activos sigue en Supabase; esta superficie Git define únicamente el contrato candidato antes de cualquier registro/promoción.

## Propósito

`LF_GOVERNANCE` es la raíz administrativa única para los controles/capabilities de gobernanza LF que formen parte del PASE. Centraliza identidad administrativa, no ejecución.

No crea un owner distinto por cada control. Los nombres históricos `LF_GOVERNANCE_*` representan scopes/subdominios y no deben convertirse por sí solos en autoridades superiores paralelas.

## Separación de responsabilidades

`LF_GOVERNANCE` NO:

- decide aplicabilidad del changeset;
- genera el `lf-ci-execution-plan/v2`;
- ejecuta Contract Check, Migration Parity, Validate Packs, Assurance, P0, Runtime, DB Regression u otro control;
- sustituye el contrato funcional de una capability;
- sustituye el runner owner-local de una capability;
- actúa como carrier;
- cambia bindings, cutover, lifecycle o currentness;
- hace deploy, runtime activation, producción o escrituras Supabase.

Changeset Governance conserva la autoridad de aplicabilidad. `PASE_ORCHESTRATOR_V1` consume el plan y delega. Cada capability conserva su propia lógica y runner. Los carriers son transporte, no ownership.

## Modelo administrativo

```text
LF_GOVERNANCE                  super administrador único
        |
        +-- CONTROL / CAPABILITY
                |
                +-- runner_ref  ejecutable propio o compartido explícitamente
                |
                +-- carrier     transporte vigente
```

Para cada control de PASE, el binding futuro debe poder resolver como mínimo:

- `control_id`;
- `super_admin = LF_GOVERNANCE`;
- `capability_id`;
- `runner_ref`;
- `carrier`;
- `state`;
- `source_revision` / currentness suficiente para fail-closed.

Esta superficie NO materializa esos bindings. Ese trabajo pertenece a una solución posterior sobre la autoridad declarativa existente.

## Invariantes

1. `super_admin` para controles gobernados por este dominio debe ser exactamente `LF_GOVERNANCE`.
2. `super_admin` no puede ser igual a `carrier` por inferencia.
3. `super_admin` no puede sustituir `runner_ref`.
4. un control puede compartir runner solo mediante binding explícito; nunca por coincidencia de nombre/path.
5. un alias/subscope `LF_GOVERNANCE_*` no crea una autoridad superior adicional.
6. `ACT-0001` permanece `ROUTER_RESOLUTION_ONLY` y no se convierte en super administrador.
7. control desconocido, super-admin ausente/incorrecto, runner no resuelto o carrier drift deben conservar semántica fail-closed en el consumidor que valide el binding.
8. qualification, activation, cutover y legacy retirement son estados distintos.

## Relación con PASE_ORCHESTRATOR_V1

Este contrato elimina la necesidad de que el orquestador interprete múltiples owners administrativos. El orquestador deberá validar el `super_admin` único y, separadamente, el `runner_ref` y `carrier` resueltos por la autoridad declarativa vigente.

No se modifica `PASE_ORCHESTRATOR_V1` en este candidato.

## No alcance

- no edición de `lf_ci_control_impact_registry_v2.json`;
- no edición de `lf-ci-execution-plan/v2`;
- no modificación de PR #1170;
- no normalización live de `owner_name` en Supabase;
- no merge/cutover/deploy/producción;
- no retiro de owners/scopes históricos.
