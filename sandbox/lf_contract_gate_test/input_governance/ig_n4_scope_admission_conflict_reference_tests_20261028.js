// DEV-ONLY REFERENCE TESTS — LF IG G3/G4; no runtime, no database writes.
// DO NOT USE THIS SCRIPT TO APPROVE, PUBLISH, OR ENFORCE POLICIES.
// A trustedLookup and trustedCoverage are *injected test doubles*, NOT LF authority adapters.
// Status READY_FOR_GOVERNED_PUBLICATION is a preliminary candidate, never ACTIVE.
// Real admission requires an independently authenticated authority registry and receipt.

function isDigest(x){return typeof x==="string"&&/^[0-9a-f]{64}$/i.test(x)}

function admissionCandidate(p, trustedLookup, trustedCoverage){
  if (!p || !isDigest(p.rule_hash) || !isDigest(p.selector_hash)
    || !isDigest(p.scope_hash) || !p.consumer || !p.owner_role || !p.receipt_ref)
    return {status:"HOLD_EVIDENCE",reason:"MISSING_BINDING"};
  if(p.rule_state!=="VIGENTE"||p.selector_state!=="ACTIVE")return {status:"HOLD_LIFECYCLE",reason:"NON_EXECUTABLE"};
  if(p.has_unknown_attributes)return {status:"HOLD_EVIDENCE",reason:"UNKNOWN_CONTEXT"};
  if(p.has_conflict)return {status:"HOLD_CONFLICT",reason:"UNRESOLVED_COLLISION"};
  if(typeof trustedLookup!=="function")return {status:"HOLD_AUTHORITY",reason:"NO_TRUSTED_RECEIPT_ADAPTER"};
  const receipt=trustedLookup(p.receipt_ref);
  if(!receipt||receipt.identity_validated!==true||receipt.authority_validated!==true)
    return {status:"HOLD_AUTHORITY",reason:"UNVERIFIED_RECEIPT"};
  if(receipt.decision!=="APPROVE_SCOPE"&&receipt.decision!=="APPROVE_WITH_CONDITIONS")
    return {status:"HOLD_AUTHORITY",reason:"DECISION_NOT_APPROVAL"};
  for(const key of ["rule_hash","selector_hash","scope_hash","consumer","owner_role"])
    if(receipt[key]!==p[key])return {status:"HOLD_AUTHORITY",reason:"RECEIPT_SCOPE_BINDING_MISMATCH"};
  if(!receipt.negative_tests_verified || !receipt.source_current)
    return {status:"HOLD_EVIDENCE",reason:"NO_NEGATIVE_TESTS_OR_STALE_SOURCE"};
  // Never trust a caller-supplied "is_broad_coverage" flag.
  // A future authoritative scope inspector must compute impact/coverage from
  // the published target registry and bind it to the exact proposal hashes.
  if(typeof trustedCoverage!=="function")
    return {status:"HOLD_SCOPE",reason:"NO_TRUSTED_COVERAGE_INSPECTOR"};
  const coverage=trustedCoverage(p);
  if(!coverage || coverage.verified!==true || coverage.source_current!==true
    || coverage.rule_hash!==p.rule_hash || coverage.selector_hash!==p.selector_hash
    || coverage.scope_hash!==p.scope_hash || typeof coverage.is_broad!=="boolean")
    return {status:"HOLD_SCOPE",reason:"SCOPE_INSPECTION_UNVERIFIED"};
  if(coverage.is_broad && !receipt.explicit_broad_scope_approval)
    return {status:"HOLD_AUTHORITY",reason:"BROAD_SCOPE_NOT_RATIFIED"};
  if(receipt.restricted_conditions && !p.conditions_satisfied)
    return {status:"HOLD_AUTHORITY",reason:"APPROVAL_CONDITIONS_UNMET"};
  if(!receipt.valid_until_epoch || receipt.valid_until_epoch<=p.evaluation_epoch)
    return {status:"HOLD_AUTHORITY",reason:"EXPIRED_RECEIPT"};
  return {status:"READY_FOR_GOVERNED_PUBLICATION",reason:"REFERENCE_CHECKS_PASSED_NOT_PRODUCTION_AUTHORIZATION"}
}

