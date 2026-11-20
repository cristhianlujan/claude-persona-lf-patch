-- IG Chat9: owner decisions D1, D1b, D1c. Policies only; no lf_ops.reglas writes.
-- Executed exclusively by canonical Migration Merge Train. The new password
-- failure rate policy is CANDIDATO, not proof of runtime password lockout.
-- All existing source decision references are preserved; no receipt fabricated.
BEGIN;
DO $chat9_d1$
DECLARE
  v_other_before text;
  v_other_after text;
  v_rule_before text;
  v_rule_after text;
  v_new_id bigint;
  v_changed integer;
  -- Named owner decisions as supplied in chat, not cryptographic receipts.
  v_d1 jsonb := jsonb_build_object(
    'origin_type','LF_CANONICAL','value_status','LF_CANONICAL',
    'decision_ref','D1','origin_reference','OWNER_CHAT_2026-11-18_16:20_LIMA',
    'origin_version','2026-11-18','identity_verified',false);
  v_d1b jsonb := jsonb_build_object(
    'origin_type','LF_CANONICAL','value_status','LF_CANONICAL',
    'decision_ref','D1b','origin_reference','OWNER_CHAT_2026-11-18_16:20_LIMA',
    'origin_version','2026-11-18','identity_verified',false);
  v_d1c jsonb := jsonb_build_object(
    'origin_type','LF_CANONICAL','value_status','LF_CANONICAL',
    'decision_ref','D1c','origin_reference','OWNER_CHAT_2026-11-18_16:20_LIMA',
    'origin_version','2026-11-18','identity_verified',false);
