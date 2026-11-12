# LOTE 12 — Auditoría de calidad de reglas reales LF y SALY
**Estado:** UNVERIFIED. **Operación:** solo lectura Supabase vivo; únicamente documentos/JSON/SQL en nueva rama GitHub. **No es PASS.**

## Proveniencia y fuente
- Auditor operativo: asistente GPT-6 en este chat paralelo. El rol solicitado como “Claude auditor” **no acredita identidad Claude ni juez externo**. No se utilizó un revisor externo. Independencia de ejecución respecto del chat Lote 11 por separación de rama y alcance; independencia de modelo NO acreditada.
- EKB consultado: `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4`, estado de fuente CANDIDATO VERIFICADO PARCIALMENTE. Precedencia de contratos live; no RUN ni promoción.
- Repo: `cristhianlujan/claude-persona-lf-patch`. Rama base `lf/issue-3779-lote4b-validator-reuse-audit-v1`; HEAD capturado al crear rama: `de0021609c543a78b416e6c3e92475797dcae3bd`.
- Única rama de escritura: `lf/issue-3779-lote12-rule-quality-audit-v1`. No se ha tocado la rama base ni la PR #3797 (DRAFT/NO-GO).
- SQL 100% `SELECT`, ejecutado mediante conexión RO de Supabase. Referencia de corte LF: 2026-11-12 18:11:32.298595+00; SALY: 2026-11-12 18:13:14.861063+00.
- Las **27 consultas** tienen SQL, filas RAW y SHA-256 de la consulta y del resultado (archivos 01, 02, 03). Un cero devuelto por detector heurístico no equivale a ausencia de defecto real.

## Cinco hallazgos de mayor impacto
1. **[OBJETIVO | LF13]** Tres reglas VIGENTE referencian reglas CANDIDATO mediante identificadores `*_rule_id`. La consecuencia funcional **REQUIERE_REVISION_SEMANTICA**. Se registran 34 referencias numéricas, de las cuales 30 tienen destino CANDIDATO (la mayoría tienen origen también CANDIDATO).
2. **[OBJETIVO | LF01, LF14]** 57 reglas VIGENTE conservan `pendiente_decision=true`. Abajo se incluye la lista íntegra y antigüedad medida desde `updated_at`.
3. **[OBJETIVO para mapeo | LF15, LF16]** 43 reglas marcadas NO transversales carecen de relación en `lf_ops.reglas_pantallas`. Cobertura efectiva: **REQUIERE_REVISION_SEMANTICA**, porque podría existir otro consumidor.
4. **[OBJETIVO | LF01–LF05]** 76 categorías exactas, 73 tras normalizar mayúsculas, 19 categorías unitarias (el dueño señaló 18: diferencia **+1**), 3 grupos de variantes por casefold y 4 pares inglés/español.
5. **[OBJETIVO como antigüedad de edición | LF01]** 256 reglas VIGENTE no actualizadas en >90 días y 161 CANDIDATO no actualizadas en >30 días. **NOT_MEASURABLE** el número realmente “sin revisar”: `updated_at` no prueba última revisión.

## Conciliación contra referencia del dueño
| Métrica | Referencia | Consulta propia | Dictamen |
|---|---:|---:|---|
| Reglas LF | 578 | 578 | COINCIDE |
| VIGENTE / CANDIDATO | 412 / 166 | 412 / 166 | COINCIDE |
| Categorías exactas / casefold | 76 / 73 | 76 / 73 | COINCIDE |
| Categorías unitarias | 18 | 19 | **DIFIERE +1** |
| Categorías seguridad ampliada | 105 en 8+ | 105 en 10 categorías declaradas en LF06 | COINCIDE conteo bajo taxonomía propuesta |
| Config vacía / razón vacía / origen vacío | 32 / 12 / 6 | 32 / 12 / 6 | COINCIDE |
| `created_by` nulo | 274 | 274 | COINCIDE |
| Grupos título / descripción duplicados | 3 / 0 | 3 / 0 | COINCIDE |
| VIGENTE pendiente_decision | 57 | 57 | COINCIDE |
| CANDIDATO sin editar 30 d | 161 | 161 | COINCIDE (proxy edición) |
| VIGENTE sin revisar 90 d | 256 | 256 sin editar | COINCIDE solo proxy; revisión NOT_MEASURABLE |

