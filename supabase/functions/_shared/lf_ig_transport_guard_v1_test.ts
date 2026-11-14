import {validateLfIgTransport,IG_RPC_REQUIRED,IG_RUNTIME_REQUIRED} from "./lf_ig_transport_guard_v1.ts";

const good = {pantalla_id:44,consumer:"CONTEXT_PACK",ticket:"ticket-from-authorized-runtime"};
Deno.test("IG transport: accepted ticket runtime with exact mandatory fields",()=>{
  const result=validateLfIgTransport("edge",good,IG_RUNTIME_REQUIRED["input-governance-agent-v1"]);
  if(result!==null) throw new Error(JSON.stringify(result));
});
for(const field of ["pantalla_id","consumer","ticket"]) {
  for(const invalid of [undefined,null,"", "  ", "{}", {}]) {
    Deno.test("IG transport: required "+field+" invalid="+String(invalid),()=>{
      const p:Record<string,unknown>={...good,[field]:invalid};
      const r=validateLfIgTransport("edge",p,IG_RUNTIME_REQUIRED["input-governance-agent-v1"]);
      if(!r || r.field!==field || r.continuation_allowed!==false || r.downstream_call_attempted!==false)
        throw new Error("missing failure "+field);
    });
  }
}
for(const field of ["semantic_receipt_sha256","catalog_sha256","request_sha256"]) {
  for(const rawField of ["raw","raw_payload","raw_output","raw_input","RAW","profile_output"]) {
    Deno.test("IG transport: forbid "+field+" in "+rawField,()=>{
      const p={...good,[rawField]:{screen_code:"B2B-CARGA-002",[field]:"forged"}};
      const r=validateLfIgTransport("edge",p,IG_RUNTIME_REQUIRED["input-governance-agent-v1"]);
      if(!r || r.code!=="IG_TRANSPORT_RAW_FORBIDDEN_FIELD" ||
         r.field!==rawField+"."+field || r.downstream_call_attempted!==false)
        throw new Error(JSON.stringify(r));
    });
  }
  Deno.test("IG transport: forbid nested RAW "+field,()=>{
    const p={...good,request_body:{raw:{nested:[{[field]:"fake"}]}}};
    const r=validateLfIgTransport("edge",p,IG_RUNTIME_REQUIRED["input-governance-agent-v1"]);
    if(!r || !r.field.endsWith("."+field)) throw new Error(JSON.stringify(r));
  });
}
Deno.test("IG transport: metadata outside RAW allowed",()=>{
  const p={...good,semantic_receipt_sha256:"64hex-does-not-matter",raw:{literal_text:"real source"}};
  if(validateLfIgTransport("edge",p,IG_RUNTIME_REQUIRED["input-governance-agent-v1"])!==null)
    throw new Error("outer metadata must not be rejected");
});
Deno.test("IG transport: reject empty RAW and JSON-stringified empty object",()=>{
  for(const raw of [{}, "{}", "  {}", []]) {
    const r=validateLfIgTransport("edge",{...good,raw},IG_RUNTIME_REQUIRED["input-governance-agent-v1"]);
    if(!r || r.code!=="IG_TRANSPORT_RAW_EMPTY" || r.field!=="raw")throw new Error(JSON.stringify(r));
  }
});
Deno.test("IG transport: malformed optional receipt does not bypass required",()=>{
 const p={p_ticket:"ticket",p_execution_id:"",p_skill_code:"INPUT_GOVERNANCE_CONTEXT_PACK"};
 const r=validateLfIgTransport("skill-ticket",p,IG_RPC_REQUIRED.lf_profile_skill_runtime_ticket_consume_v1);
 if(!r||r.field!=="p_execution_id")throw new Error(JSON.stringify(r));
});
Deno.test("IG transport: preflight consumes no external API",()=>{
 let calls=0;
 function dispatch(p:Record<string,unknown>) {
  const r=validateLfIgTransport("mock",p,IG_RPC_REQUIRED.fn_input_governance_validator_handoff_assert_v1);
  if(r)return r;
  calls++;
  return null;
 }
 const rejected=dispatch({p_run_id:954,p_ticket:""});
 if(!rejected||rejected.field!=="p_ticket"||calls!==0)throw new Error("invalid dispatch leaked");
 const valid=dispatch({p_run_id:954,p_ticket:"test"});
 if(valid!==null||Number(calls)!==1)throw new Error("valid dispatch unexpectedly blocked");
});
