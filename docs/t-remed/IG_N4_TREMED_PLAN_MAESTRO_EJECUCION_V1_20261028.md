# LF Input Governance — Plan maestro único G0–G5 / P00–P12
**Fecha de corte:** 2026-10-28 · **Versión:** 1.0 · **Tipo:** plan operativo de coordinación (NO es nuevo gate del Router/DB)  
**Repositorio:** `cristhianlujan/claude-persona-lf-patch` · **PR:** #3269, rama `dev/ig-n4-tremed-cascade-governed-20261028` (DRAFT, NO-GO).  
**HEAD de evidencia congelado antes de redactar:** `04ff92e932c443555bee604dd2f7503114a3318c`. Para futuras verificaciones, fijar nuevamente commit exacto y registrar readback.  

> **CORRECCIÓN OPERATIVA — 30/10/2026: UNA ARQUITECTURA, CONTROLES CON SEGUIMIENTOS DISTINTOS.** Input Governance incluye **N-4 y T-REMED en su flujo existente**. N-4 se ejecuta en la resolución de aplicabilidad declarativa; T-REMED participa en herencias vigentes, diagnóstico y remediación. El grafo canónico `fn_input_screen_canonical_graph` consume `fn_input_effective_rule_links_v1`, que combina `LEGACY_EXPLICIT`, `DECLARATIVE_APPLICABILITY_V1` y `DERIVED_GLOBAL`. `fn_t_remed_screen_status_v1` reutiliza el grafo canónico y clasificador de Input Governance. La arquitectura **ya está conectada**; no crear un proyecto de integración, un nuevo orquestador o rutas paralelas. El Router enruta al perfil y el perfil ejecuta según sus facultades; ejecución GPT Native / Claude Native, sin API de modelos.
>
> **DOS LEDGERS PARA NO CONFUNDIR MÉTRICAS, NO DOS PRODUCTOS:** `IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.13` registra cierre de core Curator/Validator; `P00–P12/G0–G5` registra endurecimiento de la capa N-4/T-REMED. Sus cifras no se suman ni se usan como veto automático entre sí; sus **riesgos funcionales sí deben considerarse juntos al decidir el lanzamiento**. Una deuda técnica de N-4/T-REMED queda dentro del backlog de Input Governance y no fuera del flujo.
>
> **CORTE MÍNIMO DE LANZAMIENTO CONTROLADO — propuesta de alcance, no certificación ni aprobación de producción:** (1) probar en el mismo recorrido Router → Perfil → Input Governance → N-4/T-REMED que el consumidor permitido obtiene fuentes actuales, y que un consumidor no permitido/selector sin resolver no habilita aplicación; (2) validar independencia del Validator con canary negativo real que impida cerrar ante un defecto semántico, aprovechando la evidencia ya cerrada en M4.12; (3) publicar solo el alcance/casos expresamente comprobados con readback, control de exposición y rollback operativo existente. **No activar ampliaciones de scope, reclasificación masiva, promociones nuevas ni herencia adicional por frecuencia sin autorización de regla.** Si el recorrido no puede aislar las herencias de scope incierto, el lanzamiento público de ese recorrido NO está habilitado: se requiere un control mínimo efectivo, no una declaración documental. No inventar feature flags ni reducir protecciones.
>
> **DEUDA TÉCNICA POST-CORTE (se sigue trabajando):** corpus completo de reclasificación de las 241 reglas / 8.852 relaciones; refactor de matcher frente a 10 negativos del nuevo contrato (separar brecha real de obligación nueva); optimización de score, expresividad contextual, auditoría de consumidores transitivos, gobernanza completa por scope y pruebas sintéticas ampliadas. No pretender que los controles formales P/G estén cerrados; tampoco bloquear el corte mínimo por mejoras que no se utilicen en su alcance. No borrar histórico ni eludir bloqueos reales de seguridad/fuente.


## 0. Mandato y frontera de alcance

Este documento **CONSOLIDA**, no sustituye ni duplica las definiciones de los documentos de diseño, los checkpoints P00–P12 ni los gates G0–G5. P y G son dos vistas sobre **el mismo trabajo**: P identifica entregables implementables, G decide si es admisible pasar a la siguiente etapa de la metodología. No contarlos como 19 tareas independientes. Las nuevas constataciones se añaden como evidencia a su P/G de origen.

