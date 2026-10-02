# ORQUESTACION_SKILL_LF — candidato v0.1

Operación transversal candidata para coordinar pasos delegados de un Skill usando autoridades y runtimes existentes.

## Qué resuelve

`EJECUCION_SKILL_LF` ya resuelve y ejecuta un Skill en modo read-only, pero no posee una operación `ORCHESTRATION` especializada en coordinar workers internos. `ORQUESTACION_SKILL_LF` cubre únicamente esa coordinación.

```text
EJECUCION_SKILL_LF (parent IN_PROGRESS)
        |
        v
ORQUESTACION_SKILL_LF
        |
        +-- CURRENTNESS / manifest step
        +-- SKILL_WORKER_RESOLVER_V1
        +-- PROFILE_TASK_RUNTIME_BINDING_V1 (si aplica)
        +-- reserve child execution
        +-- dispatch receipt real
        +-- ORCHESTRATOR_EXECUTION_GUARD_V1
        +-- finalize Task Packet
        +-- existing Profile Runtime o Capability contract
        +-- independent step judge
        v
checkpoint / next step / close
```

## No es otro runtime

La operación no ejecuta modelos ni reemplaza:

- `EJECUCION_SKILL_LF`;
- `EJECUCION_PERFIL_LF`;
- `CAPABILITY_EXECUTION_CONTRACT_V1`;
- ACT-0001;
- CURRENTNESS_AUTHORITY;
- los jueces de negocio J00–J13.

Su juez `JUDGE-ORQUESTACION-SKILL-LF-v0.1` sólo verifica integridad de orquestación: parent exacto, currentness, worker único, child-before-receipt, cross-binding, guard, packet estático vs final e independencia del juez de step.

## Estado

La migración `20261002031000_skill_orchestration_operation_candidate_v1.sql` sólo define el candidato en Git. Está fijado como:

- `operation_family=ORCHESTRATION`;
- `operation_domain=SKILL_RUNTIME_CONTROL`;
- `lifecycle_state_code=OP_CANDIDATE`;
- `status=CANDIDATO_READ_ONLY`.

No se permite promoverlo a `OP_OPERATIONAL` como efecto de este lote.

## Boundary

Este PR no aplica Supabase, no activa runtime/producción, no crea queue, no modifica PASE/POST-PASE y no reutiliza `ORQUESTACION_PIPELINE_LF`. La materialización y cualquier cutover son lotes posteriores, sujetos a currentness y al pase transversal vigente.
