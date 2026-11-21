# AI Sales 3.0 — perfiles funcionales estándar, políticas por negocio y adaptadores por fuente (V1)

**Decisión de alcance (21/11/2026):** NO crear/promover `PERFIL-RADAR-COMERCIAL-SALY` como perfil propio de un negocio. Reutilizar perfiles **por función**; resolver diferencias de LF/SALY por políticas, adaptadores y cápsulas compactas. Este contrato es CANDIDATO/READ_ONLY; no habilita un RUN ni modifica Router, IG, source of truth o permisos.

## Evidencia previa (Supabase y Git)
- `public.lf_router_business_catalog_v1`: `LF` y `SALY` con estado `ENABLED` en lectura del 21/11/2026.
- `public.lf_profile_selection_registry_v1` y `lf_activos`: **no** contienen un Radar comercial estándar ni Radar SALY nativo. Se prohíbe inventar un `profile_code` o usar el Product Director para suplantar Radar. La selección del especialista estándar deberá utilizar únicamente la registry vigente; la eventual alta de un rol funcional inexistente sería UNA creación transversal gobernada, no una por negocio.
- `public.v_lf_router_adapter_bindings` ya demuestra binding de adaptadores a perfiles; `ADAPTER_LF_SHELL_PROFILE` es patrón reutilizable de un adaptador transversal con varios perfiles, activado solo por Router. No crear otro Router ni una fábrica paralela.
- `docs/ai_sales/AI_SALES_3_0_SELECTION_TRANSVERSAL_V0_7_20261027.md` manda resolver `business_code > product > market > action > effective_policy_version` y distribuir la misma cápsula a Radar, Enrichment y SDR. Mantener `FIT`, `INTENT`, evidencia y permiso de contacto separados.
- `public.lf_global_config` contiene `SALY_DISCOVERY/PTE_POLICY_V1`; `public.lf_saly_discovery_pte_policy_v1()` es la política PTE **de SALY**, no de LF. El adaptador PTE existente `normalizePteCsv(text, policy)` es reutilizable con otra política, pero no está habilitado para LF automáticamente.

## Flujo sin duplicación
```text
Solicitud
  -> ACT-0001 Router + negocio descubierto y atestado (RCTX2/CONTEXT_TRANSPORT)
  -> selección nativa de perfil funcional común (no por marca)
  -> resolución de política vigente por negocio/producto/mercado/acción
  -> binding del adaptador técnico por FUENTE/INTEGRACIÓN y capacidad
  -> cápsula compacta de contexto, dentro de LA MISMA ejecución de perfil
  -> normalización, evidencia y juez transversal
  -> retorno al Router/perfil + persistencia SOLO mediante la operación autorizada
```

Tres extensiones que **no** son perfiles nuevos:
1. **Política de negocio versionada:** ICP, exclusiones, pesos, finalidad, fuentes permitidas, jurisdicción, umbrales, consentimiento y scope. Repositorio canónico: Supabase; no copiar políticas SALY en un perfil global.
2. **Adaptador de fuente/integración:** PTE CSV, SUNAT, Google Maps, etc.; normaliza formatos, registra procedencia, licencias, calidad y límites por proveedor. Un adaptador puede servir a varios negocios **solo si cada uno autoriza expresamente la fuente**.
3. **Adaptador de excepción empresarial (opcional):** únicamente cuando existe diferencia real de proceso o integración no expresable como política. Exigir evidencia y contrato propio; no crearlo por defecto.

## Contrato obligatorio
- **Entrada confiable:** identidad del `business_code` y recibo del Router obtenidos por la ruta actual, nunca por un campo libre del prompt. Revalidar que el negocio sigue `ENABLED` en `lf_router_business_catalog_v1`. El validador offline no autentica el recibo.
- **Binding:** rol funcional estándar seleccionado desde `lf_profile_selection_registry_v1`, `policy_ref` y versión/hashes actuales, `adapter_id`, `source_id`, derechos de fuente y `operation_code`. Si falta la selección nativa, solo se genera candidato, sin RUN ni ejecución.
- **Aislamiento:** negar uso de política SALY con `business_code=LF`, fuentes no autorizadas y roles con sufijos por negocio. `UNKNOWN` no es `PASS`.
- **Input Governance:** consumidor selectivo de `INPUT_READINESS_CONTRACT`, sin copiar ni acoplar la gobernanza dentro del perfil; `PASS` o N/A justificado según aplicabilidad, recibo obligatorio.
- **Contexto:** una sola llamada del perfil; adaptador técnico no convoca a un LLM independiente y la cápsula no contiene el pack completo.
- **Efectos:** adaptar no habilita contacto, anuncios, escrituras ni producción. Escritura PTE: exclusivamente `saly.ventas_pte_ingesta_core_v1` bajo RUN gobernado con idempotencia, versión e identidad de ejecución; no por migración recurrente.
- **Salida:** contrato común `source_id, discovered_entity, evidence_refs, source_version, business_code, policy_version, coverage, blocking_codes, next_step`; no puntuación ni envío en el piloto PTE.

## Estado verificable y límite de esta corrección
`profiles/saly_radar_comercial` es un paquete **histórico CANDIDATO, NO_PROMOVER/NO_HABILITADO**: conservar sus pruebas del piloto, no darle alta nativa ni ampliar el caller SALY con este identificador. No equivale a que exista un Radar compartido. Tampoco se convierte al Product Director en Radar.

El archivo `business_adapter_binding_v1.mjs` es un **validador candidato offline**, no ejecutor/Router alternativo; su `source='ACT-0001_EXTERNAL_TRUSTED_HANDOFF'` es un marcador de interfaz de test, NO una atestación criptográfica. Tests: SALY positivo, política LF sintética positiva, rechazo de contaminación SALY→LF y de fuente sin permiso. Integración oficial bloqueada hasta seleccionar un perfil nativo de función y vincular un Router receipt real, sin creación duplicada.
