from pathlib import Path
sql=Path(__file__).with_name("pg00_c3_catalog_release_candidate_v1.sql").read_text()
assert "SECURITY INVOKER" in sql
assert "catalog_jsonb_sha_matches_jsonb" in sql
assert "catalog_release_version_matches" in sql
assert "source_commit_sha ~ '^[0-9a-f]{40}$'" in sql
assert "PG00_C3_RELEASE_NOT_FOUND" in sql
assert "DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK" in sql
assert "source_file_sha256" in sql and "catalog_jsonb_sha256" in sql
assert "ROLLBACK;" in sql
assert "GRANT " not in "\n".join(l for l in sql.splitlines() if not l.lstrip().startswith("--"))
assert "SECURITY DEFINER" not in sql
print("PG00_C3_RELEASE_SQL_STATIC_PASS no_grants no_authority no_apply")
