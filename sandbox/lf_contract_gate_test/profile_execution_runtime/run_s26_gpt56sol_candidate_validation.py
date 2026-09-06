#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "services" / "profile_runtime_api"))

from profile_runtime_api.repository import RepositoryBindings
from profile_runtime_api.validation import OutputGates

FIXTURE = (
    REPO_ROOT
    / "sandbox/lf_contract_gate_test/profile_execution_runtime/fixtures/s26_gpt56sol_novel_overflow_candidate.json"
)


def main() -> int:
    raw = FIXTURE.read_text(encoding="utf-8").strip()
    repository = RepositoryBindings(REPO_ROOT, max_prompt_chars=120_000)
    gates = OutputGates(repository)
    schema = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    contract_gate, payload = gates.contract(
        profile_slug="ui_architect",
        raw_output=raw,
        schema=schema,
    )
    semantic_gate = gates.semantic_utility(
        profile_slug="ui_architect",
        payload=payload,
        contract_gate=contract_gate,
    )
    result = {
        "fixture": str(FIXTURE.relative_to(REPO_ROOT)),
        "candidate_authority": "GPT-5.6 Sol interactive sandbox candidate",
        "provider_attested": False,
        "contract_gate": contract_gate,
        "semantic_gate": semantic_gate,
        "payload": payload,
    }
    print("S26_GPT56SOL_CANDIDATE_VALIDATION=" + json.dumps(result, ensure_ascii=False, sort_keys=True))
    if contract_gate.get("status") != "PASS":
        return 2
    if semantic_gate.get("status") != "PASS":
        return 3
    print("S26_GPT56SOL_CANDIDATE_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
