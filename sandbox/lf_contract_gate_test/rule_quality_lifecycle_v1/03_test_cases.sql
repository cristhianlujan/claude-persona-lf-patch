-- LOTE 13: PostgreSQL 18 clean ephemeral sandbox test suite, fails closed.
\set ON_ERROR_STOP on
SET search_path = rule_quality_l13, public;
CREATE TABLE sandbox_test_results (
  test_id text PRIMARY KEY,
  status text NOT NULL CHECK (status='PASS'),
  expected text NOT NULL,
  observed jsonb NOT NULL,
  checked_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION assert_l13(p_id text,p_ok boolean,p_expected text,p_observed jsonb)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF p_ok IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'L13_TEST_FAILED: % | expected=% | observed=%',p_id,p_expected,p_observed
     USING ERRCODE='P0001';
 END IF;
 INSERT INTO sandbox_test_results(test_id,status,expected,observed)
 VALUES (p_id,'PASS',p_expected,p_observed);
END $$;

-- T01: LF total/status, synthetic data distributed exactly like L12.
WITH agg AS (SELECT count(*) AS total,count(*) FILTER(WHERE state='VIGENTE') AS vigentes,
               count(*) FILTER(WHERE state='CANDIDATO') AS candidatos FROM rules WHERE project_code='lf')
SELECT assert_l13('T01_LF_578_412_166',total=578 AND vigentes=412 AND candidatos=166,
 '578 total; 412 VIGENTE; 166 CANDIDATO',to_jsonb(agg)) FROM agg;

-- T02: SALY adapters use same canonical rule storage, with all 14 active.
WITH agg AS (SELECT count(*) AS total,count(*) FILTER(WHERE state='VIGENTE') AS vigentes
             FROM rules WHERE project_code='saly')
SELECT assert_l13('T02_SALY_14',total=14 AND vigentes=14,
 '14 total; 14 VIGENTE',to_jsonb(agg)) FROM agg;

WITH agg AS (
 SELECT (SELECT count(*) FROM families WHERE project_code='lf') AS lf_familias,
        (SELECT count(*) FROM families WHERE project_code='saly') AS saly_familias,
        (SELECT count(*) FROM category_family_map WHERE project_code='lf') AS lf_categorias,
        (SELECT count(*) FROM category_family_map WHERE project_code='saly') AS saly_categorias)
SELECT assert_l13('T03_MAPPING_COUNTS',
 lf_familias=15 AND saly_familias=3 AND lf_categorias=76 AND saly_categorias=3,
 'LF 15/76; SALY 3/3',to_jsonb(agg)) FROM agg;

WITH exact AS (SELECT category_raw,count(*) AS n FROM rules WHERE project_code='lf' GROUP BY category_raw),
 norm AS (SELECT upper(btrim(category_raw)) AS cat,count(*) AS n
          FROM rules WHERE project_code='lf' GROUP BY 1),
 agg AS (SELECT (SELECT count(*) FROM exact WHERE n=1) AS exact_singletons,
                (SELECT count(*) FROM norm WHERE n=1) AS casefold_singletons,
                (SELECT count(*) FROM exact) AS exact_categories,
                (SELECT count(*) FROM norm) AS casefold_categories)
SELECT assert_l13('T04_SINGLETON_19_VS_18',
 exact_singletons=19 AND casefold_singletons=18
 AND exact_categories=76 AND casefold_categories=73,
 '19 exactas; 18 casefold; 76/73 categorías',to_jsonb(agg)) FROM agg;

-- T05: wrong category -> family mapping must fail, not silently reassign.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  INSERT INTO rules(project_code,rule_code,family_code,category_raw,entity_code,definition_text)
  VALUES('lf','LF-INVALID-FAMILY','IDENTIDAD_SEGURIDAD','ux','GENERAL','No vinculada');
 EXCEPTION WHEN foreign_key_violation THEN
  blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T05_INVALID_FAMILY_ASSIGNMENT',blocked,'23503 category/family FK',
   jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T06: project owner_profile_code may never be SUPER_ADMIN.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  INSERT INTO projects(project_code,owner_name,owner_profile_code,created_by)
  VALUES('bad_admin','BAD','SUPER_ADMIN','ChatGPT');
 EXCEPTION WHEN check_violation THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T06_SUPER_ADMIN_CANNOT_OWN_PROJECT',blocked,
   '23514 owner profile check',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T07: family owner guard is independent from project owner guard.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  INSERT INTO families(project_code,family_code,scope,owner_profile_code,new_family_criterion,merge_criterion,created_by)
  VALUES('lf','BAD_FAMILY','Invalid fixture','SUPER_ADMIN',
    'distinct subject and scope','reconcile impacted rule consumers','ChatGPT');
 EXCEPTION WHEN check_violation THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T07_SUPER_ADMIN_CANNOT_OWN_FAMILY',blocked,
   '23514 family owner check',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T08: SUPER_ADMIN still rejected even though actor fixture has can_approve=true.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  PERFORM decide_rule_review('lf','LF-SYN-0003','lf-super','KEEP_VIGENTE',
   '{"source_ref":"SBX-TEST-08","rationale":"Attempt by SUPER_ADMIN"}'::jsonb,'2026-11-12T00:00:00Z');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T08_SUPER_ADMIN_APPROVAL_REJECTED',blocked,
  '42501 BLOCK_SUPER_ADMIN_APPROVAL',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T09: no semantic evidence -> no merge proposal.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  PERFORM propose_family_merge('lf','ACCESIBILIDAD','UX_FLUJOS_INTERFAZ','lf-owner','{}'::jsonb);
 EXCEPTION WHEN check_violation THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T09_FUSION_WITHOUT_EVIDENCE_REJECTED',blocked,
  '23514 BLOCK_MERGE_EVIDENCE_MISSING',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T10: due function proposes but must not update the rule.
DO $$
DECLARE before_row jsonb;after_row jsonb;due_count int;label text;
BEGIN
 SELECT to_jsonb(r) INTO before_row FROM rules r
 WHERE project_code='lf' AND rule_code='LF-SYN-0003';
 SELECT count(*),min(proposal) INTO due_count,label
 FROM list_review_due('lf','2026-11-12T00:00:00Z');
 SELECT to_jsonb(r) INTO after_row FROM rules r
 WHERE project_code='lf' AND rule_code='LF-SYN-0003';
 PERFORM assert_l13('T10_EXPIRED_REVIEW_PROPOSES_NO_CHANGE',
 due_count=1 AND label='PROPONER_REVISION' AND before_row=after_row
 AND before_row->>'state'='VIGENTE',
 'one proposal; unchanged row; state VIGENTE',
 jsonb_build_object('proposals',due_count,'label',label,'before',before_row,'after',after_row));
END $$;

-- T11: three VIGENTE -> CANDIDATO LF references, none for SALY.
WITH agg AS (
 SELECT (SELECT count(*) FROM find_noncurrent_references('lf')) AS lf_flags,
        (SELECT count(*) FROM find_noncurrent_references('saly')) AS saly_flags,
        (SELECT count(*) FROM find_noncurrent_references('lf')
         WHERE target_state='CANDIDATO'
           AND classification='REQUIERE_REVISION_SEMANTICA') AS lf_classified)
SELECT assert_l13('T11_GENERIC_REFERENCE_DETECTOR',
 lf_flags=3 AND saly_flags=0 AND lf_classified=3,
 'LF 3 classified; SALY 0',to_jsonb(agg)) FROM agg;

-- T12: detector intentionally catches one injected mismatch per project.
WITH agg AS (
 SELECT (SELECT count(*) FROM find_parameter_differences('lf')) AS lf_pairs,
        (SELECT count(*) FROM find_parameter_differences('saly')) AS saly_pairs,
        (SELECT count(*) FROM find_parameter_differences('lf')
         WHERE classification='REQUIERE_REVISION_SEMANTICA') AS lf_semantic_review)
SELECT assert_l13('T12_GENERIC_PARAMETER_DETECTOR',
 lf_pairs=1 AND saly_pairs=1 AND lf_semantic_review=1,
 'LF 1 synthetic pair; SALY 1 synthetic pair, semantic review only',to_jsonb(agg)) FROM agg;

-- T13: even positive evidence creates a PROPOSAL, does NOT merge real mappings.
DO $$
DECLARE reqid bigint;mapcount integer;statusval text;
BEGIN
 reqid:=propose_family_merge('lf','ACCESIBILIDAD','UX_FLUJOS_INTERFAZ','lf-owner',
   '{"semantic_equivalence":"Documented overlap hypothesis, review required",
      "impact_review":"Affected mapped rules and consumers evaluated in sandbox",
      "decision_ref":"SBX-OWNER-HYPOTHESIS-13",
      "source_ref":"L12-category-map"}'::jsonb);
 SELECT count(*) INTO mapcount FROM category_family_map WHERE project_code='lf';
 SELECT status INTO statusval FROM family_change_requests WHERE request_id=reqid;
 PERFORM assert_l13('T13_MERGE_ONLY_PROPOSAL',
   reqid IS NOT NULL AND mapcount=76 AND statusval='PROPOSED',
   'merge proposal recorded; 76 source categories unchanged',
   jsonb_build_object('proposal_id',reqid,'maps_still',mapcount,'status',statusval));
END $$;

-- T14: no cross-project identity fallback.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  PERFORM decide_rule_review('lf','LF-SYN-0003','saly-owner','KEEP_VIGENTE',
    '{"source_ref":"SBX-14","rationale":"cross project denial"}'::jsonb,'2026-11-12T00:00:00Z');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T14_CROSS_PROJECT_OWNER_REJECTED',blocked,
 '42501 BLOCK_ACTOR_UNRESOLVED',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T15: now and only now the LF owner explicitly renews the rule.
DO $$
DECLARE dec_id bigint;reviewed timestamptz;next_due timestamptz;stateval text;due_count int;
BEGIN
 dec_id:=decide_rule_review('lf','LF-SYN-0003','lf-owner','KEEP_VIGENTE',
 '{"source_ref":"SBX-15","rationale":"owner revalidated synthetic control"}'::jsonb,
 '2026-11-12T00:00:00Z');
 SELECT reviewed_at,next_review_at,state INTO reviewed,next_due,stateval
 FROM rules WHERE project_code='lf' AND rule_code='LF-SYN-0003';
 SELECT count(*) INTO due_count FROM list_review_due('lf','2026-11-12T00:00:00Z');
 PERFORM assert_l13('T15_OWNER_REVIEW_ACTUAL_DECISION',
 dec_id IS NOT NULL AND stateval='VIGENTE' AND due_count=0
 AND reviewed='2026-11-12T00:00:00Z'::timestamptz
 AND next_due=reviewed + interval '90 days',
 'owner decision logged; reviewed_at advanced; 90d next review; 0 overdue',
 jsonb_build_object('decision_id',dec_id,'state',stateval,'reviewed_at',reviewed,'next_review_at',next_due,'due_count',due_count));
END $$;

-- T16: even with evidence, SUPER_ADMIN cannot propose as owner.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  PERFORM propose_family_merge('lf','LEGAL','UX_FLUJOS_INTERFAZ','lf-super',
   '{"semantic_equivalence":"some","impact_review":"documented",
      "decision_ref":"SBX-16","source_ref":"test"}'::jsonb);
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T16_SUPER_ADMIN_MERGE_REJECTED',blocked,
 '42501 BLOCK_SUPER_ADMIN_APPROVAL',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T17: missing successor is a hard block.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  PERFORM decide_rule_review('lf','LF-SYN-0007','lf-owner','SUPERSEDE',
   '{"source_ref":"SBX-17","rationale":"no successor"}'::jsonb,'2026-11-12T00:00:00Z');
 EXCEPTION WHEN check_violation THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T17_SUPERSESSION_REQUIRES_SUCCESSOR',blocked,
 '23514 BLOCK_SUCCESSOR_REQUIRED',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T18: explicit and active successor permits owner-approved transition.
DO $$
DECLARE id bigint;st text;succ text;date_to timestamptz;
BEGIN
 id:=decide_rule_review('lf','LF-SYN-0007','lf-owner','SUPERSEDE',
   '{"source_ref":"SBX-18","rationale":"replacement control revalidated"}'::jsonb,
   '2026-11-12T00:00:00Z','LF-SYN-0008');
 SELECT state,successor_rule_code,effective_to INTO st,succ,date_to
 FROM rules WHERE project_code='lf' AND rule_code='LF-SYN-0007';
 PERFORM assert_l13('T18_OWNER_APPROVES_SUCCESSOR',
  id IS NOT NULL AND st='SUCEDIDA' AND succ='LF-SYN-0008'
  AND date_to='2026-11-12T00:00:00Z'::timestamptz,
  'SUCEDIDA with explicit existing VIGENTE successor',
  jsonb_build_object('decision_id',id,'state',st,'successor',succ,'effective_to',date_to));
END $$;

-- T19: SALY missing reference is found by same function (no edited function).
DO $$
DECLARE before_count int;after_count int;lf_count int;
BEGIN
 SELECT count(*) INTO before_count FROM find_noncurrent_references('saly');
 INSERT INTO rule_references(project_code,source_rule_code,target_rule_code,reference_kind)
 VALUES('saly','SALY-SYN-0003','SALY-SYN-9999','dependency');
 SELECT count(*) INTO after_count FROM find_noncurrent_references('saly');
 SELECT count(*) INTO lf_count FROM find_noncurrent_references('lf');
 PERFORM assert_l13('T19_SALY_SAME_FUNCTION_AND_ISOLATION',
 before_count=0 AND after_count=1 AND lf_count=3,
 'SALY 0->1 missing, LF 3 unchanged',
 jsonb_build_object('saly_before',before_count,'saly_after',after_count,'lf_after',lf_count));
END $$;

-- T20: even direct SUCEDIDA write with no successor fails (sandbox CHECK).
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  UPDATE rules SET state='SUCEDIDA'
   WHERE project_code='saly' AND rule_code='SALY-SYN-0005';
 EXCEPTION WHEN check_violation THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T20_NO_SUCCESSOR_CHECK_GUARD',blocked,
 '23514 CHECK successor is mandatory for SUCEDIDA',
 jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T21: read-only functions are PostgreSQL STABLE (not VOLATILE).
WITH f AS (
 SELECT proname,provolatile FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='rule_quality_l13'
   AND proname IN ('list_review_due','find_noncurrent_references','find_parameter_differences')
),a AS (SELECT count(*) AS n,count(*) FILTER(WHERE provolatile='s') AS stable FROM f)
SELECT assert_l13('T21_READ_ONLY_DETECTORS_STABLE',n=3 AND stable=3,
  '3 STABLE read-only functions',to_jsonb(a)) FROM a;

-- T22: no reader can decide rules.
DO $$
DECLARE blocked boolean:=false;err text:='';
BEGIN
 BEGIN
  PERFORM decide_rule_review('lf','LF-SYN-0009','lf-reader','EXPIRE',
   '{"source_ref":"SBX-22","rationale":"reader attempt"}'::jsonb,'2026-11-12T00:00:00Z');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true;err:=SQLERRM;
 END;
 PERFORM assert_l13('T22_NON_OWNER_REVIEW_REJECTED',blocked,
 '42501 BLOCK_NOT_OWNER_PROFILE',jsonb_build_object('rejected',blocked,'error',err));
END $$;

-- T23: owners, creators, source schemas and review decisions remain project-scoped.
WITH agg AS (
 SELECT (SELECT owner_name FROM projects WHERE project_code='lf') AS lf_owner,
        (SELECT created_by FROM projects WHERE project_code='lf') AS lf_creator,
        (SELECT count(*) FROM review_decisions WHERE project_code='lf') AS lf_decisions,
        (SELECT count(*) FROM review_decisions WHERE project_code='saly') AS saly_decisions)
SELECT assert_l13('T23_OWNER_CONFIG_AND_AUDIT',
 lf_owner='LF_GOVERNANCE' AND lf_creator='ChatGPT' AND lf_decisions=2 AND saly_decisions=0,
 'LF_GOVERNANCE/ChatGPT; 2 owner decisions in LF, 0 SALY',to_jsonb(agg)) FROM agg;

-- All 23 evidence rows are printed, and failure is signaled before a PASS is claimed.
SELECT test_id,status,expected,observed FROM sandbox_test_results ORDER BY test_id;
SELECT jsonb_build_object(
  'status',CASE WHEN count(*)=23 AND bool_and(status='PASS') THEN 'SANDBOX_TESTS_OK' ELSE 'SANDBOX_TESTS_INCOMPLETE' END,
  'tests',count(*),'passes',count(*) FILTER (WHERE status='PASS'),
  'projects',(SELECT jsonb_object_agg(project_code,n) FROM
    (SELECT project_code,count(*) AS n FROM rules GROUP BY project_code ORDER BY project_code) r)
) AS execution_summary
FROM sandbox_test_results;
