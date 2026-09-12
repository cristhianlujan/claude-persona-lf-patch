-- INPUT_GOVERNANCE_AGENT L3B semantic benchmark
-- 5 real runs x 10 contract-grounded semantic checks = 50 cases.
-- Current positive runs: 212 ONB_002, 213 ONB_003, 214 ONB_004, 215 HOME_002.
-- Negative freshness/currentness run: 210 REC_001 (expected stale, but snapshot integrity must remain valid).
-- Read-only. No DML/DDL/canonicalization.

with runset(run_id, expected_current) as (
  values (212,true),(213,true),(214,true),(215,true),(210,false)
), contract as (
  select especificacion
  from programacion.contratos
  where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT'
    and estado='defined' and fail_closed
  limit 1
), reqs as (
  select key as family_code,value as req
  from contract
  cross join lateral jsonb_each(especificacion->'family_stage_requirements')
), base as (
  select rs.run_id,rs.expected_current,r.pantalla_id,p.codigo as screen_code,
         r.family_count,r.curator_identity,r.validator_identity,r.source_snapshot_sha256,
         programacion.fn_input_readiness_run_is_current_cached_v1(r.id) as actual_current,
         programacion.fn_input_freshness_delta(r.id) as freshness
  from runset rs
  join programacion.input_readiness_runs r on r.id=rs.run_id
  join lf_ops.pantallas p on p.id=r.pantalla_id
), canon as (
  select array_agg(x.value order by x.value) as families
  from lf_ops.reglas q
  cross join lateral jsonb_array_elements_text(q.valor_config->'families') x(value)
  where q.codigo='B2B-RULE-STORY-READINESS-001'
), stats as (
  select b.*,
    (select count(*) from programacion.input_family_assessments a where a.run_id=b.run_id) as assessed,
    (select array_agg(a.family_code order by a.family_code) from programacion.input_family_assessments a where a.run_id=b.run_id) as families,
    (select count(*) from programacion.input_family_assessments a where a.run_id=b.run_id and jsonb_array_length(coalesce(a.source_refs,'[]'::jsonb))=0) as missing_source_refs,
    (select count(*) from programacion.input_family_assessments a where a.run_id=b.run_id and (a.validator_outcome<>'PASS' or a.validator_identity is distinct from b.validator_identity or a.validator_identity=b.curator_identity)) as bad_validator_identity,
    (select count(*) from programacion.input_family_assessments a where a.run_id=b.run_id and (
       not (a.validator_evidence ? 'source_snapshot_sha256') or
       not (a.validator_evidence ? 'curator_sha256') or
       not (a.validator_evidence ? 'direct_source_readback') or
       not (a.validator_evidence ? 'execution_mode') or
       not (a.validator_evidence ? 'assertions') or
       a.validator_evidence->>'source_snapshot_sha256' is distinct from b.source_snapshot_sha256 or
       coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false) is not true or
       a.validator_evidence->>'execution_mode' is distinct from 'INDEPENDENT_VALIDATOR' or
       jsonb_typeof(a.validator_evidence->'assertions') is distinct from 'array' or
       jsonb_array_length(coalesce(a.validator_evidence->'assertions','[]'::jsonb))=0
    )) as bad_validator_evidence,
    (select count(*) from programacion.input_family_assessments a where a.run_id=b.run_id and (
       (a.applicability='APPLICABLE' and (a.coverage_status='NOT_APPLICABLE' or a.well_defined_status='NOT_APPLICABLE' or a.story_ready_status='NOT_APPLICABLE' or a.implementation_ready_status='NOT_APPLICABLE' or a.qa_ready_status='NOT_APPLICABLE' or a.production_ready_status='NOT_APPLICABLE')) or
       (a.applicability='NOT_APPLICABLE' and (a.coverage_status<>'NOT_APPLICABLE' or a.well_defined_status<>'NOT_APPLICABLE' or a.story_ready_status<>'NOT_APPLICABLE' or a.implementation_ready_status<>'NOT_APPLICABLE' or a.qa_ready_status<>'NOT_APPLICABLE' or a.production_ready_status<>'NOT_APPLICABLE')) or
       (a.applicability='UNRESOLVED' and a.story_ready_status='READY')
    )) as bad_applicability,
    (select count(*)
     from programacion.input_family_assessments a
     join reqs q on q.family_code=a.family_code
     where a.run_id=b.run_id and (
       (a.implementation_ready_status='READY' and a.story_ready_status<>'READY') or
       (a.qa_ready_status='READY' and a.implementation_ready_status<>'READY') or
       (a.production_ready_status='READY' and a.qa_ready_status<>'READY') or
       ((a.coverage_status<>'COMPLETE' or a.well_defined_status<>'COMPLETE') and a.story_ready_status='READY' and coalesce((q.req->>'allow_story_ready_when_incomplete')::boolean,false)=false) or
       ((a.coverage_status<>'COMPLETE' or a.well_defined_status<>'COMPLETE') and a.implementation_ready_status='READY' and coalesce((q.req->>'allow_implementation_ready_when_incomplete')::boolean,false)=false) or
       ((a.coverage_status<>'COMPLETE' or a.well_defined_status<>'COMPLETE') and a.qa_ready_status='READY' and coalesce((q.req->>'allow_qa_ready_when_incomplete')::boolean,false)=false) or
       ((a.coverage_status<>'COMPLETE' or a.well_defined_status<>'COMPLETE') and a.production_ready_status='READY' and coalesce((q.req->>'allow_production_ready_when_incomplete')::boolean,false)=false)
    )) as bad_hierarchy,
    (select count(*) from programacion.input_family_assessments a where a.run_id=b.run_id and (
       a.severity !~ '^P[0-4]$' or
       (a.applicability='APPLICABLE' and a.story_ready_status not in ('READY','NOT_APPLICABLE') and a.severity<>'P0')
    )) as bad_story_severity,
    (select count(*) from programacion.input_family_assessments a
     where a.run_id=b.run_id
       and a.family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS')
       and (
         not exists(select 1 from jsonb_array_elements(a.source_refs) j where j->>'kind'='EKB_DECISION_SET') or
         not exists(select 1 from jsonb_array_elements(a.source_refs) j where j->>'kind'='EKB_PREVENTION_SET') or
         exists(select 1 from jsonb_array_elements(a.source_refs) j where j->>'kind'='CONTRACT')
       )) as bad_governance_authority,
    (select count(*) from programacion.input_gap_proposals gp where gp.run_id=b.run_id and (
       gp.validator_outcome<>'PASS' or
       coalesce((gp.validator_evidence->>'proposal_is_canonical_source')::boolean,false)=true or
       gp.validator_evidence->>'automatic_canonicalization' is distinct from 'DENY' or
       jsonb_array_length(coalesce(gp.source_refs,'[]'::jsonb))=0
    )) as bad_proposals
  from base b
), cases as (
  select run_id,screen_code,'01_CURRENTNESS_FRESHNESS' case_family,
    (actual_current=expected_current and
      case when expected_current
        then freshness->>'run_state'='CURRENT' and coalesce((freshness#>>'{summary,changed_source_count}')::int,-1)=0
        else freshness->>'run_state'='STALE' and coalesce((freshness#>>'{summary,changed_source_count}')::int,0)>0
      end) as pass
  from stats
  union all select run_id,screen_code,'02_FAMILY_UNIVERSE_EXACT', assessed=family_count and families=(select families from canon) from stats
  union all select run_id,screen_code,'03_SOURCE_REFS_REQUIRED', missing_source_refs=0 from stats
  union all select run_id,screen_code,'04_VALIDATOR_INDEPENDENCE', validator_identity is distinct from curator_identity and bad_validator_identity=0 from stats
  union all select run_id,screen_code,'05_VALIDATOR_EVIDENCE_BOUND', bad_validator_evidence=0 from stats
  union all select run_id,screen_code,'06_APPLICABILITY_STATUS_INVARIANTS', bad_applicability=0 from stats
  union all select run_id,screen_code,'07_READINESS_STAGE_POLICY', bad_hierarchy=0 from stats
  union all select run_id,screen_code,'08_STORY_OPEN_SEVERITY', bad_story_severity=0 from stats
  union all select run_id,screen_code,'09_GOVERNANCE_AUTHORITY_SOURCE', bad_governance_authority=0 from stats
  union all select run_id,screen_code,'10_PROPOSAL_CANON_SEPARATION', bad_proposals=0 from stats
)
select count(*) as total_cases,
       count(*) filter(where pass) as passed,
       count(*) filter(where not pass) as failed,
       coalesce(jsonb_agg(jsonb_build_object('run_id',run_id,'screen',screen_code,'family',case_family) order by run_id,case_family) filter(where not pass),'[]'::jsonb) as failures
from cases;
