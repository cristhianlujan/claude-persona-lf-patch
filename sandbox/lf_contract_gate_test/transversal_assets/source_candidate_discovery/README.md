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


## D2 — Authorization preflight, observed on 2026-10-10
- Added \`source_access_preflight_deny_only_v1.sql\` and
  \`source_access_preflight_readonly_probes_v1.sql\`. Both are read-only,
  candidate-only; neither grants source access nor introduces another policy.
- Supabase live readback:
  - \`auth.uid()\`, \`lf_ops.b2b_current_user_id()\` and
    \`lf_ops.b2b_current_company_id()\` are all NULL on the administrative
    diagnostic connection. The access preflight returned
    \`BLOCK_ACTOR_NOT_AUTHENTICATED\`.
  - Valid catalog source+current policy: catalog and currentness PASS, but
    data access stays DENIED without authenticated actor.
  - Missing source: \`BLOCK_SOURCE_NOT_IN_METADATA_SCOPE\`.
  - Stale policy version: \`BLOCK_POLICY_VERSION_MISMATCH\`.
  - \`anon\` and \`authenticated\` lack direct SELECT grants on both
    \`lf_ops.cargas_lotes\` and \`lf_ops.cargas_archivos\`. Admin
    \`postgres\` grant MUST NOT be used as consumer authority.
  - \`POL-LF-SOURCE-RESOLUTION\` currently ACTIVE with SHA
    \`5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46\`.
  - A scoped search of \`public.lf_activos.metadata\` and
    \`public.v_lf_fuente_operativa_busqueda\` found no exact existing
    reference to \`cargas_lotes\` or \`cargas_archivos\`.
    **Do not infer a canonical source-to-permission binding from a table name.**
- Existing \`lf_ops.permisos\` provides resource/action permissions (including
  \`LOAD/VIEW_DETAIL\` and \`LOAD_HISTORY/VIEW\`), but this is not evidence of a
  governed mapping for each discovered table, nor a right to read rows.
- The next required *controlled change* is a Supabase-owned binding from
  \`source_ref\` to a vetted read facade + resource/action + tenant scope and
  actual permission evidence. It must have genuine pass/fail outcomes, protect
  against cross-tenant access, and be exercised under a valid authenticated
  context. Reuse the canonical registry/policy and test contracts; do NOT
  invent table-name substring routing, permissive GRANTs, or security-definer
  bypasses.

The preflight in this PR is intentionally a **deny-only diagnostic**, not a
permanent production gate: before implementation of an admissible read path,
it must not be mistaken for complete D2.

## Lote D2 — vínculo canónico y autorización (2026-10-10)
- EKB actual `GOV-FIELD-LEVEL-SOURCE-RESOLVER-GAP-001` ya indica la solución transversal: binding tipado objeto/campos/query-template/fingerprint; se evita otro buscador o permission engine.
- Reutilización propuesta: `public.lf_activos` (tipo DB_TABLE/TABLE), `public.v_lf_fuente_operativa`, `public.lf_operation_step_contracts`, `lf_ops.permisos`, asignación usuario–empresa y permisos por empresa. No se creó tabla/función/regla paralela.
- `source_read_binding_contract_candidate_v1.md` define los metadatos y criterios necesarios para admitir una `read_facade_ref`, sin activar los permisos.
- `source_permission_admission_matrix_synthetic_v1.sql` fue recuperado de GitHub blob SHA `e6c8844b086a346a097f2b45ada4dd2a5c5ed6dc` y ejecutado tal cual en Supabase sandbox: **12 PASS, 0 FAIL**, con 1 decisión favorable **solo sintética** y 11 negativas (falta de actor, cross-tenant, DENY, binding faltante, estados candidatos, etc.). No demuestra lectura real.
- `source_access_live_denial_probe_v1.sql` blob SHA `d070330d222428055356e60a5aa22660fe2fe60f`: lectura real solo del catálogo/estados y autenticación; devuelve `metadata_source_exists=true`, binding VIGENTE=false, permiso VIGENTE=false, actor=false, `business_data_read_authorized=false`, `BLOCK_CANONICAL_READ_BINDING_ABSENT`.
- Resultado de inventario: 44 permisos B2B CANDIDATO, 1 VIGENTE (global); los 13 de cargas son CANDIDATO. No hay usuarios B2B, asignaciones usuario–empresa ni permisos empresariales en el sandbox (0/0/0). No simular un PASS real mediante cuenta administrativa.
- Mientras no se publique la asociación en Supabase y exista una identidad de prueba autorizada bajo RLS, el D2 real permanece **BLOCKED_REAL_AUTHORIZATION_EVIDENCE**. Sin merge, cutover ni cambio en datos/policies.

## Lote 2026-10-10 — D1 multifamilia + D2 reconciliación

**D1 / fuentes de Supabase**
- `multifamily_source_discovery_readonly_v1.sql` combina exclusivamente:
  - `pg_catalog` limitado a esquemas resueltos por adaptador confiable, para objetos/columnas;
  - `public.v_lf_fuente_operativa_busqueda`, autoridad de inventario de activos, alias y palabras clave.
- Todas las búsquedas son de metadatos. DOC/CARD son pistas para contexto, **no** fuentes de autoridad operativa ni autorizaciones de lectura. Fuentes físicas derivadas de `pg_catalog` son candidatos sin binding, nunca permisos.
- La consulta exige versión SHA vigente de `POL-LF-SOURCE-RESOLUTION` y límites de ámbito/costo. El parámetro SHA y el ámbito de esquemas deben provenir del **adaptador confiable**; no existe todavía ese materializador de contexto de actor/tenancy para D1.
- **Ocho pruebas directas Supabase del mismo SQL (parámetros de prueba acotados): 8/8 PASS**: carga, login, pago (solo DOC), oferta (solo CARD), inexistente/no-match, policy stale, scope vacío y presupuesto inválido. Todos devuelven `data_access_granted=false`, `discovery_exhausted=false`.
- SQL blob SHA verificado de `multifamily_source_discovery_readonly_v1.sql`: `5a836645b2ffa9efe36e3d305589310b70f85f8b`.

**D2 / planificador vigente**
- `targeted_evidence_planner_integration_readonly_v1.sql` fue ejecutado exactamente desde GitHub contra `public.lf_targeted_evidence_acquisition_plan_v1` en sandbox: **2/2 PASS**.
- `CONTINUE` propone evidencia; NO ejecuta efectos. `STOP_NO_DECISION_CHANGING_EVIDENCE` con `automation_options_exhausted=true` solo agota los candidatos pasados al planificador, **no** la búsqueda global.
- `planner_reconciliation_v1.py` produce transición a nueva exploración, validación de readback o bloqueo por estado falsificado; jamás afirma agotamiento global ni otorga lectura. Su entrada admitida sigue sujeta a implementación de lectura canónica de Supabase desde el runtime.
- Se agregaron 13 pruebas unitarias del reconciliador en Git; 12 casos equivalentes ejecutados en entorno Python local 12/12 y la regresión de estado desconocido verificada por prueba específica. **No es una ejecución completa del CI ni una prueba E2E del runtime**.

**Binding positivo de metadatos, NO acceso a negocio**
- `registered_entrypoint_security_probe_v1.sql` ejecutó 2 probes exactos desde GitHub: un activo de login B2B que apunta a vista/RPC físicamente existentes y un activo inexistente rechazado. La vista registrada no declara `security_invoker=true`, y `anon`/`authenticated` carecen de SELECT; **no autorizar** lecturas mediante esta asociación.

**Faltantes obligatorios para cierre operativo**
1. Adaptador de identidad/ámbito/política/permissions ejecutado por servidor confiable y respaldado por Supabase; nunca flags de GPT.
2. Binding tipado `source_ref → fuente canónica → permiso/tenant → read_facade` con estado VIGENTE, SHA de esquema/filtros/costo/recibo; usar `lf_activos` y `lf_operation_step_contracts` existentes, no una segunda base de reglas.
3. Prueba positiva real de lectura autorizada, negativa cross-tenant y negativa sin permiso, sin bypass RLS/roles privilegiados.
4. Runtime D1→D2→resolver autorizado→evidencia tipada→replanificación con recibos.
5. Casos, evaluación comparativa pareada y resultados canónicos en tablas de pruebas **Supabase**, no Excel; incluir holdout independiente y adversarial sin fuga de oráculo.

Estado: rama y PR **DRAFT**, sin migraciones aplicadas, sin merge, sin promoción, sin efectos productivos. Ningún resultado equivale a autonomía operacional demostrada.
