#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
from copy import deepcopy
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
RUNTIME_DIR = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime"
if str(RUNTIME_DIR) not in sys.path:
    sys.path.insert(0, str(RUNTIME_DIR))

from runtime_authority_resolver_v1 import RuntimeContextBlocked, resolve_runtime_context  # noqa: E402


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(root: Path, relative: str, content: str) -> dict[str, str]:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return {"ref": relative, "sha256": sha(path)}


def expect_block(code: str, fn) -> None:
    try:
        fn()
    except RuntimeContextBlocked as exc:
        assert exc.code == code, (exc.code, code, exc.detail)
        return
    raise AssertionError(f"expected block {code}")


def base_fixture(root: Path):
    card = write(root, "cards/demo/decision/CARD.md", "# Demo card\nRequired: decision\n")
    authority = write(root, "gobernanza/demo/product_authority.md", "canonical product authority\n")
    adapter_doc = write(root, "adapters/demo/ADAPTER.md", "demo adapter\n")
    request = {
        "input_literal": "Decidir CTA de la pantalla demo",
        "lf_adapter_bindings": [
            {
                "canonical_adapter_id": "DEMO_ADAPTER",
                "current_path": adapter_doc["ref"],
                "sha256": adapter_doc["sha256"],
                "binding_ref": "router://demo-adapter-binding",
            }
        ],
    }
    context = {
        "surface_code": "DEMO_SCREEN",
        "task_code": "PRODUCT_DECISION",
        "current_run_id": "RUN-S26-B-001",
        "input_fields": {"decision": "CTA primario"},
        "card_candidates": [
            {
                "card_id": "CARD-DEMO-001",
                **card,
                "surface_codes": ["DEMO_SCREEN"],
                "task_codes": ["PRODUCT_DECISION"],
                "required_input_fields": ["decision"],
            }
        ],
        "required_authority_types": ["PRODUCT_AUTHORITY"],
        "authority_sources": [
            {
                "authority_type": "PRODUCT_AUTHORITY",
                "authority_id": "AUTH-DEMO-001",
                "run_id": "RUN-S26-B-001",
                **authority,
            }
        ],
        "required_adapter_codes": ["DEMO_ADAPTER"],
    }
    return request, context, authority


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="s26-b-authority-") as td:
        root = Path(td)
        request, context, authority = base_fixture(root)

        resolved = resolve_runtime_context(context, request=request, repo_root=root)
        assert resolved["schema"] == "LF_RUNTIME_TYPED_CONTEXT_V1"
        assert resolved["card_resolution"]["status"] == "RESOLVED"
        assert resolved["card_resolution"]["card_id"] == "CARD-DEMO-001"
        assert resolved["card_resolution"]["schema_invention_allowed"] is False
        assert resolved["authority_resolution"][0]["authority_id"] == "AUTH-DEMO-001"
        assert resolved["adapter_binding"][0]["adapter_code"] == "DEMO_ADAPTER"
        assert resolved["adapter_binding"][0]["sha256"] == request["lf_adapter_bindings"][0]["sha256"]
        assert resolved["provenance"]["adapters"][0]["sha256"] == request["lf_adapter_bindings"][0]["sha256"]
        assert len(resolved["typed_context_sha256"]) == 64

        no_card = deepcopy(context)
        no_card["card_candidates"] = []
        fallback = resolve_runtime_context(no_card, request=request, repo_root=root)
        card_fallback = fallback["card_resolution"]
        assert card_fallback["status"] == "FALLBACK"
        assert card_fallback["mode"] == "NO_CARD_GOVERNED"
        assert card_fallback["card_id"] is None
        assert card_fallback["schema_invention_allowed"] is False
        assert "runtime_output_schema" not in card_fallback

        ambiguous_card = deepcopy(context)
        second = deepcopy(ambiguous_card["card_candidates"][0])
        second["card_id"] = "CARD-DEMO-002"
        ambiguous_card["card_candidates"].append(second)
        expect_block(
            "RUNTIME_CARD_AMBIGUOUS",
            lambda: resolve_runtime_context(ambiguous_card, request=request, repo_root=root),
        )

        missing_authority = deepcopy(context)
        missing_authority["authority_sources"] = []
        expect_block(
            "RUNTIME_AUTHORITY_MISSING",
            lambda: resolve_runtime_context(missing_authority, request=request, repo_root=root),
        )

        incompatible_authority = deepcopy(context)
        alt = write(root, "gobernanza/demo/product_authority_alt.md", "conflicting product authority\n")
        incompatible_authority["authority_sources"].append(
            {
                "authority_type": "PRODUCT_AUTHORITY",
                "authority_id": "AUTH-DEMO-002",
                "run_id": "RUN-S26-B-001",
                **alt,
            }
        )
        expect_block(
            "RUNTIME_AUTHORITY_INCOMPATIBLE",
            lambda: resolve_runtime_context(incompatible_authority, request=request, repo_root=root),
        )

        missing_adapter_context = deepcopy(context)
        missing_adapter_context["required_adapter_codes"] = ["REQUIRED_BUT_MISSING"]
        expect_block(
            "RUNTIME_ADAPTER_MISSING",
            lambda: resolve_runtime_context(missing_adapter_context, request=request, repo_root=root),
        )

        missing_adapter_sha = deepcopy(request)
        missing_adapter_sha["lf_adapter_bindings"][0].pop("sha256")
        expect_block(
            "RUNTIME_ADAPTER_SHA_MISSING",
            lambda: resolve_runtime_context(context, request=missing_adapter_sha, repo_root=root),
        )

        bad_adapter_sha = deepcopy(request)
        bad_adapter_sha["lf_adapter_bindings"][0]["sha256"] = "0" * 64
        expect_block(
            "RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH",
            lambda: resolve_runtime_context(context, request=bad_adapter_sha, repo_root=root),
        )

        incompatible_input = deepcopy(context)
        incompatible_input["input_fields"] = {}
        expect_block(
            "RUNTIME_CARD_REQUIRED_INPUT_MISSING",
            lambda: resolve_runtime_context(incompatible_input, request=request, repo_root=root),
        )

        cross_run = deepcopy(context)
        cross_run["authority_sources"][0]["run_id"] = "RUN-OTHER-001"
        expect_block(
            "RUNTIME_CROSS_RUN_REFERENCE_UNDECLARED",
            lambda: resolve_runtime_context(cross_run, request=request, repo_root=root),
        )

        declared_only = deepcopy(cross_run)
        declared_only["authority_sources"][0]["cross_run_declared"] = True
        expect_block(
            "RUNTIME_CROSS_RUN_AUTHORIZATION_MISSING",
            lambda: resolve_runtime_context(declared_only, request=request, repo_root=root),
        )

        permit = write(
            root,
            "gobernanza/demo/cross_run_auth.json",
            json.dumps(
                {
                    "schema": "LF_CROSS_RUN_AUTHORIZATION_V1",
                    "authority_id": "AUTH-DEMO-001",
                    "source_run_id": "RUN-OTHER-001",
                    "target_run_id": "RUN-S26-B-001",
                    "authorized": True,
                },
                sort_keys=True,
            ),
        )
        permitted_cross_run = deepcopy(declared_only)
        permitted_cross_run["authority_sources"][0]["cross_run_authorization_ref"] = permit["ref"]
        permitted_cross_run["authority_sources"][0]["cross_run_authorization_sha256"] = permit["sha256"]
        permitted = resolve_runtime_context(permitted_cross_run, request=request, repo_root=root)
        auth_row = permitted["authority_resolution"][0]
        assert auth_row["run_id"] == "RUN-OTHER-001"
        assert auth_row["cross_run_authorization"]["sha256"] == permit["sha256"]

        wrong_permit = write(
            root,
            "gobernanza/demo/cross_run_auth_wrong.json",
            json.dumps(
                {
                    "schema": "LF_CROSS_RUN_AUTHORIZATION_V1",
                    "authority_id": "AUTH-DEMO-001",
                    "source_run_id": "RUN-OTHER-001",
                    "target_run_id": "RUN-WRONG-999",
                    "authorized": True,
                },
                sort_keys=True,
            ),
        )
        invalid_cross_run = deepcopy(declared_only)
        invalid_cross_run["authority_sources"][0]["cross_run_authorization_ref"] = wrong_permit["ref"]
        invalid_cross_run["authority_sources"][0]["cross_run_authorization_sha256"] = wrong_permit["sha256"]
        expect_block(
            "RUNTIME_CROSS_RUN_AUTHORIZATION_INVALID",
            lambda: resolve_runtime_context(invalid_cross_run, request=request, repo_root=root),
        )

        missing_typed_context = lambda: resolve_runtime_context(None, request=request, repo_root=root)
        expect_block("RUNTIME_TYPED_CONTEXT_REQUIRED", missing_typed_context)

        broken_provenance = deepcopy(context)
        broken_provenance["authority_sources"][0]["sha256"] = "0" * 64
        expect_block(
            "RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH",
            lambda: resolve_runtime_context(broken_provenance, request=request, repo_root=root),
        )

        compatible_duplicate = deepcopy(context)
        compatible_duplicate["authority_sources"].append(
            {
                "authority_type": "PRODUCT_AUTHORITY",
                "authority_id": "AUTH-DEMO-ALIAS",
                "run_id": "RUN-S26-B-001",
                **authority,
            }
        )
        compatible = resolve_runtime_context(compatible_duplicate, request=request, repo_root=root)
        assert len(compatible["authority_resolution"]) == 2

    print(
        "RUNTIME_AUTHORITY_RESOLVER_V1_PASS "
        "card_found=1 no_card=1 negative_blocks=11 compatible_authority_alias=1 valid_cross_run_permit=1"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
