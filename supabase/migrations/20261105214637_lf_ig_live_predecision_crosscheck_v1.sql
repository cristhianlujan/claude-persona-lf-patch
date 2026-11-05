-- LF / Lote 1 / Input Governance: cruce determinista previo a la decision humana.
-- Objetivo: dejar de convertir HUMAN_DECISION_REQUIRED historico en solicitud humana
-- sin lectura viva. Usa la funcion CANONICA: NO reimplementa su clasificador.
-- Ruta: PR -> Merge Train (excepcion de circularidad documentada en Issue #3665).
-- Guard: no changes to Router/ACL/existing table rows/security policies.
-- Train exclusively controls apply/rollback/merge; NOT an execution receipt.
-- Preflight en la transaccion gobernada: MD5 de la fuente exacta actual 21f59a492708a3dee9037d9a40cba1a3
-- NOTA: los tests de este fichero requieren rol propietario en Train. NO EJECUTAR EN SESION READ_ONLY.

DO $preflight$
BEGIN
  IF md5(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure))
     IS DISTINCT FROM '21f59a492708a3dee9037d9a40cba1a3'
  THEN RAISE EXCEPTION 'LF_L1_EXECUTOR_SOURCE_DRIFT'; END IF;
  IF to_regprocedure('private.fn_lf_ig_human_decision_live_disposition_v1(bigint)') IS NULL
  THEN RAISE EXCEPTION 'LF_L1_CANONICAL_DISPOSITION_MISSING'; END IF;
  IF md5(pg_get_functiondef('private.fn_lf_ig_human_decision_live_disposition_v1(bigint)'::regprocedure))
     IS DISTINCT FROM 'd79b4ff3dfe1c2da5c2fdf8929d1ea9c'
  THEN RAISE EXCEPTION 'LF_L1_CANONICAL_DISPOSITION_SOURCE_DRIFT'; END IF;
  IF NOT has_function_privilege(current_user,'private.fn_lf_ig_human_decision_live_disposition_v1(bigint)','EXECUTE')
  THEN RAISE EXCEPTION 'LF_L1_CANONICAL_CALLER_ROLE_NOT_AUTHORIZED'; END IF;
END;
$preflight$;

