# LF IG N-4 — Evidencia P08/P10: lectores, promociones y derivación global

> **IMPLEMENTACIÓN DE PROCESO POSTERIOR (2026-10-28):** la mitigación forward-only está en [SQL candidato sandbox](../../sandbox/lf_contract_gate_test/input_governance/ig_p10_forward_only_scope_boundary_candidate_20261028.sql); no depende de que los autores editen a mano todas las rutas de promoción. Una foto de enlaces heredados preserva el pasado sin reclasificarlo; los nuevos VIGENTE/bindings/selector ACTIVE quedan bajo guard de admisión (HOLD hasta G4). Cobertura read-only 17/17; runner real PG17.6 aún NO VERIFICADO. Esta acta conserva el diagnóstico anterior, no constituye habilitación de producción.

**Fecha de corte:** 2026-10-28 · **PR #3269 DRAFT / NO-GO** · **Evidencia real:** SQL SELECT, `pg_proc` y `pg_get_functiondef`; cero invocaciones mutadoras.  
**Plan maestro:** [G0–G5 / P00–P12](./IG_N4_TREMED_PLAN_MAESTRO_EJECUCION_V1_20261028.md).  
**Estado P08:** PARCIAL (solo corpus local DB) · **P10:** EN INVESTIGACIÓN, NO CERRADO · **G5:** NO_RECLASSIFY.

## 1. Lectores estáticos: límite observado, no grafo completo

Inspección de `pg_proc.prosrc` restringida a `programacion,lf_ops,private,public`:
`19` funciones que contienen texto `fn_input_effective_rule_links_v1`,
`3` `fn_t_remed_global_rules_v1`,
`1` `fn_input_rule_selector_matches_v1`,
`0` `fn_t_remed_effective_rules_v1`.
Vistas y materialized views inspeccionadas mediante `pg_get_viewdef` para las mismas cuatro cadenas y esquemas: `[]` (cero coincidencias). **No equivale a ausencia de dependencias:** no prueba SQL dinámico, consumidor externo ni dependencia indirecta.

Ejemplos de consumidores con referencia estática: `lf_ops.fn_b2b_backoffice_login_contract`, `lf_ops.fn_screen_contract_v1`, `programacion.fn_input_api_contract_resolution`, `fn_input_design_system_resolution_v1`, `fn_input_security_capability_profile`, `fn_input_screen_canonical_graph`, `fn_input_governance_semantic_probe_v3`.

## 2. Ruta real por definiciones SQL

Se obtuvieron **las definiciones originales** desde `pg_get_functiondef`, sin ejecutarlas.

`programacion.fn_t_remed_rule_promotion_verdicts_v1(p_min_screens,p_regla_id)` devuelve `PASS` si sus criterios incluyen: `NO_PENDING_DECISION`, `NO_PENDING_MARKER`, `HAS_STATED_REASON`, `USED_BY_ENOUGH_SCREENS`, `NO_DUPLICATE_ACTIVE_RULE`. Estos son criterios de **promoción técnica**, no evidencia de `rule_ref + scope + receipt`. Su función de promoción no verifica directamente un selector N-4.

`programacion.fn_t_remed_promote_v1(p_apply boolean,p_min_screens integer,p_limit integer)` (MD5 `5b9d08393be4dab7e7a364bf506bd5ef`) toma `PASS` y, **si** `p_apply=true`, hace `UPDATE lf_ops.reglas SET estado='VIGENTE'` para candidatas. No ejecutado.

`fn_t_remed_promote_v1(p_pantalla_id integer,p_consumer text)` (MD5 `1a6216e39e10748ebba0e96535b4c11f`) promueve vínculos de políticas a VIGENTE tras verificación independiente y root decision; no aprobar scope por simple homonimia de función. No ejecutado.

`fn_t_remed_promote_v3(p_pantalla_id integer,p_consumer text)` (MD5 `63fca3a053bd1b499dc10a44a493c04f`) puede promover links, policies y reglas CANDIDATO a VIGENTE si sus propias condiciones se cumplen. Para reglas consulta `lf_ops.reglas_pantallas`, `pendiente_decision`, `_policy_id` y referencias vigentes. No se observó una comprobación directa de selector N-4 ni de recibo de autoridad de scope en su cuerpo; **no se ha demostrado que las funciones internas que invoca tampoco incorporen controles adicionales**. No ejecutado.

`programacion.fn_t_remed_global_rules_v1(p_min_share numeric DEFAULT 0.25)` deriva globalidad de reglas VIGENTE si la cuenta de pantallas físicas es al menos `25%` del universo **o** si un scope judge devuelve `PASS_GLOBAL`.

