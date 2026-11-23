# TRAZA LITERAL · SALY ORDER 9 / ITEM 13

Los bloques INPUT / OUTPUT son valores literales observados. No se reconstruyen llamadas que no quedaron registradas.

## 01 — SELECT pedido e ítem (lectura actual)
**INPUT / herramienta:** `Supabase.execute_sql`
```sql
SELECT o.id AS order_id, o.status AS order_status, o.scope_json, i.id AS item_id, i.code AS item_code, i.status AS item_status, i.context_json, i.acceptance_json, i.qa_receipt, (SELECT count(*) FROM saly.creative_runs r WHERE r.order_id=o.id AND r.item_id=i.id) AS run_count FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id WHERE o.id=9 AND i.id=13;
```
**OUTPUT / JSON del SELECT (literal):**
```json
boundaries.\n\n<untrusted-data-2274150e-f582-4b93-9716-f80697839cf7>\n[{\"order_id\":9,\"order_status\":\"BORRADOR\",\"scope_json\":{\"screen\":\"HOME\",\"queue_mode\":\"SERIAL_V1\",\"review_only\":true,\"change_scope\":\"ONLY_MI_DISPONIBLE_AS_VIEW_CALCULATION_LINK\",\"interpretation\":\"En HOME, el bloque Mi disponible debe mostrar un acceso navegable a Cómo se calcula (chevron), sin un importe monetario. Mantener todo lo demás igual. El valor S/ 800 del mockup no está autorizado.\",\"literal_origin\":\"USER_MESSAGE_VERBATIM_EXCERPT\",\"literal_sha256\":\"928dd49fc87a21cd4ac396b1a6a78b7a7b4f89442b45e57bc352ff4f8ff01060\",\"preview_origin\":\"CHAT_GENERATED_IMAGE_NO_VERIFIED_DB_RUN\",\"schema_version\":\"SALY_HOME_MIDISPONIBLE_REFINEMENT_DRAFT_V1\",\"blocking_reason\":\"NOT_COMPILED_NOT_QA_ATTESTED_NOT_RENDER_AUTHORIZED_NO_QUEUE_SLOT\",\"literal_request\":\"un refinanmiento al perido donde se indica que el mi disonible es un ver para que vea como se calcual.\",\"target_component\":\"HOME.SUMMARY.MI_DISPONIBLE\",\"render_authorized\":false,\"intake_semantic_qa\":{\"verdict\":\"PENDING\",\"required\":true},\"single_change_only\":true,\"source_message_ref\":null,\"rendering_authority\":false,\"intake_source_status\":\"VERBATIM_EXCERPT_PENDING_INDEPENDENT_QA\",\"refinement_of_item_id\":10,\"refinement_of_order_id\":7,\"dependency_policy_state\":\"UNRESOLVED_IMMUTABLE_SUCCESSOR_CHAIN\",\"preview_artifact_sha256\":\"8854a525b61d5642b3e864d5f35dbd9e3fdaf1bab83754ddeaa884eaf90f52d0\",\"source_verification_status\":\"USER_EXCERPT_AVAILABLE_MESSAGE_ID_NOT_VERIFIED\",\"no_changes_to_other_components\":true},\"item_id\":13,\"item_code\":\"HOME_MIDISPONIBLE\",\"item_status\":\"PENDIENTE\",\"context_json\":{\"screen_spec\":{\"device\":\"IPHONE16PRO\",\"screen\":\"HOME\"},\"parent_item_id\":10,\"parent_order_id\":7,\"target_component\":\"HOME.SUMMARY.MI_DISPONIBLE\"},\"acceptance_json\":{\"assertions\":[\"Mi disponible is a navigation entry to Cómo se calcula\",\"Do not render a standalone monetary value in Mi disponible\",\"All other HOME regions and their copy unchanged\"],\"qa_required\":true,\"semantic_qa\":{\"status\":\"PENDING\"}},\"qa_receipt\":{},\"run_count\":0}]\n
```

## 02 — SELECT logo (lectura actual)
**INPUT / herramienta:** `Supabase.execute_sql`
```sql
SELECT id, code, version_number, name, file_provider, external_file_id, sha256, approval_status FROM saly.brand_assets WHERE code='logo.primary.transparent' ORDER BY version_number DESC LIMIT 1;
```
**OUTPUT / JSON del SELECT (literal):**
```json
boundaries.\n\n<untrusted-data-0e9ea929-bf74-42cf-8c0c-a0558438ea6d>\n[{\"id\":9,\"code\":\"logo.primary.transparent\",\"version_number\":1,\"name\":\"01_SALY_PRINCIPAL_TRANSPARENTE.png\",\"file_provider\":\"GOOGLE_DRIVE\",\"external_file_id\":\"1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78\",\"sha256\":\"5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995\",\"approval_status\":\"APPROVED\"}]\n
```

## 03 — Archivo logo, comprobación local
**INPUT:** `sha256sum /mnt/data/01_SALY_PRINCIPAL_TRANSPARENTE.png`
**OUTPUT:**
```text
5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995  /mnt/data/01_SALY_PRINCIPAL_TRANSPARENTE.png
```

## 04 — image_gen (invocación anterior de esta conversación)
**INPUT real transmitido:** NO REGISTRADO / NO RECUPERABLE COMO PAYLOAD LITERAL. No se sustituye por un texto reconstruido.

**OUTPUT informado por la herramienta:**
```json
{"gen_id":"a8f5c1a9-6a73-42f9-9bcf-bdaaa1b6bb5d","parent_gen_id":null,"prompt":"","seed":null}
```
**Archivo entregado:** `/mnt/data/mockup_del_iphone_con_app_saly.png`

## 05 — Verificación del archivo generado (lectura actual)
**INPUT:** Python, abrir `/mnt/data/mockup_del_iphone_con_app_saly.png` con PIL, leer tamaño / formato, calcular SHA-256.
**OUTPUT:**
```json
{"path":"/mnt/data/mockup_del_iphone_con_app_saly.png","width":1024,"height":1536,"mode":"RGB","sha256":"0adca875c7cd40aed73937914b8b8b4fcfe76138e5f72cc702e632f28e2f88e3","bytes":1570760}
```

## 06 — Cierre SQL de order 9 / item 13
**INPUT de escritura:** NO EJECUTADO.
**OUTPUT de escritura:** NO EXISTE.
**OUTPUT de lectura:** ver SELECT literal del paso 01 (`order_status=BORRADOR`, `item_status=PENDIENTE`, `run_count=0`).

**Notas de integridad:** este registro no certifica que el prompt compilado de una orden SQL se enviara a `image_gen`. No crea un RUN retrospectivo, no atribuye al generador un archivo de logo que no pueda probarse como adjunto real, no cambia estados.