function compositionCandidate(a,b,relation,verifiedRelation){
  if(!a||!b||!a.effect_key||!b.effect_key||!a.effect_value||!b.effect_value)
    return {status:"MODEL_GAP",reason:"UNSTRUCTURED_EFFECT"};
  if(a.effect_key!==b.effect_key)return {status:"COMPOSE_CANDIDATE",reason:"DIFFERENT_EFFECTS"};
  if(a.effect_value===b.effect_value)return {status:"DEDUPLICATE_CANDIDATE",reason:"SAME_EFFECT_PRESERVE_PROVENANCE"};
  if((a.non_delegable===true&&b.attempts_to_relax===true)||(b.non_delegable===true&&a.attempts_to_relax===true))
    return {status:"VETO",reason:"NON_DELEGABLE_SUPERIOR_CONTROL"};
  if(!relation||relation.type!=="APPROVED_OVERRIDE"||typeof verifiedRelation!=="function"||verifiedRelation(relation,a,b)!==true)
    return {status:"HOLD_CONFLICT",reason:"NO_COMPETENT_PRECEDENCE_RECEIPT"};
  return {status:"OVERRIDE_CANDIDATE",reason:"PRECEDENCE_RECEIPT_REFERENCED_REQUIRES_PUBLICATION_GATE"};
}

const H='a'.repeat(64),J='b'.repeat(64),K='c'.repeat(64),L='d'.repeat(64);
const base={
  "rule_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "selector_hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "scope_hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  "consumer": "INPUT_GOVERNANCE",
  "owner_role": "BUSINESS_OWNER",
  "receipt_ref": "test-receipt",
  "rule_state": "VIGENTE",
  "selector_state": "ACTIVE",
  "has_unknown_attributes": false,
  "has_conflict": false,
  
  "evaluation_epoch": 100,
  "conditions_satisfied": true
};
const receipt={
  "identity_validated": true,
  "authority_validated": true,
  "decision": "APPROVE_SCOPE",
  "rule_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "selector_hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "scope_hash": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  "consumer": "INPUT_GOVERNANCE",
  "owner_role": "BUSINESS_OWNER",
  "negative_tests_verified": true,
  "source_current": true,
  "explicit_broad_scope_approval": false,
  "valid_until_epoch": 200
};
const get=()=>receipt;
// TEST DOUBLE only. A real adapter must obtain this result from independently
// authenticated scope/coverage evidence; a proposer must not set is_broad.
const trustedCoverage=p=>({verified:true,source_current:true,rule_hash:p.rule_hash,
  selector_hash:p.selector_hash,scope_hash:p.scope_hash,is_broad:p.scope_hash===L});
