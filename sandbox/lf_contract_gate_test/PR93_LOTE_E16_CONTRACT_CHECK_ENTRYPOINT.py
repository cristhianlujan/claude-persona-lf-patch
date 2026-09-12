#!/usr/bin/env python3
"""E.16 fail-closed changed-file scope adapter for the LF contract validator.

The base validator remains byte-identical to commit 4b9e768a. This entry point
replaces only ``get_changed_files`` with the CA-N96 implementation and delegates
all contract, receipt, scope and forbidden-status validation to ``base.main``.
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
ZERO_SHA = "0" * 40
BASE_VALIDATOR_PATH = Path(__file__).resolve().parents[2] / "scripts/lf_contract_check.py"


def _load_base_validator():
    spec = importlib.util.spec_from_file_location("lf_contract_check_e16_base", BASE_VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load base validator: {BASE_VALIDATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = _load_base_validator()
fail = base.fail
run_git = base.run_git


def git_changed_files(base_revision: str, head_revision: str) -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--name-only", "-z", base_revision, head_revision, "--"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip()
        fail("FAIL_GIT_DIFF", message or f"git diff failed: {base_revision}..{head_revision}")
    try:
        return [
            item.decode("utf-8", "strict")
            for item in result.stdout.split(b"\0")
            if item
        ]
    except UnicodeDecodeError as exc:
        fail("FAIL_GIT_PATH_ENCODING", str(exc))
    return []


def require_branch_name(value: str, *, field: str) -> str:
    result = subprocess.run(
        ["git", "check-ref-format", "--branch", value],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0:
        fail("FAIL_GIT_BRANCH_INVALID", f"{field} no es un nombre de rama válido: {value!r}")
    return value


def git_object_exists(revision: str) -> bool:
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{revision}^{{commit}}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def git_is_ancestor(ancestor: str, descendant: str) -> bool:
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def event_payload(*, required: bool = False) -> dict:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        if required:
            fail("FAIL_PUSH_EVENT_PAYLOAD_MISSING", "GITHUB_EVENT_PATH no está definido")
        return {}
    path = Path(event_path)
    if not path.is_file():
        if required:
            fail("FAIL_PUSH_EVENT_PAYLOAD_MISSING", f"Payload no encontrado: {path}")
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        if required:
            fail("FAIL_PUSH_EVENT_PAYLOAD_INVALID", f"Payload push inválido: {exc}")
        return {}
    if not isinstance(payload, dict):
        if required:
            fail("FAIL_PUSH_EVENT_PAYLOAD_INVALID", "Payload push debe ser un objeto JSON")
        return {}
    return payload


def require_sha(value: object, *, field: str, allow_zero: bool = False) -> str:
    if not isinstance(value, str) or SHA_RE.fullmatch(value) is None:
        fail(
            f"FAIL_PUSH_{field.upper()}_INVALID",
            f"payload.{field} debe ser SHA-1 lowercase de 40 caracteres",
        )
    if value == ZERO_SHA and not allow_zero:
        fail(f"FAIL_PUSH_{field.upper()}_INVALID", f"payload.{field} no puede ser SHA cero")
    return value


def fetch_exact_commit(revision: str) -> bool:
    result = subprocess.run(
        ["git", "fetch", "--no-tags", "--depth=1", "origin", revision],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
    )
    return result.returncode == 0 and git_object_exists(revision)


def changed_files_for_branch_creation(payload: dict, after: str) -> list[str]:
    repository = payload.get("repository")
    default_branch = repository.get("default_branch") if isinstance(repository, dict) else None
    if not isinstance(default_branch, str) or not default_branch.strip():
        fail(
            "FAIL_PUSH_DEFAULT_BRANCH_MISSING",
            "payload.repository.default_branch es obligatorio al crear rama",
        )
    default_branch = require_branch_name(
        default_branch.strip(), field="payload.repository.default_branch"
    )
    fetch = subprocess.run(
        ["git", "fetch", "--no-tags", "origin", default_branch],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
    )
    if fetch.returncode != 0:
        fail(
            "FAIL_PUSH_DEFAULT_BRANCH_UNREACHABLE",
            f"No se pudo obtener origin/{default_branch}",
        )
    result = subprocess.run(
        ["git", "merge-base", f"origin/{default_branch}", after],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
    )
    merge_base = result.stdout.strip()
    if result.returncode != 0 or SHA_RE.fullmatch(merge_base) is None:
        fail(
            "FAIL_PUSH_BRANCH_BASE_UNRESOLVED",
            f"No existe merge-base verificable con origin/{default_branch}",
        )
    return git_changed_files(merge_base, after)


def changed_files_for_push() -> list[str]:
    payload = event_payload(required=True)
    if payload.get("deleted") is True:
        fail("FAIL_PUSH_DELETION_EVENT", "El validador no acepta eventos de eliminación de rama")
    if payload.get("forced") is True:
        fail("FAIL_PUSH_FORCE_UPDATE", "El push fue marcado como forzado")

    before = require_sha(payload.get("before"), field="before", allow_zero=True)
    after = require_sha(payload.get("after"), field="after")
    expected_after = os.environ.get("GITHUB_SHA")
    if not expected_after:
        fail("FAIL_PUSH_GITHUB_SHA_MISSING", "GITHUB_SHA no está definido")
    if SHA_RE.fullmatch(expected_after) is None:
        fail(
            "FAIL_PUSH_GITHUB_SHA_INVALID",
            "GITHUB_SHA debe ser SHA-1 lowercase de 40 caracteres",
        )
    if expected_after != after:
        fail(
            "FAIL_PUSH_AFTER_MISMATCH",
            f"payload.after={after} difiere de GITHUB_SHA={expected_after}",
        )
    observed_head = run_git(["rev-parse", "HEAD"]).strip()
    if observed_head != after:
        fail(
            "FAIL_PUSH_AFTER_MISMATCH",
            f"payload.after={after} difiere de HEAD={observed_head}",
        )
    if not git_object_exists(after):
        fail("FAIL_PUSH_AFTER_UNREACHABLE", f"payload.after no es alcanzable: {after}")

    if before == ZERO_SHA:
        if payload.get("created") is not True:
            fail("FAIL_PUSH_BEFORE_ZERO_WITHOUT_CREATE", "SHA cero exige payload.created=true")
        return changed_files_for_branch_creation(payload, after)

    if not git_object_exists(before) and not fetch_exact_commit(before):
        fail(
            "FAIL_PUSH_BEFORE_UNREACHABLE",
            f"payload.before no es alcanzable después de fetch explícito: {before}",
        )
    if not git_is_ancestor(before, after):
        fail(
            "FAIL_PUSH_NON_FAST_FORWARD",
            f"payload.before no es ancestro de payload.after: {before}..{after}",
        )
    return git_changed_files(before, after)


def get_changed_files() -> list[str]:
    event_name = os.environ.get("GITHUB_EVENT_NAME")
    if not event_name:
        fail("FAIL_EVENT_NAME_MISSING", "GITHUB_EVENT_NAME no está definido")

    if event_name == "pull_request":
        base_ref = require_branch_name(
            os.environ.get("GITHUB_BASE_REF", "main"), field="GITHUB_BASE_REF"
        )
        subprocess.run(["git", "fetch", "origin", base_ref], check=True)
        merge_base = run_git(["merge-base", f"origin/{base_ref}", "HEAD"]).strip()
        if SHA_RE.fullmatch(merge_base) is None:
            fail(
                "FAIL_PULL_REQUEST_BASE_UNRESOLVED",
                f"No existe merge-base con origin/{base_ref}",
            )
        return git_changed_files(merge_base, "HEAD")

    if event_name == "push":
        return changed_files_for_push()

    if event_name == "workflow_dispatch":
        print(
            "workflow_dispatch event: no changed-file scope validation required; "
            "running static/self-tests only."
        )
        return []

    fail("FAIL_UNSUPPORTED_EVENT", f"Evento no soportado: {event_name}")
    return []


def main() -> None:
    base.get_changed_files = get_changed_files
    base.main()


if __name__ == "__main__":
    main()
