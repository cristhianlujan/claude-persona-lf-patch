-- R5-C DRAFT ONLY — logical validator evidence readers + governed STORAGE_COMPACTION transition.
-- DO NOT APPLY WITHOUT: (1) Claude review, (2) explicit Cristhian OK, (3) contract 5.13.x disposition.
-- This candidate performs no historical compaction. R5-E remains separate.

DO $r5c_preflight$
DECLARE
  v_actual text;
  v_sets bigint;
BEGIN
  IF to_regclass('programacion.input_validator_assertion_sets_v1') IS NULL
     OR to_regprocedure('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'R5C_REQUIRES_R5A';
  END IF;

  SELECT count(*) INTO v_sets FROM programacion.input_validator_assertion_sets_v1;
  IF v_sets <> 3379 THEN
    RAISE EXCEPTION 'R5C_REQUIRES_VERIFIED_R5B expected_sets=3379 actual=%',v_sets;
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)'::regprocedure));
  IF v_actual IS DISTINCT FROM '1fcbd090ac0d38945d61bc385870ab64' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=rehydrate expected=% actual=%',
      '1fcbd090ac0d38945d61bc385870ab64',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure));
  IF v_actual IS DISTINCT FROM '1ed8d14016692bae1f7c83e0fb784ce9' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=family_assessment_update expected=% actual=%',
      '1ed8d14016692bae1f7c83e0fb784ce9',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_execution_update()'::regprocedure));
  IF v_actual IS DISTINCT FROM 'a2e62e0aa8aaea5d3e0a4c48c69a5faa' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=family_execution_update expected=% actual=%',
      'a2e62e0aa8aaea5d3e0a4c48c69a5faa',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure));
  IF v_actual IS DISTINCT FROM 'b4f4e6d0f97255cd3cfe1f77df80ecb5' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=semantic_coherence_v512 expected=% actual=%',
      'b4f4e6d0f97255cd3cfe1f77df80ecb5',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_auth006_build_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM '8f46becafa22ae24cf21f316d2516511' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=auth006_build_assertions expected=% actual=%',
      '8f46becafa22ae24cf21f316d2516511',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_owner_decision_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM 'c672695362826666ac8da5799982bbad' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=owner_decision_assertions expected=% actual=%',
      'c672695362826666ac8da5799982bbad',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure));
  IF v_actual IS DISTINCT FROM '385b6a7c7cfaf56bff3c6aa8d41539d8' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=v58_build_assertions expected=% actual=%',
      '385b6a7c7cfaf56bff3c6aa8d41539d8',coalesce(v_actual,'<NULL>');
  END IF;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_governance_continuation_currentness_v1()'::regprocedure));
  IF v_actual IS DISTINCT FROM '69cf918a8510c6ba40302cbba56e5c99' THEN
    RAISE EXCEPTION 'R5C_BASE_MD5_MISMATCH function=continuation_currentness expected=% actual=%',
      '69cf918a8510c6ba40302cbba56e5c99',coalesce(v_actual,'<NULL>');
  END IF;
END
$r5c_preflight$;