Secuencia normativa: **estrategia → definiciones → reglas → pruebas sintéticas → ratificación competente → reclasificación basada en evidencia → integración posterior**. No ejecutar el SQL que retira `DERIVED_GLOBAL` en bloque. No declarar GLOBAL por frecuencia, `es_transversal`, shell, familia o similitud textual. No inventar enumeraciones de negocio en código, ni un segundo motor de scope o de aprobaciones.

**Durante diseño:** solo GitHub en PR draft para docs/tests/sandbox, Supabase en modo SELECT, sin Router, sin DDL, sin modificar pantallas, reglas, roles/ACL productivas, EKB, migraciones, pipelines ni workflows. Más adelante, integración solo por ruta gobernada, CI exact-head, source-first y autorización correspondiente. No aceptar un PASS de sandbox como permiso de producción.

## 1. Estado general — corte, no estimación inflada

| Indicador | Evidencia | Lectura correcta |
|---|---|---|
| Checkpoints P00–P12, total | 13 | 0 marcados CERRADO por la matriz de origen |
| Parciales | P00, P08, P11 = 3 | Trabajo útil pero aceptación incompleta |
| Referencia únicamente | P05 = 1 | Modelo auxiliar no calibrado ni aprobador |
| No hechos según matriz origen | P01,P02,P03,P04,P06,P07,P09,P10,P12 = 9 | Puede existir investigación preliminar; no confundir con ejecución completa |
| Gates G0/G1/G2 | Diseños propuestos, pendientes de ratificar | No LOCK formal por el agente |
| G3 | SELECT y smoke PG17.6 histórico; ACL/consumer/integración/revisión actual pendientes | No PASS integral |
| G4 | Autoridad por regla sin recibo verificado | No ratificado |
| G5 | Reclasificación bloqueada | NO_RECLASSIFY |

**Sin porcentaje global de implementación:** los 13 checkpoints no tienen esfuerzos equivalentes ni criterios de aceptación satisfechos; 0/13 CLOSED es el único porcentaje de cierre formal (0%), **no** significa 0% de trabajo ejecutado. Prohibido contar inventarios, resultados históricos o pruebas omitidas como checkpoint cerrado.

## 2. Baseline reproducido en vivo (Supabase, SELECT only)

Corte técnico del PR `04ff92e932c443555bee604dd2f7503114a3318c`: PostgreSQL 17.6, 58 pantallas, 578 reglas, 14 selectores ACTIVE, 17 cláusulas; auditor SELECT reportó `invalid_outer_schema=0`, `malformed_clauses=0`, `unauthorized_consumer_matches=0`.
`ig_n4_active_selector_parity_readonly_20261028.sql`: 14×58 = 812 pares, original=52, proyección=52, diferencias=0. **No valida G4 ni autoriza cambiar scopes.**

Preimage de funciones vivas: `fn_input_rule_selector_matches_v1` MD5 `3b912c7872aceff83de24e9e8d1ad934`; `fn_input_rule_selector_clause_matches_v1` MD5 `1123257c0c6c7eb1e2aa26783f3ccc0a`; `fn_input_effective_rule_links_v1` MD5 `156247a925d74c6f4accd7a6d2508489`. Helper de sandbox ausente en DB viva. P00 exige además currentness de vistas/API y fuente manifiesta antes de cerrar.

P07 solo **inventario, no decisión**: 241 reglas originan 8.852 enlaces `DERIVED_GLOBAL`; 92 están marcadas `es_transversal`, 149 no. Cohortes **no aditivas**: 95 `VIGENTE` transversales sin selector (92 generan enlace global), 18 con selector `UNRESOLVED` fuera de dicha cohorte; 14 ACTIVE. No recortar enlaces por conteo. En `valor_config`, ausencia de selector puede representarse como clave ausente **o clave JSON null**: usar `jsonb_typeof` y no `NOT valor_config?'applicability_v1'` como única definición de cohorte.

## 3. Checkpoints P00–P12 — matriz única de ejecución

