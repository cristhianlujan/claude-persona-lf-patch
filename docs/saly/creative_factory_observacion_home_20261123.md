# SALY · Bitácora de observación del proceso gráfico HOME
**Corte:** 23/11/2026, Lima. **Estado:** OBSERVACIÓN ABIERTA. **Alcance:** revisar paso a paso, comenzando por la elección de colores; no generar otra imagen ni actualizar datos de negocio.

**Fuentes consultadas:** Supabase de solo lectura (`saly.identity_elements`, `saly.identity_versions`, `saly.creative_context_sets`, `saly.creative_context_tokens`, `saly.creative_orders`, `saly.creative_runs`), `sandbox/creative_factory/art_direction_preflight_v1.py`, `skills/creative_factory/SKILL.md`, prueba gráfica en chat del 23/11 y archivos PNG locales. Este MD es observación, no aprobación de diseño ni evidencia de despliegue.

## 0. Objetivo de la observación
Por **cada etapa**, exponer: **solicitud original → fuente y autoridad → propuesta del proceso → handoff exacto → salida observada → diferencias → QA → estado real**. No confundir un valor CANDIDATE con APPROVED, ni el prompt compilado con el mensaje realmente enviado.

## 1. Mapa de procesos para observar en orden

| Etapa | Qué debería mostrar el proceso | Lo comprobado en esta revisión | Situación |
|---|---|---|---|
| 1. Ingreso e interpretación | Literal auténtico, restricciones, objetivo, libertad | Pedido #7 tiene QA de origen BLOCKED; #9 PENDING | ABIERTO |
| 2. Inventario de fuentes | Versiones, estados, roles, SHA, origen de colores/logo/copy | Context set #3 SEALED, **7 tokens**; dos APPROVED y cinco CANDIDATE | FUENTES LEÍDAS |
| 3. Propuesta visual/colores | Opciones, selección, descarte, mapa por componente | Prompt compilado #7 propone combinación; no documenta todas las asignaciones | **ETAPA EN ANÁLISIS** |
| 4. QA previo del handoff | Verificar colores y usos por componente, distinguir CANDIDATE | No hay recibo de QA cromático independiente para la prueba reciente | SIN EVIDENCIA |
| 5. Envío al generador | Mostrar prompt literal, adjuntos, hash y evidencia de envío antes de generar | No se conservó prueba de que el prompt compilado de #7 fuera el payload literal de image_gen | NO VERIFICADO |
| 6. Imagen Native | Capturar imagen original y recibo del intento | Archivo generado en conversación | PRESENTE |
| 7. Composición oficial | Insertar logo por archivo aprobado y verificar resultado | Logo oficial compuesto posteriormente; SHA fuente coincide | PARCIAL |
| 8. QA resultado | Cotejar tokens, textos, disposición y restricciones con imagen real | CTA de color distinto; copy de Plus/Beneficios difiere de compilado | HALLAZGOS |
| 9. Cierre SQL | PR → PASE → Merge Train → readback; RUN y recibos | #7 PLANIFICADO, #9 BORRADOR, ambos sin RUN | NO TERMINADO |

## 2. Colores — trazabilidad de la propuesta

### 2.1 Origen exacto en Supabase

Contexto: `SALY_HOME_V015_CONTEXT_20261123`, id **3**, estado `SEALED`; pedido original #7 e ítem #10; el refinamiento #9 / ítem #13 usa el mismo contexto. Consulta de `creative_context_tokens` vinculada a `identity_versions`:

| Código de token | HEX de origen | Estado real | Rol |
|---|---|---|---|
| `color.action.primary.bg` | `#008200` | **APPROVED** | OFFICIAL, CTA de texto blanco |
| `color.brand.primary` | `#00C853` | **APPROVED** | OFFICIAL, marca; NO sustituir el fondo del CTA |
| `candidate.saly_ds_v1.color.ink.navy.900` | `#081631` | CANDIDATE | EXISTING, texto |
| `candidate.saly_ds_v1.color.surface.white` | `#FFFFFF` | CANDIDATE | EXISTING, superficie |
| `candidate.saly_ds_v1.color.surface.mint` | `#EAF9EE` | CANDIDATE | EXISTING, menta |
| `candidate.saly_ds_v1.color.surface.reward` | `#FFF9E9` | CANDIDATE | EXISTING, crema |
| `candidate.saly_home_v3.color.surface.benefits` | `#F4E7FD` | CANDIDATE | HOME, lavanda |

**Observación C-01:** `SEALED` significa que el conjunto está congelado; **no significa que sus cinco tokens candidatos estén aprobados**. `art_direction_preflight_v1.py` acepta fuentes con estado `APPROVED` o `CANDIDATE` como insumos estructurales, y declara que **no autentica su autoridad** (líneas 55–65). Debe haber decisión explícita de uso en QA.

### 2.2 ¿Cómo los planteó el proceso?

La propuesta **almacenada** en `saly.creative_orders.scope_json.compiled_prompt` del pedido #7 contiene esta instrucción textual:

> Fintech sobria, verde #008200 solo para CTA y menta #EAF9EE, crema #FFF9E9, lavanda #F4E7FD como acentos suaves de categorías.

También indica fondo blanco y superficies suaves.

