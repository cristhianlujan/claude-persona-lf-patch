-- LF 166 candidates: documentary owner readback + evidence-only screen diagnosis + batch dry-run.
-- No changes to lf_ops.reglas, lf_ops.reglas_pantallas, profiles, or promotion states.
-- Existing authoritative link writer remains VINCULACION_REGLA_PANTALLA_LF via RULE_LINK_APPLY.
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM public.lf_ig_project_owner_v2
     WHERE project_code='LF' AND owner_name='Cristhian Luján'
       AND identity_mode='UNVERIFIED_CHAT_DECLARATION'
       AND status='TEMP_DOCUMENTARY_ACTIVE')<>1
 THEN RAISE EXCEPTION 'LF_PROMOTION_DOCUMENTARY_OWNER_PREIMAGE_MISMATCH'; END IF;
 IF to_regclass('public.lf_rule_promotion_documentary_owner_v1') IS NOT NULL
    OR to_regclass('public.lf_rule_promotion_screen_diagnostic_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_PROMOTION_READBACK_VIEW_ALREADY_EXISTS'; END IF;
 IF to_regprocedure('public.lf_rule_promotion_decide_batch_v1(text[],text,text,text)') IS NULL
    OR to_regprocedure('public.lf_rule_promotion_apply_batch_v1(text[])') IS NULL
 THEN RAISE EXCEPTION 'LF_PROMOTION_CANONICAL_BATCH_NOT_FOUND'; END IF;
END $pre$;

-- Applies one existing B08 TEMP_DOCUMENTARY_ACTIVE criterion backwards to
-- every prior LF rule and forwards to future LF rules, without claiming
-- authenticated identity, altering any rule or fabricating signed decisions.
CREATE VIEW public.lf_rule_promotion_documentary_owner_v1 AS
SELECT r.id AS rule_id, r.codigo AS rule_code, r.estado AS rule_status,
       o.owner_name AS documentary_decisor,
       o.identity_mode AS identity_mode,
       false AS identity_verified_effective,
       CASE WHEN r.valor_config ? 'owner_decision_identity_verified'
            THEN r.valor_config->>'owner_decision_identity_verified'
            ELSE NULL END AS source_identity_assertion,
       r.valor_config->>'owner_decision_ref' AS owner_decision_ref,
       'audits/rule-quality-lote28/12_criterios_cierre_motor_7.md#b08_identity'::text AS attribution_source,
       'DOCUMENTARY_ONLY_NOT_IAM_AUTHENTICATED'::text AS authority_class
FROM lf_ops.reglas r
JOIN public.lf_ig_project_owner_v2 o ON o.project_code='LF'
 WHERE o.owner_name='Cristhian Luján'
   AND o.identity_mode='UNVERIFIED_CHAT_DECLARATION'
   AND o.status='TEMP_DOCUMENTARY_ACTIVE';

-- Evidence-first, mutually exclusive triage. B/C are work queues, not proof
-- of a rule really applying to five screens; never fabricate relations.
CREATE VIEW public.lf_rule_promotion_screen_diagnostic_v1 AS
WITH n AS (
 SELECT r.id,r.codigo,r.categoria,r.valor_config,r.estado AS rule_status,
   count(DISTINCT rp.pantalla_id)::int AS linked_screens,
   coalesce(bool_or(p.estado='CANDIDATO_VISUAL'),false) AS has_visual_screen
 FROM lf_ops.reglas r
 LEFT JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
 LEFT JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
 WHERE r.estado='CANDIDATO'
 GROUP BY r.id,r.codigo,r.categoria,r.valor_config,r.estado
), h AS (
 SELECT n.*,
    coalesce(nullif(n.valor_config->>'screen_code',''),
             nullif(n.valor_config->>'pantalla_codigo','')) AS explicit_screen_code,
    CASE WHEN coalesce(nullif(n.valor_config->>'screen_id',''),
                       nullif(n.valor_config->>'pantalla_id','')) ~ '^[0-9]{1,9}$'
         THEN coalesce(nullif(n.valor_config->>'screen_id',''),
                       nullif(n.valor_config->>'pantalla_id',''))::int
         ELSE NULL END AS explicit_screen_id
 FROM n
), evidence AS (
 SELECT h.*,s.id AS explicit_target_id,
        s.codigo AS explicit_target_code,s.estado AS explicit_target_state,
        EXISTS(SELECT 1 FROM lf_ops.reglas_pantallas x
               WHERE x.regla_id=h.id AND x.pantalla_id=s.id) AS explicit_target_linked
 FROM h LEFT JOIN LATERAL (
   SELECT p.id,p.codigo,p.estado FROM lf_ops.pantallas p
   WHERE (h.explicit_screen_id IS NOT NULL AND p.id=h.explicit_screen_id)
     OR (h.explicit_screen_code IS NOT NULL AND p.codigo=h.explicit_screen_code)
   ORDER BY CASE WHEN p.id=h.explicit_screen_id THEN 0 ELSE 1 END,p.id
   LIMIT 1
 ) s ON true
)
SELECT id AS rule_id,codigo AS rule_code,categoria AS rule_category,
       linked_screens,greatest(5-linked_screens,0) AS screens_to_technical_threshold,
       has_visual_screen,explicit_target_id,explicit_target_code,
       explicit_target_state,explicit_target_linked,
       CASE WHEN explicit_target_id IS NOT NULL AND NOT explicit_target_linked
            THEN 'A_EVIDENCED_LINK_MISSING'
            WHEN has_visual_screen OR explicit_target_state='CANDIDATO_VISUAL'
               OR upper(coalesce(categoria,'')) IN
                  ('UX','SHELL','NAVIGATION','ESTADOS_UI','ERROR_STATES')
            THEN 'B_UI_E2E_REVIEW'
            WHEN linked_screens BETWEEN 1 AND 4
            THEN 'C_LOW_SCOPE_PROVISIONAL'
            WHEN linked_screens=0
            THEN 'D_NO_LINK_UNKNOWN'
            ELSE 'E_THRESHOLD_MET'
       END AS diagnostic_bucket,
       'READ_ONLY_SOURCE_FIRST'::text AS assessment_mode,
       false AS auto_apply_authorized
FROM evidence;

-- Existing batch writers are unchanged. This read-only report checks
-- promotion IDs and their hashes before a separately authorized decision.
CREATE FUNCTION public.lf_rule_promotion_batch_dryrun_v1(p_ids text[])
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog','public','lf_ops'
AS $fn$
WITH ids AS (
 SELECT x.id,x.ord FROM unnest(coalesce(p_ids,array[]::text[]))
 WITH ORDINALITY AS x(id,ord)
), raw AS (
 SELECT ids.id,ids.ord,p.status,p.rule_code,p.request_snapshot_sha256,
        r.estado AS rule_state,
        CASE WHEN p.promotion_id IS NULL THEN false
             ELSE public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code)
                  IS NOT DISTINCT FROM p.request_snapshot_sha256 END AS hash_match,
        count(*) OVER (PARTITION BY ids.id) AS input_copies
 FROM ids LEFT JOIN public.lf_rule_promotion_v1 p ON p.promotion_id=ids.id
 LEFT JOIN lf_ops.reglas r ON r.codigo=p.rule_code
), assessed AS (
 SELECT *,CASE
   WHEN id IS NULL OR btrim(id)='' THEN 'INVALID_INPUT'
   WHEN input_copies>1 THEN 'DUPLICATE_PROMOTION_ID'
   WHEN status IS NULL THEN 'NOT_FOUND'
   WHEN NOT hash_match THEN 'STALE_HASH'
   WHEN rule_state IS DISTINCT FROM 'CANDIDATO' AND status<>'APPLIED' THEN 'RULE_NOT_CANDIDATE'
   WHEN status='PENDING' THEN 'HUMAN_DECISION_REQUIRED'
   WHEN status='APPROVED' THEN 'READY_TO_APPLY_PENDING_REAL_HUMAN_AUTH'
   WHEN status='APPLIED' THEN 'ALREADY_APPLIED'
   ELSE 'NOT_ACTIONABLE_STATUS' END AS assessment
 FROM raw
)
SELECT jsonb_build_object(
 'schema_version','LF_RULE_PROMOTION_BATCH_DRYRUN_V1',
 'status','READ_ONLY','requested_ids',count(*),
 'actionable_for_apply',count(*) FILTER(WHERE assessment='READY_TO_APPLY_PENDING_REAL_HUMAN_AUTH'),
 'blocked_or_pending',count(*) FILTER(WHERE assessment<>'READY_TO_APPLY_PENDING_REAL_HUMAN_AUTH'),
 'identity_verified',false,'independent_judge_claimed',false,
 'no_write_performed',true,
 'items',coalesce(jsonb_agg(jsonb_build_object('promotion_id',id,
       'rule_code',rule_code,'promotion_status',status,
       'rule_status',rule_state,'hash_match',hash_match,
       'assessment',assessment) ORDER BY ord),'[]'::jsonb))
FROM assessed;
$fn$;
REVOKE ALL ON public.lf_rule_promotion_documentary_owner_v1,
              public.lf_rule_promotion_screen_diagnostic_v1 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_batch_dryrun_v1(text[])
 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.lf_rule_promotion_documentary_owner_v1,
                public.lf_rule_promotion_screen_diagnostic_v1 TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_batch_dryrun_v1(text[]) TO service_role;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.lf_rule_promotion_documentary_owner_v1
     WHERE rule_id IN (235,438,439,440,532,577)
       AND NOT identity_verified_effective
       AND source_identity_assertion='false')<>6
 THEN RAISE EXCEPTION 'LF_PROMOTION_SIX_DOCUMENTARY_READBACK_FAILED'; END IF;
 IF (SELECT count(*) FROM public.lf_rule_promotion_screen_diagnostic_v1
     WHERE linked_screens<5)<>148
 THEN RAISE EXCEPTION 'LF_PROMOTION_148_SCREEN_READBACK_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_rule_promotion_v1)<>0
 THEN RAISE EXCEPTION 'LF_PROMOTION_UNEXPECTED_EXISTING_REQUESTS'; END IF;
END $post$;
COMMIT;
