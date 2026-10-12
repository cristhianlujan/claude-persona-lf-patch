-- T-REMED layer 1 (reconcile): permanent invariant self-test.
-- Builds isolated fixtures inside a sub-transaction, runs reconcile on each case, compares against the expected verdict,
-- and ALWAYS rolls everything back (the result travels in the exception message). Nothing persists.
-- status: PASS = observed == expected; KNOWN_GAP = observed == documented current behaviour that is a real limitation; FAIL = anything else.
create or replace function programacion.fn_t_remed_layer1_selftest_v3()
 returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare
  v_cases jsonb := $c$[
    {"name":"01_duplicate_same_value","known_gap":false,
     "rules":[{"v":{"factor_security_policy_id":-9001}},{"v":{"factor_security_policy_id":-9001}}],
     "expect":[{"role":"factor_security_policy_id","target":-9001,"verdict":"LINK_CANDIDATE"}]},
    {"name":"02_contradiction_specific_key","known_gap":false,
     "rules":[{"v":{"factor_security_policy_id":-9001}},{"v":{"factor_security_policy_id":-9002}}],
     "expect":[{"role":"factor_security_policy_id","target":-9001,"verdict":"ESCALATE:SOURCE_CONFLICT"},
               {"role":"factor_security_policy_id","target":-9002,"verdict":"ESCALATE:SOURCE_CONFLICT"}]},
    {"name":"03_generic_key_multiple_targets","known_gap":false,
     "rules":[{"v":{"security_policy_id":-9001}},{"v":{"security_policy_id":-9002}}],
     "expect":[{"role":"security_policy_id","target":-9001,"verdict":"LINK_CANDIDATE"},
               {"role":"security_policy_id","target":-9002,"verdict":"LINK_CANDIDATE"}]},
    {"name":"04_target_not_found","known_gap":false,
     "rules":[{"v":{"factor_security_policy_id":-9999}}],
     "expect":[{"role":"factor_security_policy_id","target":-9999,"verdict":"ESCALATE:TARGET_NOT_FOUND"}]},
    {"name":"05_target_not_active","known_gap":false,
     "rules":[{"v":{"factor_security_policy_id":-9003}}],
     "expect":[{"role":"factor_security_policy_id","target":-9003,"verdict":"DENY:TARGET_NOT_ACTIVE"}]},
    {"name":"06_source_pending_decision","known_gap":false,
     "rules":[{"v":{"factor_security_policy_id":-9001},"pend":true}],
     "expect":[{"role":"factor_security_policy_id","target":-9001,"verdict":"DENY:SOURCE_PENDING_DECISION"}]},
    {"name":"07_no_target_family","known_gap":false,
     "rules":[{"v":{"zzz_nofamily_policy_id":5}}],
     "expect":[{"role":"zzz_nofamily_policy_id","target":5,"verdict":"ABSTAIN:NO_TARGET_FAMILY"}]},
    {"name":"08_partial_information_null_or_text","known_gap":true,
     "rules":[{"v":{"factor_security_policy_id":null}},{"v":{"factor_security_policy_id":"abc"}}],
     "expect":[]},
    {"name":"09_absent_information","known_gap":true,
     "rules":[{"v":{}}],
     "expect":[]},
    {"name":"10_duplicate_rules_without_policy_refs","known_gap":true,
     "rules":[{"v":{"max_attempts":5}},{"v":{"max_attempts":5}}],
     "expect":[]}
  ]$c$::jsonb;
  c jsonb; rl jsonb; v_pid int; v_rid int; i int:=0; j int; v_res jsonb:='[]'::jsonb; r1 jsonb; r2 jsonb; obs jsonb; v_ok boolean; v_status text;
  v_before bigint; v_after bigint; v_deterministic boolean:=true; v_readonly boolean; v_fail int; v_gap int; v_pass int; v_out jsonb;
