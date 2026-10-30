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
const context = {
  schema_version: "LF_ROUTER_EXECUTION_PIPELINE_V1",
  status: "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION",
  transport_mode: "CONTEXT_TRANSPORT",
  stage1_payload: { canal_candidato: "PRODUCTO", negocio_codigo: "LF",
    alcance: { target_type: "PANTALLA" } },
  after_selection_result: { gate2_request: { schema_version: "LF_ROUTER_PROFILE_GATE2_REQUEST_V1" } },
  gate2_derivation: { gate2_result: { decision: "RESOLVED" } },
};
const handoff = {
  schema_version: "LF_ROUTER_PROFILE_EXECUTION_HANDOFF_V1",
  operation_code: "EJECUCION_PERFIL_LF", effect_authority: false,
  profile_code: "PERFIL-UX-DESIGN-LF",
  request_sha256: "a".repeat(64), fingerprint_sha256: "b".repeat(64),
  channel: "PRODUCTO", business: "LF",
};
function check(actual: unknown, expected: unknown, label: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(label + ": actual=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected));
  }
}
function rig(opts: { admitWrite?: boolean; assetPath?: string; badIdentity?: boolean; nativeIdentity?: boolean } = {}) {
  const calls: { url: string; body?: Record<string, unknown> }[] = [];
  const fakeClaims: JwtPayload = opts.badIdentity
    ? { ...claims, workflow_ref: config.LF_CALLER_RECURATION_DISPATCH_WORKFLOW_REF,
        ref: "refs/heads/main", job_workflow_ref: config.LF_CALLER_RECURATION_WORKFLOW_REF,
        event_name: "workflow_dispatch" }
    : opts.nativeIdentity
      ? { ...claims, ref: "refs/heads/main",
          workflow_ref: REPO + "/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main",
          event_name: "issues", environment: "lf-edge-deploy" }
      : claims;
  const handler = createHandler({
    getEnv: (name: string) => config[name],
    jwks: {mock:true},
    jwtVerifyFn: async () => ({payload: fakeClaims}),
    fetchFn: async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
      const url = String(input);
      const body = typeof init?.body === "string" && init.body ? JSON.parse(init.body) : undefined;
      calls.push({url,body});
      if (url.endsWith("/rest/v1/rpc/lf_router_pipeline_context_profile_admit_v2")) {
        return new Response(JSON.stringify({
          status: "PROFILE_HANDOFF_READY", executor_mode: body?.p_executor_mode,
          profile_code: handoff.profile_code, write_performed: opts.admitWrite === true,
          execution_id: null, router_profile_handoff: handoff,
          next_action: "EJECUCION_PERFIL_LF_BEGIN_REQUIRED",
        }), {status:200});
      }
      if (url.includes("/rest/v1/lf_activos?codigo_activo=eq.")) {
        return new Response(JSON.stringify([{
          codigo_activo: handoff.profile_code,
          metadata: {entrypoint_path: opts.assetPath ?? "profiles/ux_design_lf/SKILL.md"},
          ruta_esperada: "profiles/ux_design_lf",
        }]),{status:200});
      }
      if (url.endsWith("/rest/v1/rpc/lf_profile_execution_begin_from_handoff_v1")) {
        return new Response(JSON.stringify({
          status: "READY", init_materialized: true, execution_id: body?.p_execution_id,
          next_step: "profile_resolve",
        }), {status:200});
      }
      return new Response(JSON.stringify({code:"UNEXPECTED_CALL"}),{status:404});
    },
  });
  async function invoke(action: string, mode = "GPT_NATIVE") {
    const response = await handler(new Request("https://caller.test",{
      method:"POST",
      headers:{authorization:"Bearer mock-token","content-type":"application/json"},
      body:JSON.stringify({action,context,executor_mode:mode}),
    }));
    return {status:response.status,payload:await response.json()};
  }
  return {calls,invoke};
}