CREATE OR REPLACE FUNCTION programacion.fn_input_validator_storage_compaction_check_v1(
  p_old_row jsonb,
  p_new_row jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion'
AS $function$
DECLARE
  v_old_evidence jsonb:=p_old_row->'validator_evidence';
  v_new_evidence jsonb:=p_new_row->'validator_evidence';
  v_ref text;
  v_assertions jsonb;
  v_actual_sha text;
  v_logical jsonb;
BEGIN
  -- Clause 1: apart from validator_evidence, no column may change.
  -- validator_sha256 is checked separately in clause 5 so it has an independent negative test.
  IF (p_old_row - 'validator_evidence' - 'validator_sha256')
       IS DISTINCT FROM
     (p_new_row - 'validator_evidence' - 'validator_sha256') THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_NON_EVIDENCE_COLUMN_CHANGED');
  END IF;

  -- Clause 2: exact inline -> reference representation transition.
  IF jsonb_typeof(v_old_evidence) <> 'object'
     OR jsonb_typeof(v_old_evidence->'assertions') <> 'array'
     OR jsonb_array_length(v_old_evidence->'assertions') = 0
     OR jsonb_typeof(v_new_evidence) <> 'object'
     OR v_new_evidence ? 'assertions'
     OR NOT (v_new_evidence ? 'assertion_set_sha256')
     OR coalesce(v_new_evidence->>'assertion_set_sha256','') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_STORAGE_SHAPE_INVALID');
  END IF;

  v_ref:=v_new_evidence->>'assertion_set_sha256';

  -- Clause 4: referenced set must exist and remain content-addressed.
  SELECT s.assertions INTO v_assertions
  FROM programacion.input_validator_assertion_sets_v1 s
  WHERE s.assertion_set_sha256=v_ref;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_ASSERTION_SET_NOT_FOUND');
  END IF;

  v_actual_sha:=programacion.fn_v09_sha256_jsonb(v_assertions);
  IF v_actual_sha IS DISTINCT FROM v_ref THEN
    RETURN jsonb_build_object(
      'allowed',false,
      'code','R5C_ASSERTION_SET_CONTENT_HASH_MISMATCH',
      'expected',v_ref,
      'actual',v_actual_sha
    );
  END IF;

  -- Clause 3: exact logical evidence equality after rehydration.
  v_logical:=programacion.fn_input_validator_evidence_rehydrate_v1(v_new_evidence);
  IF v_logical IS DISTINCT FROM v_old_evidence THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_REHYDRATED_EVIDENCE_MISMATCH');
  END IF;

  -- Clause 5: validator receipt hash is immutable.
  IF p_new_row->>'validator_sha256' IS DISTINCT FROM p_old_row->>'validator_sha256' THEN
    RETURN jsonb_build_object('allowed',false,'code','R5C_VALIDATOR_SHA256_CHANGED');
  END IF;

  RETURN jsonb_build_object('allowed',true,'code','STORAGE_COMPACTION');
END;
$function$;

REVOKE ALL ON FUNCTION programacion.fn_input_validator_storage_compaction_check_v1(jsonb,jsonb)
FROM PUBLIC,anon,authenticated,service_role;

-- Negative/positive self-tests for all five owner clauses.
DO $r5c_storage_tests$
DECLARE
  v_sha1 text; v_sha2 text; v_assert1 jsonb;
  v_missing text:=repeat('f',64);
  v_old jsonb; v_new jsonb; v_result jsonb;
BEGIN
  SELECT assertion_set_sha256,assertions
    INTO v_sha1,v_assert1
  FROM programacion.input_validator_assertion_sets_v1
  ORDER BY assertion_set_sha256
  LIMIT 1;

  SELECT assertion_set_sha256
    INTO v_sha2
  FROM programacion.input_validator_assertion_sets_v1
  WHERE assertion_set_sha256<>v_sha1
  ORDER BY assertion_set_sha256
  LIMIT 1;

  IF EXISTS (
    SELECT 1 FROM programacion.input_validator_assertion_sets_v1
    WHERE assertion_set_sha256=v_missing
  ) THEN
    v_missing:=repeat('e',64);
  END IF;
  IF EXISTS (
    SELECT 1 FROM programacion.input_validator_assertion_sets_v1
    WHERE assertion_set_sha256=v_missing
  ) THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_TEST_NO_MISSING_SHA_AVAILABLE';
  END IF;

  v_old:=jsonb_build_object(
    'id',1,'run_id',1,'family_code','SELFTEST',
    'validator_sha256',repeat('a',64),
    'sentinel','UNCHANGED',
    'validator_evidence',jsonb_build_object(
      'execution_id','R5C-SELFTEST',
      'assertions',v_assert1
    )
  );
  v_new:=jsonb_build_object(
    'id',1,'run_id',1,'family_code','SELFTEST',
    'validator_sha256',repeat('a',64),
    'sentinel','UNCHANGED',
    'validator_evidence',jsonb_build_object(
      'execution_id','R5C-SELFTEST',
      'assertion_set_sha256',v_sha1
    )
  );

  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(v_old,v_new);
  IF coalesce((v_result->>'allowed')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'R5C_POSITIVE_STORAGE_COMPACTION_SELFTEST_FAILED:%',v_result;
  END IF;

  -- Clause 1 negative: a non-evidence column changed.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(v_new,'{sentinel}','"CHANGED"'::jsonb)
  );
  IF v_result->>'code'<>'R5C_NON_EVIDENCE_COLUMN_CHANGED' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE1_FAILED:%',v_result;
  END IF;

  -- Clause 2 negative: NEW illegally carries inline assertions too.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(
      v_new,'{validator_evidence}',
      (v_new->'validator_evidence')||jsonb_build_object('assertions',v_assert1)
    )
  );
  IF v_result->>'code'<>'R5C_STORAGE_SHAPE_INVALID' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE2_FAILED:%',v_result;
  END IF;

  -- Clause 3 negative: valid different assertion set rehydrates to different logical evidence.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(v_new,'{validator_evidence,assertion_set_sha256}',to_jsonb(v_sha2))
  );
  IF v_result->>'code'<>'R5C_REHYDRATED_EVIDENCE_MISMATCH' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE3_FAILED:%',v_result;
  END IF;

  -- Clause 4 negative: referenced assertion set does not exist.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(v_new,'{validator_evidence,assertion_set_sha256}',to_jsonb(v_missing))
  );
  IF v_result->>'code'<>'R5C_ASSERTION_SET_NOT_FOUND' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE4_FAILED:%',v_result;
  END IF;

  -- Clause 5 negative: validator_sha256 changed.
  v_result:=programacion.fn_input_validator_storage_compaction_check_v1(
    v_old,
    jsonb_set(v_new,'{validator_sha256}',to_jsonb(repeat('b',64)))
  );
  IF v_result->>'code'<>'R5C_VALIDATOR_SHA256_CHANGED' THEN
    RAISE EXCEPTION 'R5C_NEGATIVE_CLAUSE5_FAILED:%',v_result;
  END IF;