begin
  begin
    insert into lf_ops.politicas_seguridad(security_policy_id,policy_code,category,description,enforcement_level,status) values
      (-9001,'ZZ-SELFTEST-P1','SELFTEST','selftest','REQUIRED','CANDIDATO'),
      (-9002,'ZZ-SELFTEST-P2','SELFTEST','selftest','REQUIRED','CANDIDATO'),
      (-9003,'ZZ-SELFTEST-P3','SELFTEST','selftest','REQUIRED','ARCHIVADO');
    select (select count(*) from programacion.t_remed_links)+(select count(*) from programacion.t_remed_change_log) into v_before;
    for c in select * from jsonb_array_elements(v_cases) loop
      i:=i+1;
      insert into lf_ops.pantallas(codigo,nombre) values ('ZZ-SELFTEST-S'||i,'selftest '||i) returning id into v_pid;
      j:=0;
      for rl in select * from jsonb_array_elements(c->'rules') loop
        j:=j+1;
        insert into lf_ops.reglas(codigo,categoria,titulo,descripcion,estado,pendiente_decision,valor_config)
          values ('ZZ-SELFTEST-R'||i||'-'||j,'SELFTEST','selftest','selftest','CANDIDATO',coalesce((rl->>'pend')::boolean,false),rl->'v')
          returning id into v_rid;
        insert into lf_ops.reglas_pantallas(regla_id,pantalla_id) values (v_rid,v_pid);
      end loop;
      r1:=programacion.fn_t_remed_reconcile_v3(v_pid);
      r2:=programacion.fn_t_remed_reconcile_v3(v_pid);
      if r1 is distinct from r2 then v_deterministic:=false; end if;
      select coalesce(jsonb_agg(jsonb_build_object('role',p->>'reference_role','target',(p->>'target_id')::bigint,'verdict',p->>'verdict')),'[]'::jsonb)
        into obs from jsonb_array_elements(r1->'proposals') p;
      v_ok := jsonb_array_length(obs)=jsonb_array_length(c->'expect') and obs @> (c->'expect') and (c->'expect') @> obs;
      v_status := case when not v_ok then 'FAIL' when (c->>'known_gap')::boolean then 'KNOWN_GAP' else 'PASS' end;
      v_res:=v_res||jsonb_build_array(jsonb_build_object('case',c->>'name','status',v_status,'expected',c->'expect','observed',obs));
    end loop;
    select (select count(*) from programacion.t_remed_links)+(select count(*) from programacion.t_remed_change_log) into v_after;
    v_readonly:=(v_before=v_after);
    select count(*) filter (where x->>'status'='FAIL'), count(*) filter (where x->>'status'='KNOWN_GAP'), count(*) filter (where x->>'status'='PASS')
      into v_fail,v_gap,v_pass from jsonb_array_elements(v_res) x;
    v_out:=jsonb_build_object('schema_version','LF_T_REMED_LAYER1_SELFTEST_V3',
      'invariants',jsonb_build_object('read_only',v_readonly,'deterministic',v_deterministic),
      'summary',jsonb_build_object('pass',v_pass,'known_gap',v_gap,'fail',v_fail),
      'verdict',case when v_fail=0 and v_readonly and v_deterministic then 'PASS' else 'FAIL' end,
      'cases',v_res);
    raise exception 'T_REMED_SELFTEST_ROLLBACK:%',v_out::text;
  exception when others then
    if sqlerrm like 'T_REMED_SELFTEST_ROLLBACK:%' then
      return substr(sqlerrm,length('T_REMED_SELFTEST_ROLLBACK:')+1)::jsonb;
    end if;
    raise;
  end;
end;
$fn$;
comment on function programacion.fn_t_remed_layer1_selftest_v3() is
  'T-REMED layer 1 invariant self-test. Isolated fixtures, always rolled back. Output: verdict, invariants (read_only, deterministic), per-case PASS|KNOWN_GAP|FAIL. KNOWN_GAP marks documented current limitations (partial, absent, duplicate-without-refs).';
revoke all on function programacion.fn_t_remed_layer1_selftest_v3() from public, anon, authenticated;
