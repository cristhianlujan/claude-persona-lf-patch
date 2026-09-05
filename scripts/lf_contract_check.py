#!/usr/bin/env python3
"""
LF Contract Check v0.15

Sandbox validator for controlled LF governance gates.

v0.15 changes:
- Enforces ERROR_RECOVERY_AND_EVIDENCE_LADDER_V1 markers in the exact Profiles LF runbook.
- Fails closed if the four recovery routes, canonical-target check, exhaustion proof, literal evidence tuple, or closure guard disappear.

v0.14 changes:
- Allows only the exact Profile Driven Screen Generation workflow path for issue #402.
- Keeps the broad .github/ prefix and workflow lookalikes denied.

v0.13 changes:
- Allows only the exact Profiles LF operational runbook path under ops/.
- Keeps the broad ops/ prefix and runbook lookalikes denied.

v0.12 changes:
- Allows the exact historical compact-protocol locator under claude/ while
  keeping the broad claude/ prefix and all lookalikes denied.

v0.11 changes:
- Runs the governed profile runtime provenance/runner regression intrinsically.
- Keeps the runner inside the existing sandbox allowlist; no workflow path is widened.

v0.10 changes:
- Adds only the exact reconciled P0 source-derived documents and the exact V2
  persistence contract test produced by PR #140.
- Keeps both docs/p0 and supabase/tests default-denied as broad prefixes.
- Adds intrinsic lookalike negatives for the new exact paths.

v0.9 changes:
- Allows only the exact P0 closure evidence documents produced by the durable
  persistence/OCR completion scope.
- Runs an intrinsic fail-closed invariant that keeps sibling/lookalike docs/p0
  paths default-denied; the docs/ prefix is never broadly authorized.

v0.8 changes:
- Allows exactly three shared operational-protocol paths: CLAUDE.md,
  .claude/operational-execution.md, and .claude/scripts/validate_artifact_output.py.
- Runs an intrinsic fail-closed invariant that keeps sibling/lookalike .claude
  paths default-denied on every contract-check execution.

v0.7 changes:
- Allows only the exact approved GitHub workflow paths in addition to the existing contract check workflow.
- Keeps every other .github path default-denied.

v0.6 changes:
- Detects forbidden statuses only when they are assigned as actual output/state values.
- Does not flag NOT_VALIDATED or control documents that enumerate forbidden outputs.

v0.4 changes:
- Supports pull_request, push and workflow_dispatch events.
- Allows the sandbox NO BYPASS judge package path.
- Avoids false positives when control documents list forbidden statuses as prohibited outputs.
"""

import fnmatch
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CONTRACT_PATH = Path("sandbox/lf_contract_gate_test/lf_contract.yml")
RECEIPT_DIR = Path("sandbox/lf_contract_gate_test/receipts")
PROFILE_RUNTIME_TEST_PATH = Path("sandbox/lf_contract_gate_test/profile_execution_runtime/run_tests.py")
PROFILE_RUNTIME_PASS_MARKER = "PROFILE_RUNTIME_GATE_TESTS_PASS 23/23"
VALIDATOR_SELF_PATH = "scripts/lf_contract_check.py"
PROFILES_RUNBOOK_PATH = Path("ops/runbook-profiles-lf.md")
ERROR_RECOVERY_LADDER_REQUIRED_MARKERS = [
    "ERROR_RECOVERY_AND_EVIDENCE_LADDER_V1",
    "ONE_ROUTE_FAILURE != BLOCKER",
    "CANONICAL_TARGET_CHECK",
    "Route A — ORIGINAL",
    "Route B — FOCAL_MINIMAL",
    "Route C — CANONICAL_EQUIVALENT",
    "Route D — INDEPENDENT_AUTHORIZED",
    "BLOCKED_CAUSAL",
    "raw_request",
    "raw_response",
    "failure_layer",
    "recovery_route",
    "exhaustion evidence",
    "closure is forbidden",
]
COMPACT_PROTOCOL_PATH = Path("docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md")
COMPACT_PROTOCOL_LOCATOR_PATH = Path("claude/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md")
COMPACT_PROTOCOL_TOP_LEVEL_FIELDS = [
    "status",
    "blocking_code",
    "asset_code",
    "asset_type",
    "action_code",
    "operation_code",
    "operation_payload",
    "adapter_payload",
]

