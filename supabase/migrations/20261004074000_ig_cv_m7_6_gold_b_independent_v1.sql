-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M7.6 / PAULO-145
-- Gold B independently adjudicated. Scope M7.6 only; no Validator change; no parallel authority.
-- SOURCE FIX: this migration CONSUMES verified external receipts; it never self-issues independent provenance.
-- Migration application remains governed separately; this source is fail-closed until 7 provider-bound receipts exist.
-- Gold B cases_sha256: 5540c8b369c80ceb15003c0a9b90a6ffaadcb03b68f0f781bfbc0e6221a5f60e
BEGIN;

DO $$
DECLARE v_n int; v_dep text; v_adr text;
BEGIN
  SELECT status INTO v_dep FROM programacion.engineering_work_items WHERE work_code='PAULO-121';
  IF v_dep IS DISTINCT FROM 'DONE' THEN RAISE EXCEPTION 'M1.7 not DONE'; END IF;

  SELECT estado INTO v_adr FROM transversal.decision_log
  WHERE adr='DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001';
  IF v_adr IS DISTINCT FROM 'VIGENTE' THEN
    RAISE EXCEPTION 'M1.7 adjudication authority not VIGENTE';
  END IF;

  SELECT count(*) INTO v_n FROM (VALUES(373::bigint),(374::bigint)) x(id)
  WHERE programacion.fn_input_readiness_run_is_current_cached_v2(id);
  IF v_n<>2 THEN RAISE EXCEPTION 'Currentness drift: runs 373/374'; END IF;

  SELECT count(*) INTO v_n FROM programacion.input_family_assessments
  WHERE run_id IN(373,374) AND severity='P0';
  IF v_n<>7 THEN RAISE EXCEPTION 'Critical set drift: expected 7, got %',v_n; END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code='M7_3_NEG_009_SELF_AUTHORITY'
      AND expected_output->>'decision'='REJECT_MUTATION_FAIL_CLOSED'
  ) THEN RAISE EXCEPTION 'M7.3 self-authority negative test missing/drifted'; END IF;
END $$;

