revoke execute on function programacion.fn_guard_input_family_semantic_depth_v510() from public;
revoke execute on function programacion.fn_guard_input_family_semantic_depth() from public;
revoke execute on function programacion.fn_guard_input_stage_earliest_boundary() from public;
revoke execute on function programacion.fn_guard_provenance_receipt_insert() from public;
revoke execute on function programacion.fn_input_auth006_build_assertions(bigint,bigint,text) from public;
revoke execute on function programacion.fn_input_owner_decision_assertions(bigint,bigint,text) from public;
revoke execute on function programacion.fn_input_rate_enrichment_assertions(bigint,bigint,text) from public;
revoke execute on function programacion.fn_input_rebind_assertion_specs(bigint,text,jsonb) from public;
revoke execute on function programacion.fn_input_rebind_assertion(bigint,text,jsonb) from public;
revoke execute on function programacion.fn_input_resolve_source_ref_v510(jsonb,integer,bigint) from public;
revoke execute on function programacion.fn_input_security_capability_profile(integer) from public;
revoke execute on function programacion.fn_input_security_threat_expected_v510(integer) from public;
revoke execute on function programacion.fn_input_security_threat_expected(integer) from public;
revoke execute on function programacion.fn_input_subject_depth_expected_v510(integer,text) from public;
revoke execute on function programacion.fn_input_subject_depth_expected(integer,text) from public;
revoke execute on function programacion.fn_input_v58_assertion_template(integer,text,jsonb) from public;
revoke execute on function programacion.fn_input_v58_build_assertions(bigint,bigint,text) from public;

alter default privileges for role postgres in schema programacion revoke execute on functions from public;