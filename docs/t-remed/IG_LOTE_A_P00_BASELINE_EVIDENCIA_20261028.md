# LF IG — Lote A, P00: baseline de herencia y fuentes (solo lectura)

**Estado P00: EVIDENCIA CONGELADA; sujeto a currentness del corte.** No prueba la corrección ni autoriza merge, selector o migración. Sin Router. Sin writes Supabase.

## Identificación del corte

- Fecha de consulta SQL única: **2026-10-28 15:33:20.420545 UTC** (10:33:20 Lima).
- Fuente: Supabase LF conectado, consultas SELECT, una sola sentencia para la línea base consolidada; funciones con source md5 desde `pg_get_functiondef`.
- GitHub repo: `cristhianlujan/claude-persona-lf-patch`; PR draft #3269; rama `dev/ig-n4-tremed-cascade-governed-20261028`.
- Estado de rama previo al registro: `d236320672a1904125511c180569185661d2b9e8`. La rama cambiará al adjuntar este artefacto: este hash no implica que el programa esté desplegado.
- EKB leído: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001` (activo), `INPUT-GOV-CONSUMER-BINDING-001` (ACTIVO), `CI-MIGRATION-SOURCE-PARITY-001` (activo).

## Medidas consolidadas del mismo SELECT

| Métrica | Valor |
|---|---:|
| Pantallas (activas) | 58 (53) |
| Reglas | 578 |
| Reglas vigentes / candidatas | 412 / 166 |
| Relaciones físicas | 6.176 |
| Relaciones efectivas | 15.028 |
| Relaciones legacy explícitas vigentes | 5.636 |
| Relaciones legacy explícitas candidatas | 488 |
| Relaciones N-4 declarativas | 52 |
| Relaciones DERIVED_GLOBAL | 8.852 |
| Códigos de regla que originan DERIVED_GLOBAL | 241 |
| Vigentes transversales sin selector | 95 |
| Selectores ACTIVE / UNRESOLVED | 14 / 18 |

**Límite:** las 8.852 relaciones no están todas invalidadas; su aplicabilidad semántica aún debe ser revisada. Ninguna cifra es permiso. Los 95 sin selector y 18 UNRESOLVED son cohortes que se deben analizar de modo distinto.

## Checksums de datos

Se generaron para **detección de drift**, no como firmas de autoridad. La expresión de cada digest debe conservarse idéntica para futuras comparaciones.

| Datos | MD5 |
|---|---|
| Catalogo de reglas (ID + md5 de concatenación de campos, ordenado por ID) | `5327761a4d12b495f6ec029e04f7cb49` |
| Catálogo de pantallas (ID + md5 de atributos, ordenado por ID) | `c8e756001a04e9f135e68bd9f6fc22f8` |
| Vínculos físicos (pantalla_id:regla_id ordenados) | `3e73901eec7101720863f20902b2026d` |

Para reproducir los digests, los registros de reglas se normalizan usando:
`md5(concat_ws('|',codigo,estado,titulo,descripcion,razon,categoria,valor_config::text,es_transversal::text,pendiente_decision::text))`;
para pantallas:
`md5(concat_ws('|',id::text,codigo,module_id::text,estado,activa::text,objective,dependencies::text))`;
para relaciones:
`md5(string_agg(pantalla_id||':'||regla_id,',' ORDER BY pantalla_id,regla_id))`.
**Precaución:** concat_ws omite NULL; es fingerprint de cambio bajo este contrato exacto, no firma sin ambigüedades. Para un release deberá usarse JSON canónico y SHA-256 con procedencia.

## Funciones críticas: md5 de pg_get_functiondef

| Función | MD5 |
|---|---|
| `programacion.fn_input_rule_target_context_v1(integer,text)` | `573649516a63d889f69725690a8de8db` |
| `programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)` | `1123257c0c6c7eb1e2aa26783f3ccc0a` |
| `programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)` | `3b912c7872aceff83de24e9e8d1ad934` |
| `programacion.fn_input_declared_rule_links_v1(integer,text)` | `990226616c7f48fc82346799e54c2bdf` |
| `programacion.fn_input_effective_rule_links_v1(integer,text)` | `156247a925d74c6f4accd7a6d2508489` |
| `programacion.fn_t_remed_scope_judge_v1(numeric)` | `433445c108c36b25cf26f5a1bddb7a99` |
| `programacion.fn_t_remed_global_rules_v1(numeric)` | `7d8b7a58f16bc5b53867c3322fd1befb` |
| `programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)` | `92e8025b70d17e3de7da7206795ed73d` |
| `programacion.fn_t_remed_promote_v3(integer,text)` | `63fca3a053bd1b499dc10a44a493c04f` |
| `programacion.fn_t_remed_recommend_v1(integer,numeric,boolean)` | `e691ce1784e192f10f994c86fbd0d3ef` |
| `programacion.fn_t_remed_inherited_rules_v1(integer,numeric,boolean)` | `e0fd4ce5fcd105b10858ebdc858fcc5d` |
| `programacion.fn_t_remed_effective_rules_v1(integer,numeric)` | `ad5aecf15e12be5b55fdd1e8dac00295` |
| `lf_ops.fn_screen_contract_v1(text,text,text)` | `7817a728991b66865b9f144c658512be` |
| `lf_ops.fn_b2b_backoffice_login_contract(text,text,text)` | `6fceb03a6fbb79f98f612d51cae3facf` |

## Dependencias consumidoras directamente observadas (no inventario transitivo completo)

Los siguientes consumidores leen `fn_input_effective_rule_links_v1`: `fn_ig_m107_trusted_run_data_v1`, `fn_input_actionable_remediation_summary_v1`, `fn_input_api_contract_resolution`, `fn_input_design_binding_graph`, `fn_input_design_system_resolution_v1`, `fn_input_governance_semantic_probe_v3` y variantes `ctx/cached`, `fn_input_governance_shadow_priority_oracle_v2`, `fn_input_resolve_source_ref_v510`, `fn_input_screen_canonical_graph`, `fn_input_security_capability_profile`, `fn_input_security_threat_expected_v510`, `fn_input_subject_depth_expected` y variantes, y contratos `lf_ops.fn_screen_contract_v1` y `fn_b2b_backoffice_login_contract`. `fn_t_remed_effective_rules_v1` usa también globales T-REMED.

**P08 todavía pendiente:** esta es solo la dependencia directa por texto de funciones. Las vistas, capas de API y llamadas transitivas requieren búsqueda adicional antes de declarar paridad.

## Qué permite declarar este checkpoint

- **P00 snapshot SELECT:** PASS para el corte 2026-10-28 15:33 UTC, hashes y cantidades consignados; `currentness` requerido en cada lote posterior.
- **P00 cobertura de fuentes y consumidores:** PARTIAL, porque no se ha probado el inventario transitivo/API ni una firma SHA-256 autoritativa.
- **P01:** no aprobado en este paquete; los pilotos se publican por separado.
- **Corte del SQL candidato que elimina DERIVED_GLOBAL:** NO-GO. Mantener la cascada real hasta clasificación y autorización verificadas.