`estado_origen` respeta la matriz auditada; la columna `actividad inmediata` indica la siguiente ejecución segura, **no convierte el checkpoint en DONE**. Un expediente o ensayo no equivale a ratificación.

| ID | Estado origen | Dependencia / gate | Actividad inmediata sin decisión humana | Criterio exacto de cierre | Quién debe validar |
|---|---|---|---|---|---|
| P00 | PARCIAL | Base para G0–G3 | Snapshot commit + EKB + 3 MD5 + 58×14 + manifiesto de consumidores, views/API, freshness | Source, reader graph, hashes, currentness, fecha y baseline reproducibles; control de drift | Técnico + Validator independiente |
| P01 | NO HECHO | G1/G2; precede G5 | Fichas semánticas por ejes: naturaleza, fuerza, efecto, condición, alternativas, ejemplos positivos/negativos; ampliar 12 hipótesis sin adjudicar scope | Dataset de casos estratificados y fichas por regla revisada; discrepancias y ownership rastreables | Curator + Validator; autoridad al cambio |
| P02 | NO HECHO | G2→G3 | Matriz de campos opcionales: path, fuente, owner, freshness, MATCH/NO_MATCH/UNKNOWN; 16 pantallas sin módulo no se fuerzan a tenerlo | Cada atributo obligatorio solo para regla que lo exige, prueba de ausencia/JSON null y no alteración lateral | Técnico + Validator |
| P03 | NO HECHO | G2→G3 | Inventariar casos que realmente necesitan NOT/excepción; documentar límite de EXISTS/EQ/IN; propuestas versionadas | Ejecución de negativos, compatibilidad actual, prohibición de NOT(NULL)=TRUE y no creación de operador injustificado | Técnico + Validator |
| P04 | NO HECHO | G2→G3 | Matriz de conflictos: acumular, duplicar, contradicción, veto, empate, excepción, autoridad incomparable |  S08–S10, pruebas falsadoras con fuente real y HOLD; no prioridad por orden SQL, pantalla o score | Validator + owner competente |
| P05 | REFERENCIA | G2, P01/P04 | Revisar 0..6 y alternativa sin autoaprobación; preparar casos oro, abstención y coste de errores | Tasa falsos +/− y abstención calibrada, referencias verificables, ninguna promoción por score | Curator + Validator |
| P06 | NO HECHO | G4 | Homologar el `private.lf_human_decision_*` actual, detectar owner/competencia real por rule_ref+scope+version, probar duplicidad/multidominio | Identidad, delegación, expediente hashes, decisión, vigencia, revocación y veto; receipt auténtico en ruta autorizada | Dueño funcional/seguridad/legal según caso |
| P07 | NO HECHO (inventario sí) | G5, bloqueado por G0–G4 | Conservar universo 241/8.852, clasificar **estructuralmente** y preparar fichas; NO decidir alcance ahora | Decisión por regla sustentada y ratificada: preservar, restringir, retirar o investigar; diff de enlaces sin caída arbitraria | Owner competente + Validator independiente |
| P08 | PARCIAL | G3 integración y P12 | Inventario de lectores SQL y consumidores externos, corte análisis/operación, camino de `DERIVED_GLOBAL` | Sin bypass, paridad por consumer y contratos Login/B2B/API/Seguridad/Diseño/Story; casos positivos y negativos | Técnico y propietarios de consumers |
| P09 | NO HECHO | G3 integración/P12 | Homologar estados reales; proponer transiciones, invalidación y rollback (no introducir enums por memoria) | Test de CANDIDATO/REVIEW/ACTIVE/SUPERSEDED/REVOKED según estados canónicos, cache/source manifest | Técnico + Validator |
| P10 | NO HECHO | G3 integración/P12 | Comparar 3 sobrecargas reales de `fn_t_remed_promote_v1/v3`, separar promoción de scope | Ninguna promoción/juicio técnico evita selector, owner/recibo o resuelve UNRESOLVED por heurística | Técnico + Validator |
| P11 | PARCIAL | G3→P12 | Ejecutar 28 vectores, 812 parity, ACL con roles, rollback; luego S01–S14, 13×47 con selector determinista→semántico, benchmark | Evidencia real por prueba, head exacto, datos negativos, latencia; revisión independiente que no reutiliza prueba productor | Tester técnico + revisor independiente |
| P12 | NO HECHO | Después G0–G5, P08–P11 | Preparar checklist source parity, owner, PR, CI, canary, impacto, rollback, readback; no publicar aún | Permisos firmados, fuente↔ledger exacta, PASE real, Train, readback y rollback verificables | Gobierno de integración/producción |

