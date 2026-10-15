# IG M10.7 — Ejecución instrumentada transversal (A1)

Autoridad: `IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7` y `ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train`. Este cambioset es independiente del CP3 `NO_FALSE_PASS` y no modifica su `action_spec`.

## Problema y reutilización

No crear un motor ni nuevas tablas. Ya existen `programacion.input_validator_chunk_timings` con cómputo/espera/fases por chunk, `programacion.input_readiness_runs` con duración total, y `fn_ig_performance_timing_metrics_v1()` con recibos por familia y resolutor. Necesitamos un readback **por run_id**, aplicable a todas las pantallas y 47 familias, para comparar cambios posteriores sin resumir falsamente los tiempos desconocidos.

## Objeto declarado

`programacion.fn_ig_validator_execution_metrics_v1(bigint)`: función aditiva STABLE, SECURITY INVOKER, sin DML ni llamadas de validación caras, sin EXECUTE PUBLIC. Consume solo las dos tablas ya existentes, produce JSON con duración del run y suma de chunks, fases classification/assertions/EKB/propuestas/DB_WRITE/esperas y residuo de cómputo; incluye count de chunks y familias procesadas, duración desconocida, diferencia entre relojes y límite 150000 ms. Un tiempo no medido NO es cero. En ningún momento convierte estas observaciones en PASS de CP3.

`db_write_ms` contiene el coste agregado de updates y triggers; NO atribuye el coste a un trigger individual. El perfil por trigger EKB `IG-M107-TRIGGER-ROLLBACK-PROFILE-008` sigue siendo una fuente aparte y muestreada. p50/p90 exigen varias muestras independientes.

## Invariantes

No cambia Curator/Validator/triggers ni su orden, no descarta las 246 reglas, no reutiliza autoridades entre llamadas, no modifica tiempos máximos y no comparte decisiones semánticas. Solo observa registros existentes. Falta G2B para habilitar consumo mutable entre llamadas.

## Pruebas y gobierno

Migración única del Train con negativo run inexistente, positivo histórico run 933 (6 chunks, 47 familias, 205179 ms cómputo, 21231 espera, 122115 db_write, 48773 aserciones, 34041 propuestas; total validator 229436 ms) y readback de permisos. Sin nuevos runs. Registro EKB solo si pruebas pasan. Rollback futuro mediante migración aditiva de revocación y DROP antes de consumidores. CP3 mantiene 45% y PENDING.

## Siguientes cambioset independientes

A2: reducir reconstrucciones en el grafo/manifiesto dentro de una misma evaluación, equivalencia exacta de SHA y casos negativos.
A3: consultas de reglas y bindings con clave de versión; mantener vigencia y controles.
G2B: dos sesiones reales aisladas antes de G3, consumidor de contexto.
A4: instrumentación opt-in individual de triggers y pruebas de CP3 con muestra focal y evidencia histórica. 