-- Solo consumo de autoridad existente, no nuevo clasificador.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_predecision_crosscheck_v1(p_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $body$
DECLARE
  v_proposal record;
  v_live jsonb;
  v_items jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_resolved integer := 0;
  v_internal integer := 0;
  v_action integer := 0;
  v_pre_human integer := 0;
  v_blocked integer := 0;
  v_live_state text;
  v_screen_id integer;
  v_dep record;
  v_findings jsonb := '[]'::jsonb;
  v_rate record;
  v_abuse record;
BEGIN
  SELECT pantalla_id INTO v_screen_id FROM programacion.input_readiness_runs WHERE id=p_run_id;
  IF v_screen_id IS NULL THEN RAISE EXCEPTION 'LF_L1_RUN_NOT_FOUND'; END IF;
  -- CRUCE 1: VIGENTE -> CANDIDATO, por claves relacionales tipadas.
  FOR v_dep IN
    SELECT src.policy_code source_policy, src.security_policy_id source_id,
           kv.key relation_key, target.policy_code target_policy,
           target.security_policy_id target_id
    FROM lf_ops.pantallas_politicas sp
    JOIN lf_ops.politicas_seguridad src ON src.security_policy_id=sp.security_policy_id
    CROSS JOIN LATERAL jsonb_each(src.policy_config) kv
    JOIN lf_ops.politicas_seguridad target
      ON target.security_policy_id=CASE WHEN kv.key like '%security_policy_id'
                                         AND jsonb_typeof(kv.value)='number'
                                        THEN (kv.value #>> '{}')::bigint ELSE NULL END
    WHERE sp.pantalla_id=v_screen_id AND src.status='VIGENTE'
      AND kv.key like '%security_policy_id' AND jsonb_typeof(kv.value)='number'
      AND target.status='CANDIDATO'
    ORDER BY src.security_policy_id, kv.key
  LOOP
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
      'type','VIGENTE_REFERENCES_CANDIDATO','severity','INTERNAL_REMEDIATION',
      'source_policy',v_dep.source_policy,'source_id',v_dep.source_id,
      'relation_key',v_dep.relation_key,'target_policy',v_dep.target_policy,
      'target_id',v_dep.target_id,'question_owner',false));
  END LOOP;
  -- CRUCE 2: RATE vs politica 22 sin confundir IP_USER con bloqueo solo IP.
  -- No se crea una nueva politica ni se reescriben los umbrales.
  SELECT pr.policy_code,pr.status,pr.scope_key,pr.max_requests,pr.window_seconds
    INTO v_rate
  FROM lf_ops.pantallas_politicas sp
  JOIN lf_ops.politicas_rate_limit pr ON pr.rate_limit_policy_id=sp.rate_limit_policy_id
  WHERE sp.pantalla_id=v_screen_id AND pr.policy_code='RATE-B2B-LOGIN'
  LIMIT 1;
  IF FOUND THEN
    SELECT ps.policy_code,ps.status,ps.policy_config
      INTO v_abuse FROM lf_ops.politicas_seguridad ps
    WHERE ps.security_policy_id=22;
    IF NOT FOUND THEN RAISE EXCEPTION 'LF_L1_ABUSE_POLICY_SOURCE_MISSING'; END IF;
    IF v_abuse.policy_config->>'ip_hard_limit'='DENY' THEN
      IF v_rate.scope_key='IP' THEN
        v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
          'type','IP_ONLY_SCOPE_CONTRADICTS_HARD_LIMIT_DENY',
          'severity','INTERNAL_REMEDIATION','rate_policy',v_rate.policy_code,
          'security_policy',v_abuse.policy_code,'question_owner',false));
      ELSIF v_rate.scope_key like 'IP%' THEN
        v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
          'type','IP_COMPOSITE_SCOPE_REQUIRES_RUNTIME_PROOF',
          'severity','ACQUIRE_EVIDENCE','rate_policy',v_rate.policy_code,
          'scope_key',v_rate.scope_key,'security_policy',v_abuse.policy_code,
          'question_owner',false));
      END IF;
    END IF;
  END IF;
  FOR v_proposal IN
    SELECT id,run_id,family_code,gap_code,status,proposal_kind,validator_outcome
    FROM programacion.input_gap_proposals
    WHERE run_id=p_run_id
      AND status='HUMAN_DECISION_REQUIRED'
    ORDER BY id
  LOOP
    v_total:=v_total+1;
    IF v_proposal.proposal_kind IS DISTINCT FROM 'HUMAN_DECISION_REQUIRED' THEN
      RAISE EXCEPTION 'LF_L1_HISTORICAL_HUMAN_KIND_DRIFT:%',v_proposal.id;
    END IF;
    -- No invocar por coincidencia textual, por catalogo inferido ni por status historico.
    v_live:=private.fn_lf_ig_human_decision_live_disposition_v1(v_proposal.id);
    IF jsonb_typeof(v_live) IS DISTINCT FROM 'object'
       OR v_live->>'schema_version' IS DISTINCT FROM 'lf-ig-human-live-disposition/v1'
       OR v_live->>'proposal_id' IS DISTINCT FROM v_proposal.id::text
    THEN RAISE EXCEPTION 'LF_L1_CANONICAL_RECEIPT_MALFORMED:%',v_proposal.id; END IF;
    v_live_state:=v_live->>'state';
    IF v_live_state NOT IN (
         'BLOCKED','NO_HUMAN_REQUIRED','INTERNAL_REMEDIATION',
         'ACTION_AUTHORIZATION_GATE','PRE_HUMAN_ADMISSION'
       ) OR v_live_state IS NULL
    THEN RAISE EXCEPTION 'LF_L1_CANONICAL_UNKNOWN_STATE:%',v_proposal.id; END IF;
    -- La funcion privada valida su propio classifier_sha256 y su autoridad.
    IF v_live_state NOT IN ('BLOCKED')
       AND coalesce(v_live->>'classifier_sha256','') !~ '^[0-9a-f]{64}$'
    THEN RAISE EXCEPTION 'LF_L1_CURRENTNESS_NOT_PROVEN:%',v_proposal.id; END IF;
    IF coalesce((v_live->>'human_queue_allowed')::boolean,true) IS NOT FALSE
    THEN RAISE EXCEPTION 'LF_L1_UNAUTHORIZED_HUMAN_QUEUE:%',v_proposal.id; END IF;
    IF v_live_state='NO_HUMAN_REQUIRED' THEN v_resolved:=v_resolved+1;
    ELSIF v_live_state='INTERNAL_REMEDIATION' THEN v_internal:=v_internal+1;
    ELSIF v_live_state='ACTION_AUTHORIZATION_GATE' THEN v_action:=v_action+1;
    ELSIF v_live_state='PRE_HUMAN_ADMISSION' THEN v_pre_human:=v_pre_human+1;
    ELSE v_blocked:=v_blocked+1; END IF;
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'proposal_id',v_proposal.id,'family_code',v_proposal.family_code,
      'gap_code',v_proposal.gap_code,'historical_status',v_proposal.status,
      'canonical_state',v_live_state,'canonical_code',v_live->>'code',
      'classifier_sha256',v_live->>'classifier_sha256',
      'requires_evidence',v_live_state IN ('BLOCKED','INTERNAL_REMEDIATION'),
      'human_queue_allowed',false
    ));
  END LOOP;
  RETURN jsonb_build_object(
    'schema_version','LF_IG_PREDECISION_CROSSCHECK_V1',
    'status','CANONICAL_READBACK_ONLY','run_id',p_run_id,
    'historical_count',v_total,'no_human_required_count',v_resolved,
    'internal_remediation_count',v_internal,'action_authorization_count',v_action,
    'pre_human_admission_count',v_pre_human,'blocked_count',v_blocked,
    'unresolved_count',v_internal+v_action+v_pre_human+v_blocked,
    'human_queue_opened',false,'action_authorized',false,
    'deterministic_findings',v_findings,
    'deterministic_finding_count',jsonb_array_length(v_findings),
    'items',v_items
  );
