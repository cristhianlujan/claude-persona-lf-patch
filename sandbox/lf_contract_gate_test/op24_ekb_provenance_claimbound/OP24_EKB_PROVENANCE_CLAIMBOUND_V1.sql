-- OP24 EKB provenance claim-bound consolidation V1 — candidate DML only.
-- Source-first and approval-gated. No durable write is authorized by this file.
-- Resolves the claim-binding manifest by checkpoint identity, validates its immutable
-- bindings digest and current EKB row evidence, then composes PR provenance with
-- the durable manifest receipt. Does not assert semantic correctness of the PR.

do $op24$
declare
  v_manifest_id bigint;
  v_bindings jsonb;
  v_bindings_sha text;
  v_expected_sha constant text := 'de81fb5839a6e89b4882065ff660f601ebc0949f970a567636b897886a76ceb0';
  v_manifest_count integer;
  v_eligible integer;
  v_updated integer;
begin
  select count(*), min(e.id)
    into v_manifest_count, v_manifest_id
  from public.lf_eventos e
  where e.entidad_codigo='LF_LEARNED_CONTEXT_MEMORY_OPERATIONAL_PLAN_20260904'
    and e.payload->>'checkpoint_id'='GPT_CP_OP24_P1_CONTAINER_CLAIM_BINDING_001';

  if v_manifest_count <> 1 or v_manifest_id is null then
    raise exception 'OP24_CLAIM_BINDING_MANIFEST_CARDINALITY expected=1 observed=%',v_manifest_count;
  end if;

  select e.payload->'bindings', e.payload->>'bindings_sha256'
    into v_bindings, v_bindings_sha
  from public.lf_eventos e
  where e.id=v_manifest_id;

  if jsonb_typeof(v_bindings) is distinct from 'array'
     or jsonb_array_length(v_bindings) <> 41 then
    raise exception 'OP24_CLAIM_BINDING_MANIFEST_SHAPE';
  end if;

  if v_bindings_sha is distinct from v_expected_sha
     or encode(extensions.digest(convert_to(v_bindings::text,'UTF8'),'sha256'),'hex') is distinct from v_expected_sha then
    raise exception 'OP24_CLAIM_BINDING_MANIFEST_DIGEST_MISMATCH';
  end if;

  with binding as (
    select value->>'code' as code,
           value->>'pr_number' as expected_pr,
           value->>'pr_ref' as pr_ref,
           value->>'evidence_sha256' as evidence_sha256
    from jsonb_array_elements(v_bindings)
  )
  select count(*) into v_eligible
  from binding b
  join transversal.error_knowledge e on e.codigo=b.code
  where e.source_ref is null
    and regexp_replace(coalesce(e.pr,''),'[^0-9]','','g')=b.expected_pr
    and encode(extensions.digest(convert_to(coalesce(e.evidencia,''),'UTF8'),'sha256'),'hex')=b.evidence_sha256;

  if v_eligible <> 41 then
    raise exception 'OP24_CLAIM_BOUND_ELIGIBILITY_MISMATCH expected=41 observed=%',v_eligible;
  end if;

  with binding as (
    select value->>'code' as code,
           value->>'pr_number' as expected_pr,
           value->>'pr_ref' as pr_ref,
           value->>'evidence_sha256' as evidence_sha256
    from jsonb_array_elements(v_bindings)
  )
  update transversal.error_knowledge e
     set source_ref=b.pr_ref
          ||'|supabase://mhwmirqcgxxukpctffuv/public/lf_eventos/'||v_manifest_id::text
          ||'#binding='||b.code,
         updated_at=clock_timestamp()
  from binding b
  where e.codigo=b.code
    and e.source_ref is null
    and regexp_replace(coalesce(e.pr,''),'[^0-9]','','g')=b.expected_pr
    and encode(extensions.digest(convert_to(coalesce(e.evidencia,''),'UTF8'),'sha256'),'hex')=b.evidence_sha256;

  get diagnostics v_updated=row_count;
  if v_updated <> 41 then
    raise exception 'OP24_CLAIM_BOUND_UPDATE_COUNT_MISMATCH expected=41 observed=%',v_updated;
  end if;

  if exists (
    with binding as (
      select value->>'code' as code,
             value->>'pr_ref' as pr_ref
      from jsonb_array_elements(v_bindings)
    )
    select 1
    from binding b
    join transversal.error_knowledge e on e.codigo=b.code
    where e.source_ref is distinct from (
      b.pr_ref||'|supabase://mhwmirqcgxxukpctffuv/public/lf_eventos/'||v_manifest_id::text||'#binding='||b.code
    )
  ) then
    raise exception 'OP24_CLAIM_BOUND_POSTCONDITION_FAILED';
  end if;
end
$op24$;
