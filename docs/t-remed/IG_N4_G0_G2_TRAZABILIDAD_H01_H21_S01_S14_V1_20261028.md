# LF IG N-4 — G0/G1/G2: trazabilidad normativa H01–H21 ↔ S01–S14
**Fecha:** 2026-10-28 | **PR #3269 DRAFT** | **Estado:** auditoría de diseño, NO_RATIFICADO, NO_RECLASSIFY  
**Fuente:** Contrato v2 + adenda G2 v2.1 F01–F06/H16–H21 + protocolo G0–G5 S01–S14 + EKB vivo.  
**Plan padre:** [Plan maestro único G0–G5 / P00–P12](./IG_N4_TREMED_PLAN_MAESTRO_EJECUCION_V1_20261028.md).

## Alcance y metodología

Es trazabilidad **de cobertura del diseño**, no ejecución ni certificación. Un escenario S definido en un documento es solo una especificación. Una prueba Txx del matcher o un doble JS tampoco certifica el pipeline completo, el ACL post-DDL ni la autoridad. La matriz identifica cada H, su P dueño, escenarios existentes, falta observada y falsación necesaria. No cambiar retrospectivamente el conjunto S01–S14 ni alterar sus oráculos para obtener PASS; los subcasos adversariales propuestos se añaden de forma explícita y versionada cuando sean aceptados.

| Norma | P dueño | Escenarios existentes que la rozan | Estado de cobertura del contrato | Contraprueba o evidencia necesaria antes de G2/G3 |
|---|---|---|---|---|
| H01 Sin global por frecuencia | P01,P07 | S02,S05 | PARCIAL: casos lógicos redactados | Regla popular con 1 o 100 asociaciones no amplía scope; comparar resolver real |
| H02 Selector+consumer autorizados | P02,P08 | S11,S12 | PARCIAL: S11 prueba CANDIDATO; no consumer ajeno integral | Consumidor no permitido, selector UNRESOLVED, policy CANDIDATO; sin bypass |
| H03 Nueva pantalla compatible | P02,P07 | S04,S05 | DISEÑADO; sin ejecución nueva pantalla efectiva | Nueva pantalla compatible hereda sin editar SQL; igual módulo incompatible no |
| H04 Asociación física no es autoridad | P07,P08 | S05 (indirecto) | BRECHA EXPLÍCITA de S01–S14 | Vínculo `reglas_pantallas` histórico sin scope autorizado no debe crear nuevo alcance |
| H05 Contexto solicitado por regla | P02 | S06,S07 | DISEÑADO; faltan fuentes canónicas | Falta de sesión → HOLD sesión; regla visual válida continúa; pantalla sin módulo |
| H06 NOT sobre desconocido | P03 | S12 | DISEÑADO; operador no implementado | `NOT(NULL)`/path omitido no da MATCH; no crear NOT sin caso real |
| H07 Acumulación/deduplicación | P04 | S08,S09 | PARCIAL (compatibilidad sí, equivalente no explícito) | Duplicados con distinta procedencia no pierden obligaciones ni auditoría |
| H08 Conflicto sin precedencia | P04 | S09 | DISEÑADO; sin evaluación de autoridad real | Inversión del orden SQL mantiene HOLD; fuente de precedencia ausente |
| H09 Prohibición superior/veto | P04,P06 | S10 | DISEÑADO; sin recibo auténtico | Override local no neutraliza obligación superior no delegable |
| H10 Gerencia no por match/score | P05,P06 | S13 | PARCIAL (score no autoriza) | Un MATCH nuevo de selector ya aprobado no crea nueva solicitud; cambio sí |
| H11 Promoción técnica no da scope | P09,P10 | S11 | DISEÑADO; falta funciones promote v1/v3 | CANDIDATO→VIGENTE nunca convierte regla en GLOBAL automáticamente |
| H12 Lifecycle de pantalla/regla | P09,P08 | S11 (solo candidato) | BRECHA EXPLÍCITA | Pantalla inactiva, obsoleta o duplicada no dispara acciones operativas; análisis puede conservar |
| H13 Currentness/versionado | P00,P06,P09 | S13 (indirecto) | BRECHA EXPLÍCITA | Cambio de SHA de policy/selector/owner invalida recibo anterior; revocación efectiva |
| H14 No crear motor paralelo | P03,P04,P06 | S14 | PARCIAL (evolución, no prueba de reutilización) | Nueva naturaleza genera MODEL_GAP, no motor adicional; revisar piezas existentes |
| H15 Aislar consumer/policy ref | P08 | S11 (indirecto) | BRECHA EXPLÍCITA | Identidad `consumer_role` no autorizada vs campo `profile_code`; policy ajena |
| H16 UNKNOWN y JSON null | P02,P03 | S03,S07,S12 + T07–T09 | DISEÑADO; shadow parcial | NULL, ausencia y FALSE reales separados en diagnóstico; ninguno concede aplicabilidad |
| H17 Gramática fail-closed | P03,P11 | T23–T28, fuera de S01–S14 | BRECHA explícita en casos de integración S | Cláusula con `extra_guard`, operador desconocido, any corto-circuitado inválido: rechazo |
| H18 Selector tautológico/universal | P02,P06 | S01 (caso legítimo amplio) | BRECHA: contraste inválido vs universal legítimo | `EXISTS(target)` solo no habilita universal; autorización de cobertura total sí puede |
| H19 ID local vs reusable | P01,P02 | S04,S05 | DISEÑADO; sin nueva pantalla en runtime | ID puntual válido si realmente local; reusable con capacidades no depende de ampliar lista |
| H20 ACTIVE ≠ autoridad | P06,P09 | S11 (estado) | BRECHA: falta sello competente | Selector `ACTIVE` sin receipt/version/scope no pasa publicación, aunque MATCH=true |
| H21 Matching ≠ precedencia ni lifecycle | P04,P08,P09 | S09,S10,S11 | PARCIAL: cubre partes, no composición integrada | Conflicto, candidato e invalid context tratados como controles independientes |

