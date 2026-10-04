-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M7.6 / PAULO-145 only.
-- Closure consumes 7 immutable EVIDENCE_LEDGER receipts already verified through
-- INDEPENDENT_ASSURANCE. No Validator change, no new judge/authority, no M7.14.
-- Gold B source cases_sha256: 5540c8b369c80ceb15003c0a9b90a6ffaadcb03b68f0f781bfbc0e6221a5f60e
begin;

create temp table _m76_close_cases(
  run_id bigint,
  family_code text,
  coverage text,
  well_defined text,
  primary_sha text,
  secondary_sha text,
  evidence_sha text,
  adjudication_sha text,
  source_refs text[]
) on commit drop;

insert into _m76_close_cases values
(373,'MFA_OTP_SSO','PARTIAL','PARTIAL','dab8019047812ac275d1f5df3c860c180311acc7e407ad99ffd8ffa2b608fd5a',null,'ee4a84eba2e925b71c0abf2cd4d73af83de05856c7d7623c9441064450e3b473','59f1668262b5f7583f7e18ccffff93bae78f1b4a16adc8ca49d348cae8197b47',array['SCREEN_CANONICAL_GRAPH']::text[]),
(373,'STATES','MISSING','MISSING','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',null,'fde076b4a85c7280f3376f003f0e946573a580d0544313ab79725945a29b0f18','71c14e3396a739cf5bfa5fcf969ead7d57a2fd6cf5554623f0e308e1de2e3273',array['SCREEN_STATE_SET']::text[]),
(373,'TRANSITIONS','PARTIAL','PARTIAL','dab8019047812ac275d1f5df3c860c180311acc7e407ad99ffd8ffa2b608fd5a','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945','a2ce5ff7fb6995cdf0af0a73ac83ad76c62a7cfb279265d836f5e86d25460907','7f7dcd44dbfd013e00a40a1687221f805479e31268fd84cb83d0015249584954',array['SCREEN_CANONICAL_GRAPH','SCREEN_STATE_SET']::text[]),
(374,'MFA_OTP_SSO','PARTIAL','PARTIAL','761e375a646f163048f6bd160f2a3ed641abfbf0e2f4e6c72ba18040b6a0a1b4',null,'183b3e7e6ee002b20ecb65e2b0d97d6525429b4963df25eda6ffb595231ed969','48bfc4462ea96d99f2e44130a88053ffba54e2fc6643ec8d6ebce3decf1d3a11',array['SCREEN_CANONICAL_GRAPH']::text[]),
(374,'OBJECTIVE_OUTCOMES','MISSING','MISSING','761e375a646f163048f6bd160f2a3ed641abfbf0e2f4e6c72ba18040b6a0a1b4',null,'183b3e7e6ee002b20ecb65e2b0d97d6525429b4963df25eda6ffb595231ed969','d9be382b7b08f16a83296023004698bed62cdb0d54b20fe273167677be085b7b',array['SCREEN_CANONICAL_GRAPH']::text[]),
(374,'STATES','MISSING','MISSING','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',null,'ca643e5ae0ab2c03a8abd0ecefaaf3e4df1290d070c02e322d658e9f416e75b3','a0d76adb6b0f3607ef2eb4420bcfe85980ba385523640bc9703bfd2b99411f1b',array['SCREEN_STATE_SET']::text[]),
(374,'TRANSITIONS','PARTIAL','PARTIAL','761e375a646f163048f6bd160f2a3ed641abfbf0e2f4e6c72ba18040b6a0a1b4','4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945','da8895d5eccc9902d1b744b64ce2562abad0141fb189ed760af191515b224bb5','1d8c7682e801b3be105e0537f9fdfe945929ac83a9b0bae419905bc78e05d2ca',array['SCREEN_CANONICAL_GRAPH','SCREEN_STATE_SET']::text[]);

do $$
declare
  v_work_id bigint;
  v_n int;
  v_weight numeric;
