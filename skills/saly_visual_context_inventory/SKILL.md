# SALY_VISUAL_CONTEXT_INVENTORY — lectura de insumos visuales v0.1

**Estado:** CANDIDATO / READ_ONLY / NO HABILITADO / NO REGISTRADO EN RUNTIME  
**Owner propuesto:** `PERFIL-UI-ARCHITECT` para `SALY/PRODUCTO`.  
**Alcance:** primer paso real de la fábrica de pantallas: leer fuentes aprobadas y señalar huecos. No genera imagen, pantalla, fondo ni mockup.

## Entrada requerida

- `business_code=SALY` derivado de un handoff autenticado del Router.
- `project_code=SALY-001` asociado al negocio, nunca tomado de un JSON de usuario como autoridad.
- `channel=PRODUCTO`, `output_type=APP_SCREEN|APP_MOCKUP`.
- `as_of` opcional fijado al contexto de ejecución, con timestamp.
- `execution_id` de un RUN auténtico del perfil UI cuando se habilite.

## Qué hace

1. Comprueba negocio/perfil/canal **desde el RUN padre oficial**, no desde el mensaje.
2. Resuelve el proyecto SALY y ejecuta solo el SELECT de `queries/saly_readiness.sql` con permisos gobernados.
3. Obtiene versiones efectivas de tokens desde `saly.v_identity_current`; registra `version_id`, valor, ámbito y vigencia.
4. Obtiene logos aprobados de `saly.brand_assets` sin copiar o modificar sus archivos. Una huella SHA registrada NO implica verificación independiente.
5. Comprueba si el catálogo `visual.standard_activations` existe. Si no existe, devuelve `STANDARD_CATALOG_NOT_IMPLEMENTED`; nunca inventa estándar o toma uno candidato como vigente.
6. Devuelve un inventario de fuente versionada, huecos de preparación, limitaciones y decisión `IMAGE_GENERATION_ALLOWED=false` hasta que haya estándar activo, marco/fondo/medidas aprobados y fuentes necesarias verificadas.

## Respuesta mínima

- `schema_version=SALY_VISUAL_CONTEXT_INVENTORY_V0_1`
- `status=SOURCE_INVENTORY_ONLY|READY_FOR_VISUAL_COMPILATION|BLOCKED`
- `project_code`, `business_code`, `as_of`
- `effective_tokens[]` con `element_code/version_id/value_json/channel/audience`
- `approved_assets[]` con `code/version/id/provider/file_ref/registered_sha/independent_sha_verified`
- `standard_catalog_exists`, `active_standard_version_id` o `null`
- `blocking_codes[]` y `image_generation_allowed`

## Límites y aceptación

- Sin hardcodear en el skill una paleta, tamaño de pantalla, modelo de teléfono o fondo.
- Los tokens candidatos `SALY_DS_V1` NO sustituyen los efectivos.
- Los logos aprobados no autorizan reutilizar fondos/pantallas sin readback de sus propios activos.
- No accede a tablas LF/Overall en la consulta SALY.
- No declara apto para generar porque exista un token, logo o documento de diseño.
- El invocador del perfil y sus ACL siguen siendo la única ruta válida para nuevos skills.
- Hasta implementar catálogo versionado y contrato de selector, el resultado esperado es `SOURCE_INVENTORY_ONLY`, no `READY_FOR_VISUAL_COMPILATION`.
- No reemplaza al piloto `SALY_APP_VISUAL_PROBE`: su recibo histórico permanece intacto.

**NO-GO:** no registrar este skill como `READY` ni habilitar al perfil hasta crear handler oficial y tests, asociar binding por negocio, definir el estándar visual efectivo e introducir una ejecución gobernada distinta al RUN histórico de saludo.