END
$r5c_storage_tests$;

-- Continuation-currentness gate: terminal receipts may only perform exact STORAGE_COMPACTION.
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_governance_continuation_currentness_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,programacion
AS $function$
DECLARE
  v_admission jsonb;
  v_compaction jsonb;
BEGIN
  IF tg_op='UPDATE'
     AND tg_table_schema='programacion'
     AND tg_table_name='input_family_assessments'
     AND old.validator_outcome<>'PENDING'
     AND (
       old.validator_outcome IS DISTINCT FROM new.validator_outcome
       OR old.validator_findings IS DISTINCT FROM new.validator_findings
       OR old.validator_evidence IS DISTINCT FROM new.validator_evidence
       OR old.validator_identity IS DISTINCT FROM new.validator_identity
       OR old.validator_sha256 IS DISTINCT FROM new.validator_sha256
       OR old.validator_assessed_at IS DISTINCT FROM new.validator_assessed_at
     ) THEN
    IF old.validator_evidence IS DISTINCT FROM new.validator_evidence THEN
      v_compaction:=programacion.fn_input_validator_storage_compaction_check_v1(
        to_jsonb(old),to_jsonb(new)
      );
      IF coalesce((v_compaction->>'allowed')::boolean,false) IS TRUE THEN
        RETURN new;
      END IF;
      RAISE EXCEPTION 'VALIDATOR_RECEIPT_IMMUTABLE:%:%',
        old.family_code,coalesce(v_compaction->>'code','STORAGE_COMPACTION_REJECTED');
    END IF;
    RAISE EXCEPTION 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code;
  END IF;

  v_admission:=programacion.fn_input_governance_continuation_currentness_v1(new.run_id);
  IF NOT coalesce((v_admission->>'continuation_current')::boolean,false) THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_CONTINUATION_CURRENTNESS_BLOCKED:table=%:run=%:code=%',
      tg_table_name,new.run_id,coalesce(v_admission->>'code','CURRENTNESS_UNKNOWN');
  END IF;
  RETURN new;
END;
$function$;

-- Patch the assertion-complete consumers from exact guarded base definitions.
DO $r5c_patch_readers$
DECLARE
  v_def text;
  v_occ integer;
