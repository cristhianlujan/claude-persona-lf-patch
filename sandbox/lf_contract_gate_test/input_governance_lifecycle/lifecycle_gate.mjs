/**
 * LF Input Governance — deterministic, READ-ONLY action planner.
 * It does not create RUNs, call SQL, invoke a model, approve, write or promote.
 * Its output MUST be transported by the already authorized profile-owned
 * GitHub Issue → OIDC → Edge → official RPC route, after independent checks.
 * Deployment is fail-closed until owner/identity/native-provider gates are proven.
 */
export const SCHEMA = "LF_IG_RULE_LIFECYCLE_PLAN_V1";
const SHA = /^[0-9a-f]{64}$/;
const RULE = /^[A-Z0-9][A-Z0-9_-]{3,159}$/;
const KINDS = new Set(["CREATE", "UPDATE_CANDIDATE", "CORRECT_VIGENTE"]);
const PROFILE_STEPS = ["init_execution", "router", "profile_resolve", "profile_source_read",
  "input_validate", "context_admission", "research_baseline_freeze", "execute_profile",
  "output_validate", "semantic_judge", "report_output"];

const stop = (code, reason) => ({schema_version:SCHEMA, state:"BLOCKED", code, reason});
const wait = (code, detail) => ({schema_version:SCHEMA, state:"WAITING", code, detail});
const next = (action, input) => ({schema_version:SCHEMA, state:"NEXT", action, input});
const closed = (rule, run) => ({schema_version:SCHEMA, state:"CLOSED", status:"VERIFIED",
  execution_id:run, rule_code:rule, production_authorized:false});
const isSha = v => typeof v === "string" && SHA.test(v);
const object = v => v && typeof v === "object" && !Array.isArray(v);

