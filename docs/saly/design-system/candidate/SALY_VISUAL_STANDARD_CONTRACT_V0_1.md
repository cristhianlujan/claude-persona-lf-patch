# SALY / Fábrica visual — contrato de estándares versionados v0.1

**Estado:** PROPUESTA TÉCNICA / CANDIDATO / NO OPERATIVO  
**Alcance aprobado:** formalizar un motor reutilizable de estándares visuales para APP Screens y APP Mockups con variaciones puntuales, rediseños radicales y rebranding; no rediseñar pantallas actuales ni activar tokens no aprobados.  
**Proyecto inicial:** SALY. **Diseño futuro:** multi-marca, con aislamiento y ámbito por empresa.  
**No implica:** DDL, migraciones, cambios en producción, nuevas reglas de negocio, aprobación de fuente visual o promoción de los 46 tokens candidatos.

## 1. Reutilizar la base verificada

- `saly.identity_elements` / `saly.identity_versions`: catálogo versionado de tokens, con valores vigentes y candidatos y selección por canal/audiencia.
- `saly.brand_assets`: ocho variantes de logo aprobadas, con referencias y vigencia.
- `saly.resolve_identity`: selector protegido y no expuesto a usuarios externos; no ampliar sus grants en este lote.
- Readback 2026-11-19: 48 elementos, 48 versiones, 8 assets; solo dos tokens efectivos `color.brand.primary=#00C853` y `color.action.primary.bg=#008200`.
- `SALY_DS_V1` (PR #3715) contiene 46 candidatos aislados: no convertirlos en vigentes por composición o herencia. La ruta gobernada de PR / Merge Train ya se usa para cualquier cambio de BD.

**Brecha:** no existe actualmente en `saly` un catálogo específico de paquetes `visual_standard` con versiones inmutables, selector por tipo de pieza, relaciones de herencia y recibos de generación.

## 2. Modelo lógico (no crear tablas todavía)

1. **Brand identity** (`BRAND`): logo, verdes oficiales, otros tokens aprobados, tono y referencias de marca. Cada release fija las versiones exactas de sus elementos; puede haber un cambio de marca independiente del diseño de las pantallas.
2. **Screen standard** (`APP_SCREEN`): viewport lógico, safe areas, tipografía, grid, componentes, reglas de legibilidad, estados, navegación y patrones. Hereda `BRAND` y sus dependencias versionadas.
3. **Mockup standard** (`APP_MOCKUP`): lienzo de salida, dispositivo/marco, fondo, escala, ángulo, posición, sombra, cantidad de pantallas, márgenes, rótulos y composición. Referencia un `APP_SCREEN` y `BRAND` por versión, pero **no** cambia su contenido aprobado.
4. **Generation receipt** (`GENERATION`): solicitud, marca, finalidad, público, referencias de pantallas y assets, versiones resueltas, snapshot de valores usados, paquete compacto de instrucciones, motor, modelo, parámetros disponibles, resultado, QA, autoría y estado.
5. **Binding de vigencia** (`ACTIVATION`): relación entre estándar/versión y contexto exacto `brand + channel + audience + output_type + device_class`, ventana de tiempo y evidencia de aprobación.

**Separación importante:** una pantalla de producto, su presentación en un teléfono y la identidad corporativa son tres objetos independientes, ligados por versiones.

## 3. Estados, versiones y temporalidad

`DRAFT → CANDIDATE → APPROVED → ACTIVE → SUPERSEDED/REVOKED`

- **DRAFT/CANDIDATE:** exploración habilitada solo mediante selección explícita. Nunca seleccionable por defecto como identidad/producto oficial.
- **APPROVED:** versión aprobada, sin activación automática; puede reservarse para campañas futuras.
- **ACTIVE:** vigente únicamente en un contexto temporal definido. La selección automática no puede devolver más de un estándar por contexto exacto y fecha.
- **SUPERSEDED:** dejó de ser vigente pero sigue referenciable y reproducible como insumo histórico.
- **REVOKED:** no elegible para producción; una revocación bloquea nuevos usos según política y no borra sus recibos anteriores.
- Las versiones publicadas son **inmutables** (identificador + versión + digest de manifest). Un cambio genera otra versión; no se sobrescribe el contenido de una anterior.
- **Cambio puntual:** nueva revisión de estándar (p. ej. `STD-001 v1.1`), copiando todos los valores no modificados por referencia inmutable.
- **Cambio radical:** nueva línea/estándar (p. ej. `STD-002 v1.0`) o nueva major, sin reemplazar a `STD-001` hasta que exista activación explícita.
- **Rebranding:** nueva versión de `BRAND`, independiente de `APP_SCREEN` y `APP_MOCKUP`; la compatibilidad se valida, no se presupone. Nunca sustituir la identidad histórica en recibos existentes.
- Vigencia `[valid_from,valid_to)`, hora UTC; ventanas no solapadas en un contexto exacto salvo exploración explícita que nunca sea selector predeterminado. Promoción y desactivación atómicas.
- Reversión: restaurar una versión previamente aprobada mediante nuevo binding gobernado y readback, sin editar ni borrar historial.

## 4. Contrato del selector (propuesta)

**Entrada obligatoria:** `brand_code`, `output_type`, `channel`, `audience`, `device_class`, `as_of`, `mode` (`OFFICIAL` / `EXPLORE`), y `standard_id/version` si la solicitud es explícita. En `OFFICIAL` la selección debe ser determinista, `ACTIVE` y autorizada.

**Precedencia de herencia:**
1. Paquete de marca aprobado, fijado por ID de versión.
2. Paquete APP_SCREEN fijado por versión.
3. Paquete APP_MOCKUP fijado por versión, si aplica.
4. Overrides por ámbito (canal/audiencia/dispositivo) solo si un contrato aprobado declara la propiedad sobreescribible.
5. Datos de la tarea (textos, contenido y pantalla fuente), **sin** permitir cambiar silenciosamente los tokens bloqueados.

**Excepciones:** error si falta token requerido, referencia ambigua, conflicto de overrides, dependencia no aprobada, ciclo de herencia, dimensión incompatible, cross-brand sin autorización o fuente de pantalla no verificada.

**Nunca usar** `candidate.saly_ds_v1.*` como fallback implícito a tokens oficiales. Puede pasarse explícitamente en `EXPLORE`, claramente etiquetado como no oficial.

## 5. Contrato de generación

```text
Entrada (marca, modo, pantalla(s), objetivo)
  → resolver estándar + contexto + vigencia
  → fijar versiones y digests de dependencias
  → validar fuentes/estado aprobado o exploración
  → compilar instrucciones compactas + valores mínimos
  → APP_SCREEN o APP_MOCKUP
  → QA dimensiones, contraste, ortografía, fidelidad de fuente
  → recibo inmutable (fuentes, versiones, resultado, QA)
  → candidato / revisión / aprobado
```

- `PRESERVE`: presenta la imagen de una pantalla aprobada; no rediseñar UI ni editar importes, etiquetas o contenido. Si la renderización pierde fidelidad, marcar `QA_FAIL` y no presentarla como copia exacta.
- `EXTEND`: crea pantallas faltantes usando componentes, reglas de contenido y tokens aprobados; siempre `CANDIDATE` hasta aprobación visual.
- `EXPLORE`: permite estándar candidato expresamente seleccionado sin propagación a activos oficiales.
- `MOCKUP`: exige además `canvas_width`, `canvas_height`, `device_frame_ref`, `device_bounds`, `screen_bounds`, `background_ref`, `shadow_spec`, `placement_grid` y `output_format` en **la versión del estándar**, no hardcodeados en la skill.
- `APP_SCREEN`: exige `viewport_width`, `viewport_height`, `safe_area`, `scale_policy`, `spacing_policy`, `typography_bindings`, `component_refs`, `state_rules`, `navigation_spec` en el estándar.
- Para varias pantallas, una sola familia coherente de marcos/fondos/proporciones según versión; no mezclar versiones sin declarar comparación histórica.
- No se promete reproducción píxel a píxel de un generador de imágenes probabilístico. Se garantiza trazabilidad de entradas y estándares y se aplica QA al resultado. Si el formato/dimensión exacta no puede verificarse, no declarar conformidad.

## 6. Ejemplo de manifest (CANDIDATO / ningún tamaño nuevo aprobado)

```json
{
  "standard_id": "SALY_APP_MOCKUP_STD_001",
  "version": "0.1-candidate",
  "status": "CANDIDATE",
  "type": "APP_MOCKUP",
  "brand": "SALY",
  "inherits": {
    "brand_identity": "<approved-brand-version-id>",
    "app_screen_standard": "<screen-standard-version-id>"
  },
  "canvas": {"width_px": null, "height_px": null},
  "phone": {"asset_ref": null, "frame_color_token": null, "bounds": null},
  "background": {"asset_ref": null, "style_token": null},
  "composition": {"variant": "TWO_SCREENS", "grid": null},
  "text_styles": {"title": null, "subtitle": null},
  "activation": null,
  "source_refs": [],
  "source_digest": null
}
```

Los `null` son **faltantes explícitos por definir mediante referencia aprobada**, no valores de fabricación. Antes de generar un mockup de estándar oficial deberán existir dimensiones, fondo y marco reales. Una prueba exploratoria puede usar un estándar candidato, etiquetado.

## 7. Cambios y propagación

| Acción | Crea versión | Impacto automático sobre imágenes anteriores | Requiere |
|---|---|---|---|
| Retocar un botón | Sí, APP_SCREEN | Ninguno | QA de componentes afectados |
| Cambiar fondo/marco del móvil | Sí, APP_MOCKUP | Ninguno | QA de 1/2/3 pantallas |
| Cambiar tipografía/layout completo | Nueva major o estándar | Ninguno | revisión UX/UI de pantallas |
| Rebranding | Sí, BRAND | Ninguno | aprobación expresa de identidad, compatibilidad |
| Activar nuevo estándar | Nuevo ACTIVATION | Solo nuevas solicitudes oficiales en ámbito | autoridad, ventana y readback |
| Regenerar imagen antigua | Nuevo recibo | Mantiene original | petición explícita y source refs |

## 8. Pruebas de aceptación antes de implementar

| ID | Prueba | Esperado |
|---|---|---|
| VS-01 | Dos estándares candidatos para APP | No alteran selección oficial |
| VS-02 | Un estándar ACTIVE en contexto exacto | Selector determinista |
| VS-03 | Dos ACTIVE solapados mismo contexto | BLOQUEO |
| VS-04 | Candidato seleccionado en modo OFFICIAL | BLOQUEO |
| VS-05 | Versión histórica seleccionada explícitamente | Reproducción de contexto, sin activar |
| VS-06 | Cambio puntual de fondo del mockup | Pantallas y brand pins intactos |
| VS-07 | Cambio radical de UI | Nueva línea versionada, sin mutación histórica |
| VS-08 | Rebranding | Brand pin nuevo y compatibilidad validada |
| VS-09 | Token faltante/cíclico o no aprobado | BLOQUEO en modo oficial |
| VS-10 | Generar 1, 2 y 3 pantallas | Frame, canvas y escala homogéneos por versión |
| VS-11 | APP_SCREEN preserve sobre aprobado | QA contra imagen fuente, sin falsa exactitud |
| VS-12 | BRAND SALY y BRAND LF | Aislamiento, cero herencia accidental |
| VS-13 | Invalidar estándar | Selector impide uso nuevo según política, conserva recibos |
| VS-14 | Cambiar estándar con trabajos en curso | Resultado usa snapshot fijado al comienzo |
| VS-15 | Lectura/ejecución sin permisos | BLOQUEO, sin grants implícitos |
| VS-16 | Nuevo resultado | Recibo con versión, SHA, fuente y estado QA |

## 9. Implementación propuesta — lotes separados y gobernados

- **Lote 0 (este documento):** formalizar contrato candidato. Sin SQL, sin activación, sin cambio de pantallas o assets.
- **Lote 1:** diseño de catálogo persistente multi-marca y revisión de ownership/RLS, índices de no-solapamiento, migraciones; preparar PR individual para Merge Train. No duplicar `saly.identity_elements/versions/brand_assets`.
- **Lote 2:** crear dos estándares **candidatos** (`APP_SCREEN` / `APP_MOCKUP`) y sus referencias con aprobación de dimensiones y fondos; aplicar verificación de selector.
- **Lote 3:** construir skill modular y compilador compacto que lea el estándar por referencia, con límites de contexto y fuentes/prompt minimizados.
- **Lote 4:** prueba con dos pantallas ancla aprobadas de SALY, una pantalla faltante candidata y mockup de 1/2/3 pantallas. Inspección visual, QA, recibos y cierre.

**Punto de control:** sin artefactos fuente exactos y dimensiones aprobadas, las variantes siguen candidatas. La activación o cambio de marca requiere aprobación específica; el simple hecho de explorar no promueve estado.
