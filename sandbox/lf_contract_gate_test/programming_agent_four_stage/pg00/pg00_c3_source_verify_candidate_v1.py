"""PG00_C3 independent source verifier. Read-only, never grants admission.
Expected source is an authenticated GitHub file read at exact 40-hex commit;
caller-supplied provenance and DB fields alone cannot satisfy this interface.
"""
import hashlib,json,re
from dataclasses import dataclass
from typing import Callable
SHA40=re.compile(r"^[0-9a-f]{40}$")
SHA64=re.compile(r"^[0-9a-f]{64}$")
REPO="paulozterra/lf-programming-sandbox"
PATH="standards/catalog.json"
@dataclass(frozen=True)
class AuthenticatedGitRead:
    repository:str
    exact_commit:str
    path:str
    file_bytes:bytes
    source_authenticated:bool
    def __post_init__(self):
        if not isinstance(self.file_bytes,bytes): raise TypeError("bytes required")

def verify_release(db_record:dict, authenticated_fetch:Callable[[str,str,str],AuthenticatedGitRead])->dict:
    failure={"verified":False,"decision":"BLOCK","reason":"UNVERIFIED_C3_RELEASE"}
    if not isinstance(db_record,dict) or db_record.get("found") is not True: return dict(failure,reason="MISSING_DB_RELEASE")
    if db_record.get("status")!="DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK": return dict(failure,reason="DB_STATE_UNEXPECTED")
    commit=db_record.get("source_commit_sha")
    if not isinstance(commit,str) or not SHA40.fullmatch(commit): return dict(failure,reason="INVALID_EXACT_COMMIT")
    if db_record.get("source_repo")!=REPO: return dict(failure,reason="WRONG_SOURCE_REPO")
    expected=db_record.get("source_file_sha256")
    if not isinstance(expected,str) or not SHA64.fullmatch(expected): return dict(failure,reason="INVALID_FILE_SHA")
    if db_record.get("catalog_jsonb_sha256")!=db_record.get("recomputed_jsonb_sha256"): return dict(failure,reason="DB_DIGEST_DRIFT")
    try: result=authenticated_fetch(REPO,commit,PATH)
    except Exception: return dict(failure,reason="SOURCE_FETCH_FAILED")
    if not isinstance(result,AuthenticatedGitRead) or not result.source_authenticated or (result.repository,result.exact_commit,result.path)!=(REPO,commit,PATH):
        return dict(failure,reason="SOURCE_NOT_AUTHENTICATED")
    if hashlib.sha256(result.file_bytes).hexdigest()!=expected: return dict(failure,reason="FILE_SHA_MISMATCH")
    try: source=json.loads(result.file_bytes)
    except (UnicodeDecodeError,ValueError):return dict(failure,reason="SOURCE_JSON_INVALID")
    if source.get("catalog_version")!=db_record.get("catalog_version") or source.get("schema_version")!="LF_STANDARDS_CATALOG_V1":
        return dict(failure,reason="SOURCE_VERSION_DRIFT")
    # A matching file is necessary but insufficient; independent Train/PASE authority
    # and authenticated DB snapshot were NOT established here.
    return {"verified":False,"decision":"BLOCK","reason":"SOURCE_MATCHED_AUTHORITY_NOT_ESTABLISHED",
            "source_sha256":expected,"source_commit_sha":commit}
