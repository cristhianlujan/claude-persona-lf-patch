# Política 19 — evidencia de binding ACT-0001 y Train oficial
Alcance: un único SQL ejecutable `supabase/migrations/20261113130100_lf_b2b_policy19_otp_brevo_profiles12_v1.sql`, 8 valores OTP/Brevo de decisión L36 y 8 provenance. La política sigue CANDIDATO y `identity_verified=false`.
- Preimagen del SQL histórico: blob Git `66df6d1f4ff5e5666b46f470dd4afaad934d34cc`, preservado sin modificar en `audits/login-policy19-l37/02_pre_act0001_original_migration_snapshot.sql`.
- Ante un único RUN actual `ACTUALIZACION_DB_LF`, `IN_PROGRESS`, `producer=lf-migration-merge-train`, `manifest.pr=3819`, ruta/repositorio exactos, el SQL llama `public.lf_router_scope_bind_v1(execution_id)` para emitir recibo real de alcance.
- El recibo es **solo ruta**, `effect_authority=false` y `downstream_execution_allowed=false`. El efecto se autoriza exclusivamente por `public.lf_ig_policy19_apply_v1(execution_id,description,eight)`, que consume recibo del mismo RUN y verifica SHA de preimagen, 8 claves, provenance, perfil 1/2 y CANDIDATO.
- Readback de recibo, writer SHA, descripción, fila y rollback transaccional; fallos/deriva abortan. Prohibido invocar writer desde inspección directa.
- `sandbox/lf_contract_gate_test/edge_function_operation/test_policy19_l38_governed_apply_pgdual_v1.py` cubre PG17.6/18.7 aislados, positivos+rollback y negativos de RUN incorrecto, origen falso, deriva de fila; regresión del emisor owners se conserva en fixture base #3820.
- Pruebas históricas L36 se mantienen usando snapshot histórico; no se les atribuye prueba de recibo.
- No se declara Brevo implementado, IDP integrado, Supabase native AAL2, decisión del dueño firmada ni producción. El rollback poscommit exige nuevo PR y preimagen fresca.