END;
$body$;
-- SECURITY INVOKER: no privilege escalation or ACL modifications.
-- Caller can reach private canonical disposition only via existing postgres-owned executor.

-- Integracion atomica con el ejecutor vivo. Los cinco anchors son REGEXP
-- tolerantes a indentacion y saltos de linea; cada uno debe existir 1 sola vez.
-- El MD5 impide adaptar silenciosamente cambios ajenos al alcance.
DO $integration$
DECLARE
  original_definition text;
  candidate_definition text;
  anchors_old text[] := ARRAY[
    $re$v_internal_summary[[:space:]]+jsonb;[[:space:]]+v_eval[[:space:]]+jsonb;$re$,
    $re$select[[:space:]]+count\(\*\)[[:space:]]+into[[:space:]]+v_human[[:space:]]+from[[:space:]]+programacion\.input_gap_proposals[[:space:]]+where[[:space:]]+run_id=v_run[[:space:]]+and[[:space:]]+status='HUMAN_DECISION_REQUIRED'[[:space:]]+and[[:space:]]+validator_outcome='PASS';[[:space:]]+v_internal:=coalesce\(\(v_internal_summary->>'internal_remediation_count'\)::integer,0\);$re$,
    $re$elsif[[:space:]]+v_internal>0[[:space:]]+then$re$,
    $re$'human_decision_required_count',v_human,'internal_remediation_required_count',v_internal,$re$,
    $re$if[[:space:]]+coalesce\(\(v_stage->>'canonical_story_gate_pass'\)::boolean,false\)[[:space:]]+then$re$
  ];
  anchors_new text[] := ARRAY[
    $new$v_internal_summary jsonb; v_predecision jsonb; v_eval jsonb;$new$,
    $new$v_predecision:=programacion.fn_input_governance_predecision_crosscheck_v1(v_run);
IF v_predecision->>'status' IS DISTINCT FROM 'CANONICAL_READBACK_ONLY'
OR (v_predecision->>'run_id')::bigint IS DISTINCT FROM v_run
OR v_predecision->>'human_queue_opened' IS DISTINCT FROM 'false'
THEN RAISE EXCEPTION 'LF_L1_CANONICAL_CROSSCHECK_UNPROVEN'; END IF;
-- Solo las propuestas PRE_HUMAN_ADMISSION llegan a la rama humana existente.
-- Esto NO abre cola: lf_human_escalation_admission_v1 sigue siendo obligatorio.
v_human:=coalesce((v_predecision->>'pre_human_admission_count')::integer,0);
v_internal:=coalesce((v_internal_summary->>'internal_remediation_count')::integer,0)
+ coalesce((v_predecision->>'internal_remediation_count')::integer,0)
+ coalesce((v_predecision->>'blocked_count')::integer,0)
+ coalesce((v_predecision->>'deterministic_finding_count')::integer,0);$new$,
    $new$elsif coalesce((v_predecision->>'action_authorization_count')::integer,0)>0 then
v_status:='BLOCKED';
v_remediation_state:='ACTION_AUTHORIZATION_GATE';
v_owner_interruption:=false;
elsif v_internal>0 then$new$,
    $new$'human_decision_required_count',v_human,'predecision_crosscheck',v_predecision,'internal_remediation_required_count',v_internal,$new$,
    $new$if coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false)
