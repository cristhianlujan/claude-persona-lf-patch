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
