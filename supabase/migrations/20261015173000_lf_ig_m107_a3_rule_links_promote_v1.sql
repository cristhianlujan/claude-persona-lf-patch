-- IG M10.7 A3: promote proven in-statement rule links candidate to canonical.
-- Exactly one atomic DO: preflight + equivalence + replacement + post-apply + EKB.
-- No change of rule resolver, triggers, selectors, privileges or inter-call context.
DO $a3$
DECLARE
 v_canonical constant text := 'programacion.fn_input_subject_depth_expected_v510';
 v_candidate constant text := 'programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1';
 v_ekb constant text := 'IG-M107-A3-INCALL-CANONICAL-PROMOTION-016';
 v_old_def text;
 v_candidate_def text;
 v_expected_def text;
 v_old jsonb;
 v_cand jsonb;
 v_screen integer;
 v_family text;
 v_old_error text;
 v_cand_error text;
 v_evidence jsonb;
 v_ekb_prior jsonb;
 v_acl_before text;
 v_acl_after text;
BEGIN
 -- Fail closed on source drift, history and operation conflicts.
 v_old_def:=pg_get_functiondef('programacion.fn_input_subject_depth_expected_v510(integer,text)'::regprocedure);
 v_candidate_def:=pg_get_functiondef('programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(integer,text)'::regprocedure);
 IF md5(v_old_def)<>'83c6b61cd23cc0c57abbd8ee4831f8b5'
    OR md5(v_candidate_def)<>'70abaee8cb0426fc02b1e1d1c2cf088d' THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_SOURCE_DRIFT';
 END IF;
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_ekb) THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_ALREADY_RECORDED';
 END IF;
 SELECT evidencia::jsonb INTO v_ekb_prior FROM public.lf_error_knowledge
 WHERE codigo='IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015'
   AND upper(estado)='ACTIVO';
 IF v_ekb_prior IS NULL
    OR coalesce(jsonb_array_length(v_ekb_prior->'repeated_security_samples'),0)<>10
    OR coalesce((v_ekb_prior->>'design_system_unchanged')::boolean,false) IS DISTINCT FROM true
    OR coalesce((v_ekb_prior->>'no_cross_call_cache')::boolean,false) IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_ekb_prior->'repeated_security_samples') j
       WHERE (j->>'json_exact_equal') IS DISTINCT FROM 'true'
          OR (j->>'sha_equal') IS DISTINCT FROM 'true') THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_CANDIDATE_EVIDENCE_NOT_VALID';
 END IF;
 SELECT p.proacl::text INTO v_acl_before FROM pg_proc p
 WHERE p.oid='programacion.fn_input_subject_depth_expected_v510(integer,text)'::regprocedure;
 IF v_acl_before IS DISTINCT FROM '{postgres=X/postgres}' THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_ACL_CHANGED';
 END IF;
 -- Positive and negative scope, and digest equality, before changing canonical.
 FOREACH v_screen IN ARRAY ARRAY[1,43,53,55,58] LOOP
   FOREACH v_family IN ARRAY ARRAY['SECURITY','DESIGN_SYSTEM'] LOOP
     v_old:=programacion.fn_input_subject_depth_expected_v510(v_screen,v_family);
     v_cand:=programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(v_screen,v_family);
     IF v_old IS DISTINCT FROM v_cand
        OR programacion.fn_v09_sha256_jsonb(v_old)
           IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_cand) THEN
       RAISE EXCEPTION 'IG_M107_A3_PROMOTE_PRE_PARITY_FAIL_%_%',v_screen,v_family;
     END IF;
   END LOOP;
 END LOOP;
 v_old_error:=NULL;v_cand_error:=NULL;v_old:=NULL;v_cand:=NULL;
 BEGIN
   v_old:=programacion.fn_input_subject_depth_expected_v510(2147483647,'SECURITY');
 EXCEPTION WHEN OTHERS THEN v_old_error:=SQLSTATE||':'||SQLERRM;
 END;
 BEGIN
   v_cand:=programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(2147483647,'SECURITY');
 EXCEPTION WHEN OTHERS THEN v_cand_error:=SQLSTATE||':'||SQLERRM;
 END;
 IF v_old_error IS DISTINCT FROM v_cand_error OR v_old IS DISTINCT FROM v_cand THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_PRE_MISSING_SCREEN_DIFFERENCE';
 END IF;
 -- Rewrite only the fully-qualified function name, using the exact candidate body.
 -- CREATE OR REPLACE keeps grants/owner; the whole DO rolls back on any failed test.
 IF position('FUNCTION '||v_candidate||'(' IN v_candidate_def)=0 THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_HEADER_MISSING';
 END IF;
 v_expected_def:=replace(v_candidate_def,v_candidate,v_canonical);
 IF v_expected_def=v_candidate_def THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_NO_REPLACEMENT';
 END IF;
 EXECUTE v_expected_def;
 IF pg_get_functiondef('programacion.fn_input_subject_depth_expected_v510(integer,text)'::regprocedure)
      IS DISTINCT FROM v_expected_def THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_RESULT_DEF_MISMATCH';
 END IF;
 SELECT p.proacl::text INTO v_acl_after FROM pg_proc p
 WHERE p.oid='programacion.fn_input_subject_depth_expected_v510(integer,text)'::regprocedure;
 IF v_acl_after IS DISTINCT FROM v_acl_before
    OR has_function_privilege('anon','programacion.fn_input_subject_depth_expected_v510(integer,text)','EXECUTE')
    OR has_function_privilege('authenticated','programacion.fn_input_subject_depth_expected_v510(integer,text)','EXECUTE')
    OR has_function_privilege('service_role','programacion.fn_input_subject_depth_expected_v510(integer,text)','EXECUTE') THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_PRIVILEGE_REGRESSION';
 END IF;
 FOREACH v_screen IN ARRAY ARRAY[1,43,53,55,58] LOOP
   FOREACH v_family IN ARRAY ARRAY['SECURITY','DESIGN_SYSTEM'] LOOP
     v_old:=programacion.fn_input_subject_depth_expected_v510(v_screen,v_family);
     v_cand:=programacion.fn_input_subject_depth_expected_v510_rule_snapshot_candidate_v1(v_screen,v_family);
     IF v_old IS DISTINCT FROM v_cand
        OR programacion.fn_v09_sha256_jsonb(v_old)
           IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_cand) THEN
       RAISE EXCEPTION 'IG_M107_A3_PROMOTE_POST_PARITY_FAIL_%_%',v_screen,v_family;
     END IF;
   END LOOP;
 END LOOP;
 v_evidence:=jsonb_build_object(
   'schema','IG_M107_A3_CANONICAL_PROMOTION_V1',
   'canonical_old_md5','83c6b61cd23cc0c57abbd8ee4831f8b5',
   'candidate_md5','70abaee8cb0426fc02b1e1d1c2cf088d',
   'source_ekb','IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015',
   'screens',jsonb_build_array(1,43,53,55,58),
   'families',jsonb_build_array('SECURITY','DESIGN_SYSTEM'),
   'pre_and_post_json_sha_equal',true,'negative_missing_screen_equal',true,
   'preserved_acl',true,'rule_changes',false,'trigger_changes',false,
   'cross_call_context_enabled',false,'source_mutation_tested',false,
   'validator_total_time_proven',false,'cp3_closed',false);
 INSERT INTO public.lf_error_knowledge(
   id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
   validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
   estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
   detectability,source_context,source_ref)
 VALUES(
   gen_random_uuid(),v_ekb,'GOVERNANCE',
   'A3 promoción de vínculos efectivos reutilizados dentro de sentencia canónica',
   'Cambio transversal del cuerpo de subject_depth_expected_v510. Comparación exacta JSONB/SHA previa y posterior para 5 pantallas, SECURITY y DESIGN_SYSTEM. Sin alterar reglas, triggers, privilegios o resolvedor de autoridad.',
   '17 resoluciones repetidas de vínculos de reglas en SECURITY de la misma sentencia.',
   'INSTATEMENT_EFFECTIVE_LINKS_MATERIALIZED_CANONICAL',
   'Conservar currentness fail-closed. Nunca compartir contexto entre llamadas sin G2B; no inferir mejora de tiempo del Validator de esta función.',
   'En Migration Train: MD5 de ambas fuentes, EKB 10/10, paridad 10 casos antes y después, negativo pantalla inexistente, equivalencia fuente de CREATE OR REPLACE, ACL exacto; fallo revierte todo el DO.',
   'HIGH',1,clock_timestamp(),clock_timestamp(),
   'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
   v_evidence::text,clock_timestamp(),clock_timestamp(),'PREFLIGHT',
   'R4_NO_CUESTIONA','LOUD_EARLY',
   'Candidate A3 to canonical, authorized LF Migration Train',
   'programacion.fn_input_subject_depth_expected_v510(integer,text)'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_ekb)<>1 THEN
   RAISE EXCEPTION 'IG_M107_A3_PROMOTE_EKB_POST_READBACK_FAIL';
 END IF;
END $a3$;
