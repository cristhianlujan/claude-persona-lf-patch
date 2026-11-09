"""Find synthetic values that still reach a stage output (fail-closed audit)."""
import re

PATTERNS = [
    ("FIXTURE_URI", re.compile(r"fixture://")),
    ("SYNTHETIC_REPO", re.compile(r"lf-synthetic|sandbox/example")),
    ("REPEATED_HEX40", re.compile(r"^([0-9a-f])\1{39}$")),
    ("REPEATED_HEX64", re.compile(r"^([0-9a-f])\1{63}$")),
    ("FIXTURE_TOOL", re.compile(r"fixture-")),
    ("SYNTHETIC_PATH", re.compile(r"^src/SOL-|^backend/api|^frontend/ui|^database/migration")),
]


def walk(obj, path="$"):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk(v, path + "." + str(k))
    elif isinstance(obj, (list, tuple)):
        for i, v in enumerate(obj):
            yield from walk(v, path + "[" + str(i) + "]")
    elif isinstance(obj, str):
        yield path, obj


def audit(obj):
    hits = []
    for path, value in walk(obj):
        for code, rx in PATTERNS:
            if rx.search(value):
                hits.append((code, path, value[:80]))
    return hits
