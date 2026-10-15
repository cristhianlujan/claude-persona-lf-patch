# IG_EXECUTION_SOURCE_CONTEXT_V1 — G0 (alcance y gobierno)
Estado: CANDIDATO, no activo. Origen: IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.7. Propietario: autoridad existente INPUT_GOVERNANCE (Supabase).
Aprobación de encaminar: autorización del usuario para Migration/Operation del 2026-10-15. No es autorización para saltar guards ni activar producción.

## Cambio independiente de CP3
Esta intervención es un cambioset transversal separable. No se altera el action_spec ni la evidencia del CP3 NO_FALSE_PASS, cuyo target declarado continúa siendo `sandbox/lf_contract_gate_test/engineering_checkpoints/m10_7/no_false_pass.py`.
Objeto nuevo autorizado **solo en forma candidata no ejecutable para clientes**: `programacion.fn_input_governance_run_context_packet_v1(bigint)`. Se propone mediante una migración SQL aislada y un PR propio a través de LF Migration Merge Train. No activar ni modificar las 21 guardas/transiciones de Validator.

## Contrato de datos
La identidad del paquete es (run_id, pantalla_id, version_id, contract_snapshot_sha256, source_manifest_identity_sha256, curator_identity, validator_identity). RUN_PINNED puede transportarse y releerse por run_id; no certifica autoridad actual por sí solo.
El proveedor admite solo run VALIDATING con snapshot/contrato materializados, identidad Validator independiente, familia completa y `fn_input_governance_continuation_currentness_v1` favorable.
El paquete contiene datos/ref únicas de familias y propuestas, jamás resultados PASS, evidencia de Validator ni una afirmación de autorización para producción.

## Seguridad de cambios concurrentes
Supabase usa READ COMMITTED y los resolvers son VOLATILE. Un SHA del contexto almacenado NO demuestra currentness. **Hasta G2B PASS y G3 expresamente admitido**, la implementación vigente continúa revalidando autoridad en cada consumo: no cambiar esta conducta ni los triggers. La propuesta aprobada sustituye las reconstrucciones repetidas por un contexto compilado inmutable de una sola ejecución, con verificación final atómica protegida. No compartir una GUC Curator entre transacciones ni usar caché mutable incondicional. Conservar evaluación semántica Validator independiente y 21 triggers. Prohibida cache cross-run/cross-screen. Si no se garantiza el cerco transaccional final o si falla cualquier verificación de identidad/vigencia: FAIL_CLOSED, sin PASS y sin cierre.

## G2B — contrato objetivo de compilación congelada y cierre protegido (revisión de gobierno 2026-10-15)

**Estado contractual:** DISEÑO APROBADO, IMPLEMENTACIÓN NO ACTIVA. No es una certificación G2B ni un permiso para cambiar hoy los consumidores. El G1 instalado sigue siendo `RUN_PINNED_FIELDS_ONLY` y hace currentness por invocación. Esta revisión no altera su fuente ni abre permisos.

### 1. Congelación inicial única por ejecución

- Tras crear y materializar un run `VALIDATING`, con `run_id`, `pantalla_id`, `version_id`, snapshots de fuente y contrato existentes e identidades Curator/Validator separadas, capturar **una única compilación canónica** por ejecución.
- La compilación debe contener las reglas aplicables, contratos, dependencias, fuente/ref identificada, identidad del manifiesto, política, scope, universo de familias y propuestas; nunca veredictos, PASS precalculados o decisiones humanas.
- Registrar una identidad reproducible: (`run_id`, pantalla, versión, contrato, política, manifiesto SHA, compilación SHA, instante y revisión/época de origen). Un hash aislado **no es** prueba de vigencia.
- El contexto es inmutable, confinado al `run_id` y su identidad; una continuación del mismo run puede transportarlo, pero ninguna pantalla, versión, ejecución o consumidor ajeno puede reutilizarlo.

### 2. Reutilización sin repetición de reconstrucciones

- Curator y Validator pueden consumir los datos compilados durante las fases autorizadas de esa misma ejecución **después de G2B/G3**, sin rehacer continuamente el manifiesto ni el grafo. La evaluación semántica del Validator y los oráculos Q0–Q8 siguen siendo independientes y obligatorios.
- Esta reutilización optimiza **datos de entrada**; no comparte resultados PASS/FAIL, autoridad de aceptación ni permisos. Si aparece una nueva referencia/familia, cambia el alcance o se pierde integridad de paquete, invalidar el contexto y detener o recompilar una ejecución nueva.
- Mantener las verificaciones existentes hasta tener evidencia material de equivalencia, costo, rechazo de datos stale y protección de escrituras concurrentes.

### 3. Comprobación final y cierre atómico