CREATE TEMP TABLE _m76_gold_b(
 run_id bigint,
 pantalla_id int,
 family_code text,
 coverage text,
 well_defined text,
 source_observed_sha256_primary text,
 source_observed_sha256_secondary text,
 evidence_sha256 text,
 adjudication_sha256 text,
 source_refs text,
 rationale text
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
  SELECT count(*) INTO v_n FROM _m76_gold_b;
  IF v_n<>7 THEN RAISE EXCEPTION 'Gold B temp set != 7'; END IF;

  IF EXISTS(
    SELECT 1 FROM _m76_gold_b g
    LEFT JOIN programacion.input_family_assessments a
      ON a.run_id=g.run_id AND a.family_code=g.family_code
    WHERE a.run_id IS NULL OR a.severity<>'P0'
  ) THEN RAISE EXCEPTION 'Gold B includes non-governed critical case'; END IF;

  IF EXISTS(
    SELECT 1 FROM _m76_gold_b
    WHERE family_code='TRANSITIONS' AND source_observed_sha256_secondary IS NULL
  ) THEN RAISE EXCEPTION 'TRANSITIONS evidence missing secondary digest'; END IF;
END $$;

-- Independent evidence is produced outside this migration by the governed external issuer.
-- This migration only verifies/consumes those receipts. No token is read, guessed or injected here.
DO $$
DECLARE
  v_missing int;
  v_self int;
BEGIN
  SELECT count(*) INTO v_missing
  FROM _m76_gold_b g
  WHERE NOT EXISTS (
    SELECT 1
    FROM programacion.provenance_receipts r
    WHERE r.receipt_kind='AUDIT_VERDICT'
      AND r.issuer_channel='INDEPENDENT_AUDITOR_V1'
      AND r.subject_type='INPUT_GOV_GOLD_B_CRITICAL_CASE'
      AND r.subject_ref='IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||g.run_id||'-'||g.family_code
      AND r.subject_sha256=g.adjudication_sha256
      AND r.payload->>'verdict'='PASS'
      AND r.payload->'independent'='true'::jsonb
      AND r.payload->>'auditor_identity'=r.issuer_identity
      AND r.payload->>'adjudication_sha256'=g.adjudication_sha256
      AND r.payload->'expected' = jsonb_build_object(
        'severity','P0',
        'coverage_status',g.coverage,
        'well_defined_status',g.well_defined,
        'story_ready_status','BLOCKED',
        'implementation_ready_status','BLOCKED',
        'qa_ready_status','BLOCKED',
        'production_ready_status','BLOCKED'
      )
      AND r.payload->'oracle' = jsonb_build_object(
        'contract_revision','5.13',
        'story_rule','NO_STORY_STAGE_OPEN',
        'obligation_ref','supabase://public.lf_assurance_obligation_catalog/IG-C5_13-STORY_READY_RULE@1'
      )
      AND r.payload->'evidence' = jsonb_build_object(
        'mode','DIRECT_CANONICAL_READBACK_NOT_CURATOR_VALIDATOR_CONCLUSION',
        'source_refs',to_jsonb(string_to_array(g.source_refs,',')),
        'source_observed_sha256_primary',g.source_observed_sha256_primary,
        'source_observed_sha256_secondary',g.source_observed_sha256_secondary,
        'evidence_sha256',g.evidence_sha256,
        'contract_ref','supabase://programacion.contratos/37#5.13'
      )
  );
  IF v_missing<>0 THEN
    RAISE EXCEPTION 'M7.6 external Gold B receipts missing/drifted: %',v_missing;
  END IF;

  SELECT count(*) INTO v_self
  FROM _m76_gold_b g
  JOIN programacion.provenance_receipts p
    ON p.receipt_kind='AUDIT_VERDICT'
   AND p.issuer_channel='INDEPENDENT_AUDITOR_V1'
   AND p.subject_type='INPUT_GOV_GOLD_B_CRITICAL_CASE'
   AND p.subject_ref='IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||g.run_id||'-'||g.family_code
   AND p.subject_sha256=g.adjudication_sha256
  JOIN programacion.input_readiness_runs r ON r.id=g.run_id
  WHERE p.issuer_identity IN (r.curator_identity,r.validator_identity);

  IF v_self<>0 THEN RAISE EXCEPTION 'SELF_ADJUDICATION_REJECTED: %',v_self; END IF;
END $$;

-- Reuse the existing executable negative; do not manufacture an EVIDENCE_VERIFICATION receipt.
DO $$
DECLARE v_collision int;
BEGIN
  SELECT count(*) INTO v_collision
  FROM programacion.input_readiness_runs
  WHERE id IN(373,374)
    AND curator_identity=validator_identity;
  IF v_collision<>0 THEN
    RAISE EXCEPTION 'Curator/Validator identity collision in current Gold B runs: %',v_collision;
  END IF;
END $$;

UPDATE programacion.engineering_work_checkpoints
SET status='DONE',
    completed_at=now(),
    updated_at=now(),
    updated_by_execution_id='PAULO-145',
    evidence_ref=CASE checkpoint_code
      WHEN 'GOLD_ASIS' THEN 'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261004074000_ig_cv_m7_6_gold_b_independent_v1.sql#cases_sha256=5540c8b369c80ceb15003c0a9b90a6ffaadcb03b68f0f781bfbc0e6221a5f60e'
      WHEN 'ADJUDICATION_AUTHORITY' THEN 'supabase://transversal.decision_log/DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001'
      WHEN 'CRITICAL_CASE_SET' THEN 'supabase://programacion.provenance_receipts?subject_type=INPUT_GOV_GOLD_B_CRITICAL_CASE'
      WHEN 'INDEPENDENCE_NEGATIVE' THEN 'supabase://public.lf_test_suite_cases/INPUT_GOVERNANCE_REGRESSION/M7_3_NEG_009_SELF_AUTHORITY'
      WHEN 'GOLD_B_PERSISTED' THEN 'supabase://programacion.provenance_receipts?subject_type=INPUT_GOV_GOLD_B_CRITICAL_CASE&issuer_channel=INDEPENDENT_AUDITOR_V1'
      WHEN 'GOLD_B_READBACK' THEN 'supabase://programacion.provenance_receipts?subject_type=INPUT_GOV_GOLD_B_CRITICAL_CASE&issuer_channel=INDEPENDENT_AUDITOR_V1'
      ELSE evidence_ref
    END
WHERE work_item_id=458;

DO $$
DECLARE v_n int;v_w numeric;v_gold int;
BEGIN
  SELECT count(*),coalesce(sum(weight),0)
  INTO v_n,v_w
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=458 AND status='DONE';

  SELECT count(*) INTO v_gold
  FROM _m76_gold_b g
  JOIN programacion.provenance_receipts p
    ON p.receipt_kind='AUDIT_VERDICT'
   AND p.issuer_channel='INDEPENDENT_AUDITOR_V1'
   AND p.subject_type='INPUT_GOV_GOLD_B_CRITICAL_CASE'
   AND p.subject_ref='IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||g.run_id||'-'||g.family_code
   AND p.subject_sha256=g.adjudication_sha256
   AND p.payload->>'verdict'='PASS';

  IF v_n<>6 OR v_w<>100 OR v_gold<>7 THEN
    RAISE EXCEPTION 'M7.6 readback failed: checkpoints %, weight %, external_gold %',v_n,v_w,v_gold;
  END IF;
END $$;

UPDATE programacion.engineering_work_items
SET status='DONE',
    started_at=coalesce(started_at,now()),
    completed_at=now(),
    updated_at=now(),
    updated_by_execution_id='PAULO-145'
WHERE id=458 AND work_code='PAULO-145';

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,estado,evidencia,source_ref,updated_at)
SELECT 'IG-M7-6-GOLD-B-INDEPENDENT-001','INPUT_GOVERNANCE',
 'Gold B crítico requiere adjudicación separada de Curator/Validator',
 'M7.6 consume 7 AUDIT_VERDICT externos para casos CURRENT/P0; la migración no emite ni simula evidencia independiente.',
 'Usar self-adjudication, consenso como oracle o emitir el propio receipt crea falso verde.',
 'CURRENT/P0 -> fuente directa -> oracle 5.13 -> digest -> issuer externo -> receipt -> consumo fail-closed.',
 'Rechazar adjudicador igual a Curator/Validator; reutilizar M7_3_NEG_009/035/075; no leer/inventar tokens ni relajar el guard de provenance.',
 '7/7 AUDIT_VERDICT externos provider-bound, payload expected/oracle/evidence exacto, issuer distinto de Curator/Validator; cases_sha256=5540c8b369c80ceb15003c0a9b90a6ffaadcb03b68f0f781bfbc0e6221a5f60e.',
 'HIGH','ACTIVO',
 'supabase://programacion.provenance_receipts?subject_type=INPUT_GOV_GOLD_B_CRITICAL_CASE&issuer_channel=INDEPENDENT_AUDITOR_V1',
 'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261004074000_ig_cv_m7_6_gold_b_independent_v1.sql',now()
WHERE NOT EXISTS(
  SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M7-6-GOLD-B-INDEPENDENT-001'
);

COMMIT;
