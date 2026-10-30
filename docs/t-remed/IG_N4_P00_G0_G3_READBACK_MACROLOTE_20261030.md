# LF Input Governance N-4 / P00–P11 — Readback de macrolote (30-10-2026)

> **ANEXO DE EVIDENCIA, NO PLAN NUEVO Y NO GATE NUEVO.** Plan único: `IG_N4_TREMED_PLAN_MAESTRO_EJECUCION_V1_20261028.md`. PR #3269 (DRAFT/NO-GO), HEAD antes del lote `f4a85652b20d00eabb04ba2f694aeca77e4fcd6e`. Lecturas SQL de solo lectura sobre Supabase LF y fuentes Git exact-ref. Este documento **no** ratifica G0–G4, no cierra P00–P12 ni autoriza G5, publicación, reclasificación, Router, migraciones, ACL, PASE o despliegue.

## 1. Arquitectura / alcance de ejecución

Perfiles mediante `GPT_NATIVE` o `CLAUDE_NATIVE` en la conversación nativa, con adaptador y provenance propios; **sin API remota de modelos ni fallback REMOTE_API** para este flujo. El uso de Supabase REST/RPC/Edge por el runtime Input Governance es comunicación interna de infraestructura y no constituye una llamada a API de modelos. Sin modificación del Router ni de las interfaces de los diez perfiles.

