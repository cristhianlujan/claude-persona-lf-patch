"""Adversarial source evidence checks; always BLOCK until independent runtime exists."""
import copy,hashlib,json
from pg00_c3_source_verify_candidate_v1 import verify_release,AuthenticatedGitRead,REPO,PATH
payload=json.dumps({"schema_version":"LF_STANDARDS_CATALOG_V1","catalog_version":"0.6.2"}).encode()
sha=hashlib.sha256(payload).hexdigest()
commit="a"*40
base=dict(found=True,status="DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK",source_repo=REPO,source_commit_sha=commit,source_file_sha256=sha,catalog_version="0.6.2",catalog_jsonb_sha256="b"*64,recomputed_jsonb_sha256="b"*64)
def fetch(r,c,p):return AuthenticatedGitRead(r,c,p,payload,True)
cases=[("matching-but-untrusted",base,fetch,"SOURCE_MATCHED_AUTHORITY_NOT_ESTABLISHED"),
("missing",dict(base,found=False),fetch,"MISSING_DB_RELEASE"),
("fork",dict(base,source_repo="fake/repo"),fetch,"WRONG_SOURCE_REPO"),
("short-sha",dict(base,source_commit_sha="a"*7),fetch,"INVALID_EXACT_COMMIT"),
("bad-source-hash",dict(base,source_file_sha256="0"*64),fetch,"FILE_SHA_MISMATCH"),
("jsonb-drift",dict(base,recomputed_jsonb_sha256="c"*64),fetch,"DB_DIGEST_DRIFT"),
("version-drift",dict(base,catalog_version="0.6.3"),fetch,"SOURCE_VERSION_DRIFT"),
("forged-adapter-flag",base,lambda r,c,p:AuthenticatedGitRead(r,c,p,payload,False),"SOURCE_NOT_AUTHENTICATED"),
("wrong-file-path",base,lambda r,c,p:AuthenticatedGitRead(r,c,"untrusted.json",payload,True),"SOURCE_NOT_AUTHENTICATED"),
("offline",base,lambda r,c,p:(_ for _ in ()).throw(ConnectionError()),"SOURCE_FETCH_FAILED")]
for name,record,adapter,reason in cases:
 result=verify_release(record,adapter)
 assert result["verified"] is False and result["decision"]=="BLOCK" and result["reason"]==reason,(name,result)
print(f"PG00_C3_ADVERSARIAL_SOURCE_PASS cases={len(cases)} authorized=0")
