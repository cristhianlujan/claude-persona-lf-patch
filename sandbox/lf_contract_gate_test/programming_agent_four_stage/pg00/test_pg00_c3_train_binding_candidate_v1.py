from pg00_c3_train_binding_candidate_v1 import bind_c3_train
p="supabase/migrations/20261030120000_lf_std_catalog_release_v1.sql"
execution="EXEC-DB-TRAIN-PR999-20261030120000-R123"
db={"catalog_version":"0.6.2","source_commit_sha":"a"*40,"source_file_sha256":"b"*64,"source_repo":"paulozterra/lf-programming-sandbox","train_execution_ref":execution}
source={k:db[k] for k in ("catalog_version","source_commit_sha","source_file_sha256")}
manifest={**source,"schema_version":"PG00_C3_SOURCE_RELEASE_MANIFEST_V1","source_repo":db["source_repo"],"source_path":"standards/catalog.json","migration_path":p,"migration_source_sha256":"c"*64,"train_merge_sha":"d"*40}
train={"result":"PASS"}
snapshot={"event":{"payload":{"receipt":{"schema_version":"LF_MIGRATION_TRAIN_RECEIPT_V1","repository":"cristhianlujan/claude-persona-lf-patch","execution_id":execution,"migration":{"path":p,"version":"20261030120000","source_sha256":"c"*64},"merge":{"merge_commit_sha":"d"*40}}}}}
def reason(d=db,s=source,t=train,ss=snapshot,m=manifest):return bind_c3_train(d,s,t,ss,m)["reason"]
assert reason()=="EXACT_CONTENT_ATTESTATION_AND_DB_AUTHORITY_REQUIRED"
assert reason(t={"result":"BLOCKED"})=="TRAIN_NOT_PASS"
assert reason(d={**db,"train_execution_ref":"other"})=="TRAIN_EXECUTION_MISMATCH"
assert reason(m={**manifest,"source_file_sha256":"0"*64})=="MANIFEST_DB_MISMATCH"
assert reason(s={**source,"catalog_version":"0.0.0"})=="MANIFEST_SOURCE_MISMATCH"
assert reason(m={**manifest,"migration_source_sha256":"0"*64})=="MIGRATION_CONTENT_MISMATCH"
assert reason(m={**manifest,"train_merge_sha":"0"*40})=="TRAIN_MERGE_MISMATCH"
assert reason(m={**manifest,"migration_path":"supabase/migrations/20261030120001_lf_std_catalog_release_v1.sql"})=="MIGRATION_CONTENT_MISMATCH"
assert reason(ss={"event":{"payload":{"receipt":{**snapshot["event"]["payload"]["receipt"],"repository":"other/repo"}}}})=="WRONG_TRAIN_REPO"
assert reason(ss={"event":{"payload":{"receipt":{**snapshot["event"]["payload"]["receipt"],"migration":{"path":"supabase/migrations/20261030120000_lf_other.sql"}}}}})=="NOT_C3_MIGRATION"
print("PG00_C3_EXACT_TRAIN_BINDING_PASS scenarios=10 authorized=0")
