-- T-REMED layer 1: single test entry. Known cases first (fixed anchors), then the seeded generated relations.
-- Thin caller: owns no test logic. Combined verdict = PASS only if both pass. KNOWN_GAP cases do not fail the verdict.
create or replace function programacion.fn_t_remed_layer1_test_v3(p_seed integer default 20261009, p_runs integer default 100)
 returns jsonb
 language plpgsql security definer set search_path to 'pg_catalog','programacion'
as $fn$
declare f jsonb; g jsonb;
begin
  f:=programacion.fn_t_remed_layer1_selftest_v3();
  g:=programacion.fn_t_remed_layer1_property_test_v3(p_seed,p_runs);
  return jsonb_build_object('schema_version','LF_T_REMED_LAYER1_TEST_V3',
    'order',jsonb_build_array('KNOWN_CASES','GENERATED_RELATIONS'),
    'known_cases',jsonb_build_object('verdict',f->>'verdict','summary',f->'summary','invariants',f->'invariants'),
    'generated',jsonb_build_object('verdict',g->>'verdict','seed',g->'seed','runs',g->'runs',
      'failed',(select jsonb_object_agg(k,v->'failed') from jsonb_each(g->'relations') x(k,v)),
      'examples',(select coalesce(jsonb_agg(jsonb_build_object('relation',k,'example',v->'examples'->0)) filter (where jsonb_array_length(v->'examples')>0),'[]'::jsonb) from jsonb_each(g->'relations') x(k,v))),
    'verdict',case when f->>'verdict'='PASS' and g->>'verdict'='PASS' then 'PASS' else 'FAIL' end);
end;
$fn$;
comment on function programacion.fn_t_remed_layer1_test_v3(integer,integer) is
  'T-REMED layer 1 single test entry: runs fn_t_remed_layer1_selftest_v3 (known cases) then fn_t_remed_layer1_property_test_v3 (generated relations). Thin caller. Verdict PASS only if both PASS; KNOWN_GAP does not fail.';
revoke all on function programacion.fn_t_remed_layer1_test_v3(integer,integer) from public, anon, authenticated;
