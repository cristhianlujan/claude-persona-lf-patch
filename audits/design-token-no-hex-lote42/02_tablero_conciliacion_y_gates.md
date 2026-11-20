# LF L42 — Eliminación gobernada de colores literales en reglas y consumidores
**Dueño 22:57 Lima:** decisión documental de trabajar únicamente con referencias a tokens de diseño. `identity_verified=false`. EKB V1.4 leída. **NO** Supabase DML/DDL, escritor V2, migración ni promoción. Fuente autoritativa `lf_design.color_tokens` (33 filas, 30 con color y 3 pendientes); no inventar equivalencia por parecido.
## Cobertura SELECT
- `84` tablas base de `lf_ops` + `lf_design` escaneadas (HEX 3/6/8, rgb/rgba/hsl/hsla) => `98` filas con coincidencias en `15` tablas. `private.lf_reusable_policy_registry_v1`: 1 política/0 coincidencias. `lf_ops.politicas_seguridad` y `lf_ops.politicas_rate_limit`: **0**.
- `lf_ops.reglas`: exactamente **4** reglas con HEX6, 0 HEX8, 0 rgb/hsl. Las apariciones HEX3 en `reglas_pantallas`, `pantalla_artefactos` y `system_audit_*` como `#402`, `#414`, etc. son **referencias a IDs**, no colores; no reemplazar.
- `lf_design.color_tokens.hex_value/rgb_value` son precisamente **valores canónicos del registro**; retener. `spacing_tokens` tiene 3 definiciones de sombras `rgba(...)` que usan los tokens `shadow_card_elevation`, `shadow_panel_deep` y `shadow_soft_ambient`; alfa no equivale a `navy_core` opaco: conservar origen numérico dentro de su definición de token hasta rediseño explícito.
- `brand_assets`, `visual_decisions`, `pantalla_artefactos`, `qa_*` y `system_audit_*` contienen metadata, capturas, hallazgos y evidencia histórica: NO sobrescribir ni falsificar valores medidos. `component_tokens` contiene un componente VIGENTE con dos colores de composición sin tokens y uno DEPRECADO como trazabilidad, que quedan bloqueados/no operativos.

## Reconciliación de seis filas staged (textos/JSON completos en fixture)
| Código | Estado actual | Acción staged | Gate |
|---|---|---|---|
| `UX-GAMIF-TERMOMETRO-01` | CANDIDATO | `green_action` en lugar de valor de color | Propuesta revisable |
| `UX-RUTA-ACCESIBILIDAD-01` | VIGENTE | `text_muted_inactive` | Solo rama staged; V2 CANDIDATO no puede editar vigente |
| `UX-RUTA-ESTADOS-01` | CANDIDATO | `green_action`, `gold_reward`, `navy_core`, `card_surface`, `text_muted_inactive`; foco separado en color/style/width | **BLOQUEADA:** se sugieren `route_future_segment_soft` y `cool_surface_soft`, inexistentes |
| `UX-TOKEN-CONSOLIDACION-01` | VIGENTE | `slate_text_strong` (no usar el deprecado `hero_subtitle_text`); quitar `valor_config.hex` legado | Solo rama staged |
| `link_inline_default` | VIGENTE | Notas referencian `blue_brand_accent` | Solo rama staged |
| `text_button_primary` | VIGENTE | Notas referencian `green_action` | Solo rama staged |

**No confundir:** `warm_surface` tiene otro valor real, por lo que no sustituye `cool_surface_soft`; `border_soft` tampoco tiene el valor de `route_future_segment_soft`. Todo staging con nombre inexistente queda inequívocamente **NO-GO**; no consumirlo ni promocionarlo.
**Tokens sin correspondencia:** 10 colores distintos en fuentes históricas/actuales se listan en `03_decisiones_humanas_tokens_sin_crear.json`, con nombre propuesto, origen y prueba de ausencia. No se crea ni cambia `lf_design.color_tokens`.
**No duplicar Login:** #3844/#3846/#3847/#3848 no se editaron ni copiaron; el alcance nuevo son reglas UX de Ruta/Termómetro y notas de tokens de diseño (2 consumidores).
**Preimagen y hashes:** fixture `sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_l42_color_token_mapping_and_staged_patches.json` conserva SHA y fila completa de origen. VIGENTE mantiene estado; solo propuesta documental, sin writer V2.
**Prueba real:** `sandbox/lf_contract_gate_test/edge_function_operation/test_lf_l42_token_nohex_pg17_pg18.py` reconstruye tres tablas en PG17.6 y PG18.7, verifica SHA fuente, seis UPDATE aislados en BEGIN/ROLLBACK, SQL zero-literal en propuesta y SHA íntegros tras rollback. **Solo declarar PASS cuando se lea CI exact HEAD.**
**Readback de producción: NO APLICADO** — 0 escrituras en Supabase vivo, 0 promoción. Requiere decisión humana de 2 tokens, revisión de consumidores JSON de foco, juez/regla y ruta oficial para VIGENTE.
