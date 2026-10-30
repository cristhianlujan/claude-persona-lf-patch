"""PG00 C3 authenticated read-only source adapter (candidate, fail closed).

Uses GitHub authenticated contents API at a *full* commit SHA. Never uses
caller-supplied source_authenticated. Does not grant PG-01 admission:
independent Train/PASE binding of exact C3 release is still required.
"""
from __future__ import annotations
import base64, hashlib, json, re, urllib.request
from dataclasses import dataclass

REPO = "paulozterra/lf-programming-sandbox"
PATH = "standards/catalog.json"
HEX40 = re.compile(r"^[a-f0-9]{40}$")

class SourceError(ValueError): pass

@dataclass(frozen=True)
class SourceReadback:
    repository: str
    exact_commit: str
    path: str
    sha256: str
    catalog_version: str
    schema_version: str

def read_git_source_exact(commit: str, token: str, opener=None) -> SourceReadback:
    if not isinstance(commit, str) or not HEX40.fullmatch(commit):
        raise SourceError("INVALID_EXACT_COMMIT")
    if not isinstance(token, str) or not token.strip():
        raise SourceError("NO_GITHUB_CREDENTIAL")
    if opener is None:
        opener = urllib.request.urlopen
    url = f"https://api.github.com/repos/{REPO}/contents/{PATH}?ref={commit}"
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": "Bearer " + token,
        "X-GitHub-Api-Version": "2022-11-28",
    })
    try:
        with opener(req, timeout=15) as response:
            body = response.read()
    except Exception as exc:
        raise SourceError("GITHUB_READBACK_UNAVAILABLE") from exc
    try:
        payload = json.loads(body)
        if payload.get("type") != "file" or payload.get("path") != PATH:
            raise SourceError("SOURCE_PATH_MISMATCH")
        if payload.get("encoding") != "base64":
            raise SourceError("SOURCE_ENCODING_UNSUPPORTED")
        raw = base64.b64decode(payload["content"], validate=False)
        blob_sha = hashlib.sha1(b"blob " + str(len(raw)).encode() + bytes([0]) + raw).hexdigest()
        if payload.get("sha") != blob_sha:
            raise SourceError("GITHUB_BLOB_SHA_MISMATCH")
        catalog = json.loads(raw)
        if catalog.get("schema_version") != "LF_STANDARDS_CATALOG_V1":
            raise SourceError("SOURCE_SCHEMA_MISMATCH")
        if not isinstance(catalog.get("catalog_version"), str):
            raise SourceError("SOURCE_VERSION_INVALID")
    except SourceError: raise
    except Exception as exc:
        raise SourceError("SOURCE_PAYLOAD_INVALID") from exc
    return SourceReadback(REPO, commit, PATH, hashlib.sha256(raw).hexdigest(),
                          catalog["catalog_version"], catalog["schema_version"])

def check_db_against_git(db_readback: dict, source: SourceReadback) -> dict:
    fail = lambda reason: {"verified": False, "decision": "BLOCK", "reason": reason}
    if not isinstance(db_readback, dict) or db_readback.get("found") is not True:
        return fail("DB_RELEASE_MISSING")
    expected = (db_readback.get("source_repo"), db_readback.get("source_commit_sha"),
                db_readback.get("source_file_sha256"), db_readback.get("catalog_version"))
    actual = (source.repository, source.exact_commit, source.sha256, source.catalog_version)
    if expected != actual:
        return fail("REPOSITORY_COMMIT_DIGEST_VERSION_MISMATCH")
    if db_readback.get("catalog_jsonb_sha256") != db_readback.get("recomputed_jsonb_sha256"):
        return fail("DB_JSONB_DIGEST_DRIFT")
    # A source digest match has no authority without a linked Train receipt.
    return fail("SOURCE_MATCHED_TRAIN_BINDING_REQUIRED")
