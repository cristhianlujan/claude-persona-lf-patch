INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
SELECT 'DEC-IG-M98-TECHNICAL-RELEASE-SPLIT-V7-20261011','M9.8 technical versus release gate',
'Technical readback proves four base controls PASS and two evidence-guard controls BLOCKED as required without business approval. Runtime gate stays BLOCKED until six PASS with verified per-field receipt and separately authorized decision. No release, no synthetic evidence, no historical ADR erasure.',
'Previous last technical checkpoint depended on unresolved independent business authority; these lifecycles require distinct statuses.',
'M9.8 engineering-only readback; real runtime gate and human authority are preserved.','VIGENTE'
WHERE NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-TECHNICAL-RELEASE-SPLIT-V7-20261011');
UPDATE programacion.engineering_plan_units SET unit_metadata=
jsonb_set(jsonb_set(unit_metadata,'{m9_8_gate_contract_v2,technical_acceptance_v7}',
jsonb_build_object('checkpoint','GATE_VERDICT_READBACK','technical_readback','programacion.fn_ig_m98_engineering_assurance_v7','runtime_gate','programacion.fn_ig_m98_gate_readback_v2','release_authorized',false,'governance','DEC-IG-M98-TECHNICAL-RELEASE-SPLIT-V7-20261011'),true),
'{action_specs_v1,GATE_VERDICT_READBACK}',jsonb_build_object(
'schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code','GATE_VERDICT_READBACK',
'status','READY','action_kind','READBACK_ONCE','contract_family','CURRENT_TECHNICAL_READBACK_BOUND',
'mutation_policy','NO_DOMAIN_MUTATION','requires_material_execution',false,
'expected','TECHNICAL_GATE_FAIL_CLOSED_VERIFIED_NOT_RELEASED; runtime gate remains BLOCKED',
'acceptance_function','programacion.fn_ig_m98_engineering_assurance_v7'),true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';