# LF — Separación de calificación técnica (U7) y lectura autorizada (U8/U9)

**Decisión de causa raíz.** La política vigente `POL-LF-SOURCE-RESOLUTION` resuelve fuentes mediante autoridad de Supabase y binding para **uso operativo**. No obliga a que la inspección de metadatos por D1/D2 obtenga aprobación humana. No existe en este sandbox ningún canal `HUMAN_ROUTING_DECISION` ni recibos/autoridades de este tipo; exigirlo por cada fuente crearía una dependencia imposible y bloquearía el objetivo de descubrimiento agnóstico.

## Contrato corregido sin abrir el data plane

**U7 — Calificación técnica autónoma (construcción):**
- Verificar el catálogo gestionado actual; localizar coincidencias y fuentes candidatas por referencia, sin rutas de tablas codificadas por consulta.
- Reutilizar `private.fn_lf_d2_source_binding_candidate_v1` para obtener evidencia del esquema y política; no escribir ni publicar binding.
- `private.fn_lf_source_investigation_prepare_v1` agrega `metadata_admission_decision`, `metadata_source_schema_fingerprint`, `source_policy_sha`, `metadata_technically_verified_count`, manteniendo la semántica de acciones D3 y adaptador D4.
- Una fuente técnicamente verificada NO es `VIGENTE`, no tiene permisos de SELECT de negocio y jamás autoriza filas.

**U8 — Admisión empresarial y ejecución de lectura:**
- Conservar D2 binding VIGENTE, allowlist, límites, fachada SECURITY INVOKER, política y esquema actuales cuando corresponda ejecutar una lectura.
- Resolver actor real, compañía, permiso, revocación, RLS y columnas permitidas; bloquear ausencia, falsificación o cruce de empresas.
- Diseñar la fachada transversal; no utilizar `service_role` para leer filas de negocio; la autorización viene de política y sesión reales.

**U9 — Evidencia de ejecución:**
- Registrar y verificar recibos tipados en el ledger existente, vinculados a ejecución, fuente, identidad, empresa y política; sin ledger paralelo.

## Método y pruebas

El código de este macrolote modifica solo la composición de `fn_lf_source_investigation_prepare_v1`; no modifica la política vigente, tablas, funciones de autorización empresarial, roles ni el runtime. No cambia `next_action` ni el esquema de respuesta v1 usado por D4.

Casos SQL `BEGIN ... ROLLBACK`:
- 2 escenarios positivos de candidatos de metadatos; 1 sin coincidencias y 1 presupuesto inválido, **4/4 PASS**.
- Rechazo de ruta inexistente y formato externo, **1/1 PASS**.
- Regresión del coordinador anterior, **4/4 PASS**.
- La respuesta niega `business_data_read_authorized`, `rows_accessed`, `runtime_dispatched`, `final_business_answer_allowed` y `effects_executed` en todos los casos.

## Rama no admitida
`feat/lf-d2-human-authority-receipt-gate-20261011` es un candidato experimental con ocho pruebas negativas pero ninguna positiva bajo el canal de autoridad real. **No fusionar, no aplicar ni convertirla en dependencia universal.** Las decisiones humanas quedan para acciones de riesgo que las requieran; no para inspección no operativa.

**Cierre U7:** código y pruebas técnicas después del merge y readback exacto; no equivale a lectura real de cargas. En ningún momento se crea una autorización por afirmar `VIGENTE` en JSON. RLS de cargas continúa vigente.
