-- F09-X17 qualification harness. Read-only; uses existing canonical procedures.
-- It DOES NOT create F09-X17, evaluate real producer/receiver receipts, issue
-- an authority decision, activate PASE, or close F09-016.
WITH
mapped_edges AS (
  SELECT jsonb_build_object('from',pu.unit_code,'to',dep.unit_code) AS edge
  FROM programacion.engineering_plan_units pu
  JOIN programacion.engineering_work_dependencies d
    ON d.work_item_id=pu.work_item_id AND d.relation_type='REQUIRES'
  JOIN programacion.engineering_plan_units dep
    ON dep.work_item_id=d.depends_on_work_item_id
    AND dep.plan_code=pu.plan_code AND dep.disposition='ASSIGNED'
  WHERE pu.plan_code='LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1'
    AND pu.disposition='ASSIGNED'
),
proposed_edges AS (
  SELECT jsonb_build_object('from','PASE-ATOM-F09-X17','to',required_unit) AS edge
  FROM (VALUES ('PASE-ATOM-F07-X01'),('PASE-ATOM-F07-X02'),
               ('PASE-ATOM-F07-X03'),('PASE-ATOM-F09-015')) v(required_unit)
  UNION ALL
  SELECT jsonb_build_object('from','PASE-ATOM-F09-016','to','PASE-ATOM-F09-X17')
),
positive_dag AS (
  SELECT programacion.fn_programming_dag_validate_edges_v1(
    (SELECT jsonb_agg(edge) FROM
      (SELECT edge FROM mapped_edges UNION ALL SELECT edge FROM proposed_edges) a)
  ) AS receipt
),
negative_dag AS (
  SELECT programacion.fn_programming_dag_validate_edges_v1(
    (SELECT jsonb_agg(edge) FROM (
      SELECT edge FROM mapped_edges UNION ALL SELECT edge FROM proposed_edges
      UNION ALL SELECT jsonb_build_object('from','PASE-ATOM-F09-015',
                                         'to','PASE-ATOM-F09-X17') AS edge
    ) a)
  ) AS receipt
),
consumer_cases AS (
  SELECT *
  FROM (VALUES
    ('POS_REQUIRED_PASS_OPTIONAL_HOLD',
      '[{"requiredness":"REQUIRED","state":"PASS"},{"requiredness":"OPTIONAL","state":"HOLD"}]'::jsonb, '{}'::jsonb,'PASS'),
    ('NEG_REQUIRED_UNKNOWN',
      '[{"requiredness":"REQUIRED","state":"UNKNOWN"}]'::jsonb, '{}'::jsonb,'BLOCK'),
    ('NEG_REQUIRED_HOLD',
      '[{"requiredness":"REQUIRED","state":"HOLD"}]'::jsonb, '{}'::jsonb,'HOLD'),
    ('NEG_OPTIONAL_VETO_WITHOUT_POLICY_PROOF',
      '[{"requiredness":"REQUIRED","state":"PASS"},{"requiredness":"OPTIONAL","state":"HOLD"}]'::jsonb, '{"optional_nonpass_veto":true}'::jsonb,'BLOCK')
  ) AS c(case_code,results,policy,expected)
),
consumer_results AS (
  SELECT case_code,expected,
    public.lf_consumer_admission_aggregate_v1(results,policy)->>'state' AS actual
  FROM consumer_cases
),
consumer_contradiction AS (
  SELECT public.lf_consumer_admission_evaluate_v1(
    '{"consumer_ref":"PASE_F09_X17_TEST","applicability":"NOT_APPLICABLE","requiredness":"REQUIRED"}'::jsonb
  ) AS receipt
),
unauthorized_snapshot AS (
  SELECT public.fn_lf_plan_delta_authority_readback_v1(
    20583, 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1',
    repeat('a',64),repeat('b',64)
  ) AS receipt
)
SELECT
  'PASE_F09_X17_READONLY_PROCEDURE_QUALIFICATION_V1' AS test_suite,
  (SELECT count(*) FROM mapped_edges) AS baseline_mapped_edges,
  (SELECT count(*) FROM proposed_edges) AS candidate_edges,
  (SELECT receipt->>'reason' FROM positive_dag) AS positive_dag_result,
  (SELECT receipt->>'reason' FROM negative_dag) AS negative_dag_result,
  (SELECT bool_and(actual=expected) FROM consumer_results)
    AS consumer_aggregate_four_cases_pass,
  (SELECT receipt->>'state' FROM consumer_contradiction)='UNKNOWN'
    AND (SELECT receipt->>'code' FROM consumer_contradiction)
      ='APPLICABILITY_REQUIREDNESS_CONTRADICTION'
    AS contradictory_required_consumer_rejected,
  (SELECT receipt->>'decision' FROM unauthorized_snapshot)
    ='PLAN_DELTA_NOT_AUTHORIZED'
    AND (SELECT receipt->>'reason' FROM unauthorized_snapshot)
      ='AUTHORIZATION_EVENT_TYPE_MISMATCH'
    AS snapshot_cannot_authorize_plan_delta,
  (SELECT count(*) FROM programacion.engineering_plan_units
    WHERE plan_code='LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1'
    AND unit_code='PASE-ATOM-F09-X17')=0
    AS candidate_not_materialized,
  ((SELECT receipt->>'reason' FROM positive_dag)='DAG_VALID'
   AND (SELECT receipt->>'reason' FROM negative_dag)='CIRCULAR_DEPENDENCY'
   AND (SELECT bool_and(actual=expected) FROM consumer_results)
   AND (SELECT receipt->>'state' FROM consumer_contradiction)='UNKNOWN'
   AND (SELECT receipt->>'decision' FROM unauthorized_snapshot)
       ='PLAN_DELTA_NOT_AUTHORIZED')
    AS reusable_procedures_qualified_readonly,
  'PROCEDURE_ONLY; NO_F09_X17_E2E_VERDICT; NO_PLAN_WRITE' AS disposition;
