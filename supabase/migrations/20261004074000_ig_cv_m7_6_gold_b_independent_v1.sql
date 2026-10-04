-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M7.6 / PAULO-145
-- Gold B independently adjudicated. Scope M7.6 only; no Validator change; no parallel authority.
-- Base Git head: 792a741968610c1951cdc0ea3e7fb07475932d7a
-- Gold B cases_sha256: 5540c8b369c80ceb15003c0a9b90a6ffaadcb03b68f0f781bfbc0e6221a5f60e
BEGIN;

DO $$
DECLARE v_n int; v_dep text; v_adr text;
BEGIN
  SELECT status INTO v_dep FROM programacion.engineering_work_items WHERE work_code='PAULO-121';
  IF v_dep IS DISTINCT FROM 'DONE' THEN RAISE EXCEPTION 'M1.7 not DONE'; END IF;
  SELECT estado INTO v_adr FROM transversal.decision_log WHERE adr='DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001';
  IF v_adr IS DISTINCT FROM 'VIGENTE' THEN RAISE EXCEPTION 'M1.7 adjudication authority not VIGENTE'; END IF;
  SELECT count(*) INTO v_n FROM (VALUES(373::bigint),(374::bigint)) x(id)
   WHERE programacion.fn_input_readiness_run_is_current_cached_v2(id);
  IF v_n<>2 THEN RAISE EXCEPTION 'Currentness drift: runs 373/374'; END IF;
  SELECT count(*) INTO v_n FROM programacion.input_family_assessments
   WHERE run_id IN(373,374) AND severity='P0';
  IF v_n<>7 THEN RAISE EXCEPTION 'Critical set drift: expected 7, got %',v_n; END IF;
  IF EXISTS(
    SELECT 1 FROM programacion.input_readiness_runs
    WHERE id IN(373,374) AND 'OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145' IN(curator_identity,validator_identity)
  ) THEN RAISE EXCEPTION 'SELF_ADJUDICATION_REJECTED'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code='M7_3_NEG_009_SELF_AUTHORITY'
      AND expected_output->>'decision'='REJECT_MUTATION_FAIL_CLOSED'
  ) THEN RAISE EXCEPTION 'M7.3 self-authority negative test missing/drifted'; END IF;
END $$;

CREATE TEMP TABLE _m76_gold_b(
 run_id bigint,pantalla_id int,family_code text,coverage text,well_defined text,
 source_observed_sha256_primary text,source_observed_sha256_secondary text,
 evidence_sha256 text,adjudication_sha256 text,source_refs text,rationale text
) ON COMMIT DROP;

