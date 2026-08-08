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


def verify(
    verifier: Path, bundle: Path, trusted: str, repo: Path
) -> tuple[int, str]:
    """Run the deployable verifier out-of-process and capture its output."""
    result = subprocess.run(
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
    )
    return result.returncode, result.stdout.decode("utf-8", "replace")


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


def semantics_rejects(lines: list[str], head: str) -> bool:
    """In-process complement only. Never a substitute for the subprocess run."""
    try:
        result = semantics.parse_t1_semantics(
            ("\n".join(lines) + "\n").encode("utf-8"), head
        )
    except ValueError:
        return True
    return result.get("all_pass") is not True


def rebuild_bundle(
    source: Path, destination: Path, t1_lines: list[str], t2_lines: list[str]
) -> str:
    """Build a fully coherent bundle around mutated T1/T2 transcripts.

    Every digest, size, line count, embedded copy and semantic object is
    recomputed, and a fresh external trust anchor is returned. A rejection by
    the verifier therefore proves a real contract guard fired, not a stale
    hash mismatch.
    """
    shutil.copytree(source, destination)
    value = json.loads(receipt(destination).read_text(encoding="utf-8"))
    head = value["head_sha"]
    t1 = ("\n".join(t1_lines) + "\n").encode("utf-8")
    t2 = ("\n".join(t2_lines) + "\n").encode("utf-8")
    pre_state = (destination / "PR93_E14_PRE_STATE.json").read_bytes()
    post_state = (destination / "PR93_E14_POST_STATE.json").read_bytes()
    pre_command = (destination / "PR93_E14_PRE_STATE_COMMAND.log").read_bytes()
    post_command = (destination / "PR93_E14_POST_STATE_COMMAND.log").read_bytes()
    t2_receipt = value["t2"]
    full = b"".join(
        [
            b"E14_CAPTURE_BEGIN\n",
            f"E14_HEAD_SHA={head}\n".encode(),
            f"E14_STARTED_AT={value['started_at_utc']}\n".encode(),
            b"E14_T1_PROCESS_BEGIN\n",
            t1,
            f"E14_T1_PROCESS_EXIT={value['t1']['exit_code']}\n".encode(),
            b"E14_T2_PRE_STATE_BEGIN\n",
            pre_state,
            f"E14_T2_PRE_STATE_EXIT={t2_receipt['pre_state_exit_code']}\n".encode(),
            b"E14_T2_PROCESS_BEGIN\n",
            t2,
            f"E14_T2_PROCESS_EXIT={t2_receipt['exit_code']}\n".encode(),
            b"E14_T2_POST_STATE_BEGIN\n",
            post_state,
            f"E14_T2_POST_STATE_EXIT={t2_receipt['post_state_exit_code']}\n".encode(),
            f"E14_T2_STATE_MATCH={str(t2_receipt['state_match']).lower()}\n".encode(),
            f"E14_T2_ROLLBACK_STATUS={t2_receipt['rollback_status']}\n".encode(),
            f"E14_OVERALL_STATUS={value['overall_status']}\n".encode(),
            f"E14_FINISHED_AT={value['finished_at_utc']}\n".encode(),
            b"E14_CAPTURE_END\n",
        ]
    )
    files = {
        "PR93_E14_FULL_TRANSCRIPT.log": full,
        "PR93_E14_T1_TRANSCRIPT.log": t1,
        "PR93_E14_T2_TRANSCRIPT.log": t2,
        "PR93_E14_PRE_STATE.json": pre_state,
        "PR93_E14_POST_STATE.json": post_state,
        "PR93_E14_PRE_STATE_COMMAND.log": pre_command,
        "PR93_E14_POST_STATE_COMMAND.log": post_command,
    }
    for name, data in files.items():
        (destination / name).write_bytes(data)
    value["evidence_files"] = {
        name: {
            "sha256": hashlib.sha256(data).hexdigest(),
            "size_bytes": len(data),
            "line_count": len(data.splitlines()),
        }
        for name, data in files.items()
    }
    try:
        checks = semantics.parse_t1_semantics(t1, head)
    except (UnicodeDecodeError, ValueError) as exc:
        checks = {"all_pass": False, "validation_error": str(exc)}
    value["t1"]["semantic_checks"] = checks
    receipt_bytes = canonical(value)
    receipt(destination).write_bytes(receipt_bytes)
    digest = hashlib.sha256(receipt_bytes).hexdigest()
    (destination / "PR93_E14_RECEIPT.sha256").write_text(
        f"{digest}  PR93_E14_RECEIPT.json\n", encoding="utf-8"
    )
    return digest


