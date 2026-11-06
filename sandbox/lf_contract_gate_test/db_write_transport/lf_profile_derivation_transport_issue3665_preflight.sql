-- LF #3665 / PRE-APPLY READ-ONLY CANARY
-- No DDL/DML. Must be re-read against the target DB immediately before Train apply.
WITH signatures(signature,expected_md5) AS (
 VALUES
 ('public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)', '55511725602b989238f9629a27f1ddd5'),
 ('public.lf_profile_result_router_return_prepare_v1(text)', '8bf503bf17f038a18124783c038d9793'),
 ('public.lf_router_route_v1(jsonb,jsonb,boolean)', '4e5c9a76a48769dea3ec72faf5ebceb7'),
 ('public.lf_router_profile_after_selection_v1(jsonb,jsonb)', '1f84204588c130148c33746a901f580b'),
 ('public.lf_router_profile_after_selection_raw_v1(jsonb,text)', '40009812ec47f4e93b7d52a9d807b779'),
 ('public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)', 'af1e2fd3675de05d0f421f6f76270364')
)
SELECT signature,md5(pg_get_functiondef(signature::regprocedure))=expected_md5 source_md5_pass
FROM signatures ORDER BY signature;
-- Provenance: original literal must bind to the historical completed DIRECT run.
SELECT e.execution_id,e.status,e.target_code,
       e.request_sha256=encode(extensions.digest(convert_to(e.manifest#>>'{router_profile_handoff,literal_request}','UTF8'),'sha256'),'hex') sha_pass,
       sp.entry_policy='DIRECT' source_direct
FROM public.lf_operation_execution e
JOIN public.lf_profile_selector_policy_v1 sp ON sp.profile_code=e.target_code
WHERE e.execution_id='EXEC-PROFILE-GATE2-43633381F2A1B84882FB9010';
