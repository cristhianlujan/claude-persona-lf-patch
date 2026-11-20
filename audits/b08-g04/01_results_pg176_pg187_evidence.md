# B08 G04 — Evidencia EJECUTADA, exclusivamente PostgreSQL de laboratorio

Fuente: main SHA 8dd64cea361df0d47d787a6899fa2ddb5a0c92fd; SQL original desplegado:
supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql.
Git blob SHA-1 de migración = e5fec99442933300478fd9ff46034a29b50e1df5.
SHA-256 del contenido SQL obtenido en laboratorio =
05056963367f69ade7be0949b03ff26a494dc8732b43dfab1842a412c8389d83.

## Pruebas/entornos

- PR auditoría DRAFT: https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3815
- R17 test real ejecutado en Docker PG17.6 (server_version_num=170006) y PG18.7 (180007):
  https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43414806820
- Job RAW 131849908555: GitHub Actions test output. 253 tests del repositorio PASS, incluye 9 tests B08 por motor.
- PASE: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43414806705 PASS.
- Test fuente: sandbox/lf_contract_gate_test/edge_function_operation/test_b08_documentary_owner_decide_pg176_pg187.py
- Git blob SHA-1 del test ejecutado: e5346f00f7fa302611d27f8bf6e22823cbe60e21
- Source del escritor invocado: public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb), realmente reconstruido desde la migración canónica en DOS motores efímeros.
- NO claves Supabase, NO escritor de live, NO migración real, NO modificaciones de RUNs de usuario.

## Positivos transaccionales

| Caso | PG17.6 | PG18.7 | Readback |
|---|---|---|---|
| RECHAZAR con 6 campos oficiales | PASS | PASS | row documentada con decisor, fecha, frase literal, parent RUN sintético, proponente RAW distinto, SHA record recalculado, SHA fuente/propuesta y respuesta identity_verified=false, columna identity_mode=UNVERIFIED_CHAT_DECLARATION |
| APROBAR con 6 campos oficiales | PASS | PASS | en una transacción temporal: VIGENTE, promoción=1, child con 7 PASS_CLEAN; antes de salir se ejecuta ROLLBACK y ninguna decisión/regla/promoción/cambio permanece |
| Persistencia post rollback | 0 filas | 0 filas | verificadas 4 entidades: public.lf_ig_owner_decision_v2, lf_ops.reglas del code, public.lf_rule_promotion_v1 y public.lf_ig_rule_change_v2 |

**Nota contractual exacta:** el JSON p_decision acepta EXACTAMENTE 6 claves STRING:
codigo_regla, propuesta_sha256, veredicto, decisor, fecha, frase_literal.
identity_verified=false se devuelve en la respuesta del escritor;
identity_mode=UNVERIFIED_CHAT_DECLARATION se lee de la columna gobernada.
No afirmar que exista campo identity_verified en la tabla, ni que un séptimo campo sea válido.

## Seis negativos de G04, TODOS ejecutados con error EXACTO + 0 filas nuevas

| Negativo | Error SQL exacto | PG17.6 | PG18.7 |
|---|---|---|---|
| 1. Decisor diferente de Cristhian Luján | LF_IG_OWNER_DECISION_INPUT_INVALID | PASS | PASS |
| 2. Autorevisión desde propuesta RAW del perfil | LF_IG_OWNER_SELF_APPROVAL_FORBIDDEN | PASS | PASS |
| 3. SHA fuente anterior no coincide | LF_IG_OWNER_SOURCE_PREIMAGE_DRIFT | PASS | PASS |
| 4. Decisión duplicada dentro de transacción | LF_IG_OWNER_DECISION_ALREADY_RECORDED_NO_OVERRIDE | PASS | PASS |
| 5. Fecha de formato inválido | LF_IG_OWNER_DECISION_DATE_INVALID | PASS | PASS |
| 6. Campo indebido identity_verified=true (séptimo campo) | LF_IG_OWNER_DECISION_RECORD_REQUIRED | PASS | PASS |
| Extra. Fecha ISO antigua fuera de ventana del parent | LF_IG_OWNER_DECISION_DATE_OUT_OF_SCOPE | PASS | PASS |

Cada negativo verifica que las filas nuevas en las cuatro entidades sigan en cero tras error/rollback. La excepción SQL se verifica como token exacto ERROR, no solo una aparición de texto.

Marcadores reales del job (aparecen POR SEPARADO para ambas versiones):
- PASS_B08_G04_COMPLETE_RECHAZAR_SIX_FIELDS_SHA_RECORD_SOURCE_PROPOSAL_IDENTITY_FALSE_MODE_UNVERIFIED_REGISTER_READBACK_ROLLBACK
- PASS_B08_G04_COMPLETE_APROBAR_SIX_FIELDS_SHA_RECORD_SOURCE_PROPOSAL_IDENTITY_FALSE_MODE_UNVERIFIED_REGISTER_READBACK_ROLLBACK
- PASS_B08_G04_NEGATIVE_WRONG_DECISOR_LF_IG_OWNER_DECISION_INPUT_INVALID_ZERO_NEW_ROWS
- PASS_B08_G04_NEGATIVE_SELF_APPROVAL_LF_IG_OWNER_SELF_APPROVAL_FORBIDDEN_ZERO_NEW_ROWS
- PASS_B08_G04_NEGATIVE_STALE_SHA_LF_IG_OWNER_SOURCE_PREIMAGE_DRIFT_ZERO_NEW_ROWS
- PASS_B08_G04_NEGATIVE_DUPLICATE_LF_IG_OWNER_DECISION_ALREADY_RECORDED_NO_OVERRIDE_ZERO_NEW_ROWS
- PASS_B08_G04_NEGATIVE_INVALID_DATE_LF_IG_OWNER_DECISION_DATE_INVALID_ZERO_NEW_ROWS
- PASS_B08_G04_NEGATIVE_IDENTITY_TRUE_LF_IG_OWNER_DECISION_RECORD_REQUIRED_ZERO_NEW_ROWS
- PASS_B08_G04_NEGATIVE_DATE_OUT_OF_SCOPE_LF_IG_OWNER_DECISION_DATE_OUT_OF_SCOPE_ZERO_NEW_ROWS

## Limitación de evidencia

Los parents EJECUCION_PERFIL_LF, handoff Router, perfil, juez y actor proponente son fixtures de laboratorio. La prueba NO verifica que un juez nativo haya actuado de forma independiente. Se usó declaración documental (no firma, Auth/JWT/AAL2). Las transacciones se revirtieron; el live Supabase reportó 0 decisiones en public.lf_ig_owner_decision_v2 por SELECT.

**Resultado**: tests G04 de contrato+negativos aislados PASS. **B08 G04 completo NO cerrado**: falta operación canónica real elegible con lectura del registrador oficial y aceptación del chat de plan/dueño.
