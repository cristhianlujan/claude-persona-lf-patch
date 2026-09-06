#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "services" / "profile_runtime_api"))

from profile_runtime_api.repository import RepositoryBindings
from profile_runtime_api.validation import OutputGates

MODEL = os.getenv("OPENAI_PROFILE_RUNTIME_MODEL", "gpt-5.6-terra").strip()
EXECUTION_ID = "GPT-S26-STRONG-AUTHORITY-CANARY-20260905-001"
INPUT_LITERAL = (
    "B2B-CARGA-001. TASK: REMEDIATE_EXISTING. Focused UI decision only: decide the visual "
    "treatment and interaction cue for horizontal table overflow in the existing Historial de cargas "
    "screen. Use only governed current context and observed evidence; preserve existing filters, actions "
    "and table semantics. Return the Focused UI Decision Spec only."
)
GOVERNED_FACTS = """
Governed current facts for this sandbox canary:
- Screen: B2B-CARGA-001 / Historial de cargas.
- The wide operational table exposes many columns including Lote, Nombre, Archivo, Tipo, Cargado por, Fecha, Total, Validos, Estado and Acciones.
- Preserve filters, row actions, pagination, table semantics and existing business rules.
- No exact canonical horizontal-overflow treatment already exists; this is intentionally a novel UI semantic decision.
- Existing source-bound data-table tokens that may be referenced without inventing new tokens: card_surface, border_soft, navy_core, navy_soft, radius_16, b2b_table_row_height.
- Do not invent a new button, chevron control, business rule, hidden action, token, or canonical pattern merely to obtain PASS.
- The selected treatment must be a physical UI mechanic plus a passive discoverability cue, implementation-usable, and subordinate to table content/actions.
""".strip()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def output_text(response: dict) -> str:
    parts: list[str] = []
    for item in response.get("output") or []:
        if not isinstance(item, dict) or item.get("type") != "message":
            continue
        for content in item.get("content") or []:
            if isinstance(content, dict) and content.get("type") == "output_text":
                text = content.get("text")
                if isinstance(text, str):
                    parts.append(text)
    return "".join(parts).strip()


def main() -> int:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        print("BLOCK OPENAI_API_KEY_MISSING")
        return 2
    if not MODEL:
        print("BLOCK OPENAI_MODEL_MISSING")
        return 2

    repository = RepositoryBindings(REPO_ROOT, max_prompt_chars=120_000)
    gates = OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")

    profile_source = (REPO_ROOT / "profiles/ui_architect/SKILL.md").read_text(encoding="utf-8")
    card_source = (
        REPO_ROOT / "cards/marketplace_lf/decision_product_experience/CARD.md"
    ).read_text(encoding="utf-8")
    adapter_source = (
        REPO_ROOT / "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml"
    ).read_text(encoding="utf-8")

    instructions = "\n\n".join(
        [
            "Execute the governed UI Architect profile for one sandbox-only semantic canary. "
            "Do not discuss the wrapper. Produce only the JSON object required by the supplied schema. "
            "Prefer the smallest viable visual treatment. Do not create business rules or interactive controls not authorized by the sources.",
            "--- UI ARCHITECT SOURCE ---\n" + profile_source,
            "--- DECISION CARD SOURCE ---\n" + card_source,
            "--- LF SHELL ADAPTER SOURCE ---\n" + adapter_source,
            "--- GOVERNED CURRENT FACTS ---\n" + GOVERNED_FACTS,
        ]
    )

    client_request_id = str(uuid.uuid4())
    payload = {
        "model": MODEL,
        "instructions": instructions,
        "input": INPUT_LITERAL,
        "store": False,
        "reasoning": {"effort": "medium"},
        "max_output_tokens": 1200,
        "text": {
            "format": {
                "type": "json_schema",
                "name": "ui_focused_decision",
                "description": "LF UI Architect Focused Decision Spec",
                "schema": schema_binding.payload,
                "strict": False,
            }
        },
        "metadata": {
            "execution_id": EXECUTION_ID,
            "profile_code": "PERFIL-UI-ARCHITECT",
            "operation_code": "EJECUCION_PERFIL_LF",
            "strategy": "26",
            "scope": "SANDBOX_STRONG_AUTHORITY_CANARY",
        },
    }

    request = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Client-Request-Id": client_request_id,
        },
    )

    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            body = response.read().decode("utf-8")
            provider = json.loads(body)
    except urllib.error.HTTPError as exc:
        detail = exc.read(8192).decode("utf-8", "replace")
        try:
            parsed = json.loads(detail)
            err = parsed.get("error") if isinstance(parsed, dict) else None
            code = err.get("code") or err.get("type") if isinstance(err, dict) else ""
        except Exception:
            code = ""
        print(f"BLOCK OPENAI_HTTP_ERROR status={exc.code} provider_code={code}")
        return 3
    except Exception as exc:
        print(f"BLOCK OPENAI_TRANSPORT_ERROR type={type(exc).__name__}")
        return 3
    elapsed_ms = round((time.monotonic() - started) * 1000, 3)

    if provider.get("status") != "completed":
        print("BLOCK OPENAI_RESPONSE_NOT_COMPLETED status=" + str(provider.get("status")))
        return 4
    raw = output_text(provider)
    if not raw:
        print("BLOCK OPENAI_RESPONSE_OUTPUT_EMPTY")
        return 4

    contract_gate, parsed = gates.contract(
        profile_slug="ui_architect",
        raw_output=raw,
        schema=schema_binding,
    )
    semantic_gate = gates.semantic_utility(
        profile_slug="ui_architect",
        payload=parsed,
        contract_gate=contract_gate,
    )

    usage = provider.get("usage") if isinstance(provider.get("usage"), dict) else {}
    result = {
        "execution_id": EXECUTION_ID,
        "model": provider.get("model") or MODEL,
        "provider_response_id": provider.get("id"),
        "provider_status": provider.get("status"),
        "client_request_id": client_request_id,
        "elapsed_ms": elapsed_ms,
        "input_tokens": usage.get("input_tokens"),
        "output_tokens": usage.get("output_tokens"),
        "total_tokens": usage.get("total_tokens"),
        "request_sha256": sha256_text(json.dumps(payload, ensure_ascii=False, sort_keys=True)),
        "output_sha256": sha256_text(raw),
        "contract_gate": contract_gate,
        "semantic_gate": semantic_gate,
        "output": parsed,
        "store": False,
    }
    out_path = REPO_ROOT / "s26_strong_authority_canary_result.json"
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")

    print("S26_STRONG_AUTHORITY_CANARY_RESULT=" + json.dumps(result, ensure_ascii=False, sort_keys=True))
    if contract_gate.get("status") != "PASS" or semantic_gate.get("status") != "PASS":
        return 5
    print("S26_STRONG_AUTHORITY_CANARY_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
