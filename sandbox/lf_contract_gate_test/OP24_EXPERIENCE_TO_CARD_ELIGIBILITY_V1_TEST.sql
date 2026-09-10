\set ON_ERROR_STOP on

begin;
\ir OP24_EXPERIENCE_TO_CARD_ELIGIBILITY_V1.sql

do $test$
declare
  v jsonb;
  c jsonb := '{"codigo":"EKB-1","titulo":"t","descripcion":"d","validacion":"v","lifecycle_phase":"VALIDATION","consumer_role":["PROFILE"],"source_ref":"supabase://ekb/1"}'::jsonb;
begin
  -- Positive: no competitor field is required.
  v := private.sbx_fn_lf_experience_to_card_eligibility_v1(c,false,false);
  if (v->>'eligible')::boolean is distinct from true
     or v->>'disposition' <> 'CARD_CANDIDATE_DOSSIER'
     or (v->>'competitor_required')::boolean is distinct from false
     or (v->>'direct_card_write')::boolean is distinct from false
     or (v->>'direct_impact')::boolean is distinct from false then
    raise exception 'EXPECTED_ELIGIBLE_DOSSIER_ONLY: %',v;
  end if;

  -- Negative: missing source_ref blocks.
  v := private.sbx_fn_lf_experience_to_card_eligibility_v1(c - 'source_ref',false,false);
  if v->>'disposition' <> 'BLOCK' or not (v->'missing' @> '["source_ref"]'::jsonb) then
    raise exception 'EXPECTED_SOURCE_REF_BLOCK: %',v;
  end if;

  -- Negative: missing validation blocks.
  v := private.sbx_fn_lf_experience_to_card_eligibility_v1(c - 'validacion',false,false);
  if v->>'disposition' <> 'BLOCK' or not (v->'missing' @> '["validacion"]'::jsonb) then
    raise exception 'EXPECTED_VALIDATION_BLOCK: %',v;
  end if;

  -- Negative: contradiction is reviewed before deduplication.
  v := private.sbx_fn_lf_experience_to_card_eligibility_v1(c,true,true);
  if v->>'disposition' <> 'REVIEW' or v->>'reason' <> 'CONTRADICTION_REQUIRES_REVIEW' then
    raise exception 'EXPECTED_CONTRADICTION_FIRST: %',v;
  end if;

  -- Negative: duplicate without contradiction blocks Card creation.
  v := private.sbx_fn_lf_experience_to_card_eligibility_v1(c,true,false);
  if v->>'disposition' <> 'BLOCK' or v->>'reason' <> 'DUPLICATE_CARD_FORBIDDEN' then
    raise exception 'EXPECTED_DUPLICATE_BLOCK: %',v;
  end if;
end
$test$;

rollback;

do $post$
begin
  if to_regprocedure('private.sbx_fn_lf_experience_to_card_eligibility_v1(jsonb,boolean,boolean)') is not null then
    raise exception 'EXPERIENCE_CARD_TEST_LEFT_FUNCTION_RESIDUE';
  end if;
end
$post$;
