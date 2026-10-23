-- Qualification for the same transaction as the candidate DDL; NEVER standalone apply.
-- Caller must run BEGIN; <exact migration SQL>; <this test>; ROLLBACK.
-- A protected provenance issuer + real ACTIVE authority policy are deliberately
-- NOT mocked or activated here. A live positive test is a separate cutover gate.
do $qualification$
declare
  v_screen integer;
  v_transition bigint;
  v_other_screen integer;
  v_baseline jsonb;
  v_new jsonb;
  v_attempt jsonb;
  v_foreign_receipt_id bigint;
  v_checked integer:=0;
begin
  for v_screen,v_transition in
    select pe.pantalla_id,min(et.transition_id)
    from lf_ops.pantallas_estados pe
    join lf_ops.estados_transiciones et
      on pe.state_id in (et.from_state_id,et.to_state_id)
    where pe.pantalla_id in (52,53,56) and et.status='CANDIDATO'
    group by pe.pantalla_id order by pe.pantalla_id
  loop
    v_baseline:=private.fn_lf_ig_candidate_action_context_v1(v_screen,v_transition);
    if v_baseline->>'state'<>'READY_FOR_AUTHORIZATION' then
      raise exception 'IG_ACTION_CONTEXT_NOT_READY:%:%:%',v_screen,v_transition,v_baseline;
    end if;
    v_other_screen:=-1;
    if private.fn_lf_ig_candidate_action_context_v1(v_other_screen,v_transition)->>'code'
       is distinct from 'CANDIDATE_SCREEN_MISMATCH' then
      raise exception 'IG_ACTION_WRONG_SCREEN_ALLOWED:%',v_transition;
    end if;
    if private.fn_lf_ig_candidate_action_receipt_verify_v1(v_screen,v_transition,null)->>'code'
       is distinct from 'ACTION_RECEIPT_REQUIRED' then
      raise exception 'IG_ACTION_MISSING_RECEIPT_ALLOWED:%',v_transition;
    end if;
    if private.fn_lf_ig_candidate_action_receipt_verify_v1(v_screen,v_transition,9223372036854775807)->>'code'
       is distinct from 'ACTION_RECEIPT_NOT_FOUND' then
      raise exception 'IG_ACTION_FAKE_RECEIPT_ALLOWED:%',v_transition;
    end if;
    v_attempt:=private.fn_lf_ig_candidate_promotion_consume_v1(v_screen,v_transition,null);
    if v_attempt->>'code' is distinct from 'ACTION_RECEIPT_REQUIRED' then
      raise exception 'IG_ACTION_CONSUMER_NO_RECEIPT_ALLOWED:%',v_transition;
    end if;
    if (select status from lf_ops.estados_transiciones where transition_id=v_transition)
       is distinct from 'CANDIDATO' then
      raise exception 'IG_ACTION_UNAUTHORIZED_STATUS_MUTATION:%',v_transition;
    end if;
    v_checked:=v_checked+1;
  end loop;

  if v_checked<>3 then raise exception 'IG_ACTION_EXPECTED_THREE_READY_SCREENS:%',v_checked;end if;
  if (select count(*) from private.lf_ig_candidate_action_consumptions_v1)<>0 then
    raise exception 'IG_ACTION_UNAUTHORIZED_CONSUMPTION_LEDGER';
  end if;
  v_baseline:=private.fn_lf_ig_candidate_action_context_v1(52,(
    select min(et.transition_id) from lf_ops.pantallas_estados pe
    join lf_ops.estados_transiciones et
    on pe.state_id in (et.from_state_id,et.to_state_id)
    where pe.pantalla_id=52 and et.status='CANDIDATO'
  ));
  update lf_ops.estados_transiciones
  set requires_comment=not requires_comment
  where transition_id=(v_baseline->>'transition_id')::bigint;
  v_new:=private.fn_lf_ig_candidate_action_context_v1(52,(v_baseline->>'transition_id')::bigint);
  if v_new->>'currentness_sha256' is not distinct from v_baseline->>'currentness_sha256'
  then raise exception 'IG_ACTION_STALE_CURRENTNESS_UNDETECTED';end if;
end $qualification$;

select 'PASS_IG_CANDIDATE_ACTION_NEGATIVE_ROLLBACK' as verdict,
       3 as eligible_screen_cases,
       true as no_persistent_writes,
       true as authority_policies_remain_unactivated;