def head_line_index(lines: list[str], prefix: str) -> int:
    for position, line in enumerate(lines):
        if line.startswith(prefix):
            return position
    raise SystemExit(f"control bundle lacks required marker {prefix}")


def marker_cases(
    t1: list[str], t2: list[str], head: str, other: str
) -> tuple[tuple[str, list[str], list[str], str], ...]:
    """T1/T2 marker separation matrix executed against the deployable verifier."""
    i1 = head_line_index(t1, "E13_T1_HEAD_SHA=")
    i2 = head_line_index(t2, "E13_T2_HEAD_SHA=")

    def edit(lines: list[str], action) -> list[str]:
        copy = lines.copy()
        action(copy)
        return copy

    return (
        (
            "t1-preflight-false-cannot-pass",
            preflight_false(t1),
            t2,
            "T1 PASS lacks complete semantic readiness",
        ),
        (
            "duplicate-t1-head-rejected",
            edit(t1, lambda l: l.insert(i1 + 1, l[i1])),
            t2,
            "must occur exactly once",
        ),
        (
            "contradictory-t1-head-rejected",
            edit(t1, lambda l: l.__setitem__(i1, f"E13_T1_HEAD_SHA={other}")),
            t2,
            "T1 head marker does not match audited head",
        ),
        (
            "absent-t1-head-rejected",
            edit(t1, lambda l: l.pop(i1)),
            t2,
            "must occur exactly once",
        ),
        (
            "t2-head-inside-t1-rejected",
            edit(t1, lambda l: l.insert(1, f"E13_T2_HEAD_SHA={head}")),
            t2,
            "T2 head marker is forbidden inside T1",
        ),
        (
            "envelope-head-inside-t1-rejected",
            edit(t1, lambda l: l.insert(1, f"E14_HEAD_SHA={head}")),
            t2,
            # The envelope-uniqueness guard fires first because the full
            # transcript embeds T1 verbatim; the T1-scoped guard in
            # PR93_LOTE_E14_SEMANTICS remains as defence in depth.
            "'E14_HEAD_SHA=' must occur exactly once",
        ),
        (
            "duplicate-t2-head-rejected",
            t1,
            edit(t2, lambda l: l.insert(i2 + 1, l[i2])),
            "T2 head marker is missing, duplicated or contradictory",
        ),
        (
            "contradictory-t2-head-rejected",
            t1,
            edit(t2, lambda l: l.__setitem__(i2, f"E13_T2_HEAD_SHA={other}")),
            "T2 head marker is missing, duplicated or contradictory",
        ),
        (
            "absent-t2-head-rejected",
            t1,
            edit(t2, lambda l: l.pop(i2)),
            "T2 head marker is missing, duplicated or contradictory",
        ),
        (
            "t1-head-inside-t2-rejected",
            t1,
            edit(t2, lambda l: l.insert(1, f"E13_T1_HEAD_SHA={head}")),
            "T1 head marker is forbidden inside T2",
        ),
        (
            "envelope-head-inside-t2-rejected",
            t1,
            edit(t2, lambda l: l.insert(1, f"E14_HEAD_SHA={head}")),
            "'E14_HEAD_SHA=' must occur exactly once",
        ),
    )


def preflight_false(t1: list[str]) -> list[str]:
    lines = t1.copy()
    index = segment_json(
        lines,
        "E13_T1_DEPENDENCY_PREFLIGHT",
        "E13_T1_PRIMARY_25_VECTOR_READBACK",
    )
    payload = json.loads(lines[index].strip())
    payload["preflight_ready"] = False
    lines[index] = json.dumps(payload, separators=(",", ":"))
    return lines


INTRUSIONS: tuple[tuple[str, str], ...] = (
    ("extra-regular-file", "file"),
    ("extra-subdirectory", "dir"),
    ("extra-symlink", "symlink"),
    ("extra-hidden-file", "hidden"),
)


