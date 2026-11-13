-- PR #3803 inverse script: NOT an automatic Supabase migration.
-- Run solely with separate governed authorization on an isolated Postgres test.
-- Stops if there are unrecognized owner rows, rule changes, decisions or assets.
-- The sole LF chat-declaration seed is a known forward-created row and is
-- permitted to be reversed ONLY when it matches the exact expected preimage.
-- This is not a production execution instruction.
-- Forward source blob: 3b447b35f5aaad9d548e20255256513d9f27c19f.
BEGIN;
DO $preflight$
BEGIN
 IF to_regclass('public.lf_ig_project_owner_v2') IS NULL
    OR to_regclass('public.lf_ig_owner_decision_v2') IS NULL
    OR to_regclass('public.lf_ig_rule_change_v2') IS NULL
    OR to_regclass('public.lf_ig_asset_owner_receipt_v2') IS NULL
 THEN RAISE EXCEPTION 'IG_ROLLBACK_MISSING_V2_OBJECTS'; END IF;
 IF (SELECT count(*) FROM public.lf_ig_project_owner_v2)<>1
    OR NOT EXISTS (SELECT 1 FROM public.lf_ig_project_owner_v2 o
      WHERE o.project_code='LF'
        AND o.owner_sub='00000000-0000-4000-8000-000000000001'::uuid
        AND o.owner_name='Cristhian Luján'
        AND o.owner_profile_code='PERFIL-PRODUCT-DIRECTOR-LF'
        AND o.status='TEMP_DOCUMENTARY_ACTIVE'
        AND o.identity_mode='UNVERIFIED_CHAT_DECLARATION'
        AND o.source_execution_id='OWNER_CHAT_TEMPORARY_2026-11-12'
        AND o.authority_receipt_sha256=encode(extensions.digest(convert_to(
          'CHAT_DECLARATION_OWNER_CRISTHIAN_LUJAN_2026_11_12_LF_TEMPORAL','UTF8'),'sha256'),'hex'))
    OR (SELECT count(*) FROM public.lf_ig_owner_decision_v2)>0
    OR (SELECT count(*) FROM public.lf_ig_rule_change_v2)>0
    OR (SELECT count(*) FROM public.lf_ig_asset_owner_receipt_v2)>0
 THEN RAISE EXCEPTION 'IG_ROLLBACK_NONEMPTY_V2_TABLES'; END IF;
 IF (SELECT count(*) FROM public.lf_operation_registry
     WHERE operation_code='PROMOCION_REGLA_LF' AND version='v0.2'
       AND status='SANDBOX_ACTIVE'
       AND created_by_execution_id='EXEC-MIGRATION-LF-IG-LIFECYCLE-V2')<>1
    OR (SELECT count(*) FROM public.lf_operation_registry
        WHERE operation_code='PROMOCION_REGLA_LF')<>1
 THEN RAISE EXCEPTION 'IG_ROLLBACK_REGISTRY_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_skill_catalog_v1
    WHERE (skill_code='RULE_CREATE_APPLY'
           AND opener_fn='lf_skill_o_rule_create_v2'
           AND input_required=ARRAY['regla_codigo','analysis_snapshot_sha256','decision_id','candidate_patch','owner_decision_id']::text[]
           AND description='Creates official CANDIDATO child after LF temporary documentary decision and 7-step readback')
      OR (skill_code='RULE_UPDATE_APPLY'
           AND opener_fn='lf_skill_o_rule_update_v2'
           AND input_required=ARRAY['regla_codigo','analysis_snapshot_sha256','decision_id','candidate_patch','owner_decision_id']::text[]
           AND description='Candidate-only legacy writer plus staged VIGENTE correction; exact documentary owner decision and preimage required')
   )<>2 THEN RAISE EXCEPTION 'IG_ROLLBACK_CATALOG_DRIFT'; END IF;
 IF to_regprocedure('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)') IS NULL
    OR to_regprocedure('public.lf_ig_rule_child_guard_v2(text,jsonb,text,text,text,text)') IS NULL
    OR to_regprocedure('public.lf_ig_rule_step_record_v2(text,text,text,text,jsonb)') IS NULL
    OR to_regprocedure('public.lf_skill_o_rule_create_v2(text,jsonb,text,text,text)') IS NULL
    OR to_regprocedure('public.lf_skill_o_rule_update_v2(text,jsonb,text,text,text)') IS NULL
    OR to_regprocedure('public.lf_ig_rule_finalize_v2(text)') IS NULL
    OR to_regprocedure('public.lf_ig_asset_owner_approve_v2(text,text,text,text,jsonb)') IS NULL
    OR to_regprocedure('public.lf_ig_asset_owner_apply_v2(uuid)') IS NULL
 THEN RAISE EXCEPTION 'IG_ROLLBACK_V2_FUNCTION_DRIFT'; END IF;
 -- Six pre-existing V1 function definitions MUST still have the same frozen MD5.
 IF md5(pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))
        IS DISTINCT FROM 'c311087befe49afb2affa668231c9dd1'
  OR md5(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure))
        IS DISTINCT FROM 'ac7e351e1834cbfb91aabf26e1a04a8d'
  OR md5(pg_get_functiondef('public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)'::regprocedure))
        IS DISTINCT FROM 'dc97a0e7c65b65ae1951e2da86c6238b'
  OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
        IS DISTINCT FROM 'd7fe763c999db6f6259b6b1e2bd69644'
  OR md5(pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure))
        IS DISTINCT FROM '16e45f40dad5cecc215a2f978be47728'
  OR md5(pg_get_functiondef('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))
        IS DISTINCT FROM 'fe08a25c8e3c023d7181194d2dfdee0d'
 THEN RAISE EXCEPTION 'IG_ROLLBACK_LEGACY_MD5_DRIFT'; END IF;
END $preflight$;

-- Restore exactly the two source rows; read-only source SELECT performed for preimage.
UPDATE public.lf_skill_catalog_v1
 SET opener_fn=NULL, input_required=ARRAY['regla_codigo']::text[],
     description='Abre la operacion gobernada CREACION_REGLA_LF desde el perfil (la escritura la hacen sus 7 pasos)'
 WHERE skill_code='RULE_CREATE_APPLY' AND opener_fn='lf_skill_o_rule_create_v2';
UPDATE public.lf_skill_catalog_v1
 SET opener_fn='lf_skill_o_rule_update_v1',
     input_required=ARRAY['regla_codigo','analysis_snapshot_sha256','decision_id','candidate_patch']::text[],
     description='Ejecuta ACTUALIZACION_REGLA_LF solo para parche documental exacto validado por el mismo Product Director RUN; 7 pasos registrados y readback CANDIDATO, nunca promocion'
 WHERE skill_code='RULE_UPDATE_APPLY' AND opener_fn='lf_skill_o_rule_update_v2';

DELETE FROM public.lf_operation_registry
 WHERE operation_code='PROMOCION_REGLA_LF' AND version='v0.2'
   AND created_by_execution_id='EXEC-MIGRATION-LF-IG-LIFECYCLE-V2';

-- Preimage pg_proc ACL for both legacy functions had only postgres & service_role EXECUTE.
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_decide_v1(text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text) TO service_role;

-- Explicit RESTRICT: never silently cascade to unrelated objects.
DROP FUNCTION public.lf_ig_rule_finalize_v2(text) RESTRICT;
DROP FUNCTION public.lf_skill_o_rule_create_v2(text,jsonb,text,text,text) RESTRICT;
DROP FUNCTION public.lf_skill_o_rule_update_v2(text,jsonb,text,text,text) RESTRICT;
DROP FUNCTION public.lf_ig_rule_step_record_v2(text,text,text,text,jsonb) RESTRICT;
DROP FUNCTION public.lf_ig_rule_child_guard_v2(text,jsonb,text,text,text,text) RESTRICT;
DROP FUNCTION public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb) RESTRICT;
DROP FUNCTION public.lf_ig_asset_owner_apply_v2(uuid) RESTRICT;
DROP FUNCTION public.lf_ig_asset_owner_approve_v2(text,text,text,text,jsonb) RESTRICT;
DROP TABLE public.lf_ig_rule_change_v2 RESTRICT;
DROP TABLE public.lf_ig_owner_decision_v2 RESTRICT;
-- Explicitly delete only the exact seed created by the forward migration,
-- after confirmed zero human decisions and zero child changes.
DELETE FROM public.lf_ig_project_owner_v2
 WHERE project_code='LF'
   AND owner_sub='00000000-0000-4000-8000-000000000001'::uuid
   AND owner_name='Cristhian Luján'
   AND source_execution_id='OWNER_CHAT_TEMPORARY_2026-11-12';
DROP TABLE public.lf_ig_project_owner_v2 RESTRICT;
DROP TABLE public.lf_ig_asset_owner_receipt_v2 RESTRICT;

DO $readback$
BEGIN
 IF to_regclass('public.lf_ig_project_owner_v2') IS NOT NULL
 OR to_regclass('public.lf_ig_owner_decision_v2') IS NOT NULL
 OR to_regclass('public.lf_ig_rule_change_v2') IS NOT NULL
 OR to_regclass('public.lf_ig_asset_owner_receipt_v2') IS NOT NULL
 OR to_regprocedure('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)') IS NOT NULL
 OR to_regprocedure('public.lf_ig_asset_owner_apply_v2(uuid)') IS NOT NULL
 OR EXISTS(SELECT 1 FROM public.lf_operation_registry WHERE operation_code='PROMOCION_REGLA_LF')
 THEN RAISE EXCEPTION 'IG_ROLLBACK_OBJECT_READBACK_FAILED'; END IF;
 IF (SELECT count(*) FROM public.lf_skill_catalog_v1
   WHERE (skill_code='RULE_CREATE_APPLY' AND opener_fn IS NULL
      AND input_required=ARRAY['regla_codigo']::text[]
      AND description='Abre la operacion gobernada CREACION_REGLA_LF desde el perfil (la escritura la hacen sus 7 pasos)')
   OR (skill_code='RULE_UPDATE_APPLY' AND opener_fn='lf_skill_o_rule_update_v1'
      AND input_required=ARRAY['regla_codigo','analysis_snapshot_sha256','decision_id','candidate_patch']::text[]
      AND description='Ejecuta ACTUALIZACION_REGLA_LF solo para parche documental exacto validado por el mismo Product Director RUN; 7 pasos registrados y readback CANDIDATO, nunca promocion')
   )<>2
 OR NOT has_function_privilege('service_role',
       'public.lf_rule_promotion_decide_v1(text,text,text,text)','EXECUTE')
 OR NOT has_function_privilege('service_role',
       'public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'IG_ROLLBACK_PREIMAGE_READBACK_FAILED'; END IF;
END $readback$;
COMMIT;
