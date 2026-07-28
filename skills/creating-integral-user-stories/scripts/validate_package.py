"""Validate skill package inventory against canonical manifest.yaml. Implements J11 assertions."""
import os
import re
import sys

from lf_common import argv_path, emit

PLACEHOLDERS = ("TODO", "TBD", "FIXME", "LOREM_IPSUM", "PENDIENTE_RELLENAR")
FILE_SUFFIXES = (".md", ".yaml", ".json", ".py")
SELF_PATH = "scripts/validate_package.py"


def manifest_paths(path):
    expected = []
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            stripped = raw.strip()
            if not stripped.startswith("- "):
                continue
            value = stripped[2:].strip().strip("\"'")
            if value in ("SKILL.md", "manifest.yaml"):
                expected.append(value)
            elif "/" in value and value.endswith(FILE_SUFFIXES):
                expected.append(value)
    return sorted(set(expected))


def scan_body(relative_path, body):
    if relative_path != SELF_PATH:
        return body
    return "\n".join(
        line for line in body.splitlines()
        if not line.lstrip().startswith("PLACEHOLDERS =")
    )


def main():
    root = argv_path(1)
    manifest_path = os.path.join(root, "manifest.yaml")
    if not os.path.isfile(manifest_path):
        return emit(
            "J11_SKILL_PACKAGE",
            ["invalid_manifest_references=1"],
            {"manifest_path": "manifest.yaml", "manifest_found": False},
        )

    expected = manifest_paths(manifest_path)
    actual = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [name for name in dirs if name != "__pycache__"]
        for name in files:
            if name.endswith(".pyc"):
                continue
            rel = os.path.relpath(os.path.join(base, name), root)
            actual.append(rel.replace(os.sep, "/"))
    actual = sorted(actual)

    missing = [path for path in expected if path not in actual]
    unexpected = [path for path in actual if path not in expected]
    placeholder_hits = []
    empty = 0
    pattern = re.compile(r"\b(?:%s)\b" % "|".join(map(re.escape, PLACEHOLDERS)))

    for rel in actual:
        with open(os.path.join(root, rel), "r", encoding="utf-8") as handle:
            body = handle.read()
        if not body.strip():
            empty += 1
        for match in pattern.finditer(scan_body(rel, body)):
            placeholder_hits.append({"path": rel, "token": match.group(0)})

    failed = []
    if missing:
        failed.append("missing_required_files=%d" % len(missing))
    if unexpected:
        failed.append("unexpected_files=%d" % len(unexpected))
    if placeholder_hits:
        failed.append("placeholder_count=%d" % len(placeholder_hits))
    if empty:
        failed.append("empty_required_sections=%d" % empty)

    evidence = {
        "manifest_path": "manifest.yaml",
        "expected_files": len(expected),
        "actual_files": len(actual),
        "missing": missing,
        "unexpected": unexpected,
        "placeholder_count": len(placeholder_hits),
        "placeholder_hits": placeholder_hits,
        "empty_required_sections": empty,
    }
    return emit("J11_SKILL_PACKAGE", failed, evidence)


if __name__ == "__main__":
    sys.exit(main())