`programacion.fn_input_effective_rule_links_v1(p_pantalla_id,p_consumer)` mezcla `LEGACY_EXPLICIT` + `declared` + `DERIVED_GLOBAL`. La rama heredada usa `fn_t_remed_global_rules_v1(0.25)` y toma reglas cuyo selector no es objeto, siempre que pantalla no tenga vínculo físico explícito. Esta ruta **no usa N-4 para autorizar el enlace `DERIVED_GLOBAL`**. MD5 real `156247a925d74c6f4accd7a6d2508489`.

## 3. Hipótesis de riesgo: promoción técnica → herencia implícita

**Condicional fundamentada por código:** una regla CANDIDATO sin selector, ya asociada físicamente a suficientes pantallas, **si posteriormente** cumple un control de promoción y pasa a `VIGENTE`, podría entrar en `fn_t_remed_global_rules_v1` por frecuencia. En ese caso, `fn_input_effective_rule_links_v1` emitiría `DERIVED_GLOBAL` en pantallas sin vínculo físico, sin que ese vínculo posea un selector N-4 autorizado.

**Corte SELECT vivo, sin promover nada:** `58` pantallas; umbral `0.25*58 = 14.50`, por lo que `15` asociaciones cumplen condición numérica. De `166` reglas CANDIDATO, `166` carecen de selector objeto; `18` tienen ≥5 asociaciones y `12` tienen ≥15 asociaciones. Máximo observado 24. Estas `12` **cumplen solo la condición de frecuencia; NO está verificado que pasen veredictos ni que se promuevan**. No probar la brecha ejecutando promociones en producción.

Intento SELECT de `fn_t_remed_rule_promotion_verdicts_v1(5,NULL)` fue **denegado**: error literal `ERROR: 42501: permission denied for function fn_t_remed_rule_promotion_verdicts_v1`. No hubo elevación de roles, fallback ni escrituras. `PASS` de promoción por esas 12 = **NO_VERIFICADO**.

## 4. Qué significa y qué NO

- **Hallazgo observado:** la ruta de herencia `DERIVED_GLOBAL` depende de frecuencia y estado y está separada de la autorización de selector N-4, lo que exige control de promoción + consumidor. Es deuda real del diseño actual, no autorización de cambio de datos.
- **No demostrado:** que alguna de las 12 candidatas sea autorizable, que haya pasado el gate técnico, que haya sido promovida, que exista una explotación operativa, ni que las autorizaciones de todos los owners falten.
- **No hacer:** tratar los 12 candidatos como cola de reclasificación; cambiar `es_transversal` a mano; retirar 8.852 relaciones; ejecutar `fn_t_remed_promote_*` sin ruta gobernada; convertir PASE SUCCESS en aprobación.

## 5. Pruebas necesarias P08/P10 (sandbox y luego integración)

| ID de prueba local propuesto | Negativo/positivo | Expectativa de aceptación | Bloqueo |
|---|---|---|---|
| P10-N01 | Regla CANDIDATO sin selector, con frecuencia umbral y decisión técnica PASS simulado | No genera `DERIVED_GLOBAL` ni publicación automática de scope tras promoción técnica | Falta implementación integrada nueva |
| P10-N02 | Regla de alcance legítimamente amplio con selector y recibo real | Hereda en destinos compatibles sin añadir IDs por pantalla | G4 authority/no receipt |
| P10-N03 | Regla CANDIDATO con `pending_decision` | Promoción rechazada; sin cambio de herencia | Fixture aislado |
| P10-N04 | Cambio de SHA de policy/selector después de decisión | Receipt obsoleto no habilita ampliación | G4 currentness |
| P08-N01 | Login B2B, API, security, design y consumer no autorizado | Sin ruta alternativa a global por frecuencia ni ejecución candidata | Inventario de consumers externo parcial |
| P08-N02 | Vista/función dinámica sin referencia literal | Detección de bypass por análisis de llamadas y contratos, no deducción por grep | Fuente Git/pg_depend pendiente |

Nombres N01–N04 y N01–N02 son **identificadores de casos nuevos de prueba**, no gates ni checkpoints canónicos. Requieren revisión versionada antes de integrarse a suites; no cuentan como PASS.

## 6. Próximo trabajo ejecutable sin permiso nuevo

1. Ampliar P08 con `pg_depend`, funciones y fuentes Git/API, incluyendo posible SQL dinámico; congelar mapa de readers externos.
2. Formular patch SQL de **sandbox**, con control de scope separado de promoción, que preserve casos universales legítimos; ejecutar positivos y negativos.
3. Si falta Docker/PG real, continuar con contratos G0/G2 y evidencia G4; nunca sustituir ACL post-DDL por datos calculados.
4. Ratificar metodología/competencia, luego permitir G5 por reglas con expediente y nunca por conteo.

**EKB consultado:** `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`, `IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`, `IG-TARGETED-EVIDENCE-BEFORE-HUMAN-ESCALATION-001`. No DB writes, Router, merges ni cambios ACL.
