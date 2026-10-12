-- T-REMED layer 1 (reconcile): generated metamorphic/property test (prototype).
-- Instead of fixed expected outputs, a seeded generator builds random rule sets and checks relations that must always hold:
--   R1 permutation invariance : the order of the rules does not change the proposals.
--   R2 duplicate tolerance    : adding an exact copy of an existing rule does not change the proposals.
--   R3 no silent upgrade      : adding any rule never turns a non-LINK_CANDIDATE verdict into LINK_CANDIDATE.
--   R4 determinism            : two reconcile calls on the same input return the same result.
-- Everything runs in a sub-transaction that is ALWAYS rolled back. The seed is returned so any failure is reproducible.

create or replace function programacion.fn_t_remed_pt_make_v3(p_tag text, p_rules jsonb)
 returns integer
 language plpgsql security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare v_pid int; v_rid int; r record;
begin
  insert into lf_ops.pantallas(codigo,nombre) values ('ZZ-PT-'||p_tag,'pt '||p_tag) returning id into v_pid;
  for r in select value v, ordinality o from jsonb_array_elements(p_rules) with ordinality loop
    insert into lf_ops.reglas(codigo,categoria,titulo,descripcion,estado,pendiente_decision,valor_config)
      values ('ZZ-PT-'||p_tag||'-'||r.o,'SELFTEST','pt','pt',coalesce(r.v->>'estado','CANDIDATO'),coalesce((r.v->>'pend')::boolean,false),r.v->'v')
      returning id into v_rid;
    insert into lf_ops.reglas_pantallas(regla_id,pantalla_id) values (v_rid,v_pid);
  end loop;
  return v_pid;
end;
$fn$;

create or replace function programacion.fn_t_remed_layer1_property_test_v3(p_seed integer default 20261009, p_runs integer default 200)
 returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare
  v_keys text[] := array['factor_security_policy_id','factor_security_policy_id','factor_security_policy_id','abuse_security_policy_id','abuse_security_policy_id',
                         'security_policy_id','security_policy_id','zzz_nofamily_policy_id','max_attempts','__EMPTY__'];
  v_vals jsonb[] := array['900001','900002','900003','900999','null','"abc"']::jsonb[];
  v_run int; n int; k int; key text; val jsonb; rules jsonb; rule jsonb; extra jsonb; rules_rev jsonb; rules_dup jsonb; rules_ext jsonb;
  p0 int; p1 int; p2 int; p3 int; base jsonb; o1 jsonb; o2 jsonb; o3 jsonb; r_a jsonb; r_b jsonb;
  f1 jsonb:='[]'; f2 jsonb:='[]'; f3 jsonb:='[]'; f4 jsonb:='[]'; c1 int:=0; c2 int:=0; c3 int:=0; c4 int:=0;
  v_before bigint; v_after bigint; v_out jsonb; v_tag text;
  function_norm text := $q$select coalesce(jsonb_agg(jsonb_build_object('role',p->>'reference_role','target',p->>'target_id','verdict',p->>'verdict','states',p->'rule_states')
      order by p->>'reference_role',(p->>'target_id')::bigint),'[]'::jsonb) from jsonb_array_elements($1->'proposals') p$q$;