/** Zero-trust planner. 'trusted' is a readback from the AUTHENTICATED host, never user JSON. */
export function planLifecycle(s, trusted={}) {
  if (!object(s) || !object(s.rule) || !KINDS.has(s.rule.kind) ||
      typeof s.rule.code !== "string" || !RULE.test(s.rule.code) ||
      s.project !== "LF") return stop("BLOCK_SCOPE", "Exact LF rule scope required");
  const rule=s.rule;
  if (!object(s.request) || !isSha(s.request.sha256) ||
      s.request.router !== "ACT-0001" || s.request.transport !== "CONTEXT_TRANSPORT")
    return stop("BLOCK_ROUTER_GATE2", "Source-bound Router transport missing");
  if (!object(trusted.run) || trusted.run.id !== s.run?.id ||
      !/^EXEC-PROFILE-GATE2-[A-Z0-9]{16,64}$/.test(trusted.run.id||"") ||
      trusted.run.is_new !== true || trusted.run.profile !== "PERFIL-PRODUCT-DIRECTOR-LF")
    return stop("BLOCK_NEW_RUN_BINDING", "Fresh canonical parent RUN readback missing");
  if (trusted.run.request_sha256 !== s.request.sha256)
    return stop("BLOCK_REQUEST_BINDING", "Run/request SHA mismatch");
  if (trusted.run.status !== "COMPLETED" || trusted.run.terminal !== "READY" ||
      !PROFILE_STEPS.every(step=>trusted.run.steps?.[step]==="STEP_PASS_WITH_EVIDENCE"))
    return wait("WAIT_PROFILE_11_11", "Complete the SAME RUN, no historical substitutions");
  if (!object(trusted.native) || trusted.native.run_id !== trusted.run.id ||
      trusted.native.provider_bound !== true || trusted.native.source_attested !== true ||
      trusted.native.independent_judge_attested !== true)
    return stop("BLOCK_NATIVE_PROVIDER_PROOF", "No proven unattended native model/judge");
  if (!object(trusted.ig) || trusted.ig.status !== "READY" ||
      trusted.ig.current !== true || trusted.ig.run_id !== trusted.run.id)
    return stop("BLOCK_IG_CURRENTNESS", "IG currentness/Validator missing for this RUN");
  if (!object(s.proposal) || s.proposal.rule_code !== rule.code ||
      s.proposal.kind !== rule.kind || !isSha(s.proposal.sha256) ||
      !isSha(s.proposal.source_sha256) || s.proposal.judge !== "PASS")
    return stop("BLOCK_PROPOSAL", "Source-bound judged proposal missing");
  if (rule.kind === "CREATE") {
    if (trusted.rule?.exists !== false || s.proposal.source_sha256 !== trusted.rule?.absent_sha256)
      return stop("BLOCK_CREATE_PREIMAGE", "Exact no-row source and absence hash required");
  } else {
    if (trusted.rule?.exists !== true || !isSha(trusted.rule.sha256) ||
        trusted.rule.sha256 !== s.proposal.source_sha256 ||
        trusted.rule.state !== (rule.kind==="CORRECT_VIGENTE" ? "VIGENTE" : "CANDIDATO"))
      return stop("BLOCK_SOURCE_PREIMAGE", "Exact current source/estado/hash required");
  }
  // The owner cannot be inferred from a text field or a GitHub username.
  // trusted.owner is ONLY set after live JWT/issuer/aud/JWKS/subject+project binding.
  if (!object(trusted.owner) || trusted.owner.project !== "LF" ||
      trusted.owner.profile !== "PERFIL-PRODUCT-DIRECTOR-LF" ||
      trusted.owner.authenticated !== true || trusted.owner.owner_binding_current !== true ||
      !trusted.owner.subject || trusted.owner.role === "SUPER_ADMIN_FALLBACK")
    return stop("BLOCK_OWNER_IDENTITY_B06_B08", "Verified LF-specific owner binding required");
  if (!object(s.decision)) return wait("OWNER_DECISION_REQUIRED", "One explicit approval for exact candidate and promotion");
  if (s.decision.verdict === "REJECT") return {schema_version:SCHEMA,state:"REJECTED",rule_code:rule.code};
  if (s.decision.verdict !== "APPROVE" ||
      s.decision.rule_code !== rule.code || s.decision.proposal_sha256 !== s.proposal.sha256 ||
      s.decision.source_sha256 !== s.proposal.source_sha256 ||
      s.decision.subject !== trusted.owner.subject ||
      s.decision.project !== "LF" ||
      s.decision.verified_receipt !== trusted.owner.receipt_ref ||
      !isSha(s.decision.receipt_sha256))
    return stop("BLOCK_OWNER_DECISION_BINDING", "Exact source/proposal/subject auth not proven");
  if (s.asset_owner_change) {
    const a=s.asset_owner_change, ar=trusted.asset;
    if (!object(a) || !object(ar) || !a.code || a.code !== ar.code ||
        !isSha(a.preimage_sha256) || a.preimage_sha256 !== ar.preimage_sha256 ||
        a.new_owner !== trusted.owner.owner_code || ar.project !== "LF" ||
        ar.authorized_operation !== "ACTUALIZACION_DB_LF")
      return stop("BLOCK_LF_ACTIVOS_OWNER_AUTHORITY", "No exact owner/write preimage for lf_activos");
    if (!object(s.asset_receipt) || s.asset_receipt.status !== "TRAIN_APPLIED_VERIFIED" ||
        s.asset_receipt.source_sha256 !== a.preimage_sha256 ||
        s.asset_receipt.new_owner !== a.new_owner)
      return next("ACTUALIZACION_DB_LF_MERGE_TRAIN", {asset_code:a.code,preimage_sha256:a.preimage_sha256,
        new_owner:a.new_owner,owner_receipt:trusted.owner.receipt_ref,apply_directly:false});
  }
  // Do not retry an existing, unverified child: never risk a second write.
  if (object(trusted.child) && (trusted.child.parent_id !== trusted.run.id ||
      trusted.child.rule_code !== rule.code || trusted.child.proposal_sha256 !== s.proposal.sha256 ||
      trusted.child.official_writer_verified !== true ||
      trusted.child.source_sha256 !== s.proposal.source_sha256 ||
      trusted.child.status !== "COMPLETED"))
    return stop("BLOCK_CHILD_RECEIPT_UNVERIFIED", "Existing child requires verified immutable receipt");
  if (!object(trusted.child)) {
    if (rule.kind === "CORRECT_VIGENTE")
      return next("ACTUALIZACION_DB_LF_MERGE_TRAIN", {rule_code:rule.code,source_sha256:s.proposal.source_sha256,
        proposal_sha256:s.proposal.sha256,owner_receipt:trusted.owner.receipt_ref,
        preserve_state:"VIGENTE",apply_directly:false});
    return next(rule.kind === "CREATE" ? "RULE_CREATE_APPLY" : "RULE_UPDATE_APPLY",
      {rule_code:rule.code,parent_execution_id:trusted.run.id,source_sha256:s.proposal.source_sha256,
       proposal_sha256:s.proposal.sha256,owner_receipt:trusted.owner.receipt_ref,
       operation:rule.kind === "CREATE" ? "CREACION_REGLA_LF" : "ACTUALIZACION_REGLA_LF"});
  }
  if (!isSha(trusted.child.after_sha256) || trusted.child.after_sha256 === trusted.child.source_sha256 ||
      trusted.child.state !== (rule.kind==="CORRECT_VIGENTE" ? "VIGENTE" : "CANDIDATO") ||
      trusted.child.steps_clean !== true || trusted.child.readback_verified !== true)
    return stop("BLOCK_CHILD_READBACK", "Canonical child writer/readback/hash missing");
  if (rule.kind !== "CORRECT_VIGENTE") {
    if (!object(trusted.promotion) || trusted.promotion.owner_receipt !== trusted.owner.receipt_ref ||
        trusted.promotion.rule_code !== rule.code ||
        trusted.promotion.request_snapshot_sha256 !== trusted.child.after_sha256 ||
        trusted.promotion.status !== "APPLIED" ||
        trusted.promotion.decided_by_subject !== trusted.owner.subject)
      return next("PROMOCION_REGLA_LF", {rule_code:rule.code,request_snapshot_sha256:trusted.child.after_sha256,
        owner_receipt:trusted.owner.receipt_ref,owner_subject:trusted.owner.subject,
        via:"GITHUB_ISSUES_OIDC_EDGE_ONLY"});
  }
  if (trusted.final?.rule_code !== rule.code ||
      trusted.final?.source_state !== "VIGENTE" ||
      !isSha(trusted.final?.sha256) ||
      trusted.final?.sha256 === s.proposal.source_sha256 ||
      trusted.final?.writer_receipt_verified !== true ||
      trusted.final?.operation_closed !== true ||
      trusted.final?.original_run_intact !== true)
    return stop("BLOCK_FINAL_READBACK", "VIGENTE, hash, official receipts and close not proven");
  return closed(rule.code,trusted.run.id);
}
