import hashlib
import json
import subprocess
from pathlib import Path

from lf_material_currentness_v1 import evaluate


def sh(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, text=True, capture_output=True).stdout.strip()


def commit(repo: Path, message: str) -> str:
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", message)
    return sh(repo, "rev-parse", "HEAD")


def setup_repo(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    sh(repo, "init")
    sh(repo, "config", "user.email", "test@example.com")
    sh(repo, "config", "user.name", "LF Test")
    (repo / "core").mkdir(); (repo / "docs").mkdir()
    (repo / "core" / "a.txt").write_text("a1\n")
    (repo / "docs" / "readme.md").write_text("d1\n")
    a = commit(repo, "A")
    return repo, a


def binding(a, b, materials, completeness="COMPLETE", roots=None):
    return {
        "schema_version":"LF_MATERIAL_CURRENTNESS_BINDING_V1",
        "authority":{"ref":"refs/heads/main","bound_revision":a,"current_revision":b},
        "evidence_revision":a,
        "dependency_completeness":completeness,
        "require_ancestor":True,
        "materials":materials,
        "root_material_ids":roots or [m["material_id"] for m in materials],
    }


def git_core(depends=None):
    return {"material_id":"core","kind":"GIT_TREE","selectors":{"prefixes":["core/"]},"required":True,"depends_on":depends or []}


def test_unrelated_main_change_auto_rebind(tmp_path):
    repo,a=setup_repo(tmp_path)
    (repo/"docs"/"readme.md").write_text("d2\n")
    b=commit(repo,"B docs")
    r=evaluate(binding(a,b,[git_core()]),repo)
    assert r["decision"]=="CURRENT_REBOUND" and r["ready"] and r["rebind_allowed"]
    assert r["bound_material_fingerprint"]==r["current_material_fingerprint"]
    assert r["evidence_revision"]==a


def test_material_change_stale(tmp_path):
    repo,a=setup_repo(tmp_path)
    (repo/"core"/"a.txt").write_text("a2\n")
    b=commit(repo,"B core")
    r=evaluate(binding(a,b,[git_core()]),repo)
    assert r["decision"]=="STALE_AFFECTED" and not r["ready"]
    assert r["affected_root_material_ids"]==["core"]


def test_unknown_completeness_fail_closed(tmp_path):
    repo,a=setup_repo(tmp_path)
    r=evaluate(binding(a,a,[git_core()],completeness="UNKNOWN"),repo)
    assert r["decision"]=="UNKNOWN_FAIL_CLOSED"


def test_required_selector_empty_fail_closed(tmp_path):
    repo,a=setup_repo(tmp_path)
    spec={"material_id":"missing","kind":"GIT_TREE","selectors":{"prefixes":["absent/"]},"required":True,"depends_on":[]}
    r=evaluate(binding(a,a,[spec]),repo)
    assert r["decision"]=="UNKNOWN_FAIL_CLOSED"
    assert "REQUIRED_MATERIAL_EMPTY" in r["reason"]


def test_external_digest_change_stale(tmp_path):
    repo,a=setup_repo(tmp_path)
    old=hashlib.sha256(b"v1").hexdigest(); new=hashlib.sha256(b"v2").hexdigest()
    spec={"material_id":"capability:router","kind":"DIGEST","bound_digest":old,"current_digest":new,"depends_on":[]}
    r=evaluate(binding(a,a,[spec]),repo)
    assert r["decision"]=="STALE_AFFECTED"


def test_transitive_affected_closure(tmp_path):
    repo,a=setup_repo(tmp_path)
    (repo/"core"/"a.txt").write_text("a2\n")
    b=commit(repo,"B core")
    stable=hashlib.sha256(b"stable").hexdigest()
    m1=git_core()
    m2={"material_id":"consumer","kind":"DIGEST","bound_digest":stable,"current_digest":stable,"depends_on":["core"]}
    r=evaluate(binding(a,b,[m1,m2],roots=["consumer"]),repo)
    assert r["decision"]=="STALE_AFFECTED"
    assert r["affected_material_ids"]==["consumer","core"]
    assert r["affected_root_material_ids"]==["consumer"]


def test_same_revision_current(tmp_path):
    repo,a=setup_repo(tmp_path)
    r=evaluate(binding(a,a,[git_core()]),repo)
    assert r["decision"]=="CURRENT" and r["ready"] and not r["rebind_allowed"]


def test_diverged_authority_fail_closed(tmp_path):
    repo,a=setup_repo(tmp_path)
    sh(repo,"checkout","-b","other")
    (repo/"core"/"x.txt").write_text("x\n")
    b=commit(repo,"other")
    sh(repo,"checkout","master")
    (repo/"docs"/"z.txt").write_text("z\n")
    commit(repo,"master2")
    r=evaluate(binding(sh(repo,"rev-parse","HEAD"),b,[git_core()]),repo)
    assert r["decision"]=="UNKNOWN_FAIL_CLOSED" and r["reason"]=="AUTHORITY_DIVERGED"
