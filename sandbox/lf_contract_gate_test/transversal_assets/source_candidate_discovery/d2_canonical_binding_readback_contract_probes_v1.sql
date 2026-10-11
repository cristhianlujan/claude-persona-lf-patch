-- Development-only D2 contract probes. No row SELECT from business tables.
-- Run under service_role with the D2 function installed; fixtures are references.
WITH fixtures(case_code,source_ref,expected) AS (VALUES
 ('INVALID_REF','supabase://catalog/lf_ops/cargas_lotes','BLOCK_CANONICAL_REF_INVALID'),
 ('ABSENT_SOURCE','db://lf_ops.absent_table_for_probe','BLOCK_INVENTORY_SOURCE_NOT_UNIQUE_CURRENT'),
 ('EXISTING_UNBOUND_SOURCE','db://lf_ops.cargas_lotes','BLOCK_BINDING_ABSENT_OR_AMBIGUOUS'),
 ('OTHER_UNBOUND_SOURCE','db://lf_ops.v_b2b_backoffice_login_contract','BLOCK_BINDING_ABSENT_OR_AMBIGUOUS')
), executed AS (
 SELECT case_code,expected,private.fn_lf_d2_binding_readback_v1(source_ref) AS outcome
 FROM fixtures
)
SELECT case_code,expected,outcome->>'decision' AS observed,
 CASE WHEN outcome->>'decision'=expected
       AND outcome->>'business_data_read_authorized'='false'
       AND outcome->>'rows_accessed'='false'
       AND outcome->>'global_discovery_exhausted'='false'
       AND outcome->>'effects_executed'='false'
 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM executed ORDER BY case_code;