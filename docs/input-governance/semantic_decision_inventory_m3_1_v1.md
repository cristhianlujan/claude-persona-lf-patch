# M3.1 / PAULO-130 — Inventario por decisión semántica

## Alcance
Inventario y clasificación AS-IS. No refactoriza resolvers, classify, probes ni runtime.

Autoridad observada: `LF_SUPABASE_SANDBOX` (`pg_proc` / fuente live), 2026-10-04T05:51:23Z. Se reutiliza M0.5/M2.0 para la frontera FACT / POLICY / HEURISTIC / SEMANTIC / READINESS / ORCHESTRATION y se refrescan fingerprints live.

## Resultado
- 197 decisiones lógicas inventariadas.
- 14 funciones fuente observadas.
- 197/197 con identificador estable derivado de identidad lógica, familia, módulo, fuente y clase.
- IDs no dependen de número de línea ni SHA; el SHA registra currentness/provenance, no identidad.
- 0 decisiones condicionadas por prefijo de pantalla en las 14 fuentes observadas: 0 literales `B2B-%` y 0 predicados `screen_code LIKE/ILIKE/~`.
- No hubo cambio de runtime ni de semántica.

La matriz completa machine-readable está en `semantic_decision_inventory_m3_1_v1.json`.

## Fuentes y currentness

| Fuente | SHA256 live | Decisiones |
|---|---|---:|
| `fn_input_governance_bootstrap_classify_v1` | `410ddc535be6e13dbbee449c4c196d41c777b6056eb8faa0feb7309527e74745` | 47 |
| `fn_input_governance_bootstrap_classify_v2` | `4649e9935f3ed87a6ee9df08d8fc7d95f545374b7f79fcec89edcbfe335ea3e3` | 6 |
| `fn_input_governance_semantic_probe_v1` | `e58a738bccda3c53c781e6b4eb776b2683a690fab8a70a08c3152654df3d513a` | 7 |
| `fn_input_governance_semantic_probe_v2` | `bda3b929fb0f79306c56676dd81ac3ce2293aa8733f96bb2cdb3478f1fd8d652` | 2 |
| `fn_input_governance_semantic_probe_v3` | `bbae8d1a064f8612daa66abbac505ba5426119b9dce84f94b724bca0070706fa` | 17 |
| `fn_input_bootstrap_rule_probe_v1` | `6c64f9e46915b86538d915107289b413fa5a8fd061a84094bef77fad795d133f` | 2 |
| `fn_input_governance_field_reference_probe_v1` | `e14a9d761cb81b72756c07743b853203b4776a6f883ae3619803c1d4a37bbdd3` | 7 |
| `fn_input_na_positive_authority_v512` | `13609f6093951710082748cd1bbe870bda5c102f67de24fd5f27c96c1f8674f6` | 6 |
| `fn_input_api_contract_resolution` | `9a0d3daee329821b16a79699e356268fda09ad14ed6e546c6aff924c95034ba7` | 6 |
| `fn_input_design_binding_graph_v2` | `a58c68051ea09745fc0eaa6c77966867bd90c8a5870bd4badce6e046adc4e1a9` | 5 |
| `fn_input_security_threat_expected` | `4c0a19d2c0d82ce79f8e3231c7103ace0c2b802e6eea96d2e046f27fcbcf38b7` | 9 |
| `fn_input_security_threat_expected_v510` | `b968c86679068da38dbd989d0a6559507694e920f58142d412799ffcff660a87` | 30 |
| `fn_input_subject_depth_expected` | `a40ab63d185c2ef4293995770d50e3bea8403ed9e0f02f033f2c32a2ee0b99b3` | 9 |
| `fn_input_subject_depth_expected_v510` | `f1a1f6926cefab0487081793ce9fd27d9446991ce4ca65e9dcddeebcef447606` | 44 |

Clases: FACT 20 · POLICY 14 · HEURISTIC 25 · SEMANTIC 133 · READINESS 4 · ORCHESTRATION 1.

## Reutilización M0.5 / M2.0
M2.0 está fusionada en M0.5. Se reutilizó el mapa cerrado de responsabilidades `responsibility_block_map_v1` para `classify_v1/v2` y `semantic_probe_v1/v2/v3`; donde el fingerprint live cambió, solo se conservó la clasificación estructural y se refrescó la fuente observada. No se heredó currentness por hash histórico.

## SOURCE_PACK: faltante acotado
El alcance de M3.1 nombra `subject/threat_expected`, pero `source_pack_v1` enumeraba los dos `threat_expected` y no los dos `subject_depth_expected`. Se activó únicamente el trigger `MISSING_CANONICAL_OBJECT`: búsqueda dirigida en `pg_proc`, sin barrido Git/Supabase. Ambas funciones fueron encontradas e incorporadas con SHA live. No se alteró el SOURCE_PACK ni runtime.

## Condiciones por pantalla
La prueba negativa fresca sobre las 14 fuentes dio 0 condiciones por prefijo. Existe una especialización exacta en `fn_input_subject_depth_expected`: `pantalla_id=56` (`B2B-AUTH-006`, módulo `B2B_AUTENTICACION`). No es una condición por prefijo; queda inventariada como deuda/decisión AS-IS para fases posteriores, sin refactor en M3.1.

## Regla de identidad y módulo
- ID estable: prefijo por función + clave lógica (`family`, `threat_code`, `check_code`, rol o decisión de resolución).
- Módulo: por defecto se resuelve dinámicamente desde el contexto canónico de `pantalla.module_code`; amenazas usan el perfil de capacidad de seguridad; la especialización de pantalla 56 declara `B2B_AUTENTICACION`.
- SHA/currentness: atributo de evidencia, no parte del ID.

## Exclusiones respetadas
No se modificaron N-13, N-14, N-15, M10.9, Validator runtime ni runtime semántico. No se ejecutó smoke de flujo porque M3.1 es documentación/inventario y no toca runtime.
