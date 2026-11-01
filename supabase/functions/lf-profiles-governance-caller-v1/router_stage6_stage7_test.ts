// Isolated regression carrier: Stage 06 must NOT write; Stage 07 is the sole writer.
// Loaded by the already-existing CP2 Edge test workflow; no new CI workflow.
import { createHandler, type JwtPayload } from "./caller.ts";

const REPO = "cristhianlujan/claude-persona-lf-patch";
const LEGACY_REF = "refs/heads/governance/profiles-unblock-secure-caller-20260901";
const config: Record<string, string> = {
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",
  LF_CALLER_REPOSITORY: REPO,
  LF_CALLER_REPOSITORY_ID: "1244397752",
  LF_CALLER_RECURATION_REF: "refs/heads/main",
  LF_CALLER_RECURATION_WORKFLOW_REF: REPO + "/.github/workflows/lf-input-governance-recurate.yml@refs/heads/main",
  LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF: REPO + "/.github/workflows/lf-input-governance-recurate-dispatch.yml@refs/heads/main",
  LF_CALLER_RECURATION_WORKFLOW_NAME: "LF Input Governance Recuration",
  LF_CALLER_INPUT_GOVERNANCE_SLUG: "input-governance-agent-v1",
  LF_CALLER_PROFILE_CREATOR_SLUG: "run-creacion-perfil-lf",
  LF_CALLER_RECURATION_TIMEOUT_MS: "149000",
  LF_CALLER_DEFAULT_TIMEOUT_MS: "120000",
};
const claims: JwtPayload = {
  repository: REPO, repository_id: "1244397752", ref: LEGACY_REF,
  workflow_ref: REPO + "/.github/workflows/lf-profiles-governance-caller.yml@" + LEGACY_REF,
  workflow: "LF Profiles Governance Caller", event_name: "push",
  run_id: "9004", workflow_sha: "a".repeat(40),
};

// The original Router Stage 06/07 path was not an authorized profile launcher.
// These actions must not re-enter Router nor invoke any profile or Supabase RPC.
Deno.test("retired Router-to-profile actions never call any backend", async () => {
  for (const action of ["router_profile_admit_context_v2", "profile_execution_begin_from_router_context_v1"]) {
    for (const identity of [claims, {
      ...claims, ref:"refs/heads/main",
      workflow_ref:REPO+"/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main",
      event_name:"issues",environment:"lf-edge-deploy",
    }]) {
      let backendCalls = 0;
      const handler = createHandler({
        getEnv: (name: string) => config[name],
        jwks:{mock:true},jwtVerifyFn:async()=>({payload:identity}),
        fetchFn:async()=>{backendCalls++;throw new Error("BACKEND_CALL_FORBIDDEN");},
      });
      const resp = await handler(new Request("https://caller.test",{
        method:"POST",
        headers:{authorization:"Bearer mock-token","content-type":"application/json"},
        body:JSON.stringify({action,context:{schema_version:"LF_ROUTER_EXECUTION_PIPELINE_V1",
          status:"GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",transport_mode:"CONTEXT_TRANSPORT"},
          executor_mode:"GPT_NATIVE"}),
      }));
      const body=await resp.json();
      if (resp.status!==410 || body.code!=="ROUTER_PROFILE_DIRECT_OR_INTERMEDIATE_CALL_RETIRED" ||
          backendCalls!==0) throw new Error("ROUTER_RETIRED_ACTION_LEAK:"+JSON.stringify({status:resp.status,body,backendCalls}));
    }
  }
});

