-- Append inside the rollback-owned composition from #3194, after its eight
-- groups. Uses the real D7 resolver and the real runtime-written fixture receipt.
DO $identity$
DECLARE b jsonb := pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001');
        original jsonb; replay jsonb; changed jsonb; field text; value jsonb;
BEGIN
 original := private.fn_lf_programming_context_handoff_receipt_resolve_v1(b);
 IF original->'found' IS DISTINCT FROM 'true'::jsonb THEN
   RAISE EXCEPTION 'D7_CALLER_IDENTITY_FAIL:fixture_receipt_missing';
 END IF;
 replay := private.fn_lf_programming_context_handoff_receipt_resolve_v1(
   b || jsonb_build_object('requested_scope_ids',jsonb_build_array('S1','S1')));
 IF replay#>>'{record,binding_key_sha256}' IS DISTINCT FROM original#>>'{record,binding_key_sha256}'
    OR replay#>>'{record,receipt_record_id}' IS DISTINCT FROM original#>>'{record,receipt_record_id}' THEN
   RAISE EXCEPTION 'D7_CALLER_IDENTITY_FAIL:scope_normalization';
 END IF;
 FOR field,value IN SELECT * FROM (VALUES
   ('context_id',to_jsonb('aaaaaaaa-0000-4000-8000-000000000002'::text)),
   ('context_sha256',to_jsonb(repeat('e',64))),
   ('target_ref',to_jsonb('lf-screen-contract://OTHER'::text)),
   ('requested_scope_ids',jsonb_build_array('S2')),
   ('producer_execution_ref',to_jsonb('PROFILE-OTHER'::text)),
   ('entry_contract_digest_sha256',to_jsonb(repeat('f',64)))
 ) cases(k,v) LOOP
   changed := private.fn_lf_programming_context_handoff_receipt_resolve_v1(b||jsonb_build_object(field,value));
   IF changed->'found' IS DISTINCT FROM 'false'::jsonb THEN
     RAISE EXCEPTION 'D7_CALLER_IDENTITY_FAIL:changed_field_% %',field,changed;
   END IF;
 END LOOP;
 RAISE NOTICE 'D7_CALLER_IDENTITY_PASSED:7';
END $identity$;
