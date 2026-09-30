alter function programacion.fn_input_resolve_source_ref(jsonb,integer,bigint) set search_path = pg_catalog, programacion, lf_ops, transversal;
alter function programacion.fn_input_build_source_manifest(bigint) set search_path = pg_catalog, programacion;
alter function programacion.fn_input_readiness_run_is_current(bigint) set search_path = pg_catalog, programacion;
alter function programacion.fn_guard_input_family_assessment_insert() set search_path = pg_catalog, programacion, lf_ops;
alter function programacion.fn_guard_input_family_assessment_update() set search_path = pg_catalog, programacion;
alter function programacion.fn_guard_input_readiness_run() set search_path = pg_catalog, programacion, lf_ops;

revoke all on function programacion.fn_input_resolve_source_ref(jsonb,integer,bigint) from public;
revoke all on function programacion.fn_input_build_source_manifest(bigint) from public;
revoke all on function programacion.fn_input_readiness_run_is_current(bigint) from public;
revoke all on function programacion.fn_guard_input_family_assessment_insert() from public;
revoke all on function programacion.fn_guard_input_family_assessment_update() from public;
revoke all on function programacion.fn_guard_input_readiness_run() from public;

grant execute on function programacion.fn_input_readiness_run_is_current(bigint) to programacion_auditor,programacion_builder,programacion_verifier,programacion_human_authority;