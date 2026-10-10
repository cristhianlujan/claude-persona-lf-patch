-- LF D1/D2 admission matrix: SYNTHETIC READONLY (no operational rows).
-- Validates necessary AND conditions and DENY precedence only.
-- This is NOT a production permission evaluator or a permit receipt.
-- Permission statuses are observed from LF: CANDIDATO or VIGENTE.
-- Source binding must come from canonical Supabase assets/step contracts.
WITH fixture (
 case_code,actor_verified,user_status,assignment_status,
 actor_company_matches,binding_status,source_authority_status,
 permission_status,company_permission_status,access_effect,
 explicit_deny,read_route_verified,expected_decision
) AS (VALUES
 ('ALLOW_VALID',true,'ACTIVE','VIGENTE',true,'VIGENTE','VIGENTE','VIGENTE','VIGENTE','ALLOW',false,true,'ALLOW_ADMISSION_CANDIDATE'),
 ('NO_ACTOR',false,'ACTIVE','VIGENTE',true,'VIGENTE','VIGENTE','VIGENTE','VIGENTE','ALLOW',false,true,'DENY_NO_ACTOR'),
 ('CROSS_TENANT',true,'ACTIVE','VIGENTE',false,'VIGENTE','VIGENTE','VIGENTE','VIGENTE','ALLOW',false,true,'DENY_TENANT'),
 ('MISSING_BINDING',true,'ACTIVE','VIGENTE',true,'ABSENT','VIGENTE','VIGENTE','VIGENTE','ALLOW',false,true,'DENY_SOURCE_BINDING'),
 ('SOURCE_NOT_VIGENTE',true,'ACTIVE','VIGENTE',true,'VIGENTE','CANDIDATO','VIGENTE','VIGENTE','ALLOW',false,true,'DENY_SOURCE_AUTHORITY'),
 ('PERMISSION_CANDIDATE',true,'ACTIVE','VIGENTE',true,'VIGENTE','VIGENTE','CANDIDATO','VIGENTE','ALLOW',false,true,'DENY_PERMISSION_INACTIVE'),
 ('ASSIGNMENT_CANDIDATE',true,'ACTIVE','CANDIDATO',true,'VIGENTE','VIGENTE','VIGENTE','VIGENTE','ALLOW',false,true,'DENY_COMPANY_ASSIGNMENT'),
 ('PERMISSION_EXPLICIT_DENY',true,'ACTIVE','VIGENTE',true,'VIGENTE','VIGENTE','VIGENTE','VIGENTE','DENY',true,true,'DENY_PERMISSION_EFFECT'),
 ('DENY_OVER_ALLOW',true,'ACTIVE','VIGENTE',true,'VIGENTE','VIGENTE','VIGENTE','VIGENTE','ALLOW',true,true,'DENY_PERMISSION_EFFECT'),
 ('USER_INACTIVE',true,'INACTIVE','VIGENTE',true,'VIGENTE','VIGENTE','VIGENTE','VIGENTE','ALLOW',false,true,'DENY_USER_INACTIVE'),
 ('NO_READ_ROUTE',true,'ACTIVE','VIGENTE',true,'VIGENTE','VIGENTE','VIGENTE','VIGENTE','ALLOW',false,false,'DENY_READ_ROUTE'),
 ('PERMISSION_NOT_ASSIGNED',true,'ACTIVE','VIGENTE',true,'VIGENTE','VIGENTE','VIGENTE','ABSENT','ALLOW',false,true,'DENY_COMPANY_PERMISSION')
), decisions AS (
 SELECT case_code,expected_decision,
 CASE WHEN NOT actor_verified THEN 'DENY_NO_ACTOR'
      WHEN user_status <> 'ACTIVE' THEN 'DENY_USER_INACTIVE'
      WHEN assignment_status <> 'VIGENTE' THEN 'DENY_COMPANY_ASSIGNMENT'
      WHEN NOT actor_company_matches THEN 'DENY_TENANT'
      WHEN binding_status <> 'VIGENTE' THEN 'DENY_SOURCE_BINDING'
      WHEN source_authority_status <> 'VIGENTE' THEN 'DENY_SOURCE_AUTHORITY'
      WHEN permission_status <> 'VIGENTE' THEN 'DENY_PERMISSION_INACTIVE'
      WHEN company_permission_status <> 'VIGENTE' THEN 'DENY_COMPANY_PERMISSION'
      WHEN access_effect <> 'ALLOW' OR explicit_deny THEN 'DENY_PERMISSION_EFFECT'
      WHEN NOT read_route_verified THEN 'DENY_READ_ROUTE'
      ELSE 'ALLOW_ADMISSION_CANDIDATE'
 END AS actual_decision
 FROM fixture
)
SELECT case_code,expected_decision,actual_decision,
 CASE WHEN expected_decision=actual_decision THEN 'PASS' ELSE 'FAIL' END AS result
FROM decisions ORDER BY case_code;
-- Expected: 12 PASS; exactly 1 ALLOW_ADMISSION_CANDIDATE synthetic outcome.
-- No business SELECT authorization or tenant-isolation live proof is implied.
