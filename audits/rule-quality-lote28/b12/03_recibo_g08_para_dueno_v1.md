# B12_LEGACY · G08 — Recibo de regresión actualizado, L34

Estado: **6/6 V1 CON POSITIVOS DE LABORATORIO PASS / G08 ABIERTO / RECIBO NO FIRMADO**. Fecha documental 2026-11-13. No se atribuye identidad física al dueño, no se emite cierre de B05 o B08.

## Autoridad y trazabilidad

- Plan rector: L28 Documento 12, `B12_LEGACY · G08`, `lf/issue-3779-lote28-blocker-closure-plan-v1`.
- Decisión documental del dueño: quitar EXECUTE al guard a PUBLIC/anon/authenticated; NO equivale a G08 formalmente firmado.
- PR #3817: HEAD autorizado `ec2f797993f3b4afbc8ae394abc804eb3df2c91f`; merge commit `f15ae1ffef2fd0a651ef418d8336106b509c24ce`.
- Merge Train oficial: [run 43421655978](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43421655978), `completed/success`; paso final `execution bookkeeping verdict` PASS.
- Ledger vivo: version `20261113112500`, nombre `lf_b12_legacy_guard_execute_acl_hardening_v1`, 1 statement.
- RUN: `EXEC-DB-TRAIN-PR3817-20261113112500-R43421655978`, operation `ACTUALIZACION_DB_LF`, `COMPLETED`.
- Observación: `manifest.proposer_actor=null` en RUN Train; NO inferir identidad humana.
- Preimagen L33/L34 de la prueba no altera #3817 ni ejecuciones existentes.

## G08 punto a punto (PASS solo si ejecutado)

| # | Requisito | Evidencia | Veredicto |
|---|---|---|---|
| G08-01 | Congelar 4 firmas, MD5, ACL y atributos | `audits/rule-quality-lote28/b12/01_preimagen_S21_04_live_20261113.json`, as_of 08:21:46 UTC; SELECT vivo post-Train | **PASS TÉCNICO** |
| G08-02 | Proteger 6 funciones V1, MD5 sin drift | Seis MD5 live SELECT y dos ejecuciones PG17.6/PG18.7 (L34, seis SHA exactos) | **PASS HASHES 6/6** |
| G08-03 | PG17.6/18.7, pruebas con SQL verdadero y rollback | [R17 L34 run 43439094146](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43439094146): `239 tests OK (skipped=1)`; cases six V1, `B12_SIX_TRANSACTION_ROLLBACK|true` | **PASS L34 SUITE ACOTADA** |
| G08-04 | Positivos/negativos, idempotencia, denegar por defecto, no pérdida | L34: CREATE/decide/apply/invoke/negativas. L35: `lf_skill_o_rule_update_v1` positivo con hijo `COMPLETED`, 7/7 `PASS_CLEAN`, `CANDIDATO` sin promoción; `lf_record_operation_step_core_v1` directo `STEP_RECORDED` + replay idempotente, una fila; rollback en PG17.6/18.7. | **6/6 FUNCIONES V1 POSITIVOS LAB PASS — R17 GLOBAL FAIL POR B09** |
| G08-05 | Rollback real ACL y protección de las 4 funciones S21_04 | #3817 [R17 43421283951](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43421283951), `aclexplode` conjunto exacto en ambas versiones | **PASS** |
| G08-06 | Una migración por PR y ruta oficial | #3817 Train run 43421655978, PR merged, ledger + RUN COMPLETED | **PASS** |
| G08-07 | Readback live MD5 4/4 y ACL | SELECT 2026-11-13 12:03 UTC: guard `{postgres=X/postgres,service_role=X/postgres}`, `anon/auth/PUBLIC` sin EXECUTE, `service_role` permitido; 4 MD5 intactos; 578 reglas LF; trigger enabled | **PASS** |
| G08-08 | Antes/después #3803/#3804/#3806, compatibilidad histórica | Captura individual de cuatro funciones fue posterior a #3806; seis V1 live protegidas; no se dispone de preimagen individual anterior comparable para todos los objetos | **PARCIAL — requiere reconciliación Arquitectura/DBA** |
| G08-09 | Compatibilidad B05 baseline y autoridad B08 | L34+L35: 6 funciones V1 con positivos (incluido escritor hijo y core recorder); candidata permanece sin promoción, errores/idempotencia y formato HUMAN aislado. NO acredita identidad del decisor B08 ni cierra 57 decisiones B05. | **6/6 TÉCNICO EN LAB; B05/B08 GLOBALES ABIERTOS** |
| G08-10 | Recibo final autenticado, readback independiente y decisión cierre | No hay firma verificable Arquitectura/DBA+dueño ni validación global G08. | **PENDIENTE** |

