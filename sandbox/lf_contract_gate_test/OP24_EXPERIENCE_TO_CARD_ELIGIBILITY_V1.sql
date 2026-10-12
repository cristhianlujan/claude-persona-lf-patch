-- OP24 Experience -> Card Eligibility V1 — sandbox harness
-- Contract-level verifier only. It does not create Cards and has no production authority.

create or replace function private.sbx_fn_lf_experience_to_card_eligibility_v1(
  p_candidate jsonb,
  p_duplicate boolean default false,
  p_conflict boolean default false
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog', 'private'
as $function$
declare
  v_required text[] := array[
    'codigo',
    'titulo',
    'descripcion',
    'validacion',
    'lifecycle_phase',
    'consumer_role',
    'source_ref'
  ];
  v_missing text[] := array[]::text[];
  v_key text;
begin
  if p_candidate is null or jsonb_typeof(p_candidate) <> 'object' then
    return jsonb_build_object('eligible', false, 'disposition', 'BLOCK', 'reason', 'CANDIDATE_OBJECT_REQUIRED');
  end if;

  foreach v_key in array v_required loop
    if not (p_candidate ? v_key) then
      v_missing := array_append(v_missing, v_key);
      continue;
    end if;

    if v_key = 'consumer_role' then
      if jsonb_typeof(p_candidate->v_key) <> 'array'
         or jsonb_array_length(p_candidate->v_key) = 0 then
        v_missing := array_append(v_missing, v_key);
      end if;
    elsif p_candidate->v_key = 'null'::jsonb
          or length(btrim(coalesce(p_candidate->>v_key, ''))) = 0 then
      v_missing := array_append(v_missing, v_key);
    end if;
  end loop;

  if cardinality(v_missing) > 0 then
    return jsonb_build_object(
      'eligible', false,
      'disposition', 'BLOCK',
      'reason', 'REQUIRED_SIGNAL_MISSING',
      'missing', to_jsonb(v_missing)
    );
  end if;

  if p_conflict then
    return jsonb_build_object('eligible', false, 'disposition', 'REVIEW', 'reason', 'CONTRADICTION_REQUIRES_REVIEW');
  end if;

  if p_duplicate then
    return jsonb_build_object('eligible', false, 'disposition', 'BLOCK', 'reason', 'DUPLICATE_CARD_FORBIDDEN');
  end if;

  return jsonb_build_object(
    'eligible', true,
    'disposition', 'CARD_CANDIDATE_DOSSIER',
    'reason', 'MINIMUM_CONTRACT_SATISFIED',
    'competitor_required', false,
    'direct_card_write', false,
    'direct_impact', false
  );
end;
$function$;

revoke all on function private.sbx_fn_lf_experience_to_card_eligibility_v1(jsonb,boolean,boolean)
  from public, anon, authenticated, service_role;

comment on function private.sbx_fn_lf_experience_to_card_eligibility_v1(jsonb,boolean,boolean) is
  'OP24 sandbox-only Experience-to-Card eligibility verifier. Does not create Cards.';
