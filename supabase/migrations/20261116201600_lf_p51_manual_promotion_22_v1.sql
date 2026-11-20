-- IG 15:16 (Lima), OWNER 15:15: 'Ok conforme con las 22 (el recomendado)'.
-- DRAFT ONLY: no DB writes before authenticated GitHub owner approval + official Train.
-- Scope: 22 CANDIDATO definitions linked to P51; not a production GO.
-- No grants, no new writers; functions are called by the existing postgres Train.
-- Atomic/fail-closed: any exception aborts this transaction, including prior rules.
BEGIN;
DO $lf_p51_manual_22$
DECLARE
  v_execution constant text := 'EXEC-PROFILE-GATE2-F9D127E87575564A021B3F10';
  v_owner constant text := 'HUMAN:Cristhian Lujan';
  v_authorization_1023 constant text :=
    'Aprobacion humana por regla. Te autorizo para que des el go a lo ya trabajado';
  v_owner_1515 constant text := 'Ok conforme con las 22 (el recomendado)';
  v_codes text[] := ARRAY[
    'B2B-RULE-AUTH-004',
    'B2B-RULE-AUTH-005',
    'B2B-RULE-AUTH-006',
    'B2B-RULE-AUTH-007',
    'B2B-RULE-AUTH-011',
    'B2B-RULE-AUTH-012',
    'B2B-RULE-AUTH-013',
    'B2B-RULE-AUTH-014',
    'B2B-RULE-AUTH-017',
    'B2B-RULE-AUTH-018',
    'B2B-RULE-AUTH-019',
    'B2B-RULE-AUTH-020',
    'B2B-RULE-AUTH-021',
    'B2B-RULE-AUTH-023',
    'B2B-RULE-AUTH-024',
    'B2B-RULE-AUTH-025',
    'B2B-RULE-AUTH-026',
    'B2B-RULE-AUTH-036',
    'B2B-RULE-AUTH-040',
    'B2B-RULE-AUTH-048',
    'B2B-RULE-AUTH-STATE-001',
    'B2B-RULE-SECURITY-BASELINE-001'
  ]::text[];
  v_current text[];
  v_expected_sorted text[];
  v_rule text;
  v_row record;
  v_run record;
  v_score jsonb;
  v_request jsonb;
  v_decision jsonb;
  v_applied jsonb;
  v_promotion_id text;
  v_pre_sha text;
  v_note text;
  v_count integer;
  v_done integer := 0;
  v_applied_rows integer;