const nativeClaims: JwtPayload = {
  ...claims, ref:"refs/heads/main",
  workflow_ref:REPO+"/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main",
  event_name:"issues", environment:"lf-edge-deploy",
};
const nativeContext = {
  schema_version:"LF_ROUTER_EXECUTION_PIPELINE_V1",
  status:"GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
  transport_mode:"CONTEXT_TRANSPORT",
  stage1_payload:{canal_candidato:"PRODUCTO",negocio_codigo:"LF",alcance:{target_type:"PANTALLA"}},
};
Deno.test("profile-owned BEGIN applies service_role only inside Edge canonical writer", async () => {
  const calls:{url:string,body:Record<string,unknown>,headers:Record<string,string>}[]=[];
  const h = createHandler({getEnv:(n:string)=>config[n], jwks:{mock:true},
    jwtVerifyFn:async()=>({payload:nativeClaims}),
    fetchFn:async(input: string|URL|Request, init?:RequestInit)=>{
      const url=String(input);
      const body=(typeof init?.body==="string" && init.body?JSON.parse(init.body):{}) as Record<string,unknown>;
      const headers=(init?.headers||{}) as Record<string,string>;
      calls.push({url,body,headers});
      if(url.endsWith("/rest/v1/rpc/lf_router_pipeline_context_profile_admit_v2"))
        return new Response(JSON.stringify({
          status:"PROFILE_HANDOFF_READY",write_performed:false,execution_id:null,
          executor_mode:"GPT_NATIVE",
          router_profile_handoff:{
            schema_version:"LF_ROUTER_PROFILE_EXECUTION_HANDOFF_V1",
            operation_code:"EJECUCION_PERFIL_LF",effect_authority:false,
            profile_code:"PERFIL-UX-DESIGN-LF",
            request_sha256:"a".repeat(64),fingerprint_sha256:"b".repeat(64),
            channel:"PRODUCTO",business:"LF",
          }
        }),{status:200});
      if(url.includes("/rest/v1/lf_activos?codigo_activo=eq."))
        return new Response(JSON.stringify([{codigo_activo:"PERFIL-UX-DESIGN-LF",
          metadata:{entrypoint_path:"profiles/ux_design_lf/SKILL.md"},
          ruta_esperada:"profiles/ux_design_lf"}]),{status:200});
      if(url.endsWith("/rest/v1/rpc/lf_profile_execution_begin_from_handoff_v1"))
        return new Response(JSON.stringify({
          status:"READY",init_materialized:true,
          execution_id:"EXEC-PROFILE-GATE2-"+"A".repeat(24),
        }),{status:200});
      throw new Error("UNEXPECTED_BACKEND_CALL:"+url);
    },
  });
  const response=await h(new Request("https://caller.test",{
    method:"POST",headers:{authorization:"Bearer test-oidc","content-type":"application/json"},
    body:JSON.stringify({action:"profile_native_begin_from_context_v1",
      context:nativeContext,executor_mode:"GPT_NATIVE"}),
  }));
  const result=await response.json();
  if(response.status!==200 || result.outcome!=="NATIVE_EXECUTION_READY" ||
     result.result?.execution_id!=="EXEC-PROFILE-GATE2-"+"A".repeat(24))
    throw new Error("PROFILE_BEGIN_NOT_READY:"+JSON.stringify(result));
  if(calls.length!==3)throw new Error("EXPECTED_THREE_CANONICAL_CALLS");
  if(!calls[0].url.endsWith("/rpc/lf_router_pipeline_context_profile_admit_v2")||
     !calls[1].url.includes("/rest/v1/lf_activos?")||
     !calls[2].url.endsWith("/rpc/lf_profile_execution_begin_from_handoff_v1"))
    throw new Error("WRONG_CALL_SEQUENCE");
  if(calls[2].headers.authorization!=="Bearer service-role-test-key")
    throw new Error("SERVICE_ROLE_NOT_APPLIED_AT_WRITER");
  if(JSON.stringify(calls[2].body).includes("service-role-test-key")||
     JSON.stringify(result).includes("service-role-test-key"))
    throw new Error("SERVICE_ROLE_LEAK_IN_PAYLOAD_OR_RESPONSE");
});
Deno.test("profile begin denies non-native OIDC before any backend call", async()=>{
  let calls=0;
  const h=createHandler({getEnv:(n:string)=>config[n],jwks:{mock:true},
    jwtVerifyFn:async()=>({payload:claims}),
    fetchFn:async()=>{calls++;throw new Error("SHOULD_NOT_CALL");}});
  const response=await h(new Request("https://caller.test",{
    method:"POST",headers:{authorization:"Bearer test-oidc","content-type":"application/json"},
    body:JSON.stringify({action:"profile_native_begin_from_context_v1",
      context:nativeContext,executor_mode:"GPT_NATIVE"}),
  }));
  const result=await response.json();
  if(response.status!==403 || result.code!=="PROFILE_NATIVE_BEGIN_EXACT_OIDC_REQUIRED"||calls!==0)
    throw new Error("UNAUTHENTICATED_PROFILE_BEGIN"+JSON.stringify(result));
});