## Conexiones activas a reglas aún candidatas
| Regla origen VIGENTE | Campo | Destino | Estado destino |
|---|---|---|---|
| `B2B-RULE-AUTH-016` | `duplicate_submit_rule_id` | `B2B-RULE-AUTH-012` | CANDIDATO |
| `B2B-RULE-AUTH-022` | `mfa_gate_rule_id` | `B2B-RULE-AUTH-018` | CANDIDATO |
| `B2B-RULE-THEME-003` | `dark_promotion_gate_rule_id` | `B2B-RULE-THEME-002` | CANDIDATO |

## Candidatos de control débil: heurística LF09
- `REG_CHK_001`: El checkout consolida las ofertas y modalidades seleccionadas en un único resumen. (**REQUIERE_REVISION_SEMANTICA**)
- `REG_OFR_001`: Una oferta representa una deuda negociada independiente. (**REQUIERE_REVISION_SEMANTICA**)
- `REG_OFR_002`: Pago único y cuotas son modalidades de la misma oferta, no ofertas distintas. (**REQUIERE_REVISION_SEMANTICA**)
- `REG_OFR_008`: En multi oferta, el usuario puede seleccionar una o varias ofertas. (**REQUIERE_REVISION_SEMANTICA**)

Criterio: no aparecen términos normativos, números, umbrales ni condiciones cubiertos por la expresión regular, y la configuración carece de claves operativas según la exclusión declarada. Es un detector conservador, no un juicio semántico completo.

## Pares de igual parámetro + distinto valor (LF10)
**20 pares concretos**, todos con ambos extremos VIGENTE y al menos una pantalla compartida. **REQUIERE_REVISION_SEMANTICA**: estos valores pueden referirse a entidades u operaciones diferentes, por lo que **no se confirman contradicciones**.

| Regla A | Regla B | Parámetro | A | B | Pantallas comunes |
|---|---|---|---:|---:|---:|
| `REG_ALR_001` | `REG_RATE_002` | `ventana_minutos` | 30 | 10 | 23 |
| `REG_ALR_001` | `REG_RATE_003` | `ventana_minutos` | 30 | 60 | 23 |
| `REG_ALR_001` | `REG_SES_003` | `ventana_minutos` | 30 | 5 | 23 |
| `REG_ALR_002` | `REG_ALR_004` | `umbral_maximo` | 0.8 | 0.05 | 23 |
| `REG_ALR_004` | `REG_RATE_001` | `ventana_minutos` | 15 | 10 | 23 |
| `REG_ALR_004` | `REG_SES_003` | `ventana_minutos` | 15 | 5 | 23 |
| `REG_RATE_001` | `REG_SES_003` | `ventana_minutos` | 10 | 5 | 23 |
| `REG_RATE_002` | `REG_RATE_003` | `ventana_minutos` | 10 | 60 | 23 |
| `REG_RATE_002` | `REG_SES_003` | `ventana_minutos` | 10 | 5 | 23 |
| `REG_RATE_003` | `REG_SES_003` | `ventana_minutos` | 60 | 5 | 23 |
| `REG_ALR_001` | `REG_ALR_004` | `ventana_minutos` | 30 | 15 | 22 |
| `REG_ALR_001` | `REG_RATE_001` | `ventana_minutos` | 30 | 10 | 22 |
| `REG_ALR_002` | `REG_ATQ_017` | `ventana_horas` | 1 | 24 | 22 |
| `REG_ALR_002` | `REG_RATE_004` | `ventana_horas` | 1 | 24 | 22 |
| `REG_ALR_004` | `REG_RATE_002` | `ventana_minutos` | 15 | 10 | 22 |
| `REG_ALR_004` | `REG_RATE_003` | `ventana_minutos` | 15 | 60 | 22 |
| `REG_ALR_005` | `REG_ATQ_017` | `ventana_horas` | 1 | 24 | 22 |
| `REG_ALR_005` | `REG_RATE_004` | `ventana_horas` | 1 | 24 | 22 |
| `REG_RATE_001` | `REG_RATE_003` | `ventana_minutos` | 10 | 60 | 22 |
| `REG_RATE_002` | `REG_RATE_004` | `max_intentos` | 10 | 3 | 22 |

