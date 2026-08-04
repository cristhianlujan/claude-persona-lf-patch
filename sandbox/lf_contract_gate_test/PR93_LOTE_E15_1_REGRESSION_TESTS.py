#!/usr/bin/env python3
"""LOTE-E.15.1 synthetic regression harness for CA-N127 and CA-N133..N137.

This harness does not connect to PostgreSQL or Supabase. It executes the real
capture entry point in a separate Python interpreter while replacing only the
Git/database dependencies with deterministic synthetic functions. Publication,
exclusive writes, fsync, renameat2, cleanup, filesystem races and retries remain
real OS operations.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True

SCENARIOS = (
    "write-00",
    "write-01",
    "write-04",
    "write-07",
    "write-08",
    "fsync-file",
    "fsync-staging",
    "rename-failure",
    "destination-race",
    "post-rename-parent-fsync",
)

# CA-N142: foreign objects the capture must refuse at the literal --output-dir
# argument, before any resolve(). Each case must preserve the original object,
# must not create the pointed-to target and must leave zero staging.
DESTINATION_OBJECTS = (
    "dangling-symlink",
    "symlink-to-file",
    "symlink-to-directory",
    "preexisting-regular-file",
    "preexisting-directory",
)

# CA-N143: deterministic substitutions after descriptor validation and before
# top-level removal. The foreign object must remain untouched.
ADVERSARIAL_CASES = (
    "cleanup-name-swap",
    "cleanup-symlink-swap",
)

DRIVER = r'''
import json
import os
import runpy
import sys
from pathlib import Path

sandbox = Path(sys.argv[1])
scenario = sys.argv[2]
head = sys.argv[3]
output = Path(sys.argv[4])
sys.path.insert(0, str(sandbox))
sys.dont_write_bytecode = True

import PR93_LOTE_E14_COMMON as common
import PR93_LOTE_E14_SEMANTICS as semantics

# Synthetic dependencies only. Filesystem publication remains real.
common.assert_repository = lambda *args, **kwargs: None
common.source_inventory = lambda *args, **kwargs: {
    "synthetic/E15.1": {"git_blob_sha1": "0" * 40, "sha256": "0" * 64, "size_bytes": 0}
}
common.connectivity_preflight = lambda *args, **kwargs: (0, b"1\n")
semantics.parse_t1_semantics = lambda *args, **kwargs: {"all_pass": True}
state = {"rows": [], "rowset_sha256": "0" * 64}
state_bytes = (json.dumps(state, separators=(",", ":")) + "\n").encode()
common.run_state_readback = lambda *args, **kwargs: (0, state_bytes, state)

def synthetic_psql(psql_bin, database_url, script, cwd, timeout, head_sha):
    if script.name.endswith("T1.psql"):
        return 0, b"E13_T1_SYNTHETIC_PASS\n"
    return 0, (
        "E13_T2_BEGIN\n"
        "E13_T2_CONTEXT_GUARD_PASS\n"
        f"E13_T2_HEAD_SHA={head_sha}\n"
        "ROLLBACK\n"
        "E13_T2_COMPLETE\n"
    ).encode()
common.run_psql = synthetic_psql

if scenario.startswith("write-"):
    limit = int(scenario.split("-")[1])
    original = common.write_exclusive
    count = {"value": 0}
    def injected(path, data):
        if count["value"] >= limit:
            raise OSError("E15_INJECTED_WRITE_FAILURE")
        count["value"] += 1
        return original(path, data)
    common.write_exclusive = injected
elif scenario == "fsync-file":
    common.fsync_file = lambda path: (_ for _ in ()).throw(OSError("E15_INJECTED_FILE_FSYNC"))
elif scenario == "fsync-staging":
    original = common.fsync_directory
    def injected(path):
        if Path(path).name.startswith(common.STAGING_PREFIX):
            raise OSError("E15_INJECTED_STAGING_FSYNC")
        return original(path)
    common.fsync_directory = injected
elif scenario == "rename-failure":
    common.rename_noreplace = lambda *args: (_ for _ in ()).throw(OSError("E15_INJECTED_RENAME"))
elif scenario == "destination-race":
    original = common.rename_noreplace
    def injected(source, destination):
        destination.mkdir()
        (destination / "FOREIGN_SENTINEL").write_text("keep", encoding="utf-8")
        return original(source, destination)
    common.rename_noreplace = injected
elif scenario == "post-rename-parent-fsync":
    original = common.fsync_directory
    def injected(path):
        path = Path(path)
        if path == output.parent and output.exists():
            raise OSError("E15_INJECTED_POST_RENAME_PARENT_FSYNC")
        return original(path)
    common.fsync_directory = injected
else:
    raise SystemExit(f"unknown scenario: {scenario}")

os.environ["DATABASE_URL"] = "postgresql://synthetic.invalid/db"
sys.argv = [
    str(sandbox / "PR93_LOTE_E14_CAPTURE.py"),
    "--head-sha", head,
    "--repo-root", str(sandbox.parent.parent),
    "--output-dir", str(output),
    "--psql-bin", "synthetic-psql",
]
runpy.run_path(str(sandbox / "PR93_LOTE_E14_CAPTURE.py"), run_name="__main__")
'''

CLEAN_DRIVER = DRIVER.replace(
    'scenario = sys.argv[2]',
    'scenario = "clean" if False else sys.argv[2]',
).replace(
    'else:\n    raise SystemExit(f"unknown scenario: {scenario}")',
    'elif scenario != "clean":\n    raise SystemExit(f"unknown scenario: {scenario}")',
)


def run_driver(sandbox: Path, scenario: str, head: str, output: Path, clean: bool = False) -> tuple[int, str]:
    driver = CLEAN_DRIVER if clean else DRIVER
    result = subprocess.run(
        [sys.executable, "-c", driver, str(sandbox), scenario, head, str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    return result.returncode, result.stdout.decode("utf-8", "replace")


def staging_residue(parent: Path) -> list[str]:
    return sorted(
        item.name for item in parent.iterdir()
        if item.name.startswith(".pr93-e15-staging-")
    ) if parent.is_dir() else []


def plant_destination(root: Path, destination: Path, kind: str) -> Path | None:
    """Create the foreign object at the destination path. Returns its target."""
    if kind == "dangling-symlink":
        target = root / f"{destination.name}-absent-target"
        destination.symlink_to(target)
        return target
    if kind == "symlink-to-file":
        target = root / f"{destination.name}-target-file"
        target.write_text("keep", encoding="utf-8")
        destination.symlink_to(target)
        return target
    if kind == "symlink-to-directory":
        target = root / f"{destination.name}-target-dir"
        target.mkdir()
        (target / "FOREIGN_SENTINEL").write_text("keep", encoding="utf-8")
        destination.symlink_to(target, target_is_directory=True)
        return target
    if kind == "preexisting-regular-file":
        destination.write_text("keep", encoding="utf-8")
        return None
    if kind == "preexisting-directory":
        destination.mkdir()
        (destination / "FOREIGN_SENTINEL").write_text("keep", encoding="utf-8")
        return None
    raise SystemExit(f"unknown destination object: {kind}")


def assert_destination_preserved(destination: Path, kind: str, target: Path | None) -> None:
    if kind == "dangling-symlink":
        if not destination.is_symlink():
            raise SystemExit("dangling symlink destination was replaced")
        if target is None or target.is_symlink() or target.exists():
            raise SystemExit("capture created the pointed-to target")
        return
    if kind == "symlink-to-file":
        if not destination.is_symlink():
            raise SystemExit("symlink-to-file destination was replaced")
        if target is None or target.read_text(encoding="utf-8") != "keep":
            raise SystemExit("symlink target file was modified")
        return
    if kind == "symlink-to-directory":
        if not destination.is_symlink():
            raise SystemExit("symlink-to-directory destination was replaced")
        if target is None:
            raise SystemExit("missing symlink target directory")
        names = sorted(item.name for item in target.iterdir())
        if names != ["FOREIGN_SENTINEL"]:
            raise SystemExit(f"capture wrote through the symlink: {names}")
        return
    if kind == "preexisting-regular-file":
        if destination.is_symlink() or not destination.is_file():
            raise SystemExit("regular-file destination was replaced")
        if destination.read_text(encoding="utf-8") != "keep":
            raise SystemExit("regular-file destination was modified")
        return
    if kind == "preexisting-directory":
        if destination.is_symlink() or not destination.is_dir():
            raise SystemExit("directory destination was replaced")
        names = sorted(item.name for item in destination.iterdir())
        if names != ["FOREIGN_SENTINEL"]:
            raise SystemExit(f"directory destination was written into: {names}")
        return
    raise SystemExit(f"unknown destination object: {kind}")



def run_cleanup_adversarial(common, root: Path, kind: str) -> None:
    owned = root / f"{kind}-owned"
    moved = root / f"{kind}-moved"
    foreign_target = root / f"{kind}-foreign-target"
    owned.mkdir()
    (owned / "OWNED_PAYLOAD").write_text("owned", encoding="utf-8")
    identity = (owned.lstat().st_dev, owned.lstat().st_ino)

    original = common.discard_tree_contents
    hook = {"count": 0}

    def injected(directory_fd: int) -> bool:
        if hook["count"] == 0:
            hook["count"] += 1
            owned.rename(moved)
            if kind == "cleanup-name-swap":
                owned.mkdir()
                (owned / "FOREIGN_SENTINEL").write_text("keep", encoding="utf-8")
            elif kind == "cleanup-symlink-swap":
                foreign_target.mkdir()
                (foreign_target / "FOREIGN_SENTINEL").write_text(
                    "keep", encoding="utf-8"
                )
                owned.symlink_to(foreign_target, target_is_directory=True)
            else:
                raise SystemExit(f"unknown adversarial case: {kind}")
        return original(directory_fd)

    common.discard_tree_contents = injected
    try:
        removed = common.discard_owned_tree(owned, identity)
    finally:
        common.discard_tree_contents = original

    if hook["count"] != 1:
        raise SystemExit(f"{kind}: adversarial substitution never executed")
    if removed:
        raise SystemExit(f"{kind}: cleanup reported success after name substitution")

    if kind == "cleanup-name-swap":
        sentinel = owned / "FOREIGN_SENTINEL"
        if not sentinel.is_file() or sentinel.read_text(encoding="utf-8") != "keep":
            raise SystemExit(f"{kind}: foreign directory was removed or modified")
    else:
        if not owned.is_symlink():
            raise SystemExit(f"{kind}: foreign symlink was removed")
        sentinel = foreign_target / "FOREIGN_SENTINEL"
        if not sentinel.is_file() or sentinel.read_text(encoding="utf-8") != "keep":
            raise SystemExit(f"{kind}: symlink target was removed or modified")

    # Test-owned cleanup after preservation assertions.
    if owned.is_symlink():
        owned.unlink()
    elif owned.exists():
        shutil.rmtree(owned)
    if foreign_target.exists():
        shutil.rmtree(foreign_target)
    if moved.exists():
        shutil.rmtree(moved)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--only-adversarial", action="store_true")
    args = parser.parse_args()

    sandbox = args.repo_root.absolute() / "sandbox/lf_contract_gate_test"
    sys.path.insert(0, str(sandbox))
    import PR93_LOTE_E14_COMMON as common

    root_argument = args.output_root.absolute()
    if not root_argument.parent.is_dir() or root_argument.parent.is_symlink():
        parser.error("--output-root parent must be a real existing directory")
    try:
        root, root_identity = common.create_owned_output_root(root_argument)
    except (OSError, RuntimeError) as exc:
        parser.error(str(exc))

    passed = 0
    try:
        if not args.only_adversarial:
            for index, scenario in enumerate(SCENARIOS, start=1):
                destination = root / f"{index:02d}-{scenario}"
                code, output = run_driver(sandbox, scenario, args.head_sha, destination)
                if code != 20:
                    raise SystemExit(f"{scenario} returned {code}, expected 20:\n{output}")

                if scenario == "destination-race":
                    sentinel = destination / "FOREIGN_SENTINEL"
                    if not sentinel.is_file() or sentinel.read_text(encoding="utf-8") != "keep":
                        raise SystemExit("destination race did not preserve foreign sentinel")
                    destination_identity = (destination.lstat().st_dev, destination.lstat().st_ino)
                    if not common.discard_owned_tree(destination, destination_identity):
                        raise SystemExit("could not discard test-owned race destination")
                # CA-N139: symlink-aware existence check written without the
                # publication-pattern signature banned by the static scanner.
                elif destination.is_symlink() or destination.exists():
                    raise SystemExit(f"failed capture left destination: {destination}")

                residue = staging_residue(root)
                if residue:
                    raise SystemExit(f"failed capture left staging residue: {residue}")
                passed += 1
                print(f"PASS_E15_1_FAILURE_{index:02d}={scenario}")

                retry_code, retry_output = run_driver(
                    sandbox, "clean", args.head_sha, destination, clean=True
                )
                if retry_code != 0:
                    raise SystemExit(f"clean retry after {scenario} failed:\n{retry_output}")
                names = sorted(item.name for item in destination.iterdir())
                if len(names) != 9:
                    raise SystemExit(f"retry after {scenario} produced {len(names)} entries: {names}")
                if staging_residue(root):
                    raise SystemExit(f"retry after {scenario} left staging residue")
                passed += 1
                print(f"PASS_E15_1_RETRY_{index:02d}={scenario}")
                destination_identity = (destination.lstat().st_dev, destination.lstat().st_ino)
                if not common.discard_owned_tree(destination, destination_identity):
                    raise SystemExit("could not discard verified retry destination")

            offset = len(SCENARIOS)
            for position, kind in enumerate(DESTINATION_OBJECTS, start=1):
                index = offset + position
                destination = root / f"{index:02d}-{kind}"
                target = plant_destination(root, destination, kind)
                code, output = run_driver(
                    sandbox, "clean", args.head_sha, destination, clean=True
                )
                if code != 20:
                    raise SystemExit(
                        f"destination object {kind} returned {code}, expected 20:\n{output}"
                    )
                assert_destination_preserved(destination, kind, target)
                residue = staging_residue(root)
                if residue:
                    raise SystemExit(f"destination object {kind} left staging: {residue}")
                passed += 1
                print(f"PASS_E15_1_DESTINATION_{index:02d}={kind}")

        adversarial_offset = len(SCENARIOS) + len(DESTINATION_OBJECTS)
        for position, kind in enumerate(ADVERSARIAL_CASES, start=1):
            run_cleanup_adversarial(common, root, kind)
            passed += 1
            index = adversarial_offset + position
            print(f"PASS_E15_1_ADVERSARIAL_{index:02d}={kind}")

        expected = (
            len(ADVERSARIAL_CASES)
            if args.only_adversarial
            else len(SCENARIOS) * 2 + len(DESTINATION_OBJECTS) + len(ADVERSARIAL_CASES)
        )
        if passed != expected:
            raise SystemExit(f"regression count mismatch: {passed}/{expected}")
        if args.only_adversarial:
            print(f"PASS_E15_1_CA_N143_ADVERSARIAL={passed}/{expected}")
        else:
            print(f"PASS_E15_1_CAPTURE_REGRESSION={passed}/{expected}")
        return 0
    finally:
        # Remove only the exact root inode created by this process.
        if not common.discard_owned_tree(root, root_identity):
            raise SystemExit("refusing to remove output root after identity changed")


if __name__ == "__main__":
    raise SystemExit(main())