BEGIN
  -- Fail closed on drift of the exact owner-approved 22-row cohort.
  IF cardinality(v_codes) <> 22 OR
     (SELECT count(DISTINCT x) FROM unnest(v_codes) x) <> 22
  THEN RAISE EXCEPTION 'LF_P51_COHORT_NOT_EXACTLY_22'; END IF;

  SELECT * INTO v_run FROM public.lf_operation_execution
   WHERE execution_id=v_execution
   FOR SHARE;
  IF NOT FOUND OR v_run.operation_code <> 'EJECUCION_PERFIL_LF'
      OR v_run.target_code <> 'PERFIL-PRODUCT-DIRECTOR-LF'
      OR v_run.status <> 'COMPLETED'
  THEN RAISE EXCEPTION 'LF_P51_PARENT_NOT_COMPLETED_CANONICAL'; END IF;

  SELECT count(*),count(*) FILTER(WHERE status='STEP_PASS_WITH_EVIDENCE')
    INTO v_count,v_applied_rows
    FROM public.lf_operation_execution_steps WHERE execution_id=v_execution;
  IF v_count <> 11 OR v_applied_rows <> 11 OR NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=v_execution AND step_order=80
      AND step_id='report_output' AND status='STEP_PASS_WITH_EVIDENCE'
  ) THEN RAISE EXCEPTION 'LF_P51_PARENT_NOT_CLEAN_11_OF_11'; END IF;

  IF NOT EXISTS (
     SELECT 1 FROM public.lf_profile_write_authority_v1
     WHERE profile_code=v_run.target_code
       AND operation_code='PROMOCION_REGLA_LF' AND status='ACTIVE'
  ) THEN RAISE EXCEPTION 'LF_P51_MANUAL_PROFILE_NOT_AUTHORIZED'; END IF;

  SELECT array_agg(x ORDER BY x) INTO v_expected_sorted FROM unnest(v_codes) x;
  SELECT array_agg(codigo ORDER BY codigo) INTO v_current
  FROM (
    SELECT DISTINCT r.codigo FROM lf_ops.reglas r
    JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
    WHERE rp.pantalla_id=51 AND r.estado='CANDIDATO'
      AND r.pendiente_decision=false
      AND (r.codigo LIKE 'B2B-RULE-AUTH-%'
           OR r.codigo='B2B-RULE-SECURITY-BASELINE-001')
      AND r.codigo NOT IN ('B2B-RULE-AUTH-047','B2B-RULE-AUTH-049')
  ) cohort;
  IF v_current IS DISTINCT FROM v_expected_sorted
  THEN RAISE EXCEPTION 'LF_P51_COHORT_CHANGED_FROM_OWNER_22'; END IF;

  FOREACH v_rule IN ARRAY v_codes LOOP
    -- One rule, snapshot, and decision at a time. Never skip a failed rule.
    SELECT * INTO v_row FROM lf_ops.reglas
    WHERE codigo=v_rule FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LF_P51_RULE_NOT_FOUND:%',v_rule; END IF;
    IF v_row.estado <> 'CANDIDATO'
    THEN RAISE EXCEPTION 'LF_P51_NOT_CANDIDATO:%:%',v_rule,v_row.estado; END IF;
    IF v_row.pendiente_decision IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'LF_P51_OWNER_DECISION_PENDING:%',v_rule; END IF;
    IF NOT EXISTS (SELECT 1 FROM lf_ops.reglas_pantallas
       WHERE regla_id=v_row.id AND pantalla_id=51)
    THEN RAISE EXCEPTION 'LF_P51_RULE_SCREEN_DRIFT:%',v_rule; END IF;
    IF EXISTS (SELECT 1 FROM public.lf_rule_promotion_v1 p
       WHERE p.rule_code=v_rule AND p.status IN ('PENDING','APPROVED','APPLIED'))
    THEN RAISE EXCEPTION 'LF_P51_PROMOTION_ALREADY_EXISTS:%',v_rule; END IF;

    v_score := public.lf_rule_promotion_score_v1(v_execution,v_rule);
    IF v_score->>'A' IS DISTINCT FROM '0'
       OR v_score->>'B' IS DISTINCT FROM '30'
       OR v_score->>'C' IS DISTINCT FROM '20'
       OR v_score->>'D' IS DISTINCT FROM '10'
       OR v_score->>'score' IS DISTINCT FROM '60'
       OR v_score->>'decision' IS DISTINCT FROM 'MANUAL'
       OR v_score->>'hard_block' IS DISTINCT FROM 'false'
       OR v_score->>'next_gate' IS DISTINCT FROM 'PROMOTION_REQUEST'
    THEN RAISE EXCEPTION 'LF_P51_MANUAL_SCORE_DRIFT:%:%',v_rule,v_score; END IF;

    v_pre_sha := public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
    IF v_pre_sha IS NULL OR v_pre_sha !~ '^[a-f0-9]{64}$'
    THEN RAISE EXCEPTION 'LF_P51_SNAPSHOT_MISSING:%',v_rule; END IF;

    v_request := public.lf_rule_promotion_request_v1(
      v_execution, v_rule,
      'OWNER 2026-11-16 10:23 Lima: '||v_authorization_1023||
      ' | OWNER 2026-11-16 15:15 Lima: '||v_owner_1515||
      ' | RUN='||v_execution||'; A=0,B=30,C=20,D=10; score=60 MANUAL; hard_block=false; definition only'
    );
    v_promotion_id := v_request->>'promotion_id';
    IF v_request->>'status' IS DISTINCT FROM 'PENDING_HUMAN_APPROVAL'
       OR nullif(v_promotion_id,'') IS NULL
    THEN RAISE EXCEPTION 'LF_P51_REQUEST_DENIED:%:%',v_rule,v_request; END IF;
    IF v_request->>'snapshot_sha256' IS DISTINCT FROM v_pre_sha
    THEN RAISE EXCEPTION 'LF_P51_REQUEST_SNAPSHOT_MISMATCH:%',v_rule; END IF;

    -- Recheck server-side snapshot + record before human decision.
    IF NOT EXISTS (
      SELECT 1 FROM public.lf_rule_promotion_v1 p
      WHERE p.promotion_id=v_promotion_id AND p.rule_code=v_rule
        AND p.request_execution_id=v_execution
        AND p.requested_by_profile='PERFIL-PRODUCT-DIRECTOR-LF'
        AND p.status='PENDING' AND p.request_snapshot_sha256=v_pre_sha
    ) OR public.lf_asset_snapshot_sha_v1('REGLA',v_rule)
         IS DISTINCT FROM v_pre_sha
    THEN RAISE EXCEPTION 'LF_P51_PROMOTION_STALE_BEFORE_DECISION:%',v_rule; END IF;

    v_score := public.lf_rule_promotion_score_v1(v_execution,v_rule);
    IF v_score->>'score' IS DISTINCT FROM '60'
       OR v_score->>'decision' IS DISTINCT FROM 'MANUAL'
       OR v_score->>'hard_block' IS DISTINCT FROM 'false'
    THEN RAISE EXCEPTION 'LF_P51_SCORE_CHANGED_AFTER_REQUEST:%',v_rule; END IF;

    v_note :=
      'OWNER 2026-11-16 10:23 Lima literal: '||v_authorization_1023||
      ' | OWNER 2026-11-16 15:15 Lima literal: '||v_owner_1515||
      ' | execution_id='||v_execution||' | score=60 A=0 B=30 C=20 D=10; MANUAL; hard_block=false';
    IF v_rule = ANY(ARRAY[
        'B2B-RULE-AUTH-013',
        'B2B-RULE-AUTH-019',
        'B2B-RULE-AUTH-020',
        'B2B-RULE-AUTH-021',
        'B2B-RULE-AUTH-026',
        'B2B-RULE-SECURITY-BASELINE-001'
    ]::text[]) THEN
      v_note := v_note||' | VIGENTE como definicion; NO-GO de produccion';
    ELSE
      v_note := v_note||' | aprueba solo definicion normativa; NO autoriza produccion';
    END IF;

    v_decision := public.lf_rule_promotion_decide_v1(
        v_promotion_id,'APPROVE',v_owner,v_note);
    IF v_decision->>'status' IS DISTINCT FROM 'APPROVED'
      OR v_decision->>'promotion_id' IS DISTINCT FROM v_promotion_id
    THEN RAISE EXCEPTION 'LF_P51_DECIDE_DENIED:%:%',v_rule,v_decision; END IF;

    v_applied := public.lf_rule_promotion_apply_v1(v_promotion_id);
    IF v_applied->>'status' IS DISTINCT FROM 'APPLIED'
       OR v_applied->>'rule_code' IS DISTINCT FROM v_rule
    THEN RAISE EXCEPTION 'LF_P51_APPLY_DENIED:%:%',v_rule,v_applied; END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.lf_rule_promotion_v1 p
        JOIN lf_ops.reglas r ON r.codigo=p.rule_code
      WHERE p.promotion_id=v_promotion_id AND p.rule_code=v_rule
        AND p.request_execution_id=v_execution
        AND p.request_snapshot_sha256=v_pre_sha
        AND p.decided_by=v_owner AND p.status='APPLIED'
        AND p.decided_at IS NOT NULL AND p.applied_at IS NOT NULL
        AND r.estado='VIGENTE' AND r.pendiente_decision=false
    ) THEN RAISE EXCEPTION 'LF_P51_APPLIED_READBACK_FAILED:%',v_rule; END IF;

    v_done := v_done+1;
    RAISE NOTICE 'LF_P51_APPLIED_RULE %/% % %',v_done,22,v_rule,v_promotion_id;
  END LOOP;

  SELECT count(*) INTO v_applied_rows FROM public.lf_rule_promotion_v1
  WHERE request_execution_id=v_execution AND status='APPLIED'
    AND rule_code=ANY(v_codes) AND decided_by=v_owner;
  IF v_done<>22 OR v_applied_rows<>22
  THEN RAISE EXCEPTION 'LF_P51_FINAL_APPLIED_COUNT_DRIFT:%/%',v_done,v_applied_rows; END IF;
  IF (SELECT count(*) FROM lf_ops.reglas WHERE codigo=ANY(v_codes)
      AND estado='VIGENTE' AND pendiente_decision=false)<>22
  THEN RAISE EXCEPTION 'LF_P51_FINAL_VIGENTE_COUNT_DRIFT'; END IF;
  RAISE NOTICE 'LF_P51_MANUAL_22_APPLIED_WITH_READBACK';
END $lf_p51_manual_22$;
COMMIT;