## VIGENTE con decisión pendiente y días desde último cambio (LF14)
La antigüedad de edición no prueba antigüedad de decisión ni revisión. Cortes basados en reloj de base de datos.
| Código | Días sin editar | Fecha `updated_at` UTC | Detalle pendiente (truncado en esta vista; íntegro en JSON) |
|---|---:|---|---|
| `REG_ONB003_DNI_RESOLUTION_ATOMIC_001` | 85.6 | 2026-08-19 03:15:57.583892+00 | Contrato cerrado; sigue pendiente identificar/reutilizar almacenamiento canónico para enforcement atómico |
| `REG_CLIENT_DOC_DEMO_VERSIONING_001` | 85.3 | 2026-08-19 11:12:34.139903+00 | Pendiente diseñar o identificar el registro canónico Cliente para documento maestro, versiones, archivo/c |
| `REG_CLIENT_RECOVERY_IDV_OUTCOME_001` | 85.0 | 2026-08-19 17:26:34.127488+00 | Pendiente catalogar mensajes/errores Cliente y mapearlos a la futura pantalla de recuperación; no reutili |
| `REG_CLIENT_HOME_OFFER_LOAD_FAILURE_001` | 85.0 | 2026-08-19 17:33:42.729993+00 | Funcionalidad cerrada. Pendiente registrar copy/error Cliente y mapear estado OFFER_DATA_UNAVAILABLE a la |
| `REG_CLIENT_HOME_NO_OFFER_001` | 85.0 | 2026-08-19 17:37:47.344143+00 | Funcionalidad del estado sin oferta cerrada. Pendiente reconciliar HOME_003/PASO3_SIN_OFERTA con la refer |
| `REG_CLIENT_RECURRING_PAYMENT_MANAGEMENT_001` | 85.0 | 2026-08-19 17:50:17.891878+00 | Control funcional seguro cerrado; falta decisión Negocio/Legal/Operaciones sobre terminación del acuerdo, |
| `REG_CLIENT_INSTALLMENT_PLAN_SNAPSHOT_001` | 85.0 | 2026-08-19 17:51:33.510204+00 | Contrato cerrado. Falta implementar el snapshot dentro del ledger de pago/plan Cliente canónico; no crear |
| `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001` | 85.0 | 2026-08-19 17:52:30.739642+00 | Outcomes técnicos cerrados. Pendiente política Negocio/Legal de vencimiento, gracia, mora y consecuencias |
| `REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001` | 85.0 | 2026-08-19 17:52:30.739642+00 | Funcionalidad de recordatorio cerrada; pendiente definir política de anticipación/frecuencia, canales pro |
| `REG_CLIENT_INSTALLMENT_PAYMENT_DUE_001` | 85.0 | 2026-08-19 17:52:30.739642+00 | Contrato funcional cerrado. Pendiente política de ventana de pago manual, recordatorios, proveedor recurr |
| `REG_CLIENT_DEBT_SETTLEMENT_STATUS_001` | 85.0 | 2026-08-19 17:53:27.893234+00 | Estado funcional cerrado. Implementación depende del ledger Cliente y de la definición de cuándo el aliad |
| `REG_CLIENT_PAYMENT_CONFIRMED_POST_ACTIONS_001` | 85.0 | 2026-08-19 17:53:27.893234+00 | Funcionalidad post-pago cerrada. Pendiente ledger de pago/plan/deuda canónico, workflow técnico con el al |
| `REG_CLIENT_INSTALLMENT_PLAN_VIEW_001` | 85.0 | 2026-08-19 18:03:59.312114+00 | Funcionalidad cerrada. Implementación depende del ledger/snapshot de plan y de la futura pantalla Mis ope |
| `REG_CLIENT_HOME_PUBLIC_ENTRY_001` | 85.0 | 2026-08-19 18:19:21.332732+00 | Funcionalidad cerrada. Pendiente registrar ruta/shell Cliente; el CTA visual actual puede mantenerse y no |
| `REG_CLIENT_HOME_PUBLIC_LETTER_CLAIM_001` | 85.0 | 2026-08-19 18:19:21.332732+00 | Funcionalidad y límite del claim cerrados; pendiente reconciliar el texto visual bloqueado con su condici |
| `REG_CLIENT_HOME_CLARITY_CTA_001` | 85.0 | 2026-08-19 18:26:28.928781+00 | Destino funcional cerrado. Ruta Cliente/route_pattern continúa pendiente por ausencia de shell/rutas Clie |
| `REG_CLIENT_HOME_LEARN_DECIDE_001` | 85.0 | 2026-08-19 18:28:30.810422+00 | Estructura funcional cerrada. Card 1 queda con popup legal condicionado a que EDU-NODO-02-EXPLORA sea pub |
| `REG_CLIENT_HOME_FAQ_001` | 85.0 | 2026-08-19 18:30:12.828733+00 | Funcionalidad y fuentes cerradas. Copy exacto final pendiente de revisión visual/legal; FAQ 4 debe limita |
| `UX-HOME-CAPABILITY-03` | 85.0 | 2026-08-19 18:30:12.828733+00 | Semántica funcional corregida. Falta validación Legal del copy visible “sin compromiso” y su uso por supe |
| `REG_CLIENT_HOME_FOOTER_001` | 85.0 | 2026-08-19 18:32:50.896218+00 | Funcionalidad cerrada. Pendientes rutas públicas Cliente, configuración corporativa de contacto y visual  |
| `REG_CLIENT_HOME_TRUST_SOURCE_GATING_001` | 85.0 | 2026-08-19 18:35:21.300454+00 | Contrato funcional cerrado. Pendiente poblar aliados autorizados, diseñar/identificar registry de prensa  |
| `REG_CLIENT_HOME_SINGLE_OFFER_BOTH_001` | 84.9 | 2026-08-19 21:22:38.164165+00 | Contrato funcional cerrado. Pendientes: pricing/config productiva, capacidades del header, corrección vis |
| `REG_CLIENT_RECOVERY_PHONE_CONTROL_001` | 84.8 | 2026-08-19 22:50:44.357266+00 | Pantalla funcional y ruta ya canónicas: REC_001 / CLIENT_RECOVERY. Persiste el gap del mecanismo/proveedo |
| `REG_CLIENT_RECOVERY_IDV_STEPUP_001` | 84.8 | 2026-08-19 22:50:51.257327+00 | La pantalla/route de recuperación ya existen (REC_001 / CLIENT_RECOVERY). Persiste exclusivamente la sele |
| `REG_ONB001_PHONE_PREFIX_001` | 83.9 | 2026-08-20 20:29:34.275606+00 | Definir catálogo canónico de países y comportamiento del selector antes de habilitar interacción en produ |
| `REG_ONB003_CONSENT_DATA_001` | 83.8 | 2026-08-20 23:55:18.688488+00 | Ubicación y comportamiento aprobados. Antes de producción falta Legal sobre copy/modal final y arquitectu |
| `REG_ONB003_STEPPER_4_001` | 83.8 | 2026-08-20 23:55:18.688488+00 | Pendiente reconciliar por delta las referencias visuales ONB_001/ONB_002 si el owner decide que también d |
| `REG_NEW_CLIENT_DATA_COMPLETION_001` | 83.0 | 2026-08-21 17:26:14.725103+00 | CAMPO_CONSENT_DATA fue trasladado a ONB_003 por decisión 108. ONB_004 no lo repite. Sigue pendiente Legal |
| `REG_ONB004_MARKETING_INFO_MODAL_001` | 83.0 | 2026-08-21 17:26:14.725103+00 | Pendiente reemplazar los párrafos placeholder del modal por copy final validado por Legal/Contenido antes |
| `REG_CLIENT_MY_OPERATIONS_SCOPE_001` | 82.8 | 2026-08-21 22:24:48.785339+00 | Funcionalidad base cerrada. Implementación bloqueada por ledger financiero Cliente inexistente y pantalla |
| `REG_CLIENT_NO_DEBT_LETTER_STATUS_001` | 79.9 | 2026-08-24 19:28:01.886636+00 | Estados funcionales cerrados. Pendiente workflow/API del aliado, SLA contractual, registro documental Cli |
| `REG_CLIENT_HOME_SINGLE_OFFER_PAY_ONLY_001` | 79.7 | 2026-08-25 02:20:53.433049+00 | Visual, shell, pricing transparency y pantalla canónica reconciliados a HOME_002. Pendiente runtime real: |
| `REG_CLIENT_CHECKOUT_PRICING_QUOTE_001` | 79.6 | 2026-08-25 03:25:08.235796+00 | Contrato de quote cerrado para pricing base y extendido para ajustes comerciales en selection_snapshot. I |
| `REG_CLIENT_HOME_BENEFIT_OFFER_PRESENTATION_001` | 79.6 | 2026-08-25 03:25:08.235796+00 | B4 AVANZA no se vincula funcionalmente hasta definir el estado canónico de premio aplicado a deuda. B2 pe |
| `REG_CLIENT_HOME_PRICE_DETAIL_MODAL_001` | 79.6 | 2026-08-25 03:25:08.235796+00 | Visual y contrato de transparencia cerrados. Runtime de valores reales permanece bloqueado hasta existir  |
| `REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001` | 79.6 | 2026-08-25 03:25:08.235796+00 | Contrato de outcomes cerrado. Implementación bloqueada por ausencia de ledger/callback/reconciliación can |
| `REG_CLIENT_HOME_INSTALLMENT_PLAN_DETAIL_001` | 79.5 | 2026-08-25 06:50:23.826728+00 | Contrato funcional y visual B-/C cerrados para el panel pre-checkout. Pendientes runtime: configuración c |
| `REG_CLIENT_HOME_INSTALLMENT_PLAN_SELECTION_001` | 79.5 | 2026-08-25 06:50:23.826728+00 | Selección visual base y estado seleccionado B-/C cerrados. El título del plan refleja pago inicial + cuot |
| `REG_CLIENT_CHECKOUT_PROVIDER_HANDOFF_001` | 78.1 | 2026-08-26 14:59:21.670134+00 | Funcionalidad cerrada. Pendiente proveedor productivo y contrato técnico exacto de hosted fields/SDK/redi |
| `REG_CLIENT_CHECKOUT_CONFIRMING_STATE_001` | 78.1 | 2026-08-26 16:23:28.708183+00 | Funcionalidad y visual cerrados. Implementación productiva sigue bloqueada por ausencia de ledger/reconci |
| `REG_CLIENT_CHECKOUT_CARD_DATA_BOUNDARY_001` | 78.1 | 2026-08-26 16:42:30.026251+00 | Contrato visual y frontera de seguridad cerrados. Pendientes runtime: binding del proveedor productivo, c |
| `REG_CLIENT_CHECKOUT_ERROR_STATE_001` | 78.0 | 2026-08-26 18:11:25.79975+00 | Contrato funcional y visual de error recuperable cerrado para rechazo confirmado y falla previa al envío. |
| `REG_CLIENT_PAYMENT_SUCCESS_INSTALLMENTS_001` | 78.0 | 2026-08-26 18:13:43.342688+00 | Contrato funcional y visual de éxito para pago inicial de cuotas cerrado. Existe además variante visual s |
| `REG_CLIENT_PAYMENT_SUCCESS_VIEW_001` | 78.0 | 2026-08-26 18:13:43.342688+00 | Funcionalidad mínima de éxito cerrada. El destino Mis operaciones ya tiene contrato funcional, pero su pa |
| `REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001` | 78.0 | 2026-08-26 18:21:32.588413+00 | Contrato funcional cerrado. Pendiente proveedor QR productivo, API/callback de consulta y ledger/reconcil |
| `REG_CLIENT_CHECKOUT_SCHEDULE_CONTEXT_001` | 78.0 | 2026-08-26 18:21:32.588413+00 | Funcionalidad de contextos cerrada. Pendiente fuente/configuración canónica de fechas permitidas por plan |
| `REG_CLIENT_CHECKOUT_AUTODEBIT_CONSENT_CONTEXT_001` | 77.9 | 2026-08-26 20:35:15.783979+00 | Owner cerró política de producto: en CUOTAS la autorización de cobro automático es obligatoria antes del  |
| `REG_CLIENT_CHECKOUT_INSTALLMENTS_VIEW_001` | 77.8 | 2026-08-26 22:15:57.614129+00 | Contrato funcional y visual cerrado para CUOTAS=CARD_ONLY. Estados aprobados: autorización vacía con CTA  |
| `REG_CLIENT_CHECKOUT_PAY_ONLY_VIEW_001` | 77.8 | 2026-08-26 22:15:57.614129+00 | Estructura funcional aprobada. Pendiente evidencia visual, provider/config reales y pricing runtime APROB |
| `REG_CLIENT_CHECKOUT_PAYMENT_METHOD_ELIGIBILITY_001` | 77.8 | 2026-08-26 22:15:57.614129+00 | Política cerrada: CUOTAS admite únicamente CARD. Yape queda exclusivamente para PAGO_UNICO/pago directo.  |
| `REG_CLIENT_HOME_CLARITY_CONTENT_FRESHNESS_001` | 41.0 | 2026-10-02 17:43:14.180839+00 | Mecanismo de vigencia cerrado. Falta construir/identificar el registro canónico de contenido versionado p |
| `REG_CLIENT_HOME_PRIMARY_ACTION_PRIORITY_001` | 41.0 | 2026-10-02 17:43:14.180839+00 | Prioridad macro aprobada por estructura visual. Falta cerrar reglas de desempate y umbrales de proximidad |
| `REG_CLIENT_PAYMENT_REFUND_POLICY_001` | 41.0 | 2026-10-02 17:43:14.180839+00 | Principio funcional cerrado. Pendiente implementación técnica de refund: proveedor, ledger, estados, tiem |
| `REG_CLIENT_PUBLIC_LEGAL_NAV_001` | 41.0 | 2026-10-02 17:43:14.180839+00 | Pendiente crear/registrar rutas Cliente. La obligación funcional pública está cerrada; no inventar route_ |
| `REG_LF_BENEFITS_B2B_CAMPAIGN_001` | 41.0 | 2026-10-02 17:43:14.180839+00 | Pendiente definir/reutilizar estructura canónica de campaña al formalizar el módulo. No crear tabla ni pa |
| `REG_RISK_PHONE_MULTI_DNI_001` | 41.0 | 2026-10-02 17:43:14.180839+00 | Pendiente calibrar ventanas y umbrales numéricos con telemetría real/baseline antes de convertir esta señ |
| `REG_CLIENT_LIBRO_SUBMIT_001` | 38.9 | 2026-10-04 20:20:01.407106+00 | Contrato de submit cerrado. Implementación bloqueada hasta reconciliar/confirmar con Legal el Anexo I fin |

