"""C3 exact Train binding: verifies release record and Train evidence refer to SAME migration.

Input is an already independently verified Train report and a read-only Train
snapshot. Never authorizes from caller JSON: return is always a candidate gate.
"""
import re
SHA40=re.compile(r"^[0-9a-f]{40}$")
SHA64=re.compile(r"^[0-9a-f]{64}$")
MIGRATION=re.compile(r"^([0-9]{14})_([a-z0-9_]*lf_[a-z0-9_]*std_catalog[a-z0-9_]*).sql$")
REPO="cristhianlujan/claude-persona-lf-patch"
SOURCE_REPO="paulozterra/lf-programming-sandbox"
SOURCE_PATH="standards/catalog.json"

def bind_c3_train(db,source,train_report,snapshot,release_manifest):
    def block(reason):return {"verified":False,"decision":"BLOCK","reason":reason}
    if not all(isinstance(x,dict) for x in (db,source,train_report,snapshot,release_manifest)):
        return block("EVIDENCE_MISSING")
    if train_report.get("result")!="PASS":return block("TRAIN_NOT_PASS")
    receipt=((snapshot.get("event") or {}).get("payload") or {}).get("receipt") or {}
    mig=receipt.get("migration") or {}
    if receipt.get("schema_version")!="LF_MIGRATION_TRAIN_RECEIPT_V1":
        return block("TRAIN_RECEIPT_SCHEMA")
    path=mig.get("path","")
    match=MIGRATION.fullmatch(path.rsplit("/",1)[-1]) if isinstance(path,str) else None
    if not match or not path.startswith("supabase/migrations/"):
        return block("NOT_C3_MIGRATION")
    if mig.get("version")!=match.group(1):return block("MIGRATION_VERSION_MISMATCH")
    if receipt.get("repository")!=REPO:return block("WRONG_TRAIN_REPO")
    if release_manifest.get("schema_version")!="PG00_C3_SOURCE_RELEASE_MANIFEST_V1":
        return block("RELEASE_MANIFEST_SCHEMA")
    fields=("catalog_version","source_commit_sha","source_file_sha256")
    if any(release_manifest.get(k)!=db.get(k) for k in fields):
        return block("MANIFEST_DB_MISMATCH")
    if any(release_manifest.get(k)!=source.get(k) for k in fields):
        return block("MANIFEST_SOURCE_MISMATCH")
    if db.get("source_repo")!=SOURCE_REPO or release_manifest.get("source_repo")!=SOURCE_REPO:
        return block("WRONG_CATALOG_REPO")
    if release_manifest.get("source_path")!=SOURCE_PATH:return block("WRONG_SOURCE_PATH")
    if not SHA40.fullmatch(str(db.get("source_commit_sha",""))) or not SHA64.fullmatch(str(db.get("source_file_sha256",""))):
        return block("INVALID_DIGEST_OR_COMMIT")
    if db.get("train_execution_ref")!=receipt.get("execution_id"):
        return block("TRAIN_EXECUTION_MISMATCH")
    if release_manifest.get("migration_path")!=path or release_manifest.get("migration_source_sha256")!=mig.get("source_sha256"):
        return block("MIGRATION_CONTENT_MISMATCH")
    if release_manifest.get("train_merge_sha")!=((receipt.get("merge") or {}).get("merge_commit_sha")):
        return block("TRAIN_MERGE_MISMATCH")
    # Caller/fixture fields alone cannot prove the manifest was embedded in the
    # exact migration byte stream or that the DB record was read via trusted SQL.
    return block("EXACT_CONTENT_ATTESTATION_AND_DB_AUTHORITY_REQUIRED")