EKB vivo leído: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`, `AUD-045`, `IG-M107-NATIVE-EXECUTOR-ROUTE-CORRECTION-044`. Respetar fail-closed en selector no resuelto, independencia del Validator y prohibición de inferir GLOBAL por frecuencia.

## 2. P00 — línea base, fuentes, integridad

- Supabase vivo: **58 pantallas / 53 activas; 578 reglas / 412 VIGENTE / 166 CANDIDATO; 6.176 vínculos físicos; 14 selectores ACTIVE y 18 UNRESOLVED**.
- Hashes `md5(pg_get_functiondef)`: las 14 funciones críticas registradas en `IG_LOTE_A_P00_BASELINE_EVIDENCIA_20261028.md` conservan **14/14 valores originales**.
- Huella de vínculos físicos: `3e73901eec7101720863f20902b2026d`, coincide con la línea base de 28/10.
- `updated_at`: **0** filas de `lf_ops.reglas` y **0** de `lf_ops.pantallas` posteriores al corte `2026-10-28 15:33:20 UTC`. Es control de timestamp, no prueba absoluta contra cambios sin auditoría.
- Nuevos SHA-256 con contrato de serialización explícito: cada conjunto se ordena por `id`, se crea `jsonb_agg(jsonb_build_object(...))::text`, se convierte `UTF8` y se calcula `sha256`. Campos de **reglas**: `id,codigo,estado,titulo,descripcion,razon,categoria,valor_config,es_transversal,pendiente_decision`; SHA = `abf8c114f323d882c9667062022ba9d2b7c7dc884a0d63891a82d17fc61dd4bc` (802.229 bytes). Campos de **pantallas**: `id,codigo,module_id,estado,activa,objective,dependencies`; SHA = `219f78158d01622866fba81313e8e8fa1119a3d1bdcd51177768a94681ea9735` (13.572 bytes).
- **Límite:** los dos MD5 históricos del *contenido* de reglas/pantallas están descritos sin serialización externa exacta; un recálculo con separadores razonables no los reproduce. No afirmar paridad de esos dos MD5; usar SHA-256 anterior como **nuevo corte verificable** sin reescribir el histórico.

## 3. P08 — lectores y consumidores

- SQL `pg_proc.prosrc`, esquemas `programacion,lf_ops,private,public,transversal`: **19** lectores directos de `fn_input_effective_rule_links_v1`, **3** de `fn_t_remed_global_rules_v1`, **1** de `fn_input_rule_selector_matches_v1` y **0** de `fn_t_remed_effective_rules_v1`. Total de funciones con al menos una coincidencia directa: **22**, sin sumar las coincidencias superpuestas como consumidores distintos.
- Inspección de vistas/vistas materializadas de `pg_views/pg_matviews`: **0 referencias textuales directas** a las cinco funciones objetivo. `pg_depend` de vistas contra esos mismos objetivos: 0.
- Se inspeccionó fuente de **39/39 Edge Functions** desplegadas: ninguna referencia textual directa a esas seis funciones. `input-governance-agent-v1` sigue llamando `fn_input_governance_execute`, Curator llama `fn_input_governance_curator_materialize_v1` y su handoff, Validator usa handoff/validate/resume.
- **Pendiente:** SQL dinámico, grafo transitivo completo y consumidores externos que invoquen por RPC genérico o nombres construidos. Un 0 textual no prueba 0 operativo.

## 4. P01/P02 — casos reales sin adjudicar alcance

- Se observaron en la base **12 reglas** piloto/adversariales: `REG_SES_001`, `REG_ABT_004`, `B2B-RULE-SESSION-001`, `B2B-RULE-DESIGN-001`, `B2B-RULE-STORY-READINESS-001`, `REG_ONB_003`, `REG_ONB_004`, `B2B-RULE-A11Y-001`, `B2B-RULE-PRIVACY-001`, `B2B-RULE-AUTH-001`, `B2B-RULE-RATE-001`, `B2B-RULE-PROD-001`.
- Lectura efectiva, 12×4 = **48 pares**, destinos `B2B-AUTH-001`, `B2B-AUTH-002`, `ONB_004`, `HOME_FAQ`. `B2B-RULE-DESIGN-001` está declarada para ambos Login y **no coincide** con ONB/FAQ; `B2B-RULE-STORY-READINESS-001` coincide solo con Login 001. Ejemplos de reglas LEGACY B2B de accesibilidad/privacidad/autenticación aparecen `DERIVED_GLOBAL` en ONB/FAQ. **Observación, no decisión de validez semántica**.
- Los **14** ACTIVE tienen **17 cláusulas** en total: **14** sobre screen.id, **2** módulo, **1** shell, **0 EXISTS**, **0 operadores no soportados**. **16 pantallas** carecen de módulo; no crear campos globales de sesión/onboarding. Las fuentes adicionales se consultan solo por regla que las necesite.

## 5. P07 — reejecución completa del corpus de herencia

Fuente exacta `ig_lote_a_p07_alcance_readonly_20261028.sql` ejecutada en SELECT con CTE MATERIALIZED:
- **8.852** `DERIVED_GLOBAL` / **241** reglas / **58** pantallas / **785** pares en pantallas inactivas.
- Partición: destino sin shell **2.201**; origen sin shell **42**; fuera de shell de origen **5.230**; dentro de shell observado **1.379**. `partition_ok=true`.
- El shell es dato diagnóstico, **no** autoridad para suprimir ninguno de los 8.852 vínculos. No reclasificar.

## 6. G2/G3 — replay material del matcher, read-only

Fuentes exactas `ig_n4_preclass_synthetic_matcher_v2_20261028.sql` y `ig_n4_active_selector_parity_readonly_20261028.sql` ejecutadas en Supabase:
- **28 vectores: 18 PASS / 10 FAIL** respecto al contrato objetivo propuesto, no respecto a un contrato productivo ratificado.
- Fallos: `T07,T08,T09,T22,T23,T24,T25,T26,T27,T28`. Agrupación: JSON null/EXISTS/EQ/IN; amplitud sin autoridad; propiedad extra ignorada; OR con segundo elemento inválido; `consumer_role` de tipo incorrecto.
- Baseline activo: **14×58=812** comparaciones, **52** matches originales, **52** en contexto proyectado, **0 diferencias**.
- **Conclusión:** G3 no pasa integralmente. El fallo T22 es frontera de *publicación/autoridad*, no necesariamente bug booleano del comparador. No cambiar oráculos para fabricar PASS. La prueba PostgreSQL aislada previa queda como evidencia histórica con su commit específico, no como ejecución fresca del candidato actual.

## 7. P10/G4 — promoción y autoridad

- Candidatas: **166 sin selector objeto**, de las cuales **12** poseen al menos **15** vínculos físicos (umbral histórico 25 % de 58), máximo **24**. **Solo riesgo condicional**, no consta PASS de promoción ni una promoción real.
- Query del G4 canónico `ig_g4_run_registry_live_readonly_boundary_20261028.sql`: último run IG **949**, `COMPLETED_CURRENT`, consumer `CONTEXT_PACK` permitido; **0** rutas `RULE_APPLICABILITY_CHANGE` de Input Governance, **0** emisores activos, **0** receipts de scope. Resultado exacto `HOLD_NO_SCOPE_AUTHORITY_ROUTE`. No afecta por sí solo la vigencia del run 949 ni autoriza G5.

## 8. Dictamen por secuencia, sin cierres ficticios

| Etapa | Avance de evidencia | Estado de cierre |
|---|---|---|
| P00 / G0 | Baseline, 14 hashes, inventario SQL/Edge/vistas, SHA256 nuevos | **PARCIAL**: serialización histórica ambigua, trazas dinámicas/externas y review independiente; G0 requiere ratificación |
| G1 | Diccionario y ejes A-F existentes, leídos en contrato director | **DISEÑADO / NO RATIFICADO** |
| G2 | Adenda F01-F06 / H01-H21, 10 fallos reproducidos y mecanismo propuesto | **DISEÑADO / NO RATIFICADO** |
| G3 | 28 vectores materiales, 812 pares, P07 reejecutado | **PARCIAL / FAIL de contrato propuesto; falta integración/independiente** |
| G4 | Prepublicación comprobada contra run 949 | **HOLD_NO_SCOPE_AUTHORITY_ROUTE** |
| G5 | Sin operaciones | **NO_RECLASSIFY** |
| P12 | Sin operaciones | **NO_GO para publicación** |

**Cierre formal de P00-P12:** no se altera 0/13 registrados. La próxima intervención técnica puede usar este anexo y los artefactos existentes sin rehacer inventarios. Para ratificar G0/G1/G2 se necesita decisión competente y evidencia registrada; no sustituirla con el análisis del autor.
