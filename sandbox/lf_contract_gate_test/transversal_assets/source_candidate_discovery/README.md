# D1/D2 — Prototipo de descubrimiento de fuentes (sin activación)
Estado: CANDIDATO / solo pruebas unitarias. No es una capacidad RELEASED ni un runtime activo.

## Frontera de autoridad
- Supabase: única fuente canónica de políticas, catálogo, permisos, casos oficiales, trayectorias de ejecución, resultados y puntuaciones.
- GitHub: únicamente implementación y pruebas sintéticas del código.
- Excel: exclusivamente vista de resultados exportados; no se consulta como fuente, no almacena reglas, no recibe escrituras operativas.
- Este módulo es puro/efímero. No ejecuta SQL, no lee filas, no accede a Excel ni concede permisos.
- El runtime deberá construir snapshots tipados de metadatos desde Supabase, verificando actor/tenant, política vigente, source bindings y recibos. No se debe aceptar un dict armado por GPT como comprobación de autorización.
- D1 produce **candidatos**, jamás una declaración de autoridad. D2 solamente prepara la entrada del planificador existente `TARGETED_EVIDENCE_ACQUISITION`, pero tampoco concede permiso de consulta.

## Hallazgo del sandbox (metadata-only)
Scope de análisis interno `lf_ops`: 109 objetos relacionales, 181 relaciones FK, descripciones presentes en 26 objetos. La consulta léxica exploratoria de «Subí una carga y no aparece» recuperó `cargas_archivos` y `cargas_lotes` sin tener sus nombres en el prompt. La consulta PG solo leyó metadatos. **Esto no valida accesos tenant ni resolución end-to-end**.

## Gates antes de la admisión
1. Resolver alcance de metadatos, identidad y reglas directamente desde Supabase, nunca desde Python/Excel.
2. Binding de actor/tenant y verificaciones firmadas/canónicas; no confiar en flags de entrada del modelo.
3. Resolver origen y versión vigentes con la policy `POL-LF-SOURCE-RESOLUTION` — no crear resolver paralelo.
4. Registros y resultados reales en Supabase; benchmark ciego baseline/candidato con trazabilidad y cero regresiones críticas.
5. Antes de activar: migración Git-first (si se agregan objetos), PR, pruebas con rollback, merge autorizado, apply sandbox exacto y readback Git=ledger=DB. Sin activar producción.

## Contrato provisional
`discover_sources(request, metadata_snapshot, policy_snapshot) -> discovery_result`.
`adapt_for_targeted_evidence(discovery, reasons, consumer_ref, admitted_by_supabase) -> planner_input | DISCOVER_MORE`.

El contrato no prueba aún descubrimiento semántico general, solo recuperación estructural/léxica y separación de permisos.


## Avance D1-B (2026-10-10; sandbox solamente)
- \`source_candidate_discovery_v1.py\` ahora soporta búsqueda por alias metadato
  y recorrido de FK de 0 a 2 saltos, con límites provenientes de política.
  Los vecinos solo son \`STRUCTURAL_NEIGHBOR_UNVERIFIED\`, NO fuentes autorizadas.
- \`adapt_for_targeted_evidence\` nunca fabrica agotamiento: \`DISCOVERY_EXHAUSTED\`
  sin verificación canónica retorna \`CANONICAL_EXHAUSTION_PROOF_REQUIRED\`.
  Un \`STOP\` del planificador de evidencia no demuestra por sí solo que no haya
  fuentes semánticas sin explorar.
- \`metadata_scope_catalog_readonly_v1.sql\`: compila nombres, columnas y aristas
  de FK directamente desde \`pg_catalog\`. Parámetros de ámbitos y límites
  provienen del resolutor autorizado de Supabase; NUNCA de GPT/Excel.
- \`metadata_readonly_candidate_query_v1.sql\`: búsqueda léxica inicial acotada,
  sin SQL generado por GPT, sin lecturas de filas.
- Pruebas: 20/20 unittest sintéticas PASAN localmente; SHA de Git blobs de
  fuente/tests verificados contra el mismo contenido ejecutado.
- Probe estructural real Supabase: \`lf_ops\` tiene 109 objetos relacionales y 181 FK;
  consulta sin nombres de tablas descubrió fuentes de cargas, y aristas hacia
  empresas, estados, archivos, incidencias y auditoría.
- El alcance de metadata en el probe fue limitado explícitamente a \`lf_ops\`,
  elegido por operador del sandbox. No extrapolar a alcance de usuarios reales.
- Verificación de seguridad: \`lf_ops.cargas_lotes\` y
  \`lf_ops.cargas_archivos\` tienen RLS \`ENABLE/FORCE\` y política
  \`deny_direct_client_access\` para roles anon/authenticated.
  La consulta a metadatos no otorga SELECT de datos a esos roles.

### Condiciones para avanzar a ejecución real
1. Implementar un conector de metadatos con identidad de actor confiable, alcance
   de esquemas y presupuestos resueltos *en Supabase*; rechazar configuración
   suministrada por el modelo y no inferir permisos a partir de coincidencias.
2. Usar la política canónica \`POL-LF-SOURCE-RESOLUTION\`, con corriente version/SHA,
   y \`ORCHESTRATOR_EXECUTION_GUARD\` antes de invocar capacidades.
3. Conectar D2 al planificador actualmente liberado, conservando su contrato
   \`candidates[]\` y \`current_evidence[]\`.
4. Implementar lectura de filas solo mediante una ruta autorizada por actor,
   empresa, capacidad y propósito, evitando evasión de RLS con service_role.
5. Grabar casos oficiales, métricas, RAW y receipts exclusivamente en Supabase;
   Excel solo presenta una extracción o vista de lectura.
6. Benchmark pareado y adversarial baseline vs candidato: respuestas correctas,
   preguntas evitables, ampliación de búsqueda, cero regresiones críticas,
   costos/latencia. Sin verificación completa no hay cutover.

**Estado:** candidato de diseño/prototipo; este PR no incluye migración canónica,
registro de nueva capacidad en Supabase, runtime activo ni benchmark end-to-end.

- Regresiones adicionales: descripción de metadatos de tipo inválido, objetos de candidato mal formados y consumer_ref vacío bloquean sin invocar D2.