begin
  begin
    perform setseed((p_seed % 1000000)::float8/1000000.0);
    insert into lf_ops.politicas_seguridad(security_policy_id,policy_code,category,description,enforcement_level,status) values
      (900001,'ZZ-PT-P1','SELFTEST','pt','REQUIRED','CANDIDATO'),
      (900002,'ZZ-PT-P2','SELFTEST','pt','REQUIRED','CANDIDATO'),
      (900003,'ZZ-PT-P3','SELFTEST','pt','REQUIRED','ARCHIVADO');
    select (select count(*) from programacion.t_remed_links)+(select count(*) from programacion.t_remed_change_log) into v_before;
    for v_run in 1..p_runs loop
      v_tag:=v_run::text;
      n:=1+floor(random()*5)::int; rules:='[]'::jsonb;
      for k in 1..n loop
        key:=v_keys[1+floor(random()*array_length(v_keys,1))::int];
        val:=v_vals[1+floor(random()*array_length(v_vals,1))::int];
        rule:=jsonb_build_object('v',case key when '__EMPTY__' then '{}'::jsonb when 'max_attempts' then jsonb_build_object(key,5) else jsonb_build_object(key,val) end,
                                 'pend',random()<0.12,'estado',case when random()<0.2 then 'VIGENTE' else 'CANDIDATO' end);
        rules:=rules||jsonb_build_array(rule);
      end loop;
      -- relation inputs
      select coalesce(jsonb_agg(x order by o desc),'[]'::jsonb) into rules_rev from jsonb_array_elements(rules) with ordinality t(x,o);
      rules_dup:=rules||jsonb_build_array(rules->(floor(random()*n)::int));
      extra:=jsonb_build_object('v',case when random()<0.5 then jsonb_build_object('factor_security_policy_id',v_vals[1+floor(random()*3)::int])
                                         else jsonb_build_object('security_policy_id',v_vals[1+floor(random()*3)::int]) end,
                               'pend',random()<0.2,'estado','CANDIDATO');
      rules_ext:=rules||jsonb_build_array(extra);
      p0:=programacion.fn_t_remed_pt_make_v3(v_tag||'a',rules);
      p1:=programacion.fn_t_remed_pt_make_v3(v_tag||'b',rules_rev);
      p2:=programacion.fn_t_remed_pt_make_v3(v_tag||'c',rules_dup);
      p3:=programacion.fn_t_remed_pt_make_v3(v_tag||'d',rules_ext);
      r_a:=programacion.fn_t_remed_reconcile_v3(p0);
      r_b:=programacion.fn_t_remed_reconcile_v3(p0);
      execute function_norm into base using r_a;
      execute function_norm into o1 using programacion.fn_t_remed_reconcile_v3(p1);
      execute function_norm into o2 using programacion.fn_t_remed_reconcile_v3(p2);
      execute function_norm into o3 using programacion.fn_t_remed_reconcile_v3(p3);
      -- R4
      c4:=c4+1; if r_a is distinct from r_b then f4:=f4||jsonb_build_array(jsonb_build_object('run',v_run,'rules',rules)); end if;
      -- R1
      c1:=c1+1; if base is distinct from o1 then f1:=f1||jsonb_build_array(jsonb_build_object('run',v_run,'rules',rules,'base',base,'reversed',o1)); end if;
      -- R2
      c2:=c2+1; if base is distinct from o2 then f2:=f2||jsonb_build_array(jsonb_build_object('run',v_run,'rules',rules,'base',base,'with_duplicate',o2)); end if;
      -- R3
      c3:=c3+1;
      if exists(select 1 from jsonb_array_elements(base) b join jsonb_array_elements(o3) e
                  on b->>'role'=e->>'role' and b->>'target'=e->>'target'
                where b->>'verdict'<>'LINK_CANDIDATE' and e->>'verdict'='LINK_CANDIDATE') then
        f3:=f3||jsonb_build_array(jsonb_build_object('run',v_run,'rules',rules,'added',extra,'base',base,'extended',o3));
      end if;
    end loop;
    select (select count(*) from programacion.t_remed_links)+(select count(*) from programacion.t_remed_change_log) into v_after;
    v_out:=jsonb_build_object('schema_version','LF_T_REMED_LAYER1_PROPERTY_TEST_V3','seed',p_seed,'runs',p_runs,'read_only',(v_before=v_after),
      'relations',jsonb_build_object(
        'R1_permutation_invariance',jsonb_build_object('checked',c1,'failed',jsonb_array_length(f1),'examples',(select coalesce(jsonb_agg(e),'[]'::jsonb) from (select e from jsonb_array_elements(f1) e limit 3) q)),
        'R2_duplicate_tolerance',jsonb_build_object('checked',c2,'failed',jsonb_array_length(f2),'examples',(select coalesce(jsonb_agg(e),'[]'::jsonb) from (select e from jsonb_array_elements(f2) e limit 3) q)),
        'R3_no_silent_upgrade',jsonb_build_object('checked',c3,'failed',jsonb_array_length(f3),'examples',(select coalesce(jsonb_agg(e),'[]'::jsonb) from (select e from jsonb_array_elements(f3) e limit 3) q)),
        'R4_determinism',jsonb_build_object('checked',c4,'failed',jsonb_array_length(f4),'examples',(select coalesce(jsonb_agg(e),'[]'::jsonb) from (select e from jsonb_array_elements(f4) e limit 3) q))),
      'verdict',case when jsonb_array_length(f1)+jsonb_array_length(f2)+jsonb_array_length(f3)+jsonb_array_length(f4)=0 and v_before=v_after then 'PASS' else 'FAIL' end);
    raise exception 'T_REMED_PT_ROLLBACK:%',v_out::text;
  exception when others then
    if sqlerrm like 'T_REMED_PT_ROLLBACK:%' then
      return substr(sqlerrm,length('T_REMED_PT_ROLLBACK:')+1)::jsonb;
    end if;
    raise;
  end;
end;
$fn$;
comment on function programacion.fn_t_remed_layer1_property_test_v3(integer,integer) is
  'T-REMED layer 1 generated property test. Inputs: seed (reproducible), runs. Relations: R1 permutation invariance, R2 duplicate tolerance, R3 no silent upgrade to LINK_CANDIDATE, R4 determinism. Always rolled back; failures include the generated rules.';
revoke all on function programacion.fn_t_remed_pt_make_v3(text,jsonb), programacion.fn_t_remed_layer1_property_test_v3(integer,integer) from public, anon, authenticated;
