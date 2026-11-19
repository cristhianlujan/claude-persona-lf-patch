# SALY / Fábrica visual — almacenamiento y selector v0.1

**Estado:** PROPUESTA TÉCNICA / DRAFT / NO IMPLEMENTADO  
**Lote:** 1 de contrato `SALY_VISUAL_STANDARD_CONTRACT_V0_1.md`; persistencia y selección solamente.  
**Alcance autorizado:** diseñar almacenamiento, herencia, versionamiento, vigencia, selector, aislamiento y validación. **No** DDL aplicado, migración, activación, cambio de tokens/activos/pantallas ni habilitación de Router/adapter.

## 0. Baseline verificada el 2026-11-19

- En DB existen schemas `saly`, `lf_design` y `overall_design`; **no** existen schemas `visual` ni `creative` (consulta de `pg_namespace`).
- SALY: `saly.identity_elements` 48 filas, `saly.identity_versions` 48, `saly.brand_assets` 8. Exactamente **2 versiones efectivas** verificadas (verde de marca `#00C853` y CTA `#008200`); las otras 46 siguen candidatas.
- `saly.identity_versions` ya controla aprobaciones, contextos canal/audiencia y no solapamiento temporal. `saly.brand_assets` ya registra los 8 logos oficiales. **No duplicar** estas fuentes.
- `saly.resolve_identity` es `SECURITY INVOKER`, protegido, sin grants de cliente para uso externo automático. No ampliar grants por este diseño.
- Existe `adapters/project_brand_mockup_render_lf` con entrada Router-bound, gobernanza, prevención de contaminación entre proyectos, validación y QA; estado real en su `manifest.yaml`: `CANDIDATO / READ_ONLY / NO_HABILITADO`. Su `output_target` actual admite `PDF/PPTX/HTML/BRANDBOOK`, **no IMAGE** y no se modificará ni declarará habilitado en este lote.
- Fuentes de diseño: `docs/saly/design-system/candidate/SALY_VISUAL_STANDARD_CONTRACT_V0_1.md` (PR #4237), `docs/saly/design-system/candidate/ESPECIFICACION_SALY_DS_V1.md` (PR #3715, candidato), `supabase/migrations/20261119012046_lf_saly_creative_identity_v02.sql`, adapter `ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF` del repo.

**Decisión:** implementar en etapa futura un registro genérico solo para **paquetes de estándar y recibos**. No construir otra base de tokens ni otra normalización de marca.

## 1. Modelo físico propuesto, NO existente

Schema lógico provisional: `visual` (**nombre candidato**, exige revisión del namespace, ownership, permisos y schema exposure antes de cualquier migración).

| Tabla propuesta | Clave y columnas mínimas | Reglas y responsabilidad |
|---|---|---|
| `visual.standards` | `id`, `brand_code`, `standard_code`, `kind` (`BRAND` / `APP_SCREEN` / `APP_MOCKUP`), `created_at` | Una **línea** de estándar por marca y tipo; único `(brand_code,standard_code)`. No guarda HEX ni pantallas en duro |
| `visual.standard_versions` | `id`, `standard_id`, `version`, `parent_version_id`, `change_kind`, `manifest_json`, `manifest_sha256`, `state`, `approval_ref`, `created_at` | Snapshot de configuración e IDs exactos de dependencias; único `(standard_id,version)`; `manifest_json` inmutable tras publicar; transiciones autorizadas/auditadas |
| `visual.standard_activations` | `id`, `brand_code`, `kind`, `channel_code`, `audience_code`, `device_class`, `output_target`, `standard_version_id`, `valid_from`, `valid_to`, `approval_ref` | Binding de versión vigente por **contexto exacto**, con ventana `[from,to)`; no dos asignaciones activas solapadas para misma tupla aunque sean estándares distintos; historial conservado |
| `visual.source_assets` | `id`, `brand_code`, `source_kind` (`SCREEN`, `FRAME`, `BACKGROUND`, etc.), `provider`, `file_ref`, `sha256`, `approval_status`, `approval_ref`, `metadata` | Inventario versionado de fuentes de pantalla, marcos y fondos. Para logos SALY **referenciar** `saly.brand_assets`, no recopiarlos; no tratar imagen con nombre «APROBADA» como evidencia suficiente |
| `visual.generation_receipts` | `id`, `request_ref`, `brand_code`, `mode`, `resolved_standard_version_ids`, `dependency_digest`, `input_source_refs`, `input_digest`, `engine_ref`, `output_refs`, `output_digest`, `qa_status`, `decision_ref`, `created_at` | Recibo inmutable final (incluye bloqueos/errores), versión usada, fuentes, motor y QA; resultados anteriores nunca se reescriben al cambiar estándar |

### Restricciones de integridad exigidas

1. **FK internas reales:** `standard_versions.standard_id → standards.id`, `standard_activations.standard_version_id → standard_versions.id`, parent existente y en **la misma marca**. `standard_versions` mantiene digest SHA-256 del manifest canónico (serialización definida).
2. **Ámbito de marca:** jamás asumir que `brand_code` recibido por usuario basta. Resolver contra registro de proyectos autorizado y origen concreto (p. ej. `saly.proyecto` + adaptador SALY); no crear FKs dinámicas a schemas variables. Si no existe fuente corporativa para otra marca, **bloquear** habilitación multi-marca hasta registrar autoridad. Este punto debe resolverse antes del DDL.
3. **No solapamiento:** índice GiST de exclusión sobre `brand_code,kind,channel_code,audience_code,device_class,output_target,tstzrange(valid_from,valid_to,'[)')`. El índice incluye **contexto y tipo**, NO `standard_version_id`, para bloquear dos estándares distintos que compitan en el mismo ámbito.
4. **Cardinalidad:** exactamente 1 activación válida en un contexto oficial dado. Si hay 0, responder `BLOCK_NO_ACTIVE_STANDARD`; si hay más de 1 por mala migración/conflicto, `BLOCK_AMBIGUOUS_ACTIVE_STANDARD`.
5. **Sin fallback implícito:** primera versión del selector usa coincidencia exacta de canal/audiencia/dispositivo/salida; `GLOBAL/ALL` puede usarse solo como binding explícitamente registrado para ese ámbito y con precedencia aprobada posteriormente. No inferir wildcard por conveniencia.
6. **Referencias y SHA:** `source_assets` requiere proveedor, identificador real y hash comprobado para estado `APPROVED`. Un archivo ya aprobado en Drive puede seguir **pendiente de SHA** hasta lectura real; no inventar el digest.
7. **Inmutabilidad:** manifest + lista de pines + SHA no se modifican después de publicar. Cambiar fondo, dimensión, marca o teléfono crea nueva `standard_version` y una nueva `standard_activation`; cerrar el `valid_to` anterior no elimina trazabilidad.
8. **RLS/privilegios:** tabla RLS activa, sin grants públicos `anon/authenticated`, selector invoker/servicio gobernado, sin `SECURITY DEFINER` abierto. Mutaciones únicamente operación/PR/Merge Train autorizado cuando se implemente. Prohibido confiar en `actor_id` o `approval_ref` aportados por usuario como autoridad.
9. **Publicación:** transición `DRAFT → CANDIDATE → APPROVED` tiene evidencia y rol autorizado; `ACTIVE` se **deriva de binding vigente**, no de renombrar un archivo ni de que una versión esté aprobada.
10. **Revocación:** un registro de revocación impide nuevos usos oficiales; version y recibos históricos se conservan. La política de explotación de resultados publicados se define por separado.

### No ampliar alcance

No implementar en este lote un CMS, un sistema de autorización paralelo, tabla de valores de tokens duplicada, motor de render ni catálogo de negocios alternativo. `visual` es **propuesta de namespace**, no un schema aplicado.

## 2. Manifest de versión propuesto

```json
{
  "standard_code": "SALY_MOCKUP_STD_001",
  "standard_version": "0.1-candidate",
  "kind": "APP_MOCKUP",
  "brand_code": "SALY",
  "dependencies": {
    "brand_release_version_id": null,
    "screen_standard_version_id": null,
    "required_token_version_refs": [
      "saly.identity_versions:<exact_numeric_id>"
    ],
    "source_assets": [
      {"source_ref": null, "sha256": null}
    ]
  },
  "spec": {
    "canvas_px": {"width": null, "height": null},
    "device_frame_ref": null,
    "phone_bounds": null,
    "screen_bounds": null,
    "background_ref": null,
    "spacing_ref": null,
    "typography_refs": [],
    "variants": ["ONE_SCREEN", "TWO_SCREENS", "THREE_SCREENS"]
  },
  "state": "CANDIDATE",
  "effective_from": null,
  "effective_to": null
}
```

**Importante:** los `null` representan *no verificado/no fijado*. Estos campos obligatorios tienen que cerrarse antes de activar un estándar. El `<exact_numeric_id>` es solo un placeholder de esquema, no un ID conocido; debe reemplazarse por refs reales de readback.

## 3. Contrato del selector determinista (especificación; no RPC ejecutada)

Nombre lógico candidato: `visual.resolve_standard_v1`.

**Entrada:**
- `brand_code` (resuelto/atestiguado, no autoafirmado);
- `kind` = `BRAND`, `APP_SCREEN`, `APP_MOCKUP`;
- `channel_code`, `audience_code`, `device_class`, `output_target`;
- `as_of` (timestamptz);
- `mode` = `OFFICIAL` / `EXPLORE`;
- `requested_standard_version_id` **opcional** (obligatorio en EXPLORE);
- recibo de caller autenticado/autoridad de servicio fuera de los datos suministrados por usuario.

**Salida:**
`decision` (`BOUND` o `BLOCK_*`), `standard_version_id`, `manifest_sha256`, `resolved_dependency_pins`, `source_asset_refs`, `brand_scope`, `resolution_trace`, `valid_at`, `blocking_reasons`. Devuelve **solo datos de binding**, no genera imágenes.

**Algoritmo:**

```text
1. Validar credencial de invocación y negocio/proyecto autorizado.
2. Validar tupla exacta de ámbito y modo.
3. OFFICIAL: buscar 1 activación vigente con mismo ámbito y [from,to).
   EXPLORE: exigir requested_standard_version_id explícito y permiso para candidato.
4. Revalidar que revisión corresponde al brand/kind y no está revocada.
5. Cargar manifest INMUTABLE, verificar digest y referenciales.
6. Resolver pines BRAND, APP_SCREEN y APP_MOCKUP en DAG.
   - No elegir silenciosamente «latest» para dependencias.
   - Detectar ciclos y cambios de marca.
7. Resolver tokens oficiales desde autoridad existente (para SALY,
   saly.identity_versions aprobadas, de forma gobernada).
   - Los 46 candidate.saly_ds_v1.* NO entran en OFFICIAL.
   - En EXPLORE, etiquetar provisional e impedir publicación oficial.
8. Validar dimensiones/fondo/frame/componentes obligatorios y contexto de salida.
9. Emitir binding con lista exacta de source refs + version IDs + SHA.
10. Bloquear si falta fuente, aprobación, dimensión, compatibilidad, acceso o unicidad.
```

**Semántica de bloqueo mínima:** `BLOCK_UNAUTHORIZED_SCOPE`, `BLOCK_NO_ACTIVE_STANDARD`, `BLOCK_AMBIGUOUS_ACTIVE_STANDARD`, `BLOCK_UNAPPROVED_DEPENDENCY`, `BLOCK_DEPENDENCY_CYCLE`, `BLOCK_MISSING_REQUIRED_TOKEN`, `BLOCK_SOURCE_HASH_UNVERIFIED`, `BLOCK_OUTPUT_TARGET_UNSUPPORTED`, `BLOCK_CROSS_BRAND`, `BLOCK_SCHEMA_OR_GRANTS_UNVERIFIED`.

## 4. Interfaz con adapter existente

El adapter `ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF` **ya resuelve marca/tokens y aplica QA** pero no está habilitado ni recibe IMAGE en su `output_target` actual.

**No crear otro adapter equivalente.** Cuando sea autorizado:
- Proponer extensión explícita de `project_brand_mockup_binding` para `standard_version_id`, `manifest_sha256`, `mode`, `dependency_pins`, `source_asset_hashes` y `output_target=IMAGE`. Todo requiere versión de schema + validator + judge + evals, sin romper consumidores PDF/PPTX/HTML.
- La nueva RPC solo aporta el **selector de estándar**: adapter consume binding devuelto y no sustituye autoridad de UI/Product ni los recibos de Router/IG.
- Restricciones vigentes: `ROUTER_BOUND_ONLY`, `NO_HABILITADO`, input governance requerido, cápsula compacta <=1600 caracteres, una sola ejecución LLM worker; **no activar** nada por editar un documento.
- Si el flujo nuevo requiere generación directa nativa sin Router, no saltarse el contrato: definir primero el entrypoint/autoridad y probarlo. No habilitar un bypass de gobernanza.

## 5. Ejemplo de cambio y conservación de versión (ilustrativo, no aplicado)

```text
SALY / BRAND / v1.0 [APPROVED]
   ├─ color.brand.primary -> saly.identity_versions:<id>#00C853
   └─ color.action.primary.bg -> saly.identity_versions:<id>#008200

APP_SCREEN_STD_001 / v1.0 [CANDIDATE]
   └─ BRAND v1.0 + layout/typography/safe area por refs

APP_MOCKUP_STD_001 / v1.0 [CANDIDATE]
   └─ SCREEN v1.0 + dispositivo A + fondo A + lienzo A

Cambio puntual de marco:
   APP_MOCKUP_STD_001 v1.1 [CANDIDATE] -> pantalla original intacta

Cambio radical / rebranding:
   BRAND v2.0 + APP_SCREEN_STD_002 v1.0 + APP_MOCKUP_STD_002 v1.0
   -> línea paralela; no afecta imágenes generadas antes
```

No se debe interpretar `BRAND v1.0` como paquete existente hoy: solo hay dos valores oficiales registrados y ocho logos; falta paquetización formal, tamaños y otros tokens.

## 6. Matriz de pruebas exigidas para futura implementación

| Caso | Prueba | Evidencia obligatoria |
|---|---|---|
| P-01 | Registro de candidato APP_SCREEN + MOCKUP sin activación | No cambia selector oficial ni vista SALY |
| P-02 | Dos activaciones superpuestas mismo ámbito | DB rechaza por constraint, rollback real |
| P-03 | Mismo ámbito, distintas versiones en ventanas disjuntas | Selección correcta por `as_of` |
| P-04 | Activaciones de distintas marcas | Aislamiento, sin fuga LF/Overall |
| P-05 | OFFICIAL intenta candidato | Bloqueo |
| P-06 | EXPLORE pide versión explícita | Binding candidato visible, no oficial |
| P-07 | Falta token requerido/no hay SHA de pantalla | Bloqueo con causa exacta |
| P-08 | Dependencia cíclica/cross-brand | Bloqueo |
| P-09 | Cambio de marco sin cambio de pantalla | Nuevo manifest + pantalla antigua intacta |
| P-10 | Cambio de marca radical | Versiones nuevas, recibos anteriores inmutables |
| P-11 | APP_MOCKUP 1, 2, 3 pantallas | Medidas uniformes según manifest, QA visual |
| P-12 | Fuente de pantalla aprobada y otra solo candidata | Producción solo aprobada; EXPLORE marcada |
| P-13 | IMAGE requiere extensión de adapter | Bloqueo antes de habilitar salida PNG |
| P-14 | Revocación + resolución histórica | No nuevos usos; lecturas históricas por permiso |
| P-15 | Supabase read-only/anon intentan cambiar activación | DENY, sin grants nuevos |
| P-16 | Simular falla de promoción y rollback | 0 efectos, SELECT de baseline idéntico |

**Hoy los 16 escenarios están ESPECIFICADOS, NO ejecutados**. La futura migración requiere pruebas PostgreSQL reales con `BEGIN/ROLLBACK`, readback independiente, PASE y Merge Train; no basta con pruebas estáticas.

## 7. Control de implementación y dependencias

| Lote futuro | Entregable | Bloqueos |
|---|---|---|
| M1 | Diseño de DDL y seguridad `visual` con FKs, GiST, RLS, sin grants de clientes | Resolver marca/tenant authority y namespace |
| M2 | Una migración gobernada con 5 tablas (si diseño validado), `0` estándares ACTIVOS por defecto | PASE, PR exact-head, Merge Train, ledger y readback |
| M3 | Selector `resolve_standard_v1` con 16 casos de prueba | Servicio autorizado, sin bypass de Router |
| M4 | Dos estándares SALY en CANDIDATE con dimensiones/fondo/marco **verificados**, fuentes reales | Drive refs, SHA, coherencia visual y selección |
| M5 | Extensión versionada del adapter para IMAGE + ejecutor de prototipos | Eval, QA visual, integración y permisos |

**Pendiente crítico:** resolver procedencia/autoridad multi-marca y registrar materiales/fuentes exactos, antes de permitir publicación. No completar automáticamente ningún token o dimensión que no esté aprobado.

## 8. Evidencia y cierre de este lote de diseño

- Fuente verificada en GitHub: `saly/visual-standards-contract-v01-20261119`, PR #4237 (DRAFT).
- Código del adapter revisado (ADAPTER, manifest, schema, token resolution, screen mockup contract y casos).
- DB consultada solo con SELECT: 48/48, 8 assets, 2 efectivos; `visual` NO EXISTE.
- Este documento **no es** una migración ni una operación activa. Puede modificarse y revisarse sin cambiar datos de usuario.

**Criterio de cierre:** contrato de tablas, selector, seguridad, estados, límites y pruebas especificados con readback de archivo en PR DRAFT. La ejecución se evalúa en otro lote, sin llamar implementado a lo que sigue propuesto.
