-- IG package 2 (remainder): register in the append-only assurance catalog the 89 contract clauses (167 atoms) that
-- programacion.fn_input_contract_obligation_trace_v1() reports with no catalog obligation:
--   87 clauses of contracts 38 (CONTEXT_MANIFEST 2.0), 39 (FRESHNESS_DELTA 1.0), 40 (RETRIEVAL_HANDLE 2.0),
--   41 (MODULE_HEALTH 1.0), 42 (GOVERNANCE_EXECUTION 1.7), 47 (EXPLAIN_FAMILY_ASSESSMENT 1.0)
--   + 2 clauses new in contract 37 rev 5.13.1 (validator_evidence_required_fields_scope, validator_evidence_storage_contract).
-- Scope of the claim: REGISTRATION ONLY. Every row is CANDIDATO, mirroring the existing IG-* obligations (same claim class CLOSURE,
-- same CANDIDATE_ONLY_UNTIL_D_V2_3 mode, assurance_completeness RETIRED_NOT_USED). Nothing here proves a clause is enforced; each
-- obligation records semantic_test_status=PENDING_CLAUSE_SEMANTIC_TEST. verification_method is derived mechanically from the atom
-- classes of the clause (case-backed -> TEST, locator/identity -> ANALYSIS, descriptive/open -> INSPECTION).
-- evidence_contract carries contract_id + clause_key, which is what the trace function joins on.
-- The existing 60-obligation claim for contract 37 rev 5.13 is untouched (append-only; its required_obligation_count stays 60).
DO $ig_assurance_register$
DECLARE v_cl int; v_ob int; v_atoms int; v_pre_ob int; v_pre_cl int;
BEGIN
  SELECT count(*) INTO v_pre_ob FROM public.lf_assurance_obligation_catalog;
  SELECT count(*) INTO v_pre_cl FROM public.lf_assurance_claim_catalog;

  SELECT count(DISTINCT contract_code||'|'||split_part(obligation_key,'.',1)), count(*) INTO v_cl, v_atoms
    FROM programacion.fn_input_contract_obligation_trace_v1() WHERE catalog_obligation_code IS NULL;
  IF v_cl <> 89 OR v_atoms <> 167 THEN RAISE EXCEPTION 'IG_ASSURANCE_REGISTER_UNEXPECTED_SCOPE:%/%', v_cl, v_atoms; END IF;

  CREATE TEMP TABLE _ig_clause ON COMMIT DROP AS
  WITH map(contract_id, prefix) AS (VALUES
    (37::bigint,'C5_13_1'),(38,'CTX_2_0'),(39,'FRESH_1_0'),(40,'RETR_2_0'),(41,'HEALTH_1_0'),(42,'EXEC_1_7'),(47,'EXPL_1_0'))
  SELECT t.contract_id, m.prefix, c.especificacion->>'contract_revision' AS rev, c.contrato_codigo,
         split_part(t.obligation_key,'.',1) AS clause_key,
         array_agg(t.obligation_key ORDER BY t.obligation_key) AS atom_keys,
         array_agg(t.obligation_class ORDER BY t.obligation_key) AS atom_classes
    FROM programacion.fn_input_contract_obligation_trace_v1() t
    JOIN map m ON m.contract_id=t.contract_id
    JOIN programacion.contratos c ON c.id=t.contract_id
   WHERE t.catalog_obligation_code IS NULL
   GROUP BY t.contract_id, m.prefix, c.especificacion->>'contract_revision', c.contrato_codigo, split_part(t.obligation_key,'.',1);

  IF (SELECT count(*) FROM _ig_clause) <> 89 THEN RAISE EXCEPTION 'IG_ASSURANCE_REGISTER_CLAUSE_COUNT'; END IF;

  INSERT INTO public.lf_assurance_claim_catalog
    (claim_code, version, subject_type, subject_code, claim_class, claim_text, criticality, applicability, closure_rule,
     methodology_version, status, source_ref)
  SELECT CASE WHEN contract_id=37 THEN 'INPUT_GOVERNANCE_CONTRACT_5_13_1_DELTA_ASSURANCE_V1'
              ELSE 'INPUT_GOVERNANCE_CONTRACT_'||prefix||'_ASSURANCE_V1' END,
         1, 'OPERATION', 'EJECUCION_INPUT_GOVERNANCE_LF', 'CLOSURE',
         'Every clause of '||contrato_codigo||' rev '||rev||CASE WHEN contract_id=37 THEN ' added after rev 5.13' ELSE '' END||
         ' is traced to an implementation locator and a clause-level test before any material PASS; registration alone proves nothing.',
         'CRITICAL',
         jsonb_build_object('mode','CANDIDATE_ONLY_UNTIL_D_V2_3','contract_id',contract_id,'contract_revision',rev,
                            'contract_code',contrato_codigo,'assurance_capability','ASSURANCE_EVALUATOR',
                            'assurance_completeness','RETIRED_NOT_USED'),
         jsonb_build_object('activation_authority','EXACT_ORCHESTRATOR_DISPATCH_RECEIPT_PLUS_EXPLICIT_HUMAN_GO',
                            'required_obligation_count',count(*),'no_parallel_assurance_engine',true,
                            'global_pase_phase_completion_required',false,'all_required_obligations_must_be_resolved',true,
                            'material_pass_forbidden_on_missing_obligation',true),
         'LF_ASSURANCE_METHOD_V1', 'CANDIDATO',
         'supabase://programacion.contratos/'||contract_id||'#'||rev||'#assurance-register-remaining-v1'
    FROM _ig_clause GROUP BY contract_id, prefix, rev, contrato_codigo;

  INSERT INTO public.lf_assurance_obligation_catalog
    (obligation_code, version, claim_code, claim_version, requirement_ref, implementation_ref, verification_method,
     structural_coverage_mode, evidence_contract, failure_taxonomy_code, required, status, source_ref)
  SELECT 'IG-'||prefix||'-'||upper(clause_key), 1,
         CASE WHEN contract_id=37 THEN 'INPUT_GOVERNANCE_CONTRACT_5_13_1_DELTA_ASSURANCE_V1'
              ELSE 'INPUT_GOVERNANCE_CONTRACT_'||prefix||'_ASSURANCE_V1' END, 1,
         'supabase://programacion.contratos/'||contract_id||'#'||rev||'/'||clause_key,
         'supabase://programacion.fn_input_contract_obligation_trace_v1/'||contrato_codigo||'/'||clause_key,
         CASE WHEN atom_classes && ARRAY['A','B','D','G','J'] THEN 'TEST'
              WHEN atom_classes && ARRAY['C','E','F','H'] THEN 'ANALYSIS' ELSE 'INSPECTION' END,
         'NONE',
         jsonb_build_object('schema_version','IG_ASSURANCE_OBLIGATION_V1','contract_id',contract_id,'contract_revision',rev,
                            'clause_key',clause_key,'atom_keys',to_jsonb(atom_keys),'atom_classes',to_jsonb(atom_classes),
                            'traceability_source','programacion.fn_input_contract_obligation_trace_v1',
                            'semantic_test_status','PENDING_CLAUSE_SEMANTIC_TEST',
                            'registration_basis','MECHANICAL_FROM_CONTRACT_CLAUSE_NOT_SEMANTIC_PROOF',
                            'semantic_pass_requires_governed_evidence',true),
         'TRACEABILITY_BROKEN', true, 'CANDIDATO',
         'supabase://programacion.contratos/'||contract_id||'#'||rev||'/'||clause_key||'#assurance-register-remaining-v1'
    FROM _ig_clause;

  SELECT count(*) INTO v_ob FROM public.lf_assurance_obligation_catalog;
  IF v_ob - v_pre_ob <> 89 THEN RAISE EXCEPTION 'IG_ASSURANCE_REGISTER_OBLIGATION_DELTA:%', v_ob - v_pre_ob; END IF;
  IF (SELECT count(*) FROM public.lf_assurance_claim_catalog) - v_pre_cl <> 7 THEN RAISE EXCEPTION 'IG_ASSURANCE_REGISTER_CLAIM_DELTA'; END IF;
  IF EXISTS (SELECT 1 FROM programacion.fn_input_contract_obligation_trace_v1() WHERE catalog_obligation_code IS NULL) THEN
    RAISE EXCEPTION 'IG_ASSURANCE_REGISTER_STILL_UNCATALOGED'; END IF;
  IF (SELECT count(*) FROM programacion.fn_input_contract_obligation_trace_v1()) <> 331 THEN
    RAISE EXCEPTION 'IG_ASSURANCE_REGISTER_TRACE_TOTAL_CHANGED'; END IF;
END
$ig_assurance_register$;
