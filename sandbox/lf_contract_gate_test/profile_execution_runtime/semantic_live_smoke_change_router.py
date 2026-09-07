#!/usr/bin/env python3
"""Deterministic changed-scope router for the expensive semantic live smoke.

The live 7B smoke is required when semantic implementation files change or when
meaningful payload inside the semantic-mini-judge-smoke workflow job changes.
Routing-only scaffolding (the classifier step, fetch depth, and the positive
heavy-step guards themselves) is normalized away so introducing the guard does
not force the expensive lane by itself.

The head workflow must retain the exact heavy-step guards. Removing or changing
one fails closed into live_smoke=true.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess

WORKFLOW = ".github/workflows/story-agent-evidence-verifier.yml"
DIRECT_SEMANTIC = {
    "sandbox/lf_contract_gate_test/profile_execution_runtime/semantic_mini_judge.py",
    "sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_semantic_judge.py",
    "sandbox/lf_contract_gate_test/profile_execution_runtime/run_semantic_mini_judge_live_smoke.py",
}
HEAVY_STEPS = (
    "Build pinned llama.cpp server from source",
    "Download and verify pinned semantic judge model",
    "Run real zero-cost semantic smoke",
)
GUARD = "if: steps.route.outputs.live_smoke == 'true'"
ROUTE_STEP = "- name: Classify live semantic smoke necessity"


def semantic_job_block(text: str) -> str:
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.strip() == "semantic-mini-judge-smoke:" and line.startswith("  "):
            start = index
            break
    if start is None:
        raise ValueError("SEMANTIC_JOB_MISSING")

    block: list[str] = []
    for line in lines[start:]:
        if block and re.match(r"^  [A-Za-z0-9_.-]+:\s*$", line):
            break
        block.append(line)
    return "\n".join(block)


def normalized_semantic_payload(block: str) -> str:
    """Remove only routing scaffolding; preserve the semantic runtime payload."""
    lines = block.splitlines()
    result: list[str] = []
    index = 0
    while index < len(lines):
        if lines[index].strip() == ROUTE_STEP:
            index += 1
            while index < len(lines):
                if re.match(r"^      - name:", lines[index]):
                    break
                index += 1
            continue

        line = lines[index]
        if line.strip() == GUARD:
            index += 1
            continue
        if line.strip().startswith("fetch-depth:"):
            index += 1
            continue
        result.append(line.rstrip())
        index += 1
    return "\n".join(result).strip()


def guard_integrity(block: str) -> tuple[bool, list[str]]:
    lines = block.splitlines()
    missing: list[str] = []
    for name in HEAVY_STEPS:
        step_index = next(
            (index for index, line in enumerate(lines) if line.strip() == f"- name: {name}"),
            None,
        )
        if step_index is None:
            missing.append(f"{name}:STEP_MISSING")
            continue
        window = "\n".join(lines[step_index + 1 : step_index + 4])
        if GUARD not in window:
            missing.append(f"{name}:GUARD_MISSING_OR_CHANGED")
    return not missing, missing


def classify_changes(changed_paths: list[str], base_workflow: str, head_workflow: str) -> dict:
    reasons: list[str] = []
    direct = sorted(set(changed_paths) & DIRECT_SEMANTIC)
    reasons.extend(f"DIRECT_SEMANTIC_PATH:{path}" for path in direct)

    if WORKFLOW in changed_paths:
        try:
            base_block = semantic_job_block(base_workflow)
            head_block = semantic_job_block(head_workflow)
        except ValueError as exc:
            reasons.append(str(exc))
        else:
            guards_ok, guard_findings = guard_integrity(head_block)
            if not guards_ok:
                reasons.extend(guard_findings)
            if normalized_semantic_payload(base_block) != normalized_semantic_payload(head_block):
                reasons.append("SEMANTIC_JOB_PAYLOAD_CHANGED")

    return {
        "schema": "LF_SEMANTIC_LIVE_SMOKE_ROUTE_V1",
        "live_smoke": bool(reasons),
        "reasons": reasons,
        "changed_paths": sorted(changed_paths),
    }


def _git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True)


def _read_at(sha: str, path: str) -> str:
    try:
        return _git("show", f"{sha}:{path}")
    except subprocess.CalledProcessError:
        return ""


def self_test() -> None:
    base = (
        "jobs:\n"
        "  semantic-mini-judge-smoke:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n"
        "      - name: Checkout repository\n"
        "        uses: actions/checkout@v4\n"
        "        with:\n"
        "          fetch-depth: 1\n"
        "      - name: Run deterministic mini-judge regressions\n"
        "        run: python3 tests.py\n"
        "      - name: Build pinned llama.cpp server from source\n"
        "        env:\n"
        f"          LLAMA_COMMIT: {'a' * 40}\n"
        "        run: cmake --build build --target llama-server\n"
        "      - name: Download and verify pinned semantic judge model\n"
        "        env:\n"
        f"          MODEL_SHA256: {'b' * 64}\n"
        "        run: curl https://huggingface.co/x/model.gguf\n"
        "      - name: Run real zero-cost semantic smoke\n"
        "        env:\n"
        "          LF_SEMANTIC_MODEL_PATH: model.gguf\n"
        "        run: python3 sandbox/lf_contract_gate_test/profile_execution_runtime/run_semantic_mini_judge_live_smoke.py\n"
        "  next-job:\n"
        "    runs-on: ubuntu-latest\n"
    )

    head = base.replace("fetch-depth: 1", "fetch-depth: 0")
    route_step = (
        "      - name: Classify live semantic smoke necessity\n"
        "        id: route\n"
        "        run: python3 semantic_live_smoke_change_router.py\n"
    )
    head = head.replace(
        "      - name: Run deterministic mini-judge regressions",
        route_step + "      - name: Run deterministic mini-judge regressions",
    )
    for name in HEAVY_STEPS:
        head = head.replace(
            f"      - name: {name}\n",
            f"      - name: {name}\n        {GUARD}\n",
        )

    cases: list[tuple[bool, str]] = []
    cases.append((classify_changes(["helper.py"], base, head)["live_smoke"] is False, "routing_scaffold_false"))
    cases.append((classify_changes([next(iter(DIRECT_SEMANTIC))], base, head)["live_smoke"] is True, "direct_true"))

    model_changed = head.replace("MODEL_SHA256: " + ("b" * 64), "MODEL_SHA256: " + ("c" * 64))
    cases.append((classify_changes([WORKFLOW], base, model_changed)["live_smoke"] is True, "model_change_true"))

    guard_removed = head.replace(f"        {GUARD}\n", "", 1)
    cases.append((classify_changes([WORKFLOW], base, guard_removed)["live_smoke"] is True, "guard_removed_true"))

    command_changed = head.replace(
        "cmake --build build --target llama-server",
        "cmake --build build --target llama-server -j 8",
    )
    cases.append((classify_changes([WORKFLOW], base, command_changed)["live_smoke"] is True, "command_change_true"))
    cases.append((classify_changes([WORKFLOW], base, head)["live_smoke"] is False, "workflow_scaffold_only_false"))
    cases.append(
        (
            classify_changes(
                ["sandbox/lf_contract_gate_test/profile_execution_runtime/github_backup_transport_preflight.py"],
                base,
                head,
            )["live_smoke"]
            is False,
            "preflight_only_false",
        )
    )

    failures = [name for passed, name in cases if not passed]
    if failures:
        raise SystemExit("SEMANTIC_LIVE_SMOKE_ROUTE_SELF_TEST_FAIL:" + ",".join(failures))
    print("SEMANTIC_LIVE_SMOKE_ROUTE_SELF_TEST_PASS 7/7")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-sha")
    parser.add_argument("--head-sha")
    parser.add_argument("--github-output")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()
        if not args.base_sha and not args.head_sha:
            return 0
    if not args.base_sha or not args.head_sha:
        parser.error("--base-sha and --head-sha are required")

    changed_paths = [
        path for path in _git("diff", "--name-only", args.base_sha, args.head_sha).splitlines() if path
    ]
    result = classify_changes(
        changed_paths,
        _read_at(args.base_sha, WORKFLOW),
        _read_at(args.head_sha, WORKFLOW),
    )
    print(json.dumps(result, sort_keys=True))

    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as handle:
            handle.write("live_smoke=" + str(result["live_smoke"]).lower() + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
