/**
 * LF Skills Governance Caller V1 — CANDIDATE, NOT DEPLOYED.
 * Generic infrastructure for SKILL, not a skill that calls itself.
 * All native RPC names below are PROPOSED and NOT installed.
 * Only a trusted service-role Edge function may invoke the native RPCs.
 */
export const AUDIENCE = 'lf-skills-governance-caller-v1';
export const ACTIONS = Object.freeze({
  BEGIN: 'skill_native_begin_v1',
  STEP: 'skill_native_record_step_v1',
  STATUS: 'skill_native_status_v1',
});
export const PROPOSED_RPC = Object.freeze({
  PREFLIGHT: 'lf_skill_native_preflight_v1',
  BEGIN: 'lf_skill_execution_begin_from_handoff_v1',
  STEP: 'lf_record_skill_execution_step_v1',
  STATUS: 'lf_skill_execution_status_v1',
});
const SHA40 = /^[a-f0-9]{40}$/;
const CODE = /^[A-Z][A-Z0-9_-]{2,63}$/;
const EXEC_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{10,127}$/;
const STEP_IDS = ['router', 'skill_resolve', 'skill_source_read', 'input_validate', 'execute_skill', 'output_validate', 'semantic_judge', 'report_output'];
const SOURCE_PATH = /^skills\/[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*\/SKILL\.md$/;

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {status, headers:{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'}});
}
const blocked=(code,status=409)=>json({status:'BLOCKED',blocking_code:code,operationally_integrated:false,a3_allowed:false},status);
function truthy(v) { return v === 'true'; }
function configFrom(getEnv) {
  const cfg = {
    enabled: truthy(getEnv('LF_SKILL_NATIVE_CALLER_ENABLED')),
    supabaseUrl: getEnv('SUPABASE_URL') ?? '',
    serviceKey: getEnv('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    repository: getEnv('LF_REPOSITORY') ?? '',
    repositoryId: getEnv('LF_REPOSITORY_ID') ?? '',
    workflowRef: getEnv('LF_SKILL_NATIVE_WORKFLOW_REF') ?? '',
    environment: getEnv('LF_SKILL_NATIVE_ENVIRONMENT') ?? '',
    githubReadToken: getEnv('LF_GITHUB_READ_TOKEN') ?? '',
  };
  return cfg;
}
function claimsValid(claims,cfg){
  return claims && typeof claims==='object' &&
    claims.iss==='https://token.actions.githubusercontent.com' &&
    (claims.aud===AUDIENCE || (Array.isArray(claims.aud) && claims.aud.length===1 && claims.aud[0]===AUDIENCE)) &&
    claims.repository===cfg.repository && claims.repository_id===cfg.repositoryId &&
    claims.ref==='refs/heads/main' && claims.workflow_ref===cfg.workflowRef &&
    claims.environment===cfg.environment && ['workflow_dispatch','workflow_call'].includes(claims.event_name) &&
    /^[0-9]{1,20}$/.test(String(claims.run_id??'')) && SHA40.test(String(claims.workflow_sha??''));
}
const forbidden=new Set(['_trusted','trusted','source_attested','readback_authenticated','native_judge_verified','a3_allowed','actor_execution_id','business','caller_identity','source_sha','source_path']);
function hasPrivilegeOverride(body) {
  // Business is only a DECLARED fact at input.business. Never an authority.
  // For every other location, reject reserved keys even in nested objects or
  // arrays, so caller-supplied receipts cannot be smuggled through wrappers.
  const stack = [{value:body, area:'root', depth:0}];
  let visited = 0;
  while (stack.length) {
    const {value,area,depth} = stack.pop();
    if (!value || typeof value !== 'object') continue;
    if (depth > 24 || ++visited > 3000) return true;
    for (const [key,child] of Object.entries(value)) {
      if (forbidden.has(key) && !(area === 'input' && key === 'business')) return true;
      if (child && typeof child === 'object') {
        stack.push({value:child,area:area === 'root' ? key : 'nested',depth:depth+1});
      }
    }
  }
  return false;
}
function validInput(body){return body.input && typeof body.input==='object' && !Array.isArray(body.input) && JSON.stringify(body.input).length<=65536;}
function srcAllowed(p){return typeof p==='string' && SOURCE_PATH.test(p) && !p.includes('..') && !p.includes('//');}
async function getJson(fetchFn,url,init){
  let response;try{response=await fetchFn(url,init);}catch{return {ok:false,network:true};}
  let data;try{data=await response.json();}catch{return {ok:false};}
  return {ok:response.ok,data,status:response.status};
}
function serviceHeaders(cfg){return {'apikey':cfg.serviceKey,'authorization':'Bearer '+cfg.serviceKey,'content-type':'application/json'};}
async function rpc(fetchFn,cfg,name,payload){
  return getJson(fetchFn,cfg.supabaseUrl+'/rest/v1/rpc/'+name,{
    method:'POST',headers:serviceHeaders(cfg),body:JSON.stringify(payload),signal:AbortSignal.timeout(10000),
  });
}
async function exactMainSource(fetchFn,cfg,path){
  if(!srcAllowed(path))return {error:'SKILL_CANONICAL_SOURCE_PATH_INVALID'};
  const headers={'accept':'application/vnd.github+json'};
  if(cfg.githubReadToken)headers.authorization='Bearer '+cfg.githubReadToken;
  const main=await getJson(fetchFn,'https://api.github.com/repos/'+cfg.repository+'/git/ref/heads/main',{headers});
  const sha=main.data?.object?.sha;
  if(!main.ok||!SHA40.test(String(sha??'')))return {error:'SKILL_MAIN_SOURCE_UNRESOLVED'};
  const safePath=path.split('/').map(encodeURIComponent).join('/');
  const file=await getJson(fetchFn,'https://api.github.com/repos/'+cfg.repository+'/contents/'+safePath+'?ref='+sha,{headers});
  const blob=file.data?.sha;
  if(!file.ok||Array.isArray(file.data)||file.data?.type!=='file'||!SHA40.test(String(blob??'')))return {error:'SKILL_EXACT_SOURCE_NOT_ATTESTED'};
  return {source:{repository:cfg.repository,path,ref:'refs/heads/main',commit_sha:sha,blob_sha:blob}};
}
export function createSkillsHandler({getEnv,fetchFn,verifyJwt}){
  if(typeof getEnv!=='function'||typeof fetchFn!=='function'||typeof verifyJwt!=='function')throw Error('SKILL_CALLER_DEPENDENCIES_REQUIRED');
  return async function handle(req){
    if(req.method!=='POST')return blocked('METHOD_NOT_ALLOWED',405);
    const cfg=configFrom(getEnv);
    // Fail closed even when a build accidentally deploys this source.
    if(!cfg.enabled)return blocked('SKILL_NATIVE_ROUTE_NOT_ACTIVATED',503);
    if(!cfg.supabaseUrl.startsWith('https://')||!cfg.serviceKey||!cfg.repository||!cfg.repositoryId||
       !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(cfg.repository)||
       !cfg.workflowRef.startsWith(cfg.repository+'/.github/workflows/')||
       !cfg.workflowRef.endsWith('@refs/heads/main')||!cfg.environment)
      return blocked('SKILL_NATIVE_SERVER_CONFIGURATION_MISSING',503);
    const token=(req.headers.get('authorization')??'').match(/^Bearer ([A-Za-z0-9_.-]{20,4096})$/)?.[1];
    if(!token)return blocked('SKILL_OIDC_TOKEN_REQUIRED',401);
    let claims;try{claims=await verifyJwt(token,AUDIENCE);}catch{return blocked('SKILL_OIDC_VERIFICATION_FAILED',401);}
    if(!claimsValid(claims,cfg))return blocked('SKILL_OIDC_SCOPE_MISMATCH',403);
    let body;try{const raw=await req.text();if(raw.length>100000)throw Error('too_big');body=JSON.parse(raw);}catch{return blocked('SKILL_BODY_INVALID',400);}
    if(!body||typeof body!=='object'||Array.isArray(body)||hasPrivilegeOverride(body))return blocked('SKILL_AUTHORITY_FIELDS_FORBIDDEN',403);
    if(!Object.values(ACTIONS).includes(body.action))return blocked('SKILL_ACTION_UNKNOWN',400);
    if(!CODE.test(String(body.skill_code??''))||!EXEC_ID.test(String(body.parent_execution_id??'')))return blocked('SKILL_TARGET_OR_PARENT_INVALID',400);
    const caller={repository:claims.repository,repository_id:claims.repository_id,workflow_ref:claims.workflow_ref,workflow_sha:claims.workflow_sha,run_id:String(claims.run_id),method:'GITHUB_ACTIONS_OIDC_SKILL_NATIVE_V1'};
    const core={p_skill_code:body.skill_code,p_parent_execution_id:body.parent_execution_id,p_caller:caller};
    // SQL authorization is always authoritative; Edge does not elevate caller claims.
    if(body.action===ACTIONS.BEGIN){
      if(!validInput(body))return blocked('SKILL_INPUT_INVALID',400);
      const eligibility=await rpc(fetchFn,cfg,PROPOSED_RPC.PREFLIGHT,core);
      if(!eligibility.ok||eligibility.data?.status!=='ELIGIBLE'||!srcAllowed(eligibility.data?.source_path))
        return blocked('SKILL_NATIVE_PREFLIGHT_NOT_ADMITTED');
      const source=await exactMainSource(fetchFn,cfg,eligibility.data.source_path);
      if(source.error)return blocked(source.error);
      const opened=await rpc(fetchFn,cfg,PROPOSED_RPC.BEGIN,{...core,p_input:body.input,p_source:source.source});
      if(!opened.ok||opened.data?.status!=='RUN_OPENED_PENDING_EXECUTION'||opened.data?.step0_recorded!==true||opened.data?.a3_allowed!==false)
        return blocked('SKILL_NATIVE_BEGIN_NOT_VERIFIED');
      if(!EXEC_ID.test(String(opened.data?.execution_id??'')))return blocked('SKILL_RUN_IDENTITY_UNRESOLVED');
      // RPC readback MUST be server-side; never accept user-submitted receipts.
      const readback=await rpc(fetchFn,cfg,PROPOSED_RPC.STATUS,{...core,p_child_execution_id:opened.data.execution_id});
      if(!readback.ok||readback.data?.execution_id!==opened.data.execution_id||readback.data?.status!=='IN_PROGRESS'||readback.data?.step0_clean!==true||readback.data?.skill_code!==body.skill_code)
        return blocked('SKILL_NATIVE_READBACK_NOT_CLEAN');
      return json({status:'RUN_OPENED_PENDING_EXECUTION',skill_code:body.skill_code,execution_id:opened.data.execution_id,
        skill_run_id:opened.data.skill_run_id,next_step:'router',a3_allowed:false,native_judge_verified:false});
    }
    if(body.action===ACTIONS.STEP){
      if(!EXEC_ID.test(String(body.child_execution_id??''))||!STEP_IDS.includes(body.step_id)||typeof body.evidence_ref!=='string'||
         !body.evidence_ref.startsWith('supabase://')||body.evidence_ref.length>900||!body.evidence_payload||typeof body.evidence_payload!=='object'||Array.isArray(body.evidence_payload))
        return blocked('SKILL_STEP_INPUT_INVALID',400);
      // The proposed SQL recorder validates trust, order, judge and writes receipts.
      // Its response must be read back separately by the native operation host.
      const write=await rpc(fetchFn,cfg,PROPOSED_RPC.STEP,{...core,p_child_execution_id:body.child_execution_id,
        p_step_id:body.step_id,p_evidence_ref:body.evidence_ref,p_evidence_payload:body.evidence_payload});
      if(!write.ok||!['STEP_RECORDED','BLOCKED'].includes(write.data?.outcome))return blocked('SKILL_NATIVE_STEP_RPC_UNVERIFIED');
      return json({status:write.data.outcome==='STEP_RECORDED'?'STEP_SUBMITTED_PENDING_READBACK':'BLOCKED',
        step_id:body.step_id,execution_id:body.child_execution_id,a3_allowed:false,native_judge_verified:false,
        blocking_code:write.data.outcome==='BLOCKED'?String(write.data?.code??'STEP_BLOCKED'):null});
    }
    if(!EXEC_ID.test(String(body.child_execution_id??'')))return blocked('SKILL_CHILD_ID_INVALID',400);
    const readback=await rpc(fetchFn,cfg,PROPOSED_RPC.STATUS,{...core,p_child_execution_id:body.child_execution_id});
    if(!readback.ok||readback.data?.execution_id!==body.child_execution_id||readback.data?.skill_code!==body.skill_code)
      return blocked('SKILL_STATUS_READBACK_UNAVAILABLE');
    // Status does not infer judge PASS; only the server-authorized RUN can close.
    return json({status:'READBACK_ONLY',execution_id:body.child_execution_id,execution_status:readback.data?.status,
      skill_code:body.skill_code,a3_allowed:false,native_judge_verified:false});
  };
}
