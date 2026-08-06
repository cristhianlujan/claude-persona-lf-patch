#!/usr/bin/env python3
"""Static, fail-closed assertions for PR93 production P0 Edge proxy hardening."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRITE = ROOT / "supabase/migrations/edge_functions/run-github-write-perfil-lf/index.ts"
READBACK = ROOT / "supabase/migrations/edge_functions/run-github-readback-perfil-lf/index.ts"


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"missing {label}: {needle}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise AssertionError(f"forbidden {label}: {needle}")


def main() -> None:
    write = WRITE.read_text(encoding="utf-8")
    readback = READBACK.read_text(encoding="utf-8")

    common_requirements = {
        'const TARGET_REPOSITORY = "cristhianlujan/claude-persona-lf-patch";': "fixed repository",
        'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")': "service role secret",
        "constantTimeEqual(received, expected)": "constant-time credential comparison",
        'code: "SERVICE_ROLE_REQUIRED"': "service-role denial",
        '"Cache-Control": "no-store"': "non-cacheable responses",
        '"profiles/"': "profile path allowlist",
        '"sandbox/lf_contract_gate_test/receipts/"': "receipt path allowlist",
        "path.includes(\"..\")": "path traversal rejection",
        "repo !== TARGET_REPOSITORY": "repository enforcement",
    }
    for source_name, source in (("write", write), ("readback", readback)):
        for needle, label in common_requirements.items():
            require(source, needle, f"{source_name} {label}")
        forbid(source, '"Access-Control-Allow-Origin": "*"', f"{source_name} wildcard CORS")
        forbid(source, "body.repo ||", f"{source_name} caller-selected repository fallback")

    require(write, 'branch === "main" || branch === "master"', "write default-branch block")
    require(write, '"POST", "/git/blobs"', "atomic blob creation")
    require(write, '"POST", "/git/trees"', "atomic tree creation")
    require(write, '"POST", "/git/commits"', "atomic commit creation")
    require(write, '"PATCH", `/git/refs/heads/${encodedRef(branch)}`', "non-force ref update")
    require(write, "force: false", "force-push prevention")
    require(write, 'code: "NON_FAST_FORWARD_OR_REF_UPDATE_FAILED"', "concurrent update rejection")
    forbid(write, 'method: "PUT"', "per-file contents writes")
    forbid(write, "/contents/", "legacy contents endpoint")

    require(readback, "/contents/${encodedPath}?ref=", "bounded contents read")
    require(readback, 'code: "FILE_SHA_MISMATCH"', "Git blob mismatch detection")
    require(readback, 'code: "CONTENT_SHA_MISMATCH"', "content digest mismatch detection")
    require(readback, "await sha256Hex(content)", "independent content digest")

    print("PASS_P0_EDGE_AUTH_STATIC=24/24")


if __name__ == "__main__":
    main()
