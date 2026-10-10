-- D1 qualification probe on an already refreshed managed DB/registries snapshot.
-- If run before refresh, BLOCKED is correct. This SQL cannot promote assets.
WITH cases(code,snapshot_ref,expected_decision) AS (
 VALUES ('CURRENT',NULL::text,'MANAGED_METADATA_TECHNICALLY_READY'),
        ('OUTDATED','__STALE_SNAPSHOT_NOT_CURRENT__','BLOCK_EXPECTED_SNAPSHOT_MISMATCH')
), evidence AS (
 SELECT code,expected_decision,
  private.fn_lf_d1_managed_inventory_qualification_v1(snapshot_ref) AS assessment
 FROM cases
)
SELECT code,expected_decision,assessment->>'decision' AS observed_decision,
 assessment->>'technical_readiness' AS technical_readiness,
 assessment->>'snapshot_code' AS snapshot_ref,
 assessment->>'indexed_objects' AS objects,
 assessment->>'active_dependencies' AS relations,
 assessment->>'catalog_drift' AS drift,
 CASE WHEN assessment->>'decision'=expected_decision
 AND (assessment->>'inventory_governance_admitted')='false'
 AND (assessment->>'external_repo_and_edge_qualified')='false'
 AND (assessment->>'business_data_read_authorized')='false'
 AND (assessment->>'runtime_cutover_authorized')='false'
 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM evidence ORDER BY code;