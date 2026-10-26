"""Read-only artifact backends; real temporary Git objects and bounded exports."""
from copy import deepcopy
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import test_programming_pg01_preplanning_receiver_v1 as integration_cases
from programming_pg01_exact_artifact_reader_v1 import (
    LocalGitBackend, ConnectedReadbackBackend, ExactArtifactReader, SourceReadError, blob_oid,
)
from programming_pg01_preplanning_receiver_v1 import SourcePreplanningReceiver


def git(repo, *args):
    env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8",
           "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"}
    return subprocess.check_output(["/usr/bin/git", "-C", str(repo),
        "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
        "-c", "core.hooksPath=/dev/null", *args], env=env, stderr=subprocess.DEVNULL)


def make_repository(root, origin="fixture/product"):
    root.mkdir(parents=True, exist_ok=True)
    git(root, "init", "-q", "-b", "main")
    git(root, "remote", "add", "origin", "https://github.com/" + origin + ".git")


def commit(root):
    git(root, "add", "--", ".")
    git(root, "commit", "-q", "-m", "fixture")
    return git(root, "rev-parse", "HEAD").decode().strip()


def fixture_git_reader(fixture, root):
    make_repository(root, fixture.repo)
    for name, data in fixture.store.items():
        (root / name).write_bytes(data)
    revision = commit(root)
    for value in fixture.frame.values():
        if isinstance(value, dict) and "commit" in value:
            value["commit"] = revision
    return ExactArtifactReader(LocalGitBackend({fixture.repo: root}))


class ExactArtifactReaderChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="pg01-source-reader-")
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / "repo"
        make_repository(self.repo)
        self.raw = b'{"fixture":"one"}\n'
        (self.repo / "material.json").write_bytes(self.raw)
        (self.repo / "literal[1].json").write_bytes(self.raw)
        (self.repo / "unsafe").symlink_to("/etc/passwd")
        self.revision = commit(self.repo)
        self.reader = ExactArtifactReader(LocalGitBackend({"fixture/product": self.repo}))
        self.pin = {"repo":"fixture/product","commit":self.revision,
                    "path":"material.json","sha256":hashlib.sha256(self.raw).hexdigest()}

    def test_exact_bytes_and_observation(self):
        self.assertEqual(self.reader(self.pin), self.raw)
        got = self.reader.observe(self.pin, revision=self.revision)
        self.assertEqual(got["blob_sha"], blob_oid(self.raw))
        self.assertNotIn("ready", got)
        self.assertNotIn("decision", got)

    def test_ignores_mutable_worktree(self):
        (self.repo / "material.json").write_text("uncommitted")
        self.assertEqual(self.reader(self.pin), self.raw)

    def test_observation_independent_of_expected_hash(self):
        new = b'{"fixture":"two"}\n'
        (self.repo / "material.json").write_bytes(new)
        revision = commit(self.repo)
        got = self.reader.observe(self.pin, revision=revision)
        self.assertEqual(got["sha256"], hashlib.sha256(new).hexdigest())
        self.assertNotEqual(got["sha256"], self.pin["sha256"])
        self.assertEqual(self.reader(self.pin), self.raw)

    def test_mutable_ref_and_noncommit_rejected(self):
        for revision in ("main", "HEAD", blob_oid(self.raw)):
            with self.subTest(revision=revision), self.assertRaises(SourceReadError):
                self.reader({**self.pin, "commit": revision})

    def test_unknown_repository_and_mismatched_origin(self):
        with self.assertRaisesRegex(SourceReadError, "REPOSITORY_NOT_REGISTERED"):
            self.reader({**self.pin,"repo":"other/product"})
        git(self.repo, "remote", "set-url", "origin", "https://github.com/other/product.git")
        with self.assertRaisesRegex(SourceReadError, "REGISTERED_ORIGIN_MISMATCH"):
            self.reader(self.pin)

    def test_path_traversal_missing_and_symlink_rejected(self):
        for path in ("../material.json", "/etc/passwd", "a//b", ".", "missing", "unsafe"):
            with self.subTest(path=path), self.assertRaises(SourceReadError):
                self.reader({**self.pin,"path":path})

    def test_replace_refs_cannot_reinterpret_commit(self):
        (self.repo / "material.json").write_bytes(b"replacement")
        replacement = commit(self.repo)
        git(self.repo, "replace", self.revision, replacement)
        self.assertEqual(self.reader(self.pin), self.raw)

    def test_partial_clone_rejected_before_object_reads(self):
        git(self.repo, "config", "remote.origin.promisor", "true")
        with self.assertRaisesRegex(SourceReadError, "PARTIAL_CLONE_NOT_SUPPORTED"):
            self.reader(self.pin)

    def test_literal_path_no_wildcard(self):
        self.assertEqual(self.reader({**self.pin,"path":"literal[1].json"}), self.raw)
        with self.assertRaises(SourceReadError):
            self.reader({**self.pin,"path":"*.json"})

    def test_sha256_mismatch_and_size_limit(self):
        with self.assertRaisesRegex(SourceReadError, "ARTIFACT_SHA256_MISMATCH"):
            self.reader({**self.pin,"sha256":"0"*64})
        with self.assertRaisesRegex(SourceReadError, "ARTIFACT_TOO_LARGE"):
            ExactArtifactReader(LocalGitBackend({"fixture/product":self.repo}, max_bytes=1))(self.pin)

    def connected(self, mutate=None, content=None, max_bytes=1024*1024):
        row = {"repo":self.pin["repo"],"commit":self.revision,"path":self.pin["path"],
               "blob_sha":blob_oid(self.raw),"encoding":"base64",
               "content":base64.b64encode(self.raw if content is None else content).decode()}
        if mutate: mutate(row)
        registry = {(self.pin["repo"], self.revision, self.pin["path"]):blob_oid(self.raw)}
        return ExactArtifactReader(ConnectedReadbackBackend(registry, lambda *a: row, max_bytes=max_bytes))

    def test_connected_exact_readback(self):
        self.assertEqual(self.connected()(self.pin), self.raw)

    def test_connected_identity_and_blob_must_match_tree(self):
        for field, value in (("repo","other/product"),("commit","0"*40),("path","other"),("blob_sha","0"*40),("encoding","utf-8")):
            with self.subTest(field=field), self.assertRaises(SourceReadError):
                self.connected(lambda row:row.update({field:value}))(self.pin)

    def test_connected_tampered_bytes_rejected(self):
        with self.assertRaisesRegex(SourceReadError, "GIT_BLOB_DIGEST_MISMATCH"):
            self.connected(content=b"tampered")(self.pin)

    def test_connected_invalid_base64_and_limit(self):
        with self.assertRaisesRegex(SourceReadError, "CONNECTED_BASE64_INVALID"):
            self.connected(lambda row:row.update(content="!"))(self.pin)
        with self.assertRaisesRegex(SourceReadError, "ARTIFACT_TOO_LARGE"):
            self.connected(max_bytes=1)(self.pin)

    def test_unregistered_connected_source_never_fetches(self):
        calls = []
        reader = ExactArtifactReader(ConnectedReadbackBackend({},lambda *a:calls.append(a)))
        with self.assertRaisesRegex(SourceReadError, "SOURCE_NOT_REGISTERED"):
            reader(self.pin)
        self.assertEqual(calls, [])

    def test_framework_reads_actual_git_objects(self):
        case = integration_cases.IntegratedReceiverChecks();case.setUp()
        reader = fixture_git_reader(case.fixture,Path(self.tmp.name)/"technical")
        wrapper = case.receiver(reader=reader)
        got = wrapper.consume(case.expected,"S1")
        self.assertEqual(got["state"],"ACCEPT")
        self.assertEqual(got["technical_framework"]["status"],"COMPLETE")
        self.assertFalse(got["operational_admission"])


def exercise_git_source_reads(*, boundary, expected, check):
    fixture = integration_cases.case_fixture()
    with tempfile.TemporaryDirectory(prefix="pg01-sql-git-sources-") as folder:
        reader = fixture_git_reader(fixture, Path(folder))
        provider = lambda e,s,c: integration_cases.packet_for(e,c,fixture)
        wrapper = SourcePreplanningReceiver(boundary,provider,reader,
            technical_currentness=integration_cases.currentness_fixture(fixture))
        got = wrapper.consume(expected,"S1")
        check("source_git_real_objects_integrated_ACCEPT",got["state"],"ACCEPT")
        check("source_git_framework_COMPLETE",got["technical_framework"]["status"],"COMPLETE")
        pin=fixture.frame["standards_catalog"]
        observed=reader.observe(pin,revision=pin["commit"])
        check("source_git_observed_digest_matches_bound",observed["sha256"],pin["sha256"])
        check("source_git_observation_is_not_admission","ready" in observed,False)
        check("source_git_never_operational",got["operational_admission"],False)
        return {"evidence_tier":"LOCAL_GIT_OBJECT_READ_WITH_SYNTHETIC_ARTIFACTS","operational_provider_qualified":False}


if __name__ == "__main__":
    unittest.main()
