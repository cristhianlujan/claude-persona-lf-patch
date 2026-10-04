-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M9.1 / PAULO-149
-- Transversal repair: stale successor runs must use the canonical source-stale
-- recuration path instead of preserving inherited classifier/source fingerprints.
-- No screen ids are hardcoded. Validator/currentness semantics are not relaxed.

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
    null; -- idempotent readback/replay
  elsif position(v_old in v_def) = 0 then
    raise exception 'M9_1_TRANSVERSAL_STALE_ROUTE_SOURCE_DRIFT';
  else
    v_def := replace(v_def,v_old,v_new);
    execute v_def;
  end if;
end
$patch$;

comment on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) is
  'M9.1: stale governed successors are routed through canonical source-stale recuration; non-stale successors retain normal rebind semantics.';

do $verify$
declare
  v_def text := pg_get_functiondef('programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure);
  v_compact text := replace(lower(v_def),' ','');
begin
  if position($$'runtime_assertion_rebind_safe_successor_v1'$$ in lower(v_def))=0 then
    raise exception 'M9_1_TRANSVERSAL_STALE_ROUTE_POSTCONDITION_MISSING';
  end if;

  if position('fn_input_freshness_delta' in v_def)=0
     or position('fn_input_governance_recurate_source_stale_v1' in v_def)=0
     or position('v_changed_sources>0' in v_compact)=0
     or position('ifv_affected_families=0then' in v_compact)=0
     or position('notv_successor_required' in v_compact)=0
     or position('v_resolution_errors=0' in v_compact)=0 then
    raise exception 'M9_1_TRANSVERSAL_STALE_ROUTE_GUARDS_REGRESSED';
  end if;
end
$verify$;

commit;
