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
