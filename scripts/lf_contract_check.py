#!/usr/bin/env python3
"""
LF Contract Check v0.5

Sandbox validator for controlled LF governance gates.

v0.4 changes:
- Supports pull_request, push and workflow_dispatch events.
- Allows the sandbox NO BYPASS judge package path.
- Avoids false positives when control documents list forbidden statuses as prohibited outputs.
"""

import fnmatch
import json
import os
import subprocess
import sys
from pathlib import Path

CONTRACT_PATH = Path("sandbox/lf_contract_gate_test/lf_contract.yml")
RECEIPT_DIR = Path("sandbox/lf_contract_gate_test/receipts")
VALIDATOR_SELF_PATH = "scripts/lf_contract_check.py"

ALLOWED_EXACT = {
    ".github/workflows/lf-contract-check.yml",
    VALIDATOR_SELF_PATH,
}
ALLOWED_PREFIXES = [
    "sandbox/lf_contract_gate_test/",
    "sandbox/no_bypass_judge_profile_card_skill/",
    "supabase/migrations/",
]
GOVERNED_PREFIXES = [
    "profiles/",
    "skills/",
    "cards/",
    "gobernanza/procedimientos/",
    "gobernanza/contratos/",
    "gobernanza/judges/",
    "gobernanza/activos/",
]
ALWAYS_BLOCKED_PREFIXES = [
    "official/",
    "production/",
    "runtime/",
]
FORBIDDEN_GITHUB_PREFIX = ".github/"
ALLOWED_GITHUB_EXACT = ".github/workflows/lf-contract-check.yml"

FORBIDDEN_TERM_EXEMPT_EXACT = {
    VALIDATOR_SELF_PATH,
    "sandbox/no_bypass_judge_profile_card_skill/GPT_INSTRUCTIONS_NO_BYPASS_v0_1.md",
}
FORBIDDEN_TERM_EXEMPT_PREFIXES = [
    "sandbox/no_bypass_judge_profile_card_skill/",
]

VALID_RECEIPT_ISSUERS = {"contract_judge", "operation_judge"}
VALID_RECEIPT_RESULTS = {"PASS", "PASS_SANDBOX"}
REQUIRED_RECEIPT_FIELDS = [
    "receipt_type",
    "receipt_version",
    "issued_by",
    "operation_code",
    "execution_id",
    "result",
    "all_required_steps_pass",
    "contract_sha",
    "judge_sha",
    "source_sha_list",
    "target_paths",
    "blocking_codes",
    "issued_at",
]

FORBIDDEN_TERMS = [
    "VALIDATED",
    "PRODUCTION",
    "PRODUCCION",
    "APROBADO_FINAL",
    "OPERATIVO_GENERAL",
]
REQUIRED_TERMS = [
    'contract_version: "v0.1"',
    'contract_id: "LF-GH-GATE-INSTALL-SANDBOX-20260529-001"',
    'activo_router: "ACT-0001"',
    'vista: "public.v_lf_fuente_operativa"',
    'operation_code: "GITHUB_CONTRACT_GATE_INSTALL_SANDBOX"',
    'impacto_productivo: false',
    'estado_salida_permitido: "GATE_INSTALL_SANDBOX_TESTED"',
]


def fail(code: str, message: str) -> None:
    print(f"{code}: {message}")
    sys.exit(1)


def pass_check(message: str) -> None:
    print(f"PASS_CONTRACT_VALID: {message}")
    sys.exit(0)