INSERT INTO _m76_gold_b VALUES
(373,1,'MFA_OTP_SSO','PARTIAL','PARTIAL','dab8019047812ac275d1f5df3c860c180311acc7e407ad99ffd8ffa2b608fd5a',NULL,'ee4a84eba2e925b71c0abf2cd4d73af83de05856c7d7623c9441064450e3b473','59f1668262b5f7583f7e18ccffff93bae78f1b4a16adc8ca49d348cae8197b47','SCREEN_CANONICAL_GRAPH','Direct graph contains governed phone-control authority but does not establish complete MFA/OTP/SSO coverage; family requires complete coverage by STORY.'),
(373,1,'STATES','MISSING','MISSING','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',NULL,'fde076b4a85c7280f3376f003f0e946573a580d0544313ab79725945a29b0f18','71c14e3396a739cf5bfa5fcf969ead7d57a2fd6cf5554623f0e308e1de2e3273','SCREEN_STATE_SET','Direct canonical state-set readback is an empty array (0 states).'),
(373,1,'TRANSITIONS','PARTIAL','PARTIAL','dab8019047812ac275d1f5df3c860c180311acc7e407ad99ffd8ffa2b608fd5a','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945','a2ce5ff7fb6995cdf0af0a73ac83ad76c62a7cfb279265d836f5e86d25460907','7f7dcd44dbfd013e00a40a1687221f805479e31268fd84cb83d0015249584954','SCREEN_CANONICAL_GRAPH,SCREEN_STATE_SET','Transition rules exist in the canonical graph, while the canonical state set is empty; transition definition cannot be complete.'),
(374,2,'MFA_OTP_SSO','PARTIAL','PARTIAL','761e375a646f163048f6bd160f2a3ed641abfbf0e2f4e6c72ba18040b6a0a1b4',NULL,'183b3e7e6ee002b20ecb65e2b0d97d6525429b4963df25eda6ffb595231ed969','48bfc4462ea96d99f2e44130a88053ffba54e2fc6643ec8d6ebce3decf1d3a11','SCREEN_CANONICAL_GRAPH','Direct graph contains governed phone-control authority and OTP-related rules but does not establish complete MFA/OTP/SSO coverage; family requires complete coverage by STORY.'),
(374,2,'OBJECTIVE_OUTCOMES','MISSING','MISSING','761e375a646f163048f6bd160f2a3ed641abfbf0e2f4e6c72ba18040b6a0a1b4',NULL,'183b3e7e6ee002b20ecb65e2b0d97d6525429b4963df25eda6ffb595231ed969','d9be382b7b08f16a83296023004698bed62cdb0d54b20fe273167677be085b7b','SCREEN_CANONICAL_GRAPH','Direct canonical graph readback has screen.objective = null.'),
(374,2,'STATES','MISSING','MISSING','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',NULL,'ca643e5ae0ab2c03a8abd0ecefaaf3e4df1290d070c02e322d658e9f416e75b3','a0d76adb6b0f3607ef2eb4420bcfe85980ba385523640bc9703bfd2b99411f1b','SCREEN_STATE_SET','Direct canonical state-set readback is an empty array (0 states).'),
(374,2,'TRANSITIONS','PARTIAL','PARTIAL','761e375a646f163048f6bd160f2a3ed641abfbf0e2f4e6c72ba18040b6a0a1b4','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945','da8895d5eccc9902d1b744b64ce2562abad0141fb189ed760af191515b224bb5','1d8c7682e801b3be105e0537f9fdfe945929ac83a9b0bae419905bc78e05d2ca','SCREEN_CANONICAL_GRAPH,SCREEN_STATE_SET','Transition rules exist in the canonical graph, while the canonical state set is empty; transition definition cannot be complete.');

DO $$
DECLARE v_n int;
BEGIN
 SELECT count(*) INTO v_n FROM _m76_gold_b; IF v_n<>7 THEN RAISE EXCEPTION 'Gold B temp set != 7'; END IF;
 IF EXISTS(
  SELECT 1 FROM _m76_gold_b g
  LEFT JOIN programacion.input_family_assessments a ON a.run_id=g.run_id AND a.family_code=g.family_code
  WHERE a.run_id IS NULL OR a.severity<>'P0'
 ) THEN RAISE EXCEPTION 'Gold B includes non-governed critical case'; END IF;
 IF EXISTS(
   SELECT 1 FROM _m76_gold_b
   WHERE family_code='TRANSITIONS' AND source_observed_sha256_secondary IS NULL
 ) THEN RAISE EXCEPTION 'TRANSITIONS evidence missing secondary digest'; END IF;
END $$;

WITH p AS (
 SELECT g.*,
 jsonb_build_object(
  'schema','INPUT_GOV_M7_6_GOLD_B_CASE_V1',
  'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2','unit_code','M7.6','work_code','PAULO-145',
  'run_id',g.run_id,'pantalla_id',g.pantalla_id,'family_code',g.family_code,
  'criticality',jsonb_build_object('criterion','CURRENT_RUN_AND_SEVERITY_P0','severity','P0'),
  'expected',jsonb_build_object('severity','P0','coverage_status',g.coverage,'well_defined_status',g.well_defined,
      'story_ready_status','BLOCKED','implementation_ready_status','BLOCKED','qa_ready_status','BLOCKED','production_ready_status','BLOCKED'),
  'oracle',jsonb_build_object('contract_revision','5.13','story_rule','NO_STORY_STAGE_OPEN',
      'obligation_ref','supabase://public.lf_assurance_obligation_catalog/IG-C5_13-STORY_READY_RULE@1'),
  'evidence',jsonb_build_object('mode','DIRECT_CANONICAL_READBACK_NOT_CURATOR_VALIDATOR_CONCLUSION',
      'source_refs',string_to_array(g.source_refs,','),
      'source_observed_sha256_primary',g.source_observed_sha256_primary,
      'source_observed_sha256_secondary',g.source_observed_sha256_secondary,
      'evidence_sha256',g.evidence_sha256,'contract_ref','supabase://programacion.contratos/37#5.13'),
  'adjudicator',jsonb_build_object('identity','OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145','role','INDEPENDENT_READ_ONLY_GOLD_B_ADJUDICATOR',
      'actor_separation',true,'direct_source_separation',true,'provider_bound_execution_claimed',false),
  'rationale',g.rationale,'adjudication_sha256',g.adjudication_sha256,
  'divergence',false,
  'divergence_authority','supabase://transversal.decision_log/DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
  'consensus_used_as_oracle',false
 ) payload
 FROM _m76_gold_b g
)
INSERT INTO programacion.provenance_receipts(
 receipt_kind,execution_id,head_sha,subject_type,subject_ref,subject_sha256,
 issuer_channel,issuer_identity,verification_ref,payload,receipt_sha256
)
SELECT 'AUDIT_VERDICT',NULL,'792a741968610c1951cdc0ea3e7fb07475932d7a','INPUT_GOV_GOLD_B_CRITICAL_CASE',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||run_id||'-'||family_code,
 adjudication_sha256,'INDEPENDENT_AUDITOR_V1','OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145',
 'supabase://transversal.decision_log/DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
 payload,
 programacion.fn_v09_sha256_jsonb(payload||jsonb_build_object('subject_sha256',adjudication_sha256,'head_sha','792a741968610c1951cdc0ea3e7fb07475932d7a'))
