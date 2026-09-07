#!/usr/bin/env python3
"""S26 zero-cost sandbox benchmark of the already-pinned Qwen2.5-VL-7B model.

This is capability evidence only. The model remains authorized as the semantic
mini-judge, not as the primary profile worker. A PASS here cannot promote or
change authority; it only decides whether a governed authority-change proposal
is worth opening.

The first exact-source attempt intentionally used the complete UI profile/card/
adapter prompt and exceeded the existing 240s request timeout. Per LF API/job
policy, this benchmark does not increase timeout first. It instead uses a bounded
capability capsule plus exact source hashes, a smaller context, and the already-
governed focused output budget. This isolates model capability from prompt-load
cost without claiming operational-profile parity.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "services" / "profile_runtime_api"))

from profile_runtime_api.llama import governed_generation_schema
from profile_runtime_api.repository import RepositoryBindings
from profile_runtime_api.validation import OutputGates

MODEL_ID = (
    "ggml-org/Qwen2.5-VL-7B-Instruct-GGUF@"
    "508edd0afaa66bb9e9f40587acc2184f02daf1f6:"
    "Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
)
MODEL_SHA256 = "9258bf05b12686d097ff3b6b18d968ab393649780aa2b3cd67fec43d50554392"
LLAMA_COMMIT = "925e1179947ea0c0ebfb0032df18af3a729822be"
PORT = 18081
CONTEXT_TOKENS = 2048
MAX_OUTPUT_TOKENS = 256
REQUEST_TIMEOUT_SECONDS = 240
PROMPT_POLICY = "S26_QWEN7B_COMPACT_AUTHORITY_CAPSULE_V1"

PROFILE_PATH = REPO_ROOT / "profiles/ui_architect/SKILL.md"
CARD_PATH = REPO_ROOT / "cards/marketplace_lf/decision_product_experience/CARD.md"
ADAPTER_PATH = REPO_ROOT / "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml"

TASK = (
    "B2B-CARGA-001. TASK: REMEDIATE_EXISTING. Focused UI decision only: decide the visual "
    "treatment and interaction cue for horizontal table overflow in the existing Historial de cargas "
    "screen. Use only governed current facts below; preserve existing filters, actions and table "
    "semantics. Return the Focused UI Decision Spec only."
)

GOVERNED_FACTS = """
- Screen: B2B-CARGA-001 / Historial de cargas.
- Wide operational table columns: Lote, Nombre, Archivo, Tipo, Cargado por, Fecha, Total, Validos, Estado, Acciones.
- Preserve filters, row actions, pagination, table semantics and existing business rules.
- No exact canonical horizontal-overflow treatment is already authorized; this is intentionally a novel semantic decision.
- Existing source-bound values available without invention: card_surface, border_soft, navy_core, navy_soft, radius_16, b2b_table_row_height.
- Do not invent a new button, chevron control, hidden action, business rule, token or canonical pattern merely to obtain PASS.
- The selected treatment must be a physical UI mechanic plus a passive discoverability cue, implementation-usable, and subordinate to table content/actions.
- hard_exclusions are rejected alternatives only and must not repeat or contradict the selected treatment.
""".strip()

FOCUSED_QUALITY_CAPSULE = """
Sandbox capability capsule distilled from the current governed UI focused-decision contract:
1. Return exactly one naked JSON object satisfying the supplied schema. No prose or Markdown fences.
2. decision_subject must name the exact UI attribute being decided.
3. selected_visual_type must name a concrete corrective visual/interaction treatment, not merely the defect or subject.
4. base_color_or_surface must reference a concrete existing token/surface/value when used.
5. size_or_coverage must state where and how much of the table/screen the treatment covers.
6. density_limits must contain an observable quantity/bound/per-element rule.
7. depth_style and visual_weight must be concrete, not labels such as subtle, medium, thin or standard.
8. relationship_to_main_element must explain how the cue/mechanic relates to table content/actions.
9. implementation_format must name a concrete implementation target plus behavior/property/value; bare css/svg/component is invalid.
10. hard_exclusions must contain rejected alternatives only and must not repeat or prohibit the selected treatment.
11. Do not invent facts, controls, business rules, tokens or an already-authorized canonical pattern.
12. status must remain read-only/sandbox appropriate; this benchmark never authorizes production or promotion.
""".strip()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def required_path(name: str) -> Path:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"{name}_MISSING")
    path = Path(value)
    if not path.is_file():
        raise RuntimeError(f"{name}_NOT_FILE")
    return path


def health_ready(base_url: str) -> bool:
    try:
        with urllib.request.urlopen(base_url + "/health", timeout=2) as response:
            body = json.loads(response.read().decode("utf-8"))
        return response.status == 200 and isinstance(body, dict) and body.get("status") == "ok"
    except Exception:
        return False


def output_content(envelope: dict[str, Any]) -> tuple[str, str]:
    choices = envelope.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        raise RuntimeError("QWEN7B_CHOICES_MISSING")
    message = choices[0].get("message")
    if not isinstance(message, dict):
        raise RuntimeError("QWEN7B_MESSAGE_MISSING")
    content = message.get("content")
    if isinstance(content, list):
        content = "".join(part.get("text", "") for part in content if isinstance(part, dict))
    if not isinstance(content, str) or not content.strip():
        raise RuntimeError("QWEN7B_CONTENT_EMPTY")
    return content.strip(), str(choices[0].get("finish_reason") or "")


def source_hashes() -> dict[str, str]:
    return {
        "ui_architect_skill_sha256": sha256_file(PROFILE_PATH),
        "decision_card_sha256": sha256_file(CARD_PATH),
        "adapter_capsule_sha256": sha256_file(ADAPTER_PATH),
    }


def build_system_prompt() -> str:
    return "\n\n".join(
        [
            "SANDBOX PRIMARY-WORKER CAPABILITY BENCHMARK ONLY. "
            "This bounded capsule does not replace canonical sources and cannot authorize promotion.",
            FOCUSED_QUALITY_CAPSULE,
            "GOVERNED CURRENT FACTS:\n" + GOVERNED_FACTS,
        ]
    )


def main() -> int:
    if os.getenv("LF_REPOSITORY_VISIBILITY", "").strip() != "public":
        print("BLOCK S26_QWEN7B_ZERO_COST_VISIBILITY")
        return 2
    if os.getenv("LF_RUNNER_LABEL", "").strip() != "ubuntu-latest":
        print("BLOCK S26_QWEN7B_ZERO_COST_RUNNER")
        return 2
    if os.getenv("LF_LLAMA_SOURCE_COMMIT", "").strip() != LLAMA_COMMIT:
        print("BLOCK S26_QWEN7B_LLAMA_COMMIT_MISMATCH")
        return 2

    server = required_path("LF_LLAMA_SERVER_PATH")
    model = required_path("LF_SEMANTIC_MODEL_PATH")
    if not os.access(server, os.X_OK):
        print("BLOCK S26_QWEN7B_SERVER_NOT_EXECUTABLE")
        return 2
    observed_model_sha = sha256_file(model)
    if observed_model_sha != MODEL_SHA256:
        print("BLOCK S26_QWEN7B_MODEL_SHA_MISMATCH")
        return 2

    repository = RepositoryBindings(REPO_ROOT, max_prompt_chars=120_000)
    gates = OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = governed_generation_schema(
        schema_binding.payload,
        profile_slug="ui_architect",
        schema_mode="UI_FOCUSED_DECISION",
    )
    system_prompt = build_system_prompt()
    source_evidence = source_hashes()
    print(
        "S26_QWEN7B_CAPSULE_PREFLIGHT="
        + json.dumps(
            {
                "prompt_policy": PROMPT_POLICY,
                "system_prompt_chars": len(system_prompt),
                "task_chars": len(TASK),
                "context_tokens": CONTEXT_TOKENS,
                "max_output_tokens": MAX_OUTPUT_TOKENS,
                "request_timeout_seconds": REQUEST_TIMEOUT_SECONDS,
                "timeout_increased": False,
                "source_hashes": source_evidence,
            },
            sort_keys=True,
        ),
        flush=True,
    )

    base_url = f"http://127.0.0.1:{PORT}"
    with tempfile.TemporaryDirectory(prefix="s26-qwen7b-primary-candidate-") as td:
        work = Path(td)
        stdout_path = work / "llama.stdout.log"
        stderr_path = work / "llama.stderr.log"
        with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open("w", encoding="utf-8") as stderr:
            process = subprocess.Popen(
                [
                    str(server), "-m", str(model), "--host", "127.0.0.1", "--port", str(PORT),
                    "-c", str(CONTEXT_TOKENS), "-t", "4",
                ],
                cwd=work,
                stdin=subprocess.DEVNULL,
                stdout=stdout,
                stderr=stderr,
                text=True,
            )
            try:
                deadline = time.monotonic() + 120
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        print("BLOCK S26_QWEN7B_SERVER_START_FAILED")
                        return 3
                    if health_ready(base_url):
                        break
                    time.sleep(0.5)
                else:
                    print("BLOCK S26_QWEN7B_SERVER_START_TIMEOUT")
                    return 3

                payload = {
                    "model": MODEL_ID,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": TASK},
                    ],
                    "stream": False,
                    "temperature": 0,
                    "top_p": 1,
                    "seed": 42,
                    "max_tokens": MAX_OUTPUT_TOKENS,
                    "cache_prompt": True,
                    "response_format": {"type": "json_object", "schema": generation_schema},
                }
                request = urllib.request.Request(
                    base_url + "/v1/chat/completions",
                    data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                    headers={"Content-Type": "application/json", "Accept": "application/json"},
                    method="POST",
                )
                started = time.monotonic()
                try:
                    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                        envelope = json.loads(response.read().decode("utf-8"))
                except urllib.error.HTTPError as exc:
                    print(f"BLOCK S26_QWEN7B_HTTP_ERROR status={exc.code}")
                    return 4
                except TimeoutError:
                    print(
                        "BLOCK S26_QWEN7B_TRANSPORT type=TimeoutError "
                        f"timeout={REQUEST_TIMEOUT_SECONDS} prompt_policy={PROMPT_POLICY}"
                    )
                    return 4
                except Exception as exc:
                    print(f"BLOCK S26_QWEN7B_TRANSPORT type={type(exc).__name__}")
                    return 4
                elapsed_s = round(time.monotonic() - started, 3)
                raw, finish_reason = output_content(envelope)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)

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
    usage = envelope.get("usage") if isinstance(envelope.get("usage"), dict) else {}
    result = {
        "scope": "SANDBOX_PRIMARY_WORKER_CAPABILITY_ONLY_NOT_OPERATIONAL_PARITY",
        "authority_changed": False,
        "current_authority": "SEMANTIC_MINI_JUDGE_ONLY",
        "provider": "local_llama_cpp_github_standard_public",
        "model_id": MODEL_ID,
        "model_sha256": observed_model_sha,
        "llama_source_commit": LLAMA_COMMIT,
        "github_run_id": os.getenv("GITHUB_RUN_ID", ""),
        "github_sha": os.getenv("GITHUB_SHA", ""),
        "prompt_policy": PROMPT_POLICY,
        "source_hashes": source_evidence,
        "generation_schema_policy": generation_policy,
        "context_tokens": CONTEXT_TOKENS,
        "max_output_tokens": MAX_OUTPUT_TOKENS,
        "request_timeout_seconds": REQUEST_TIMEOUT_SECONDS,
        "timeout_increased": False,
        "elapsed_s": elapsed_s,
        "finish_reason": finish_reason,
        "usage": usage,
        "contract_gate": contract_gate,
        "semantic_gate": semantic_gate,
        "output": parsed if isinstance(parsed, dict) else None,
        "production_mutation": False,
        "promotion_authorized": False,
    }
    print("S26_QWEN7B_PRIMARY_CANDIDATE=" + json.dumps(result, ensure_ascii=False, sort_keys=True), flush=True)
    if contract_gate.get("status") == "PASS" and semantic_gate.get("status") == "PASS":
        print("S26_QWEN7B_PRIMARY_CANDIDATE_PASS", flush=True)
    else:
        print("S26_QWEN7B_PRIMARY_CANDIDATE_FAIL_CLOSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
