#!/usr/bin/env python3
"""S26 zero-cost primary-worker capability benchmark.

Runs one explicitly pinned local GGUF candidate after the independent semantic
mini-judge smoke. This is sandbox capability evidence only: it cannot change
model authority, production routing, profile sources, or promotion state.

The benchmark keeps the bounded Focused UI capability capsule used after the
full-source Qwen2.5-VL-7B attempt hit the existing 240s ceiling. Per LF
API/job policy, timeout is not increased first. It performs one initial pass
and one explicitly declared contract-review pass over the exact initial RAW.
Both stages remain in evidence; there is no silent repair, validator change,
or automatic promotion. Candidate identity, exact source hashes, timing,
usage, contract and semantic gates are emitted for durable readback.
"""

from __future__ import annotations

import hashlib
import json
import os
import resource
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

LLAMA_COMMIT = "925e1179947ea0c0ebfb0032df18af3a729822be"
PORT = 18081
CONTEXT_TOKENS = 2048
MAX_OUTPUT_TOKENS = 384
REQUEST_TIMEOUT_SECONDS = 240
REVISION_ARCHITECTURE = "DECLARED_TWO_PASS_CONTRACT_REVIEW_WITH_RAW_BINDING_V2"
DECLARED_REVIEW_CODES = (
    "S26_PRESERVATION_EXPLICITNESS_REVIEW_REQUIRED",
    "S26_DUAL_IMPLEMENTATION_DETAIL_REVIEW_REQUIRED",
    "S26_EXCLUSION_CONSISTENCY_REVIEW_REQUIRED",
    "S26_NO_INVENTED_LIMITS_REVIEW_REQUIRED",
)

CANDIDATE_CODE = os.getenv(
    "LF_S26_PRIMARY_CANDIDATE_CODE", "QWEN3_5_4B_Q4_K_M_CONTRACT_ALIGNED"
).strip()
MODEL_REPO = os.getenv(
    "LF_S26_PRIMARY_CANDIDATE_REPO", "unsloth/Qwen3.5-4B-GGUF"
).strip()
MODEL_COMMIT = os.getenv(
    "LF_S26_PRIMARY_CANDIDATE_COMMIT",
    "720bb031aae5488eae5d6a78768e6d826662b2ae",
).strip()
MODEL_FILENAME = os.getenv(
    "LF_S26_PRIMARY_CANDIDATE_FILENAME", "Qwen3.5-4B-Q4_K_M.gguf"
).strip()
MODEL_SHA256 = os.getenv(
    "LF_S26_PRIMARY_CANDIDATE_SHA256",
    "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
).strip()
PROMPT_POLICY = os.getenv(
    "LF_S26_PRIMARY_CANDIDATE_PROMPT_POLICY",
    "S26_QWEN3_5_4B_SOURCE_BOUNDED_TWO_PASS_V3",
).strip()
DISABLE_THINKING = os.getenv(
    "LF_S26_PRIMARY_CANDIDATE_DISABLE_THINKING", "1"
).strip().lower() in {"1", "true", "yes", "on"}
MODEL_ID = f"{MODEL_REPO}@{MODEL_COMMIT}:{MODEL_FILENAME}"

PROFILE_PATH = REPO_ROOT / "profiles/ui_architect/SKILL.md"
CARD_PATH = REPO_ROOT / "cards/marketplace_lf/decision_product_experience/CARD.md"
ADAPTER_PATH = REPO_ROOT / "adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml"

