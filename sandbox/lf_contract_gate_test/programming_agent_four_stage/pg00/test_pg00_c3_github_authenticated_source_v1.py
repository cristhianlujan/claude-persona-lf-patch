import base64,hashlib,json
from pg00_c3_github_authenticated_source_v1 import read_git_source_exact,check_db_against_git,SourceError,REPO,PATH
raw=json.dumps({"schema_version":"LF_STANDARDS_CATALOG_V1","catalog_version":"0.6.2"}).encode()
blob=hashlib.sha1(b"blob "+str(len(raw)).encode()+bytes([0])+raw).hexdigest()
obj={"type":"file","path":PATH,"encoding":"base64","content":base64.b64encode(raw).decode(),"sha":blob}
class Response:
 def __init__(self,value):self.value=value
 def __enter__(self):return self
 def __exit__(self,*_):return False
 def read(self):return json.dumps(self.value).encode()
def opener(request,timeout):return Response(obj)
commit="a"*40
source=read_git_source_exact(commit,"test-placeholder",opener)
assert source.sha256==hashlib.sha256(raw).hexdigest()
assert source.catalog_version=="0.6.2"
row={"found":True,"source_repo":REPO,"source_commit_sha":commit,"source_file_sha256":source.sha256,"catalog_version":"0.6.2","catalog_jsonb_sha256":"b"*64,"recomputed_jsonb_sha256":"b"*64}
assert check_db_against_git(row,source)["reason"]=="SOURCE_MATCHED_TRAIN_BINDING_REQUIRED"
assert check_db_against_git(dict(row,source_file_sha256="0"*64),source)["decision"]=="BLOCK"
assert check_db_against_git(dict(row,recomputed_jsonb_sha256="c"*64),source)["reason"]=="DB_JSONB_DIGEST_DRIFT"
try:read_git_source_exact("abc","test-placeholder",opener);raise AssertionError()
except SourceError as e:assert str(e)=="INVALID_EXACT_COMMIT"
try:read_git_source_exact(commit,"",opener);raise AssertionError()
except SourceError as e:assert str(e)=="NO_GITHUB_CREDENTIAL"
def broken(_req,_timeout):return Response(dict(obj,sha="0"*40))
try:read_git_source_exact(commit,"test-placeholder",broken);raise AssertionError()
except SourceError as e:assert str(e)=="GITHUB_BLOB_SHA_MISMATCH"
print("PG00_C3_GITHUB_EXACT_SOURCE_PASS cases=6 authorized=0")
