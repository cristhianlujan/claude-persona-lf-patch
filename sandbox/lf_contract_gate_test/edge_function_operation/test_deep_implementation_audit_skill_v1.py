"""Admit the candidate skill's local tests to existing R17; no workflow/DB changes."""
import subprocess
import sys
import unittest
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PACK = ROOT / "skills/auditoria-profunda-implementacion-lf"


def ensure_baseline_commit(repo, commit):
    """Retrieve one missing source commit; never weaken provenance validation.

    Actions checkout uses depth=1. The file can exist on disk while its reported
    base commit is absent. Fetch only that exact hex commit from this repo's origin.
    """
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("AUDIT_BASELINE_COMMIT_INVALID")
    probe = subprocess.run(["git", "cat-file", "-e", commit + "^{commit}"], cwd=repo,
                           text=True, capture_output=True, timeout=10)
    fetched = probe.returncode != 0
    if fetched:
        result = subprocess.run(["git", "fetch", "--no-tags", "--depth=1", "origin", commit],
                                cwd=repo, text=True, capture_output=True, timeout=60)
        if result.returncode:
            raise RuntimeError("AUDIT_BASELINE_FETCH_FAILED:" + result.stderr[-1000:])
    verified = subprocess.run(["git", "cat-file", "-e", commit + "^{commit}"],
                              cwd=repo, text=True, capture_output=True, timeout=10)
    if verified.returncode:
        raise RuntimeError("AUDIT_BASELINE_COMMIT_NOT_AVAILABLE:" + commit)
    return {"commit": commit, "fetched": fetched, "commit_available": True}


class DeepImplementationAuditR17(unittest.TestCase):
    def test_candidate_suite_and_pack(self):
        report = json.loads((PACK / "reports/pilot_report.json").read_text())
        print(json.dumps({"audit_baseline": ensure_baseline_commit(ROOT, report["base_commit"])}))
        for command in ([sys.executable, "-m", "unittest", "discover", "-s", str(PACK / "evals"), "-p", "test_*.py", "-v"],
                        [sys.executable, str(PACK / "validators/validate_pack.py")]):
            result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout[-1800:] + result.stderr[-6000:])


if __name__ == "__main__":
    unittest.main()
