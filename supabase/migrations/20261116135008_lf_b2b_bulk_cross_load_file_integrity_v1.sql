BEGIN;
-- E7: preserve existing safe processing rule; add source-file ownership and role checks.
-- A CLEAN file from a different load must never authorize this load's processing.
DO $preimage$
DECLARE d text;
BEGIN
 d := pg_get_functiondef('lf_ops.cargas_lotes_block_unsafe_processing_v1()'::regprocedure);
 IF position('a.file_id=NEW.source_file_id' IN d)=0
    OR position('a.malware_scan_status=''CLEAN''' IN d)=0
    OR NOT EXISTS(SELECT 1 FROM pg_trigger
       WHERE tgrelid='lf_ops.cargas_lotes'::regclass
         AND tgname='trg_cargas_lotes_block_unsafe_processing_v1'
         AND NOT tgisinternal AND tgenabled<>'D')
 THEN
   RAISE EXCEPTION 'LF_E7_BULK_UNSAFE_PROCESSING_PREIMAGE_DRIFT';
 END IF;
END $preimage$;

CREATE OR REPLACE FUNCTION lf_ops.cargas_lotes_block_unsafe_processing_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'lf_ops'
AS $fn$
BEGIN
 IF NEW.processed_count > 0 AND NOT EXISTS (
   SELECT 1 FROM lf_ops.cargas_archivos a
   WHERE a.file_id = NEW.source_file_id
     AND a.load_id = NEW.load_id
     AND a.file_role = 'ORIGINAL'
     AND a.malware_scan_status = 'CLEAN'
 ) THEN
   RAISE EXCEPTION 'LF_B2B_UNSAFE_FILE_PROCESSING_BLOCKED load=%', NEW.load_code
     USING ERRCODE='check_violation';
 END IF;
 RETURN NEW;
END
$fn$;
COMMIT;