const admissionTests=[
  ["A01 positive bounded receipt",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},get,"READY_FOR_GOVERNED_PUBLICATION"],
  ["A02 no adapter",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},null,"HOLD_AUTHORITY"],
  ["A03 receipt missing",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>null,"HOLD_AUTHORITY"],
  ["A04 forged/unverified identity",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,identity_validated:false}),"HOLD_AUTHORITY"],
  ["A05 altered rule version",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,rule_hash:J}),"HOLD_AUTHORITY"],
  ["A06 altered selector version",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,selector_hash:H}),"HOLD_AUTHORITY"],
  ["A07 altered scope",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,scope_hash:H}),"HOLD_AUTHORITY"],
  ["A08 wrong consumer",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,consumer:"OUTSIDE"}),"HOLD_AUTHORITY"],
  ["A09 wrong owner competence",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,owner_role:"UNKNOWN"}),"HOLD_AUTHORITY"],
  ["A10 expired receipt",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,valid_until_epoch:10}),"HOLD_AUTHORITY"],
  ["A11 stale source",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,source_current:false}),"HOLD_EVIDENCE"],
  ["A12 missing negative tests",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,negative_tests_verified:false}),"HOLD_EVIDENCE"],
  ["A13 unresolved context",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":true,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},get,"HOLD_EVIDENCE"],
  ["A14 conflict",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":true,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},get,"HOLD_CONFLICT"],
  ["A15 CANDIDATO",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"CANDIDATO","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},get,"HOLD_LIFECYCLE"],
  ["A16 UNRESOLVED",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"UNRESOLVED","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},get,"HOLD_LIFECYCLE"],
  ["A17 broad without approval",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"evaluation_epoch":100,"conditions_satisfied":true},get,"HOLD_AUTHORITY"],
  ["A18 broad explicitly ratified",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,scope_hash:L,explicit_broad_scope_approval:true}),"READY_FOR_GOVERNED_PUBLICATION"],
  ["A19 conditional approval unmet",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":false},()=>({...receipt,restricted_conditions:true}),"HOLD_AUTHORITY"],
  ["A20 conditional approval met",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,restricted_conditions:true,decision:"APPROVE_WITH_CONDITIONS"}),"READY_FOR_GOVERNED_PUBLICATION"],
  ["A21 rejected decision",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},()=>({...receipt,decision:"REJECT_SCOPE"}),"HOLD_AUTHORITY"],
  ["A22 bad digest",{"rule_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selector_hash":"fake","scope_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","consumer":"INPUT_GOVERNANCE","owner_role":"BUSINESS_OWNER","receipt_ref":"test-receipt","rule_state":"VIGENTE","selector_state":"ACTIVE","has_unknown_attributes":false,"has_conflict":false,"is_broad_coverage":false,"evaluation_epoch":100,"conditions_satisfied":true},get,"HOLD_EVIDENCE"]
];
const x={"id":"privacy","effect_key":"telemetry.pii","effect_value":"DENY","non_delegable":true},y={"id":"other","effect_key":"a11y.keyboard","effect_value":"REQUIRE"},z={"id":"exception","effect_key":"telemetry.pii","effect_value":"ALLOW","attempts_to_relax":true};
const compositionTests=[
  ["C01 independent compatible",{"id":"privacy","effect_key":"telemetry.pii","effect_value":"DENY","non_delegable":true},{"id":"other","effect_key":"a11y.keyboard","effect_value":"REQUIRE"},null,null,"COMPOSE_CANDIDATE"],
  ["C02 exact duplicate",{"id":"privacy","effect_key":"telemetry.pii","effect_value":"DENY","non_delegable":true},{"id":"duplicate","effect_key":"telemetry.pii","effect_value":"DENY","non_delegable":true},null,null,"DEDUPLICATE_CANDIDATE"],
  ["C03 superior nondelegable veto",{"id":"privacy","effect_key":"telemetry.pii","effect_value":"DENY","non_delegable":true},{"id":"exception","effect_key":"telemetry.pii","effect_value":"ALLOW","attempts_to_relax":true},null,null,"VETO"],
  ["C04 incompatible/no precedence",{"effect_key":"limit","effect_value":"10"},{"effect_key":"limit","effect_value":"20"},null,null,"HOLD_CONFLICT"],
  ["C05 incompatible/unsigned override",{"effect_key":"limit","effect_value":"10"},{"effect_key":"limit","effect_value":"20"},{"type":"APPROVED_OVERRIDE"},()=>false,"HOLD_CONFLICT"],
  ["C06 incompatible/verified override",{"effect_key":"limit","effect_value":"10"},{"effect_key":"limit","effect_value":"20"},{"type":"APPROVED_OVERRIDE","receipt_ref":"synthetic"},()=>true,"OVERRIDE_CANDIDATE"],
  ["C07 approved override cannot weaken nondelegable",{"id":"privacy","effect_key":"telemetry.pii","effect_value":"DENY","non_delegable":true},{"id":"exception","effect_key":"telemetry.pii","effect_value":"ALLOW","attempts_to_relax":true},{"type":"APPROVED_OVERRIDE"},()=>true,"VETO"],
  ["C08 unknown effect missing",{"effect_key":"limit"},{"effect_key":"limit","effect_value":"20"},null,null,"MODEL_GAP"],
  ["C09 same effect differing modality",{"effect_key":"session.timeout","effect_value":"20"},{"effect_key":"session.timeout","effect_value":"40"},null,null,"HOLD_CONFLICT"],
  ["C10 string title similarity no collision",{"effect_key":"onboarding.session","effect_value":"REQUIRE"},{"effect_key":"auth.session","effect_value":"DENY"},null,null,"COMPOSE_CANDIDATE"]
];
let failed=0;
for(const [label,p,lookup,expected] of admissionTests){const actual=admissionCandidate(p,lookup,trustedCoverage).status;if(actual!==expected){failed++;throw new Error(label+": expected "+expected+" got "+actual)}}
for(const [label,a,b,relation,verify,expected] of compositionTests){const actual=compositionCandidate(a,b,relation,verify).status;if(actual!==expected){failed++;throw new Error(label+": expected "+expected+" got "+actual)}}
const noInspector=admissionCandidate(base,get,null);
if(noInspector.status!=="HOLD_SCOPE")throw new Error("Scope adapter missing must HOLD");
const forgedInspector=admissionCandidate(base,get,()=>({...trustedCoverage(base),scope_hash:L}));
if(forgedInspector.status!=="HOLD_SCOPE")throw new Error("Scope hash drift must HOLD");
const staleInspector=admissionCandidate(base,get,()=>({...trustedCoverage(base),source_current:false}));
if(staleInspector.status!=="HOLD_SCOPE")throw new Error("Stale scope inspection must HOLD");
console.log(JSON.stringify({admission:admissionTests.length+3,composition:compositionTests.length,failed,reference_only:true}));
