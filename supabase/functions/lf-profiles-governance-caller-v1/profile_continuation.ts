// Governed, profile-agnostic continuation for an *existing* Router-admitted execution.
// It deliberately does not select a profile/screen, impersonate a model, or grant
// write authority. All substantive transitions use existing canonical RPCs.
export const PROFILE_SOURCE_BIND_ACTION = "profile_native_source_bind_v1";
export const PROFILE_CONTINUE_ACTION = "profile_native_continue_v1";
// A read-only profile calls a governed skill through its own route. The skill invoker
// (lf_skill_invoke_v1) owns the authority/input checks; this action only transports the call.
export const PROFILE_SKILL_INVOKE_ACTION = "profile_native_skill_invoke_v1";
export const PROFILE_SKILL_STEP_BATCH_ACTION = "profile_native_skill_step_batch_v1";
// Controlled post-70 action owned by Product Director. No Router dispatch
// or profile run is created; issuer identity stays outside this caller.
export const PROFILE_RULE_AUTHORITY_ACTION = "profile_native_rule_authority_v1";
export const PROFILE_CONTINUATION_ACTIONS = [PROFILE_SOURCE_BIND_ACTION, PROFILE_CONTINUE_ACTION, PROFILE_SKILL_INVOKE_ACTION, PROFILE_SKILL_STEP_BATCH_ACTION, PROFILE_RULE_AUTHORITY_ACTION] as const;
const SKILL_CODE_RE = /^[A-Z][A-Z0-9_]{2,63}$/;
const SKILL_TARGET_PATH_RE = /^profiles\/[A-Za-z0-9][A-Za-z0-9_./-]*$/;
// Extra GitHub path type is *only* allowed for SKILL_UPDATE_APPLY; the invoker
// still refuses DRAFT skills and the governed child opener owns target authority.
const SKILL_UPDATE_TARGET_PATH_RE = /^skills\/[a-z0-9_-]+(?:\/[A-Za-z0-9_.-]+)+$/;
const SHA40_RE = /^[0-9a-f]{40}$/;
const GITHUB_API = "https://api.github.com";
const MAX_SKILL_INPUT_BYTES = 65536;

// Native executors are bound to their provider; any other mode/provider pair is rejected.
const NATIVE_EXECUTOR_PROVIDER_BY_MODE = new Set([
  "GPT_NATIVE|OPENAI_CHATGPT_NATIVE",
  "CLAUDE_NATIVE|ANTHROPIC_CLAUDE_NATIVE",
]);

type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
type Config = { supabaseUrl: string; serviceRoleKey: string; repository: string };
// Identity of the authenticated OIDC caller of this route (verified by the Edge function, never by the request body).
export type CallerIdentity = { method: string; repository: string; workflow_ref: string; run_id: string; workflow_sha: string };
type Execution = {
  execution_id: string;
  status: string;
  operation_code: string;
  target_type: string;
  target_code: string;
  target_repo: string;
  target_path: string;
  manifest: Record<string, unknown>;
};
type Payload = Record<string, unknown>;

function respond(body: Payload, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", "x-content-type-options": "nosniff" },
  });
}

function blocked(code: string, status = 409): Response {
  return respond({ outcome: "BLOCKED", code }, status);
}

async function parseResponse(response: Response): Promise<unknown> {
  try { return await response.json(); } catch { return null; }
}

async function authorizedExecution(
  config: Config,
  fetchFn: Fetcher,
  executionId: string,
): Promise<{ execution?: Execution; error?: Response }> {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{10,127}$/.test(executionId)) {
    return { error: blocked("PROFILE_CONTINUATION_EXECUTION_ID_INVALID", 400) };
  }
  const endpoint = `${config.supabaseUrl}/rest/v1/lf_operation_execution?execution_id=eq.${encodeURIComponent(executionId)}&select=execution_id,status,operation_code,target_type,target_code,target_repo,target_path,manifest`;
  let response: Response;
  try {
    response = await fetchFn(endpoint, {
      method: "GET",
      headers: { apikey: config.serviceRoleKey, authorization: `Bearer ${config.serviceRoleKey}` },
      signal: AbortSignal.timeout(15_000),
    });
  } catch { return { error: blocked("PROFILE_CONTINUATION_READ_FAILED", 502) }; }
  if (!response.ok) return { error: blocked("PROFILE_CONTINUATION_READ_REJECTED", 502) };
  const rows = await parseResponse(response);
  if (!Array.isArray(rows) || rows.length !== 1 || !rows[0] || typeof rows[0] !== "object") {
    return { error: blocked("PROFILE_CONTINUATION_EXECUTION_NOT_FOUND", 404) };
  }
  const e = rows[0] as Execution;
  const m = e.manifest;
  const handoff = m?.router_profile_handoff as Record<string, unknown> | undefined;
  const receipt = handoff?.router_authorization_receipt as Record<string, unknown> | undefined;
  if (
    e.operation_code !== "EJECUCION_PERFIL_LF" || e.target_type !== "PERFIL" ||
    e.status !== "IN_PROGRESS" || e.target_repo !== config.repository ||
    !/^profiles\/[a-z0-9_-]+\/SKILL\.md$/.test(e.target_path) ||
    !NATIVE_EXECUTOR_PROVIDER_BY_MODE.has(`${m?.executor_mode}|${m?.executor_provider}`) ||
    m?.read_only !== true || m?.no_write !== true ||
    m?.no_promotion !== true || m?.governed_repair_write !== false ||
    handoff?.profile_code !== e.target_code || receipt?.profile_code !== e.target_code ||
    receipt?.profile_execution_allowed !== true || receipt?.effect_authority !== false
  ) return { error: blocked("PROFILE_CONTINUATION_GOVERNED_READ_ONLY_AUTHORITY_REQUIRED", 403) };
  return { execution: e };
}

async function rpc(config: Config, fetchFn: Fetcher, name: string, parameters: Payload): Promise<{ result?: Payload; error?: Response }> {
  let response: Response;
  try {
    response = await fetchFn(`${config.supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: config.serviceRoleKey,
        authorization: `Bearer ${config.serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(parameters),
      signal: AbortSignal.timeout(30_000),
    });
  } catch { return { error: blocked("PROFILE_CONTINUATION_RPC_TRANSPORT_FAILED", 502) }; }
  const data = await parseResponse(response);
  if (!response.ok || !data || typeof data !== "object" || Array.isArray(data)) {
    return { error: blocked("PROFILE_CONTINUATION_RPC_REJECTED", 502) };
  }
  return { result: data as Payload };
}

