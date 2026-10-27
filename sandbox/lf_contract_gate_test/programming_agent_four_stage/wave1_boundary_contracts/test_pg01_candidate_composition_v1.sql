-- Synthetic profile/judge/catalog only; real D7/V2/writer/gate candidates.
-- Appended to the pinned writer fixture by build_pg01_candidate_composition_v1.py.
-- All writes belong to the surrounding disposable BEGIN/ROLLBACK.
CREATE OR REPLACE FUNCTION pg_temp.binding() RETURNS jsonb LANGUAGE sql AS $q$
 WITH body AS (SELECT jsonb_build_object(
  'channel','PROGRAMACION','channel_effect_authority',false,
  'channel_precondition',jsonb_build_object(
    'code','PROGRAMACION_PRECHECK_DEFINICION',
    'required_before_channel_effect',true,
    'programming_entry_contract','PROGRAMMING_ENTRY_CONTRACT_V1')) b)
 SELECT b||jsonb_build_object('binding_sha256',
   'sha256:'||encode(extensions.digest(convert_to(b::text,'UTF8'),'sha256'),'hex'))
 FROM body
$q$;
UPDATE public.lf_operation_execution
 SET manifest=jsonb_set(manifest,
  '{router_profile_handoff,semantic_request,router_action_binding}',pg_temp.binding())
 WHERE execution_id='PROFILE';

-- Synthetic Native-style handoff/output; real #3180 prepare/classify below.
UPDATE public.lf_operation_execution
 SET manifest=jsonb_set(manifest,'{router_profile_handoff}',
   manifest->'router_profile_handoff'||jsonb_build_object(
    'literal_request','synthetic composition request',
    'return_to_router_after_profile_result',true))
 WHERE execution_id='PROFILE';
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
 VALUES('PROFILE','execute_profile','STEP_PASS_WITH_EVIDENCE',
  jsonb_build_object('profile_output',jsonb_build_object(
   'output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','status','COMPLETE',
   'programming_handoff',pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'))));

DO $typed$ DECLARE r jsonb; req jsonb; gate jsonb; BEGIN
 r:=public.lf_profile_result_router_return_prepare_v1('PROFILE');
 req:=r->'programming_admission_request';
 IF r->>'next_action' IS DISTINCT FROM 'ENTER_PROGRAMMING_DEVELOPMENT_ADMISSION'
    OR req->'router_action_binding' IS DISTINCT FROM pg_temp.binding()
    OR req->'programming_handoff' IS DISTINCT FROM pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001')
    OR req->>'source_execution_id' IS DISTINCT FROM 'PROFILE'
    OR r ? 'router_return_request' THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:0_typed_return %',r;
 END IF;
 gate:=public.lf_programming_development_admission_v1(
   req->'router_action_binding',req->'programming_handoff',req->>'source_execution_id');
 IF gate->>'retorno' IS DISTINCT FROM 'RETURN_TO_ANALYSIS_NO_CODE'
    OR gate->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:0_typed_request_to_gate %',gate;
 END IF;
END $typed$;

DO $missing$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(
  pg_temp.binding(),pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'PROFILE');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_V2_RECEIPT_NOT_FOUND'
    OR r->>'retorno' IS DISTINCT FROM 'RETURN_TO_ANALYSIS_NO_CODE'
    OR r->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:1_missing %',r;
 END IF;
END $missing$;

DO $writer$ DECLARE r jsonb; a jsonb; b jsonb; BEGIN
 a:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),
   pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'JUDGE');
 b:=private.fn_lf_programming_receipt_record_runtime_v1('PROFILE',pg_temp.binding(),
   pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'JUDGE');
 IF a->>'status' IS DISTINCT FROM 'RECORDED'
    OR a->>'verdict' IS DISTINCT FROM 'ACCEPT'
    OR b->>'status' IS DISTINCT FROM 'IDEMPOTENT_REPLAY'
    OR a->>'receipt_record_id' IS DISTINCT FROM b->>'receipt_record_id' THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:2_writer % %',a,b;
 END IF;
 r:=public.lf_programming_development_admission_v1(pg_temp.binding(),
   pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'PROFILE');
 IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_OPERACION_NO_ACTIVA'
    OR r->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:3_candidate %',r;
 END IF;
END $writer$;

-- ACTIVE is a test-only toggle in this rollback transaction, never a promotion.
UPDATE public.lf_router_action_registry SET status='ACTIVE';
DO $admitted$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.binding(),
   pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'PROFILE');
 IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_DESARROLLO_ADMITIDO'
    OR r->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:4_admitted_no_execution %',r;
 END IF;
END $admitted$;

-- A second completed origin with the same binding must not borrow PROFILE's
-- real, admitted receipt. The positive PROFILE case above remains unchanged.
INSERT INTO public.lf_operation_execution
 SELECT (jsonb_populate_record(NULL::public.lf_operation_execution,
   to_jsonb(e)||jsonb_build_object('execution_id','PROFILE-SECOND'))).*
 FROM public.lf_operation_execution e WHERE execution_id='PROFILE';
DO $cross_origin$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.binding(),
   pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'PROFILE-SECOND');
 IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_HANDOFF_INVALIDO'
    OR r->>'codigo' IS DISTINCT FROM 'PG01_HANDOFF_SOURCE_EXECUTION_MISMATCH'
    OR r->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:7_cross_origin_receipt %',r;
 END IF;
END $cross_origin$;

UPDATE lf_ops.pantallas SET estado='CANDIDATO' WHERE codigo='B2B-AUTH-001';
DO $stale$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.binding(),
   pg_temp.handoff('aaaaaaaa-0000-4000-8000-000000000001'),'PROFILE');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_V2_DEFINITION_CURRENTNESS_NOT_VERIFIED'
    OR r->>'retorno' IS DISTINCT FROM 'BLOCK_NO_CODE'
    OR r->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:5_stale %',r;
 END IF;
END $stale$;

-- Current V2 must reject a technical reference, even with a valid screen package.
DO $technical$ DECLARE r jsonb; BEGIN
 r:=private.fn_lf_programming_definition_ref_sha256_v1(
  'lf-technical-definition://FUNCTION/public.fn_lf_decision_context_asof_record_v1');
 IF r->'ok' IS DISTINCT FROM 'false'::jsonb
    OR r->>'reason' IS DISTINCT FROM 'DEFINITION_REF_SCHEME_UNSUPPORTED' THEN
  RAISE EXCEPTION 'COMPOSITION_FAIL:6_technical_not_admitted %',r;
 END IF;
 RAISE NOTICE 'PG01_CANDIDATE_COMPOSITION_PASSED:8';
END $technical$;
