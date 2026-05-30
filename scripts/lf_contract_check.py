#!/usr/bin/env python3
"""
LF Contract Check v0.2

Sandbox validator for TEST_GITHUB_CONTRACT_GATE_LF_SANDBOX_001.
Supports the controlled gate-install sandbox operation.

Fix v0.2:
- Avoid self-referential false positives by excluding this validator file
  from forbidden-term content scanning. Scope/path checks still apply.
"""

import os
import subprocess
import sys
from pathlib import Path

CONTRACT_PATH = Path("sandbox/lf_contract_gate_test/lf_contract.yml")
VALIDATOR_SELF_PATH = "scripts/lf_contract_check.py"

ALLOWED_EXACT = {
    ".github/workflows/lf-contract-check.yml",
    VALIDATOR_SELF_PATH,
}
ALLOWED_PREFIXES = [
    "sandbox/lf_contract_gate_test/",
]
BLOCKED_PREFIXES = [
    "profiles/",
    "skills/",
    "official/",
    "production/",
]
FORBIDDEN_GITHUB_PREFIX = ".github/"
ALLOWED_GITHUB_EXACT = ".github/workflows/lf-contract-check.yml"

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


def get_changed_files() -> list[str]:
    base_ref = os.environ.get("GITHUB_BASE_REF", "main")
    subprocess.run(["git", "fetch", "origin", base_ref], check=True)
    result = subprocess.run(
        ["git", "diff", "--name-only", f"origin/{base_ref}...HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


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


def validate_changed_files(changed_files: list[str]) -> None:
    if not changed_files:
        fail("FAIL_NO_CHANGED_FILES", "No se detectaron archivos modificados")

    for path in changed_files:
        for blocked in BLOCKED_PREFIXES:
            if path.startswith(blocked):
                fail("FAIL_BLOCKED_PATH_TOUCHED", f"Ruta bloqueada tocada: {path}")

        if path.startswith(FORBIDDEN_GITHUB_PREFIX) and path != ALLOWED_GITHUB_EXACT:
            fail("FAIL_UNAUTHORIZED_GITHUB_PATH", f"Ruta .github no autorizada: {path}")

        if not is_allowed_path(path):
            fail("FAIL_SCOPE_INVALID", f"Archivo fuera de scope sandbox gate-install: {path}")


def validate_forbidden_terms(changed_files: list[str]) -> None:
    for path in changed_files:
        if path == VALIDATOR_SELF_PATH:
            print(f"Skipping forbidden-term scan for validator control file: {path}")
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
    validate_changed_files(changed_files)
    validate_forbidden_terms(changed_files)
    pass_check("Contrato LF gate-install sandbox válido y scope respetado")


if __name__ == "__main__":
    main()