Deno.test("Stage 06 read-only: returns verified handoff and does not touch execution writer",async()=>{
  const h=rig();
  const x=await h.invoke("router_profile_admit_context_v2");
  check(x.status,200,"ADMIT_HTTP");
  check(x.payload.outcome,"PROFILE_HANDOFF_READY","ADMIT_STATUS");
  check(x.payload.result.write_performed,false,"ADMIT_WRITE");
  check(x.payload.result.execution_id,null,"ADMIT_EXECUTION_ID");
  check(h.calls.length,1,"ONLY_ADMISSION_RPC");
  check(h.calls[0].url.endsWith("/rest/v1/rpc/lf_router_pipeline_context_profile_admit_v2"),true,"ADMIT_RPC");
});

Deno.test("Stage 07 execution writer: preserves exact handoff fingerprint and canonical source",async()=>{
  const h=rig();
  const x=await h.invoke("profile_execution_begin_from_router_context_v1");
  check(x.status,200,"BEGIN_HTTP");
  check(x.payload.outcome,"NATIVE_EXECUTION_READY","BEGIN_OUTCOME");
  check(h.calls.length,3,"EXACT_THREE_CALLS");
  check(h.calls[0].url.endsWith("/rest/v1/rpc/lf_router_pipeline_context_profile_admit_v2"),true,"PREWRITE_ADMISSION");
  check(h.calls[2].url.endsWith("/rest/v1/rpc/lf_profile_execution_begin_from_handoff_v1"),true,"PROFILE_ONLY_WRITER");
  check((h.calls[2].body?.p_handoff as Record<string,unknown>).fingerprint_sha256,handoff.fingerprint_sha256,"SAME_HANDOFF");
  check(h.calls[2].body?.p_target_path,"profiles/ux_design_lf/SKILL.md","CANONICAL_TARGET");
  check(h.calls[2].body?.p_target_repo,REPO,"CANONICAL_REPO");
  check(x.payload.result.execution_id,"EXEC-PROFILE-GATE2-"+"A".repeat(24),"EXECUTION_ID");
});

Deno.test("Stages 06/07 fail closed on invalid OIDC, REMOTE_API, bad admission and unsafe profile path",async()=>{
  for(const c of [
    {opts:{badIdentity:true},mode:"GPT_NATIVE",status:403},
    {opts:{},mode:"REMOTE_API",status:400},
    {opts:{admitWrite:true},mode:"GPT_NATIVE",status:409},
    {opts:{assetPath:"../private/SKILL.md"},mode:"GPT_NATIVE",status:409},
  ]) {
    const h=rig(c.opts);
    const x=await h.invoke("profile_execution_begin_from_router_context_v1",c.mode);
    check(x.status,c.status,"NEGATIVE_HTTP");
    check(h.calls.some(v=>v.url.endsWith("/rest/v1/rpc/lf_profile_execution_begin_from_handoff_v1")),false,"NO_WRITE_ON_BLOCK");
  }
});

Deno.test("Stage07 exact MAIN workflow issue OIDC invokes canonical writer after Stage06 handoff",async()=>{
  const h=rig({nativeIdentity:true});
  const admit=await h.invoke("router_profile_admit_context_v2");
  check(admit.status,200,"NATIVE_ISSUE_STAGE06_HTTP");
  check(admit.payload.outcome,"PROFILE_HANDOFF_READY","NATIVE_ISSUE_STAGE06_RESULT");
  check(h.calls.length,1,"NATIVE_ISSUE_STAGE06_READ_ONLY");

  const result=await h.invoke("profile_execution_begin_from_router_context_v1");
  check(result.status,200,"NATIVE_ISSUE_STAGE07_HTTP");
  check(result.payload.outcome,"NATIVE_EXECUTION_READY","NATIVE_ISSUE_STAGE07_RESULT");
  check(h.calls.filter(c=>c.url.endsWith("/rest/v1/rpc/lf_profile_execution_begin_from_handoff_v1")).length,1,
    "EXACTLY_ONE_CANONICAL_WRITER");
});

Deno.test("Stage07 native OIDC remains closed for non-profile actions",async()=>{
  const h=rig({nativeIdentity:true});
  const x=await h.invoke("profile_creator_init_v1");
  check(x.status,403,"NATIVE_ISSUE_CREATOR_DENIED");
  check(x.payload.code,"NATIVE_CONTINUATION_OIDC_ACTION_SCOPE_MISMATCH","NATIVE_ISSUE_SCOPE_GUARD");
  check(h.calls.length,0,"NO_BACKEND_CALL_ON_UNRELATED_ACTION");
});
