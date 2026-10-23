# STORY_J02_ORCHESTRATED_CANARY_V1

Primer canary gobernado previsto para demostrar la ruta interna del Story Creator sin ejecutar todavía J01→J13 completo.

## Alcance

Únicamente:

```text
EJECUCION_SKILL_LF
  -> ORQUESTACION_SKILL_LF
  -> SCREEN_DECOMPOSITION
  -> SCREEN_DECOMPOSER
  -> PERFIL-SCREEN-DECOMPOSER-LF
  -> EJECUCION_PERFIL_LF
  -> J02_SCREEN_DECOMPOSITION v0.8
```

## Por qué J02 primero

J02 ya tiene agente, Profile, schema, judge, validator visual y evidencia histórica. Además es el punto donde #1344 introdujo el `worker_binding` dinámico. Por eso permite validar el wiring nuevo con una superficie acotada antes de ampliar a los demás workers.

## Cierre positivo

El canary no se considera PASS por PASE ni por la mera existencia de archivos. Requiere simultáneamente:

- currentness limpio de las fuentes J02;
- parent Skill execution real;
- orchestration execution real;
- worker resolution único/current;
- task runtime binding exacto;
- child `EJECUCION_PERFIL_LF` reservado antes del receipt;
- dispatch receipt real;
- entry guard real `ORCHESTRATOR_ENTRY_ACCEPTED`;
- Profile Runtime adjunto al mismo child;
- `runtime_completion=PASS`;
- `profile_contract_valid=PASS`;
- juez independiente J02 v0.8 `PASS_WITH_EVIDENCE`;
- consumo downstream del output observado;
- exact source revision/head y digests cross-bound.

## Negativos obligatorios

Se conserva el negativo histórico de Profile binding no resuelto y se agregan controles contra currentness stale, worker ambiguo, receipt/guard fabricado, drift del packet después del receipt, source omission de J02 y self-judging.

## Boundary

Este PR sólo define el contrato del canary. No ejecuta el runtime, no aplica migraciones, no activa producción y no modifica PASE/POST-PASE. La ejecución real queda bloqueada hasta que las dependencias source-only estén materializadas por sus rutas autorizadas.