def plant_intrusion(bundle: Path, kind: str) -> None:
    """CA-N128: physical entries a bundle directory must never contain."""
    if kind == "file":
        (bundle / "PR93_E14_EXTRA.log").write_bytes(b"extra\n")
    elif kind == "dir":
        (bundle / "PR93_E14_EXTRA_DIR").mkdir()
    elif kind == "symlink":
        (bundle / "PR93_E14_EXTRA_LINK").symlink_to("PR93_E14_RECEIPT.json")
    elif kind == "hidden":
        (bundle / ".PR93_E14_HIDDEN").write_bytes(b"hidden\n")
    else:
        raise SystemExit(f"unknown intrusion kind: {kind}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--trusted-receipt-sha256", required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()

    bundle = args.bundle_dir.resolve()
    repo = args.repo_root.resolve()
    verifier = repo / "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY.py"
    control_code, _ = verify(verifier, bundle, args.trusted_receipt_sha256, repo)
    if control_code != 0:
        raise SystemExit("control bundle did not verify")

    executed = 0
    rejected = 0
    with tempfile.TemporaryDirectory(prefix="pr93-e14-negative-") as temp:
        root = Path(temp)
        for index, (name, mutation) in enumerate(CASES, start=1):
            target = root / f"{index:02d}-{name}"
            shutil.copytree(bundle, target)
            mutation(target)
            executed += 1
            code, _ = verify(verifier, target, args.trusted_receipt_sha256, repo)
            if code == 0:
                raise SystemExit(f"negative case unexpectedly passed: {name}")
            rejected += 1
            print(f"PASS_NEGATIVE_{index:02d}={name}")

        value = json.loads(receipt(bundle).read_text(encoding="utf-8"))
        head = value["head_sha"]
        other = "0" * 39 + "1"
        base_t1 = (bundle / "PR93_E14_T1_TRANSCRIPT.log").read_text(
            encoding="utf-8"
        ).splitlines()
        base_t2 = (bundle / "PR93_E14_T2_TRANSCRIPT.log").read_text(
            encoding="utf-8"
        ).splitlines()

        offset = len(CASES)
        for position, entry in enumerate(
            marker_cases(base_t1, base_t2, head, other), start=1
        ):
            name, t1_lines, t2_lines, expected = entry
            index = offset + position
            target = root / f"{index:02d}-{name}"
            anchor = rebuild_bundle(bundle, target, t1_lines, t2_lines)
            executed += 1
            code, output = verify(verifier, target, anchor, repo)
            if code == 0:
                raise SystemExit(f"negative case unexpectedly passed: {name}")
            if expected not in output:
                raise SystemExit(
                    f"negative case {name} rejected for the wrong reason: {output}"
                )
            # In-process complement only; the subprocess above is authoritative.
            if t2_lines is base_t2 and not semantics_rejects(t1_lines, head):
                raise SystemExit(f"in-process complement disagrees: {name}")
            rejected += 1
            print(f"PASS_NEGATIVE_{index:02d}={name}")

        offset += len(marker_cases(base_t1, base_t2, head, other))
        for position, (name, kind) in enumerate(INTRUSIONS, start=1):
            index = offset + position
            target = root / f"{index:02d}-{name}"
            shutil.copytree(bundle, target)
            plant_intrusion(target, kind)
            executed += 1
            code, output = verify(
                verifier, target, args.trusted_receipt_sha256, repo
            )
            if code == 0:
                raise SystemExit(f"negative case unexpectedly passed: {name}")
            if "bundle inventory is not exact" not in output and (
                "must not be a symlink" not in output
            ):
                raise SystemExit(
                    f"intrusion {name} rejected for the wrong reason: {output}"
                )
            rejected += 1
            print(f"PASS_NEGATIVE_{index:02d}={name}")

    if rejected != executed:
        raise SystemExit(f"negative matrix count mismatch: {rejected}/{executed}")
    # CA-N125: the published counter is derived from cases this process
    # actually executed. E.14 does not run the historical E.13 matrix -- its
    # six runners are fail-closed stubs -- so no E.13 counter is published.
    print("E13_NEGATIVE_MATRIX=NOT_EXECUTED_BY_E14")
    print(f"PASS_E14_NEGATIVE_MATRIX={rejected}/{executed}")
    return 0



if __name__ == "__main__":
    raise SystemExit(main())
