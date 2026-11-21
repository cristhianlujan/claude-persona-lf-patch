---
name: creative-factory-standalone
description: Orquesta la composición gráfica de revisión reutilizando el compilador, adaptador por negocio y verificador de transporte existentes, sin invocar Router, perfiles ni generación de producción.
---

# Fábrica Digital — skill autónoma v0.3 (PLAN_ONLY / REVIEW_ONLY)

## Alcance y activación

La skill puede invocarse directamente en modo PLAN_ONLY mediante el adaptador
SALY de lectura, o por CLI con un **paquete congelado** y archivos locales.
NO ejecuta ni llama Router, perfiles, RUN de perfil, proveedores ni aprobaciones.
PLAN_ONLY lee Supabase exclusivamente por la RPC autorizada descrita abajo;
COMPOSE_REVIEW_ONLY permanece offline. No se registra en el selector de perfiles durante este lote.
No reemplaza ni duplica `SALY_VISUAL_CONTEXT_INVENTORY`, `SALY_APP_VISUAL_PROBE`,
`adapter_saly_review_v1`, `native_transport_capture_v1` o `compositor_core_v1`.

**Estado actual:** demostrable con SALY usando un paquete L2C de revisión y un
cuerpo gráfico **sintético**. No admite cuerpos declarados como resultados de GPT Native
sin origen autenticado. Sin adaptador específico no se ejecutan LF ni negocios nuevos.

## Preparación autónoma de un pedido (Macrolote A)

**Entrada inicial:** texto literal del usuario + negocio + objetivo. La interpretación
semántica pertenece a la skill, no al Router. Antes de compilar, separar el texto
literal (no corregirlo ni resumirlo como si fuera original) de una propuesta con:
- objetivo funcional y entregable solicitado;
- pantalla/variante y qué debe conservarse;
- contenido/copy/cifras con autoridad de origen;
- áreas fijas y libertad creativa;
- fuentes requeridas y criterios de aceptación técnicos y semánticos.

No inventar valores ni declarar una interpretación propuesta como aprobada.
Si todavía no existe pedido e interpretación sellados, devolver la propuesta
`NEW_INTENT_REQUIRES_INTERPRETATION` y los datos pendientes, sin construir
un prompt operativo usando otro pedido. La creación/persistencia de pedidos
nuevos no se implementa en este lote.

**Para un pedido existente:** una vez localizado el objetivo exacto por negocio,
proyecto, código de pedido e item, invocar la RPC de solo lectura
`saly.creative_skill_prepare_v1(p_request jsonb)` desde el cliente autorizado
`service_role`. No usar credenciales del usuario como autoridad ni elevar el
rol de solo lectura. El JSON tiene exactamente siete campos:

```json
{
  "schema_version": "CREATIVE_SKILL_PREPARE_REQUEST_V1",
  "mode": "PLAN_ONLY",
  "business_code": "SALY",
  "project_code": "SALY-001",
  "order_code": "<código localizado>",
  "item_code": "<código de variante localizada>",
  "literal_request": "<texto original exacto del pedido>"
}
```

La RPC reutiliza `creative_item_work_packet_l2c` para descubrir y verificar
fuentes y contrato; `creative_native_canonical_wire_v1` para devolver los
bytes exactos, no una reconstrucción por Python o por el modelo.
El resultado `CREATIVE_SKILL_PLAN_V1` muestra en orden:

1. **Interpretación**: negocio, objetivo y variante. Texto original y
   estrategia separada en `work_packet.review_contract.contract.acceptance_criteria.semantic_qa`;
   hashes del literal y mensajes originales.
2. **Descubrimiento**: versión de plantilla, tokens y cadenas de resolución en
   `work_packet.review_contract.contract.handoff.trace`, logo (proveedor,
   archivo, versión, SHA), frame/iconos con sus bytes y referencias en
   `work_packet.composition_svg_assets`. Valores CANDIDATE no se promueven.
