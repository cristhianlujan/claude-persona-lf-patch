#!/usr/bin/env python3
"""S26 sandbox-only provider-attested strong semantic authority canary.

Reuses the existing OpenAI Responses adapter and readback verifier. It does not
create a provider implementation, does not modify production routing, and is
hard-gated against accidental external/billable execution.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO_ROOT / "services" / "profile_runtime_api"))

from openai_responses_runtime import OpenAIResponsesAdapter, OpenAIResponsesReadbackVerifier
from profile_runtime_runner import RuntimeExecutionBlocked, execute_profile_runtime
from semantic_authority_router import STRONG_SEMANTIC_AUTHORITY, select_semantic_authority
from profile_runtime_api.repository import RepositoryBindings
from profile_runtime_api.validation import OutputGates

EXECUTION_ID = "GPT-S26-STRONG-AUTHORITY-PROVIDER-CANARY-20260906-001"
MODEL = os.getenv("OPENAI_PROFILE_RUNTIME_MODEL", "gpt-5.6-sol").strip()

BASE_INPUT = (
    "B2B-CARGA-001. TASK: REMEDIATE_EXISTING. Focused UI decision only: decide the visual "
    "treatment and interaction cue for horizontal table overflow in the existing Historial de cargas "
    "screen. Use only governed current context and observed evidence; preserve existing filters, actions "
    "and table semantics. Return the Focused UI Decision Spec only, as one naked JSON object, no Markdown fences."
)

GOVERNED_FACTS = """
Governed current facts for this sandbox provider canary:
- Screen: B2B-CARGA-001 / Historial de cargas.
- The wide operational table includes Lote, Nombre, Archivo, Tipo, Cargado por, Fecha, Total, Validos, Estado and Acciones.
- Preserve filters, row actions, pagination, table semantics and existing business rules.
- No exact canonical horizontal-overflow treatment is already authorized; this is intentionally a novel semantic decision.
- Existing source-bound values that may be referenced without inventing new tokens: card_surface, border_soft, navy_core, navy_soft, radius_16, b2b_table_row_height.
- Do not invent a new button, chevron control, hidden action, business rule, token or canonical pattern merely to obtain PASS.
- The selected treatment must be a physical UI mechanic plus a passive discoverability cue, implementation-usable, and subordinate to table content/actions.
- hard_exclusions are rejected alternatives only and must not repeat or contradict the selected treatment.
""".strip()


def _output_text(raw_output: Any) -> str:
    if not isinstance(raw_output, list):
        return ""
    parts: list[str] = []
    for item in raw_output:
        if not isinstance(item, dict) or item.get("type") != "message":
            continue
        for content in item.get("content") or []:
            if isinstance(content, dict) and content.get("type") == "output_text":
                text = content.get("text")
                if isinstance(text, str):
                    parts.append(text)
    return "".join(parts).strip()


def main() -> int:
    decision = select_semantic_authority(
        task_kind="NOVEL_DECISION",
        source_grounding_ready=False,
        authority_ref=None,
        requires_novel_judgment=True,
    )
    if decision.route != STRONG_SEMANTIC_AUTHORITY:
        print("BLOCK S26_SEMANTIC_AUTHORITY_ROUTE_NOT_STRONG")
        return 2

    if os.getenv("S26_EXTERNAL_CANARY_AUTHORIZED", "").strip() != "1":
        print("BLOCK S26_EXTERNAL_CANARY_AUTHORIZATION_MISSING")
        return 2
    if os.getenv("S26_EXTERNAL_CANARY_BILLING_ACK", "").strip() != "1":
        print("BLOCK S26_EXTERNAL_CANARY_BILLING_ACK_MISSING")
        return 2
    if not os.getenv("OPENAI_API_KEY", "").strip():
        print("BLOCK OPENAI_API_KEY_MISSING")
        return 2
    if not MODEL:
        print("BLOCK OPENAI_MODEL_MISSING")
        return 2

    profile_path = REPO_ROOT / "profiles/ui_architect/SKILL.md"
    profile_sources = [
        {
            "ref": "profiles/ui_architect/SKILL.md",
            "content": profile_path.read_text(encoding="utf-8"),
        }
    ]
    input_literal = BASE_INPUT + "\n\n" + GOVERNED_FACTS

    adapter = OpenAIResponsesAdapter(
        model=MODEL,
        reasoning_effort="medium",
        timeout_seconds=180,
        max_output_tokens=1200,
    )
    verifier = OpenAIResponsesReadbackVerifier(timeout_seconds=180)

    try:
        package = execute_profile_runtime(
            execution_id=EXECUTION_ID,
            profile_code="PERFIL-UI-ARCHITECT",
            profile_slug="ui_architect",
            profile_sources=profile_sources,
            input_literal=input_literal,
            adapter=adapter,
            attestation_verifier=verifier,
            allow_test_doubles=False,
        )
    except RuntimeExecutionBlocked as exc:
        print(f"BLOCK {exc.code}" + (f" detail={exc.detail}" if exc.detail else ""))
        return 3

    raw_text = _output_text(package.get("raw_output"))
    if not raw_text:
        print("BLOCK OPENAI_PROFILE_OUTPUT_TEXT_EMPTY")
        return 4

    repository = RepositoryBindings(REPO_ROOT, max_prompt_chars=120_000)
    gates = OutputGates(repository)
    schema = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    contract_gate, payload = gates.contract(
        profile_slug="ui_architect",
        raw_output=raw_text,
        schema=schema,
    )
    semantic_gate = gates.semantic_utility(
        profile_slug="ui_architect",
        payload=payload,
        contract_gate=contract_gate,
    )

    receipt = package.get("receipt") if isinstance(package.get("receipt"), dict) else {}
    attestation = receipt.get("runtime_attestation") if isinstance(receipt, dict) else {}
    result = {
        "execution_id": EXECUTION_ID,
        "scope": "SANDBOX_PROVIDER_VIABILITY_NOT_GOLDEN_CLOSURE",
        "semantic_authority_route": decision.route,
        "semantic_authority_reason": decision.reason_code,
        "model": attestation.get("model_id") if isinstance(attestation, dict) else MODEL,
        "provider": attestation.get("provider") if isinstance(attestation, dict) else None,
        "provider_response_id": attestation.get("run_id") if isinstance(attestation, dict) else None,
        "attestation_verifier": attestation.get("attestation_verifier") if isinstance(attestation, dict) else None,
        "contract_gate": contract_gate,
        "semantic_gate": semantic_gate,
        "output": payload,
        "production_mutation": False,
        "promotion_authorized": False,
    }
    print("S26_STRONG_AUTHORITY_PROVIDER_CANARY=" + json.dumps(result, ensure_ascii=False, sort_keys=True))

    if contract_gate.get("status") != "PASS":
        return 5
    if semantic_gate.get("status") != "PASS":
        return 6
    print("S26_STRONG_AUTHORITY_PROVIDER_CANARY_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
