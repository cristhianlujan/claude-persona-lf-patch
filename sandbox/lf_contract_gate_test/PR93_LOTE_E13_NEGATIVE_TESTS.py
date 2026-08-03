#!/usr/bin/env python3
"""Negative tests for the E.13 receipt verifier using a valid captured bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Callable


def run_verify(verifier: Path, bundle: Path, trusted: str, repo_root: Path) -> int:
    return subprocess.run(
        [
            "python3",
            str(verifier),
            "--bundle-dir",
            str(bundle),
            "--trusted-receipt-sha256",
            trusted,
            "--repo-root",
            str(repo_root),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode


def canonical(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def mutate_prepend_full(bundle: Path) -> None:
    path = bundle / "PR93_E13_FULL_TRANSCRIPT.log"
    path.write_bytes(b"INJECTED_BEFORE_BEGIN\n" + path.read_bytes())


def mutate_warning_after_begin(bundle: Path) -> None:
    path = bundle / "PR93_E13_FULL_TRANSCRIPT.log"
    lines = path.read_bytes().splitlines(keepends=True)
    lines.insert(1, b"WARNING_INJECTED\n")
    path.write_bytes(b"".join(lines))


def mutate_delete_full_line(bundle: Path) -> None:
    path = bundle / "PR93_E13_FULL_TRANSCRIPT.log"
    lines = path.read_bytes().splitlines(keepends=True)
    del lines[len(lines) // 2]
    path.write_bytes(b"".join(lines))


def mutate_t1_byte(bundle: Path) -> None:
    path = bundle / "PR93_E13_T1_TRANSCRIPT.log"
    path.write_bytes(path.read_bytes() + b"X")


def mutate_truncate_end(bundle: Path) -> None:
    path = bundle / "PR93_E13_FULL_TRANSCRIPT.log"
    lines = path.read_bytes().splitlines(keepends=True)
    path.write_bytes(b"".join(lines[:-1]))


def mutate_receipt(bundle: Path) -> None:
    path = bundle / "PR93_E13_RECEIPT.json"
    receipt = json.loads(path.read_text())
    receipt["overall_status"] = "PASS" if receipt["overall_status"] == "FAIL" else "FAIL"
    path.write_bytes(canonical(receipt))


def mutate_t1_and_receipt(bundle: Path) -> None:
    t1 = bundle / "PR93_E13_T1_TRANSCRIPT.log"
    t1.write_bytes(t1.read_bytes() + b"FORGED\n")
    receipt_path = bundle / "PR93_E13_RECEIPT.json"
    receipt = json.loads(receipt_path.read_text())
    data = t1.read_bytes()
    receipt["evidence_files"][t1.name]["sha256"] = hashlib.sha256(data).hexdigest()
    receipt["evidence_files"][t1.name]["size_bytes"] = len(data)
    receipt["evidence_files"][t1.name]["line_count"] = len(data.splitlines())
    receipt_path.write_bytes(canonical(receipt))


def mutate_remove_full(bundle: Path) -> None:
    (bundle / "PR93_E13_FULL_TRANSCRIPT.log").unlink()


def mutate_t2_byte(bundle: Path) -> None:
    path = bundle / "PR93_E13_T2_TRANSCRIPT.log"
    path.write_bytes(path.read_bytes() + b"X\n")


def mutate_state(bundle: Path) -> None:
    path = bundle / "PR93_E13_POST_STATE.json"
    path.write_bytes(b'{"forged":true}\n')


CASES: tuple[tuple[str, Callable[[Path], None]], ...] = (
    ("prepend-before-full-begin", mutate_prepend_full),
    ("warning-after-full-begin", mutate_warning_after_begin),
    ("delete-full-line", mutate_delete_full_line),
    ("mutate-t1-byte", mutate_t1_byte),
    ("truncate-full-end", mutate_truncate_end),
    ("mutate-receipt", mutate_receipt),
    ("mutate-t1-and-recompute-receipt", mutate_t1_and_receipt),
    ("remove-full-transcript", mutate_remove_full),
    ("mutate-t2-byte", mutate_t2_byte),
    ("mutate-post-state", mutate_state),
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--trusted-receipt-sha256", required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--verifier", type=Path, required=True)
    args = parser.parse_args()

    if run_verify(args.verifier, args.bundle_dir, args.trusted_receipt_sha256, args.repo_root) != 0:
        raise SystemExit("control bundle did not verify")

    with tempfile.TemporaryDirectory(prefix="pr93-e13-negative-") as temp:
        root = Path(temp)
        for index, (name, mutation) in enumerate(CASES, start=1):
            target = root / f"{index:02d}-{name}"
            shutil.copytree(args.bundle_dir, target)
            mutation(target)
            if run_verify(args.verifier, target, args.trusted_receipt_sha256, args.repo_root) == 0:
                raise SystemExit(f"negative case unexpectedly passed: {name}")
            print(f"PASS_NEGATIVE_{index:02d}={name}")

    print(f"PASS_E13_NEGATIVE_MATRIX={len(CASES)}/{len(CASES)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
