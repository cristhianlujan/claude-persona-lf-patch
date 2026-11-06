/**
 * LF Input Governance: semantic receipt classification in the EXISTING Validator.
 * Read-only, no new RUN, receipt writer, model call, semantic family PASS or promotion.
 * Untrusted readback fields fail closed; a receipt PASS is NOT rule readiness.
 */
export type SemanticReceiptStatus =
  | "SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED"
  | "INDEPENDENT_SEMANTIC_VERDICT_REQUIRED"
  | "SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE";

export type SemanticContinuationStatus =
  | "CANDIDATE_EVIDENCE_REQUIRED"
  | "INDEPENDENT_REVIEW_REQUIRED"
  | "SEMANTIC_AUDIT_PASS_NOT_RULE_PASS"
  | "SEMANTIC_AUDIT_FAILED_REMEDIATION_REQUIRED"
  | "SEMANTIC_AUDIT_BLOCKED_HUMAN_DECISION_REQUIRED";

export interface SemanticContinuation {
  status: SemanticContinuationStatus;
  run_id: number;
  candidate_sha256: string | null;
  next_action: string;
  retry_policy: "NO_AUTOMATIC_MODEL_RETRY";
  same_run: true;
  semantic_rule_pass_authorized: false;
  independent_semantic_quality_proven: false;
  official_write_authorized: false;
  promotion_authorized: false;
  production_authorized: false;
}
const shaRe = /^[a-f0-9]{64}$/;
const sha = (v: unknown): v is string =>
  typeof v === "string" && shaRe.test(v);

function fail(reason: string): never {
  throw new Error("IG_SEMANTIC_CONTINUATION_" + reason);
}

export function classifySemanticReadback(
  value: unknown,
  expectedRunId: number,
  expectedCandidateSha: string | null = null,
): SemanticContinuation {
  if (!Number.isSafeInteger(expectedRunId) || expectedRunId < 1)
    fail("RUN_ID_INVALID");
  if (expectedCandidateSha !== null && !sha(expectedCandidateSha))
    fail("EXPECTED_CANDIDATE_DIGEST_INVALID");
  if (!value || typeof value !== "object" || Array.isArray(value))
    fail("RECEIPT_NOT_OBJECT");
  const r = value as Record<string, unknown>;
  if (r.run_id !== expectedRunId || r.promotion_authorized !== false ||
      r.production_authorized !== false ||
      (r.official_write_authorized !== undefined &&
       r.official_write_authorized !== false))
    fail("RUN_OR_AUTHORITY_MISMATCH");

  let status: SemanticContinuationStatus;
  let nextAction: string;
  let candidateSha: string | null = null;
  switch (r.status as SemanticReceiptStatus) {
    case "SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED":
      if (r.model_candidate_verified !== false || r.auditor_verified !== false)
        fail("MISSING_EVIDENCE_STATUS_MISMATCH");
      status = "CANDIDATE_EVIDENCE_REQUIRED";
      nextAction = "EXTERNAL_EVIDENCE_VERIFIER_REQUIRED";
      break;
    case "INDEPENDENT_SEMANTIC_VERDICT_REQUIRED":
      if (r.model_candidate_verified !== true || r.auditor_verified !== false ||
          !sha(r.candidate_sha256) ||
          !Number.isSafeInteger(r.candidate_evidence_receipt_id) ||
          Number(r.candidate_evidence_receipt_id) < 1)
        fail("AUDITOR_REQUIRED_BINDING_INVALID");
      candidateSha = r.candidate_sha256 as string;
      status = "INDEPENDENT_REVIEW_REQUIRED";
      nextAction = "EXTERNAL_INDEPENDENT_AUDITOR_REQUIRED";
      break;
    case "SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE":
      if (r.model_candidate_verified !== true || r.auditor_verified !== true ||
          r.semantic_independence_credited !== false ||
          r.official_write_authorized !== false ||
          !sha(r.candidate_sha256) ||
          !Number.isSafeInteger(r.candidate_evidence_receipt_id) ||
          !Number.isSafeInteger(r.independent_audit_receipt_id) ||
          Number(r.candidate_evidence_receipt_id) < 1 ||
          Number(r.independent_audit_receipt_id) < 1)
        fail("AUDIT_RECEIPT_BINDING_INVALID");
      candidateSha = r.candidate_sha256 as string;
      if (r.audit_verdict === "PASS") {
        status = "SEMANTIC_AUDIT_PASS_NOT_RULE_PASS";
        nextAction = "SEMANTIC_QUALITY_GATE_REQUIRES_INDEPENDENT_TESTS";
      } else if (r.audit_verdict === "FAIL") {
        status = "SEMANTIC_AUDIT_FAILED_REMEDIATION_REQUIRED";
        nextAction = "REMEDIATION_WITH_AUDIT_FINDINGS_REQUIRED";
      } else if (r.audit_verdict === "BLOCKED") {
        status = "SEMANTIC_AUDIT_BLOCKED_HUMAN_DECISION_REQUIRED";
        nextAction = "HUMAN_DECISION_REQUIRED";
      } else fail("AUDIT_VERDICT_INVALID");
      break;
    default:
      fail("RECEIPT_STATUS_UNRECOGNIZED");
  }
  if (candidateSha !== null && expectedCandidateSha !== null &&
      candidateSha !== expectedCandidateSha)
    fail("CANDIDATE_SHA_MISMATCH");

  return {
    status, run_id: expectedRunId, candidate_sha256: candidateSha,
    next_action: nextAction, retry_policy: "NO_AUTOMATIC_MODEL_RETRY",
    same_run: true, semantic_rule_pass_authorized: false,
    independent_semantic_quality_proven: false, official_write_authorized: false,
    promotion_authorized: false, production_authorized: false,
  };
}
