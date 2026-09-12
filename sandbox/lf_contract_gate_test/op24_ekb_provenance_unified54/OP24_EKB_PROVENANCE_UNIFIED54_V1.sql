-- OP24 P1 unified provenance reconstruction candidate — 54 unique rows.
-- Candidate-only. No durable application is authorized by this source.
-- Resolves two durable claim-binding manifests and fails closed on drift.

do $op24$
declare
  v_container_event_id bigint;
  v_exact_event_id bigint;
  v_container jsonb;
  v_exact jsonb;
  v_bindings jsonb;
  v_count integer;
  v_duplicates integer;
  v_eligible integer;
  v_updated integer;
begin
  select e.id,e.payload into v_container_event_id,v_container
  from public.lf_eventos e
  where e.evento_tipo='REVISION'
    and e.entidad_tipo='LF_EKB_PROVENANCE_BINDING_MANIFEST'
    and e.payload->>'checkpoint_id'='GPT_CP_OP24_P1_CONTAINER_CLAIM_BINDING_001'
    and e.payload->>'bindings_sha256'='de81fb5839a6e89b4882065ff660f601ebc0949f970a567636b897886a76ceb0'
  order by e.id desc
  limit 1;
  if not found then
    raise exception 'OP24_P1_CONTAINER_MANIFEST_NOT_FOUND';
  end if;

  select e.id,e.payload into v_exact_event_id,v_exact
  from public.lf_eventos e
  where e.evento_tipo='REVISION'
    and e.entidad_tipo='LF_EKB_PROVENANCE_BINDING_MANIFEST'
    and e.payload->>'checkpoint_id'='GPT_CP_OP24_P1_EXACT_CLAIM_BINDING_001'
    and e.payload->>'bindings_sha256'='9aaaa513f3e491d6c453901cd7e5319c6544c301ac45484242a63c97e1931ac1'
  order by e.id desc
  limit 1;
  if not found then
    raise exception 'OP24_P1_EXACT_MANIFEST_NOT_FOUND';
  end if;

  if coalesce((v_container->>'binding_count')::integer,-1) <> 41
     or jsonb_array_length(coalesce(v_container->'bindings','[]'::jsonb)) <> 41 then
    raise exception 'OP24_P1_CONTAINER_MANIFEST_COUNT_MISMATCH';
  end if;
  if coalesce((v_exact->>'binding_count')::integer,-1) <> 13
     or jsonb_array_length(coalesce(v_exact->'bindings','[]'::jsonb)) <> 13 then
    raise exception 'OP24_P1_EXACT_MANIFEST_COUNT_MISMATCH';
  end if;

  select jsonb_agg(x order by x->>'code') into v_bindings
  from (
    select jsonb_build_object(
      'code',b->>'code',
      'kind','PR_CONTAINER',
      'pr_number',b->>'pr_number',
      'evidence_sha256',b->>'evidence_sha256',
      'source_ref',(b->>'pr_ref') || '|supabase://mhwmirqcgxxukpctffuv/public/lf_eventos/' || v_container_event_id::text || '#binding=' || (b->>'code')
    ) as x
    from jsonb_array_elements(v_container->'bindings') b
    union all
    select jsonb_build_object(
      'code',b->>'code',
      'kind','EXACT_EXTERNAL_REF',
      'pr_number',null,
      'evidence_sha256',b->>'evidence_sha256',
      'source_ref',(b->>'source_ref') || '|supabase://mhwmirqcgxxukpctffuv/public/lf_eventos/' || v_exact_event_id::text || '#binding=' || (b->>'code')
    ) as x
    from jsonb_array_elements(v_exact->'bindings') b
  ) q;

  select count(*) into v_count from jsonb_array_elements(v_bindings);
  if v_count <> 54 then
    raise exception 'OP24_P1_UNIFIED_BINDING_COUNT_MISMATCH expected=54 observed=%',v_count;
  end if;

  select count(*) into v_duplicates
  from (
    select x->>'code' code,count(*) n
    from jsonb_array_elements(v_bindings) x
    group by 1 having count(*) > 1
  ) d;
  if v_duplicates <> 0 then
    raise exception 'OP24_P1_DUPLICATE_CODE_BINDING count=%',v_duplicates;
  end if;

  select count(*) into v_eligible
  from jsonb_array_elements(v_bindings) x
  join transversal.error_knowledge k on k.codigo=x->>'code'
  where k.source_ref is null
    and encode(extensions.digest(convert_to(coalesce(k.evidencia,''),'UTF8'),'sha256'),'hex') = x->>'evidence_sha256'
    and (
      x->>'kind'='EXACT_EXTERNAL_REF'
      or regexp_replace(coalesce(k.pr,''),'[^0-9]','','g') = x->>'pr_number'
    );
  if v_eligible <> 54 then
    raise exception 'OP24_P1_ELIGIBILITY_MISMATCH expected=54 observed=%',v_eligible;
  end if;

  update transversal.error_knowledge k
     set source_ref=x->>'source_ref',
         updated_at=clock_timestamp()
  from jsonb_array_elements(v_bindings) x
  where k.codigo=x->>'code'
    and k.source_ref is null
    and encode(extensions.digest(convert_to(coalesce(k.evidencia,''),'UTF8'),'sha256'),'hex') = x->>'evidence_sha256'
    and (
      x->>'kind'='EXACT_EXTERNAL_REF'
      or regexp_replace(coalesce(k.pr,''),'[^0-9]','','g') = x->>'pr_number'
    );
  get diagnostics v_updated=row_count;
  if v_updated <> 54 then
    raise exception 'OP24_P1_UPDATE_COUNT_MISMATCH expected=54 observed=%',v_updated;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_bindings) x
    join transversal.error_knowledge k on k.codigo=x->>'code'
    where k.source_ref is distinct from x->>'source_ref'
  ) then
    raise exception 'OP24_P1_POSTCONDITION_FAILED';
  end if;
end
$op24$;
