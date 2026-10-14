-- EKB M10.5: two distinct proven failures, one knowledge-only migration.
-- No production Edge, no operation state, no run verdict or new policy gates.
DO $ekb_m105_r17$
DECLARE
  c_a constant text := 'IG-M105-R17-EVENT-CONTRACT-MISCLASSIFIED-014';
  c_b constant text := 'TRAIN-MIGRATION-TEST-PATH-BRITTLE-015';
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN (c_a,c_b))
  THEN RAISE EXCEPTION 'EKB_R17_DUPLICATE_KNOWLEDGE'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_event_type_contract_audit_v2
    WHERE event_type='RUNTIME_PREFLIGHT' AND active
      AND contract_mode='OPERATIONAL'
      AND contract_version=2
      AND allowed_evidence_schemas=ARRAY['operational-event/v2']::text[]
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=20883 AND evento_tipo='RUNTIME_PREFLIGHT'
      AND payload->>'acceptance_declared'='false'
      AND payload->'read_measurement'->>'github_run_id'='38520767968'
  ) OR NOT EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE name='lf_ig_m105_r17_read_evidence_event_v1'
      AND version='20261014062911'
  ) THEN RAISE EXCEPTION 'EKB_R17_CANONICAL_READBACK_MISSING'; END IF;

  INSERT INTO public.lf_error_knowledge(
    codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref
  ) VALUES
  (
    c_a,'INPUT_GOVERNANCE',
    'R17 event classified as Skill test-evidence instead of operational preflight receipt',
    'The R17 prevention rule mandated an exact RUNTIME_PREFLIGHT event not present in the governed event catalog. PR #2595 registered it as VALIDATION_ACCEPTANCE/test-evidence/v2, but a direct inspection of private.fn_enforce_lf_eventos_test_evidence_v2 proved that schema requires a current Skill artifact, gate event and audit event. No RUNTIME_PREFLIGHT row had been inserted. PR #2596 corrected only that event contract using governed UPDATE to OPERATIONAL/operational-event/v2 v2. PR #2598 then persisted the first truthful partial measurement event 20883.',
    'The schema was selected by the name of its acceptance semantics without first reading the runtime trigger and the type-specific required entities. This made a new event contract structurally valid but semantically unusable.',
    'An event-type change may pass catalog governance yet reject its first real domain event because the evidence schema belongs to a different nature.',
    'Before creating an event type, read the live type-contract enforcement trigger, required related entities and the shared EVENT_CONTRACT_GOVERNANCE registry. Prefer a factual operational envelope when the event records preflight measurements; leave the actual R17 decision to the separately bound Operations judge. Test first positive domain payload and negative false-acceptance packet. Never fabricate a PASS or bypass the catalog.',
    'Train #38521320902 registered type v1; live trigger review found Skill-specific required row/gate/audit; Train #38521811070 corrected type v2; live audit contract_mode OPERATIONAL, schema operational-event/v2, current contract_version 2. Train #38522418887 inserted event 20883 with real Management run #38520767968, acceptance_declared false, no effect executed, no CP2 runs.',
    'ALTA',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5/CP2',
    'PR #2595; PR #2596; PR #2598','resuelto',
    'Public event type audit v2; event 20883; R17 Management read artifact 38520767968; Train runs 38521320902,38521811070,38522418887',
    clock_timestamp(),clock_timestamp(),
    'GOVERNED_EVENT_CONTRACT',ARRAY['OPERATION_EXECUTOR','ENGINEERING_VALIDATOR']::text[],
    'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
    'First real R17 preflight for M10.5; operational facts not automatic acceptance',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2596'
  ),
  (
    c_b,'TRANSVERSAL_ENGINEERING',
    'Train-renumbered SQL migration broke tests using hardcoded timestamped filenames',
    'CI on M10.5 R17 failed after Merge Train renumbered a merged SQL migration: unittest looked for 20261014064000_lf_ig_m105_r17_event_nature_correction_v1.sql but the canonical filename had become 20261014062501_lf_ig_m105_r17_event_nature_correction_v1.sql. A second new test would have repeated the error on the next Train retimestamp. PR #2598 corrected both tests to glob the stable migration semantic suffix and reject zero or multiple matches, with CI green on the corrected HEAD.',
    'Tests coupled source location to a mutable Train-assigned timestamp rather than the stable semantic migration identifier.',
    'Renumbering a migration during Train sync silently invalidates tests and produces repeated FAIL even when the SQL is correct.',
    'In every migration test that must survive Train retimestamping, locate the migration by its stable semantic suffix in supabase/migrations and assert exactly one match. Never hardcode the 14-digit migration version in a test file unless version immutability itself is under test.',
    'PR #2598 initial CI FAILED because previous merged SQL filename changed; tests updated to stable suffix glob with unique-match assertion; subsequent test, classification, admission, and route checks succeeded. Train #38522418887 SUCCESS; ledger 20261014062911 and final event 20883 read back.',
    'MEDIA',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5/CP2',
    'PR #2598','resuelto',
    'GitHub PR #2598 CI test before/after; merge Train #38522418887; supabase_migrations.schema_migrations 20261014062911; final event 20883',
    clock_timestamp(),clock_timestamp(),
    'MIGRATION_TEST_RESILIENCE',ARRAY['ENGINEERING_VALIDATOR','MIGRATION_TRAIN_CONSUMER']::text[],
    'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
    'Generic prevention across any LF Train-managed migration, not product-owned',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2598'
  );

  IF (SELECT count(*) FROM public.lf_error_knowledge
      WHERE codigo IN(c_a,c_b) AND estado='resuelto')<>2
  THEN RAISE EXCEPTION 'EKB_R17_READBACK_FAILED'; END IF;
END $ekb_m105_r17$;