## Seis MD5 V1 expected = live (select ejecutado 2026-11-13)
| Función | MD5 |
|---|---|
| `lf_regla_candidate_write_v1` | `c311087befe49afb2affa668231c9dd1` |
| `lf_skill_invoke_v1` | `ac7e351e1834cbfb91aabf26e1a04a8d` |
| `lf_skill_o_rule_update_v1` | `dc97a0e7c65b65ae1951e2da86c6238b` |
| `lf_rule_promotion_apply_v1` | `d7fe763c999db6f6259b6b1e2bd69644` |
| `lf_rule_promotion_decide_v1` | `16e45f40dad5cecc215a2f978be47728` |
| `lf_record_operation_step_core_v1` | `fe08a25c8e3c023d7181194d2dfdee0d` |

## Dependencias y custodia pendiente
1. **Arquitectura/DBA:** contraste histórico anterior a #3806 y confirmación de compatibilidad integral de los seis V1 con consumidores reales en entorno final.
2. **Producto/QA/Legal/Seguridad:** 57 decisiones B05, 3 referencias y 20 pares semánticos según L21 (fuera de alcance de ensayo mecánico); no promover reglas sin este dictamen.
3. **IG/Seguridad/owner:** B08 decisión real por escritor oficial, SHA y recibo; el `HUMAN:B12_LAB_ONLY` es solo string de fixture, `identity_verified=false`, sin credencial real.
4. **Auditor independiente/DBA y dueño:** recibo autenticado, autoridad y cierre G08; no adjudicar firma.
5. No hubo cambios en Supabase por L34; sólo SELECT y tests de contenedores efímeros.

**Veredicto: `B12_ABIERTO_G08_NO_CIERRE`.** No se confunde cobertura técnica parcial con cierre de control global.

## Adenda L35 — dos positivos faltantes ejecutados

- Prueba: `sandbox/lf_contract_gate_test/edge_function_operation/test_b12_v1_full_positive_l35.py`, SQL REAL en Docker descartable PostgreSQL 17.6/18.7. En ambos: `PASS_B12_L35_SKILL_O_POSITIVE`, `PASS_B12_L35_CORE_POSITIVE_REPLAY`, `PASS_B12_L35_ROLLBACK`.
- Evidencia: [GitHub Actions R17 #43446461150](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43446461150). **El workflow completo concluyó FAILURE** por tests B09 ajenos con `SOURCE_MISSING` del SQL `20261113150000_lf_ig_native_chat_sha_receiver_v1.sql`. La ejecución de los dos tests L35 fue `ok` en ambas versiones; no atribuir PASS al workflow global.
- **Seis V1, seis positivos de laboratorio; no son seis autorizaciones productivas ni seis firmas humanas.** En ambos positivos, preimagen y tablas restauradas mediante ROLLBACK.
- Pendientes G08: reconciliación de hashes individuales anteriores a #3806 y verificación de consumidores reales, firma Arquitectura/DBA y dueño, B05 global y B08 identidad documental auténtica. Por ello `G08_NO_CIERRE`.