begin
  select id into v_work_id
  from programacion.engineering_work_items
  where work_code='PAULO-145';
  if v_work_id is null then raise exception 'M7_6_WORK_ITEM_MISSING'; end if;

  if (select count(*) from _m76_close_cases) <> 7 then
    raise exception 'M7_6_CASE_SET_NOT_7';
  end if;

  if (select estado from transversal.decision_log where adr='DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001') is distinct from 'VIGENTE' then
    raise exception 'M7_6_M1_7_AUTHORITY_NOT_CURRENT';
  end if;

  if (select count(*) from (values(373::bigint),(374::bigint)) x(id)
      where programacion.fn_input_readiness_run_is_current_cached_v2(id)) <> 2 then
    raise exception 'M7_6_RUN_CURRENTNESS_DRIFT';
  end if;

  if (select count(*) from programacion.input_family_assessments where run_id in(373,374) and severity='P0') <> 7 then
    raise exception 'M7_6_CRITICAL_SET_DRIFT';
  end if;

  if (select count(*) from programacion.engineering_work_checkpoints
      where work_item_id=v_work_id
        and checkpoint_code in('GOLD_ASIS','ADJUDICATION_AUTHORITY','CRITICAL_CASE_SET','INDEPENDENCE_NEGATIVE')
        and status='DONE') <> 4 then
    raise exception 'M7_6_PRIOR_CHECKPOINTS_NOT_4_DONE';
  end if;

  -- Exact 7 subjects, authority, provider head/blob, independent reviewer and exact payload.
  select count(*) into v_n
  from _m76_close_cases g
  join private.lf_evidence_ledger_v1 l
    on l.capability_code='INDEPENDENT_ASSURANCE'
   and l.receipt_kind='AUDIT_VERDICT'
   and l.subject_type='INPUT_GOV_GOLD_B_CRITICAL_CASE'
   and l.subject_ref='IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||g.run_id::text||'-'||g.family_code
   and l.subject_sha256=g.adjudication_sha
   and l.verification_state='VERIFIED'
   and l.source_head_sha='c07f6a16d7d270803540a13b9be95dd053f25c43'
   and l.authority_ref='supabase://transversal.decision_log/DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001'
   and l.receipt_payload->>'verdict'='PASS'
   and l.receipt_payload->'independent'='true'::jsonb
   and l.receipt_payload#>>'{independence_measure,state}'='INDEPENDENT'
   and l.receipt_payload->>'reviewer_identity'='INDEPENDENT_ASSURANCE:EXEC-IG-M7-6-INDEP-20261004-001'
   and l.receipt_payload->>'artifact_blob_sha'='87d438bfc44d89c92c04e9f666ef39ee3cbca62f'
   and l.receipt_payload->>'cases_sha256'='5540c8b369c80ceb15003c0a9b90a6ffaadcb03b68f0f781bfbc0e6221a5f60e'
   and l.receipt_payload->'expected'=jsonb_build_object(
      'severity','P0','coverage_status',g.coverage,'well_defined_status',g.well_defined,
      'story_ready_status','BLOCKED','implementation_ready_status','BLOCKED',
      'qa_ready_status','BLOCKED','production_ready_status','BLOCKED')
   and l.receipt_payload->'oracle'=jsonb_build_object(
      'contract_revision','5.13','story_rule','NO_STORY_STAGE_OPEN',
      'obligation_ref','supabase://public.lf_assurance_obligation_catalog/IG-C5_13-STORY_READY_RULE@1')
   and l.receipt_payload->'evidence'=jsonb_build_object(
      'mode','DIRECT_CANONICAL_READBACK_NOT_CURATOR_VALIDATOR_CONCLUSION',
      'source_refs',to_jsonb(g.source_refs),
      'source_observed_sha256_primary',g.primary_sha,
      'source_observed_sha256_secondary',g.secondary_sha,
      'evidence_sha256',g.evidence_sha,
      'contract_ref','supabase://programacion.contratos/37#5.13');
  if v_n<>7 then raise exception 'M7_6_LEDGER_EXACT_RECEIPTS_NOT_7:%',v_n; end if;

  if exists(
    select 1
    from _m76_close_cases g
    join private.lf_evidence_ledger_v1 l
      on l.subject_ref='IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||g.run_id::text||'-'||g.family_code
     and l.subject_sha256=g.adjudication_sha
     and l.capability_code='INDEPENDENT_ASSURANCE'
    join programacion.input_readiness_runs r on r.id=g.run_id
    where l.receipt_payload->>'reviewer_identity' in(r.curator_identity,r.validator_identity)
  ) then raise exception 'M7_6_SELF_ADJUDICATION_DETECTED'; end if;

  -- Recompute composition digest and full receipt digest from immutable rows.
  if exists(
    select 1
    from _m76_close_cases g
    join private.lf_evidence_ledger_v1 l
      on l.subject_ref='IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||g.run_id::text||'-'||g.family_code
     and l.subject_sha256=g.adjudication_sha
     and l.capability_code='INDEPENDENT_ASSURANCE'
    where l.receipt_payload->>'composition_sha256' is distinct from
      encode(extensions.digest(convert_to(jsonb_build_object(
        'schema_version','LF_EVIDENCE_COMPOSITION_V1',
        'orchestrator_execution_id',l.receipt_payload->>'orchestrator_execution_id',
        'plan_digest',l.receipt_payload->>'plan_digest',
        'ledger_execution_id',l.created_by_execution_id,
        'producer_execution_id',l.execution_id,
        'producer_capability_code',l.capability_code,
        'gate_code',l.gate_code,'receipt_kind',l.receipt_kind,
        'subject_type',l.subject_type,'subject_ref',l.subject_ref,
        'subject_sha256',l.subject_sha256,'source_head_sha',l.source_head_sha,
        'authority_ref',l.authority_ref,'resolver_id',l.resolver_id,
        'provider',l.provider,'provider_ref',l.provider_ref,
        'verification_method',l.verification_method)::text,'UTF8'),'sha256'),'hex')
  ) then raise exception 'M7_6_COMPOSITION_DIGEST_RECOMPUTE_MISMATCH'; end if;

  if exists(
    select 1
    from _m76_close_cases g
    join private.lf_evidence_ledger_v1 l
      on l.subject_ref='IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.6/GB-'||g.run_id::text||'-'||g.family_code
     and l.subject_sha256=g.adjudication_sha
     and l.capability_code='INDEPENDENT_ASSURANCE'
    where l.receipt_sha256 is distinct from
      encode(extensions.digest(convert_to(jsonb_build_object(
        'schema_version','LF_EVIDENCE_LEDGER_RECEIPT_V1',
        'execution_id',l.execution_id,'capability_code',l.capability_code,
        'gate_code',l.gate_code,'receipt_kind',l.receipt_kind,
        'subject_type',l.subject_type,'subject_ref',l.subject_ref,
        'subject_sha256',l.subject_sha256,'source_head_sha',l.source_head_sha,
        'authority_ref',l.authority_ref,'resolver_id',l.resolver_id,
        'provider',l.provider,'provider_ref',l.provider_ref,
        'verification_method',l.verification_method,'verification_state',l.verification_state,
        'verification_payload',l.verification_payload,'receipt_payload',l.receipt_payload,
        'created_by_execution_id',l.created_by_execution_id)::text,'UTF8'),'sha256'),'hex')
  ) then raise exception 'M7_6_RECEIPT_DIGEST_RECOMPUTE_MISMATCH'; end if;

  update programacion.engineering_work_checkpoints
     set status='DONE',completed_at=now(),updated_at=now(),updated_by_execution_id='PAULO-145',
         evidence_ref=case checkpoint_code
           when 'GOLD_B_PERSISTED' then 'supabase://private.lf_evidence_ledger_v1?capability_code=INDEPENDENT_ASSURANCE&subject_type=INPUT_GOV_GOLD_B_CRITICAL_CASE#verified=7'
           when 'GOLD_B_READBACK' then 'supabase://private.lf_evidence_ledger_v1?capability_code=INDEPENDENT_ASSURANCE&subject_type=INPUT_GOV_GOLD_B_CRITICAL_CASE#verified=7;digest_match=7;consumer_pass=7'
           else evidence_ref end
   where work_item_id=v_work_id and checkpoint_code in('GOLD_B_PERSISTED','GOLD_B_READBACK');

  select count(*),coalesce(sum(weight),0) into v_n,v_weight
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_id and status='DONE';
  if v_n<>6 or v_weight<>100 then
    raise exception 'M7_6_CHECKPOINT_READBACK_FAILED:done=% weight=%',v_n,v_weight;
  end if;

  update programacion.engineering_work_items
     set status='DONE',started_at=coalesce(started_at,now()),completed_at=now(),updated_at=now(),
         updated_by_execution_id='PAULO-145',
         source_ref='supabase://public.lf_error_knowledge/IG-M7-6-EXTERNAL-GOLD-B-RECEIPTS-PENDING-001'
   where id=v_work_id and work_code='PAULO-145';
  if not found then raise exception 'M7_6_WORK_ITEM_DONE_UPDATE_FAILED'; end if;