def run_git(args: list[str]) -> str:
    result = subprocess.run(
        ["git", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def event_payload() -> dict:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        return {}
    path = Path(event_path)
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def get_changed_files() -> list[str]:
    event_name = os.environ.get("GITHUB_EVENT_NAME", "pull_request")

    if event_name == "pull_request":
        base_ref = os.environ.get("GITHUB_BASE_REF", "main")
        subprocess.run(["git", "fetch", "origin", base_ref], check=True)
        output = run_git(["diff", "--name-only", f"origin/{base_ref}...HEAD"])
        return [line.strip() for line in output.splitlines() if line.strip()]

    if event_name == "push":
        payload = event_payload()
        before = payload.get("before")
        after = payload.get("after") or os.environ.get("GITHUB_SHA", "HEAD")
        if before and not set(before) <= {"0"}:
            output = run_git(["diff", "--name-only", before, after])
        else:
            output = run_git(["diff", "--name-only", "HEAD~1", "HEAD"])
        return [line.strip() for line in output.splitlines() if line.strip()]

    if event_name == "workflow_dispatch":
        print("workflow_dispatch event: no changed-file scope validation required; running static/self-tests only.")
        return []

    output = run_git(["diff", "--name-only", "HEAD~1", "HEAD"])
    return [line.strip() for line in output.splitlines() if line.strip()]


def validate_contract() -> str:
    if not CONTRACT_PATH.exists():
        fail("FAIL_CONTRACT_MISSING", "lf_contract.yml no existe")
    contract_text = CONTRACT_PATH.read_text(encoding="utf-8")
    for term in REQUIRED_TERMS:
        if term not in contract_text:
            fail("FAIL_CONTRACT_INVALID", f"Falta término obligatorio: {term}")
    return contract_text


def is_allowed_path(path: str) -> bool:
    if path in ALLOWED_EXACT:
        return True
    return any(path.startswith(prefix) for prefix in ALLOWED_PREFIXES)


def is_governed_path(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in GOVERNED_PREFIXES)


def validate_changed_files(changed_files: list[str]) -> list[str]:
    event_name = os.environ.get("GITHUB_EVENT_NAME", "pull_request")
    if not changed_files:
        if event_name == "workflow_dispatch":
            print("No changed files for workflow_dispatch; scope validation skipped.")
            return []
        fail("FAIL_NO_CHANGED_FILES", "No se detectaron archivos modificados")

    governed_files: list[str] = []
    for path in changed_files:
        for blocked in ALWAYS_BLOCKED_PREFIXES:
            if path.startswith(blocked):
                fail("FAIL_BLOCKED_SCOPE_RISK", f"Ruta productiva/bloqueada tocada: {path}")

        if path.startswith(FORBIDDEN_GITHUB_PREFIX) and path != ALLOWED_GITHUB_EXACT:
            fail("FAIL_UNAUTHORIZED_GITHUB_PATH", f"Ruta .github no autorizada: {path}")

        if is_governed_path(path):
            governed_files.append(path)
            continue

        if not is_allowed_path(path):
            fail("FAIL_SCOPE_INVALID", f"Archivo fuera de scope sandbox gate-install: {path}")
    return governed_files


def load_receipts_from_changed_files(changed_files: list[str]) -> list[tuple[str, dict]]:
    receipts: list[tuple[str, dict]] = []
    for path in changed_files:
        if not path.startswith(str(RECEIPT_DIR) + "/") or not path.endswith(".json"):
            continue
        receipt_path = Path(path)
        if not receipt_path.exists():
            continue
        try:
            receipts.append((path, json.loads(receipt_path.read_text(encoding="utf-8"))))
        except json.JSONDecodeError as exc:
            fail("FAIL_RECEIPT_INVALID_JSON", f"Receipt JSON inválido en {path}: {exc}")
    return receipts


def receipt_covers_file(receipt: dict, changed_file: str) -> bool:
    target_paths = receipt.get("target_paths", [])
    if not isinstance(target_paths, list):
        fail("FAIL_RECEIPT_INVALID", "target_paths debe ser lista")
    return any(fnmatch.fnmatch(changed_file, pattern) for pattern in target_paths)


def validate_receipt_shape(path: str, receipt: dict) -> None:
    for field in REQUIRED_RECEIPT_FIELDS:
        if field not in receipt:
            fail("FAIL_RECEIPT_INVALID", f"Falta campo obligatorio {field} en {path}")

    if receipt.get("receipt_type") != "LF_OPERATION_CONTRACT_RECEIPT":
        fail("FAIL_RECEIPT_INVALID", f"receipt_type inválido en {path}")
    if receipt.get("issued_by") not in VALID_RECEIPT_ISSUERS:
        fail("FAIL_RECEIPT_INVALID_ISSUER", f"issued_by inválido en {path}")
    if receipt.get("result") not in VALID_RECEIPT_RESULTS:
        fail("FAIL_RECEIPT_RESULT_NOT_PASS", f"result inválido en {path}")
    if receipt.get("all_required_steps_pass") is not True:
        fail("FAIL_RECEIPT_INCOMPLETE_STEPS", f"all_required_steps_pass debe ser true en {path}")
    if receipt.get("blocking_codes") not in ([], None):
        fail("FAIL_RECEIPT_BLOCKING_CODES", f"blocking_codes debe estar vacío en {path}")
    if not receipt.get("contract_sha") or not receipt.get("judge_sha"):
        fail("FAIL_RECEIPT_WEAK_EVIDENCE", f"contract_sha/judge_sha requeridos en {path}")
    source_sha_list = receipt.get("source_sha_list")
    if not isinstance(source_sha_list, list) or not source_sha_list:
        fail("FAIL_RECEIPT_WEAK_EVIDENCE", f"source_sha_list requerido en {path}")
    if not receipt.get("operation_code") or not receipt.get("execution_id"):
        fail("FAIL_RECEIPT_INVALID", f"operation_code/execution_id requeridos en {path}")


def validate_governed_receipt(changed_files: list[str], governed_files: list[str]) -> None:
    if not governed_files:
        print("No governed LF paths touched; receipt not required.")
        return

    receipts = load_receipts_from_changed_files(changed_files)
    if not receipts:
        fail("FAIL_RECEIPT_MISSING", "Ruta gobernada tocada sin LF_OPERATION_CONTRACT_RECEIPT")

    for receipt_path, receipt in receipts:
        validate_receipt_shape(receipt_path, receipt)

    for governed_file in governed_files:
        if not any(receipt_covers_file(receipt, governed_file) for _, receipt in receipts):
            fail("FAIL_RECEIPT_TARGET_MISMATCH", f"Ningún receipt cubre ruta gobernada: {governed_file}")


def is_forbidden_term_exempt(path: str) -> bool:
    if path in FORBIDDEN_TERM_EXEMPT_EXACT:
        return True
    return any(path.startswith(prefix) for prefix in FORBIDDEN_TERM_EXEMPT_PREFIXES)


def validate_forbidden_terms(changed_files: list[str]) -> None:
    for path in changed_files:
        if is_forbidden_term_exempt(path):
            print(f"Skipping forbidden-term scan for control/sandbox file: {path}")
            continue

        file_path = Path(path)
        if file_path.exists() and file_path.is_file():
            content = file_path.read_text(encoding="utf-8", errors="ignore")
            for forbidden in FORBIDDEN_TERMS:
                if forbidden in content:
                    fail("FAIL_FORBIDDEN_STATUS", f"Término prohibido encontrado: {forbidden} en {path}")


def main() -> None:
    validate_contract()
    changed_files = get_changed_files()
    print("Changed files:")
    for path in changed_files:
        print(f"- {path}")
    governed_files = validate_changed_files(changed_files)
    validate_governed_receipt(changed_files, governed_files)
    validate_forbidden_terms(changed_files)
    pass_check("Contrato LF gate-install sandbox válido y scope respetado")


if __name__ == "__main__":
    main()
