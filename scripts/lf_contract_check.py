#!/usr/bin/env python3
"""
LF Contract Check v0.1

Sandbox validator for TEST_GITHUB_CONTRACT_GATE_LF_SANDBOX_001.
This script is intentionally restrictive: it only allows changes inside
sandbox/lf_contract_gate_test/** and blocks critical paths.
"""

import os
import subprocess
import sys
from pathlib import Path

CONTRACT_PATH = Path("sandbox/lf_contract_gate_test/lf_contract.yml")
ALLOWED_PREFIX = "sandbox/lf_contract_gate_test/"
BLOCKED_PREFIXES = [
    ".github/",
    "profiles/",
    "skills/",
    "official/",
    "production/",
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
    'activo_router: "ACT-0001"',
    'vista: "public.v_lf_fuente_operativa"',
    'operation_code: "GITHUB_CONTRACT_GATE_SANDBOX"',
    'impacto_productivo: false',
    'estado_salida_permitido: "SANDBOX_TESTED"',
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


def validate_changed_files(changed_files: list[str]) -> None:
    if not changed_files:
        fail("FAIL_NO_CHANGED_FILES", "No se detectaron archivos modificados")

    for path in changed_files:
        for blocked in BLOCKED_PREFIXES:
            if path.startswith(blocked):
                fail("FAIL_BLOCKED_PATH_TOUCHED", f"Ruta bloqueada tocada: {path}")

        if not path.startswith(ALLOWED_PREFIX):
            fail("FAIL_SCOPE_INVALID", f"Archivo fuera de scope sandbox: {path}")


def validate_forbidden_terms(changed_files: list[str]) -> None:
    for path in changed_files:
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
    pass_check("Contrato LF válido y scope sandbox respetado")


if __name__ == "__main__":
    main()