end $$;

update public.lf_error_knowledge
set estado='RESUELTO',
    frecuencia=coalesce(frecuencia,0)+1,
    ultima_vez=now(),
    updated_at=now(),
    validacion=coalesce(validacion,'')||E'\n[CLOSE_M7_6_20261004] 7/7 EVIDENCE_LEDGER receipts VERIFIED; 7/7 adapter PASS; reviewer distinct 7/7; independence 7/7; composition_sha256 recomputed 7/7; receipt_sha256 recomputed 7/7; exact Gold B source head c07f6a16d7d270803540a13b9be95dd053f25c43; cases_sha256=5540c8b369c80ceb15003c0a9b90a6ffaadcb03b68f0f781bfbc0e6221a5f60e; M7.6 6/6 DONE.',
    evidencia='supabase://private.lf_evidence_ledger_v1?capability_code=INDEPENDENT_ASSURANCE&subject_type=INPUT_GOV_GOLD_B_CRITICAL_CASE#verified=7;github://cristhianlujan/claude-persona-lf-patch@c07f6a16d7d270803540a13b9be95dd053f25c43/supabase/migrations/20261004074000_ig_cv_m7_6_gold_b_independent_v1.sql'
where codigo='IG-M7-6-EXTERNAL-GOLD-B-RECEIPTS-PENDING-001';

do $$
declare v_work_id bigint; v_status text; v_done int; v_pending int;
begin
  select id,status into v_work_id,v_status from programacion.engineering_work_items where work_code='PAULO-145';
  select count(*) filter(where status='DONE'),count(*) filter(where status<>'DONE')
    into v_done,v_pending from programacion.engineering_work_checkpoints where work_item_id=v_work_id;
  if v_status<>'DONE' or v_done<>6 or v_pending<>0 then
    raise exception 'M7_6_TERMINAL_READBACK_FAILED:status=% done=% non_done=%',v_status,v_done,v_pending;
  end if;
end $$;

commit;
