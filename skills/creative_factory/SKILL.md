---
name: creative-factory-standalone
description: Orquesta la composición gráfica de revisión reutilizando el compilador, adaptador por negocio y verificador de transporte existentes, sin invocar Router, perfiles ni generación de producción.
---

# Fábrica Digital — skill autónoma v0.6 (PLAN_ONLY / REVIEW_ONLY)

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

## Constructor de dirección de arte y QA previo (v0.5)

**Objetivo:** interpretar el entregable completo, no confundir el arte final con
el cuerpo que recibe un generador parcial. No convertir el ejemplo Home en
una receta fija. La dirección de arte es propuesta por la skill en función
de cada intención y de las fuentes del negocio.

### Secuencia obligatoria antes de compilar un nuevo handoff

1. **Entregable y destino:** aclarar en la interpretación si el pedido exige
   escena completa de producto (`FULL_SCENE`), cuerpo separado
   (`BODY_ONLY`) u otro activo (`OTHER_ASSET`). Mantener vista, encuadre,
   soporte y finalidad pedidos. Una escena completa puede incluir partes que
   ejecutan distintos componentes; no degradarla a cuerpo aislado ni hacer
   dibujar a Native un activo fijo que corresponde al compositor.
2. **Descubrimiento de fuentes:** localizar identidad, tokens, activos,
   textos, datos, reglas/patrones, referencia visual y geometría aplicables.
   Usar las fuentes del adaptador del negocio y la versión congelada; si
   un elemento (logo, dispositivo, icono, copy, etc.) es obligatorio y
   no está resuelto, declararlo pendiente. No inventar leyendas, valores,
   permisos, ubicación de archivos ni decisiones oficiales.
3. **Dirección de arte:** especificar seis dimensiones con una instrucción
   concreta y una justificación ligada al pedido/fuentes: escena y
   presentación, estilo y lenguaje visual, fondo y ambiente (incluye luz
   y sombras cuando procede), tipografía, jerarquía/composición y calidad
   visual/impacto buscado. Para una dimensión no aplicable explicar por qué.
   No basta "premium", "moderno" o "wow": describir qué los materializa.
4. **Desglose por componente:** recorrer toda la jerarquía del
   `CREATIVE_VISUAL_BLUEPRINT_V1`, no un checklist fijo de Home. Cada parte
   precisa propósito, posición/relación, estilo, textos exactos cuando
   correspondan, iconografía/imagen, fuente y responsable de ejecución.
   Reutilizar `design_lock.LOCK/GUIDED/FREE`: preservar contenido fijo,
   orientar tratamiento creativo y delimitar libertades. Separar los
   responsables NATIVE / COMPOSITOR / REFERENCE_ONLY para evitar duplicación.
   Un texto solicitado se conserva literal y no autoriza cambiar una fuente
   oficial; si hay conflicto mostrarlo y bloquear la compilación afectada.
5. **Preflight estructural obligatorio:** invocar
   `sandbox/creative_factory/art_direction_preflight_v1.py:preflight(plan)`
   con el blueprint y la propuesta. El plan incluye `business_code`,
   `literal_request`, `blueprint`, `presentation` (mode, destination),
   `direction`, `components`, `sources` y `requirements`.
   Las seis claves de direction son scene/style/background/typography/
   hierarchy/visual_impact, cada una con instruction, rationale, requirements.
   Cada componente contiene name, owner, freedom, instruction, copy,
   source_ids, requirements. Cada requisito tiene id, source y quote literal
   del pedido (REQUEST) o de una fuente; cada fuente tiene id,
   business_code, ref, version, status, text y sha256 de sus bytes UTF-8.
   Obtener snapshots reales del adaptador; la huella del texto es integridad
   local, no autenticación de origen ni hash del archivo gráfico.
   El resultado `STRUCTURAL_PASS_SEMANTIC_PENDING` es un suplemento
   de planificación para el constructor existente, **no** un payload Native.
   Un fallo bloquea y muestra el código, aplicando el protocolo de incidencias.
6. **QA semántico previo independiente:** un revisor diferente del autor de
   la propuesta coteja el pedido literal y las fuentes, no solo el resumen del
   autor. Evaluar (a) completitud del entregable, (b) cobertura real de todos
   los requisitos, incluida la detección de requisitos omitidos antes de
   construir la lista, (c) consistencia con activos/tokens/copy oficiales y
   candidatos, (d) especificidad de dirección de arte y tratamiento por
   componente, (e) responsabilidad y ausencia de contradicciones entre
   generador y compositor, (f) creatividad compatible con LOCK/GUIDED/FREE,
   (g) que la instrucción final sea renderizable y libre de metadatos QA,
   y (h) hash del plan y evidencia de la revisión. No confundir un resultado
   estructural ni una autorrevisión con PASS independiente.
   Si el revisor o la evidencia no están disponibles, mantener
   `SEMANTIC_QA_PENDING` y no enviar.