**Nota P10:** el catálogo read-only muestra `fn_t_remed_promote_v1(p_pantalla_id integer,p_consumer text)`, otra sobrecarga `fn_t_remed_promote_v1(p_apply boolean,p_min_screens integer,p_limit integer)` y `fn_t_remed_promote_v3(p_pantalla_id integer,p_consumer text)`. No comparar solo por nombre: distinguir firmas y el posible camino de escritura de `p_apply`. MD5 observados respectivamente `1a6216e39e10748ebba0e96535b4c11f`, `5b9d08393be4dab7e7a364bf506bd5ef`, `63fca3a053bd1b499dc10a44a493c04f`.

## 4. Gates G0–G5 — criterios de salida, no checkpoints nuevos

| Gate | Condición de admisión | Estado vigente | Cierre no delegado |
|---|---|---|---|
| G0 STRATEGY_REVIEW | Fuentes/EKB, estrategia sin global por heurística, componentes reutilizados, frontera offline/online | DISEÑO PREPARADO / NO RATIFICADO | Revisión de metodología por autoridad competente |
| G1 DEFINITIONS_LOCK | Glosario y ejes A–F sin confundir alcance, naturaleza, estado y autoridad | DISEÑO PREPARADO / NO RATIFICADO | Ratificación versionada de glosario |
| G2 CLASSIFICATION_RULES_LOCK | H01–H15 + **H16–H21**; precedencia por competencia probada, no jerarquía universal; gramática NULL, UNKNOWN, excepciones y negativos | DISEÑO v2.1 / NO RATIFICADO | Cerrar F01–F06, comparativa y actor competente |
| G3 SYNTHETIC_TESTS_PASS | S01–S14, matcher/ACL PostgreSQL 17.6, paridad, rollback, consumers, negativos reales, revisor independiente | PARCIAL / NO-GO | Test execution + revisión independiente |
| G4 OWNER_METHOD_APPROVAL | Fuente de competencia por regla, owner, autorización de scope versionada, veto y receipts auténticos; reusar registry actual | NO_VERIFICADO | Autoridad humana funcional/especializada según alcance |
| G5 REAL_RULES_RECLASSIFICATION | Solo posterior a G0–G4, fichas individuales, conservar herencias autorizadas, diff y validación | BLOCKED / NO_RECLASSIFY | Owner por regla; integración posterior por P12 |

**G3 históricas no son nuevas ejecuciones:** run `40741198646` del commit `efd74ce...` documentó PG17.6 28 vectores, 812 pares y rollback de un candidato previo. El candidato ACL y runner revisados en la rama posterior todavía requieren su **propia ejecución** y revisión independiente; reparación H01–H05 en handoff V3, commit `04ff92e...`. `PASE SUCCESS` con `MIGRATION_SOURCE_PARITY SKIPPED` NO equivale a paridad certificada ni G3 integral.

## 5. Cinco macrolotes con dependencias y trabajo en paralelo

| Macrolote | Scope de P/G existentes | Ejecutable de inmediato | Bloqueo / entrega |
|---|---|---|---|
| A — Estrategia, definiciones, evidencia | P00,P01,P02 + G0,G1,G2 | Completar baseline de readers/fuentes, normalizar H01–H21, falsar glosario con S01–S14 | Ratificación solo después de dossier y opciones |
| B — Motor y falsación | P03,P04,P05,P11 + G3 | Integridad SQL, ACL/perfiles en PG17.6 aislado, casos negativos, conflictos, paridad y benchmark | Falta runner PG disponible / revisor independiente; no certificar por tests Bash |
| C — Competencia humana | P06 + G4 | Identificar fuente de owner/delegación, revisar esquema central, diseñar expediente, probar rechazo | Sin fuente de competencia ni recibos no hay aprobación |
| D — Catálogo y herencias | P01,P07 + G5 | Preparar clasificación **no decisoria** y matriz de excepciones sobre 241/8.852 | G0–G4 y autoridad de cada cambio; cero reclasificación hoy |
| E — Integración y seguridad | P08,P09,P10,P11,P12 | Inventario de consumidores, lifecycle y variantes promote; preparar integración y regresiones | Implementación/cutover solo tras gates y ruta gobernada |

