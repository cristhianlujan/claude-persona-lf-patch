-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M8.2 / R16 Git-first.
-- Only admit the RESOLVER timing phase with non-empty resolver_code.
-- This operation does not issue performance receipts, tokens or provenance proofs.
-- Existing EVIDENCE_VERIFIER_V1 receipt checks remain in the original constraint.
DO $ig_m82$
DECLARE
  old_def text;
  new_def text;
  phase_old text := 'ARRAY[''CURATOR''::text, ''VALIDATOR''::text, ''TOTAL''::text, ''FAMILY''::text]';
  phase_new text := 'ARRAY[''CURATOR''::text, ''VALIDATOR''::text, ''TOTAL''::text, ''FAMILY''::text, ''RESOLVER''::text]';
  elapsed_pred text := 'AND (jsonb_typeof((payload -> ''elapsed_ms''::text)) = ''number''::text)';
  resolver_pred text := 'AND (((payload ->> ''phase''::text) <> ''RESOLVER''::text) OR (NULLIF(btrim((payload ->> ''resolver_code''::text)), ''''::text) IS NOT NULL)) ';
BEGIN
  SELECT pg_get_constraintdef(oid) INTO old_def
  FROM pg_constraint WHERE conrelid='programacion.provenance_receipts'::regclass
    AND conname='provenance_receipts_ig_performance_timing_sink_v1';
  IF old_def IS NULL OR strpos(old_def,phase_old)=0 OR strpos(old_def,elapsed_pred)=0 THEN
    RAISE EXCEPTION 'M82_TIMING_SINK_BASELINE_CHANGED';
  END IF;
  new_def := replace(replace(old_def,phase_old,phase_new),
                     elapsed_pred,resolver_pred||elapsed_pred);
  IF new_def=old_def OR strpos(new_def,phase_new)=0 OR strpos(new_def,'resolver_code')=0 THEN
    RAISE EXCEPTION 'M82_RESOLVER_TRANSFORMATION_INVALID';
  END IF;
  EXECUTE 'ALTER TABLE programacion.provenance_receipts DROP CONSTRAINT provenance_receipts_ig_performance_timing_sink_v1';
  EXECUTE 'ALTER TABLE programacion.provenance_receipts ADD CONSTRAINT provenance_receipts_ig_performance_timing_sink_v1 '||new_def;
END
$ig_m82$;