// Resolve only the existing post-model steps; never relax the pre-model 7-step guard.
async function resolveExistingPostModelStep(
  e: Execution,
  prepareResult: Payload,
  config: Config,
  fetchFn: Fetcher,
): Promise<Response | null> {
  if (
    prepareResult.status !== "BLOCKED" ||
    prepareResult.blocking_code !== "BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT" ||
    prepareResult.expected_clean_step_count !== 7 ||
    (prepareResult.clean_step_count !== 9 && prepareResult.clean_step_count !== 10)
  ) return null;

  const url = `${config.supabaseUrl}/rest/v1/lf_operation_execution_steps?execution_id=eq.${encodeURIComponent(e.execution_id)}&select=step_id,status&order=step_order.asc`;
  let response: Response;
  try {
    response = await fetchFn(url, {
      method: "GET",
      headers: { apikey: config.serviceRoleKey, authorization: `Bearer ${config.serviceRoleKey}` },
      signal: AbortSignal.timeout(15_000),
    });
  } catch { return blocked("PROFILE_POST_MODEL_STEP_READ_FAILED", 502); }
  if (!response.ok) return blocked("PROFILE_POST_MODEL_STEP_READ_REJECTED", 502);
  const rows = await parseResponse(response);
  if (!Array.isArray(rows)) return blocked("PROFILE_POST_MODEL_STEPS_INVALID", 409);

  const steps = new Map<string, string>();
  for (const row of rows) {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      return blocked("PROFILE_POST_MODEL_STEPS_INVALID", 409);
    }
    const item = row as Record<string, unknown>;
    if (typeof item.step_id !== "string" || typeof item.status !== "string" || steps.has(item.step_id)) {
      return blocked("PROFILE_POST_MODEL_STEPS_INVALID", 409);
    }
    steps.set(item.step_id, item.status);
  }
  const completed = [
    "init_execution", "router", "profile_resolve", "profile_source_read",
    "input_validate", "context_admission", "research_baseline_freeze",
    "execute_profile", "output_validate",
  ];
  const semanticStatus = steps.get("semantic_judge");
  // The prepare RPC counts CLEAN steps, not rows: a failed semantic attempt
  // is the tenth row while only the first nine steps are clean.
  const expectedClean = completed.length + (semanticStatus === "STEP_PASS_WITH_EVIDENCE" ? 1 : 0);
  if (
    (steps.size !== 9 && steps.size !== 10) ||
    steps.size !== completed.length + (semanticStatus === undefined ? 0 : 1) ||
    prepareResult.clean_step_count !== expectedClean ||
    !completed.every(step => steps.get(step) === "STEP_PASS_WITH_EVIDENCE") ||
    [...steps.keys()].some(step => step !== "semantic_judge" && !completed.includes(step)) ||
    steps.has("report_output")
  ) return blocked("PROFILE_POST_MODEL_STEPS_NOT_CLEAN", 409);

  let nextStep: string;
  let phase: string;
  if (steps.size === 9 && semanticStatus === undefined) {
    nextStep = "semantic_judge";
    phase = "INDEPENDENT_SEMANTIC_JUDGE_REQUIRED";
  } else if (steps.size === 10 &&
             (semanticStatus === "BLOCKED_STEP_NOT_CLEAN" || semanticStatus === "RETURN_TO_ROUTER")) {
    // Only the canonical step-70 recorder may replace a blocked/return attempt.
    nextStep = "semantic_judge";
    phase = "INDEPENDENT_SEMANTIC_JUDGE_REQUIRED";
  } else if (steps.size === 10 && semanticStatus === "STEP_PASS_WITH_EVIDENCE") {
    nextStep = "report_output";
    phase = "REPORT_OUTPUT_REQUIRED";
  } else {
    return blocked("PROFILE_POST_MODEL_STEPS_NOT_CLEAN", 409);
  }
  return respond({
    outcome: "CONTINUATION_REQUIRED",
    phase,
    code: null,
    execution_id: e.execution_id,
    profile_code: e.target_code,
    next_action: nextStep === "semantic_judge"
      ? "PRODUCE_EVIDENCED_V3_AND_SUBMIT_GOVERNED_CONTINUATION"
      : "RECORD_EXISTING_REPORT_OUTPUT",
    governed_continuation: nextStep === "semantic_judge" ? {
      transport: "EXISTING_GITHUB_ISSUE_OIDC_EDGE",
      schema_version: "LF_PROFILE_NATIVE_RESUME_REQUEST_V1",
      payload_field: "semantic_judge_review",
      issue_label: "lf-profile-resume-governed",
      reuse_execution_id: true,
      owner_reauthorization_required: false,
      credential_route: "GITHUB_OIDC_TO_EDGE_ONLY",
      completion_status: "NOT_COMPLETE",
    } : null,
    result: {
      status: phase,
      last_completed_step: nextStep === "semantic_judge" ? "output_validate" : "semantic_judge",
      next_step: nextStep,
      clean_step_count: prepareResult.clean_step_count,
      execution_id: e.execution_id,
    },
  });
}

async function githubGet(fetchFn: Fetcher, path: string): Promise<{ ok: boolean; data: unknown }> {
  try {
    const r = await fetchFn(`${GITHUB_API}${path}`, {
      method: "GET",
      headers: { accept: "application/vnd.github+json", "x-github-api-version": "2022-11-28", "user-agent": "lf-profile-skill-context-resolver-v1" },
      signal: AbortSignal.timeout(15_000),
    });
    return { ok: r.ok, data: await parseResponse(r) };
  } catch { return { ok: false, data: null }; }
}