## Hallazgos normativos que requieren resolución antes de ratificar

1. **Precedencia v2 versus adenda v2.1:** el contrato v2 describe heurística `normativa > legal/seguridad > gerencia > especificidad`. La adenda v2.1 **prohíbe usar esa secuencia como orden universal** sin fuente de competencia, efecto, delegación y policy. Para una ratificación válida, preferir la adenda: incompatibilidad sin competencia probada → HOLD, no seleccionar por el orden de categorías.
2. **Tres valores conceptuales versus booleano vigente:** el lenguaje propone `MATCH/NO_MATCH/UNKNOWN` en diagnóstico, pero el matcher operativo actual es booleano. No cambiar firmas del runtime sin prueba de necesidad y compatibilidad; la admisión fail-closed debe impedir que UNKNOWN se transforme en autorización.
3. **Universalidad legítima:** proteger contra `EXISTS(target)` tautológico no debe impedir una política de aplicación general **si existe autorización real**. La gramática sola no puede reemplazar la decisión de scope.
4. **Owner y recibos:** `private.lf_human_decision_*` es un registro reutilizable, pero las rutas `INPUT_GAP_PROPOSAL` y sus recibos no prueban competencia de scope N-4. No usar `provenance.authority` textual, `created_by`, score ni JSON `ACTIVE` como firma.
5. **Contextos no disponibles:** no agregar `session`, `onboarding`, `payments` a todas las pantallas. Cada condición debe identificar fuente canónica, freshness, negativas y consecuencias de ausencia según la regla.
6. **No confundir cobertura con ejecución:** el paquete S01–S14 puede prepararse íntegro, pero sin ruta real de owners, consumidores y pruebas PG ACL el gate G3 sigue NO_VERIFICADO para esos aspectos.

## Subcasos de falsación propuestos (no son nuevos checkpoints ni S históricos aprobados)

| Eje a reforzar | Subcaso propuesto | Condición de éxito |
|---|---|---|
| S05 / H04 | Legacy explícito sin selector autorizado | Ninguna ampliación a destino nuevo; preservar evidencia histórica |
| S08 / H07 | Duplicado equivalente con owners distintos | Sin doble efecto; conservar provenance y estado de ambas |
| S11 / H12 | Pantalla inactiva en consumer operativo vs analítico | Diferenciar salida; sin ejecución accidental |
| S13 / H13 | Reutilizar receipt tras cambiar SHA | HOLD/INVALID, no aceptar receipt stale |
| S11 / H15 | `consumer_role` no permitido y asset_id como consumer | REJECT sin reducir protección ni cambiar validación runtime |
| S12 / H17 | Cláusula inválida oculta por ANY coincidente | FAIL CLOSED, no corto circuito de validación |
| S01 / H18 | Tautología sin competencia versus universal con recibo válido | Negativo y positivo diferenciados, con alcance probado |
| S11 / H20 | `ACTIVE` sintáctico sin owner/recibo | MATCH técnico ≠ publicación autorizada |
| S09 / H21 | Dos efectos incompatibles, uno candidato y otro vigente | Separación de estado y veto, sin gana por orden |

Estos subcasos **no modifican el protocolo S01–S14**; requerirán evidencia de ejecución independiente contra la implementación integrada. No declararlos PASS solo por estar descritos.

## Definición de listo para ratificación G0–G2

- Cotejo exacto de H01–H21 con fuente/provenance/actualidad, criterios de falsación y S01–S14; resolver conflictos anteriores con decisión versionada.
- Negativos para F01–F06, incluida ausencia vs JSON null, clave extra, tautología, reutilización dinámica y ACTIVE falso.
- Matriz de roles/autoridad por **competencia probada**, no cargos nominales; separación entre preparación Curator, verificación Validator y firma competente.
- Mensaje de salida: `READY_FOR_AUTHORITY_REVIEW`, **no** `G2_APPROVED` ni `G5_RECLASSIFY`.

**Dictamen de esta revisión de diseño:** 21/21 normas correlacionadas con contrato y prueba o brecha; **cero ratificadas por esta auditoría**. G0/G1/G2 preparación documental; G3 integración y ACL pendiente; G4 no verificada; G5 bloqueada.