7. **Compilación:** tras el QA previo, adaptar los campos de arte y componentes
   al blueprint canónico y reutilizar el compilador vigente para su nuevo
   contrato/hash. No concatenar el suplemento directamente al prompt
   sellado, no reescribir contratos históricos, no alterar el modo de
   revisión, permisos ni activos. Mostrar el payload exacto (únicamente las
   instrucciones pertinentes al receptor) y continuar automáticamente
   solo si existe canal y autoridad, conforme a los controles de abajo.

### Pruebas y límites

```bash
cd sandbox/creative_factory
python -m unittest -v test_art_direction_preflight_v1.py
```

El preflight es transversal y local: no llama Router, perfiles, Supabase
ni proveedores. Valida los requisitos **declarados**, no descubre por sí solo
todos los requisitos ni autentica las fuentes. Los escenarios positivos
incluyen escena completa, cuerpo aislado y otro negocio/activo; los 19
negativos incluyen fuentes cruzadas, hash alterado, omisiones de componentes,
copy no sustentado, falta de dirección y conflicto de responsables.
No declara QA semántico independiente, render real ni persistencia de
nuevos pedidos. El flujo L2C anterior permanece intacto.

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

## Composición flexible por blueprint (v0.6, revisión local)

No imponer el layout de Home B a una escena nueva. El mismo entrypoint
`compositor_core_v1.compose(manifest, body)` admite el contrato histórico
`CREATIVE_COMPOSITION_REVIEW_V1` y el contrato candidato
`CREATIVE_COMPOSITION_BLUEPRINT_REVIEW_V2`. La extensión
`compositor_blueprint_layers_v2.py` reutiliza primitives y preflight
existentes; no es otra skill ni otro pipeline.

Para preparar V2:
- Partir del plan de dirección de arte y jerarquía, con la propuesta de
  geometría aprobable por el flujo de QA. Incluir en el blueprint
  `composition_layout` y en `design_lock.LOCK.composition_layout` la misma
  estructura {canvas, backdrop, regions}. Congelar el hash de propuesta del
  preflight. El manifest no puede sustituir esas posiciones.
- Cada región respeta nombre, orden y propietario de los componentes del
  plan; contiene name, owner, box (x,y,ancho,alto), coverage y ops. NATIVE
  reserva zonas BOX sin operaciones fijas; REFERENCE_ONLY usa NONE, box null,
  ops vacías. COMPOSITOR BOX reserva toda la caja, ALPHA reserva únicamente
  los píxeles no transparentes de un único activo fijado (por ejemplo, marco).
- Las operaciones compositor, ordenadas dentro de cada caja, son FILL
  (box, color_source, radius), ASSET (box, source_id) o TEXT
  (box, copy, size, weight, font_source, color_source). Sus fuentes deben
  pertenecer al componente; los textos coinciden con el copy declarado.
  FILL y TEXT pueden compartir la caja del CTA dentro de una tarjeta mayor.
  Un activo con texto sigue necesitando verificación visual del copy.
- El fondo es TRANSPARENT, COLOR vinculado al token, o ASSET con archivo
  fijado por SHA y dimensiones exactas de salida. Cada fuente usada como
  archivo incluye file_sha256 en su snapshot JSON, y las fuentes tipográficas
  además weight; no inventar huellas de archivos oficiales. El registro
  files mapea identificadores de fuente a las rutas materializadas.
- El cuerpo RGBA sintético tiene exactamente las dimensiones canvas. Debe
  dejar transparentes los píxeles fijos y no invadir zonas ajenas. No recortar
  arbitrariamente un resultado Native para hacerlo pasar. El marco con
  apertura transparente se compone mediante su silueta; cajas de activos
  fijos BOX no pueden colisionar con otras máscaras fijas.
- Manifest V2 contiene schema_version, review_only=true,
  render_authorized=false, body_origin=SYNTHETIC_REVIEW, plan,
  proposal_sha256, canvas, backdrop, regions y files. Realizar preflight
  antes de componer, comprobar SHA de los activos, generar recibo y
  aplicar el protocolo de incidencia ante fallo. No declarar un resultado
  de Native desde un fixture ni usar el modo revisión para eludir autoridad.

Ejecución técnica directa, sin Router, perfiles, proveedor ni generación:

```bash
python sandbox/creative_factory/compositor_core_v1.py manifest.json body.png preview.png --receipt receipt.json
cd sandbox/creative_factory
python -m unittest -v test_compositor_blueprint_layers_v2.py
```