BEGIN
  -- 1) Main assessment update guard:
  --    * exact storage compaction bypass for terminal receipts;
  --    * terminal-validation checks/hash operate on logical rehydrated evidence.
  v_def:=pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure);
  v_def:=replace(v_def,'new.validator_evidence','v_logical_validator_evidence');
  v_def:=replace(
    v_def,
    E'declare\n',
    E'declare\n  v_logical_validator_evidence jsonb;\n  v_storage_compaction jsonb;\n'
  );
  v_def:=replace(
    v_def,
    E'begin\n  if new.run_id',
    E'begin\n  if old.validator_outcome<>''PENDING'' and new.validator_evidence is distinct from old.validator_evidence then\n'
    || E'    v_storage_compaction:=programacion.fn_input_validator_storage_compaction_check_v1(to_jsonb(old),to_jsonb(new));\n'
    || E'    if coalesce((v_storage_compaction->>''allowed'')::boolean,false) is true then return new; end if;\n'
    || E'    raise exception ''VALIDATOR_RECEIPT_IMMUTABLE:%:%'',old.family_code,coalesce(v_storage_compaction->>''code'',''STORAGE_COMPACTION_REJECTED'');\n'
    || E'  end if;\n'
    || E'  if new.run_id'
  );
  v_def:=replace(
    v_def,
    'if new.validator_outcome=''PENDING'' then raise exception ''VALIDATOR_UPDATE_MUST_BE_TERMINAL:%'',old.family_code; end if;',
    'if new.validator_outcome=''PENDING'' then raise exception ''VALIDATOR_UPDATE_MUST_BE_TERMINAL:%'',old.family_code; end if;'
    || E'\n  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);'
  );
  IF position('fn_input_validator_storage_compaction_check_v1' in v_def)=0
     OR position('v_logical_validator_evidence' in v_def)=0 THEN
    RAISE EXCEPTION 'R5C_PATCH_ANCHOR_FAILED:family_assessment_update';
  END IF;
  EXECUTE v_def;

  -- 2) Independent execution guard reads logical evidence.
  v_def:=pg_get_functiondef('programacion.fn_guard_input_family_execution_update()'::regprocedure);
  v_def:=replace(v_def,'new.validator_evidence','v_logical_validator_evidence');
  v_def:=replace(v_def,E'declare\n',E'declare\n  v_logical_validator_evidence jsonb;\n');
  v_def:=replace(
    v_def,
    'if old.validator_outcome<>''PENDING'' or new.validator_outcome=''PENDING'' then return new; end if;',
    'if old.validator_outcome<>''PENDING'' or new.validator_outcome=''PENDING'' then return new; end if;'
    || E'\n  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);'
  );
  IF position('v_logical_validator_evidence' in v_def)=0 THEN
    RAISE EXCEPTION 'R5C_PATCH_ANCHOR_FAILED:family_execution_update';
  END IF;
  EXECUTE v_def;

  -- 3) V5.12/V5.13 semantic coherence guard reads logical evidence.
  v_def:=pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure);
  v_def:=replace(v_def,'new.validator_evidence','v_logical_validator_evidence');
  v_def:=replace(v_def,E'declare\n',E'declare\n  v_logical_validator_evidence jsonb;\n');
  v_def:=replace(
    v_def,
    'if old.validator_outcome<>''PENDING'' or new.validator_outcome=''PENDING'' then return new; end if;',
    'if old.validator_outcome<>''PENDING'' or new.validator_outcome=''PENDING'' then return new; end if;'
    || E'\n  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);'
  );
  IF position('v_logical_validator_evidence' in v_def)=0 THEN
    RAISE EXCEPTION 'R5C_PATCH_ANCHOR_FAILED:semantic_coherence_v512';
  END IF;
  EXECUTE v_def;

  -- 4-6) Builders reading persisted parent assertions rehydrate before array access.
  FOREACH v_def IN ARRAY ARRAY[
    pg_get_functiondef('programacion.fn_input_auth006_build_assertions(bigint,bigint,text)'::regprocedure),
    pg_get_functiondef('programacion.fn_input_owner_decision_assertions(bigint,bigint,text)'::regprocedure),
    pg_get_functiondef('programacion.fn_input_v58_build_assertions(bigint,bigint,text)'::regprocedure)
  ]
  LOOP
    v_occ:=regexp_count(
      v_def,
      '([A-Za-z_][A-Za-z0-9_]*)\.validator_evidence->''assertions'''
    );
    IF v_occ=0 THEN
      RAISE EXCEPTION 'R5C_PATCH_ANCHOR_FAILED:builder_assertion_access';
    END IF;

    v_def:=regexp_replace(
      v_def,
      '([A-Za-z_][A-Za-z0-9_]*)\.validator_evidence->''assertions''',
      E'programacion.fn_input_validator_evidence_rehydrate_v1(\\1.validator_evidence)->''assertions''',
      'g'
    );

    IF position('fn_input_validator_evidence_rehydrate_v1' in v_def)=0 THEN
      RAISE EXCEPTION 'R5C_PATCH_RESULT_FAILED:builder_rehydrate';
    END IF;
    EXECUTE v_def;
  END LOOP;
END
$r5c_patch_readers$;

-- Postconditions: all seven governed functions still exist.
DO $r5c_postcheck$
BEGIN
  IF to_regprocedure('programacion.fn_guard_input_family_assessment_update()') IS NULL
     OR to_regprocedure('programacion.fn_guard_input_family_execution_update()') IS NULL
     OR to_regprocedure('programacion.fn_guard_input_validator_semantic_coherence_v512()') IS NULL
     OR to_regprocedure('programacion.fn_input_auth006_build_assertions(bigint,bigint,text)') IS NULL
     OR to_regprocedure('programacion.fn_input_owner_decision_assertions(bigint,bigint,text)') IS NULL
     OR to_regprocedure('programacion.fn_input_v58_build_assertions(bigint,bigint,text)') IS NULL
     OR to_regprocedure('programacion.fn_guard_input_governance_continuation_currentness_v1()') IS NULL THEN
    RAISE EXCEPTION 'R5C_POSTCHECK_FUNCTION_MISSING';
  END IF;
END
$r5c_postcheck$;