and v_human=0
and v_internal=0
and coalesce((v_predecision->>'action_authorization_count')::integer,0)=0 then$new$
  ];
  fragment_count integer;
  i integer;
BEGIN
  original_definition:=pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure);
  IF md5(original_definition) IS DISTINCT FROM '21f59a492708a3dee9037d9a40cba1a3'
  THEN RAISE EXCEPTION 'LF_L1_EXECUTOR_SOURCE_DRIFT'; END IF;
  candidate_definition:=original_definition;
  FOR i IN 1..array_length(anchors_old,1) LOOP
    SELECT count(*) INTO fragment_count
    FROM regexp_matches(candidate_definition, anchors_old[i], 'g');
    IF fragment_count<>1
    THEN RAISE EXCEPTION 'LF_L1_EXECUTOR_ANCHOR_DRIFT:%:%',i,fragment_count; END IF;
    candidate_definition:=regexp_replace(candidate_definition,anchors_old[i],anchors_new[i]);
  END LOOP;
  -- Seguridad: la rama humana ORIGINAL debe permanecer alcanzable.
  IF position('elsif v_human>0 then' IN candidate_definition)=0
     OR position('v_human:=coalesce((v_predecision->>''pre_human_admission_count'')::integer,0);' IN candidate_definition)=0
  THEN RAISE EXCEPTION 'LF_L1_HUMAN_BRANCH_LOST'; END IF;
  EXECUTE candidate_definition;
END;
$integration$;

-- Canary verification INSIDE THE SAME SQL TRANSACTION. A failure rolls back DDL.
-- The negative tests use actual database rows, and never update any row.
DO $lf_l1_canary$
DECLARE
  v_run_id bigint;
  v_proposal_id bigint;
  v_nonpass_id bigint;
  v_expected integer;
  v_expected_pre_human integer;
  v_result jsonb;
  v_private jsonb;
  v_missing_rejected boolean:=false;
  v_run_rejected boolean:=false;
  v_pre_count bigint;
  v_post_count bigint;
  v_fn_security_definer boolean;
