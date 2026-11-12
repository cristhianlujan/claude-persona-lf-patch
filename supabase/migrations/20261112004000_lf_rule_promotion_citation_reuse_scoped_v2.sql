-- LF L8 CANDIDATE ONLY. No production / no merge / no live apply.
-- Preserve L7 source, receipt, Step70 and apply guards unchanged.
-- The quote proves literal text, not the verdict's semantic relevance.
BEGIN;
DO $guard_l8$
BEGIN
 IF md5(pg_get_functiondef(
   'public.lf_rule_promotion_citation_record_v1(text,text,text)'::regprocedure))
       IS DISTINCT FROM '89cbfac4162dbc9f8ecca59f2c3ab4c3'
    OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
       IS DISTINCT FROM '86b0494984edf95cf0f9c0a0df67000b'
    OR NOT EXISTS (
       SELECT 1 FROM pg_constraint
       WHERE conrelid='public.lf_rule_promotion_citation_capture_v1'::regclass
         AND conname='lf_rule_promotion_citation_capture_v1_quote_sha256_key'
         AND contype='u'
    )
 THEN RAISE EXCEPTION 'BLOCK_L8_UPSTREAM_MD5_OR_QUOTE_UNIQUE_DRIFT'; END IF;
END $guard_l8$;

ALTER TABLE public.lf_rule_promotion_citation_capture_v1
  DROP CONSTRAINT lf_rule_promotion_citation_capture_v1_quote_sha256_key;
-- PK (promotion_id,case_id) already exists and is preserved.
-- Proposals remain globally one-use, independent of the case and rule.
CREATE UNIQUE INDEX lf_rule_promotion_proposal_quote_one_case_v2
 ON public.lf_rule_promotion_citation_capture_v1(quote_sha256)
 WHERE literal_origin='PROPOSAL';

-- Cross-rule BASE reuse and any reuse involving a PROPOSAL are rejected.
-- The transactional advisory lock serializes concurrent inserts of the same SHA:
-- it is NOT an authorization or a quote-validity substitute.
CREATE FUNCTION public.lf_rule_promotion_citation_scope_guard_v2()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $l8$
DECLARE v_source public.lf_rule_promotion_citation_source_v1%ROWTYPE;
BEGIN
 SELECT * INTO v_source FROM public.lf_rule_promotion_citation_source_v1
 WHERE promotion_id=NEW.promotion_id AND case_id=NEW.case_id;
 IF NOT FOUND OR v_source.rule_code IS DISTINCT FROM
   (SELECT rule_code FROM public.lf_rule_promotion_v1
     WHERE promotion_id=NEW.promotion_id)
 THEN RAISE EXCEPTION USING ERRCODE='23505',
      MESSAGE='BLOCK_L8_CITATION_CASE_SOURCE_MISMATCH'; END IF;
 IF NEW.quote_sha256 IS DISTINCT FROM
    encode(extensions.digest(convert_to(NEW.literal_excerpt,'UTF8'),'sha256'),'hex')
    OR (NEW.literal_origin='BASE_RULE'
        AND position(NEW.literal_excerpt IN v_source.base_rule->>'description')=0)
    OR (NEW.literal_origin='PROPOSAL'
        AND position(NEW.literal_excerpt IN v_source.proposal->>'description')=0)
 THEN RAISE EXCEPTION USING ERRCODE='23505',
      MESSAGE='BLOCK_L8_CITATION_ORIGIN_OR_SHA_INVALID'; END IF;

 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.quote_sha256,0));
 IF EXISTS(
  SELECT 1
  FROM public.lf_rule_promotion_citation_capture_v1 existing
  JOIN public.lf_rule_promotion_citation_source_v1 other
    ON other.promotion_id=existing.promotion_id AND other.case_id=existing.case_id
  WHERE existing.quote_sha256=NEW.quote_sha256
    AND (
      other.rule_code IS DISTINCT FROM v_source.rule_code
      OR NEW.literal_origin='PROPOSAL'
      OR existing.literal_origin='PROPOSAL'
    )
 ) THEN RAISE EXCEPTION USING ERRCODE='23505',
      MESSAGE='BLOCK_L8_QUOTE_REUSE_PROPOSAL_OR_CROSS_RULE'; END IF;
 RETURN NEW;
END $l8$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_citation_scope_guard_v2()
  FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER trg_lf_rule_promotion_citation_reuse_scope_v2
 BEFORE INSERT ON public.lf_rule_promotion_citation_capture_v1
 FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_citation_scope_guard_v2();
COMMIT;