## Dependencias y coherencia
- **[OBJETIVO | LF12]** Cero campos estructurados `depends_on_rules` en `valor_config`; el campo no existe como columna directa en `lf_ops.reglas`. La verificación de dependencias por **códigos** en ese supuesto campo es **NOT_MEASURABLE** por ausencia de dato.
- **[OBJETIVO | LF13]** Sí se pudo medir un subconjunto distinto: referencias numéricas top-level `*_rule_id` contra `lf_ops.reglas.id`; destinos existentes pero CANDIDATO registrados en JSON. No suponer que las referencias numéricas agotan todas las dependencias transitivas.
- **[OBJETIVO | LF12]** 1 regla tiene `dependency_status=MISSING` explícito, distinto de demostrar una dependencia rota por código.
- **[OBJETIVO del patrón, NO de coherencia global | LF11]** 0 discordancias numéricas detectadas entre texto `parametro (=|:|de|es) número` y `valor_config`. **Contradicciones semánticas reales: NOT_MEASURABLE con SQL lexical solamente**. La unidad, entidad y ámbito requieren revisión humana o juez acreditado.

## Comparativo genérico SALY (14 reglas; SQL SALY01–10 y SCHEMA01)
| Criterio | LF | SALY | Interpretación |
|---|---|---|---|
| Texto normativo | `descripcion` | `regla` | Adapter, no hacer UNION por misma columna |
| Vigencia | `estado='VIGENTE'` | `vigente=true` y `estado` | No equivalencia automática entre estados |
| Categorías | 76 | 3 | Taxonomías distintas |
| Configuración vacía | 32 | 2 | Misma condición JSON |
| Decisión pendiente | `pendiente_decision` | sin tal columna | **NOT_MEASURABLE** en SALY; `decision_id` NO equivale |
| Creador | `created_by` | sin tal columna | No imputar 14 nulos |
| Fuente | `origen` | `fuente` | Semánticas de procedencia distintas |
| Fecha última revisión | no acreditada | no acreditada | **NOT_MEASURABLE** en ambas |
| Antigüedad >90 días sin editar | 256 VIGENTE | 0 | Proxy, no revisión |

