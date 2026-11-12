# LF — Dossier L21 incorporado, estados actualizados en Lote 27

**Dossier documental:** fuente L21 reproducida en L27, NO-GO / UNVERIFIED; **sin firmas autenticadas**. Todo lo necesario para una decisión está reunido en esta carpeta, sin solicitar que el dueño lea las 578 reglas.

## Lectura ejecutiva de una página

| Indicador | Valor | Carácter |
|---|---:|---|
| Decisiones en registro | **32** (12 L16 + 8 L19 + 12 L21) | 3 decididas en conversación, 1 recomendada sin confirmar, 28 pendientes |
| Bloqueos identificados | **14** + gate de liberación | REQUIERE_REVISION_SEMANTICA |
| Familias LF propuestas | **15** | L16, no aprobadas |
| Pertenencias dudosas | **23** | L16, no dictaminadas |
| Reglas LF | 578 (412 VIGENTE,166 CANDIDATO) | OBJETIVO S21_01 |
| Reglas SALY | 14 vigentes | OBJETIVO S21_01 |
| RUN IN_PROGRESS | 232; 184 con >30d; 8 leases vencidos | OBJETIVO S21_01 |
| Asignaciones usuario-perfil (tablas examinadas) | 0 | OBJETIVO S21_01 |
| Política factor MFA #19 | CANDIDATO | OBJETIVO S21_03 |
| Campos lifecycle en fuentes | LF 4 faltantes; SALY 5 faltantes | OBJETIVO S21_02 |
| Compatibilidad de funciones legacy | 4 existentes; compatibilidad post-migración NO_PROBADA | OBJETIVO S21_04 + juicio |
| Avance de cobertura de etapas PG18 L18/L20 | 15/36 = **41,7%** REAL_EN_SANDBOX | DOCUMENTADO L18/L20 |
| Suites PG18 L20 | 18/18 scripts PASS (solapados) | REAL_EN_SANDBOX |
| E2E producción acreditada | 0/36 etapas-escenario, no significa 0% producto | NO_PROBADO |
| Firmas del dueño | **0/32** acreditadas | NO_GO / UNVERIFIED |

### Condición de MFA

La **recomendación C NO CONFIRMADA** sugiere mantener **AUTH-022→AUTH-018** como dependencia identificada (**opción C redefinida en este dossier**), con fail-closed y sin promoción. El destino AUTH-018 sigue CANDIDATO y la política 19 de elegibilidad del factor también CANDIDATO. Requisitos previos para promoción: SAML/IdP administradores, Brevo OTP, ADR-003 M1 decidido, policy 19 VIGENTE y pruebas negativas de sesión prematura. Los **11 candidatos MFA** son contexto confirmado por el dueño, no reconteo independiente de este lote.

### Lo que NO está listo

La identidad de L17 es HMAC/JWT sintético; Router/Perfil/RUN/IG/Step70/OIDC/Curator/cierre de L18 no son E2E oficiales. L20 sincroniza lifecycle atómicamente **solo en PG18 sandbox**; SALY conserva `estado=VALIDADO` y necesitaría campo aparte `lifecycle_state`. No hay acta de backup físico/PITR/restauración. No hay firma ni autorización productiva.

## Índice del paquete (lectura en orden)

1. **`01_registro_unico_decisiones.md`:** las 32 preguntas, alternativas, sugerencia, bloqueo, quién firma y evidencia para cada una.
2. **`02_matriz_bloqueos_produccion.md`:** 14 bloqueos, pruebas aceptables, responsables, dependencias y orden propuesto.
3. **`03_tablero_12_etapas.md`:** 3 escenarios × 12 etapas; REAL_EN_SANDBOX / SINTETICO / NO_PROBADO y fórmula de avance.
4. **`04_go_no_go_firmable.md`:** 15 verificaciones, resultado GO/NO-GO y casillas/firma en blanco.
5. **`05_respuestas_dueno.csv`:** 32 filas; Q03/Q04/Q05 con decisión en conversación, Q01 recomendada sin confirmar, las demás pendientes; **todas sin firma formal**.
6. **`06_select_evidencia_live.sql`:** SELECT S21_01–S21_06 y SHA-256 servidor.
7. **`07_manifest.md`:** provenance, hash, readback y límites.

### Invariantes

- Entrada oficial EKB V1.4: usuario→ACT-0001→perfil→RUN→pasos→IG si aplica→validación→juez→registro→cierre.
- Solo lectura Supabase `mhwmirqcgxxukpctffuv`; ningún DML/DDL, cierre/reintento de RUN, merge ni producción.
- No declarar juez independiente: **GPT-6, mismo modelo GPT**, identidad Claude no verificada.
- Los PASS PG18 son de laboratorio; no equivalen a autorización de cambios ni validación E2E nativa.
- Cada sugerencia se identifica como SUGERENCIA/REQUIERE_REVISION_SEMANTICA; hashes y conteos se califican OBJETIVO.

**Fuente EKB adjunta:** INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4, CANDIDATO VERIFICADO PARCIALMENTE; SHA-256 de bytes de la copia suministrada: `234fafb2b06b91e96a979feac138069ec75863aae1bd75aea93c72740c075f79`.

## Adenda estado L27

- **Decisiones capturadas en conversación:** Q03 A (Niubiz recaudo tarjeta/Yape), Q04 estados/cancelación/autoantigüedad y Q05 A (pricing versionado con permiso de perfil): **3**.
- **Recomendación sin confirmación:** Q01 MFA C: **1**. **Pendiente:** Q02 y otras 27: **28**.
- **Q04 con cuatro asuntos abiertos:** reintentos automáticos, recordatorios, mora, destino contable de INCOBRABLE. **No se interpreta como aprobación operativa completa.**
- **Firmas formales:** **0/32**. Ninguna propuesta CANDIDATO L25 se adoptó.
- **Permisos de precios:** 45 permisos y 0 asignaciones usuario-perfil se heredan de L19/L21; 16 resource_types y ausencia de permiso pricing son observaciones comunicadas por el dueño, sin SELECT ejecutado en L27. Ver `audits/rule-quality-lote27/02_pricing_permission_select_no_ejecutado.sql`.
- El tablero L21 `03_tablero_12_etapas.md` y criterio GO/NO-GO `04_go_no_go_firmable.md` se preservan **byte por byte**; estado productivo NO-GO/UNVERIFIED.