- Antes de registrar cualquier resultado `PASS`, completar el run, emitir una aprobación o realizar otra transición irreversible, comparar en Supabase **fuentes actuales**, contrato, política, identidad y todas las referencias con el snapshot inicial. No comparar solamente dos hashes almacenados ni confiar en una marca local.
- La comprobación y el cierre deben ejecutarse dentro de **una misma transacción**, protegidos contra el cambio *entre comprobación y COMMIT*. Mecanismo objetivo: **época/versión de fuente gobernada** por cada fuente relevante; todo writer que modifique una fuente cubierta debe incrementar su época en su propia transacción. El cierre toma bloqueo transaccional conflictivo sobre la fila de versión (por ejemplo, `SELECT ... FOR SHARE`), compara época inicial y actual, recalcula una sola vez la identidad en vivo, persiste el veredicto y confirma el COMMIT reteniendo el bloqueo.
- Los escritores han de actualizar esa misma época bajo su transacción (bloqueo incompatible con el del cierre). La garantía solo aplica si **todos** los writers relevantes participan y los cambios de contratos, reglas, vínculos, políticas, versiones y fuentes externas están cubiertos o bloqueados por control equivalente. Este mecanismo es **propuesto, todavía no implementado ni probado**.
- Si alguna fuente no dispone de cobertura demostrada, si no se puede adquirir el fence, si hay cambio de identidad/época/SHA, timeout, lectura ausente o divergencia, el sistema debe **denegar el cierre**, invalidar el contexto, conservar evidencia y recalcular desde fuentes actuales en una nueva evaluación; no emitir falso PASS. No usar una comprobación final de solo lectura sin bloqueo para certificar ausencia de carrera TOCTOU.
- Los cambios que ocurran **después** del COMMIT pertenecen a una nueva revisión de autoridad y se manejarán mediante el mecanismo vigente de invalidación/recuración; no se promete vigencia perpetua.

### 4. Pruebas que admiten G2B

- Dos sesiones PostgreSQL independientes `A` y `B`, identificadas por `pg_backend_pid()`, usando fixture gobernado y no productivo. Caso sin cambio: contexto inicial y final JSON/SHA iguales y cierre correcto.
- Cambio concurrente: `A` congela; `B` cambia una fuente de fixture y realiza `COMMIT`; `A` revalida y debe fallar cerrado. Simular carrera dentro de ventana de cierre y comprobar que el fence serializa correctamente.
- Negativos: identidad `run_id`/pantalla distinta, contrato/política o snapshot adulterados, fuente sin epoch/coverage, retry con token/compilación stale, error/timeout y cambio después de comprobación pero antes de cierre. Ningún caso negativo puede finalizar en PASS.
- Medir fase de compilación, tiempo de cálculos y evaluación, costo del cierre, esperas por lock, reconstrucciones evitadas y duración completa p50/p90; comparar con baseline bajo carga/fuentes comparables. Comprobar que sobreviven las 21 guardas y las 246 reglas, sin relajación de presupuesto de 150000 ms ni de CP3.
- Asegurar limpieza de fixtures y cero residuos; registrar evidencia de Operation. Un test sintético o dos invocaciones en una misma sesión no alcanzan G2B PASS.

### 5. Frontera de implementación y admisión

1. **G2B-Contrato:** esta definición versionada, código y hashes en Git; EKB separado como evidencia **solo de diseño**.
2. **G2B-Implementación:** definir owners de cada fuente mutable, writers, fila de época y bloqueo conflictivo; diseñar fixture/ejecutor sin acceso a datos productivos. Migraciones siempre PR → Train → ledger/paridad/readback, sin alterar el `action_spec` CP3.
3. **G2B-Prueba:** correr casos materiales con dos sesiones mediante Operation autorizada; FAIL_CLOSED si falta el ejecutor. Solo evidencia real da G2B PASS.
4. **G3-Activación:** consumidores pasan al contexto congelado únicamente después de G2B PASS y benchmark/paridad completos. Hasta entonces, el runtime canónico y todos los controles siguen como están.

## Fases de admisión
G0: esta declaración de objeto, dueño, ámbito, veto y pruebas, ruta Router ACT-0001 -> ACTUALIZACION_DB_LF; no es una mutación de CP3.
G1: migration standalone (una por PR), función SECURITY DEFINER con search_path restringido y EXECUTE revocado a PUBLIC. Pruebas de ausente y terminal; sin permisos de runtime, sin usuarios, sin nuevos run.
G2: G2A ya ejecutado sobre fuentes estables; G2B requiere la prueba material de congelación y protección final con dos sesiones, cambio real en fixture, commit/fence, negativos de contrato/identidad y readback. La revisión del contrato no equivale a G2B PASS.
G3: activar reutilización del contexto congelado en consumidores Curator/Validator/propuestas solo tras G2B PASS, equivalencia semántica y medición completa; no descartar 246 reglas, 21 triggers ni controles Q0–Q8.
G4: una pantalla compleja, tiempos y percentiles comparables; CP3 sigue PENDING hasta >=2 observaciones históricas as-of por pantalla/familia, 0 falsos PASS, 0 D4, 0 timeout >150 s, duración completa y ventana congelada.

## Rutas, rollback, EKB
Todas las escrituras DB solo por PR -> label ready-to-merge -> LF Migration Train REAL -> apply exact-version -> ledger -> Git/main/readback DB. Operación ACTUALIZACION_DB_LF la reserva Train; NO reservarla manualmente. Operation runtime posterior, no sustituto de DDL.
G1 es aditiva y sin GRANT público. Reversión controlada antes de consumo autorizado: DROP FUNCTION mediante una migración nueva (no borrar historial).
EKB: IG-SHADOW-V2-CONTEXT-REUSE-001, IG-M107-TRIGGER-ROLLBACK-PROFILE-008, IG-M107-ATOMIC-MANIFEST-REPEAT-005, ENGINEERING-CP-SECURITY-CONTEXT-NO-EXPLICITO-028.
Prueba local 12/12 del context_guard del paquete offline; NO es prueba PostgreSQL. Issue #2733: bloqueo de herramientas anterior; no declarar resuelto si reaparece.

## Criterio de cierre de G0
Documento incorporado a main por Train con hashes y readback. La revisión G2B del contrato solo documenta el diseño autorizado, no implementa el fence, no declara G2B PASS, no cambia G1 existente, no demuestra rendimiento mejorado ni cierra CP3.