**Qué sí propuso:** usar el verde oficial `#008200` para CTA y los tres candidatos como acentos.  
**Qué no está sustentado:** una comparación visible de alternativas cromáticas, razones de selección/descarte, asignación completa `componente → token → valor → aprobación` ni un QA independiente específico de la paleta.

**Separación obligatoria:** el prompt compilado de Supabase es fuente de *propuesta*. No consta un SHA de **envío real** que demuestre que ese mismo texto llegó al generador. En la invocación de imagen mostrada en el chat se usaron referencias generales a «green accents» y «soft pastel cards», no un mapeo de colores sellado.

### 2.3 ¿Qué se ve en la imagen y cómo contrasta con la propuesta?

Imagen de prueba con logo compuesto: `SALY_HOME_prueba_logo_oficial_20261123.png`, **1024×1536**, SHA-256 local `099ceff11450f1a3aa78df8ddfbf98473395e14e687185b0918b73877d7ccc42`. Muestras indicativas de píxel del CTA:

| Punto (x,y) | Color leído del PNG | Color exigido en prompt compilado |
|---|---|---|
| (280,550) | `#01904D` | `#008200` |
| (512,550) | `#049850` | `#008200` |
| (730,550) | `#02904D` | `#008200` |

**Observación C-02:** salió un verde con variación tonal/gradiente, **no el token plano #008200**. La muestra de píxeles no reemplaza el QA cromático completo, pero acredita una diferencia visible de cumplimiento.

**Observación C-03:** los tres tonos pastel aparecen como decisión estética sin evidencia de asignación exacta ni aprobación. Eso no autoriza promover `CANDIDATE` a `APPROVED`.

### 2.4 Diagnóstico de la etapa de colores

| Punto | Evidencia | Evaluación |
|---|---|---|
| Lectura desde fuente | Siete versiones exactas y roles, Supabase | VERIFICADO |
| Distinción APPROVED / CANDIDATE | La fuente los distingue | VERIFICADO EN DATOS |
| Propuesta elegida | Extracto de `compiled_prompt` | DOCUMENTADA |
| Mapa componente/color | No se acreditó para el envío reciente | PENDIENTE |
| Handoff enviado idéntico a propuesta | No existe registro de transmisión literal | NO VERIFICADO |
| Imagen conforme al CTA | Muestras de tres píxeles difieren | DIFERENCIA DETECTADA |
| Aprobación de la paleta final | No se ha solicitado ni recibido | NO APROBADA |

**Causa plausible, todavía NO verificada:** el paso de propuesta a generación debilitó la restricción de color al usar una descripción general y no entregar al generador una tabla de tokens y destinos bloqueados. Requiere reconstruir el handoff exacto y cotejarlo antes de afirmarlo como causa raíz.

### 2.5 Preguntas de control para la revisión conjunta
1. ¿El proceso elige la paleta desde fuentes realmente aprobadas o mezcla candidatos sin alertar?
2. ¿Qué colores son LOCK, cuáles GUIDED y cuáles FREE, por componente?
3. ¿Comparó alternativas y justificó la que seleccionó?
4. ¿Qué texto exacto y qué adjuntos mandó efectivamente a Native?
5. ¿La composición debe aplicar el CTA oficial después de generar, sin delegarlo a interpretación gráfica?
6. ¿Dónde se genera el QA cromático independiente y se archiva su evidencia?

**Acción siguiente (no ejecutada):** revisar el **paso 3**, propuesta visual/selección de alternativas y sus mapeos, usando los valores de este registro; después el handoff y la imagen. No corregir colores ni generar nuevamente antes de esa revisión.

## 3. Otras diferencias anotadas, no analizadas todavía
- Saly Plus en imagen: «Accede a beneficios exclusivos.»; el prompt compilado #7 especifica la idea «hasta 3 días antes y sorteos para ganar efectivo».
- Beneficios en imagen: «Descuentos y promociones pensadas para ti.»; el prompt compilado #7 indica «Descubre más.»
- Saly Rewards requiere cotejar la fuente de copy vigente; la prueba visible y el prompt histórico no comparten el mismo texto. No resolver ese conflicto por memoria ni inventando versión.
- Logo oficial: `saly.brand_assets.id=9`, `logo.primary.transparent`, `APPROVED v1`, Drive ID `1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78`, SHA fuente `5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995`. Fue compuesto **después**, no suministrado como PNG al generador en su invocación original.

## 4. Consultas reproducibles (solo lectura)

```sql
SELECT e.code, v.value_json->>'value' AS color, v.approval_status, ct.role, v.id AS version_id
FROM saly.creative_context_tokens ct
JOIN saly.identity_versions v ON v.id = ct.identity_version_id
JOIN saly.identity_elements e ON e.id = v.element_id
WHERE ct.context_set_id = 3 ORDER BY ct.role, e.code;

SELECT id, code, status, scope_json->>'compiled_prompt' AS proposed_prompt,
       scope_json->'intake_semantic_qa'->>'verdict' AS intake_verdict
FROM saly.creative_orders WHERE id IN (7,9);
```

## 5. Regla de seguimiento
Actualizar **una etapa por lote** con `fecha, fuente, propuesta, decisión, entrega real, diferencias, evidencia, estado`. No presentar propuestas como realizadas. No modificar el origen de colores, los pedidos, el estado de RUN ni el skill oficial para “corregir” la prueba. Toda eventual actualización operativa de Supabase seguirá la ruta gobernada PR → PASE → Merge Train → readback.
