from __future__ import annotations

import hashlib
import json
import tempfile
from pathlib import Path

from profile_candidate_materializer_v1 import materialize


REV = "a" * 40


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def base_candidate(before_sha: str):
    return {
        "schema": "PROFILE_EVOLUTION_CANDIDATE_OVERLAY_V1",
        "profile_code": "PERFIL-TEST",
        "profile_slug": "test_profile",
        "baseline_revision": REV,
        "evolution_mode": "SPECIALIZE",
        "authority_state": "NON_AUTHORITY_CANDIDATE",
        "reversible": True,
        "profile_source_write_authorized": False,
        "runtime_activation": False,
        "production_activation": False,
        "evidence_map": [{"source_ref": "benchmark://evidence/1", "supports": ["specialization delta"]}],
        "preservation_constraints": ["preserve identity", "no runtime activation"],
        "changes": [
            {"path": "SKILL.md", "operation": "UPSERT", "before_sha256": before_sha, "content": "# Specialized\n"},
            {"path": "contracts/new.md", "operation": "UPSERT", "before_sha256": None, "content": "# New contract\n"},
        ],
    }


def expect_fail(candidate, repo, out, code, rev=REV):
    try:
        materialize(candidate, repo, out, rev)
    except Exception as exc:
        assert str(exc) == code, (str(exc), code)
        return
    raise AssertionError(f"EXPECTED_FAIL:{code}")


def run():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        repo = root / "repo"
        profile = repo / "profiles/test_profile"
        profile.mkdir(parents=True)
        original = "# Generic\n"
        (profile / "SKILL.md").write_text(original, encoding="utf-8")

        candidate = base_candidate(sha(original))
        receipt = materialize(candidate, repo, root / "candidate", REV)
        assert receipt["source_unchanged"] is True
        assert receipt["authority_state"] == "NON_AUTHORITY_CANDIDATE"
        assert (profile / "SKILL.md").read_text(encoding="utf-8") == original
        assert (root / "candidate/test_profile/SKILL.md").read_text(encoding="utf-8") == "# Specialized\n"
        assert (root / "candidate/test_profile/contracts/new.md").is_file()
        assert receipt["changed_paths"] == ["SKILL.md", "contracts/new.md"]

        bad = base_candidate("0" * 64)
        expect_fail(bad, repo, root / "bad1", "CANDIDATE_BEFORE_SHA256_MISMATCH")

        bad = base_candidate(sha(original))
        bad["changes"][0]["path"] = "../escape.md"
        expect_fail(bad, repo, root / "bad2", "CANDIDATE_PATH_ESCAPE")

        bad = base_candidate(sha(original))
        bad["profile_source_write_authorized"] = True
        expect_fail(bad, repo, root / "bad3", "CANDIDATE_SOURCE_WRITE_AUTHORITY_FORBIDDEN")

        bad = base_candidate(sha(original))
        expect_fail(bad, repo, repo / "candidate", "CANDIDATE_OUTPUT_INSIDE_AUTHORITY_REPOSITORY")

        bad = base_candidate(sha(original))
        expect_fail(bad, repo, root / "bad5", "CANDIDATE_BASELINE_REVISION_MISMATCH", rev="b" * 40)

        no_change = base_candidate(sha(original))
        no_change["evolution_mode"] = "NO_CHANGE"
        no_change["changes"] = []
        r = materialize(no_change, repo, root / "nochange", REV)
        assert r["changed_paths"] == [] and r["deleted_paths"] == []

    print("PASS_PROFILE_CANDIDATE_MATERIALIZER_V1 positive=2 negative=5 authority_writes=0")


if __name__ == "__main__":
    run()
