-- M1.A9 N-9 rollback-only prelude.
-- Reconstructs the functional preimage of migration 20261003023000 inside the judge transaction.
-- No production persistence: IG_RUNTIME_CANDIDATE_JUDGE_V1 owns the final rollback.

DO $m1a9_preimage$
DECLARE
  r record;
  v_def text;
  v_new text;
BEGIN
  IF to_regprocedure('programacion.fn_input_contract_clause_v1_n9_hold(bigint,text,text[])') IS NOT NULL THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_HOLD_NAME_OCCUPIED';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_contract_clause_v1(bigint,text,text[])'::regprocedure)) <> 'df3129fa512eaeeee319264199644aed' THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_ACCESSOR_POSTIMAGE_DRIFT';
  END IF;

  FOR r IN
    SELECT * FROM (VALUES
      ('programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)'::regprocedure,'adea36699afc83e09f54b92e1656fda2'),
      ('programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure,'f00ed3bbf1259932ce19f6705506ee54'),
      ('programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb)'::regprocedure,'7bdb44ce517556a888c18d59dba1a04e')
    ) q(sig,expected_md5)
  LOOP
    v_def:=pg_get_functiondef(r.sig);
    IF md5(v_def)<>r.expected_md5 THEN
      RAISE EXCEPTION 'M1_A9_PRELUDE_CLASSIFIER_POSTIMAGE_DRIFT:%',r.sig;
    END IF;
    v_new:=replace(
      v_def,
      $s$'revision',programacion.fn_input_contract_clause_v1(p_version_id,'INPUT_READINESS_CONTRACT',array['family_stage_requirements','CONTEXT_BUDGET_RETRIEVAL_POLICY'])->>'contract_revision'$s$,
      $s$'revision','5.13'$s$
    );
    IF v_new=v_def THEN
      RAISE EXCEPTION 'M1_A9_PRELUDE_CLASSIFIER_INVERSE_NOOP:%',r.sig;
    END IF;
    EXECUTE v_new;
  END LOOP;

  v_def:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)'::regprocedure);
  IF md5(v_def)<>'fcf1afe1fd1abf3b241c7aa8b54a5fd0' THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_MATERIALIZE_POSTIMAGE_DRIFT';
  END IF;
  v_new:=replace(
    v_def,
    $s$v_contract_revision is distinct from (programacion.fn_input_contract_clause_v1(v_version,'INPUT_READINESS_CONTRACT',array['family_stage_requirements'])->>'contract_revision')$s$,
    $s$v_contract_revision not in ('5.12','5.13')$s$
  );
  IF v_new=v_def THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_MATERIALIZE_INVERSE_NOOP';
  END IF;
  EXECUTE v_new;

  ALTER FUNCTION programacion.fn_input_contract_clause_v1(bigint,text,text[])
    RENAME TO fn_input_contract_clause_v1_n9_hold;

  IF to_regprocedure('programacion.fn_input_contract_clause_v1(bigint,text,text[])') IS NOT NULL THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_ACCESSOR_STILL_VISIBLE';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint)'::regprocedure)) <> '2ebfa25bdde741e5052bd6dadde1bc29' THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_CLASSIFY_V1_PREIMAGE_MISMATCH';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure)) <> '478c66b884a68430671701ecf7d3bf8e' THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_CLASSIFY_CACHED_V1_PREIMAGE_MISMATCH';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v1_cached_v2(integer,text,bigint,jsonb)'::regprocedure)) <> '13e07ad8c2036f3886a8cb5448485e06' THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_CLASSIFY_CACHED_V2_PREIMAGE_MISMATCH';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text)'::regprocedure)) <> '1124648cb0e8ee1414bd9ca06f010887' THEN
    RAISE EXCEPTION 'M1_A9_PRELUDE_MATERIALIZE_PREIMAGE_MISMATCH';
  END IF;
END
$m1a9_preimage$;
