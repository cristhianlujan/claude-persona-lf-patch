import {test} from "node:test";
import assert from "node:assert/strict";
import {planLifecycle} from "./lifecycle_gate.mjs";
const h = c => c.repeat(64);
const steps = Object.fromEntries(["init_execution","router","profile_resolve",
  "profile_source_read","input_validate","context_admission","research_baseline_freeze",
  "execute_profile","output_validate","semantic_judge","report_output"]
  .map(x=>[x,"STEP_PASS_WITH_EVIDENCE"]));
const build = (kind="CREATE") => {
  const source = h("a"), proposal=h("b"), after=h("c"), final=h("d"), req=h("e");
  const code="B2B-RULE-AUTH-999";
  const runid="EXEC-PROFILE-GATE2-ABCDEF1234567890";
  const s={project:"LF",request:{router:"ACT-0001",transport:"CONTEXT_TRANSPORT",sha256:req},
    run:{id:runid},rule:{kind,code},
    proposal:{rule_code:code,kind,sha256:proposal,source_sha256:source,judge:"PASS"},
    decision:{verdict:"APPROVE",project:"LF",rule_code:code,proposal_sha256:proposal,
      source_sha256:source,subject:"github-sub:259964988",verified_receipt:"oidc://verified/1",
      receipt_sha256:h("f")}};
  const trusted={run:{id:runid,is_new:true,profile:"PERFIL-PRODUCT-DIRECTOR-LF",request_sha256:req,
    status:"COMPLETED",terminal:"READY",steps},
    native:{run_id:runid,provider_bound:true,source_attested:true,independent_judge_attested:true},
    ig:{status:"READY",current:true,run_id:runid},
    rule:{exists:kind!=="CREATE",state:kind==="CORRECT_VIGENTE"?"VIGENTE":"CANDIDATO",
      sha256:source,absent_sha256:source},
    owner:{project:"LF",profile:"PERFIL-PRODUCT-DIRECTOR-LF",authenticated:true,
      owner_binding_current:true,subject:"github-sub:259964988",role:"LF_OWNER",
      receipt_ref:"oidc://verified/1",owner_code:"LF_OWNER"},
    child:{parent_id:runid,rule_code:code,proposal_sha256:proposal,source_sha256:source,
      after_sha256:after,status:"COMPLETED",state:kind==="CORRECT_VIGENTE"?"VIGENTE":"CANDIDATO",
      official_writer_verified:true,steps_clean:true,readback_verified:true},
    promotion:{owner_receipt:"oidc://verified/1",rule_code:code,
      request_snapshot_sha256:after,status:"APPLIED",decided_by_subject:"github-sub:259964988"},
    final:{rule_code:code,source_state:"VIGENTE",sha256:final,
      writer_receipt_verified:true,operation_closed:true,original_run_intact:true}};
  return {s,trusted};
};
for(const kind of ["CREATE","UPDATE_CANDIDATE","CORRECT_VIGENTE"]){
  test("E2E readback certified "+kind,()=>{let {s,trusted}=build(kind);
    assert.equal(planLifecycle(s,trusted).state,"CLOSED");
  });
  test("official writer selected "+kind,()=>{
    let {s,trusted}=build(kind); delete trusted.child;
    const x=planLifecycle(s,trusted);
    assert.equal(x.action,kind==="CREATE"?"RULE_CREATE_APPLY":
      kind==="UPDATE_CANDIDATE"?"RULE_UPDATE_APPLY":"ACTUALIZACION_DB_LF_MERGE_TRAIN");
  });
}
const neg=(name,change,code)=>test(name,()=>{
  const x=build();change(x);assert.equal(planLifecycle(x.s,x.trusted).code,code);
});
neg("no historical RUN substitution",x=>x.trusted.run.is_new=false,"BLOCK_NEW_RUN_BINDING");
neg("wrong request SHA",x=>x.trusted.run.request_sha256=h("0"),"BLOCK_REQUEST_BINDING");
neg("cross project blocked",x=>x.s.project="SALY","BLOCK_SCOPE");
neg("router bypass blocked",x=>x.s.request.router="DIRECT","BLOCK_ROUTER_GATE2");
neg("missing native dispatch receipt",x=>delete x.trusted.native,"BLOCK_NATIVE_PROVIDER_PROOF");
neg("fake independence blocked",x=>x.trusted.native.independent_judge_attested=false,"BLOCK_NATIVE_PROVIDER_PROOF");
neg("missing IG currentness",x=>x.trusted.ig.current=false,"BLOCK_IG_CURRENTNESS");
neg("missing owner authentication",x=>x.trusted.owner.authenticated=false,"BLOCK_OWNER_IDENTITY_B06_B08");
neg("SUPER_ADMIN is not LF owner",x=>x.trusted.owner.role="SUPER_ADMIN_FALLBACK","BLOCK_OWNER_IDENTITY_B06_B08");
neg("owner subject spoof",x=>x.s.decision.subject="other","BLOCK_OWNER_DECISION_BINDING");
neg("proposal digest mismatch",x=>x.s.decision.proposal_sha256=h("0"),"BLOCK_OWNER_DECISION_BINDING");
neg("current rule drift",x=>x.trusted.rule.absent_sha256=h("0"),"BLOCK_CREATE_PREIMAGE");
neg("unverified child",x=>x.trusted.child.official_writer_verified=false,"BLOCK_CHILD_RECEIPT_UNVERIFIED");
neg("no VIGENTE readback",x=>x.trusted.final.source_state="CANDIDATO","BLOCK_FINAL_READBACK");
neg("no exact owner preimage in lf_activos",x=>{
  x.s.asset_owner_change={code:"A1",preimage_sha256:h("2"),new_owner:"LF_OWNER"};
  x.trusted.asset={code:"A1",preimage_sha256:h("3"),project:"LF",authorized_operation:"ACTUALIZACION_DB_LF"};
},"BLOCK_LF_ACTIVOS_OWNER_AUTHORITY");
test("wait for explicit owner decision",()=>{
 const x=build();delete x.s.decision;
 assert.equal(planLifecycle(x.s,x.trusted).code,"OWNER_DECISION_REQUIRED");
});
test("reject never triggers writer",()=>{
 const x=build();x.s.decision.verdict="REJECT";
 assert.equal(planLifecycle(x.s,x.trusted).state,"REJECTED");
});
test("wait for same RUN 11/11",()=>{
 const x=build();x.trusted.run.steps.semantic_judge="BLOCKED_STEP_NOT_CLEAN";
 assert.equal(planLifecycle(x.s,x.trusted).code,"WAIT_PROFILE_11_11");
});
test("promotion requires authenticated human bound to child sha",()=>{
 const x=build();delete x.trusted.promotion;
 const p=planLifecycle(x.s,x.trusted);
 assert.equal(p.action,"PROMOCION_REGLA_LF");
 assert.equal(p.input.request_snapshot_sha256,h("c"));
});
test("lf_activos goes exclusively through Merge Train",()=>{
 const x=build();x.s.asset_owner_change={code:"A1",preimage_sha256:h("2"),new_owner:"LF_OWNER"};
 x.trusted.asset={code:"A1",preimage_sha256:h("2"),project:"LF",authorized_operation:"ACTUALIZACION_DB_LF"};
 let r=planLifecycle(x.s,x.trusted);
 assert.equal(r.action,"ACTUALIZACION_DB_LF_MERGE_TRAIN");
 assert.equal(r.input.apply_directly,false);
});
