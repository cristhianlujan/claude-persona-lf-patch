-- Synthetic one-rule PG18 test fixture. NEVER import into LF live.
CREATE SCHEMA IF NOT EXISTS lf_ops;
CREATE SCHEMA IF NOT EXISTS programacion;
DO $roles$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
END $roles$;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,
 operation_code text NOT NULL,target_type text NOT NULL,target_code text NOT NULL,
 status text NOT NULL,manifest jsonb NOT NULL);
CREATE TABLE public.lf_activo_relaciones(
 codigo_activo text,relacionado_codigo text,relacion_tipo text);
INSERT INTO public.lf_activo_relaciones VALUES
 ('PERFIL-PRODUCT-DIRECTOR-LF','INPUT_GOVERNANCE_EXECUTION_CONTRACT','GOBERNADO_POR');
CREATE TABLE lf_ops.reglas(
 id integer PRIMARY KEY,codigo text NOT NULL UNIQUE,
 descripcion text NOT NULL,estado text NOT NULL);
CREATE TABLE lf_ops.pantallas(
 id integer PRIMARY KEY,codigo text NOT NULL UNIQUE,activa boolean NOT NULL);
CREATE TABLE lf_ops.reglas_pantallas(
 regla_id integer NOT NULL REFERENCES lf_ops.reglas(id),
 pantalla_id integer NOT NULL REFERENCES lf_ops.pantallas(id),
 PRIMARY KEY(regla_id,pantalla_id));
CREATE TABLE programacion.fake_ig_state(
 pantalla_id integer PRIMARY KEY,
 status text NOT NULL,run_id bigint NOT NULL,
 source_current boolean NOT NULL);
INSERT INTO lf_ops.reglas VALUES
 (1,'RULE-ACTIVE-001','material active baseline','CANDIDATO'),
 (2,'RULE-UNLINKED-001','material unlinked baseline','CANDIDATO'),
 (3,'RULE-INACTIVE-001','material inactive baseline','CANDIDATO');
INSERT INTO lf_ops.pantallas VALUES
 (101,'SCREEN-A',true),(102,'SCREEN-INACTIVE',false);
INSERT INTO lf_ops.reglas_pantallas VALUES (1,101),(3,102);
INSERT INTO programacion.fake_ig_state VALUES (101,'READY',1101,true);
CREATE FUNCTION public.lf_asset_snapshot_sha_v1(p_asset_type text,p_code text)
RETURNS text LANGUAGE sql STABLE AS $sha$
 SELECT md5(r.codigo||':'||r.descripcion)||md5(r.codigo||':'||r.descripcion)
 FROM lf_ops.reglas r WHERE r.codigo=p_code AND p_asset_type='REGLA'
$sha$;
CREATE FUNCTION public.lf_profile_input_governance_requirement_v1(p_handoff jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $task$
 SELECT '{"status":"REQUIRED","input_governance_requirement":"REQUIRED_BY_TASK"}'::jsonb
$task$;
CREATE FUNCTION programacion.fn_input_governance_execute(
 p_pantalla_id integer,p_consumer text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $ig$
DECLARE r record;
BEGIN
 SELECT * INTO r FROM programacion.fake_ig_state
 WHERE pantalla_id=p_pantalla_id AND p_consumer='CONTEXT_PACK';
 IF NOT FOUND THEN RETURN jsonb_build_object(
   'status','CURATOR_RUNTIME_REQUIRED','run_id',null); END IF;
 RETURN jsonb_build_object('status',r.status,'run_id',r.run_id,
   'execution_mode','REUSE_COMPLETED_CURRENT_RUN',
   'output_sha256',repeat('a',64));
END $ig$;
CREATE FUNCTION programacion.fn_input_run_source_currentness_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $current$
 SELECT jsonb_build_object('source_current',s.source_current,'run_id',s.run_id)
 FROM programacion.fake_ig_state s WHERE s.run_id=p_run_id
$current$;
CREATE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(
 p_handoff jsonb,p_input_literal text,p_profile_code text)
RETURNS jsonb LANGUAGE sql STABLE AS $validate$ SELECT '{"valid":true}'::jsonb $validate$;
CREATE FUNCTION public.lf_profile_execution_scope_authority_packet_v1(
 p_execution_id text,p_input_literal text,p_input_source_ref text)
RETURNS jsonb LANGUAGE sql STABLE AS $scope$
 SELECT jsonb_build_object('status','READY',
   'scope_authority_packet',jsonb_build_object('execution_id',p_execution_id),
   'scope_packet_sha256','sha256:'||repeat('a',64)) $scope$;
CREATE FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(
 p_input_literal text,p_scope jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $prepare$
 SELECT jsonb_build_object('status','READY','candidate_screen_count',1,
   'request_sha256',repeat('b',64),'catalog_sha256',repeat('c',64)) $prepare$;
CREATE FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(
 p_request jsonb,p_result jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $check$
 SELECT '{"status":"VALID"}'::jsonb $check$;
CREATE FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(
 p_request_text text,p_profile_code text,p_scope jsonb,p_consumer text)
RETURNS jsonb LANGUAGE sql STABLE AS $existing$
 SELECT jsonb_build_object('applicable',true,'status','READY',
 'decision','PASS','continuation_allowed',true,'profile_code',p_profile_code,
 'consumer',p_consumer,'binding_mode','DIRECT_PROFILE',
 'pantalla_id',101,'governance_result',jsonb_build_object(
 'status','READY','run_id',1101)) $existing$;
