import hashlib,json,copy
from pg00_c3_source_verify_candidate_v1 import verify_release,AuthenticatedGitRead,REPO,PATH
source=json.dumps({"schema_version":"LF_STANDARDS_CATALOG_V1","catalog_version":"0.6.2"}).encode()
sha=hashlib.sha256(source).hexdigest()
commit="a"*40
db={"found":True,"status":"DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK",
"source_repo":REPO,"source_commit_sha":commit,"source_file_sha256":sha,
"catalog_jsonb_sha256":"b"*64,"recomputed_jsonb_sha256":"b"*64,"catalog_version":"0.6.2"}
def fetch(repo,head,path):return AuthenticatedGitRead(repo,head,path,source,True)
def check(row,fn,reason):
 out=verify_release(row,fn)
 assert out["decision"]=="BLOCK" and out["verified"] is False and out["reason"]==reason,out
check(db,fetch,"SOURCE_MATCHED_AUTHORITY_NOT_ESTABLISHED")
for key,val,reason in [
("found",False,"MISSING_DB_RELEASE"),
("source_repo","untrusted/fork","WRONG_SOURCE_REPO"),
("source_commit_sha","abc","INVALID_EXACT_COMMIT"),
("source_file_sha256","0"*64,"FILE_SHA_MISMATCH"),
("recomputed_jsonb_sha256","c"*64,"DB_DIGEST_DRIFT"),
("catalog_version","9.0.0","SOURCE_VERSION_DRIFT")]:
 row=dict(db);row[key]=val;check(row,fetch,reason)
check(db,lambda *args:AuthenticatedGitRead(REPO,commit,PATH,source,False),"SOURCE_NOT_AUTHENTICATED")
check(db,lambda *args:AuthenticatedGitRead(REPO,commit,"other.json",source,True),"SOURCE_NOT_AUTHENTICATED")
check(db,lambda *args:(_ for _ in ()).throw(IOError("offline")),"SOURCE_FETCH_FAILED")
print("PG00_C3_SOURCE_VERIFY_NEGATIVES_PASS checks=10 positive_authority=0")