**Paralelismo correcto:** A, análisis de B, investigación de C y descubrimiento de E pueden avanzar juntos. D solo se analiza estructuralmente hasta G4; P12 final espera decisiones/CI. Prohibido detener todo porque Docker o owner estén pendientes si existen otros P sin bloqueo.

## 6. Hallazgo ejecutado en este lote — P08 descubrimiento de lectores

Consulta exclusivamente de catálogo `pg_proc.prosrc` en `programacion,lf_ops,private,public`:
- `19` referencias estáticas al resolvedor `fn_input_effective_rule_links_v1`; `3` a `fn_t_remed_global_rules_v1`; `1` a `fn_input_rule_selector_matches_v1`; `0` a `fn_t_remed_effective_rules_v1` en ese mismo filtro.
- Entre los lectores se observan `lf_ops.fn_b2b_backoffice_login_contract`, `lf_ops.fn_screen_contract_v1`, `programacion.fn_input_api_contract_resolution`, `fn_input_design_system_resolution_v1`, `fn_input_security_capability_profile`, `fn_input_screen_canonical_graph`, `fn_input_governance_semantic_probe_v3`, entre otros.
- **Esto NO es un grafo transitivo completo**: referencias por texto no detectan SQL dinámico, vistas, Edge Functions, consumidores externos ni dependencias indirectas. `0` referencias a una función en cuatro esquemas no prueba que esté sin uso.
- Acción P08 siguiente: `pg_depend` + `pg_rewrite`/vistas, búsqueda source Git, caller contract, clasificación operacional/diagnóstica y prueba de bypass en fixture, sin ejecutar funciones mutadoras.

## 7. Gestión de ejecución sin microaprobaciones

Cada P usa `PENDING → IN_PROGRESS → TECH_VALIDATED → INDEPENDENT_REVIEW → CLOSED`, con `BLOCKED`/ `NO_VERIFICADO` cuando aplique. **Son etiquetas de seguimiento de este documento, NO estados nuevos de base de datos ni cambios del workflow original.**

Mínimo por actualización: (1) P/G exacto y dependencia; (2) input/commit/query literal; (3) salida observada, no interpretada; (4) prueba positiva/negativa; (5) error y EKB; (6) patch atómico docs/sandbox si procede; (7) resultado de CI exact-head y skipped; (8) handoff revisor si corresponde; (9) próximo checkpoint desbloqueado.

No solicitar permiso para lectura, investigación, pruebas de sandbox o edición en la rama de desarrollo dentro del alcance ya autorizado. **Sí detener acciones** que afecten producción, grants, publicación, reglas/selector ACTIVE, rutas, gates canónicos o requieran que un actor humano competente firme decisión que no puede deducirse.

## 8. Próximas acciones concretas en el mismo programa

1. **P00/P08:** ampliar el manifiesto de consumidores con `pg_depend`, vistas, funciones Git, contratos externos; identificar bypass de globales y origen por función (solo lectura).
2. **G0–G2/P01/P02:** generar matriz de trazabilidad H01–H21↔F01–F06↔S01–S14; detectar contradicciones respecto a glosario y fuente; preparar decisión ratificable (sin auto-ratificar).
3. **P03/P04/P11:** ejecutar pruebas G3 en runner PostgreSQL 17.6 autorizado o conservar `NO_VERIFICADO`; en paralelo validar semántica de NOT/NULL/UNKNOWN y colisiones sin inventar operadores.
4. **P06/G4:** agotar adquisición de evidencia competente por `rule_ref+scope+consumer+version` antes de solicitar owner; no sustituir aprobaciones con score, origen textual ni alias técnico.
5. **P07/G5:** solo fichas e inventario estructural hasta G4. No cortar 8.852 relaciones por `es_transversal`.

