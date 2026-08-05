#!/usr/bin/env python3
"""Synthetic regression matrix for PR93 E.16 CA-N96 push-scope handling."""
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Iterator

sys.dont_write_bytecode = True
ZERO_SHA = "0" * 40


def run(command: list[str], cwd: Path, *, check: bool = True) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{result.stderr}"
        )
    return result.stdout.strip()


def git(repo: Path, *args: str) -> str:
    return run(["git", *args], repo)


def write(repo: Path, relative: str, text: str) -> None:
    path = repo / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def commit(repo: Path, message: str) -> str:
    git(repo, "add", "-A")
    git(repo, "commit", "-m", message)
    return git(repo, "rev-parse", "HEAD")


def load_validator(path: Path):
    spec = importlib.util.spec_from_file_location("lf_contract_check_e16", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@contextlib.contextmanager
def environment(repo: Path, values: dict[str, str | None]) -> Iterator[None]:
    previous = {key: os.environ.get(key) for key in values}
    old_cwd = Path.cwd()
    try:
        os.chdir(repo)
        for key, value in values.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        yield
    finally:
        os.chdir(old_cwd)
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def payload_file(root: Path, value: object, name: str = "event.json") -> Path:
    path = root / name
    if isinstance(value, str):
        path.write_text(value, encoding="utf-8")
    else:
        path.write_text(json.dumps(value), encoding="utf-8")
    return path


def expect_failure(function: Callable[[], object], code: str) -> None:
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        try:
            function()
        except SystemExit as exc:
            if exc.code != 1:
                raise AssertionError(f"{code}: exit={exc.code}, expected 1") from exc
        else:
            raise AssertionError(f"{code}: function unexpectedly succeeded")
    text = output.getvalue()
    if code not in text:
        raise AssertionError(f"expected {code!r} in output, observed: {text!r}")


def base_payload(before: str, after: str, **extra: object) -> dict[str, object]:
    value: dict[str, object] = {
        "before": before,
        "after": after,
        "created": False,
        "deleted": False,
        "forced": False,
        "repository": {"default_branch": "main"},
    }
    value.update(extra)
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--validator", type=Path, required=True)
    args = parser.parse_args()
    validator = load_validator(args.validator.resolve())

    with tempfile.TemporaryDirectory(prefix="pr93-e16-ca-n96-") as temp:
        root = Path(temp)
        origin = root / "origin.git"
        repo = root / "repo"
        run(["git", "init", "--bare", str(origin)], root)
        run(["git", "init", "-b", "main", str(repo)], root)
        git(repo, "config", "user.name", "E16 Synthetic")
        git(repo, "config", "user.email", "e16@example.invalid")
        git(repo, "remote", "add", "origin", str(origin))

        write(repo, "sandbox/lf_contract_gate_test/base.txt", "base\n")
        base = commit(repo, "base")
        git(repo, "push", "-u", "origin", "main")

        git(repo, "checkout", "-b", "lf/e16-test")
        write(repo, "sandbox/lf_contract_gate_test/one.txt", "one\n")
        one = commit(repo, "one")
        write(repo, "sandbox/lf_contract_gate_test/two.txt", "two\n")
        two = commit(repo, "two")
        git(repo, "push", "-u", "origin", "lf/e16-test")

        cases: list[tuple[str, Callable[[], None]]] = []

        def with_push(payload: object, function: Callable[[], object], *, raw: bool = False) -> object:
            event = payload_file(root, payload if raw else payload, f"event-{len(cases)}.json")
            with environment(
                repo,
                {
                    "GITHUB_EVENT_NAME": "push",
                    "GITHUB_EVENT_PATH": str(event),
                    "GITHUB_SHA": git(repo, "rev-parse", "HEAD"),
                },
            ):
                return function()

        def regular_push() -> None:
            observed = with_push(base_payload(one, two), validator.changed_files_for_push)
            if observed != ["sandbox/lf_contract_gate_test/two.txt"]:
                raise AssertionError(observed)

        cases.append(("regular-push-exact-range", regular_push))

        def multi_commit_push() -> None:
            observed = with_push(base_payload(base, two), validator.changed_files_for_push)
            expected = [
                "sandbox/lf_contract_gate_test/one.txt",
                "sandbox/lf_contract_gate_test/two.txt",
            ]
            if observed != expected:
                raise AssertionError(observed)

        cases.append(("multi-commit-push-complete", multi_commit_push))

        git(repo, "checkout", "-b", "lf/e16-newline")
        newline_path = "sandbox/lf_contract_gate_test/line\nbreak.txt"
        write(repo, newline_path, "newline\n")
        newline_head = commit(repo, "newline path")

        def nul_delimited_path() -> None:
            git(repo, "checkout", "lf/e16-newline")
            try:
                observed = with_push(base_payload(two, newline_head), validator.changed_files_for_push)
                if observed != [newline_path]:
                    raise AssertionError(repr(observed))
            finally:
                git(repo, "checkout", "lf/e16-test")

        cases.append(("nul-delimited-git-path", nul_delimited_path))
        git(repo, "checkout", "lf/e16-test")

        def branch_creation() -> None:
            observed = with_push(
                base_payload(ZERO_SHA, two, created=True),
                validator.changed_files_for_push,
            )
            expected = [
                "sandbox/lf_contract_gate_test/one.txt",
                "sandbox/lf_contract_gate_test/two.txt",
            ]
            if observed != expected:
                raise AssertionError(observed)

        cases.append(("branch-creation-merge-base", branch_creation))

        def missing_event_path() -> None:
            with environment(
                repo,
                {
                    "GITHUB_EVENT_NAME": "push",
                    "GITHUB_EVENT_PATH": None,
                    "GITHUB_SHA": two,
                },
            ):
                expect_failure(validator.changed_files_for_push, "FAIL_PUSH_EVENT_PAYLOAD_MISSING")

        cases.append(("missing-event-payload", missing_event_path))

        def invalid_json() -> None:
            event = payload_file(root, "{not-json", "invalid.json")
            with environment(repo, {"GITHUB_EVENT_NAME": "push", "GITHUB_EVENT_PATH": str(event), "GITHUB_SHA": two}):
                expect_failure(validator.changed_files_for_push, "FAIL_PUSH_EVENT_PAYLOAD_INVALID")

        cases.append(("invalid-event-json", invalid_json))

        def malformed_before() -> None:
            expect_failure(
                lambda: with_push(base_payload("abc", two), validator.changed_files_for_push),
                "FAIL_PUSH_BEFORE_INVALID",
            )

        cases.append(("malformed-before", malformed_before))

        def malformed_after() -> None:
            expect_failure(
                lambda: with_push(base_payload(one, "ABC"), validator.changed_files_for_push),
                "FAIL_PUSH_AFTER_INVALID",
            )

        cases.append(("malformed-after", malformed_after))

        def after_mismatch() -> None:
            expect_failure(
                lambda: with_push(base_payload(one, one), validator.changed_files_for_push),
                "FAIL_PUSH_AFTER_MISMATCH",
            )

        cases.append(("after-mismatch", after_mismatch))

        def missing_github_sha() -> None:
            event = payload_file(root, base_payload(one, two), "missing-github-sha.json")
            with environment(repo, {"GITHUB_EVENT_NAME": "push", "GITHUB_EVENT_PATH": str(event), "GITHUB_SHA": None}):
                expect_failure(validator.changed_files_for_push, "FAIL_PUSH_GITHUB_SHA_MISSING")

        cases.append(("missing-github-sha", missing_github_sha))

        def unreachable_before() -> None:
            missing = "1" * 40
            expect_failure(
                lambda: with_push(base_payload(missing, two), validator.changed_files_for_push),
                "FAIL_PUSH_BEFORE_UNREACHABLE",
            )

        cases.append(("unreachable-before-explicit", unreachable_before))

        def forced_push() -> None:
            expect_failure(
                lambda: with_push(base_payload(one, two, forced=True), validator.changed_files_for_push),
                "FAIL_PUSH_FORCE_UPDATE",
            )

        cases.append(("forced-push-rejected", forced_push))

        git(repo, "checkout", "main")
        write(repo, "sandbox/lf_contract_gate_test/side.txt", "side\n")
        side = commit(repo, "side")
        git(repo, "checkout", "lf/e16-test")

        def non_fast_forward() -> None:
            expect_failure(
                lambda: with_push(base_payload(side, two), validator.changed_files_for_push),
                "FAIL_PUSH_NON_FAST_FORWARD",
            )

        cases.append(("non-fast-forward-rejected", non_fast_forward))

        def zero_without_create() -> None:
            expect_failure(
                lambda: with_push(base_payload(ZERO_SHA, two), validator.changed_files_for_push),
                "FAIL_PUSH_BEFORE_ZERO_WITHOUT_CREATE",
            )

        cases.append(("zero-before-requires-created", zero_without_create))

        def missing_default_branch() -> None:
            value = base_payload(ZERO_SHA, two, created=True)
            value["repository"] = {}
            expect_failure(
                lambda: with_push(value, validator.changed_files_for_push),
                "FAIL_PUSH_DEFAULT_BRANCH_MISSING",
            )

        cases.append(("branch-create-default-required", missing_default_branch))

        def invalid_default_branch() -> None:
            value = base_payload(ZERO_SHA, two, created=True)
            value["repository"] = {"default_branch": "-invalid"}
            expect_failure(
                lambda: with_push(value, validator.changed_files_for_push),
                "FAIL_GIT_BRANCH_INVALID",
            )

        cases.append(("branch-create-default-valid-ref", invalid_default_branch))

        def missing_event_name() -> None:
            with environment(repo, {"GITHUB_EVENT_NAME": None, "GITHUB_EVENT_PATH": None, "GITHUB_SHA": two}):
                expect_failure(validator.get_changed_files, "FAIL_EVENT_NAME_MISSING")

        cases.append(("missing-event-name-fail-closed", missing_event_name))

        def unsupported_event() -> None:
            with environment(repo, {"GITHUB_EVENT_NAME": "schedule", "GITHUB_EVENT_PATH": None, "GITHUB_SHA": two}):
                expect_failure(validator.get_changed_files, "FAIL_UNSUPPORTED_EVENT")

        cases.append(("unsupported-event-fail-closed", unsupported_event))

        def deletion_event() -> None:
            expect_failure(
                lambda: with_push(base_payload(one, two, deleted=True), validator.changed_files_for_push),
                "FAIL_PUSH_DELETION_EVENT",
            )

        cases.append(("deletion-event-rejected", deletion_event))

        passed = 0
        for index, (name, function) in enumerate(cases, start=1):
            function()
            passed += 1
            print(f"PASS_E16_CA_N96_{index:02d}={name}")

        if passed != 19:
            raise SystemExit(f"CA-N96 regression count mismatch: {passed}")
        print("PASS_E16_CA_N96_REGRESSION=19/19")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
