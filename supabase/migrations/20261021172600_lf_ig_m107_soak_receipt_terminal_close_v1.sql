-- IG M10.7 terminal SOAK_RECEIPT readback closure.
-- Exact declared readback observed EVIDENCE_VERIFICATION n=1110,
-- last_at=2026-10-17 00:59:58.709843+00.
-- No production activation and no domain mutation.

BEGIN;

DO $close$
DECLARE
  v_cp record;
  v_progress numeric;
  v_ev_count bigint;
  v_ev_last timestamptz;
  v_receipt record;
  v_prior_done int;
  v_transition jsonb;
  v_evidence_ref constant text :=
    'supabase://programacion.provenance_receipts?readback=receipt_kind_summary;kind=EVIDENCE_VERIFICATION;n=1110;last_at=2026-10-17T00:59:58.709843Z';
BEGIN
  SELECT status,evidence_ref,assertion_receipt_sha256
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478
    AND checkpoint_code='SOAK_RECEIPT'
  FOR UPDATE;

  IF v_cp.status IS DISTINCT FROM 'PENDING'
     OR v_cp.evidence_ref IS NOT NULL
     OR v_cp.assertion_receipt_sha256 IS NOT NULL
  THEN
    RAISE EXCEPTION 'M107_SOAK_RECEIPT_PRESTATE_DRIFT:%',row_to_json(v_cp);
  END IF;

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=478;

  IF v_progress IS DISTINCT FROM 80.00 THEN
    RAISE EXCEPTION 'M107_SOAK_RECEIPT_PROGRESS_PRESTATE_DRIFT:%',v_progress;
  END IF;

  SELECT count(*) INTO v_prior_done
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478
    AND checkpoint_code IN (
      'SOAK_CRITERIA_ASIS',
      'OBSERVATION_COVERAGE',
      'NO_FALSE_PASS',
      'NEG_INSUFFICIENT'
    )
    AND status='DONE';

  IF v_prior_done IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'M107_SOAK_RECEIPT_PRIOR_CHECKPOINTS_NOT_DONE:%',v_prior_done;
  END IF;

  SELECT count(*),max(created_at)
    INTO v_ev_count,v_ev_last
  FROM programacion.provenance_receipts
  WHERE receipt_kind='EVIDENCE_VERIFICATION';

  IF v_ev_count < 1110 OR v_ev_last IS NULL THEN
    RAISE EXCEPTION 'M107_SOAK_RECEIPT_AGGREGATE_READBACK_FAIL:%/%',v_ev_count,v_ev_last;
  END IF;

  SELECT id,receipt_kind,subject_type,subject_ref,payload,receipt_sha256
    INTO v_receipt
  FROM programacion.provenance_receipts
  WHERE id=38;

  IF v_receipt.id IS NULL
     OR v_receipt.receipt_kind IS DISTINCT FROM 'EVIDENCE_VERIFICATION'
     OR v_receipt.subject_type IS DISTINCT FROM 'ig_soak_observation_history'
     OR v_receipt.subject_ref IS DISTINCT FROM 'plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2'
     OR v_receipt.receipt_sha256 IS DISTINCT FROM '17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972'
     OR v_receipt.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED'
     OR v_receipt.payload->>'pass' IS DISTINCT FROM 'true'
     OR (v_receipt.payload->>'screens_total')::int IS DISTINCT FROM 13
     OR (v_receipt.payload->>'families_total')::int IS DISTINCT FROM 47
     OR (v_receipt.payload->>'min_screen_observations')::int < 2
     OR (v_receipt.payload->>'min_family_observations')::int < 2
     OR (v_receipt.payload->>'known_false_pass_signals')::int IS DISTINCT FROM 0
     OR (v_receipt.payload->>'unresolved_d4')::int IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'M107_SOAK_RECEIPT_AUTHORITY_FAIL:%',row_to_json(v_receipt);
  END IF;

  v_transition := programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.7',
    'SOAK_RECEIPT',
    'DONE',
    v_evidence_ref,
    'GPT_NATIVE:M10.7:SOAK_RECEIPT',
    'Terminal readback PASS. Declared query observed EVIDENCE_VERIFICATION n=1110 and last_at=2026-10-17T00:59:58.709843Z. Canonical soak authority receipt 38 remains VERIFIED with SHA 17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972; 13/13 screens; 47/47 families; min observations >=2; false-pass=0; D4=0. NO_FALSE_PASS and NEG_INSUFFICIENT are already DONE with GPT Native material evidence. No production authorization implied.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_transition#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
     OR v_transition#>>'{transition,ledger_progress_pct}' IS DISTINCT FROM '100'
  THEN
    RAISE EXCEPTION 'M107_SOAK_RECEIPT_TRANSITION_FAIL:%',v_transition;
  END IF;
END
$close$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M107-SOAK-RECEIPT-TERMINAL-CLOSE-048',
  'VALIDATION',
  'M10.7 cerrado por readback terminal del receipt de soak',
  'El checkpoint terminal releyó la autoridad declarada de provenance receipts y confirmó que el receipt histórico M9.11 permanece VERIFIED. Los cuatro checkpoints previos estaban DONE, incluidos NO_FALSE_PASS y NEG_INSUFFICIENT con evidencia GPT Native.',
  'N/A: evidencia terminal de cierre de M10.7.',
  'SOAK_RECEIPT_TERMINAL_READBACK_PASS',
  'Cerrar el soak sólo después de criterios, cobertura, cero false-pass/timeouts y negativo de insuficiencia; el checkpoint terminal es readback, no una nueva campaña integral ni autorización de producción.',
  'PASS si SOAK_RECEIPT queda DONE, los 5/5 checkpoints quedan terminales, progress_pct=100 y work item 478 queda DONE sin blockers ni dependencias pendientes.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','VERIFICADO',
  'Declared readback: EVIDENCE_VERIFICATION n=1110 last_at=2026-10-17T00:59:58.709843Z. Receipt 38 SHA=17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972. NO_FALSE_PASS capture blob a62528e6c8a5db73b0f5e2a94aa1e1c94c37810a; NEG_INSUFFICIENT capture blob b851895a62cda7e569d4586f1d740b59483ee837.',
  'CLOSURE',
  array['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.7 terminal soak receipt closure',
  'supabase://programacion.provenance_receipts/38'
)
ON CONFLICT (codigo) DO UPDATE SET
  descripcion=excluded.descripcion,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

DO $postcheck$
DECLARE
  v_progress numeric;
  v_status text;
  v_done int;
  v_open_blockers int;
  v_unmet_deps int;
BEGIN
  SELECT progress_pct,status,done_checkpoint_count
    INTO v_progress,v_status,v_done
  FROM programacion.v_engineering_work_progress
  WHERE id=478;

  SELECT programacion.fn_engineering_effective_open_blocker_count_v1(478)
    INTO v_open_blockers;

  SELECT count(*) INTO v_unmet_deps
  FROM programacion.fn_engineering_effective_dependencies_v1(478) d
  WHERE d.is_unmet;

  IF v_progress IS DISTINCT FROM 100.00
     OR v_status IS DISTINCT FROM 'DONE'
     OR v_done IS DISTINCT FROM 5
     OR v_open_blockers IS DISTINCT FROM 0
     OR v_unmet_deps IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'M107_TERMINAL_POSTCHECK_FAIL:progress=% status=% done=% blockers=% deps=%',
      v_progress,v_status,v_done,v_open_blockers,v_unmet_deps;
  END IF;
END
$postcheck$;

COMMIT;