3. **Blueprint**: geometría, áreas fijas/creativas y prompt literal desde el
   handoff; `canonical_wire.wire_base64` y `wire_sha256` son los bytes del
   mensaje que debe usarse después, sin reenviar ni reserializar ahora.
4. **QA preparado, no ejecutado**: criterios técnicos y semánticos de la
   fuente. Exponer conteos y códigos; nunca afirmar el resultado visual.

Mostrar al usuario los valores efectivamente leídos en cada etapa. Solo
`PLAN_PREPARED_REVIEW_ONLY` permite pasar a revisión del plan. Ante
`SKILL_PLAN_SOURCE_NOT_READY` mostrar el estado real y bloquear; ante
`SKILL_NEW_INTENT_REQUIRES_INTERPRETATION` separar nueva intención del
contrato anterior. Si negocio o proyecto carecen de adaptador, no buscar
en fuentes de otro negocio. No invocar GPT Native ni producir imágenes.

La prueba SQL de despliegue consume Home B canónico, compara ambos outputs
directos de las funciones existentes, ejecuta 13 negativos y verifica que las
cantidades de pedidos, items, RUNs, capturas y recibos QA no cambian.
El cliente limitado de lectura puede cotejar filas/hashes pero no llamar esta RPC.

## Contrato de entrada

`CREATIVE_SKILL_STANDALONE_REVIEW_V1`, modo `COMPOSE_REVIEW_ONLY`:
- `business_code`: código del negocio declarado en el input aislado. No confiere permisos.
- `packet_path` + `packet_sha256`: paquete inmutable con su hash **de bytes**.
- `logo_path`, `fonts_path`, `body_path`: fuentes y cuerpo local.
- `body_origin=SYNTHETIC_REVIEW`: no equivale a respuesta del proveedor.
- `output_dir`: directorio **nuevo** para resultado y recibo técnico.

No recibe perfil, Router, skill de inventario, credenciales, write authority ni
instrucciones para omitir validaciones. El esquema del paquete SALY
(`SALY_WORK_PACKET_L2C_V1`) se verifica contra el adaptador registrado. Un código
LF/futuro nunca reutiliza los datos de SALY como sustituto.

## Flujo obligatorio

1. Validar modo, negocio y campos exactos. Seleccionar adaptador autorizado;
   si falta, `SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE`.
2. Leer el paquete como bytes locales (sin red) y comprobar su hash, versión y
   permisos `REVIEW_ONLY`.
3. Reutilizar `native_transport_capture_v1.sealed_envelope` para comprobar
   prompt literal, adjuntos, item, contrato y SHA; **no enviar**.
4. Reutilizar `adapter_saly_review_v1.from_packet` para materializar en un
   directorio temporal solo SVGs de fuente con SHA y resolver tokens, logo y
   tipografía del contrato. No inventar paleta, copy ni plantilla.
5. Reutilizar `compositor_core_v1.compose` con el cuerpo sintético en slots
   autorizados; producir dos composiciones y compararlas para determinismo.
6. Escribir `composition_review.png` y `receipt.json`; reabrir PNG, comparar
   bytes/píxeles y registrar hashes. La entrega contiene solo esos dos archivos.
7. Cualquier error impide la publicación y devuelve código específico.
   No modificar artefactos previos.

## Resultado y límites de QA

`LOCAL_TECHNICAL_REVIEW_PASS` solo acredita revisión técnica determinista:
hashes, integridad, geometría, aislamiento de áreas, reproducibilidad y readback.

El recibo SIEMPRE declara:
`native_transmitted=false`, `provider_receipt=null`,
`semantic_qa=NOT_EVALUATED`, `production_approved=false`,
`image_generation_allowed=false`, `router_invoked=false`,
`profile_invoked=false`, `database_written=false`.

No elevar a `QA_PASS`, `NATIVE_DELIVERED` ni `RENDER_AUTHORIZED`.
Un juicio visual/semántico independiente y la recepción del proveedor requieren
contratos y evidencias separados, fuera del alcance autónomo actual.

## Protocolo obligatorio ante rechazo o incidencia — readback del handoff

