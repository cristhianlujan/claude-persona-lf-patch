-- Candidate integration PG. Requires live-equivalent schema in isolated PostgreSQL.
-- No production/sandbox Supabase application; if not run report NOT_EXECUTED.
DO $test$
DECLARE v_count int; v_legacy_days int; v_new_days int; v_hot int; v_audits int;
BEGIN
  SELECT count(*),
    max(value_integer) FILTER(WHERE parameter_code='LF_RECORD_RETENTION_DAYS'),
    max(value_integer) FILTER(WHERE parameter_code='LF_RETENTION_HOT_MONTHS')
  INTO v_count,v_new_days,v_hot FROM private.lf_ig_parameters_v1
  WHERE lifecycle_status='CANDIDATO';
  IF v_count<>2 OR v_new_days<>3650 OR v_hot<>12 THEN
    RAISE EXCEPTION 'FAIL_RETENTION_INITIAL_PARAMETERS';
  END IF;
  SELECT count(*) INTO v_audits
  FROM lf_ops.auditoria_eventos a
  JOIN private.lf_ig_parameters_v1 p ON p.correlation_id=a.correlation_id
  WHERE a.action='LF_IG_PARAMETER_CANDIDATE_INSERT'
    AND a.policy_snapshot->>'owner_approval_verified'='false';
  IF v_audits<>2 THEN RAISE EXCEPTION 'FAIL_RETENTION_PARAMETER_AUDIT'; END IF;
  BEGIN
    PERFORM private.fn_lf_ig_record_retention_for_rule_v1('REG_AUD_003');
    RAISE EXCEPTION 'FAIL_RETENTION_NO_ACTIVE_MUST_BLOCK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='FAIL_RETENTION_NO_ACTIVE_MUST_BLOCK' THEN RAISE; END IF;
    IF SQLERRM<>'LF_IG_RETENTION_NO_OWNER_APPROVED_ACTIVE_PARAMETER' THEN RAISE; END IF;
  END;
  SELECT count(*) INTO v_count FROM lf_ops.reglas
  WHERE (codigo='REG_AUD_003' AND estado='VIGENTE')
     OR (codigo='LEGAL-RECLAMOS-04' AND estado='CANDIDATO');
  IF v_count<>2 THEN RAISE EXCEPTION 'FAIL_RETENTION_RULES_UNCHANGED'; END IF;
  RAISE NOTICE 'PASS_IG_RETENTION_CANDIDATE_PARAMETERS_2_AUDIT_2_FAIL_CLOSED';
END;
$test$;
