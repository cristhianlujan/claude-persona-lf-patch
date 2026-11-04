# PG-07_C5 — Iteraciones justificadas y sin redefiniciones silenciosas

## Criterio oficial
PG-07_C5: cada iteración debe explicarse y vincularse al objetivo; cambios de objetivo, aceptación o scope se enrutan a PG-10, nunca se aplican en silencio. Criterio de salida oficial: “0 redefiniciones silenciosas”.

PG-10, por su parte, distingue conflictos de requisitos, estándares y contratos; reutiliza decisiones vigentes antes de preguntar; enruta decisiones técnicas a PG-03, investigación de requisitos a A3, y decisiones verdaderamente humanas por un paquete gobernado. **C5 no resuelve ni clasifica por sí mismo esa decisión**: solo prepara la derivación sin escribir.

## Implementación candidata
`tools/pg07_c5_iteration_guard_candidate_v1.py` expone:

`prepare_pg07_c5(pg07_c2, pg07_c3, pg07_c4, iteration_proposals)`

Comprueba:
- integridad de los tres sobres C2–C4 y su cadena de SHA256; todos permanecen sin autoridad;
- task spec de cada solución ligado al hash de C2;
- cada propuesta de iteración con `iteration_id`, `solution_id`, razón, referencia de objetivo, referencia/digest de diff, evidencias y relación explícita con la iteración anterior;
- hashes base de **objetivo**, **criterios de aceptación** y **scope** iguales a los campos de la tarea original congelada;
- hashes propuestos de esos tres campos; discrepancias que el llamador omite de `declared_changed_fields` se rechazan con `PG07_C5_UNDECLARED_MATERIAL_CHANGE`;
- cadena ordenada de iteraciones por solución, sin dependencia previa oculta en la primera.

Cualquier campo material cambiado genera `BLOCK_ROUTE_PG10` con `pg10_referral_requests`; nunca se aplica una redefinición silenciosa. Si no aparece un cambio en los hashes declarados, el estado solo dice `NO_DECLARED_MATERIAL_DRIFT_UNVERIFIED`, que **no es una autorización ni prueba que el diff real preserve esos campos**.

El paquete mantiene todos los flags de ejecución en falso: `source_evidence_authenticated=false`, `real_diff_verified=false`, `worker_receipts_verified=false`, `pg10_routing_executed=false`, `worker_invoked=false`, `iteration_applied=false`, `dispatch_allowed=false`, `write_allowed=false`, `production_authority=false`, `handoff_allowed=false`.

## Bloqueos hasta un PASS real
La autoridad deberá inspeccionar el diff real, verificar que los hashes corresponden a los campos efectivos de la tarea y demostrar la secuencia de recibos del Worker. La ausencia de redefiniciones silenciosas es un **criterio de calificación**, no una afirmación de este componente. PG-10 deberá efectuar la derivación y resolución correspondiente antes de aplicar cualquier cambio de alcance.

**Estado:** `PG07_C5_SOURCE_GUARD_PREPARED / REAL_DIFF_AND_WORKER_NOT_VERIFIED / PG10_ROUTING_NOT_EXECUTED / OFFICIAL_PENDING`.

El Owner mantuvo las pruebas en pausa. No se modifica Análisis, Supabase, main ni el repositorio de destino. Siguiente checkpoint: **PG-07_C6**, recibo sellado por lote de Worker con diff, entradas y estándares aplicados, preparado para PG-12 sin anticipar autoridad.
