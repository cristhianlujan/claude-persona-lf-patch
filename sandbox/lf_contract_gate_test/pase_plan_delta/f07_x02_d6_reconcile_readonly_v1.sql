-- F07-X02 D6: read-only source-backed dependency projection (not an apply script).
-- Governance: lf_eventos #20574 (D5), #20583 (D6), issue #2056.
-- No DELETE, UPDATE, INSERT, DDL, extension, deployment, or PR check mutation.
-- All targeted debt identities derive from D6's declared_debt, not from a
-- maintained exception list or an unscoped R% prefix.
WITH
d6 AS (
  SELECT e.payload, e.entidad_codigo, e.evento_tipo
  FROM public.lf_eventos AS e
  WHERE e.id = 20583
    AND e.entidad_codigo = 'PASE-ATOM-F07-X02'
),
debt AS (
  SELECT 'PASE-ATOM-F07-X02-' || d.value AS work_code
  FROM d6
  CROSS JOIN LATERAL jsonb_array_elements_text(d6.payload->'declared_debt') AS d(value)
),
existing AS (
  SELECT dep.work_code AS predecessor, dep.status AS predecessor_status
  FROM programacion.engineering_work_items AS w
  JOIN programacion.engineering_work_dependencies AS e
    ON e.work_item_id = w.id AND e.relation_type = 'REQUIRES'
  JOIN programacion.engineering_work_items AS dep
    ON dep.id = e.depends_on_work_item_id
  WHERE w.work_code = 'PASE-ATOM-F07-X02'
),
projection AS (
  SELECT predecessor, predecessor_status,
         predecessor IN (SELECT work_code FROM debt) AS becomes_nonblocking_debt
  FROM existing
),
summary AS (
  SELECT
    (SELECT count(*) FROM d6) AS d6_exists,
    (SELECT count(*) FROM debt) AS debt_items,
    (SELECT count(*) FROM existing) AS existing_hard_edges,
    (SELECT count(*) FROM projection WHERE becomes_nonblocking_debt) AS candidate_debt_edge_removals,
    (SELECT count(*) FROM projection WHERE NOT becomes_nonblocking_debt) AS retained_hard_edges,
    (SELECT count(*) FROM projection WHERE predecessor = 'PASE-ATOM-F07-X02-R01'
       AND NOT becomes_nonblocking_debt) AS required_r01_retained,
    (SELECT count(*) FROM debt WHERE work_code NOT IN (SELECT predecessor FROM existing))
      AS debt_items_already_not_required,
    (SELECT coalesce((payload->>'r01_required')::boolean, false) FROM d6) AS d6_r01_required,
    (SELECT coalesce((payload->>'debt_outside_global07_critical_path')::boolean,false) FROM d6) AS d6_debt_outside_global07,
    (SELECT payload->>'migration_source_parity_pass_prerequisite' FROM d6) AS d6_parity_moved_to,
    (SELECT coalesce((payload->>'no_repairs_now')::boolean,false) FROM d6) AS d6_do_not_repair_debt
),
assertions AS (
  SELECT
    d6_exists = 1 AND debt_items = 4
      AND d6_r01_required AND d6_debt_outside_global07
      AND d6_do_not_repair_debt
      AND d6_parity_moved_to = 'PASE-ATOM-F09-X16'
      AS d6_authority_scope_valid,
    existing_hard_edges = 4
      AND candidate_debt_edge_removals = 3
      AND retained_hard_edges = 1
      AND required_r01_retained = 1
      AND debt_items_already_not_required = 1
      AS exact_edge_projection_valid,
    required_r01_retained = 1 AS required_r01_preserved,
    -- Negative fixture: a candidate that also removed R01 MUST be rejected.
    (required_r01_retained = 0) = false AS negative_r01_removal_rejected
  FROM summary
)
SELECT 'F07_X02_D6_PLAN_PROJECTION_READ_ONLY_V1' AS test_suite,
       d6_authority_scope_valid, exact_edge_projection_valid,
       required_r01_preserved, negative_r01_removal_rejected,
       d6_authority_scope_valid AND exact_edge_projection_valid
       AND required_r01_preserved AND negative_r01_removal_rejected
       AS candidate_safe_to_request_authorization,
       'NO_EFFECT_PROPOSED_ONLY; GOVERNED_PLAN_DELTA_REQUIRED' AS disposition
FROM assertions;
