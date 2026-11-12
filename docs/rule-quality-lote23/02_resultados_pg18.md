# Lote 23 — Evidencia real del Curator mínimo

Estado de prueba: SANDBOX_VERIFIED (mecánico); producción: NO-GO / UNVERIFIED.
PG18 18.6 aislado, base disposable lf_3779_l23_curator_stage_pg18. Ninguna escritura Supabase. El juez autor y revisor es GPT-6, mismo modelo, no independiente.

CI real: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43313398467
Commit probado: 612014b0d91d3082becad3c9ae6a134b319f4f54
Resultado: **17/17 PASS**; 3 positivos de Curator, 9 negativos, 2 readbacks de ausencia de efecto, 2 controles MD5 y 1 bootstrap.

| # | ID exacto | Evidencia de la prueba | Estado |
|---:|---|---|---|
| 1 | BOOTSTRAP_CLEAN_PG18 | Setup PG18 efímero con L11B/L13/L14/L17/L18/L23 | PASS |
| 2 | MD5_FROZEN_BEFORE | MD5 de cuatro gates antes | PASS |
| 3 | POSITIVE_A_LF_NEW | Curator ACEPTAR para LF nueva; NO apply en esta ruta; rollback | PASS |
| 4 | POSITIVE_B_CORRECTED | LF corregida con lineage+owner HMAC, Curator ACEPTAR, gate LF APPLIED, READY, rollback | PASS |
| 5 | POSITIVE_C_SALY_NEW | SALY nueva Curator ACEPTAR, apply sintético READY, rollback | PASS |
| 6 | N1_MISSING_VERDICT_BLOCKS_WRAPPER | Sin dictamen, SALY bloqueada antes de apply | PASS |
| 7 | N1_NO_SIDE_EFFECT | SALY tras bloqueo con cero tickets/efectos | PASS |
| 8 | N1B_LF_FROZEN_GATE_NEEDS_CURATOR | Sin dictamen LF, gate congelado bloqueado antes de apply | PASS |
| 9 | N1B_LF_GATE_NO_SIDE_EFFECT | LF tras bloqueo sin efectos persistidos | PASS |
| 10 | N2_EXACT_DUPLICATE | Duplicado VIGENTE => DEVOLVER_CON_MOTIVO | PASS |
| 11 | N3_CONFLICTING_CONFIG | Claves valor_config contradictorias => ESCALAR_A_HUMANO | PASS |
| 12 | N4_FAMILY_NOT_FOUND | Familia inexistente bloqueada temprano por L13, antes de Curator | PASS |
| 13 | N5_WRONG_FAMILY_OWNER | Owner de familia incorrecto => DEVOLVER_CON_MOTIVO | PASS |
| 14 | N6_TAMPERED_VERDICT_SEAL | HMAC manipulado => BLOCK_L23_CURATOR_SEAL_INVALID | PASS |
| 15 | N7_DIRECT_VERDICT_DML_DENIED | DML directo al registro Curator => 42501 | PASS |
| 16 | N8_ACCEPTED_VERDICT_STALE_CANDIDATE | Candidato mutado después de ACEPTAR => stale SHA bloqueo | PASS |
| 17 | MD5_FROZEN_AFTER | Cuatro gates MD5 intactos después | PASS |

## Alcance de los positivos

- LF nueva A_NEW: preparación EN_REVISION y dictamen ACEPTAR; no se ejecutó apply en la misma ruta. No atribuir un E2E integrado.
- LF corregida B_CORRECTED: sucesora REG_SEG_004 de RULE-DEPENDENCY-001, corrección explícita y owner HMAC firmado del **fixture**, Curator ACEPTAR, gate apply APPLIED y readback READY; rollback.
- SALY nueva C_SALY_NEW: dictamen ACEPTAR, apply SALY sintético y READY; rollback. No se implementaron gates LF para SALY.

El fixture inicial de REG_SEG_004 como regla nueva encontró un conflicto real de valor_config con RULE-DEPENDENCY-001 VIGENTE y se clasificó ESCALAR_A_HUMANO. El control NO se debilitó para aceptarlo. El positivo LF nuevo se probó con otra regla candidata no contradictoria.

## Seguridad del dictamen

El registro conserva proyecto/regla/owner/categoría, evidencia, snapshot SHA-256 de candidato y universo VIGENTE, veredicto, motivo y HMAC sobre el contenido. Antes de crear un activation_ticket ARMED de L14, el trigger L23 requiere ACEPTAR, identidad/owner coherentes, sello válido y snapshot sin cambios. Sin dictamen, no se alcanza la función de promoción. El DML de tenants hacia dictámenes está denegado.

Familia inexistente: se comprobó el bloqueo temprano L13 por FK y quality_prepare; NO se obtuvo un dictamen posterior Curator porque la regla sin familia válida no puede registrarse. Esa frontera se reporta explícitamente.

## MD5 de los gates PG18 antes y después

| Gate | MD5 antes = después |
|---|---|
| apply congelado PG18 | 86b0494984edf95cf0f9c0a0df67000b |
| capture_record | 89cbfac4162dbc9f8ecca59f2c3ab4c3 |
| citation_verify | 773a62783baa5edbe967200cac66b8c3 |
| l8 guard | 522d12f0843be1da3c785cef3c0bf3fc |

El md5 d7fe763c... del apply legado observado en vivo por el dueño NO se compara con 86b04949 del gate PG18: son funciones/entornos diferentes.

## SHA y readback

| Fuente probada | SHA-256 UTF-8 | Git blob SHA-1 |
|---|---|---|
| SQL Curator L23 | 09549c4ce4b081db632394e264ece50a423a87234a0d23d30a2a0334463f6009 | 9eecdce422c45e048e1db2f11b36fc66825ddf9c |
| Python PG18 L23 | d330d2735d7212ec6dd5e3e90b70d443c6023f14b83d4baa1b2d269a1f7bb061 | 4c01a5c9b3437a3afc922248a6c5a9bbd039b8a5 |
| Workflow PG18 L23 | a2ed410437e13aed55c8c5c26d8e47a5609c9a8bce40ce92d6a9e23c7cc4745b | a75f2ad2c36a5172ae7c351ac93da2069f9d9994 |

SHA-256 del JSON runtime real emitido por CI: 2540e2d4ff8ab31b938ff118cfb03fba33f42388b4c10c0bd64c201b7e6665a5.
Artifact GH Actions: l23-pg18-curator-raw-evidence, id 13987286280, ZIP SHA-256 e2e943c1cedbf373045efa487be2f5f3009a43a61cf0564f761ada7be5dfd763, retención 14 días.

## Límites estrictos

Curator real de Input Governance, Step70/OIDC, Supabase Auth/PostgREST reales, Router, RUN oficial, evaluación semántica genuina y cierre nativo: NO_PROBADO. Este Curator es SQL determinista en PG18, no un agente externo ni un segundo juez. El juicio GPT-6 actual no es independiente. No se editó ningún gate congelado ni fuentes oficiales.

NO-GO / UNVERIFIED para producción.
