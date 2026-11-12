-- LOTE 17: QUALITY-ONLY source trigger v2 + least-privilege grants.
-- NEVER alters the frozen apply/capture/citation/l8 functions.
SET search_path=rule_quality_l13,public;

CREATE OR REPLACE FUNCTION source_quality_activation_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_project text:=TG_ARGV[0];v_code text;v_category text;v_description text;
        v_is_active text;v_record rules%ROWTYPE;v_ticket activation_tickets%ROWTYPE;
        v_actor text;
BEGIN
 v_is_active:=to_jsonb(NEW)->>TG_ARGV[4];
 IF v_is_active IS DISTINCT FROM TG_ARGV[5] THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE'
    AND (to_jsonb(OLD)->>TG_ARGV[4]) IS NOT DISTINCT FROM v_is_active THEN
    RETURN NEW;
 END IF;
 v_code:=to_jsonb(NEW)->>TG_ARGV[1];
 v_category:=to_jsonb(NEW)->>TG_ARGV[2];
 v_description:=to_jsonb(NEW)->>TG_ARGV[3];
 SELECT * INTO v_record FROM rules WHERE project_code=v_project AND rule_code=v_code;
 IF NOT FOUND OR v_record.family_code IS NULL OR v_record.reviewed_at IS NULL
    OR v_record.next_review_at IS NULL OR v_record.next_review_at<=clock_timestamp()
    OR v_record.category_raw IS DISTINCT FROM v_category
    OR v_record.definition_text IS DISTINCT FROM v_description THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_ACTIVE_METADATA_MISSING';
 END IF;
 -- Reverify the signed JWT in the trigger as fail-closed defense-in-depth.
 v_actor:=trusted_actor_role_v2(v_project);
 SELECT * INTO v_ticket FROM activation_tickets
  WHERE project_code=v_project AND rule_code=v_code AND status='ARMED';
 IF NOT FOUND OR v_ticket.actor_role IS DISTINCT FROM v_actor THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_QUALITY_NO_ACTIVATION_TICKET';
 END IF;
 RETURN NEW;
END $fn$;

-- Function signatures remain stable. Only trusted actor implementation and
-- quality activation trigger are redefined. Gates are never redefined.
REVOKE ALL ON FUNCTION l17_verify_signed_claim_v2(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION trusted_actor_role_v2(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION l17_assert_request_current_user_v2(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION quality_prepare_new_v2(text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION quality_propose_correction_v2(text,text,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION quality_apply_envelope_v2(text,text,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION l17_verify_signed_claim_v2(text),
 l17_assert_request_current_user_v2(text),
 quality_prepare_new_v2(text,text,text),
 quality_propose_correction_v2(text,text,text,text,jsonb),
 quality_apply_envelope_v2(text,text,text,text)
TO lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;

-- Explicit proof: signer and secret remain inaccessible, including to authenticator.
REVOKE ALL ON l17_hmac_private,l17_actor_subjects FROM
 l17_authenticator,lf_owner_role,lf_super_role,lf_reader_role,
 saly_owner_role,saly_super_role;
REVOKE ALL ON FUNCTION l17_sandbox_sign_claim(jsonb),
 l17_sandbox_mint(text,text,text,integer) FROM
 l17_authenticator,lf_owner_role,lf_super_role,lf_reader_role,
 saly_owner_role,saly_super_role;
