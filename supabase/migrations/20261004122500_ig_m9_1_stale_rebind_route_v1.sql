-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M9.1 / PAULO-149
-- PREVALIDATION_SANITATION_V1 shared-root repair.
-- A stale 5.13 run produced by RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1
-- must use the canonical source-stale recuration path, not another rebind that
-- preserves an obsolete bootstrap classifier fingerprint.
-- R16 Git-first. R17/N-9 required before apply.

begin;

do $patch$
declare
  v_reg regprocedure := 'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure;
  v_def text;
  v_old text := $$and coalesce(v_scope->>'mode','') in ('GOVERNED_CANONICAL_BOOTSTRAP_V1','RUNTIME_GOVERNED_RECURATION_V2') then$$;
  v_new text := $$and coalesce(v_scope->>'mode','') in ('GOVERNED_CANONICAL_BOOTSTRAP_V1','RUNTIME_GOVERNED_RECURATION_V2','RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1') then$$;
begin
  v_def := pg_get_functiondef(v_reg);
  if position(v_new in v_def) > 0 then
    raise exception 'M9_1_STALE_REBIND_ROUTE_ALREADY_APPLIED';
  end if;
  if position(v_old in v_def) = 0 then
    raise exception 'M9_1_STALE_REBIND_ROUTE_SOURCE_DRIFT';
  end if;

  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$patch$;

comment on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) is
  'M9.1: stale successors created by governed rebind are re-read through the canonical source-stale recuration path; current/no-source-change rebind semantics remain unchanged.';

do $verify$
declare
  v_def text := pg_get_functiondef('programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure);
begin
  if position($$'RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1'$$ in v_def)=0 then
    raise exception 'M9_1_STALE_REBIND_ROUTE_POSTCONDITION_MISSING';
  end if;
  if position('fn_input_governance_recurate_source_stale_v1' in v_def)=0
     or position('fn_input_freshness_delta' in v_def)=0
     or position('fn_input_readiness_run_is_current_cached_v1' in v_def)=0 then
    raise exception 'M9_1_STALE_REBIND_ROUTE_GUARDS_REGRESSED';
  end if;
end
$verify$;

commit;
