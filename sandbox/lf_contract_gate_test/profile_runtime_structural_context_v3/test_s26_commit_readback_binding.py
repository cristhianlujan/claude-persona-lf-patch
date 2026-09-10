from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
HP = REPO / "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001"

TRANSITIONS = [
    (
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_a_output.json",
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_b_output.json",
    ),
    (
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_b_output.json",
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_c_output.json",
    ),
    (
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_c_output.json",
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_d_output.json",
    ),
    (
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_d_output.json",
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_e_output.json",
    ),
    (
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_e_output.json",
        "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/s26_hp001/gate_f_input.json",
    ),
]


def _run(*args: str, text: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        list(args),
        cwd=REPO,
        check=True,
        capture_output=True,
        text=text,
    )


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _git_blob_sha(raw: bytes) -> str:
    preimage = f"blob {len(raw)}\0".encode("utf-8") + raw
    return hashlib.sha1(preimage).hexdigest()


def _fetch_commit(sha: str) -> None:
    subprocess.run(
        ["git", "fetch", "origin", sha, "--depth=1"],
        cwd=REPO,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _parent_sha(head: str) -> str:
    body = _run("git", "cat-file", "-p", head).stdout
    parents = [line.split()[1] for line in body.splitlines() if line.startswith("parent ")]
    if len(parents) != 1:
        raise AssertionError(f"S26_SHA_BINDING_PARENT_COUNT_INVALID:{len(parents)}")
    return parents[0]


def _git_bytes(ref: str, path: str) -> bytes:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        cwd=REPO,
        check=True,
        capture_output=True,
    )
    return result.stdout


def main() -> None:
    head = _run("git", "rev-parse", "HEAD").stdout.strip()
    parent = _parent_sha(head)
    _fetch_commit(parent)
    changed = set(_run("git", "diff", "--name-only", parent, head).stdout.splitlines())

    checked = []
    grandfathered = []

    for upstream_ref, downstream_ref in TRANSITIONS:
        downstream_path = REPO / downstream_ref
        if not downstream_path.is_file():
            continue
        payload = json.loads(downstream_path.read_text(encoding="utf-8"))
        upstream = payload.get("upstream") or {}
        binding = upstream.get("committed_readback_binding")
        downstream_changed = downstream_ref in changed

        if binding is None:
            if downstream_changed:
                raise AssertionError(
                    f"S26_SHA_BINDING_PROOF_REQUIRED_FOR_CHANGED_DOWNSTREAM:{downstream_ref}"
                )
            grandfathered.append(downstream_ref)
            continue

        if binding.get("schema") != "S26_POST_COMMIT_READBACK_BINDING_V1":
            raise AssertionError(f"S26_SHA_BINDING_SCHEMA_INVALID:{downstream_ref}")
        if binding.get("mode") != "POST_COMMIT_PROVIDER_READBACK_BEFORE_DOWNSTREAM_BINDING":
            raise AssertionError(f"S26_SHA_BINDING_MODE_INVALID:{downstream_ref}")
        if binding.get("provider") != "GITHUB":
            raise AssertionError(f"S26_SHA_BINDING_PROVIDER_INVALID:{downstream_ref}")
        if binding.get("source_ref") != upstream_ref:
            raise AssertionError(f"S26_SHA_BINDING_SOURCE_REF_INVALID:{downstream_ref}")
        if binding.get("same_commit_source_and_binding_forbidden") is not True:
            raise AssertionError(f"S26_SHA_BINDING_SAME_COMMIT_POLICY_MISSING:{downstream_ref}")

        source_commit = binding.get("source_commit_sha")
        if not isinstance(source_commit, str) or len(source_commit) != 40:
            raise AssertionError(f"S26_SHA_BINDING_SOURCE_COMMIT_INVALID:{downstream_ref}")

        if downstream_changed:
            if source_commit != parent:
                raise AssertionError(
                    f"S26_SHA_BINDING_SOURCE_COMMIT_MUST_EQUAL_PARENT:{downstream_ref}"
                )
            if upstream_ref in changed:
                raise AssertionError(
                    f"S26_SHA_BINDING_SAME_COMMIT_SOURCE_AND_DOWNSTREAM_FORBIDDEN:{upstream_ref}->{downstream_ref}"
                )

        _fetch_commit(source_commit)
        committed_bytes = _git_bytes(source_commit, upstream_ref)
        current_bytes = (REPO / upstream_ref).read_bytes()
        if committed_bytes != current_bytes:
            raise AssertionError(f"S26_SHA_BINDING_UPSTREAM_DRIFT_AFTER_READBACK:{downstream_ref}")

        actual_sha = _sha256(committed_bytes)
        if binding.get("source_sha256") != actual_sha:
            raise AssertionError(f"S26_SHA_BINDING_READBACK_SHA_MISMATCH:{downstream_ref}")
        if upstream.get("source_output_sha256") != actual_sha:
            raise AssertionError(f"S26_SHA_BINDING_DOWNSTREAM_SHA_MISMATCH:{downstream_ref}")
        if binding.get("source_git_blob_sha") != _git_blob_sha(committed_bytes):
            raise AssertionError(f"S26_SHA_BINDING_BLOB_MISMATCH:{downstream_ref}")

        checked.append(
            {
                "upstream": upstream_ref,
                "downstream": downstream_ref,
                "source_commit_sha": source_commit,
                "sha256": actual_sha,
                "git_blob_sha": binding.get("source_git_blob_sha"),
                "downstream_changed_this_commit": downstream_changed,
            }
        )

    if not checked:
        raise AssertionError("S26_SHA_BINDING_NO_ENFORCED_TRANSITION")

    print(
        json.dumps(
            {
                "gate": "S26_POST_COMMIT_READBACK_BINDING_GUARD_V1",
                "result": "PASS",
                "head": head,
                "parent": parent,
                "checked_transition_count": len(checked),
                "checked": checked,
                "grandfathered_unchanged_transitions": grandfathered,
                "same_commit_source_and_downstream_forbidden": True,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
