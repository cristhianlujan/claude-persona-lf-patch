export const GOLDEN_CAPABLE_GRADUATION = "GOLDEN_CAPABLE_V1";

export const GRADUATION_SERVER_FIELDS = new Set([
  "server_contract_receipt_verified",
  "server_contract_receipt",
  "graduation_receipt_source",
]);

type GithubJson = (url: string, label: string) => Promise<any>;
type PriorStep = (executionId: string, stepId: string) => Promise<any | null>;

function decodeBase64Utf8(value: string): string {
  const binary = atob(value.replace(/\s+/g, ""));
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function fail(evidence: Record<string, unknown>, code: string): Record<string, unknown> {
  return {
    ...evidence,
    server_contract_receipt_verified: false,
    graduation_receipt_source: "run-creacion-perfil-lf",
    server_contract_receipt: { verification_error: code },
  };
}

export async function enrichGoldenGraduationReceipt(
  repository: string,
  ex: any,
  stepId: string,
  evidence: Record<string, unknown>,
  githubJson: GithubJson,
  priorStep: PriorStep,
): Promise<Record<string, unknown>> {
  if (ex?.operation_code !== "ACTUALIZACION_PERFIL_LF" || ex?.manifest?.graduation_contract !== GOLDEN_CAPABLE_GRADUATION || stepId !== "close") return evidence;

  const receiptPath = typeof evidence.contract_receipt_path === "string" ? evidence.contract_receipt_path.trim() : "";
  if (!/^sandbox\/lf_contract_gate_test\/receipts\/[A-Za-z0-9._-]+\.json$/.test(receiptPath)) return fail(evidence, "PROFILE_UPDATE_GOLDEN_RECEIPT_PATH_INVALID");

  const readback = await priorStep(ex.execution_id, "github_readback");
  const exactHead = typeof readback?.evidence_payload?.exact_head === "string" ? readback.evidence_payload.exact_head.trim().toLowerCase() : "";
  if (!/^[0-9a-f]{40}$/.test(exactHead)) return fail(evidence, "PROFILE_UPDATE_GOLDEN_READBACK_HEAD_UNRESOLVED");

  try {
    const encodedPath = receiptPath.split("/").map(encodeURIComponent).join("/");
    const artifact = await githubJson(`https://api.github.com/repos/${repository}/contents/${encodedPath}?ref=${exactHead}`, "GITHUB_GRADUATION_RECEIPT");
    if (!artifact || Array.isArray(artifact) || artifact.encoding !== "base64" || typeof artifact.content !== "string" || typeof artifact.sha !== "string" || !/^[0-9a-f]{40}$/.test(artifact.sha)) return fail(evidence, "PROFILE_UPDATE_GOLDEN_RECEIPT_ARTIFACT_INVALID");

    let receipt: any;
    try { receipt = JSON.parse(decodeBase64Utf8(artifact.content)); } catch { return fail(evidence, "PROFILE_UPDATE_GOLDEN_RECEIPT_JSON_INVALID"); }

    const issuerOk = receipt?.issued_by === "contract_judge" || receipt?.issued_by === "operation_judge";
    const resultOk = receipt?.result === "PASS" || receipt?.result === "PASS_SANDBOX";
    const blockersOk = Array.isArray(receipt?.blocking_codes) && receipt.blocking_codes.length === 0;
    const sourcesOk = Array.isArray(receipt?.source_sha_list) && receipt.source_sha_list.length > 0;
    const targetPaths = Array.isArray(receipt?.target_paths) ? receipt.target_paths.filter((x: unknown) => typeof x === "string") as string[] : [];
    const packageRoot = String(ex.target_path ?? "").split("/").slice(0, 2).join("/");
    const targetOk = packageRoot.startsWith("profiles/") && targetPaths.some((p) => p === packageRoot || p === `${packageRoot}/**` || p.startsWith(`${packageRoot}/`));
    const identityOk = receipt?.receipt_type === "LF_OPERATION_CONTRACT_RECEIPT" && receipt?.operation_code === "ACTUALIZACION_PERFIL_LF" && receipt?.execution_id === ex.execution_id;
    const evidenceOk = typeof receipt?.contract_sha === "string" && receipt.contract_sha.trim() !== "" && typeof receipt?.judge_sha === "string" && receipt.judge_sha.trim() !== "";

    if (!identityOk) return fail(evidence, "PROFILE_UPDATE_GOLDEN_RECEIPT_IDENTITY_INVALID");
    if (!issuerOk || !resultOk || receipt?.all_required_steps_pass !== true || !blockersOk || !sourcesOk || !targetOk || !evidenceOk) return fail(evidence, "PROFILE_UPDATE_GOLDEN_RECEIPT_NOT_CLEAN");

    return {
      ...evidence,
      server_contract_receipt_verified: true,
      graduation_receipt_source: "run-creacion-perfil-lf",
      server_contract_receipt: {
        receipt_type: receipt.receipt_type,
        issued_by: receipt.issued_by,
        operation_code: receipt.operation_code,
        execution_id: receipt.execution_id,
        result: receipt.result,
        all_required_steps_pass: receipt.all_required_steps_pass,
        contract_sha: receipt.contract_sha,
        judge_sha: receipt.judge_sha,
        source_sha_list: receipt.source_sha_list,
        target_paths: receipt.target_paths,
        blocking_codes: receipt.blocking_codes,
        receipt_path: receiptPath,
        receipt_blob_sha: artifact.sha,
        exact_head: exactHead,
      },
    };
  } catch {
    return fail(evidence, "PROFILE_UPDATE_GOLDEN_RECEIPT_FETCH_FAILED");
  }
}
