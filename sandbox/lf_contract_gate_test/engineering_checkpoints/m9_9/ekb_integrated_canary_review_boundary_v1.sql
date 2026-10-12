-- M9.9 EKB operational update. Source-first, no lifecycle closure.
UPDATE transversal.error_knowledge
SET evidencia=CASE WHEN position('M99_INTEGRATED_SIX_CASE_20261012' in coalesce(evidencia,''))>0
 THEN evidencia ELSE concat_ws(E'\n',evidencia,
 'M99_INTEGRATED_SIX_CASE_20261012: Git integrated_six_case_canary_v1.sql ejecutado en LF_SUPABASE_SANDBOX: CLEAN CONTINUE y FALSE_PASS/DIVERGENCE/TIMEOUT/EXECUTION_ERROR/MISSING_RECEIPT requieren ROLLBACK. 6/6 retorno exacto de INPUT_GOVERNANCE 1.0.0, versiones residuales cero. TIMEOUT basado en medicion historica, no canary live. 0 recibos IG_CANARY_OBSERVATION y 0 reviews verificados del subject en EVIDENCE_LEDGER. fn_lf_independent_review_begin_v3 devuelve BLOCKED SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID sin receipt previo. INDEPENDENT_ASSURANCE 2.0.1 usa REVISION_INDEPENDIENTE_ESTRATEGIA_LF; el adaptador necesita recibir UUID de review autentico, no campo autodeclarado. PR2261 migracion 20261012013000 aun sin ledger. Checkpoint M9.9 sigue abierto.') END,
 updated_at=clock_timestamp()
WHERE codigo IN ('IG-M99-RUNTIME-EXECUTOR-RECEIPT-DISCONNECTED-001',
                 'IG-M99-ROLLBACK-FIVE-TRIGGERS-VALIDATION-GAP-001')
RETURNING codigo,estado;