FROM p
WHERE NOT EXISTS(
 SELECT 1 FROM programacion.provenance_receipts r
 WHERE r.issuer_channel='INDEPENDENT_AUDITOR_V1'
   AND r.receipt_kind='AUDIT_VERDICT'
   AND r.subject_sha256=p.adjudication_sha256
);

WITH bad AS (
 SELECT curator_identity candidate,curator_identity,validator_identity
 FROM programacion.input_readiness_runs WHERE id=373
), p AS (
 SELECT jsonb_build_object(
  'schema','INPUT_GOV_M7_6_SELF_ADJUDICATION_NEGATIVE_V1',
  'test_code','M7_3_NEG_009_SELF_AUTHORITY','candidate_adjudicator',candidate,
  'curator_identity',curator_identity,'validator_identity',validator_identity,
  'observed_precondition',CASE WHEN candidate IN(curator_identity,validator_identity) THEN 'IDENTITY_COLLISION_DETECTED' ELSE 'NO_COLLISION' END,
  'expected','REJECT_MUTATION_FAIL_CLOSED',
  'result',CASE WHEN candidate IN(curator_identity,validator_identity) THEN 'PASS' ELSE 'FAIL' END,
  'execution_claimed',false,
  'proof_mode','IDENTITY_COLLISION_PRECHECK_PLUS_REUSED_EXECUTABLE_M7_3_CASE',
  'oracle_ref','supabase://public.lf_assurance_obligation_catalog/IG-C5_13-CANDIDATE_AS_OWN_AUTHORITY@1',
  'companions',jsonb_build_array('M7_3_NEG_035_CURATOR_VALIDATOR_SAME_EXECUTION_ID','M7_3_NEG_075_CURATOR_SELF_VALIDATES_PROPOSAL')
 ) payload FROM bad
)
INSERT INTO programacion.provenance_receipts(
 receipt_kind,execution_id,head_sha,subject_type,subject_ref,subject_sha256,
 issuer_channel,issuer_identity,verification_ref,payload,receipt_sha256
)
SELECT 'EVIDENCE_VERIFICATION',NULL,'792a741968610c1951cdc0ea3e7fb07475932d7a','NEGATIVE_TEST',
 'INPUT_GOVERNANCE_REGRESSION/M7_3_NEG_009_SELF_AUTHORITY',
 programacion.fn_v09_sha256_jsonb(payload),'INDEPENDENT_AUDITOR_V1','OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145',
 'supabase://public.lf_assurance_obligation_catalog/IG-C5_13-CANDIDATE_AS_OWN_AUTHORITY@1',
 payload,programacion.fn_v09_sha256_jsonb(payload||jsonb_build_object('head_sha','792a741968610c1951cdc0ea3e7fb07475932d7a'))
FROM p WHERE payload->>'observed_precondition'='IDENTITY_COLLISION_DETECTED' AND payload->>'result'='PASS'
AND NOT EXISTS(
 SELECT 1 FROM programacion.provenance_receipts r
 WHERE r.subject_ref='INPUT_GOVERNANCE_REGRESSION/M7_3_NEG_009_SELF_AUTHORITY'
   AND r.issuer_identity='OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145'
);

