-- LF Input Governance, PG17 governed reversible discovery/probe.
-- This test intentionally DOES NOT invent a Product Director/owner skill invocation.
-- An existing authorized RULE_CREATE_APPLY with a current IN_PROGRESS Product Director
-- and exact owner decision is required to certify the positive IG V2 CREATE path.
-- This migration proves negative admission and the replacement dependencies only.
-- It must never insert a synthetic rule, promote or rebind existing production rows.
BEGIN;
DO $lf_ig_create_phase2_pilot_pg17$
DECLARE
  v_old CONSTANT text := 'B2B-RULE-VALIDATION-VALID-ONLY-001';
  v_new CONSTANT text := 'B2B-RULE-VALIDATION-VALID-ONLY-002';
  v_old_id integer;
  v_state text;
  v_links integer;
  v_tests integer;
  v_refs integer;
  v_family integer;
  v_history integer;
  v_new_present integer;
  v_ready_ig_creates integer;
  v_approved_promotions integer;
  v_error text;
  v_delete_fk_rejected boolean := false;
  v_ig_guard_rejected boolean := false;
BEGIN
  IF current_setting('server_version_num')::integer / 10000 <> 17 THEN
    RAISE EXCEPTION 'LF_IG_PILOT_REQUIRES_PG17';
  END IF;
  SELECT id, estado INTO STRICT v_old_id,v_state FROM lf_ops.reglas WHERE codigo=v_old;
  IF v_state<>'VIGENTE' THEN
    RAISE EXCEPTION 'LF_IG_PILOT_SOURCE_NOT_VIGENTE:%',v_state;
  END IF;
  SELECT count(*) INTO v_new_present FROM lf_ops.reglas WHERE codigo=v_new;
  IF v_new_present<>0 THEN
    RAISE EXCEPTION 'LF_IG_PILOT_REPLACEMENT_CODE_ALREADY_EXISTS:%',v_new;
  END IF;
  SELECT count(*) INTO v_links FROM lf_ops.reglas_pantallas WHERE regla_id=v_old_id;
  SELECT count(*) INTO v_tests FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old;
  SELECT count(*) INTO v_refs FROM lf_ops.reglas r WHERE r.codigo<>v_old
    AND concat_ws(' ',r.descripcion,r.razon,r.valor_config::text) ILIKE '%'||v_old||'%';
  SELECT count(*) INTO v_family FROM programacion.input_family_inheritable_sources_v1
    WHERE rule_id=v_old_id;
  SELECT count(*) INTO v_history FROM lf_ops.reglas_versiones
    WHERE codigo=v_old AND vigente_hasta IS NULL AND estado='VIGENTE';
  IF v_links<>3 OR v_tests<>1 OR v_refs<>3 OR v_family<>0 OR v_history<>1 THEN
    RAISE EXCEPTION 'LF_IG_PILOT_SOURCE_DRIFT:links=%,tests=%,refs=%,families=%,history_open=%',
      v_links,v_tests,v_refs,v_family,v_history;
  END IF;
  RAISE NOTICE 'LF_IG_PHASE2_BEFORE:old=% state=% screens=% tests=% citations=% family=% open_history=% new_absent=%',
    v_old,v_state,v_links,v_tests,v_refs,v_family,v_history,v_new_present=0;

  -- Actual IG V2 function, negative authorization path.
  -- NULL inputs are intentional: no run identifiers/receipts are manufactured.
  BEGIN
    PERFORM public.lf_skill_o_rule_create_v2(
      NULL, '{}'::jsonb, NULL, NULL, NULL
    );
    RAISE EXCEPTION 'LF_IG_V2_GUARD_UNEXPECTEDLY_ACCEPTED_UNBOUND_INPUT';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error='LF_IG_V2_GUARD_UNEXPECTEDLY_ACCEPTED_UNBOUND_INPUT' THEN RAISE; END IF;
    IF position('LF_IG_CHILD_PARENT_REQUEST_MISMATCH' in v_error)=0 THEN
      RAISE EXCEPTION 'LF_IG_V2_UNEXPECTED_REJECTION:%',v_error;
    END IF;
    v_ig_guard_rejected:=true;
    RAISE NOTICE 'LF_IG_V2_REAL_GUARD_NEGATIVE_PASS:%',v_error;
  END;

  -- No fake approval: check if a REAL current create is available for positive.
  SELECT count(*) INTO v_ready_ig_creates
    FROM public.lf_ig_owner_decision_v2 d
    JOIN public.lf_operation_execution p ON p.execution_id=d.parent_execution_id
    WHERE d.kind='CREATE' AND d.verdict='APROBAR'
      AND p.operation_code='EJECUCION_PERFIL_LF'
      AND p.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
      AND p.status='IN_PROGRESS'
      AND p.manifest->>'read_only'='true'
      AND p.manifest->>'no_write'='true';
  SELECT count(*) INTO v_approved_promotions FROM public.lf_rule_promotion_v1
    WHERE status='APPROVED' AND rule_code=v_new;
  RAISE NOTICE 'LF_IG_V2_POSITIVE_ELIGIBILITY:owner_attested_current_create=% replacement_promotion_approved=%',
    v_ready_ig_creates,v_approved_promotions;

  -- Demonstrate that deletion BEFORE relinking is rejected by real PG17
  -- foreign-key enforcement. The exception block is a subtransaction:
  -- all trigger preimage writes made before the FK rejection are rolled back.
  BEGIN
    DELETE FROM lf_ops.reglas WHERE codigo=v_old;
    RAISE EXCEPTION 'LF_IG_PILOT_DELETE_WITH_DEPENDENCIES_UNEXPECTEDLY_ALLOWED';
  EXCEPTION WHEN foreign_key_violation THEN
    v_delete_fk_rejected:=true;
    RAISE NOTICE 'LF_IG_PILOT_FK_NEGATIVE_PASS:relink screens/tests/other references before DELETE';
  END;
  IF NOT v_delete_fk_rejected OR NOT v_ig_guard_rejected THEN
    RAISE EXCEPTION 'LF_IG_PILOT_SECURITY_NEGATIVES_NOT_VERIFIED';
  END IF;

  -- Real readback after negative tests, still within transaction.
  IF NOT EXISTS (SELECT 1 FROM lf_ops.reglas WHERE id=v_old_id AND codigo=v_old AND estado='VIGENTE')
    OR EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo=v_new)
    OR (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE regla_id=v_old_id)<>v_links
    OR (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo=v_old)<>v_tests
    OR (SELECT count(*) FROM lf_ops.reglas r WHERE r.codigo<>v_old
      AND concat_ws(' ',r.descripcion,r.razon,r.valor_config::text) ILIKE '%'||v_old||'%')<>v_refs
    OR (SELECT count(*) FROM lf_ops.reglas_versiones
      WHERE codigo=v_old AND vigente_hasta IS NULL AND motivo='FOTO_INICIAL')<>1
  THEN RAISE EXCEPTION 'LF_IG_PILOT_POST_NEGATIVE_READBACK_DRIFT'; END IF;

  RAISE NOTICE 'LF_IG_PHASE2_AFTER_NEGATIVES:old=VIGENTE screens=% tests=% citations=% family=% open_history=% new_absent=true; positive_create=NOT_EXECUTED; promotion=NOT_EXECUTED; replacement=NOT_EXECUTED',
    v_links,v_tests,v_refs,v_family,v_history;
  RAISE NOTICE 'LF_IG_PHASE2_REQUIRED_ROUTE:ProductDirectorRUN->RAW+selectedScreen->Step50/60/70->OwnerDecision->RULE_CREATE_APPLY->Promote->RebindScreens/Families/Tests/Citations->DELETE with lf.reglas_cambio_motivo=REEMPLAZADA_POR:%',
    v_new;
END;
$lf_ig_create_phase2_pilot_pg17$;
ROLLBACK;
-- The Merge Train migration ledger is distinct from any rule change.