ALLOWED_GITHUB_EXACT = {
    ".github/workflows/lf-contract-check.yml",
    ".github/workflows/lf-bootstrap-reproducibility.yml",
    ".github/workflows/lf-github-reconcile-v3.yml",
    ".github/workflows/story-agent-evidence-verifier.yml",
    ".github/workflows/profile-driven-screen-generation.yml",
    ".github/workflows/input-governance-pr418-holdout-replay.yml",
}
OPERATIONAL_PROTOCOL_ALLOWED_EXACT = {
    "CLAUDE.md",
    ".claude/operational-execution.md",
    ".claude/scripts/validate_artifact_output.py",
    "docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md",
    "claude/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md",
    "ops/runbook-profiles-lf.md",
}
OPERATIONAL_PROTOCOL_DENIED_LOOKALIKES = {
    "CLAUDE.md.bak",
    ".claude/operational-execution.md.bak",
    ".claude/operational-execution/child.md",
    ".claude/scripts/validate_artifact_output.py.bak",
    ".claude/scripts/extra.py",
    ".claude/other.md",
    "docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md.bak",
    "docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF/child.md",
    "docs/operations/protocolo_consumo_compacto_router_lf.md",
    "claude/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md.bak",
    "claude/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF/child.md",
    "claude/protocolo_consumo_compacto_router_lf.md",
    "claude/OTHER_PROTOCOL.md",
    "ops/runbook-profiles-lf.md.bak",
    "ops/runbook-profiles-lf/child.md",
    "ops/RUNBOOK-PROFILES-LF.md",
    "ops/other.md",
}
P0_CLOSURE_EVIDENCE_ALLOWED_EXACT = {
    "docs/p0/CONTRATO_BENCHMARK_OCR_CV.md",
    "docs/p0/MAPA_BRECHAS_OCR_CV.md",
    "docs/p0/MATRIZ_OPCIONES_OCR_CV.md",
    "docs/p0/PERSISTENCE_CONTRACT_AUDIT_20260812.md",
    "docs/p0/REAL_PERSISTENCE_READBACK_20260812.md",
    "docs/p0/RESEARCH_OCR_SCREEN_P0.md",
    "docs/p0/persistence-normalization-config-v1.json",
    "docs/p0/P0_EXECUTION_PERSISTENCE_CONTRACT_V2.md",
    "docs/p0/ADR_OCR_UI_PIPELINE_20260812.md",
    "docs/p0/OCR_BENCHMARK_PLAN.md",
    "docs/p0/OCR_GAP_MATRIX.md",
    "docs/p0/OCR_RESEARCH_REPORT.md",
}
P0_CLOSURE_EVIDENCE_DENIED_LOOKALIKES = {
    "docs/p0/CONTRATO_BENCHMARK_OCR_CV.md.bak",
    "docs/p0/P0_EXECUTION_PERSISTENCE_CONTRACT_V2.md.bak",
    "docs/p0/OCR_RESEARCH_REPORT.md.tmp",
    "docs/p0/OCR_BENCHMARK_PLAN/child.md",
    "docs/p0/UNSCOPED.md",
    "docs/p0/subdir/RESEARCH_OCR_SCREEN_P0.md",
    "docs/P0/RESEARCH_OCR_SCREEN_P0.md",
}
P0_PERSISTENCE_TEST_ALLOWED_EXACT = {
    "supabase/tests/p0_execution_persistence_v2_contract.sql",
}
P0_PERSISTENCE_TEST_DENIED_LOOKALIKES = {
    "supabase/tests/p0_execution_persistence_v2_contract.sql.bak",
    "supabase/tests/p0_execution_persistence_v1_contract.sql",
    "supabase/tests/p0_execution_persistence_v3_contract.sql",
    "supabase/tests/subdir/p0_execution_persistence_v2_contract.sql",
}
ALLOWED_EXACT = {
    *ALLOWED_GITHUB_EXACT,
    VALIDATOR_SELF_PATH,
    *OPERATIONAL_PROTOCOL_ALLOWED_EXACT,
    *P0_CLOSURE_EVIDENCE_ALLOWED_EXACT,
    *P0_PERSISTENCE_TEST_ALLOWED_EXACT,
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
    "adapters/",
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

FORBIDDEN_STATUS_ASSIGNMENT = re.compile(
    r"(?:"
    r"^\s*(?:[-*]\s*)?(?:status|estado|state|result|resultado)\s*[:=]\s*`?"
    r"(?:VALIDATED|PRODUCTION|PRODUCTION_READY|PRODUCTION_AUTHORIZED|PRODUCCION|APROBADO_FINAL|OPERATIVO_GENERAL)\b"
    r"|"
    r'\"(?:status|estado|state|result|resultado)\"\s*:\s*\"'
    r"(?:VALIDATED|PRODUCTION|PRODUCTION_READY|PRODUCTION_AUTHORIZED|PRODUCCION|APROBADO_FINAL|OPERATIVO_GENERAL)\""
    r")",
    re.IGNORECASE | re.MULTILINE,
)

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


def validate_operational_protocol_scope() -> None:
    failures: list[str] = []
    if ".claude/" in ALLOWED_PREFIXES:
        failures.append("dot_claude_prefix_must_remain_denied")
    if "claude/" in ALLOWED_PREFIXES:
        failures.append("claude_prefix_must_remain_denied")
    if "ops/" in ALLOWED_PREFIXES:
        failures.append("ops_prefix_must_remain_denied")
    for path in sorted(OPERATIONAL_PROTOCOL_ALLOWED_EXACT):
        if not is_allowed_path(path):
            failures.append(f"approved_exact_missing:{path}")
    for path in sorted(OPERATIONAL_PROTOCOL_DENIED_LOOKALIKES):
        if is_allowed_path(path):
            failures.append(f"lookalike_unexpectedly_allowed:{path}")
    if failures:
        fail("FAIL_OPERATIONAL_PROTOCOL_SCOPE_INVARIANT", ",".join(failures))
    print(
        "PASS_OPERATIONAL_PROTOCOL_SCOPE_INVARIANT: "
        f"approved={len(OPERATIONAL_PROTOCOL_ALLOWED_EXACT)} "
        f"denied={len(OPERATIONAL_PROTOCOL_DENIED_LOOKALIKES)}"
    )


def validate_error_recovery_ladder_contract() -> None:
    if not PROFILES_RUNBOOK_PATH.exists():
        fail("FAIL_ERROR_RECOVERY_LADDER_RUNBOOK_MISSING", str(PROFILES_RUNBOOK_PATH))
    runbook = PROFILES_RUNBOOK_PATH.read_text(encoding="utf-8")
    missing = [marker for marker in ERROR_RECOVERY_LADDER_REQUIRED_MARKERS if marker not in runbook]
    if missing:
        fail("FAIL_ERROR_RECOVERY_LADDER_INVARIANT", ",".join(missing))
    route_positions = [
        runbook.index("Route A — ORIGINAL"),
        runbook.index("Route B — FOCAL_MINIMAL"),
        runbook.index("Route C — CANONICAL_EQUIVALENT"),
        runbook.index("Route D — INDEPENDENT_AUTHORIZED"),
    ]
    if route_positions != sorted(route_positions) or len(set(route_positions)) != 4:
        fail("FAIL_ERROR_RECOVERY_LADDER_ROUTE_ORDER", str(route_positions))
    if "ONE_ROUTE_FAILURE" not in runbook or "never stop conditions" not in runbook:
        fail("FAIL_ERROR_RECOVERY_LADDER_CLOSURE_GUARD", "missing one-route closure invariant")
    print(
        "PASS_ERROR_RECOVERY_LADDER_INVARIANT: "
        f"markers={len(ERROR_RECOVERY_LADDER_REQUIRED_MARKERS)} routes=4 order=A>B>C>D"
    )


def validate_compact_protocol_contract() -> None:
    if not COMPACT_PROTOCOL_PATH.exists():
        fail("FAIL_COMPACT_PROTOCOL_MISSING", str(COMPACT_PROTOCOL_PATH))
    if not COMPACT_PROTOCOL_LOCATOR_PATH.exists():
        fail("FAIL_COMPACT_PROTOCOL_LOCATOR_MISSING", str(COMPACT_PROTOCOL_LOCATOR_PATH))

    protocol = COMPACT_PROTOCOL_PATH.read_text(encoding="utf-8")
    if "Estado del documento: PROMOVIDO v1.0" not in protocol:
        fail("FAIL_COMPACT_PROTOCOL_STATUS", "El protocolo compacto no está promovido a v1.0")

    projection_match = re.search(
        r"## 3\. Proyección canónica(?P<body>.*?)(?:\n###|\n## )",
        protocol,
        re.DOTALL,
    )
    if not projection_match:
        fail("FAIL_COMPACT_PROTOCOL_PROJECTION", "No se encontró la proyección canónica")
    fields = re.findall(r"^\d+\. `([^`]+)`$", projection_match.group("body"), re.MULTILINE)
    if fields != COMPACT_PROTOCOL_TOP_LEVEL_FIELDS:
        fail("FAIL_COMPACT_PROTOCOL_FIELDS", f"Campos superiores inválidos: {fields}")
    if "coalesce(raw.asset_code, raw.asset.codigo_activo)" not in protocol:
        fail(
            "FAIL_COMPACT_PROTOCOL_ASSET_NORMALIZATION",
            "Falta la normalización de asset_code para la caché de adapters",
        )

    helper_match = re.search(
        r"### 9\.2 Helper SQL de resolución\s*```sql(?P<sql>.*?)```",
        protocol,
        re.DOTALL,
    )
    if not helper_match:
        fail("FAIL_COMPACT_PROTOCOL_HELPER", "No se encontró el helper SQL de §9.2")
    helper_sql = helper_match.group("sql")
    if "target_hint" in helper_sql:
        fail("FAIL_COMPACT_PROTOCOL_TARGET_HINT", "El helper SQL no puede pasar target_hint")
    if "p_action_hint => :action_hint" not in helper_sql:
        fail("FAIL_COMPACT_PROTOCOL_ACTION_HINT", "El helper SQL debe pasar action_hint explícito")

    locator = COMPACT_PROTOCOL_LOCATOR_PATH.read_text(encoding="utf-8")
    if str(COMPACT_PROTOCOL_PATH).replace("\\", "/") not in locator:
        fail("FAIL_COMPACT_PROTOCOL_LOCATOR_TARGET", "El localizador no apunta a la fuente canónica")

    print("PASS_COMPACT_PROTOCOL_CONTRACT: promoted_v1 fields=8 target_hint=omitted locator=valid")


def validate_p0_closure_evidence_scope() -> None:
    failures: list[str] = []
    if "docs/" in ALLOWED_PREFIXES or "docs/p0/" in ALLOWED_PREFIXES:
        failures.append("docs_prefix_must_remain_denied")
    for path in sorted(P0_CLOSURE_EVIDENCE_ALLOWED_EXACT):
        if not is_allowed_path(path):
            failures.append(f"approved_exact_missing:{path}")
    for path in sorted(P0_CLOSURE_EVIDENCE_DENIED_LOOKALIKES):
        if is_allowed_path(path):
            failures.append(f"lookalike_unexpectedly_allowed:{path}")
    if failures:
        fail("FAIL_P0_CLOSURE_EVIDENCE_SCOPE_INVARIANT", ",".join(failures))
    print(
        "PASS_P0_CLOSURE_EVIDENCE_SCOPE_INVARIANT: "
        f"approved={len(P0_CLOSURE_EVIDENCE_ALLOWED_EXACT)} "
        f"denied={len(P0_CLOSURE_EVIDENCE_DENIED_LOOKALIKES)}"
    )


def validate_p0_persistence_test_scope() -> None:
    failures: list[str] = []
    if "supabase/tests/" in ALLOWED_PREFIXES:
        failures.append("supabase_tests_prefix_must_remain_denied")
    for path in sorted(P0_PERSISTENCE_TEST_ALLOWED_EXACT):
        if not is_allowed_path(path):
            failures.append(f"approved_exact_missing:{path}")
    for path in sorted(P0_PERSISTENCE_TEST_DENIED_LOOKALIKES):
        if is_allowed_path(path):
            failures.append(f"lookalike_unexpectedly_allowed:{path}")
    if failures:
        fail("FAIL_P0_PERSISTENCE_TEST_SCOPE_INVARIANT", ",".join(failures))
    print(
        "PASS_P0_PERSISTENCE_TEST_SCOPE_INVARIANT: "
        f"approved={len(P0_PERSISTENCE_TEST_ALLOWED_EXACT)} "
        f"denied={len(P0_PERSISTENCE_TEST_DENIED_LOOKALIKES)}"
    )


def validate_profile_runtime_regression() -> None:
    if not PROFILE_RUNTIME_TEST_PATH.exists():
        fail("FAIL_PROFILE_RUNTIME_TEST_MISSING", str(PROFILE_RUNTIME_TEST_PATH))
    result = subprocess.run(
        [sys.executable, str(PROFILE_RUNTIME_TEST_PATH)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="" if result.stderr.endswith("\n") else "\n")
    if result.returncode != 0:
        fail("FAIL_PROFILE_RUNTIME_REGRESSION", f"exit={result.returncode}")
    if PROFILE_RUNTIME_PASS_MARKER not in result.stdout:
        fail("FAIL_PROFILE_RUNTIME_REGRESSION_MARKER", PROFILE_RUNTIME_PASS_MARKER)
    print(f"PASS_PROFILE_RUNTIME_REGRESSION: {PROFILE_RUNTIME_PASS_MARKER}")


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

        if path.startswith(FORBIDDEN_GITHUB_PREFIX) and path not in ALLOWED_GITHUB_EXACT:
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
            match = FORBIDDEN_STATUS_ASSIGNMENT.search(content)
            if match:
                excerpt = " ".join(match.group(0).split())
                fail("FAIL_FORBIDDEN_STATUS", f"Asignación de estado prohibido encontrada en {path}: {excerpt}")


def main() -> None:
    validate_contract()
    validate_operational_protocol_scope()
    validate_error_recovery_ladder_contract()
    validate_compact_protocol_contract()
    validate_p0_closure_evidence_scope()
    validate_p0_persistence_test_scope()
    validate_profile_runtime_regression()
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