# L23 — Manifest de auditoría y límites

**Estado del alcance mecánico:** SANDBOX_VERIFIED (17/17 PASS). **Estado producción:** NO-GO / UNVERIFIED. No hay firma independiente ni Curator nativo acreditado.

## 1. Provenance y ruta
- Base Git exacta: 48f1e316d81c83ca2f880372a3a050b456c6b3ab (L22). Rama nueva: lf/issue-3779-lote23-curator-stage-v1.
- CI probó commit 612014b0d91d3082becad3c9ae6a134b319f4f54. Run 43313398467, job 131515024001, conclusión success.
- Entorno: GitHub Actions con servicio postgres:18, base desechable lf_3779_l23_curator_stage_pg18; integración de L11B/L13/L14/L17/L18 y Curator L23.
- Autor del juicio: GPT-6, **mismo modelo**, identidad Claude/no dependencia de juez externo NO ACREDITADA. El Curator ejecutado es SQL determinista y NO es un servicio Curator real.
- EKB leída: INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4, CANDIDATO VERIFICADO PARCIALMENTE; no se reencamina Router ni IG.

## 2. Evidencia y límites de aceptación
- 17/17 controles PASS en corrida final: 3 positivos, 9 negativos, 2 comprobaciones cero efectos, 2 comprobaciones integridad MD5 y 1 bootstrap.
- LF A_NEW = Curator y preparación ACCEPT/EN_REVISION únicamente, SIN apply en esa misma secuencia. LF B_CORRECTED = Curator ACCEPT y apply congelado/READY en la misma transacción. C_SALY_NEW = Curator ACCEPT y SALY synthetic apply/READY.
- Curator verifica familia y mapping aprobados, owner de familia/proyecto/actor del fixture L13/L17, duplicado VIGENTE, valor_config contradictorio, HMAC de dictamen, SHA de candidato y snapshot activos.
- Familia inexistente queda bloqueada por L13 antes de que se pueda crear fila Curator; no hay dictamen post-FK para ese negativo. Duplicado exacto DEVOLVER; conflicto JSON ESCALAR; owner incorrecto DEVOLVER.
- Trigger nuevo sobre activation_tickets ARMED de L14 bloquea falta de ACEPTAR, sello manipulado o snapshot obsoleto, antes de invocar LF apply o SALY fixture. L14 y los SQL de gates quedan intactos.
- Se detectó un conflicto verdadero en la primera prueba de REG_SEG_004 como A_NEW; no se relajó detector. La prueba A_NEW final utiliza otro candidato no conflictivo. El conflicto de corrección B solo se acepta ligado a sucesora explícita y owner HMAC sintético L18, no autorización real.
- Pruebas iniciales fallidas documentadas por logs de CI; solo se acredita la corrida final PASS #43313398467, no se ocultan intentos fallidos.

## 3. MD5 del PG18 realmente leídos antes/después
| Gate | MD5 antes = después |
|---|---|
| apply | 86b0494984edf95cf0f9c0a0df67000b |
| capture_record | 89cbfac4162dbc9f8ecca59f2c3ab4c3 |
| citation_verify | 773a62783baa5edbe967200cac66b8c3 |
| l8_guard | 522d12f0843be1da3c785cef3c0bf3fc |

Nota: md5 d7fe763c en Supabase vivo es la función LEGADA lf_rule_promotion_apply_v1 informada por el dueño; no es discrepancia respecto al gate nuevo PG18.

## 4. Hash y CI
| Elemento | SHA-256 |
|---|---|
| SQL Curator | 09549c4ce4b081db632394e264ece50a423a87234a0d23d30a2a0334463f6009 |
| Python test | d330d2735d7212ec6dd5e3e90b70d443c6023f14b83d4baa1b2d269a1f7bb061 |
| Workflow | a2ed410437e13aed55c8c5c26d8e47a5609c9a8bce40ce92d6a9e23c7cc4745b |
| JSON runtime PG18 | 2540e2d4ff8ab31b938ff118cfb03fba33f42388b4c10c0bd64c201b7e6665a5 |
| Artifact ZIP CI | e2e943c1cedbf373045efa487be2f5f3009a43a61cf0564f761ada7be5dfd763 |

CI: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43313398467. Raw JSON y consola están en artifact l23-pg18-curator-raw-evidence (13987286280; retención 14 días). Los SHA de fuente se calcularon de contenido GitHub UTF-8, verificados con el vector SHA256('abc'). SHA del runtime proviene del runner CI.

## 5. Scope de cambios y readback
Comparación Git de base L22 a rama L23: ahead, behind=0; **solo archivos nuevos de L23** dentro de:
- sandbox/lf_contract_gate_test/rule_quality_lifecycle_v1/15_l23_curator_stage_pg18.sql
- sandbox/lf_contract_gate_test/rule_promotion_v1/test_pg18_lote23_curator_stage.py
- .github/workflows/l23-curator-stage-pg18.yml
- docs/rule-quality-lote23/.
Ningún SQL original de gates 01–14, main, fuentes oficiales, Supabase ni RUN fue modificado. La suite L23 no ejecutó la batería completa anterior de 18 scripts; esa regresión heredada corresponde al alcance L20 previo, no se reetiqueta como ejecutada ahora.

## 6. Tablero y pendientes
El tablero de L21 cambia 3 celdas Curator: REAL_EN_SANDBOX de 15/36 (41,7%) a 18/36 (50%). La producción sigue 0/36 nativo acreditado por estos lotes. Curator productivo, Router, IG, OIDC, Step70 y firma independiente **NO_PROBADO**.

**Siguiente autorización potencial (NO EJECUTADA):** Curator auténtico gobernado por perfil/RUN/IG, identidad real, juez independiente si lo exige el contrato, pruebas E2E nativas, backup/restauración y firma owner. No se promueve regla ni se cambia RUN por esta entrega.

**NO-GO / UNVERIFIED.**