BEGIN
  IF NOT has_function_privilege(current_user,'private.fn_lf_ig_human_decision_live_disposition_v1(bigint)','EXECUTE')
  THEN RAISE EXCEPTION 'LF_L1_TRAIN_OWNER_EXECUTE_NOT_AVAILABLE'; END IF;
  SELECT p.run_id,p.id INTO v_run_id,v_proposal_id
  FROM programacion.input_gap_proposals p
  WHERE p.status='HUMAN_DECISION_REQUIRED'
    AND p.proposal_kind='HUMAN_DECISION_REQUIRED'
    AND p.validator_outcome='PASS'
  ORDER BY p.id LIMIT 1;
  IF v_run_id IS NULL THEN RAISE EXCEPTION 'LF_L1_POSITIVE_REAL_FIXTURE_MISSING'; END IF;
  SELECT count(*) INTO v_pre_count FROM programacion.input_gap_proposals;
  SELECT count(*) INTO v_expected FROM programacion.input_gap_proposals p
  WHERE p.run_id=v_run_id AND p.status='HUMAN_DECISION_REQUIRED'
    AND p.proposal_kind='HUMAN_DECISION_REQUIRED';
  v_result:=programacion.fn_input_governance_predecision_crosscheck_v1(v_run_id);
  IF v_result->>'status' IS DISTINCT FROM 'CANONICAL_READBACK_ONLY'
     OR (v_result->>'historical_count')::integer IS DISTINCT FROM v_expected
     OR (v_result->>'run_id')::bigint IS DISTINCT FROM v_run_id
     OR jsonb_array_length(v_result->'items') IS DISTINCT FROM v_expected
     OR v_result->>'human_queue_opened' IS DISTINCT FROM 'false'
     OR v_result->>'action_authorized' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'LF_L1_CANARY_REAL_RUN_MISMATCH:%',v_run_id; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_result->'items') AS r(x)
             WHERE r.x->>'human_queue_allowed' IS DISTINCT FROM 'false'
                OR r.x->>'canonical_state' NOT IN
                   ('BLOCKED','NO_HUMAN_REQUIRED','INTERNAL_REMEDIATION',
                    'ACTION_AUTHORIZATION_GATE','PRE_HUMAN_ADMISSION'))
  THEN RAISE EXCEPTION 'LF_L1_CANARY_FALSE_HUMAN_QUEUE'; END IF;
  SELECT count(*) INTO v_expected_pre_human
  FROM jsonb_array_elements(v_result->'items') AS r(x)
  WHERE r.x->>'canonical_state'='PRE_HUMAN_ADMISSION';
  IF (v_result->>'pre_human_admission_count')::integer IS DISTINCT FROM v_expected_pre_human
     OR (v_result->>'historical_count')::integer IS DISTINCT FROM
        (coalesce((v_result->>'no_human_required_count')::integer,0)
         + coalesce((v_result->>'internal_remediation_count')::integer,0)
         + coalesce((v_result->>'action_authorization_count')::integer,0)
         + coalesce((v_result->>'pre_human_admission_count')::integer,0)
         + coalesce((v_result->>'blocked_count')::integer,0))
  THEN RAISE EXCEPTION 'LF_L1_NEGATIVE_HUMAN_COUNT_DISPOSITION_MISMATCH'; END IF;
  v_private:=private.fn_lf_ig_human_decision_live_disposition_v1(v_proposal_id);
  IF v_private->>'proposal_id' IS DISTINCT FROM v_proposal_id::text
     OR v_private->>'human_queue_allowed' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'LF_L1_CANARY_PRIVATE_READBACK_MISMATCH'; END IF;

  -- NEGATIVE: actual non-PASS proposal is never eligible for human escalation.
  SELECT id INTO v_nonpass_id FROM programacion.input_gap_proposals
  WHERE validator_outcome IS DISTINCT FROM 'PASS' ORDER BY id LIMIT 1;
  IF v_nonpass_id IS NULL THEN RAISE EXCEPTION 'LF_L1_NEGATIVE_NONPASS_FIXTURE_MISSING'; END IF;
  v_private:=private.fn_lf_ig_human_decision_live_disposition_v1(v_nonpass_id);
  IF v_private->>'state' IS DISTINCT FROM 'BLOCKED'
     OR v_private->>'code' IS DISTINCT FROM 'SOURCE_PROPOSAL_NOT_VALIDATED'
     OR v_private->>'human_queue_allowed' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'LF_L1_NEGATIVE_NONPASS_FALSE_PASS'; END IF;

  -- NEGATIVE: nonexistent proposal reference never produces a valid receipt.
  BEGIN
    PERFORM private.fn_lf_ig_human_decision_live_disposition_v1(-999999999::bigint);
  EXCEPTION WHEN no_data_found THEN
    v_missing_rejected:=true;
  END;
  IF NOT v_missing_rejected THEN RAISE EXCEPTION 'LF_L1_NEGATIVE_FAKE_PROPOSAL_ACCEPTED'; END IF;

  -- NEGATIVE: unknown run cannot be treated as current or READY.
  BEGIN
    PERFORM programacion.fn_input_governance_predecision_crosscheck_v1(-999999999::bigint);
  EXCEPTION WHEN raise_exception THEN
    v_run_rejected:=true;
  END;
  IF NOT v_run_rejected THEN RAISE EXCEPTION 'LF_L1_NEGATIVE_UNKNOWN_RUN_ACCEPTED'; END IF;

  -- NO NEW PRIVILEGE ROUTE: helper is invoker-only (the existing executor remains definer).
  SELECT p.prosecdef INTO v_fn_security_definer FROM pg_catalog.pg_proc p
  WHERE p.oid='programacion.fn_input_governance_predecision_crosscheck_v1(bigint)'::regprocedure;
  IF v_fn_security_definer IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'LF_L1_NEW_HELPER_ELEVATED'; END IF;
  SELECT count(*) INTO v_post_count FROM programacion.input_gap_proposals;
  IF v_pre_count IS DISTINCT FROM v_post_count
  THEN RAISE EXCEPTION 'LF_L1_CANARY_PERSISTENCE_SIDE_EFFECT'; END IF;
  RAISE NOTICE 'LF_L1_CANARY_PASS real_run=%, real_proposal=%, nonpass_proposal=%, pre_human_count=%',
    v_run_id,v_proposal_id,v_nonpass_id,v_expected_pre_human;
END;
$lf_l1_canary$;
