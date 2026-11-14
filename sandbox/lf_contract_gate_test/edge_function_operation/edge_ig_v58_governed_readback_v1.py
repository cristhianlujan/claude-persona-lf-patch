"""Fail-closed sandbox-only exact-source readback for IG V58 (Agent + Validator).

Supabase Management GET /functions/{slug} contains metadata, NOT source files.
The pinned Supabase CLI uses the existing SUPABASE_ACCESS_TOKEN to download
and unbundle GET /functions/{slug}/body into an isolated temporary directory.
Never hash bundle metadata or GitHub source in place of downloaded index.ts.
"""
from __future__ import annotations
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

PROJECT_REF = "mhwmirqcgxxukpctffuv"
TARGETS = {
    "input-governance-agent-v1": "supabase/functions/input-governance-agent-v1/index.ts",
    "input-governance-validator-v1": "supabase/functions/input-governance-validator-v1/index.ts",
}
MAX_SOURCE_BYTES = 2_000_000

class ReadbackBlocked(Exception):
    pass

def inspect_metadata(payload, slug, source, expected_sha=None, min_version=1):
    if slug not in TARGETS:
        raise ReadbackBlocked("IG_V58_TARGET_NOT_ALLOWED")
    if not isinstance(payload, dict) or payload.get("slug") != slug:
        raise ReadbackBlocked("IG_V58_WRONG_TARGET")
    if payload.get("status") != "ACTIVE" or payload.get("verify_jwt") is not True:
        raise ReadbackBlocked("IG_V58_STATUS_OR_JWT_DRIFT")
    version = payload.get("version")
    if type(version) is not int or version < min_version:
        raise ReadbackBlocked("IG_V58_EDGE_VERSION_NOT_ADVANCED")
    if not isinstance(source, bytes) or not 0 < len(source) <= MAX_SOURCE_BYTES:
        raise ReadbackBlocked("IG_V58_BODY_SOURCE_INVALID")
    source_sha = hashlib.sha256(source).hexdigest()
    if expected_sha is not None and source_sha != expected_sha:
        raise ReadbackBlocked("IG_V58_DEPLOYED_SOURCE_SHA_MISMATCH")
    if expected_sha is not None:
        if slug == "input-governance-agent-v1" and b"CURATOR_RECURATION_SUCCESSOR" not in source:
            raise ReadbackBlocked("IG_V58_AGENT_CASCADE_NOT_DEPLOYED")
        if slug == "input-governance-validator-v1" and b"VALIDATOR_RECURATION_RECEIPT_INVALID" not in source:
            raise ReadbackBlocked("IG_V58_VALIDATOR_NEGATIVE_NOT_DEPLOYED")
    return {
        "status": "READBACK_PASS",
        "source_transport": "MANAGEMENT_BODY_UNBUNDLED_PINNED_CLI",
        "project_ref": PROJECT_REF,
        "slug": slug,
        "version": version,
        "verify_jwt": True,
        "source_sha256": source_sha,
        "ezbr_sha256": payload.get("ezbr_sha256"),
    }

def read_metadata(slug, opener=urlopen):
    if slug not in TARGETS:
        raise ReadbackBlocked("IG_V58_TARGET_NOT_ALLOWED")
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
    if not token:
        raise ReadbackBlocked("IG_V58_MANAGEMENT_TOKEN_MISSING")
    req = Request(
        "https://api.supabase.com/v1/projects/" + PROJECT_REF + "/functions/" + slug,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/json",
            "Cache-Control": "no-store",
        },
        method="GET",
    )
    try:
        with opener(req, timeout=20) as res:
            if res.status != 200:
                raise ReadbackBlocked("IG_V58_MANAGEMENT_NON_200")
            return json.loads(res.read(2000000))
    except HTTPError as ex:
        raise ReadbackBlocked("IG_V58_MANAGEMENT_HTTP_" + str(ex.code)) from None
    except (URLError, OSError, TimeoutError):
        raise ReadbackBlocked("IG_V58_MANAGEMENT_UNAVAILABLE") from None

def read_body_index(slug, runner=subprocess.run):
    """GET /body via the pinned CLI. Extract into temp; no repository/source edits."""
    if slug not in TARGETS:
        raise ReadbackBlocked("IG_V58_TARGET_NOT_ALLOWED")
    if not os.environ.get("SUPABASE_ACCESS_TOKEN"):
        raise ReadbackBlocked("IG_V58_MANAGEMENT_TOKEN_MISSING")
    with tempfile.TemporaryDirectory(prefix="lf-ig-v58-body-") as tmp:
        root = Path(tmp)
        config_source = Path("supabase/config.toml")
        if not config_source.is_file():
            raise ReadbackBlocked("IG_V58_LOCAL_CONFIG_MISSING")
        (root / "supabase").mkdir()
        shutil.copyfile(config_source, root / "supabase/config.toml")
        cmd = [
            "supabase", "functions", "download", slug,
            "--project-ref", PROJECT_REF, "--use-api",
        ]
        try:
            result = runner(cmd, cwd=str(root), env=os.environ.copy(),
                            capture_output=True, timeout=120, check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise ReadbackBlocked("IG_V58_BODY_DOWNLOAD_UNAVAILABLE") from None
        if result.returncode != 0:
            # Never print CLI output: it may contain request metadata.
            raise ReadbackBlocked("IG_V58_BODY_DOWNLOAD_FAILED")
        path = root / TARGETS[slug]
        if not path.is_file() or path.is_symlink():
            raise ReadbackBlocked("IG_V58_BODY_INDEX_NOT_DOWNLOADED")
        if path.stat().st_size > MAX_SOURCE_BYTES:
            raise ReadbackBlocked("IG_V58_BODY_SOURCE_OVERSIZE")
        return path.read_bytes()

def main(argv):
    if len(argv) not in (2, 3, 4):
        print(json.dumps({"status": "BLOCKED", "reason": "IG_V58_READBACK_ARGS_INVALID"}))
        return 2
    slug = argv[1]
    try:
        min_version = int(argv[2]) if len(argv) >= 3 else 1
        expected = argv[3] if len(argv) == 4 else None
        if expected is not None and (
            len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected)
        ):
            raise ReadbackBlocked("IG_V58_EXPECTED_SHA_INVALID")
        result = inspect_metadata(read_metadata(slug), slug,
                                  read_body_index(slug), expected, min_version)
    except (ReadbackBlocked, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "BLOCKED", "reason": str(exc)}))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