**Disparador:** cualquier ERROR, BLOCKED, FAIL, REJECTED o incumplimiento observado
durante la preparación, transporte, generación, composición o QA. No esperar
a que el usuario pida el handoff. Detener la entrega y el reintento automático.

1. Identificar etapa, componente emisor y receptor, pedido/item/variante y
   referencia real de la ejecución o intento, si existe.
2. Recuperar el handoff funcional exacto preparado por el emisor y, si hubo
   envío, su evidencia de salida. Mantener referencias, adjuntos y hashes
   originales; no regenerar el prompt.
3. **Solicitar inmediatamente al receptor del mismo intento que envíe el
   handoff funcional que recibió**. Mensaje de diagnóstico, no de generación:
   "Devuelve el handoff funcional exacto que recibiste para este intento, sin
   resumirlo, corregirlo ni completarlo. Incluye los adjuntos/referencias
   recibidos y el identificador del intento, si están disponibles. Si no
   puedes recuperar el mensaje exacto, indícalo expresamente. No generes
   otra imagen ni ejecutes otro pedido."
   Usar solo un canal de readback disponible y autorizado. No pedir
   instrucciones internas, credenciales ni datos de otros negocios.
4. Mostrar al usuario ambos handoffs, distinguiendo explícitamente:
   PREPARADO, ENVIADO (solo evidencia de salida) y RECIBIDO (respuesta del
   receptor). Comparar texto/bytes, adjuntos, fuentes y huellas disponibles;
   señalar las diferencias y qué comprobación falló. Una declaración del
   receptor no equivale a atestación del proveedor. No fabricar readback
   ni presentar el handoff de Supabase como si fuera el recibido.
5. Si no hubo envío, informar HANDOFF_NOT_SENT y el último contrato
   disponible. Si no hay canal de consulta o no hay readback del mismo
   intento, informar HANDOFF_RECEIVER_READBACK_UNAVAILABLE y mantener el
   bloqueo. Mostrar por separado el handoff preparado y la evidencia real
   disponible; nunca inventar un identificador o recibo.
6. Localizar la primera divergencia, corregir solo la etapa responsable y
   conservar la evidencia del intento rechazado. Reintentar únicamente
   dentro de la autorización vigente cuando la causa esté resuelta. No
   elevar permisos de render ni promover QA por el simple hecho de obtener
   el handoff.

**Aceptación del protocolo:** rechazo con ambos handoffs permite comparar;
rechazo sin evidencia de recepción permanece bloqueado; error antes del
envío identifica HANDOFF_NOT_SENT. Un eco local, una imagen con texto PASS
o una respuesta reconstruida no prueba recepción. En todos los casos el
usuario recibe el diagnóstico y handoff disponible sin tener que solicitarlo.

Este es un contrato de actuación de la skill; no agrega capacidades al
proveedor ni activa un transporte nuevo. No invoca Router, perfiles ni sus
RUNs y no cambia permisos o registros de Supabase.

## Ejecución y prueba

```bash
PYTHONPATH=sandbox/creative_factory \
  python sandbox/creative_factory/skill_run_review_v1.py --request /ruta/request.json
PYTHONPATH=sandbox/creative_factory \
  python -m unittest -v sandbox/creative_factory/test_skill_run_review_v1.py
```

Pruebas: positivos, determinismo, no sobrescritura, aislamiento SALY/LF/futuro,
fuentes y tipografías por SHA, mutación de prompt y adjuntos, intento de activar
render, logo alterado, invasión de CTA, JSON duplicado, symlinks, salida no
autorizada y ausencia de efectos de Router/perfiles.

## Extensibilidad

La skill es **una sola** para múltiples negocios. Cada negocio adicional aporta
su contrato fuente y un adaptador probado; el motor, los tests de transporte,
compositor, recibo técnico y QA permanecen compartidos.

Hasta contar con adaptador y pruebas contractuales, la ausencia de fuentes
se trata como **bloqueo**, no como permiso para consultar reglas de otro negocio.
Para integrar posteriormente Router y perfiles se requiere otro lote; aquí no
se implementan ni modifican.
