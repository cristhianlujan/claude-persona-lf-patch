# SKILL_WORKER_RESOLVER_V1

Resolver determinista y read-only para seleccionar un único worker gobernado a partir de un `worker_role` lógico declarado por un Skill.

## Flujo

```text
manifest/step worker_role + allowed_worker_kinds
        |
        v
Router/currentness-derived authority snapshot
        |
        v
SKILL_WORKER_RESOLVER_V1
        |
        +-- 0 elegibles  -> BLOCK_WORKER_UNRESOLVED
        +-- >1 elegibles -> BLOCK_WORKER_AMBIGUOUS
        +-- 1 elegible   -> WORKER_RESOLVED
        |
        v
binding_seed (sin execution/receipt todavía)
```

## Autoridades que no duplica

El resolver no consulta ni reemplaza:

- `ACT-0001` / Router para elegibilidad de ejecución;
- `CURRENTNESS_AUTHORITY` para currentness;
- `public.lf_activos` para identidad de activos;
- `EJECUCION_PERFIL_LF` para ejecutar perfiles;
- `CAPABILITY_EXECUTION_CONTRACT_V1` para capabilities standalone;
- `ORCHESTRATOR_EXECUTION_GUARD_V1` ni el dispatch receipt.

El snapshot que consume debe venir de esas autoridades. El resolver sólo filtra y produce una semilla determinista de binding.

## Regla anti-hardcode

El `step_contract` no puede contener `worker_ref`, `worker_profile` ni `capability_code`. Debe declarar `worker_role` y `allowed_worker_kinds`. La identidad concreta sólo aparece después de resolver la autoridad vigente.

## Fail closed

Un worker sólo es elegible cuando:

1. declara el role exacto;
2. su kind está permitido;
3. Router lo reporta `READY_TO_EXECUTE`;
4. `downstream_execution_allowed=true`;
5. currentness es `CURRENT`;
6. `source_revision` coincide exactamente con el snapshot;
7. si es `CAPABILITY`, declara `capability_code` y `CAPABILITY_EXECUTION_CONTRACT_V1`.

Duplicados, ambigüedad, stale currentness y autoridad incompleta bloquean.

## Boundary

Esta solución no crea operación, execution, receipt, queue, runtime, registry, capability ni tabla. No llama red, GitHub ni Supabase. No activa runtime/producción y no modifica PASE/POST-PASE.
