#!/usr/bin/env python3
"""Negative matrix for the authoritative PR #93 LOTE-E.14 evidence contract."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

sys.dont_write_bytecode = True
import PR93_LOTE_E14_SEMANTICS as semantics

Mutation = Callable[[Path], None]


def verify(verifier: Path, bundle: Path, trusted: str, repo: Path) -> int:
    return subprocess.run(
        [
            sys.executable,
            str(verifier),
            "--bundle-dir",
            str(bundle),
            "--trusted-receipt-sha256",
            trusted,
            "--repo-root",
            str(repo),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    ).returncode


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def append(path: Path, data: bytes) -> None:
    path.write_bytes(path.read_bytes() + data)


def full(bundle: Path) -> Path:
    return bundle / "PR93_E14_FULL_TRANSCRIPT.log"


def receipt(bundle: Path) -> Path:
    return bundle / "PR93_E14_RECEIPT.json"


def mutate_prepend(bundle: Path) -> None:
    path = full(bundle)
    path.write_bytes(b"INJECTED_BEFORE_BEGIN\n" + path.read_bytes())


def mutate_warning(bundle: Path) -> None:
    path = full(bundle)
    lines = path.read_bytes().splitlines(keepends=True)
    lines.insert(1, b"WARNING_INJECTED\n")
    path.write_bytes(b"".join(lines))


def mutate_delete_line(bundle: Path) -> None:
    path = full(bundle)
    lines = path.read_bytes().splitlines(keepends=True)
    del lines[len(lines) // 2]
    path.write_bytes(b"".join(lines))


def mutate_t1(bundle: Path) -> None:
    append(bundle / "PR93_E14_T1_TRANSCRIPT.log", b"X")


def mutate_truncate(bundle: Path) -> None:
    path = full(bundle)
    path.write_bytes(b"".join(path.read_bytes().splitlines(keepends=True)[:-1]))


def mutate_receipt(bundle: Path) -> None:
    path = receipt(bundle)
    value = json.loads(path.read_text(encoding="utf-8"))
    value["overall_status"] = "FAIL" if value["overall_status"] == "PASS" else "PASS"
    path.write_bytes(canonical(value))


def mutate_t1_and_receipt(bundle: Path) -> None:
    t1 = bundle / "PR93_E14_T1_TRANSCRIPT.log"
    append(t1, b"FORGED\n")
    path = receipt(bundle)
    value = json.loads(path.read_text(encoding="utf-8"))
    data = t1.read_bytes()
    meta = value["evidence_files"][t1.name]
    meta.update(
        sha256=hashlib.sha256(data).hexdigest(),
        size_bytes=len(data),
        line_count=len(data.splitlines()),
    )
    path.write_bytes(canonical(value))


def remove_full(bundle: Path) -> None:
    full(bundle).unlink()


def mutate_t2(bundle: Path) -> None:
    append(bundle / "PR93_E14_T2_TRANSCRIPT.log", b"X\n")


def mutate_post_state(bundle: Path) -> None:
    (bundle / "PR93_E14_POST_STATE.json").write_bytes(b'{"forged":true}\n')


CASES: tuple[tuple[str, Mutation], ...] = (
    ("prepend-before-full-begin", mutate_prepend),
    ("warning-after-full-begin", mutate_warning),
    ("delete-full-line", mutate_delete_line),
    ("mutate-t1-byte", mutate_t1),
    ("truncate-full-end", mutate_truncate),
    ("mutate-receipt", mutate_receipt),
    ("mutate-t1-and-recompute-receipt", mutate_t1_and_receipt),
    ("remove-full-transcript", remove_full),
    ("mutate-t2-byte", mutate_t2),
    ("mutate-post-state", mutate_post_state),
)


def segment_json(lines: list[str], start_marker: str, end_marker: str) -> int:
    start = lines.index(start_marker)
    end = lines.index(end_marker, start + 1)
    hits = []
    for index in range(start + 1, end):
        text = lines[index].strip()
        if text.startswith("{"):
            json.loads(text)
            hits.append(index)
    if len(hits) != 1:
        raise ValueError(
            f"segment {start_marker} must contain exactly one JSON object; "
            f"observed {len(hits)}"
        )
    return hits[0]


def expect_semantic_rejection(lines: list[str], head: str, message: str) -> None:
    try:
        result = semantics.parse_t1_semantics(
            ("\n".join(lines) + "\n").encode("utf-8"), head
        )
    except ValueError:
        return
    if result.get("all_pass") is not False:
        raise SystemExit(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--trusted-receipt-sha256", required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()

    bundle = args.bundle_dir.resolve()
    repo = args.repo_root.resolve()
    verifier = repo / "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY.py"
    if verify(verifier, bundle, args.trusted_receipt_sha256, repo) != 0:
        raise SystemExit("control bundle did not verify")

    passed = 0
    with tempfile.TemporaryDirectory(prefix="pr93-e14-negative-") as temp:
        root = Path(temp)
        for index, (name, mutation) in enumerate(CASES, start=1):
            target = root / f"{index:02d}-{name}"
            shutil.copytree(bundle, target)
            mutation(target)
            if verify(verifier, target, args.trusted_receipt_sha256, repo) == 0:
                raise SystemExit(f"negative case unexpectedly passed: {name}")
            print(f"PASS_NEGATIVE_{index:02d}={name}")
            passed += 1

    value = json.loads(receipt(bundle).read_text(encoding="utf-8"))
    head = value["head_sha"]
    original = (bundle / "PR93_E14_T1_TRANSCRIPT.log").read_text(
        encoding="utf-8"
    ).splitlines()

    false_preflight = original.copy()
    index = segment_json(
        false_preflight,
        "E13_T1_DEPENDENCY_PREFLIGHT",
        "E13_T1_PRIMARY_25_VECTOR_READBACK",
    )
    payload = json.loads(false_preflight[index].strip())
    payload["preflight_ready"] = False
    false_preflight[index] = json.dumps(payload, separators=(",", ":"))
    expect_semantic_rejection(
        false_preflight, head, "preflight false unexpectedly passed"
    )
    print("PASS_NEGATIVE_11=t1-preflight-false-cannot-pass")
    passed += 1

    duplicate = original.copy()
    head_line = next(line for line in duplicate if line.startswith("E13_T1_HEAD_SHA="))
    duplicate.insert(duplicate.index(head_line) + 1, head_line)
    expect_semantic_rejection(duplicate, head, "duplicate T1 head unexpectedly passed")
    print("PASS_NEGATIVE_12=duplicate-t1-head-rejected")
    passed += 1

    cross_t1 = original.copy()
    cross_t1.insert(1, f"E13_T2_HEAD_SHA={head}")
    expect_semantic_rejection(cross_t1, head, "T2 head inside T1 unexpectedly passed")
    print("PASS_NEGATIVE_13=t2-head-inside-t1-rejected")
    passed += 1

    with tempfile.TemporaryDirectory(prefix="pr93-e14-cross-") as temp:
        target = Path(temp) / "bundle"
        shutil.copytree(bundle, target)
        t2 = target / "PR93_E14_T2_TRANSCRIPT.log"
        t2.write_text(
            f"E13_T1_HEAD_SHA={head}\n" + t2.read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        if verify(verifier, target, args.trusted_receipt_sha256, repo) == 0:
            raise SystemExit("T1 head inside T2 unexpectedly passed")
    print("PASS_NEGATIVE_14=t1-head-inside-t2-rejected")
    passed += 1

    if passed != 14:
        raise SystemExit(f"negative matrix count mismatch: {passed}")
    print("PASS_E13_NEGATIVE_MATRIX=12/12")
    print("PASS_E14_NEGATIVE_MATRIX=14/14")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