## 9. Fuentes canónicas de este plan (no copiadas ni sustituidas)

- `IG_N4_TREMED_PENDIENTES_ATOMICOS_DEV_20261028.md` (13 P y estados originales)
- `IG_N4_TREMED_CONTRATO_ESTRATEGIA_DEFINICIONES_REGLAS_V2_20261028.md` (glosario, ejes A–F, H01–H15)
- `IG_N4_TREMED_G2_AUDITORIA_Y_AJUSTES_DE_CONTRATO_V21_20261028.md` (F01–F06, H16–H21, corrección de precedencia)
- `IG_N4_TREMED_PRECLASS_GATES_Y_CASOS_V2_20261028.md` (G0–G5, S01–S14)
- `IG_LOTE_A_STATUS_EVIDENCIA_20261028.md` (P00, P01, P02, P07 evidencias históricas)
- `IG_G4_PAQUETE_REVISION_CONJUNTA_AUTORIDAD_POR_REGLA_20261028.md` y `IG_G4_REGISTRY_REUSE_REAL_AUTHORITY_GAP_20261028.md`.
- `IG_N4_G3_ACL_HANDOFF_REVISION_INDEPENDIENTE_V3_20261028.md`, con hashes exactos de G3.
- EKB leído vivo: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`, `IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`, `IG-TARGETED-EVIDENCE-BEFORE-HUMAN-ESCALATION-001`.

## 10. Adenda de ejecución P08/P10

> **CONTINUIDAD P10, cambio de PROCESO implementado en sandbox (2026-10-28):** se añadió [límite forward-only](../../sandbox/lf_contract_gate_test/input_governance/ig_p10_forward_only_scope_boundary_candidate_20261028.sql), que congela pares implícitos y asociaciones explícitas actuales (sin reclasificarlas), reemplaza ambas rutas efectivas para impedir que asociaciones nuevas de CANDIDATO o globalidad por frecuencia/PASS_GLOBAL se conviertan en alcance operativo, y guarda futuras publicaciones ACTIVE, promociones con vínculos y enlaces a reglas VIGENTE. **No se reevalúan ni corrigen históricas.** La [prueba SQL read-only de 17 casos](../../sandbox/lf_contract_gate_test/input_governance/ig_p10_forward_only_scope_boundary_readonly_regression_20261028.sql) pasó 17/17; mutación rechazó 2 casos; 58 pantallas/15.028 vínculos originales/8.852 pares congelados/0 diferencias. La [fixture PG17.6](../../sandbox/lf_contract_gate_test/input_governance/ig_p10_pg17_6_process_fixture_20261028.sql) y el [runner con DML real, ROLLBACK y 11 aserciones](../../sandbox/lf_contract_gate_test/input_governance/ig_p10_pg17_6_isolated_runner_20261028.sh) están versionados **NO EJECUTADOS** por ausencia local de Docker. El SQL anterior de eliminación global masiva ahora falla deliberadamente. **P10=IMPLEMENTADO_CANDIDATO_SIN_CERTIFICACION_PG; integración y autoridad G4 pendientes; P10 no CLOSED.**

**Actualización técnica del mismo proceso:** preflight de base aislada antes de cualquier bloqueo; PostgreSQL 17.6 exacto y 4 hashes; transacción con SHARE LOCK de `reglas`, `reglas_pantallas`, `pantallas`, `modulos` y `app_shells` antes de leer los datos, `lock_timeout=5s`. El fixture añade `app_shells`. Runner actualizado a **11 aserciones**, incluida lectura real de `pg_locks` para los cinco bloqueos. **Runner P10 aún NO EJECUTADO**; PASE no ejecuta controles de dominio durante la ventana de reparación y paridad sigue SKIPPED. Se conserva la separación construcción sandbox / admisión y el no-go para producción.


### Descubrimiento sin cambio de gates

Se completó lectura de fuentes reales de `fn_t_remed_promote_v1` (dos sobrecargas), `fn_t_remed_promote_v3`, `fn_t_remed_rule_promotion_verdicts_v1`, `fn_t_remed_global_rules_v1` y `fn_input_effective_rule_links_v1`. Evidencia y casos negativos: [P08/P10: promoción técnica no autoriza scope](./IG_N4_P08_P10_MAPEO_CONSUMIDORES_PROMOCION_RIESGO_NO_SCOPE_20261028.md).

**Riesgo condicional concreto:** la promoción de una regla sin selector a `VIGENTE` puede colocarla en el resolvedor global por frecuencia, porque la rama `DERIVED_GLOBAL` no verifica un selector N-4. Corte SELECT: 166 reglas CANDIDATO sin selector objeto, 18 con al menos 5 vínculos físicos, 12 con al menos 15 de las 58 pantallas (umbral 25%). No implica que esas 12 tengan `verdict=PASS`: la consulta de veredictos fue denegada por ACL, SQLSTATE 42501. **P10 permanece NO HECHO formalmente y se prioriza su cierre técnico antes de integración**; P08 sigue PARCIAL. No promover ninguna regla ni inferir autoridad.

**Progreso documental confirmado:** H01–H21 correlacionadas con escenarios o brechas en [trazabilidad G0–G2](./IG_N4_G0_G2_TRAZABILIDAD_H01_H21_S01_S14_V1_20261028.md). Nueve contrapruebas de integración propuestas, todavía NO EJECUTADAS. La clasificación de estado G0–G5 y P00–P12 no se altera por publicar estos documentos.

## 11. Corte posterior P10 / G4 — evidencia ejecutada

**Fecha: 2026-10-28.** Esta adenda actualiza el corte del plan sin reescribir resultados históricos anteriores. Fuente: PR #3269, contenido del SQL candidato P10 por Git blob, EKB vivo y SQL G4 read-only; **no supone cierre G4 ni autorización productiva**.

- **P10 proceso prospectivo en aislado: APROBADO TÉCNICAMENTE.** PostgreSQL 17.6 GitHub Actions [40788761710](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/40788761710), 11/11 casos reales y rollback. Regresión read-only 17/17; cuatro blobs conservados tras sync de main. El dictamen de revisión independiente externa confirma integridad, prueba documental del productor y regresión sombra, sin segunda PG independiente; el owner aceptó **no imponer segunda ejecución** para avanzar en construcción. Eso no convierte G4, ACL/integración ni producción en PASS.
- **PASE exact-head previo de handoff: SUCCESS**, [run 40790329461](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/40790329461). `MIGRATION_SOURCE_PARITY=SKIPPED` permanece explícito. Cada commit posterior requiere su propio estado PASE; no trasladar el PASS sin leer CI.
- **G4-SOURCE investigación ejecutada:** cinco reglas reales `REG_SES_001`, `REG_ABT_004`, `B2B-RULE-AUTH-001`, `B2B-RULE-DESIGN-001`, `B2B-RULE-STORY-READINESS-001` consultadas por SELECT vivo. Las cinco están VIGENTE y ninguna acredita ruta y política de autoridad ACTIVAS para `RULE_APPLICABILITY_CHANGE`; decision VIGENTE de Design System = referencia de fuente, **no delegación de modificar selector**.
- **G4 falso positivo evitado:** `POL-PROFILE-UPDATE-PASS` en `lf_policy_versions` sí declara `governance_authority_binding=OWNER_ROLE_ONLY_NOT_HUMAN_DECISION` para otro flujo, pero jamás autoriza scope de Input Governance. Auditor reproducible `sandbox/lf_contract_gate_test/input_governance/ig_g4_source_authority_reuse_negative_regression_20261028.sql`: 5/5 PASS, SELECT-only. Los cinco controles son negativos y miden detección correcta de ausencia/contaminación de autoridad, **no** aprobación de ninguna regla.
- **Siguiente G4 implementable:** homologar binding exacto desde fuente competente real `rule_ref+rule_version+operation+scope+consumer+delegation/revocation` hacia el registro humano existente `private.lf_human_decision_*`. Mientras no exista, `HOLD_NO_SCOPE_AUTHORITY` para **nuevas ampliaciones**; no crear owner universal, registros paralelos ni recibos ficticios. No revisar pantallas históricas ni reclasificar G5 en este proceso.

## 12. G4 — EKB recurrencia y contrato de autoridad (2026-10-28)

**Resultado de este lote (fuente PR #3269):**
- EKB vivo leído antes de actuar. Hallazgo recurrente en `HUMAN-DECISION-POLICY-RESOLUTION-NO-PRODUCER-AUTHORITY-001` y `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, sin duplicar códigos. Expediente de recurrencia: `docs/t-remed/IG_N4_G4_EKB_RECURRENCIA_GOBERNADA_20261028.md`, `PENDING_GOVERNED_WRITE`; **no se invocó ni simuló** `lf_write_pipeline_ekb_v1` por tratarse de conector Supabase de solo lectura y faltar una ejecución legítima de `ESCRITURA_BASE_CONOCIMIENTO_LF`.
- **G4-SOURCE**: consulta SQL viviente 5/5 PASS de rechazo de delegaciones ajenas; no aprueba ninguna regla nueva. Código bajo `sandbox/lf_contract_gate_test/input_governance/ig_g4_source_authority_reuse_negative_regression_20261028.sql`.
- **G4-PROBE**: `ig_g4_authority_contract_probe_v1.py` + `test_ig_g4_authority_contract_probe_v1.py`; **20/20 pruebas sintéticas** ejecutadas en Python local con SHA Git blob exacto publicado (`cdd134053d3132425de09ba4080e655c3cb14661` / `30c2edd1784f0ac115bd5dcfa81bc21f33bf2c79`). `PROOF_READY_FOR_TECHNICAL_ADMISSION` en tests **no es firma, permiso ni autorización real**: `verify_source` y `verify_receipt` son callbacks simulados en las pruebas y solo podrían conectarse a verificadores canónicos en una fase gobernada.
- PASE para commit que incorporó ambos archivos `64d47421d407c417e3b9e6de2121d4aa47b00d7b`: [run 40793071399](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/40793071399) **SUCCESS**, `MIGRATION_SOURCE_PARITY=SKIPPED`. El commit del presente documento requiere su propio CI.
- **Próximo paso G4**: homologar la procedencia y competencia con las políticas versionadas actuales y el caller autorizado de `private.lf_human_decision_*`; verificar un ejemplo real positivo y negativos sin inventar autoridad, firma, rol o política. Hasta entonces, nuevas ampliaciones `HOLD_NO_SCOPE_AUTHORITY`, G5 sin reclasificación.

