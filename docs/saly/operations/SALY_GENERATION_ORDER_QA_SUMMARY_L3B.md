# SALY — Orden de generación, QA y resumen visible (L3B)

**Alcance:** SALY_HOME_BATCH_001, fuente oficial Supabase, sin ZIP ni n8n. No habilita generación por sí solo.

## Camino obligatorio

1. El ejecutor autorizado obtiene `order_id` de la orden vigente en Supabase. No acepta identificadores sugeridos por un prompt como autoridad.
2. Llama como `service_role` a `saly.creative_order_live_summary_l3b(order_id)`. **Antes de generar, mostrar al dueño el resumen** con orden, pantallas, dependencias, preparados, bloqueados, generaciones efectivas y QA.
3. Para el ítem elegible llama `saly.creative_item_visual_contract_l3b(item_id)`. Este contrato es la fuente única de valores, criterios, imágenes fuente y SHA para **generador y revisor**.
4. No envía a generación si `native_execution_authorized=false`, si la pantalla está bloqueada o si no hay renderer real invocable. La etiqueta `READY_FOR_NATIVE_HANDOFF` es preparación, **no autorización de renderizado**.
5. Cuando exista motor nativo gobernado, entrega el contrato **sin modificar** y exige eco del `contract_sha256` en el recibo firmado del worker y en el QA. Un prompt aislado en ChatGPT NO prueba esta integración.
6. El QA independiente utiliza los **mismos valores y SHA**, contrasta imagen real + bytes/mediciones de referencias originales y devuelve observaciones por regla con evidencia; un campo `qa_result=NOT_EVALUATED` jamás equivale a PASS.
7. Registra solo ejecuciones reales, artifacts reales, checks de imagen, revisor distinto del generador; actualiza readback y vuelve a mostrar la tabla. Si falla, HOLD con causa concreta.

## Criterios del QA, todos inicialmente NO EVALUADOS

| Código | Origen | Qué verifica | Método y límite |
|---|---|---|---|
| SALY_CTA_BACKGROUND | identity_versions OFFICIAL + SHA | Fondo de CTA primario | Comparación de píxeles/estilo del artefacto, no solo de prompt |
| SALY_CTA_TEXT | Uso aprobado del CTA + representación blanca candidata | Texto blanco | Valor exacto; no promover el token candidato |
| SALY_NO_DECORATIVE_RAYS | acceptance_json.visual_rules de la orden, pedido del dueño | Sin rayitas/palitos decorativos | Análisis visual independiente, no basta con texto |
| SALY_GEOMETRY_SOURCE_MATCH | creative_item_sources + SHA | Proporciones, márgenes y tamaños vs referencia | Requiere recuperar bytes originales y medir; si no, HOLD |
| SALY_NO_UNGROUNDED_FINANCIAL_AMOUNTS | acceptance_json.visual_rules | No inventar saldos, montos, tasas ni fechas | Contrastar valores con datos de negocio verificables |

La identidad oficial permanece en `saly.identity_versions`, el subconjunto de versiones selladas en `saly.creative_context_tokens`, las fuentes por pantalla en `saly.creative_item_sources`, y el pedido/brief en `saly.creative_orders` / `saly.creative_order_items`. El CTA oficial no se sustituye por el verde de marca. Las dimensiones de dispositivo y su patrón nativo siguen sin estar medidas/certificadas: el QA debe indicar `GEOMETRY_NOT_VERIFIED`, no inventar dimensiones ni asignar PASS.

## Resumen visible en cada ejecución

```
SALY | Orden <codigo> | Contexto <id> | Contrato <SHA>
Pantalla    Estado      Dependencia       Generaciones     QA
HOME        PENDIENTE   libre             0                NOT_EVALUATED
ADELANTO    PENDIENTE   HOME aprobada     0                NOT_EVALUATED
REWARDS     PENDIENTE   HOME aprobada     0                NOT_EVALUATED
Preparadas 1/3 · Bloqueadas 2/3 · Completadas 0/3
Siguiente: solo HOME. Sin autorización para renderizar todavía.
```

**Pantalla Bienvenida:** fue creada en una prueba manual anterior y **no existe como ítem en SALY_HOME_BATCH_001**. No afirmar que se generaron cuatro desde el pedido. Si se incorpora, requiere alta gobernada con referencias verificadas y actualización del plan.

**Verificación necesaria:** lectura en SQL con rol autorizado, igualdad de CTA y hashes entre origen y contrato de generación/QA, 3 ítems, 1 READY, 2 BLOCKED, 0 generaciones, 0 PASS. En Github el PASS de CI no sustituye test real PG ni análisis visual.
