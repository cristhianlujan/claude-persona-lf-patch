# SALY — catálogo visual versionado, lote M1

**Estado actual:** M1 MERGED / aplicado en Supabase; ninguna pantalla ni estándar activo por su sola existencia.
**Fuente de alcance:** contrato candidato \`SALY_VISUAL_STORAGE_SELECTOR_V0_1.md\`, PR #4237.

## Evidencia Drive — 2026-11-20 (primera lectura, reemplazada por corrección)

> **CORRECCIÓN VERIFICADA (2026-11-20):** la búsqueda inicial por palabras/filtro devolvió falsamente 0 archivos. `Google_Drive.list_folder` sobre las carpetas existentes confirmó **39 PNG en Pantallas_Aprobadas**, **7 PNG en Pantallas_Candidatas**, y **8 logos PNG + comparativa + acta** en Logos_Aprobados_v1.0. Los PNG se pueden descargar directamente. Se verificaron los bytes, dimensiones y SHA-256 independiente de seis originales; el detalle está en `SALY_SCREEN_SOURCE_FIRST_SIX_20261120.json`. Los 39 PNG incluyen láminas de presentación, por lo que no se clasifican automáticamente todos como `SCREEN`. Esta corrección reemplaza las conclusiones de inaccesibilidad de la lectura inicial, que se conservan abajo solo como evidencia histórica del error. El catálogo M1 ya está desplegado (PR #4438 MERGED), aunque sin estándar activo.



El árbol verificado es:

\`\`\`text
Saly - Planeamiento  [1YdTGWmdChtAyx31aQyEZ8Jd2E4so5mGD]
  ├─ 01_Diseño_UI  [1ZflQU9Vwdd6Yq5AbIDnSyufYirPBxl0q]
  │    ├─ Pantallas_Aprobadas  [1qhQwIhuJJ-EvKFRDxEVf-R265_gGh-65] → 39 PNG (lectura directa corregida)
  │    └─ Pantallas_Candidatas [1-jw_2gf8TyXdLYM-4G6-GqgUv3yiyj-R] → 7 PNG (lectura directa corregida)
  └─ 02_Identidad_Marca
       └─ Logos_Aprobados_v1.0 → 8 PNG + comparativa + acta
\`\`\`

La primera búsqueda `search` no devolvió los PNG con nombre exacto. Esto **fue un falso negativo**: la lectura directa de la carpeta reveló, entre otros, `SALY_SOPORTE_AI_v1.1_INICIO_PROACTIVO_APROBADA.png` y `SALY_SEGUIMIENTO_MINIMAL_v1.5.png`. Los originales son accesibles y descargables; seis fueron comprobados byte a byte.

Hay presentaciones SALY con láminas aprobadas. Una lámina **no sustituye** la pantalla PNG fuente para \`PRESERVE\` sin extraer, comparar y obtener aprobación explícita del screenshot. No registrar estos slides como \`SCREEN APPROVED\`.

## Baseline real Supabase

- \`saly.proyecto\`: proyecto \`SALY-001\` activo.
- \`saly.identity_elements\`: 48; \`saly.identity_versions\`: 48.
- \`saly.v_identity_current\`: 2 tokens oficiales, IDs 7 y 8.
- \`saly.brand_assets\`: 8 logos aprobados por acta. Sus metadatos indican
  \`sha256_independent_byte_check=false\`; no afirmar lectura binaria completa.
- \`overall_design.app_screens\`: 26; \`overall_design.mockup_assets\`: 19;
  \`overall_design.screen_visual_specs\`: 15. **No reutilizar** por defecto
  estos objetos de otro dominio como fuentes de SALY.
- El namespace \`visual\` no existía en esta consulta. \`pgcrypto\` y
  \`btree_gist\` existen en \`extensions\`.

## Entregable M1 — 5 tablas inicialmente VACÍAS

| Tabla | Alcance | Invariante |
|---|---|---|
| \`visual.standards\` | Líneas \`BRAND / APP_SCREEN / APP_MOCKUP\` | Solo código de marca SALY, aún 0 filas |
| \`visual.standard_versions\` | Versiones/JSON snapshot/hash | Mismo estándar, manifest inmutable, estados gobernados |
| \`visual.standard_activations\` | Binding por canal, audiencia, dispositivo, target y tiempo | No solapamiento GiST; versión debe estar APPROVED |
| \`visual.source_assets\` | Referencias de screenshot/marco/fondo | APPROVED exige SHA independiente y acta; 0 fuentes |
| \`visual.generation_receipts\` | Recibos de futuras generaciones | Append-only; nunca se generan aquí |

**Límite importante:** esta primera migración implementa SALY exclusivamente con \`brand_code='SALY'\` y NO habilita LF/Overall. La autoridad genérica multi-marca requiere otra migración y su revisión.

**Seguridad:** RLS + FORCE en 5 tablas, \`anon/authenticated\` sin uso de schema/tablas, \`service_role\` solo SELECT; sin RPC ni grants de escritura. Trigger de versionamiento, activaciones y append-only. Si falta evidencia de pantallas, NO se activa nada.

**Esta migración crea solo contenedores vacíos, no un estándar aprobado.**
No cambia los 2 tokens ni los 8 logos existentes, ni cambia la ejecución del inventario visual.

## Lote M2 pendiente / bloqueo funcional

1. Localizar archivos fuente **exactos** de pantallas aprobadas (PNG / file_id, versión, acta).
2. Leer bytes reales, calcular SHA-256 independiente, verificar dimensiones y preservación visual.
3. Crear \`source_assets\` candidate con evidencia, luego registrar versión aprobada mediante ruta de escritura gobernada que todavía NO existe.
4. Resolver tokens mínimos, marco/tamaño/fondo antes de crear \`APP_SCREEN\` y \`APP_MOCKUP\` como estándares versionados.
5. Diseñar y probar \`visual.resolve_standard_v1\`; NO hay selector de estándares en M1.
6. Revalidar vía PG17 las pruebas SQL \`supabase/tests/saly_visual_catalog_m1_rollback.sql\`, con ROLLBACK y readback 0 filas.

**Cierre M1:** CI PASE, Merge Train (si se autoriza), SELECT de cinco tablas,
RLS/grants, 0 rows, 0 activaciones, 0 fuentes SCREEN, sin migraciones de tokens.
Una prueba estática o una captura de tabla no acredita generación visual.

## Semáforo

- Inventario tokens/logos: VERIFICADO en lote anterior.
- Pantallas originales en Drive: **39 PNG localizados; 6 SCREEN con SHA independiente verificado**. Aprobación individual para insertar como APPROVED: todavía requiere evidencia por versión.
- Catálogo SQL: **MERGED, aplicado, 5 tablas y RLS verificados**.
- Estándar activo/render oficial: **NO HABILITADO**.
