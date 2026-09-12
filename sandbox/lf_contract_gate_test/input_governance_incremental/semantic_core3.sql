-- INPUT_GOVERNANCE_AGENT authoritative semantic CORE 3.
-- Read-only. No DDL/DML/canonicalization.

with c1 as (
  select programacion.fn_input_readiness_run_is_current_cached_v1(212) as is_current,
         programacion.fn_input_freshness_delta(212) as fresh,
         programacion.fn_input_stage_gate_summary_known_current_v1(212,true) as gate,
         (select count(*)
          from programacion.input_family_assessments
          where run_id=212
            and family_code in ('APPLICABILITY_READINESS','SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE')
            and validator_outcome='PASS'
            and story_ready_status='READY') as selected_ready
), c2 as (
  select programacion.fn_input_readiness_run_is_current_cached_v1(210) as is_current,
         programacion.fn_input_freshness_delta(210) as fresh
), c3 as (
  select r.curator_identity,r.validator_identity,
         (select count(*)
          from programacion.input_family_assessments a
          where a.run_id=215
            and a.family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS')
            and exists(select 1 from jsonb_array_elements(a.source_refs) j where j->>'kind'='EKB_DECISION_SET')
            and exists(select 1 from jsonb_array_elements(a.source_refs) j where j->>'kind'='EKB_PREVENTION_SET')
            and not exists(select 1 from jsonb_array_elements(a.source_refs) j where j->>'kind'='CONTRACT')) as authority_ok,
         (select count(*)
          from programacion.input_gap_proposals gp
          where gp.run_id=215
            and gp.validator_outcome='PASS'
            and coalesce((gp.validator_evidence->>'proposal_is_canonical_source')::boolean,false)=false
            and gp.validator_evidence->>'automatic_canonicalization'='DENY') as proposal_safe,
         (select count(*) from programacion.input_gap_proposals gp where gp.run_id=215) as proposal_total
  from programacion.input_readiness_runs r
  where r.id=215
), cases as (
  select 'CORE1_CURRENT_ADVISORY_FAIL_CLOSED' id,
         (c1.is_current=true
          and c1.fresh->>'run_state'='CURRENT'
          and (c1.fresh#>>'{summary,changed_source_count}')::int=0
          and c1.selected_ready=5
          and coalesce((c1.gate->>'canonical_story_gate_pass')::boolean,false)=false) pass
  from c1
  union all
  select 'CORE2_STALE_REJECTED',
         (c2.is_current=false
          and c2.fresh->>'run_state'='STALE'
          and (c2.fresh#>>'{summary,changed_source_count}')::int>0)
  from c2
  union all
  select 'CORE3_AUTHORITY_PROPOSAL_SEPARATION',
         (c3.curator_identity is distinct from c3.validator_identity
          and c3.authority_ok=5
          and c3.proposal_safe=c3.proposal_total)
  from c3
)
select count(*) total,
       count(*) filter(where pass) passed,
       count(*) filter(where not pass) failed,
       jsonb_agg(jsonb_build_object('id',id,'pass',pass) order by id) results
from cases;
