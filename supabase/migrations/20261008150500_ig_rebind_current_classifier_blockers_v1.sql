-- IG rebinding parity repair. EKB: stale parent blocker payload crossed a 
-- current classifier boundary. Curator must not sign parent blockers with a
-- freshly computed classifier fingerprint. No validator/pass gate is bypassed.
--
-- The family-agnostic correction sources both the curator SHA input and the
-- immutable INSERT from the SAME current canonical classifier snapshot,
-- while the original parent data remains traceable through run lineage and
-- governed semantic_plan/resolver_result receipts.
do $rebind$
declare
 v_sig constant regprocedure := 'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure;
 v_def text;
 v_new text;
 v_old_hash constant text := '''blockers'',a.blockers';
 v_new_hash constant text := '''blockers'',coalesce(v_classifier->''blockers'',''[]''::jsonb)';
 v_old_insert constant text := 'a.rationale,a.blockers,a.negative_requirements';
 v_new_insert constant text := 'a.rationale,coalesce(v_classifier->''blockers'',''[]''::jsonb),a.negative_requirements';
begin
 v_def:=pg_get_functiondef(v_sig);
 if v_def is null or position('v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2' in v_def)=0
    or position(v_old_hash in v_def)=0 or position(v_old_insert in v_def)=0
    or (length(v_def)-length(replace(v_def,v_old_hash,'')))/length(v_old_hash)<>1
    or (length(v_def)-length(replace(v_def,v_old_insert,'')))/length(v_old_insert)<>1
 then raise exception 'IG_REBIND_CANONICAL_BLOCKERS_SOURCE_DRIFT';end if;
 v_new:=replace(replace(v_def,v_old_hash,v_new_hash),v_old_insert,v_new_insert);
 if v_new=v_def then raise exception 'IG_REBIND_BLOCKERS_REWRITE_NOT_APPLIED';end if;
 execute v_new;
end;
$rebind$;

do $verify$
declare v_def text;
begin
 v_def:=pg_get_functiondef(
  'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure
 );
 if position('''blockers'',coalesce(v_classifier->''blockers'',''[]''::jsonb)' in v_def)=0
    or position('a.rationale,coalesce(v_classifier->''blockers'',''[]''::jsonb),a.negative_requirements' in v_def)=0
    or position('''blockers'',a.blockers' in v_def)>0
    or position('a.rationale,a.blockers,a.negative_requirements' in v_def)>0
 then raise exception 'IG_REBIND_CANONICAL_BLOCKERS_READBACK_FAILED';end if;
 if (select count(*) from pg_trigger where tgrelid='programacion.input_family_assessments'::regclass
      and tgname='trg_input_family_assessment_00a_preinsert_composition' and tgenabled='O')<>1
    or (select count(*) from pg_trigger where tgrelid='programacion.input_family_assessments'::regclass
      and tgname='trg_input_family_assessment_update' and tgenabled='O')<>1
 then raise exception 'IG_REBIND_GOVERNED_COMPOSITION_OR_IMMUTABILITY_MISSING';end if;
end;
$verify$;