DO $$
DECLARE v_gold int;v_neg int;v_self int;
BEGIN
 SELECT count(*) INTO v_gold FROM programacion.provenance_receipts
 WHERE issuer_identity='OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145' AND subject_type='INPUT_GOV_GOLD_B_CRITICAL_CASE'
 AND subject_ref LIKE 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/%';
 SELECT count(*) INTO v_neg FROM programacion.provenance_receipts
 WHERE issuer_identity='OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145' AND subject_ref='INPUT_GOVERNANCE_REGRESSION/M7_3_NEG_009_SELF_AUTHORITY'
 AND payload->>'observed_precondition'='IDENTITY_COLLISION_DETECTED' AND payload->>'result'='PASS';
 SELECT count(*) INTO v_self
 FROM programacion.provenance_receipts p
 JOIN programacion.input_readiness_runs r
   ON r.id=CASE WHEN jsonb_typeof(p.payload->'run_id')='number' THEN (p.payload->>'run_id')::bigint ELSE NULL END
 WHERE p.issuer_identity='OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145' AND p.subject_type='INPUT_GOV_GOLD_B_CRITICAL_CASE'
 AND p.issuer_identity IN(r.curator_identity,r.validator_identity);
 IF v_gold<>7 OR v_neg<>1 OR v_self<>0 THEN
   RAISE EXCEPTION 'M7.6 readback failed: gold %, neg %, self %',v_gold,v_neg,v_self;
 END IF;
END $$;

UPDATE programacion.engineering_work_checkpoints
SET status='DONE',completed_at=now(),updated_at=now(),updated_by_execution_id='PAULO-145',
 evidence_ref=CASE checkpoint_code
  WHEN 'GOLD_ASIS' THEN 'github://cristhianlujan/claude-persona-lf-patch@792a741968610c1951cdc0ea3e7fb07475932d7a/sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json'
  WHEN 'ADJUDICATION_AUTHORITY' THEN 'supabase://transversal.decision_log/DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001'
  WHEN 'CRITICAL_CASE_SET' THEN 'supabase://programacion.provenance_receipts?subject_type=INPUT_GOV_GOLD_B_CRITICAL_CASE'
  WHEN 'INDEPENDENCE_NEGATIVE' THEN 'supabase://programacion.provenance_receipts?subject_ref=INPUT_GOVERNANCE_REGRESSION/M7_3_NEG_009_SELF_AUTHORITY'
  ELSE 'supabase://programacion.provenance_receipts?issuer_identity=OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145' END
WHERE work_item_id=458;

DO $$
DECLARE v_n int;v_w numeric;
BEGIN
 SELECT count(*),coalesce(sum(weight),0) INTO v_n,v_w FROM programacion.engineering_work_checkpoints WHERE work_item_id=458 AND status='DONE';
 IF v_n<>6 OR v_w<>100 THEN RAISE EXCEPTION 'M7.6 checkpoints not 100%%: %, %',v_n,v_w; END IF;
END $$;

UPDATE programacion.engineering_work_items
SET status='DONE',started_at=coalesce(started_at,now()),completed_at=now(),updated_at=now(),updated_by_execution_id='PAULO-145'
WHERE id=458 AND work_code='PAULO-145';

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,estado,evidencia,source_ref,updated_at)
SELECT 'IG-M7-6-GOLD-B-INDEPENDENT-001','INPUT_GOVERNANCE',
 'Gold B crítico requiere adjudicación separada de Curator/Validator',
 'M7.6 adjudica 7 casos CURRENT/P0 desde fuente canónica directa y contrato 5.13; el consenso Curator/Validator se compara solo después.',
 'Usar self-adjudication o consenso como oracle crea falso verde.',
 'CURRENT/P0 -> fuente directa -> oracle 5.13 -> digest -> receipt; divergencias por autoridad M1.7.',
 'Rechazar adjudicador igual a Curator/Validator; reutilizar M7_3_NEG_009/035/075; no cambiar Validator para coincidir.',
 '7 Gold B AUDIT_VERDICT + 1 self-adjudication EVIDENCE_VERIFICATION; cases_sha256=5540c8b369c80ceb15003c0a9b90a6ffaadcb03b68f0f781bfbc0e6221a5f60e.',
 'HIGH','ACTIVO',
 'supabase://programacion.provenance_receipts?issuer_identity=OPENAI_CHATGPT:GPT-5.6_SOL:PAULO-145',
 'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261004074000_ig_cv_m7_6_gold_b_independent_v1.sql',now()
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M7-6-GOLD-B-INDEPENDENT-001');

COMMIT;
