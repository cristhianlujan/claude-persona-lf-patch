\set ON_ERROR_STOP on
-- Run AS the non-superuser login role `authenticator` (how PostgREST connects), after
-- test_pg01_authority_attestations_v1.sql's fixture roles exist in the cluster (see runner).
-- Proves service_role cannot become an authority principal.
SET ROLE service_role;
DO $b$ DECLARE ok boolean:=false; BEGIN
 BEGIN EXECUTE 'SET SESSION AUTHORIZATION lf_t_auditor_login'; EXCEPTION WHEN insufficient_privilege THEN ok:=true; END;
 IF NOT ok THEN RAISE EXCEPTION 'TEST_FAIL:B3_service_role_set_session_authorization'; END IF;
 ok:=false; BEGIN EXECUTE 'SET ROLE programacion_auditor'; EXCEPTION WHEN insufficient_privilege THEN ok:=true; END;
 IF NOT ok THEN RAISE EXCEPTION 'TEST_FAIL:B3b_service_role_set_role_authority'; END IF;
 RAISE NOTICE 'PG01_AUTHORITY_SESSION_BOUNDARY_TESTS_PASSED:2 session_user=%',session_user; END $b$;
