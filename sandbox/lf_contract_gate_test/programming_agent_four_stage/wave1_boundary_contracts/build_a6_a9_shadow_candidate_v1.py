"""Reproducible tracked-source archive only. Never installs or starts anything."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile


def _git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def build_candidate(repo, revision, output_directory):
    repo = Path(repo).resolve()
    output = Path(output_directory).resolve()
    if re.fullmatch(r"[0-9a-f]{40}", revision or "") is None:
        raise ValueError("EXACT_COMMIT_REQUIRED")
    if output == repo or repo in output.parents:
        raise ValueError("OUTPUT_MUST_BE_OUTSIDE_SOURCE")
    if _git(repo, "rev-parse", "--verify", revision + "^{commit}").decode().strip() != revision:
        raise ValueError("EXACT_COMMIT_REQUIRED")
    source_tree = _git(repo, "rev-parse", revision + "^{tree}").decode().strip()
    entries = _git(repo, "ls-tree", "-rz", revision).split(b"\0")
    tracked = set()
    for entry in entries:
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, kind, _oid = metadata.split()
        if kind != b"blob" or mode not in {b"100644", b"100755"}:
            raise ValueError("ARCHIVE_LINK_OR_SPECIAL_UNSUPPORTED")
        tracked.add(raw_path.decode("utf-8"))
    archive = _git(repo, "archive", "--format=tar", revision)
    # Validate members and compare bytes with their Git blobs. Export transforms,
    # submodules or symlinks require explicit packaging support, never silent use.
    inventory = []
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as bundle:
        for member in bundle:
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts or member.name in seen:
                raise ValueError("ARCHIVE_MEMBER_UNSAFE")
            seen.add(member.name)
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError("ARCHIVE_LINK_OR_SPECIAL_UNSUPPORTED")
            raw = bundle.extractfile(member).read()
            expected = _git(repo, "show", revision + ":" + member.name)
            if raw != expected:
                raise ValueError("ARCHIVE_GIT_BYTES_MISMATCH")
            inventory.append({"path": member.name, "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)})
    if not inventory:
        raise ValueError("ARCHIVE_EMPTY")
    if {item["path"] for item in inventory} != tracked:
        raise ValueError("ARCHIVE_TRACKED_INVENTORY_MISMATCH")
    manifest = {"schema_version": "A6_A9_SOURCE_CANDIDATE_BUNDLE_V1",
                "source_commit": revision, "source_tree": source_tree,
                "archive_sha256": hashlib.sha256(archive).hexdigest(),
                "archive_bytes": len(archive), "files": inventory,
                "tracked_source_only": True, "deployment_allowed": False,
                "operational_admission": False, "model_execution_allowed": False}
    output.mkdir(parents=True, exist_ok=True)
    archive_path = output / (revision + ".tar")
    manifest_path = output / (revision + ".manifest.json")
    # Refuse overwrite: a previous artifact remains reviewable.
    with archive_path.open("xb") as f:
        f.write(archive)
    try:
        with manifest_path.open("x") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
            f.write("\n")
    except Exception:
        archive_path.unlink()
        raise
    if archive_path.read_bytes() != archive or json.loads(manifest_path.read_text()) != manifest:
        raise ValueError("CANDIDATE_READBACK_MISMATCH")
    return {"archive_path": str(archive_path), "manifest_path": str(manifest_path),
            "source_commit": revision, "source_tree": source_tree,
            "archive_sha256": manifest["archive_sha256"], "files": len(inventory),
            "deployment_allowed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--output-directory", required=True)
    args = parser.parse_args()
    print(json.dumps(build_candidate(args.repo_root, args.revision, args.output_directory)))


if __name__ == "__main__":
    main()