El recibo V2 `LOCAL_BLUEPRINT_COMPOSITOR_PASS` acredita composición local
reproducible, no QA semántico ni autenticidad de fuentes por sí solo.
El adaptador L2C histórico conserva su contrato V1 y no se migra
automáticamente a V2. El nuevo layout es un candidato local: todavía
requiere materialización/compilación gobernada, revisión independiente y
canal de recepción Native verificable antes de cualquier uso productivo.

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

## Control automático antes y después de cada envío — handoff visible

**Disparadores obligatorios, sin intervención del usuario:**
- Al preparar cualquier handoff operativo entre componentes de la skill:
  mostrarlo y, si el envío ya está autorizado y es técnicamente posible,
  transmitirlo inmediatamente en la misma ejecución, sin esperar respuesta,
  confirmación, mensaje nuevo ni microaprobación del usuario.
- Al detectar cualquier error, rechazo o incumplimiento: solicitar al
  receptor el handoff del mismo intento, comparar y mostrar el diagnóstico
  automáticamente según el protocolo siguiente, sin esperar una instrucción.

La visualización no es una pausa de aprobación. No agrega permisos, no
habilita proveedores ni convierte un resultado de revisión en producción.

### Antes del envío

1. Resolver y congelar el payload y adjuntos exactos del contrato autorizado.
   Para Native, reutilizar los bytes de `canonical_wire.wire_base64` y su
   `wire_sha256` emitidos por `saly.creative_native_canonical_wire_v1`.
2. **Mostrar al usuario el handoff completo y literal antes de invocar
   al receptor**, en una salida visible intermedia de la misma ejecución.
   Incluir emisor, receptor, negocio, pedido/item/variante, intento si existe,
   prompt íntegro, adjuntos y referencias exactos, SHA del payload y estado
   `HANDOFF_PREPARED_NOT_SENT`. Indicar explícitamente si no hay adjuntos.
   Excluir credenciales, secretos e instrucciones internas del sistema.
   La cabecera del diagnóstico no forma parte del mensaje al receptor.
3. Sin esperar al usuario, comprobar que el contenido a emitir y los
   adjuntos son los mismos que se acaban de mostrar. No regenerar, resumir,
   reserializar ni añadir contexto operativo o QA a un payload que no lo
   incluye. Si cambian, volver a congelar y mostrar el handoff antes del
   envío. Una vista previa no sustituye la evidencia de transmisión.
4. Si ya existe autorización y canal de envío exacto, invocar al receptor
   inmediatamente en la misma ejecución. Si falta autoridad o capacidad
   técnica, no enviar: informar `HANDOFF_NOT_SENT` y la causa. No saltar
   controles existentes ni ampliar el alcance aprobado.

### Después del envío

5. Mostrar automáticamente el resultado de la invocación y su evidencia
   real: referencia del intento, recibo disponible, huella de bytes emitidos
   cuando el canal la exponga, adjuntos enviados y cotejo con lo mostrado.
   Si hubo una invocación real sin evidencia exacta suficiente, informar
   `HANDOFF_SENT_UNVERIFIED`. Si no hubo invocación, `HANDOFF_NOT_SENT`.
   Nunca presentar el hash preparado como prueba de envío o recepción.
6. Continuar automáticamente con recepción y QA autorizados. Ante fallo
   aplicar el protocolo de readback de abajo en esa misma ejecución:
   solicitar al receptor su handoff funcional exacto, recuperar el readback
   si existe, comparar y mostrar divergencias sin esperar otro turno.
   Si el canal no recupera el payload recibido, informar
   `HANDOFF_RECEIVER_READBACK_UNAVAILABLE`; no inventar evidencia ni
   reintentar sin resolver la causa y respetar la autorización vigente.

**Criterios de aceptación:** (a) vista literal visible antes de invocar,
(b) envío automático sin confirmación intermedia cuando está autorizado,
(c) evidencia de salida visible inmediatamente después, (d) readback
automático ante rechazo, (e) bloqueo verificable si falta autoridad,
capacidad de envío exacto o evidencia del receptor. Una imagen con recibos
o indicadores PASS no satisface estos controles.

Este cambio define el comportamiento obligatorio de la skill; la integración
real con un proveedor sigue condicionada a un canal disponible y autorizado.
No se crea ni invoca Router, perfiles o RUNs de perfil.

## Protocolo obligatorio ante rechazo o incidencia — readback del handoff

**Disparador:** cualquier ERROR, BLOCKED, FAIL, REJECTED o incumplimiento observado
durante la preparación, transporte, generación, composición o QA. No esperar
a que el usuario pida el handoff. Disparar el diagnóstico automáticamente en
la misma ejecución; detener solo la entrega y el reintento no verificado.

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