TASK = (
    "B2B-CARGA-001. TASK: REMEDIATE_EXISTING. Focused UI decision only: decide the visual "
    "treatment and interaction cue for horizontal table overflow in the existing Historial de cargas "
    "screen. Use only governed current facts below. Preserve explicitly: existing filters, every "
    "table column, row actions, pagination, table semantics and business rules. Return the Focused "
    "UI Decision Spec only."
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
6. For this task, density_limits has exactly two grounded bounds: one passive cue per overflowing table viewport and zero added controls per row. Do not assert any pixel, percentage, row-count, pagination or breakpoint limit.
7. depth_style and visual_weight must be concrete. Preserve the existing flat surface without a new elevation or shadow. State visual_weight only as an explicit lower hierarchy relative to table data, statuses and row actions; do not invent a numeric value. Standalone labels primary, secondary, tertiary, medium, light, dark, standard, default or subtle (and Spanish equivalents) are invalid.
8. relationship_to_main_element must explain how the cue/mechanic relates to table content/actions and explicitly preserve existing filters, every column, row actions, pagination, table semantics and business rules.
9. implementation_format must name the implementation target, behavior and usable property/value for both the physical overflow mechanic and its passive discoverability cue; bare css/svg/component or a mechanic without its cue is invalid. If selecting the native scrollbar, state that CSS overflow-x: auto is applied to the existing table wrapper and the browser shows its native scrollbar while overflow exists; do not style its thumb or invent dimensions.
10. hard_exclusions must contain rejected alternatives only and must not repeat or prohibit the selected treatment.
11. Do not invent facts, controls, business rules, tokens or an already-authorized canonical pattern.
12. status must remain read-only/sandbox appropriate; this benchmark never authorizes production or promotion.
13. Outside the explicitly grounded counts one cue and zero added row controls, do not invent any quantitative value.
14. Complete every field as a self-contained statement; do not end a string mid-list, mid-condition or mid-clause. Keep each scalar field concise (at most 30 words), use at most four concise exclusions, and refer to all columns as “Lote through Acciones” instead of enumerating them.
""".strip()

REVISION_CAPSULE = """
One and only one declared revision is required for this sandbox capability test.
Re-evaluate the prior RAW decision against every governed fact and all fourteen
quality rules. Correct the underlying decision, not only a named gate label.
The final treatment must contain an implementable physical horizontal-overflow
mechanic plus a passive discoverability cue. Its implementation field must give
a target, behavior and usable property/value for both. Explicitly preserve
filters, every column, row actions, pagination, table semantics and business
rules. Avoid unsupported controls or tokens and keep every exclusion consistent
with the selected treatment. Use exactly one passive cue per overflowing
viewport and zero added controls per row; do not assert any other number, pixel,
percentage, row-count, pagination trigger or breakpoint. Express visual_weight
only as lower hierarchy relative to table data, statuses and actions, without a
number. If native scroll is selected, fully specify overflow-x: auto on the
existing table wrapper and a browser-native scrollbar visible while overflow
exists, with no thumb styling or invented dimension. Complete every field
without ending mid-list, mid-condition or mid-clause; keep scalar fields under
30 words and refer to all columns compactly as Lote through Acciones.
Do not claim that the treatment is already authorized. Return one new naked
JSON object only. The prior RAW and both evaluations remain preserved as
evidence; this revision cannot authorize production or promotion.
""".strip()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _linux_meminfo_kib() -> dict[str, int]:
    """Read a bounded runner memory snapshot without changing host state."""
    wanted = {"MemTotal", "MemAvailable", "SwapTotal", "SwapFree"}
    result: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            key, separator, remainder = line.partition(":")
            if separator and key in wanted:
                value = remainder.strip().split()[0]
                result[f"{key.lower()}_kib"] = int(value)
    except (OSError, ValueError, IndexError):
        return {}
    return result


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
        raise RuntimeError("PRIMARY_CANDIDATE_CHOICES_MISSING")
    message = choices[0].get("message")
    if not isinstance(message, dict):
        raise RuntimeError("PRIMARY_CANDIDATE_MESSAGE_MISSING")
    content = message.get("content")
    if isinstance(content, list):
        content = "".join(part.get("text", "") for part in content if isinstance(part, dict))
    if not isinstance(content, str) or not content.strip():
        raise RuntimeError("PRIMARY_CANDIDATE_CONTENT_EMPTY")
    return content.strip(), str(choices[0].get("finish_reason") or "")


def request_completion(
    *,
    base_url: str,
    messages: list[dict[str, str]],
    generation_schema: dict[str, Any],
) -> tuple[dict[str, Any], str, str, float]:
    payload: dict[str, Any] = {
        "model": MODEL_ID,
        "messages": messages,
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": MAX_OUTPUT_TOKENS,
        "cache_prompt": True,
        "response_format": {"type": "json_object", "schema": generation_schema},
    }
    if DISABLE_THINKING:
        payload["chat_template_kwargs"] = {"enable_thinking": False}
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
        detail = exc.read().decode("utf-8", errors="replace")[-1000:]
        raise RuntimeError(
            f"PRIMARY_CANDIDATE_HTTP_ERROR status={exc.code} "
            + detail.replace("\n", " ")
        ) from exc
    except TimeoutError as exc:
        raise RuntimeError(
            "PRIMARY_CANDIDATE_TRANSPORT type=TimeoutError "
            f"timeout={REQUEST_TIMEOUT_SECONDS} prompt_policy={PROMPT_POLICY}"
        ) from exc
    except Exception as exc:
        raise RuntimeError(
            f"PRIMARY_CANDIDATE_TRANSPORT type={type(exc).__name__}"
        ) from exc
    elapsed_s = round(time.monotonic() - started, 3)
    raw, finish_reason = output_content(envelope)
    return envelope, raw, finish_reason, elapsed_s


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


def exact_candidate_head() -> str:
    try:
        target = "HEAD^2" if os.getenv("GITHUB_EVENT_NAME") == "pull_request" else "HEAD"
        return subprocess.check_output(
            ["git", "rev-parse", target], cwd=REPO_ROOT, text=True
        ).strip()
    except Exception:
        return os.getenv("GITHUB_SHA", "")


def _safe_release_semantic_model(runner_temp: Path) -> None:
    raw = os.getenv("LF_SEMANTIC_MODEL_PATH", "").strip()
    if not raw:
        return
    judge_path = Path(raw).resolve()
    try:
        judge_path.relative_to(runner_temp)
    except ValueError:
        print("S26_PRIMARY_CANDIDATE_KEEP_JUDGE_MODEL reason=OUTSIDE_RUNNER_TEMP", flush=True)
        return
    if judge_path.is_file():
        size = judge_path.stat().st_size
        judge_path.unlink()
        print(f"S26_PRIMARY_CANDIDATE_RELEASE_JUDGE_MODEL bytes={size}", flush=True)


def _release_candidate_model_after_run(model_path: Path) -> bool:
    if os.getenv("LF_S26_PRIMARY_CANDIDATE_RELEASE_AFTER_RUN", "0").strip() != "1":
        return False
    runner_temp = Path(os.getenv("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
    resolved = model_path.resolve()
    try:
        resolved.relative_to(runner_temp)
    except ValueError as exc:
        raise RuntimeError("PRIMARY_CANDIDATE_RELEASE_PATH_OUTSIDE_RUNNER_TEMP") from exc
    if sha256_file(resolved) != MODEL_SHA256:
        raise RuntimeError("PRIMARY_CANDIDATE_RELEASE_SHA_MISMATCH")
    size = resolved.stat().st_size
    resolved.unlink()
    print(f"S26_PRIMARY_CANDIDATE_RELEASE_MODEL bytes={size}", flush=True)
    return True


def prepare_candidate_model() -> Path:
    runner_temp = Path(os.getenv("RUNNER_TEMP") or tempfile.gettempdir()).resolve()
    _safe_release_semantic_model(runner_temp)
    candidate_dir = runner_temp / "lf-s26-primary-candidate" / CANDIDATE_CODE.lower()
    candidate_dir.mkdir(parents=True, exist_ok=True)
    candidate_path = candidate_dir / "model.gguf"
    if candidate_path.is_file() and sha256_file(candidate_path) == MODEL_SHA256:
        print("S26_PRIMARY_CANDIDATE_MODEL_CACHE_HIT", flush=True)
        return candidate_path
    if candidate_path.exists():
        candidate_path.unlink()
    url = (
        f"https://huggingface.co/{MODEL_REPO}/resolve/{MODEL_COMMIT}/"
        f"{MODEL_FILENAME}?download=true"
    )
    print(
        "S26_PRIMARY_CANDIDATE_DOWNLOAD="
        + json.dumps(
            {
                "candidate_code": CANDIDATE_CODE,
                "model_repo": MODEL_REPO,
                "model_commit": MODEL_COMMIT,
                "model_filename": MODEL_FILENAME,
                "model_sha256": MODEL_SHA256,
            },
            sort_keys=True,
        ),
        flush=True,
    )
    subprocess.run(
        [
            "curl", "-L", "--fail", "--retry", "3", "--retry-delay", "2",
            url, "-o", str(candidate_path),
        ],
        check=True,
    )
    observed = sha256_file(candidate_path)
    if observed != MODEL_SHA256:
        candidate_path.unlink(missing_ok=True)
        raise RuntimeError(
            f"PRIMARY_CANDIDATE_MODEL_SHA_MISMATCH expected={MODEL_SHA256} observed={observed}"
        )
    return candidate_path


def main() -> int:
    if os.getenv("LF_REPOSITORY_VISIBILITY", "").strip() != "public":
        print("BLOCK S26_PRIMARY_CANDIDATE_ZERO_COST_VISIBILITY")
        return 2
    if os.getenv("LF_RUNNER_LABEL", "").strip() != "ubuntu-latest":
        print("BLOCK S26_PRIMARY_CANDIDATE_ZERO_COST_RUNNER")
        return 2
    if os.getenv("LF_LLAMA_SOURCE_COMMIT", "").strip() != LLAMA_COMMIT:
        print("BLOCK S26_PRIMARY_CANDIDATE_LLAMA_COMMIT_MISMATCH")
        return 2

    server = required_path("LF_LLAMA_SERVER_PATH")
    model = prepare_candidate_model()
    if not os.access(server, os.X_OK):
        print("BLOCK S26_PRIMARY_CANDIDATE_SERVER_NOT_EXECUTABLE")
        return 2
    observed_model_sha = sha256_file(model)
    if observed_model_sha != MODEL_SHA256:
        print("BLOCK S26_PRIMARY_CANDIDATE_MODEL_SHA_MISMATCH")
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
    candidate_head = exact_candidate_head()
    runner_meminfo_before = _linux_meminfo_kib()
    print(
        "S26_PRIMARY_CANDIDATE_PREFLIGHT="
        + json.dumps(
            {
                "candidate_code": CANDIDATE_CODE,
                "candidate_head": candidate_head,
                "model_id": MODEL_ID,
                "model_sha256": observed_model_sha,
                "prompt_policy": PROMPT_POLICY,
                "system_prompt_chars": len(system_prompt),
                "task_chars": len(TASK),
                "context_tokens": CONTEXT_TOKENS,
                "max_output_tokens": MAX_OUTPUT_TOKENS,
                "request_timeout_seconds": REQUEST_TIMEOUT_SECONDS,
                "timeout_increased": False,
                "thinking_disabled": DISABLE_THINKING,
                "source_hashes": source_evidence,
            },
            sort_keys=True,
        ),
        flush=True,
    )

    base_url = f"http://127.0.0.1:{PORT}"
    server_ready_elapsed_s: float | None = None
    server_started = time.monotonic()
    child_usage: dict[str, float | int] = {}
    with tempfile.TemporaryDirectory(prefix="s26-zero-cost-primary-candidate-") as td:
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
                        detail = stderr_path.read_text(encoding="utf-8", errors="replace")[-1200:]
                        print("BLOCK S26_PRIMARY_CANDIDATE_SERVER_START_FAILED detail=" + detail.replace("\n", " "))
                        return 3
                    if health_ready(base_url):
                        server_ready_elapsed_s = round(time.monotonic() - server_started, 3)
                        break
                    time.sleep(0.5)
                else:
                    print("BLOCK S26_PRIMARY_CANDIDATE_SERVER_START_TIMEOUT")
                    return 3

                try:
                    initial_envelope, initial_raw, initial_finish_reason, initial_elapsed_s = request_completion(
                        base_url=base_url,
                        messages=[
                            {"role": "system", "content": system_prompt},
                            {"role": "user", "content": TASK},
                        ],
                        generation_schema=generation_schema,
                    )
                except RuntimeError as exc:
                    print("BLOCK S26_" + str(exc))
                    return 4

                initial_contract_gate, initial_parsed = gates.contract(
                    profile_slug="ui_architect",
                    raw_output=initial_raw,
                    schema=schema_binding,
                )
                initial_semantic_gate = gates.semantic_utility(
                    profile_slug="ui_architect",
                    payload=initial_parsed,
                    contract_gate=initial_contract_gate,
                )
                gate_trigger_codes = sorted(set(
                    list(initial_contract_gate.get("blocking_codes") or [])
                    + list(initial_semantic_gate.get("blocking_codes") or [])
                ))
                revision_trigger_codes = sorted(
                    set(gate_trigger_codes + list(DECLARED_REVIEW_CODES))
                )
                revision_applied = True
                revision_request = "\n\n".join([
                    REVISION_CAPSULE,
                    "MACHINE GATE CODES FROM PRIOR RAW:\n"
                    + json.dumps(gate_trigger_codes, ensure_ascii=False),
                    "DECLARED CONTRACT REVIEW CODES:\n"
                    + json.dumps(list(DECLARED_REVIEW_CODES), ensure_ascii=False),
                ])
                try:
                    envelope, raw, finish_reason, revision_elapsed_s = request_completion(
                        base_url=base_url,
                        messages=[
                            {"role": "system", "content": system_prompt},
                            {"role": "user", "content": TASK},
                            {"role": "assistant", "content": initial_raw},
                            {"role": "user", "content": revision_request},
                        ],
                        generation_schema=generation_schema,
                    )
                except RuntimeError as exc:
                    print("BLOCK S26_PRIMARY_CANDIDATE_REVISION_" + str(exc))
                    return 4
                elapsed_s = round(initial_elapsed_s + revision_elapsed_s, 3)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
                usage_snapshot = resource.getrusage(resource.RUSAGE_CHILDREN)
                child_usage = {
                    "max_rss_kib": int(usage_snapshot.ru_maxrss),
                    "user_cpu_s": round(float(usage_snapshot.ru_utime), 3),
                    "system_cpu_s": round(float(usage_snapshot.ru_stime), 3),
                }

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
    initial_usage = (
        initial_envelope.get("usage")
        if isinstance(initial_envelope.get("usage"), dict)
        else {}
    )
    model_bytes = model.stat().st_size
    candidate_model_released_after_run = _release_candidate_model_after_run(model)
    runner_meminfo_after = _linux_meminfo_kib()
    result = {
        "scope": "SANDBOX_PRIMARY_WORKER_CAPABILITY_ONLY_NOT_OPERATIONAL_PARITY",
        "candidate_code": CANDIDATE_CODE,
        "candidate_head": candidate_head,
        "authority_changed": False,
        "current_semantic_judge_authority": "QWEN2_5_VL_7B_SEMANTIC_MINI_JUDGE_ONLY",
        "provider": "local_llama_cpp_github_standard_public",
        "model_id": MODEL_ID,
        "model_repo": MODEL_REPO,
        "model_commit": MODEL_COMMIT,
        "model_filename": MODEL_FILENAME,
        "model_sha256": observed_model_sha,
        "model_bytes": model_bytes,
        "candidate_model_released_after_run": candidate_model_released_after_run,
        "llama_source_commit": LLAMA_COMMIT,
        "github_run_id": os.getenv("GITHUB_RUN_ID", ""),
        "github_sha": os.getenv("GITHUB_SHA", ""),
        "prompt_policy": PROMPT_POLICY,
        "revision_architecture": REVISION_ARCHITECTURE,
        "revision_applied": revision_applied,
        "revision_trigger_codes": revision_trigger_codes,
        "initial_gate_trigger_codes": gate_trigger_codes,
        "declared_review_codes": list(DECLARED_REVIEW_CODES),
        "max_revision_passes": 1,
        "silent_repair": False,
        "source_hashes": source_evidence,
        "generation_schema_policy": generation_policy,
        "context_tokens": CONTEXT_TOKENS,
        "max_output_tokens": MAX_OUTPUT_TOKENS,
        "request_timeout_seconds": REQUEST_TIMEOUT_SECONDS,
        "timeout_increased": False,
        "thinking_disabled": DISABLE_THINKING,
        "elapsed_s": elapsed_s,
        "server_ready_elapsed_s": server_ready_elapsed_s,
        "child_process_resource_usage": child_usage,
        "runner_meminfo_before": runner_meminfo_before,
        "runner_meminfo_after": runner_meminfo_after,
        "finish_reason": finish_reason,
        "usage": usage,
        "inference_stages": {
            "initial": {
                "elapsed_s": initial_elapsed_s,
                "finish_reason": initial_finish_reason,
                "usage": initial_usage,
                "raw_output": initial_raw,
                "raw_output_sha256": hashlib.sha256(initial_raw.encode("utf-8")).hexdigest(),
                "contract_gate": initial_contract_gate,
                "semantic_gate": initial_semantic_gate,
                "output": initial_parsed if isinstance(initial_parsed, dict) else None,
            },
            "revision": {
                "executed": revision_applied,
                "elapsed_s": revision_elapsed_s,
                "raw_output": raw,
                "raw_output_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
            },
        },
        "contract_gate": contract_gate,
        "semantic_gate": semantic_gate,
        "output": parsed if isinstance(parsed, dict) else None,
        "raw_output": raw,
        "production_mutation": False,
        "promotion_authorized": False,
        "paid_provider_call_executed": False,
        "api_cost_incurred": False,
    }
    print("S26_ZERO_COST_PRIMARY_CANDIDATE=" + json.dumps(result, ensure_ascii=False, sort_keys=True), flush=True)
    if contract_gate.get("status") == "PASS" and semantic_gate.get("status") == "PASS":
        print("S26_ZERO_COST_PRIMARY_CANDIDATE_CAPABILITY_PASS_NO_PROMOTION", flush=True)
    else:
        print("S26_ZERO_COST_PRIMARY_CANDIDATE_FAIL_CLOSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