## 13. IG RUN único desde inicio de Input Governance — corrección owner (2026-10-28)

**Ejecución raíz de IG comienza en IG, no en Router.** Router enruta y pasa contexto. El Curator gobernado de IG crea el `run_id` en `programacion.input_readiness_runs` en estrategia de materialización, o reutiliza un run actual en NOOP; Validator recibe el mismo `p_run_id`. G4 es un control condicional de cambio nuevo de selector dentro de **ese mismo run IG**, no un nuevo run ni una verificación de identidad de cada fase. Las continuaciones reanudan ese run; estados/fases actuales no se alteran. `execution_id` del perfil/Router puede aparecer en evidencia del consumidor y NO es identidad padre ni prerequisito de G4.

**Corrección material hecha en el mismo lote:** se quitó del probe sandbox la obligación de `execution_id`, callback `verify_run_binding` y acoplamiento recibo de autorización↔run. El run IG sigue presente para trazabilidad; la autorización se comprueba por la fuente/regla/selector/consumidor y competencia vigente, sin segunda autenticación. Probe y tests en GitHub blobs `199692ad7278d53924935de485b8061f205f4aae` / `ac7d63b0448e320397c2fe45b544ddd4ded716f8`; **24/24 pruebas sintéticas locales PASS**. PASE se comprobará contra el HEAD exacto del lote.

**Frontera actual:** diseño y sandbox, no fuente/recibo reales conectados, no publicación productiva ni activación G4. EKB vivo aún no fue escrito. Ver [G4 sección 8 corregida](./IG_G4_RULE_SCOPE_APPROVAL_CONTRACT_V1_20261028.md). La investigación e implementación de la autorización competente continúan sobre el mecanismo existente; no se vuelve a exigir identidad padre del perfil ni se generan runs adicionales.