// The skill child execution needs the same trusted starting context a Profile Update init execution gets:
// the current main revision and the exact target blob. They are resolved here, from GitHub, and any value the
// request supplied under the reserved key is discarded.
async function trustedSkillContext(
  config: Config, fetchFn: Fetcher, skillCode: string, targetCode: unknown, targetPath: string, callerIdentity: CallerIdentity | undefined,
): Promise<{ context?: Payload; error?: Response }> {
  if (!callerIdentity) return { error: blocked("PROFILE_SKILL_CALLER_IDENTITY_MISSING", 500) };
  const validTargetPath = skillCode === "SKILL_UPDATE_APPLY"
    ? SKILL_UPDATE_TARGET_PATH_RE.test(targetPath)
    : SKILL_TARGET_PATH_RE.test(targetPath);
  if (!validTargetPath || targetPath.includes("..") || targetPath.includes("//")) {
    return { error: blocked("PROFILE_SKILL_TARGET_PATH_INVALID", 400) };
  }
  const ref = await githubGet(fetchFn, `/repos/${config.repository}/git/ref/heads/main`);
  const mainSha = String(((ref.data as Payload | null)?.object as Payload | undefined)?.sha ?? "").toLowerCase();
  if (!ref.ok || !SHA40_RE.test(mainSha)) return { error: blocked("PROFILE_SKILL_MAIN_REVISION_UNRESOLVED", 502) };
  const encoded = targetPath.split("/").map(encodeURIComponent).join("/");
  const target = await githubGet(fetchFn, `/repos/${config.repository}/contents/${encoded}?ref=${mainSha}`);
  if (!target.ok || !target.data || Array.isArray(target.data)) return { error: blocked("PROFILE_SKILL_EXACT_TARGET_FILE_REQUIRED", 409) };
  const blob = String((target.data as Payload).sha ?? "").toLowerCase();
  if (!SHA40_RE.test(blob)) return { error: blocked("PROFILE_SKILL_TARGET_BLOB_UNRESOLVED", 502) };
  let githubOwner: Payload | null = null;
  if (skillCode === "SKILL_UPDATE_APPLY") {
    // Currentness is read from the exact same GitHub main tree as target_blob_sha.
    // SQL independently verifies historical 14/14 skill ownership and asset status.
    if (typeof targetCode !== "string" || !/^[A-Z][A-Z0-9_-]{3,159}$/.test(targetCode)) {
      return { error: blocked("SKILL_UPDATE_TARGET_CODE_INVALID", 400) };
    }
    const root = targetPath.split("/").slice(0, 2).join("/");
    const readmePath = root + "/README.md";
    const readme = await githubGet(fetchFn,
      `/repos/${config.repository}/contents/${readmePath.split("/").map(encodeURIComponent).join("/")}?ref=${mainSha}`);
    if (!readme.ok || !readme.data || Array.isArray(readme.data)) {
      return { error: blocked("SKILL_UPDATE_OWNER_README_UNAVAILABLE", 409) };
    }
    const doc = readme.data as Payload;
    const readmeSha = typeof doc.sha === "string" ? doc.sha.toLowerCase() : "";
    if (doc.type !== "file" || !SHA40_RE.test(readmeSha) ||
        doc.encoding !== "base64" || typeof doc.content !== "string" ||
        doc.content.length > 180000) {
      return { error: blocked("SKILL_UPDATE_OWNER_README_INVALID", 409) };
    }
    let content = "";
    try {
      const bytes = Uint8Array.from(atob(doc.content.replace(/\s/g, "")), c => c.charCodeAt(0));
      content = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch {
      return { error: blocked("SKILL_UPDATE_OWNER_README_INVALID", 409) };
    }
    // A historical citation is not an owner declaration. Require one explicit
    // line declaring the governing asset, rather than a mere code occurrence.
    const ownerMatch = content.match(/(?:^|\n)\s*(?:[-*]\s*)?(ACT-[0-9]{4,})\s+is\s+the\s+governing\s+asset\b/i)
      ?? content.match(/(?:^|\n)\s*(?:[-*]\s*)?(?:source|governing)\s+authority\s*:\s*(ACT-[0-9]{4,})\b/i);
    if (ownerMatch?.[1]?.toUpperCase() !== targetCode) {
      return { error: blocked("SKILL_UPDATE_OWNER_DECLARATION_MISMATCH", 409) };
    }
    githubOwner = { asset_code: targetCode, root_path: root,
      readme_path: readmePath, readme_blob_sha: readmeSha, main_sha: mainSha };
  }
  return { context: { main_sha: mainSha, target_blob_sha: blob, caller: { ...callerIdentity },
    ...(githubOwner ? { github_owner: githubOwner } : {}) } };
}

async function invokeSkill(e: Execution, body: Payload, config: Config, fetchFn: Fetcher, callerIdentity?: CallerIdentity): Promise<Response> {
  const skill = body.skill_code;
  const input = body.input;
  if (typeof skill !== "string" || !SKILL_CODE_RE.test(skill)) return blocked("PROFILE_SKILL_CODE_INVALID", 400);
  if (!input || typeof input !== "object" || Array.isArray(input) || JSON.stringify(input).length > MAX_SKILL_INPUT_BYTES) {
    return blocked("PROFILE_SKILL_INPUT_INVALID", 400);
  }
  // "_trusted" is reserved for this transport: whatever the request put there is dropped.
  const { _trusted: _discarded, ...cleanInput } = input as Payload;
  let skillInput: Payload = cleanInput;
  if (typeof cleanInput.target_path === "string") {
    const resolved = await trustedSkillContext(config, fetchFn, skill, cleanInput.target_code, cleanInput.target_path, callerIdentity);
    if (resolved.error) return resolved.error;
    skillInput = { ...cleanInput, _trusted: resolved.context };
  }
  let response: Response;
  try {
    response = await fetchFn(`${config.supabaseUrl}/rest/v1/rpc/lf_skill_invoke_v1`, {
      method: "POST",
      headers: { apikey: config.serviceRoleKey, authorization: `Bearer ${config.serviceRoleKey}`, "content-type": "application/json" },
      // The parent is always the authenticated, read-only profile execution, never a caller-supplied id.
      body: JSON.stringify({ p_skill: skill, p_execution_id: e.execution_id, p_input: skillInput }),
      signal: AbortSignal.timeout(30_000),
    });
  } catch { return blocked("PROFILE_SKILL_INVOKE_TRANSPORT_FAILED", 502); }
  const data = await parseResponse(response) as Payload | null;
  if (!response.ok) {
    // The invoker raises explicit, human-readable block reasons (what is missing and where): pass them on.
    const detail = typeof data?.message === "string" ? data.message.slice(0, 400) : null;
    return respond({ outcome: "BLOCKED", code: "PROFILE_SKILL_INVOKE_REJECTED", skill_code: skill, execution_id: e.execution_id, detail }, 409);
  }
  return respond({ outcome: "SKILL_INVOKED", skill_code: skill, execution_id: e.execution_id, profile_code: e.target_code, result: data });
}

// Governed skill update steps through the EXISTING OIDC Edge and recorder.
// No Router dispatch, extra executor, model provider or product write.
const SKILL_UPDATE_PREWRITE_STEPS = [
 "router","skill_resolve","baseline_read","change_scope",
 "regression_plan","pre_write_execution_binding_gate",
] as const;


const SKILL_UPDATE_POSTWRITE_STEPS = [
 "github_write","github_readback","deterministic_validation","semantic_judge",
 "regression_after","close","report_output",
] as const;

// Same OIDC Edge, same operation-neutral SQL core; no additional writer or Router path.
async function recordSkillPostWriteSteps(
 parent:Execution,child:Execution,steps:Payload[],config:Config,fetchFn:Fetcher,
):Promise<Response>{
 const childId=child.execution_id;
 const ledgerUrl=config.supabaseUrl+"/rest/v1/lf_operation_execution_steps?execution_id=eq."+
   encodeURIComponent(childId)+"&select=step_order,step_id,status,evidence_payload&order=step_order.asc";
 const getLedger=async():Promise<Payload[]|null>=>{
   try{
     const r=await fetchFn(ledgerUrl,{method:"GET",headers:{
       apikey:config.serviceRoleKey,authorization:"Bearer "+config.serviceRoleKey,
     },signal:AbortSignal.timeout(15000)});
     const rows=await parseResponse(r);
     return r.ok&&Array.isArray(rows)?rows as Payload[]:null;
   }catch{return null;}
 };
 const existing=await getLedger();
 const pre=["init_execution","router","skill_resolve","baseline_read",
   "change_scope","regression_plan","pre_write_execution_binding_gate"];
 if(!existing||pre.some((name,i)=>existing.filter(row=>
     row.step_id===name&&row.step_order===i*10&&row.status==="STEP_PASS_WITH_EVIDENCE").length!==1))
   return blocked("SKILL_POST60_PREWRITE_LEDGER_INCOMPLETE");
 const gate=existing.find(r=>r.step_id==="pre_write_execution_binding_gate")?.evidence_payload as Payload|undefined;
 const plan=gate?.write_plan;
 const expected=Array.isArray(plan)&&plan.length===1?(plan[0] as Payload):null;
 if(!expected||expected.path!==child.target_path||
   typeof expected.content_sha256!=="string"||
   !/^[0-9a-f]{64}$/.test(expected.content_sha256)||
   child.manifest?.pre_write_bound_write_plan_sha256!==gate?.write_plan_hash||
   child.manifest?.pre_write_bound_main_revision!==gate?.bound_revision||
   child.manifest?.pre_write_bound_target_blob_sha!==gate?.source_blob_sha)
   return blocked("SKILL_POST60_FROZEN_PREWRITE_INVALID");
 const first=steps[0].evidence_payload as Payload;
 const prNumber=first.pr_number;
 if(!Number.isInteger(prNumber)||Number(prNumber)<1)
   return blocked("SKILL_POST60_PR_NUMBER_REQUIRED",400);
 if(steps.some(item=>(item.evidence_payload as Payload).pr_number!==prNumber))
   return blocked("SKILL_POST60_PR_IDENTITY_DRIFT",400);
 const api="/repos/"+config.repository;
 const prRes=await githubGet(fetchFn,api+"/pulls/"+prNumber);
 if(!prRes.ok||!prRes.data||typeof prRes.data!=="object")
   return blocked("SKILL_POST60_PR_UNRESOLVED",502);
 const pr=prRes.data as Payload;
 const head=pr.head as Payload|undefined,base=pr.base as Payload|undefined;
 const headRepo=head?.repo as Payload|undefined;
 const headSha=head?.sha;
 if(pr.number!==prNumber||headRepo?.full_name!==config.repository||
   base?.ref!=="main"||typeof head?.ref!=="string"||
   !/^[A-Za-z0-9_./-]{3,180}$/.test(head.ref)||
   typeof headSha!=="string"||!SHA40_RE.test(headSha)||
   typeof gate?.bound_revision!=="string")
   return blocked("SKILL_POST60_PR_BINDING_DRIFT");

 // Main may advance for this very Edge fix. Rebind only when the skill's
 // canonical baseline blob and declared owner README have not changed.
 if(pr.merged!==true){
   const current=await githubGet(fetchFn,api+"/git/ref/heads/main");
   const mainSha=String(((current.data as Payload|null)?.object as Payload|undefined)?.sha??"");
   if(!current.ok||!SHA40_RE.test(mainSha))
     return blocked("SKILL_POST60_MAIN_READBACK_FAILED");
   const source=await githubGet(fetchFn,api+"/contents/"+
     child.target_path.split("/").map(encodeURIComponent).join("/")+"?ref="+mainSha);
   const rootPath=child.target_path.split("/").slice(0,2).join("/");
   const owner=await githubGet(fetchFn,api+"/contents/"+
     rootPath+"/README.md?ref="+mainSha);
   const prov=child.manifest?.owner_provenance as Payload|undefined;
   if(!source.ok||!owner.ok||
      (source.data as Payload)?.sha!==gate?.source_blob_sha||
      (owner.data as Payload)?.sha!==prov?.readme_blob_sha)
     return blocked("SKILL_POST60_BASELINE_OR_OWNER_DRIFT");
 }
 const filename=child.target_path.split("/").map(encodeURIComponent).join("/");
 const fileRes=await githubGet(fetchFn,api+"/contents/"+filename+"?ref="+headSha);
 const file=fileRes.data as Payload|null;
 if(!fileRes.ok||!file||Array.isArray(file)||file.type!=="file"||
   file.encoding!=="base64"||typeof file.content!=="string"||
   !SHA40_RE.test(String(file.sha??""))||file.content.length>500000)
   return blocked("SKILL_POST60_TARGET_NOT_READABLE",502);
 let sha256="";
 try{
   const bytes=Uint8Array.from(atob(file.content.replace(/\s/g,"")),c=>c.charCodeAt(0));
   const digest=await crypto.subtle.digest("SHA-256",bytes);
   sha256=Array.from(new Uint8Array(digest)).map(x=>x.toString(16).padStart(2,"0")).join("");
 }catch{return blocked("SKILL_POST60_CONTENT_HASH_FAILED",502);}
 if(sha256!==expected.content_sha256)
   return blocked("SKILL_POST60_CANDIDATE_SHA256_MISMATCH");
 const files=await githubGet(fetchFn,api+"/pulls/"+prNumber+"/files?per_page=100");
 if(!files.ok||!Array.isArray(files.data)||files.data.length<1||files.data.length>20)
   return blocked("SKILL_POST60_PR_FILE_SCOPE_UNPROVEN",502);
 const paths=files.data.map(v=>String((v as Payload).filename??""));
 const root=child.target_path.split("/").slice(0,-1).join("/");
 if(!paths.includes(child.target_path)||paths.some(p=>
    p!==child.target_path&&!(p.startsWith(root+"/")&&
      /^test_[A-Za-z0-9_.-]+\.py$/.test(p.slice(root.length+1)))))
   return blocked("SKILL_POST60_PR_SCOPE_EXCEEDED");
 const verifyRun=async(runId:unknown,name:string,sha:string):Promise<boolean>=>{
   if(!Number.isInteger(runId)||Number(runId)<=0)return false;
   const r=await githubGet(fetchFn,api+"/actions/runs/"+runId);
   const run=r.data as Payload|null;
   return !!(r.ok&&run&&run.name===name&&run.status==="completed"&&
     run.conclusion==="success"&&run.head_sha===sha);
 };
 let completed=0;
 const receipts:Payload[]=[];
 for(const item of steps){
   const step=String(item.step_id);
   const input=item.evidence_payload as Payload;
   if(input.blocking_codes&&(!Array.isArray(input.blocking_codes)||input.blocking_codes.length))
     return blocked("SKILL_POST60_INPUT_BLOCKERS_NOT_CLEAN");
   const prior=await getLedger();
   if(!prior)return blocked("SKILL_POST60_READBACK_FAILED",502);
   const index=SKILL_UPDATE_POSTWRITE_STEPS.indexOf(step as typeof SKILL_UPDATE_POSTWRITE_STEPS[number]);
   const earlier=SKILL_UPDATE_POSTWRITE_STEPS.slice(0,index);
   if(earlier.some(s=>prior.filter(r=>r.step_id===s&&r.status==="STEP_PASS_WITH_EVIDENCE").length!==1))
     return blocked("SKILL_POST60_PRIOR_STEP_MISSING");
   if((step==="github_write"||step==="github_readback")&&
      ((input.commit_sha&&input.commit_sha!==headSha)||
       (input.exact_head&&input.exact_head!==headSha)||
       (input.branch&&input.branch!==head.ref)))
     return blocked("SKILL_POST60_GITHUB_RECEIPT_MISMATCH");
   if(step==="deterministic_validation"||step==="regression_after"){
     if(!await verifyRun(input.pase_run_id,"PASE",headSha))
       return blocked("SKILL_POST60_PASE_EXACT_HEAD_REQUIRED");
     const qa=await githubGet(fetchFn,api+"/actions/runs/"+input.test_run_id);
     const run=qa.data as Payload|null;
     if(!qa.ok||!run||run.name!=="LF S26 Native Validator Binding Regression"||
       run.status!=="completed"||run.conclusion!=="success"||
       !SHA40_RE.test(String(run.head_sha??"")))
       return blocked("SKILL_POST60_TEST_RUN_NOT_VERIFIED");
     for(const path of paths){
       const p=path.split("/").map(encodeURIComponent).join("/");
       const old=await githubGet(fetchFn,api+"/contents/"+p+"?ref="+run.head_sha);
       const now=await githubGet(fetchFn,api+"/contents/"+p+"?ref="+headSha);
       if(!old.ok||!now.ok||(old.data as Payload)?.sha!==(now.data as Payload)?.sha)
         return blocked("SKILL_POST60_QA_SOURCE_DRIFT");
     }
   }
   if(step==="semantic_judge"){
     const review=input.semantic_judge_result as Payload|undefined;
     if(!review||review.review_mode!=="CURRENT_CONTEXT_REVIEW"||
       review.independent_review_attested!==false||
       review.verdict!=="PASS_REVIEWED_CURRENT_CONTEXT"||
       !Array.isArray(input.coverage_manifest)||input.coverage_manifest.length<1||
       !Array.isArray(input.authority_checks)||input.authority_checks.length<1||
       !Array.isArray(input.directionality_checks)||input.directionality_checks.length<1||
       !Array.isArray(input.upstream_validity_checks)||input.upstream_validity_checks.length<1||
       typeof input.evidence_ceiling_check!=="string"||
       input.router_direct_consistency!=="NOT_TESTED / not_applicable / ROUTER_ONLY")
       return blocked("SKILL_POST60_SEMANTIC_EVIDENCE_INCOMPLETE");
   }
   if(step==="close"||step==="report_output"){
     if(pr.merged!==true||!SHA40_RE.test(String(pr.merge_commit_sha??""))||
       child.manifest?.runtime_write_executed!==false||
       child.manifest?.automatic_runtime_promotion!==false||
       !Array.isArray(input.open_blockers)||input.open_blockers.length!==0)
       return blocked("SKILL_POST60_CLOSE_NOT_AUTHORIZED");
   }
   const attested:Payload={...input,
     pr_number:prNumber,git_commit_sha:headSha,source_sha256:sha256,
     candidate_path:child.target_path,verification_source:"EXISTING_OIDC_EDGE_GITHUB_API",
     blocking_codes:[]};
   if(step==="github_write")
     Object.assign(attested,{branch:head.ref,written_files:paths,
       commit_sha:headSha,identity_preserved:true});
   if(step==="github_readback")
     Object.assign(attested,{exact_head:headSha,readback_files:paths,
       sha_match:true,identity_preserved:true});
   if(step==="close")
     Object.assign(attested,{all_required_steps_clean:true,open_blockers:[],
       runtime_unchanged:true,no_auto_promotion:true});
   if(step==="report_output")
     Object.assign(attested,{exact_head:headSha,open_blockers:[],
       next_gate:input.next_gate??"RETURN_TO_PARENT_PROFILE"});
   const receipt=await rpc(config,fetchFn,"lf_record_operation_step_core_v1",{
      p_execution_id:childId,p_step_id:step,p_evidence_ref:item.evidence_ref,
      p_evidence_payload:attested,p_actor_execution_id:parent.execution_id,
      p_expected_operation_code:"ACTUALIZACION_SKILL_LF",
      p_expected_target_type:"SKILL",p_contract_status:"ACTIVE_ENFORCEMENT",
      p_binding_status:"ACTIVE_ENFORCEMENT",p_judge_status:"ACTIVE_ENFORCEMENT",
      p_trust_validation:{valid:true,source:"OIDC_EDGE_GITHUB_VERIFIED",
        server_assertions:[],server_hard_fails:[],verified_head_sha:headSha,
        verified_sha256:sha256},
      p_close_on_report_output:step==="report_output",
      p_recorder_name:"lf_skill_update_post60_existing_core_oidc_v1",
   });
   if(receipt.error||receipt.result?.outcome!=="STEP_RECORDED"||
     receipt.result?.status!=="STEP_PASS_WITH_EVIDENCE")
     return blocked(String(receipt.result?.code??"SKILL_POST60_CORE_REJECTED"));
   const back=await getLedger();
   if(!back||back.filter(r=>r.step_id===step&&
     r.status==="STEP_PASS_WITH_EVIDENCE").length!==1)
     return blocked("SKILL_POST60_STEP_READBACK_FAILED");
   completed++;
   receipts.push({step_id:step,status:"STEP_PASS_WITH_EVIDENCE"});
 }
 const last=String(steps[steps.length-1].step_id);
 return respond({outcome:"SKILL_CHILD_STEP_BATCH_RECORDED",
   execution_id:parent.execution_id,child_execution_id:childId,steps_recorded:completed,
   steps:receipts,next_step:last==="report_output"?"RETURN_TO_PARENT_PROFILE":
     SKILL_UPDATE_POSTWRITE_STEPS[
       SKILL_UPDATE_POSTWRITE_STEPS.indexOf(last as typeof SKILL_UPDATE_POSTWRITE_STEPS[number])+1],
   child_completed:last==="report_output",no_file_write:true});
}

async function recordSkillChildSteps(
 parent:Execution,body:Payload,config:Config,fetchFn:Fetcher,identity?:CallerIdentity,
):Promise<Response>{
 if(!identity)return blocked("SKILL_CHILD_STEP_OIDC_IDENTITY_REQUIRED",403);
 const childId=body.child_execution_id, steps=body.steps;
 if(typeof childId!=="string" || !/^EXEC-SKILL-[A-Za-z0-9]{12,40}$/.test(childId) ||
    !Array.isArray(steps)||steps.length===0||steps.length>7||JSON.stringify(steps).length>52000){
   return blocked("SKILL_CHILD_STEP_BATCH_INPUT_INVALID",400);
 }
 const positions:number[]=[];
 for(const item of steps){
   if(!item||typeof item!=="object"||Array.isArray(item))
     return blocked("SKILL_CHILD_STEP_ITEM_INVALID",400);
   const step=item as Payload;
   if(Object.keys(step).sort().join(",")!=="evidence_payload,evidence_ref,step_id" ||
     typeof step.step_id!=="string" ||
     !([...SKILL_UPDATE_PREWRITE_STEPS,...SKILL_UPDATE_POSTWRITE_STEPS] as readonly string[]).includes(step.step_id) ||
     typeof step.evidence_ref!=="string"||step.evidence_ref.length<1||step.evidence_ref.length>1500||
     !step.evidence_payload||typeof step.evidence_payload!=="object"||
     Array.isArray(step.evidence_payload)||JSON.stringify(step.evidence_payload).length>44000)
     return blocked("SKILL_CHILD_STEP_ITEM_INVALID",400);
   const p=step.evidence_payload as Payload;
   if(["server_assertions","server_hard_fails","trust_validation","derived_result",
        "derived_by_judge","step_result","mini_judge_result"].some(
         k=>Object.prototype.hasOwnProperty.call(p,k)))
     return blocked("SKILL_CHILD_STEP_ASSERTION_INJECTION",400);
   positions.push(([...SKILL_UPDATE_PREWRITE_STEPS,...SKILL_UPDATE_POSTWRITE_STEPS] as readonly string[]).indexOf(step.step_id));
 }
 if(positions.some((v,i)=>i>0&&v<=positions[i-1])||
    (positions[0]<SKILL_UPDATE_PREWRITE_STEPS.length&&
     positions[positions.length-1]>=SKILL_UPDATE_PREWRITE_STEPS.length))
   return blocked("SKILL_CHILD_STEP_BATCH_ORDER_INVALID",400);

 const endpoint=config.supabaseUrl+"/rest/v1/lf_operation_execution?execution_id=eq."+
   encodeURIComponent(childId)+
   "&select=execution_id,status,operation_code,target_type,target_code,target_repo,target_path,created_by_execution_id,manifest";
 let res:Response;
 try{
   res=await fetchFn(endpoint,{method:"GET",
     headers:{apikey:config.serviceRoleKey,authorization:"Bearer "+config.serviceRoleKey},
     signal:AbortSignal.timeout(15000)});
 }catch{return blocked("SKILL_CHILD_STEP_EXECUTION_READ_FAILED",502);}
 if(!res.ok)return blocked("SKILL_CHILD_STEP_EXECUTION_READ_FAILED",502);
 const rows=await parseResponse(res);
 if(!Array.isArray(rows)||rows.length!==1||!rows[0]||typeof rows[0]!=="object")
   return blocked("SKILL_CHILD_STEP_EXECUTION_UNRESOLVED",404);
 const child=rows[0] as Execution & {created_by_execution_id?:string};
 const handoff=child.manifest?.profile_handoff as Payload|undefined;
 if(child.execution_id!==childId||child.operation_code!=="ACTUALIZACION_SKILL_LF"||
   child.target_type!=="SKILL"||child.target_code!=="ACT-0045"||
   child.status!=="IN_PROGRESS"||child.target_repo!==config.repository||
   !SKILL_UPDATE_TARGET_PATH_RE.test(child.target_path)||
   child.target_path.includes("..")||child.target_path.includes("//")||
   child.created_by_execution_id!==parent.execution_id||
   handoff?.source_execution_id!==parent.execution_id||
   child.manifest?.router_governed_caller_code!=="CALLER-GHA-NATIVE-SKILL-UPDATE-V1")
   return blocked("SKILL_CHILD_STEP_PARENT_CHILD_AUTHORITY_MISMATCH",403);

 if(positions[0]>=SKILL_UPDATE_PREWRITE_STEPS.length)
   return recordSkillPostWriteSteps(parent,child,steps as Payload[],config,fetchFn);
 const proof=await trustedSkillContext(config,fetchFn,"SKILL_UPDATE_APPLY",
   child.target_code,child.target_path,identity);
 if(proof.error||!proof.context)
   return proof.error??blocked("SKILL_CHILD_STEP_CONTEXT_UNRESOLVED",409);
 let completed=0;
 const receipts:Payload[]=[];
 for(const item of steps){
   const step=item as Payload;
   const recorded=await rpc(config,fetchFn,"lf_skill_update_child_step_v1",{
     p_parent:parent.execution_id,p_child:childId,p_step:step.step_id,
     p_evidence_ref:step.evidence_ref,p_evidence:step.evidence_payload,
     p_server_context:proof.context,
   });
   if(recorded.error)return respond({outcome:"BLOCKED",code:"SKILL_CHILD_STEP_RPC_DENIED",
     execution_id:parent.execution_id,child_execution_id:childId,
     failed_step:step.step_id,steps_recorded:completed},502);
   const result=recorded.result;
   if(result?.outcome!=="STEP_RECORDED"||result.status!=="STEP_PASS_WITH_EVIDENCE"||
     result.step_id!==step.step_id)
     return respond({outcome:"BLOCKED",code:result?.code??"SKILL_CHILD_STEP_NOT_CLEAN",
       execution_id:parent.execution_id,child_execution_id:childId,
       failed_step:step.step_id,steps_recorded:completed},409);
   completed++;
   receipts.push({step_id:step.step_id,status:result.status,replay:result.replay===true});
 }
 // Read back from the same canonical operation ledger rather than trusting
 // the RPC success body alone.
 const url=config.supabaseUrl+"/rest/v1/lf_operation_execution_steps?execution_id=eq."+
    encodeURIComponent(childId)+"&select=step_id,status";
 let back:Response;
 try{
   back=await fetchFn(url,{method:"GET",
     headers:{apikey:config.serviceRoleKey,authorization:"Bearer "+config.serviceRoleKey},
     signal:AbortSignal.timeout(15000)});
 }catch{return blocked("SKILL_CHILD_STEP_READBACK_TRANSPORT_FAILED",502);}
 if(!back.ok)return blocked("SKILL_CHILD_STEP_READBACK_REJECTED",502);
 const entries=await parseResponse(back);
 if(!Array.isArray(entries)||steps.some(item=>entries.filter((v:unknown)=>{
    if(!v||typeof v!=="object")return false;
    const row=v as Payload;
    return row.step_id===(item as Payload).step_id&&row.status==="STEP_PASS_WITH_EVIDENCE";
 }).length!==1))return blocked("SKILL_CHILD_STEP_READBACK_NOT_CLEAN",409);
 const last=positions[positions.length-1];
 return respond({outcome:"SKILL_CHILD_STEP_BATCH_RECORDED",
   execution_id:parent.execution_id,child_execution_id:childId,
   operation_code:"ACTUALIZACION_SKILL_LF",steps_recorded:completed,
   steps:receipts,next_step:last<SKILL_UPDATE_PREWRITE_STEPS.length-1
      ? SKILL_UPDATE_PREWRITE_STEPS[last+1] : "github_write_SEPARATE_GOVERNED_GATE",
   no_file_write:true,profile_completed:false,child_completed:false});
}

// Caller-verified, no credentials in body. The canonical SQL procedures
// perform original Router, Product RAW/validator/judge, source/currentness and
// exact promotion receipt checks. This transport NEVER signs a receipt.
async function handleRuleAuthority(
  e: Execution,
  body: Payload,
  config: Config,
  fetchFn: Fetcher,
  callerRevision: string,
  callerIdentity?: CallerIdentity,
): Promise<Response> {
  const trustedWorkflow =
    `${config.repository}/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main`;
  if (
    e.target_code !== "PERFIL-PRODUCT-DIRECTOR-LF" ||
    e.target_path !== "profiles/product_director_lf/SKILL.md"
  ) return blocked("RULE_AUTHORITY_PRODUCT_DIRECTOR_ONLY", 403);
  if (
    callerIdentity?.method !== "GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1" ||
    callerIdentity.repository !== config.repository ||
    callerIdentity.workflow_ref !== trustedWorkflow ||
    !/^[1-9][0-9]*$/.test(callerIdentity.run_id)
  ) return blocked("RULE_AUTHORITY_VERIFIED_OIDC_REQUIRED", 403);
  if (
    body.source_revision !== callerRevision ||
    typeof body.screen_code !== "string" ||
    !/^[A-Z][A-Z0-9_-]{3,63}$/.test(body.screen_code)
  ) return blocked("RULE_AUTHORITY_SOURCE_OR_SCREEN_INVALID", 400);

  const step = body.rule_authority_action;
  let procedure: string;
  let params: Payload = {
    p_execution_id: e.execution_id,
    p_screen_code: body.screen_code,
  };
  if (step === "MARK") {
    if (
      typeof body.evidence_ref !== "string" ||
      body.evidence_ref.length < 8 || body.evidence_ref.length > 1200
    ) return blocked("RULE_AUTHORITY_JUDGE_EVIDENCE_REQUIRED", 400);
    procedure = "lf_rule_authority_mark_refresh_v1";
    params = {...params, p_evidence_ref: body.evidence_ref};
  } else if (step === "REQUEST" || step === "COMPLETE") {
    if (
      typeof body.rule_code !== "string" ||
      !/^[A-Z0-9][A-Z0-9_-]{3,159}$/.test(body.rule_code)
    ) return blocked("RULE_AUTHORITY_EXACT_RULE_REQUIRED", 400);
    params = {...params, p_rule_code: body.rule_code};
    if (step === "REQUEST") {
      procedure = "lf_rule_promotion_request_eligible_v1";
    } else {
      if (
        typeof body.receipt_id !== "number" ||
        !Number.isSafeInteger(body.receipt_id) || body.receipt_id <= 0
      ) return blocked("RULE_AUTHORITY_VERIFIED_RECEIPT_ID_REQUIRED", 400);
      procedure = "lf_rule_promotion_complete_tracked_v1";
      params = {...params, p_receipt_id: body.receipt_id};
    }
  } else return blocked("RULE_AUTHORITY_ACTION_UNSUPPORTED", 400);

  const call = await rpc(config, fetchFn, procedure, params);
  if (call.error || !call.result) return call.error ?? blocked("RULE_AUTHORITY_RPC_UNAVAILABLE", 502);
  const result = call.result;
  const expected = step === "MARK" ? "MARKS_RECORDED" :
    step === "REQUEST" ? "WAIT_GOVERNED_ACTION_RECEIPT" : "APPLIED_VERIFIED";
  if (result.status !== expected) {
    return respond({
      outcome: "BLOCKED",
      code: result.code ?? result.blocking_code ?? "RULE_AUTHORITY_GOVERNED_OPERATION_BLOCKED",
      execution_id: e.execution_id,
      rule_authority_action: step,
      result,
    }, 409);
  }
  return respond({
    outcome: "RULE_AUTHORITY_GOVERNED_STEP_ACCEPTED",
    execution_id: e.execution_id,
    profile_code: e.target_code,
    rule_authority_action: step,
    result,
    no_router_mutation: true,
    independent_issuer_required: true,
    profile_completed: false,
  });
}

export async function handleProfileContinuation(
  action: string,
  body: Payload,
  config: Config,
  fetchFn: Fetcher,
  callerRevision: string,
  callerIdentity?: CallerIdentity,
): Promise<Response> {
  const executionId = typeof body.execution_id === "string" ? body.execution_id : "";
  const { execution: e, error } = await authorizedExecution(config, fetchFn, executionId);
  if (error || !e) return error ?? blocked("PROFILE_CONTINUATION_EXECUTION_NOT_FOUND");
  if (action === PROFILE_SOURCE_BIND_ACTION) {
    return respond({
      outcome: "SOURCE_BINDING_REQUIRED",
      execution_id: e.execution_id,
      profile_code: e.target_code,
      target_repo: e.target_repo,
      target_path: e.target_path,
      source_revision_required: callerRevision,
      next_action: "READ_PROFILE_AT_AUTHORIZED_SOURCE_REVISION",
    });
  }
  if (action === PROFILE_SKILL_INVOKE_ACTION) return await invokeSkill(e, body, config, fetchFn, callerIdentity);
  if (action === PROFILE_SKILL_STEP_BATCH_ACTION) return await recordSkillChildSteps(e, body, config, fetchFn, callerIdentity);
  if (action === PROFILE_RULE_AUTHORITY_ACTION) {
    return await handleRuleAuthority(e, body, config, fetchFn, callerRevision, callerIdentity);
  }
  if (action !== PROFILE_CONTINUE_ACTION) return blocked("PROFILE_CONTINUATION_ACTION_UNSUPPORTED", 400);
  const revision = body.source_revision;
  const digest = body.source_digest;
  if (
    typeof revision !== "string" || !/^[0-9a-f]{40}$/.test(revision) ||
    revision !== callerRevision ||
    typeof digest !== "string" || !/^sha256:[0-9a-f]{64}$/.test(digest)
  ) return blocked("PROFILE_CONTINUATION_SOURCE_BINDING_INVALID", 400);

  // The native prepare function enforces ordered checkpoints and validates
  // Router handoff, profile source, screen selection, IG and compact context.
  let prepared = await rpc(config, fetchFn, "lf_profile_native_bridge_prepare_v1", {
    p_execution_id: e.execution_id,
    p_source_revision: revision,
    p_source_digest: digest,
    p_actor_execution_id: e.execution_id,
  });
  if (prepared.error) return prepared.error;
  let result = prepared.result!;
  // Only an explicit semantic decision may bind a screen; one candidate is NOT
  // auto-selected. SQL rehydrates the current shortlist and judges the draft.
  if (Object.prototype.hasOwnProperty.call(body, "screen_selection_draft")) {
    if (result.status !== "SCREEN_SELECTION_REQUIRED") {
      return blocked("PROFILE_CONTINUATION_SCREEN_SELECTION_NOT_REQUESTED", 409);
    }
    const draft = body.screen_selection_draft;
    if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
      return blocked("PROFILE_CONTINUATION_SCREEN_SELECTION_DRAFT_INVALID", 400);
    }
    const submitted = await rpc(config, fetchFn, "lf_profile_screen_selector_semantic_submit_v1", {
      p_execution_id: e.execution_id,
      p_draft: draft,
      p_actor_execution_id: e.execution_id,
    });
    if (submitted.error) return submitted.error;
    if (!["BOUND", "ALREADY_BOUND"].includes(String(submitted.result?.status ?? ""))) {
      return respond({ outcome: "BLOCKED", code: "PROFILE_CONTINUATION_SCREEN_SELECTION_REJECTED", result: submitted.result }, 409);
    }
    prepared = await rpc(config, fetchFn, "lf_profile_native_bridge_prepare_v1", {
      p_execution_id: e.execution_id,
      p_source_revision: revision,
      p_source_digest: digest,
      p_actor_execution_id: e.execution_id,
    });
    if (prepared.error) return prepared.error;
    result = prepared.result!;
  }
  const semanticKeys = [
    "context_resolution_valid", "evidence_supported", "decision_resolves_objective",
    "authority_resolution_valid", "constraints_preserved", "claims_authorized",
    "materiality_handled_correctly", "tradeoff_defensible",
    "acceptance_detects_wrong_implementation", "handoff_implementation_ready",
    "router_direct_consistency", "counterfactual_trajectory",
  ];

  if (Object.prototype.hasOwnProperty.call(body, "semantic_judge_result")) {
    const semantic = body.semantic_judge_result;
    const semanticRef = body.semantic_evidence_ref;
    if (
      !semantic || typeof semantic !== "object" || Array.isArray(semantic) ||
      typeof semanticRef !== "string" || !semanticRef.startsWith("actions://")
    ) return blocked("PROFILE_NATIVE_SEMANTIC_SUBMISSION_INVALID", 400);

    const receipt = semantic as Payload;
    const review = receipt.judge_v3_evidence;
    const resultObj = receipt.result;
    const currentContext = receipt.review_mode === "CURRENT_CONTEXT_REVIEW";
    const expectedVerdict = currentContext ? "PASS_REVIEWED_CURRENT_CONTEXT" : "PASS_INDEPENDENT_SEMANTIC";
    const reviewerFactsValid = currentContext
      ? receipt.producer_independence_proven === false &&
        receipt.reviewer_is_producer === true && receipt.model_call_count === 0
      : (receipt.review_mode === undefined || receipt.review_mode === "INDEPENDENT_SEMANTIC") &&
        receipt.producer_independence_proven === true && receipt.model_call_count === 1;
    if (
      receipt.status !== "PASS" ||
      receipt.verdict !== expectedVerdict ||
      receipt.validator_status !== "PASS" ||
      !reviewerFactsValid ||
      typeof receipt.candidate_sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(receipt.candidate_sha256) ||
      typeof receipt.scope_packet_sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(receipt.scope_packet_sha256) ||
      !resultObj || typeof resultObj !== "object" || Array.isArray(resultObj) ||
      (resultObj as Payload).verdict !== expectedVerdict ||
      (resultObj as Payload).candidate_sha256 !== receipt.candidate_sha256 ||
      (resultObj as Payload).scope_packet_sha256 !== receipt.scope_packet_sha256 ||
      !Array.isArray((resultObj as Payload).unsupported_claims) ||
      ((resultObj as Payload).unsupported_claims as unknown[]).length !== 0 ||
      !Array.isArray((resultObj as Payload).blocking_codes) ||
      ((resultObj as Payload).blocking_codes as unknown[]).length !== 0 ||
      !review || typeof review !== "object" || Array.isArray(review)
    ) return blocked("PROFILE_NATIVE_SEMANTIC_RECEIPT_NOT_PASS", 409);

    const v3 = review as Payload;
    const checks = v3.decision_checks;
    if (
      v3.verdict !== expectedVerdict ||
      (currentContext
        ? v3.review_mode !== "CURRENT_CONTEXT_REVIEW" ||
          v3.reviewer_is_producer !== true ||
          v3.producer_independence_proven !== false || v3.model_call_count !== 0
        : v3.producer_independence_proven !== true || v3.model_call_count !== 1) ||
      v3.candidate_sha256 !== receipt.candidate_sha256 ||
      v3.scope_packet_sha256 !== receipt.scope_packet_sha256 ||
      !Array.isArray(v3.unsupported_claims) || v3.unsupported_claims.length !== 0 ||
      !Array.isArray(v3.blocking_codes) || v3.blocking_codes.length !== 0 ||
      !Array.isArray(v3.source_refs) || v3.source_refs.length === 0 ||
      !Array.isArray(v3.resolved_context_refs) || v3.resolved_context_refs.length === 0 ||
      !["PASS", "NOT_TESTED"].includes(String(v3.router_direct_consistency ?? "")) ||
      !v3.counterfactual_result ||
      !checks || typeof checks !== "object" || Array.isArray(checks) ||
      Object.keys(checks).sort().join("|") !== [...semanticKeys].sort().join("|")
    ) return blocked("PROFILE_NATIVE_SEMANTIC_V3_EVIDENCE_INVALID", 409);

    for (const key of semanticKeys) {
      const check = (checks as Payload)[key];
      if (!check || typeof check !== "object" || Array.isArray(check)) {
        return blocked("PROFILE_NATIVE_SEMANTIC_V3_CHECK_FAILED", 409);
      }
      const item = check as Payload;
      const refs = item.source_refs;
      if (typeof item.reason !== "string" || !item.reason.trim() ||
          !Array.isArray(refs) || refs.length === 0) {
        return blocked("PROFILE_NATIVE_SEMANTIC_V3_CHECK_FAILED", 409);
      }
      if (key === "router_direct_consistency" && v3.router_direct_consistency === "NOT_TESTED") {
        // No direct production route exists. NOT_TESTED is neither PASS nor divergence.
        if (item.result !== "not_applicable" || item.applicability !== "ROUTER_ONLY") {
          return blocked("PROFILE_NATIVE_ROUTER_ONLY_APPLICABILITY_INVALID", 409);
        }
      } else if (key === "router_direct_consistency") {
        const routerRef = item.router_execution_ref;
        const directRef = item.direct_execution_ref;
        if (![true, "true"].includes(item.result as true | string) ||
            item.applicability !== "AUTHORIZED_COMPARISON" ||
            typeof routerRef !== "string" || !routerRef.trim() ||
            typeof directRef !== "string" || !directRef.trim() ||
            directRef === routerRef ||
            !refs.includes(routerRef) || !refs.includes(directRef)) {
          return blocked("PROFILE_NATIVE_ROUTER_DIRECT_COMPARISON_UNPROVEN", 409);
        }
      } else if (![true, "true"].includes(item.result as true | string)) {
        return blocked("PROFILE_NATIVE_SEMANTIC_V3_CHECK_FAILED", 409);
      }
    }

    const recordedSemantic = await rpc(config, fetchFn, "lf_profile_native_bridge_record_semantic_v1", {
      p_execution_id: e.execution_id,
      p_semantic_judge_result: receipt,
      p_evidence_ref: semanticRef,
      p_actor_execution_id: e.execution_id,
    });
    if (recordedSemantic.error) return recordedSemantic.error;
    if (
      recordedSemantic.result?.status !== "SEMANTIC_JUDGE_RECORDED" ||
      Number(recordedSemantic.result?.clean_step_count ?? 0) !== 10
    ) {
      return respond({
        outcome: "BLOCKED",
        phase: "SEMANTIC_RECORD",
        code: recordedSemantic.result?.blocking_code ?? "PROFILE_NATIVE_SEMANTIC_RECORD_REJECTED",
        execution_id: e.execution_id,
        profile_code: e.target_code,
        result: recordedSemantic.result,
      }, 409);
    }

    const reportRef = `supabase://public.lf_operation_execution_steps/${e.execution_id}/report_output`;
    const recordedReport = await rpc(config, fetchFn, "lf_profile_native_bridge_record_report_v1", {
      p_execution_id: e.execution_id,
      p_evidence_ref: reportRef,
      p_actor_execution_id: e.execution_id,
    });
    if (recordedReport.error) return recordedReport.error;
    if (recordedReport.result?.status !== "PROFILE_EXECUTION_COMPLETED") {
      return respond({
        outcome: "BLOCKED",
        phase: "REPORT_RECORD",
        code: recordedReport.result?.blocking_code ?? "PROFILE_NATIVE_REPORT_RECORD_REJECTED",
        execution_id: e.execution_id,
        profile_code: e.target_code,
        result: recordedReport.result,
      }, 409);
    }
    return respond({
      outcome: "TERMINAL",
      phase: "PROFILE_EXECUTION_COMPLETED",
      code: null,
      execution_id: e.execution_id,
      profile_code: e.target_code,
      next_gate: recordedReport.result?.next_gate ?? "RETURN_TO_ROUTER",
      result: recordedReport.result,
    });
  }

  if (body.finalize_report === true) {
    const reportRef = `supabase://public.lf_operation_execution_steps/${e.execution_id}/report_output`;
    const recordedReport = await rpc(config, fetchFn, "lf_profile_native_bridge_record_report_v1", {
      p_execution_id: e.execution_id,
      p_evidence_ref: reportRef,
      p_actor_execution_id: e.execution_id,
    });
    if (recordedReport.error) return recordedReport.error;
    if (recordedReport.result?.status !== "PROFILE_EXECUTION_COMPLETED") {
      return respond({
        outcome: "BLOCKED",
        phase: "REPORT_RECORD",
        code: recordedReport.result?.blocking_code ?? "PROFILE_NATIVE_REPORT_RECORD_REJECTED",
        execution_id: e.execution_id,
        profile_code: e.target_code,
        result: recordedReport.result,
      }, 409);
    }
    return respond({
      outcome: "TERMINAL",
      phase: "PROFILE_EXECUTION_COMPLETED",
      code: null,
      execution_id: e.execution_id,
      profile_code: e.target_code,
      next_gate: recordedReport.result?.next_gate ?? "RETURN_TO_ROUTER",
      result: recordedReport.result,
    });
  }

  // The pre-model bridge must never be reentered to complete an existing 9/11
  // or 10/11 execution. Read canonical step states and hand off the next gate.
  const postModel = await resolveExistingPostModelStep(e, result, config, fetchFn);
  if (postModel) return postModel;

  // Post-model submission is accepted only from this already-authorized OIDC
  // continuation transport. The model supplies only its RAW profile output;
  // deterministic validity must come from the source-bound canonical runner.
  if (Object.prototype.hasOwnProperty.call(body, "profile_output")) {
    if (result.status !== "NATIVE_MODEL_INPUT_READY") {
      return blocked("PROFILE_NATIVE_OUTPUT_NOT_REQUESTED", 409);
    }
    const profileOutput = body.profile_output;
    const validation = body.validation_result;
    const rawEvidenceRef = body.raw_evidence_ref;
    const validatorEvidenceRef = body.validator_evidence_ref;
    if (
      !profileOutput || typeof profileOutput !== "object" || Array.isArray(profileOutput) ||
      !validation || typeof validation !== "object" || Array.isArray(validation) ||
      typeof rawEvidenceRef !== "string" || !rawEvidenceRef.startsWith("actions://") ||
      typeof validatorEvidenceRef !== "string" || !validatorEvidenceRef.startsWith("actions://")
    ) return blocked("PROFILE_NATIVE_OUTPUT_SUBMISSION_INVALID", 400);

    const receipt = validation as Payload;
    const blockingCodes = receipt.blocking_codes;
    const validatorErrors = receipt.validator_errors;
    if (
      receipt.schema !== "PROFILE_OUTPUT_VALIDATION_RESULT_V1" ||
      receipt.status !== "CANDIDATE_OUTPUT_PARITY_OBSERVED" ||
      receipt.structural_check_executed !== true ||
      receipt.profile_validator_executed !== true ||
      receipt.source_readback_matched !== true ||
      receipt.independent_review_executed !== false ||
      receipt.provider_attested !== false ||
      receipt.admission_authorized !== false ||
      receipt.profile_write_authorized !== false ||
      receipt.runtime_activation_authorized !== false ||
      !Array.isArray(blockingCodes) || blockingCodes.length !== 0 ||
      !Array.isArray(validatorErrors) || validatorErrors.length !== 0 ||
      typeof receipt.raw_output_sha256 !== "string" ||
      !/^[0-9a-f]{64}$/.test(receipt.raw_output_sha256)
    ) return blocked("PROFILE_NATIVE_OUTPUT_VALIDATOR_RECEIPT_NOT_PASS", 409);

    const recorded = await rpc(config, fetchFn, "lf_profile_native_bridge_record_output_v1", {
      p_execution_id: e.execution_id,
      p_profile_output: profileOutput,
      p_validation: {
        valid: true,
        errors: validatorErrors,
        blocking_codes: blockingCodes,
        source_bound_validation: receipt,
      },
      p_raw_evidence_ref: rawEvidenceRef,
      p_validator_evidence_ref: validatorEvidenceRef,
      p_actor_execution_id: e.execution_id,
    });
    if (recorded.error) return recorded.error;
    if (recorded.result?.status !== "NATIVE_PRODUCER_VALIDATED") {
      return respond({
        outcome: "BLOCKED",
        phase: "OUTPUT_RECORD",
        code: recorded.result?.blocking_code ?? "PROFILE_NATIVE_OUTPUT_RECORD_REJECTED",
        execution_id: e.execution_id,
        profile_code: e.target_code,
        result: recorded.result,
      }, 409);
    }
    return respond({
      outcome: "CONTINUATION_REQUIRED",
      phase: "INDEPENDENT_SEMANTIC_JUDGE_REQUIRED",
      code: null,
      execution_id: e.execution_id,
      profile_code: e.target_code,
      next_action: "PRODUCE_EVIDENCED_V3_AND_SUBMIT_GOVERNED_CONTINUATION",
      governed_continuation: {
        transport: "EXISTING_GITHUB_ISSUE_OIDC_EDGE",
        schema_version: "LF_PROFILE_NATIVE_RESUME_REQUEST_V1",
        payload_field: "semantic_judge_review",
        issue_label: "lf-profile-resume-governed",
        reuse_execution_id: true,
        owner_reauthorization_required: false,
        credential_route: "GITHUB_OIDC_TO_EDGE_ONLY",
        completion_status: "NOT_COMPLETE",
      },
      result: recorded.result,
    });
  }

  const status = String(result.status ?? "BLOCKED");
  const expected = [
    "SCREEN_SELECTION_REQUIRED",
    "INPUT_GOVERNANCE_RUNTIME_REQUIRED",
    "NATIVE_MODEL_INPUT_READY",
    "HUMAN_DECISION_REQUIRED",
    "SCREEN_SELECTION_AMBIGUOUS",
    "SCREEN_SELECTION_NO_MATCH",
  ];
  const recognized = expected.includes(status);
  return respond({
    outcome: recognized ? "CONTINUATION_REQUIRED" : "BLOCKED",
    phase: status,
    code: recognized ? null : (result.blocking_code ?? "PROFILE_CONTINUATION_PREPARE_BLOCKED"),
    execution_id: e.execution_id,
    profile_code: e.target_code,
    next_action: result.next_action ?? null,
    result,
  }, recognized ? 200 : 409);
}
