-- T-REMED layer 2 (complete), option A: when several rules of one screen cite DIFFERENT targets for the same specific reference
-- (reconcile verdict ESCALATE:SOURCE_CONFLICT), every cited target is written as a CANDIDATO link (never VIGENTE).
-- Layer 3 (independent judge) decides; its NO_CONFLICT criterion keeps these links from being promoted while the conflict stands.
-- Everything else is unchanged from 20261010050000.
create or replace function programacion.fn_t_remed_complete_v3(p_pantalla_id integer, p_consumer text default 'IG_CURATOR')
 returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare
  v_rec jsonb; p jsonb; v_link_id bigint; v_status text; v_applied int:=0; v_already int:=0; v_skipped int:=0; v_actions jsonb:='[]'::jsonb; v_action jsonb; v_back record; v_exists bigint;
begin
  if nullif(trim(p_consumer),'') is null then raise exception 'T_REMED_CONSUMER_REQUIRED'; end if;
  v_rec:=programacion.fn_t_remed_reconcile_v3(p_pantalla_id);
  for p in select value from jsonb_array_elements(v_rec->'proposals') loop
    if p->>'verdict' not in ('LINK_CANDIDATE','ESCALATE:SOURCE_CONFLICT') then
      v_skipped:=v_skipped+1;
      v_action:=jsonb_build_object('action','NO_WRITE','reason',p->>'verdict','reference_role',p->>'reference_role','target_id',p->'target_id','rule_codes',p->'rule_codes');
    else
      select link_id into v_exists from programacion.t_remed_links
       where subject_kind='PANTALLA' and subject_id=p_pantalla_id and reference_role=p->>'reference_role'
         and target_table=p->>'target_table' and target_id=(p->>'target_id')::bigint;
      if v_exists is not null then
        v_already:=v_already+1;
        v_action:=jsonb_build_object('action','ALREADY_LINKED','link_id',v_exists,'reference_role',p->>'reference_role','target_id',p->'target_id');
      else
        v_status:=case when p->>'verdict'='LINK_CANDIDATE' and p->'rule_states'='["VIGENTE"]'::jsonb and p->>'target_status'='VIGENTE' then 'VIGENTE' else 'CANDIDATO' end;
        insert into programacion.t_remed_links(subject_kind,subject_id,reference_role,target_table,target_id,status)
        values('PANTALLA',p_pantalla_id,p->>'reference_role',p->>'target_table',(p->>'target_id')::bigint,v_status) returning link_id into v_link_id;
        insert into programacion.t_remed_link_sources(link_id,rule_id) select v_link_id,x::bigint from jsonb_array_elements_text(p->'rule_ids') x;
        select l.status, l.target_id, (select count(*) from programacion.t_remed_link_sources s where s.link_id=l.link_id) n into v_back
          from programacion.t_remed_links l where l.link_id=v_link_id;
        if v_back.status is distinct from v_status or v_back.target_id is distinct from (p->>'target_id')::bigint
           or v_back.n<>jsonb_array_length(p->'rule_ids') then raise exception 'T_REMED_READBACK_FAILED:%',v_link_id; end if;
        insert into programacion.t_remed_change_log(layer,subject_kind,subject_id,kind,target_table,pk_col,pk_value,after_value,actor)
        values('COMPLETE','PANTALLA',p_pantalla_id,'LINK_INSERT','programacion.t_remed_links','link_id',v_link_id,v_status,p_consumer);
        v_applied:=v_applied+1;
        v_action:=jsonb_build_object('action',case when p->>'verdict'='LINK_CANDIDATE' then 'LINK_EXPLICIT_REFERENCE' else 'LINK_CONFLICTING_CANDIDATE' end,'link_id',v_link_id,'reference_role',p->>'reference_role','target_id',p->'target_id','link_status',v_status);
      end if;
    end if;
    v_actions:=v_actions||jsonb_build_array(v_action);
    insert into programacion.t_remed_receipts(layer,subject_kind,subject_id,consumer,action,result,evidence,evidence_sha256)
    values('COMPLETE','PANTALLA',p_pantalla_id,p_consumer,v_action->>'action',
           case v_action->>'action' when 'LINK_EXPLICIT_REFERENCE' then 'APPLIED' when 'LINK_CONFLICTING_CANDIDATE' then 'APPLIED' when 'ALREADY_LINKED' then 'NOOP' else 'NO_WRITE' end,
           v_action,encode(sha256(convert_to(v_action::text,'UTF8')),'hex'));
  end loop;
  return jsonb_build_object('capability','T_REMED','layer','COMPLETE','version',3,'consumer',p_consumer,'pantalla_id',p_pantalla_id,
    'applied_count',v_applied,'already_linked_count',v_already,'skipped_count',v_skipped,'actions',v_actions);
end;
$fn$;