En SALY: 14 reglas; 14 `vigente=true`, 2 configs vacías, 0 fuentes vacías, 0 sin decisión ID, 14 sin editar >30 días, 0 sin editar >90 días. 0 candidatos de control débil, 0 pares de mismo parámetro con valor diferente dentro de una categoría, 0 discrepancias numéricas por patrón, 0 duplicados exactos de título, 0 de texto. Cobertura sólo del detector declarado. Versiones: V1.0=1, V2.3=13.

## Propuesta NO aplicada: familias + ciclo de vida
- `04_familias_lf.csv`: 76 categorías a **15 familias propuestas**; asignación exhaustiva y sin duplicados de clave. `04_familias_saly.csv`: 3 categorías conservadas sin forzar fusión entre productos. Familias: hipótesis de taxonomía, no dictamen semántico.
- **Nueva familia:** sólo ante frontera demostrable distinta en sujeto, alcance, control y owner; registrar evidencia de dos o más reglas representativas (excepción: obligación legal autónoma), reglas de precedencia, consumidor, referencia de decisión y plan de búsqueda de duplicados.
- **Fusión:** equivalencia demostrada de sujetos, controles y precedencia + evaluación de consumidores/impacto + dictamen del dueño; mantener alias de transición y plan reversible. Mayúsculas, traducciones o valores similares no bastan para fusionar.
- **Crecer/mejorar:** regla vigente con versionado y sucesora explícita, propietario, evidencia, casos positivos/negativos, histórico y revisión de regresión; primero comparar y decidir, nunca editar por coincidencia de palabra.
- **Caducar/retirar:** `reviewed_at`, `next_review_at`, `effective_from/to`, causa de vencimiento, referencias a reemplazo y política por tipo de control. Ningún dato actual acredita esos ciclos en las dos tablas `reglas`. **Propuesta documental, cero DDL/DML.**

## Reproducción + límites
- Ejecutar únicamente `SELECT` de 01/02/03 SQL, mantener sus filtros y `ORDER BY`, comparar filas de los JSON de lectura del mismo instante. Se incluyen SHA-256 por consulta y por resultado; el digest de SQL se calcula sobre su texto más `semicolon+LF`, resultado sobre `JSON.stringify(rows)` UTF-8.
- SQL con datos de hoy y comparación con `now()` puede cambiar mañana; para reproducibilidad temporal exacta, guardar una instantánea bajo permiso en entorno de pruebas (no autorizada aquí). La comparación posterior debe reportar `as_of` y diferencias.
- **NO-GO / UNVERIFIED** hasta validación del banco independiente del dueño. No hubo juez adicional, cambios oficiales, gate, RUN, CI, merge ni producción. No se autoriza promoción por esta auditoría.