BEGIN
  IF to_regclass('lf_ops.politicas_rate_limit') IS NULL
     OR to_regclass('lf_ops.reglas') IS NULL THEN
     RAISE EXCEPTION 'CHAT9_D1_CANONICAL_TABLE_MISSING';
  END IF;
  LOCK TABLE lf_ops.politicas_rate_limit IN SHARE ROW EXCLUSIVE MODE;
  IF (SELECT count(*) FROM lf_ops.reglas) <> 579
     OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE') <> 438
     OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO') <> 141
  THEN RAISE EXCEPTION 'CHAT9_D1_RULE_BASELINE_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.politicas_rate_limit) <> 9
     OR (SELECT max(rate_limit_policy_id) FROM lf_ops.politicas_rate_limit) <> 9
     OR EXISTS (SELECT 1 FROM lf_ops.politicas_rate_limit
                WHERE policy_code='RATE-B2B-LOGIN-FAILED-PASSWORD'
                   OR resource_code='AUTH_LOGIN_FAILED_PASSWORD')
  THEN RAISE EXCEPTION 'CHAT9_D1_RATE_POLICY_COUNT_OR_TARGET_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.politicas_rate_limit
      WHERE rate_limit_policy_id=1
        AND policy_code='RATE-B2B-LOGIN'
        AND resource_code='AUTH_LOGIN'
        AND window_seconds=900 AND max_requests=5 AND burst_limit=5
        AND scope_key='IP_USER' AND status='VIGENTE') <> 1
     OR (SELECT count(*) FROM lf_ops.politicas_rate_limit
      WHERE rate_limit_policy_id=7
        AND policy_code='RATE-B2B-PASSWORD-RECOVERY-OTP'
        AND resource_code='AUTH_PASSWORD_RECOVERY_OTP_SEND'
        AND window_seconds=900 AND max_requests=6 AND burst_limit=6
        AND scope_key='USER' AND status='CANDIDATO') <> 1
     OR (SELECT count(*) FROM lf_ops.politicas_rate_limit
      WHERE rate_limit_policy_id=8
        AND policy_code='RATE-B2B-NEW-DEVICE-OTP'
        AND resource_code='AUTH_NEW_DEVICE_OTP_SEND'
        AND window_seconds=900 AND max_requests=6 AND burst_limit=6
        AND scope_key='USER' AND status='CANDIDATO') <> 1
  THEN RAISE EXCEPTION 'CHAT9_D1_EXACT_SOURCE_POLICY_DRIFT'; END IF;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.rate_limit_policy_id)::text,'[]'))
     INTO v_other_before FROM lf_ops.politicas_rate_limit p
     WHERE p.rate_limit_policy_id NOT IN (1,7,8);
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
     INTO v_rule_before FROM lf_ops.reglas r;

  UPDATE lf_ops.politicas_rate_limit
  SET scope_key='USER',updated_at=now(),
      parameter_provenance=parameter_provenance ||
        jsonb_build_object('scope_key',v_d1c)
  WHERE rate_limit_policy_id=1 AND policy_code='RATE-B2B-LOGIN'
    AND scope_key='IP_USER';
  GET DIAGNOSTICS v_changed=ROW_COUNT;
  IF v_changed<>1 THEN RAISE EXCEPTION 'CHAT9_D1_LOGIN_UPDATE_NOT_EXACT'; END IF;

  UPDATE lf_ops.politicas_rate_limit
  SET max_requests=5,burst_limit=5,updated_at=now(),
      parameter_provenance=parameter_provenance ||
        jsonb_build_object('max_requests',v_d1b,'burst_limit',v_d1b)
  WHERE rate_limit_policy_id IN (7,8) AND status='CANDIDATO'
    AND max_requests=6 AND burst_limit=6 AND window_seconds=900
    AND scope_key='USER';
  GET DIAGNOSTICS v_changed=ROW_COUNT;
  IF v_changed<>2 THEN RAISE EXCEPTION 'CHAT9_D1_OTP_UPDATE_NOT_EXACT'; END IF;

  v_new_id := (SELECT max(rate_limit_policy_id)+1 FROM lf_ops.politicas_rate_limit);
  IF v_new_id<>10 THEN RAISE EXCEPTION 'CHAT9_D1_NEXT_ID_DRIFT'; END IF;
  INSERT INTO lf_ops.politicas_rate_limit(
      policy_code,resource_code,window_seconds,max_requests,burst_limit,
      scope_key,status,rate_limit_policy_id,parameter_provenance)
  VALUES(
      'RATE-B2B-LOGIN-FAILED-PASSWORD','AUTH_LOGIN_FAILED_PASSWORD',
      900,5,5,'USER','CANDIDATO',v_new_id,
      jsonb_build_object(
        'window_seconds',v_d1,'max_requests',v_d1,
        'burst_limit',v_d1,'scope_key',v_d1));

  IF (SELECT count(*) FROM lf_ops.politicas_rate_limit)<>10
     OR (SELECT count(*) FROM lf_ops.politicas_rate_limit
        WHERE policy_code='RATE-B2B-LOGIN-FAILED-PASSWORD'
          AND resource_code='AUTH_LOGIN_FAILED_PASSWORD'
          AND window_seconds=900 AND max_requests=5 AND burst_limit=5
          AND scope_key='USER' AND status='CANDIDATO'
          AND source_decision_id IS NULL AND source_decision_number IS NULL
          AND parameter_provenance->'max_requests'->>'decision_ref'='D1'
          AND programacion.fn_input_parameter_provenance_valid_v1(parameter_provenance))<>1
     OR (SELECT count(*) FROM lf_ops.politicas_rate_limit
        WHERE rate_limit_policy_id=1 AND policy_code='RATE-B2B-LOGIN'
          AND scope_key='USER' AND window_seconds=900
          AND max_requests=5 AND burst_limit=5 AND status='VIGENTE'
          AND parameter_provenance->'scope_key'->>'decision_ref'='D1c')<>1
     OR (SELECT count(*) FROM lf_ops.politicas_rate_limit
        WHERE rate_limit_policy_id IN (7,8) AND max_requests=5
          AND burst_limit=5 AND window_seconds=900 AND scope_key='USER'
          AND status='CANDIDATO'
          AND parameter_provenance->'max_requests'->>'decision_ref'='D1b'
          AND parameter_provenance->'burst_limit'->>'decision_ref'='D1b')<>2
  THEN RAISE EXCEPTION 'CHAT9_D1_POLICY_POSTIMAGE_FAILED'; END IF;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.rate_limit_policy_id)::text,'[]'))
     INTO v_other_after FROM lf_ops.politicas_rate_limit p
     WHERE p.rate_limit_policy_id NOT IN (1,7,8,10);
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
     INTO v_rule_after FROM lf_ops.reglas r;
  IF v_other_before IS DISTINCT FROM v_other_after
     OR v_rule_before IS DISTINCT FROM v_rule_after
  THEN RAISE EXCEPTION 'CHAT9_D1_UNAUTHORIZED_POLICY_OR_RULE_CHANGE'; END IF;
  RAISE NOTICE 'CHAT9_D1_IN_TX_PASS policies=9_to_10 existing_3_updated=3 new_candidate=1 rules=579_unchanged';
END $chat9_d1$;
COMMIT;
