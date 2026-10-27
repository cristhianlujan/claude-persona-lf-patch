"""Build an explicit synthetic SQL composition from pinned candidate Git objects.

No database connection, deployment or operational receipt. Run the generated
SQL only in a disposable PostgreSQL database. Requires the candidate Git objects
to be present locally; never fetches sources or reads DB credentials.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

WRITER_REF = "87e0f8736415da5fa1fdf75d60edff73e44b55ca"
RETURN_REF = "1adb33144e26bbc18013db72bb4637ee3c42cd9f"
RETURN_FILES = [
 "20261025004001_lf_profile_result_router_return_v1.sql",
 "20261025014719_lf_srcr_return_router_after_repair_v1.sql",
 "20261026180000_lf_profile_result_positive_continue_router_return_v1.sql",
 "20261026180500_lf_profile_positive_continuation_router_return_v1.sql",
 "20261027090000_lf_programming_analysis_return_to_development_v1.sql",
]
GATE_SHA256 = "c25f55b8234c2ae6b3c36926b6c36ea94051b21e80ce5cbfb982ed1b2721f77a"
BOUNDARY = "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/"
MIGRATIONS = [
    "20261026173901_lf_programming_context_handoff_receipt_ledger_v1.sql",
    "20261027091000_lf_programming_admission_envelope_v2_resolver_v1.sql",
    "20261027120000_lf_programming_receipt_runtime_writer_v1.sql",
]
GATE = "20261026230000_lf_programming_development_admission_gate_v1.sql"


def git_bytes(root: Path, path: str, ref: str = WRITER_REF) -> bytes:
    return subprocess.run(["git", "-C", str(root), "show", ref + ":" + path],
        check=True, capture_output=True).stdout


def build(repo_root: Path, gate_root: Path, output: Path) -> dict:
    gate = (gate_root / "supabase/migrations" / GATE).read_bytes()
    if hashlib.sha256(gate).hexdigest() != GATE_SHA256:
        raise ValueError("COMPOSITION_GATE_SOURCE_DRIFT")
    fixture = git_bytes(repo_root, BOUNDARY + "test_pg01_receipt_runtime_writer_v1.sql").decode()
    marker = "DO $$ DECLARE r jsonb; BEGIN\n r:=private.fn_lf_programming_context_handoff_receive_v1("
    if fixture.count(marker) != 1:
        raise ValueError("COMPOSITION_FIXTURE_ANCHOR_DRIFT")
    prefix = fixture[:fixture.index(marker)]
    extra = Path(__file__).with_name("test_pg01_candidate_composition_v1.sql").read_text()
    artifacts = {("supabase/migrations/" + name): git_bytes(repo_root, "supabase/migrations/" + name)
                 for name in MIGRATIONS}
    artifacts["supabase/migrations/" + GATE] = gate
    # Load the actual gate inside the same rollback-owned test transaction.
    load_gate = """
CREATE TABLE public.lf_router_action_registry(
 asset_type text,action_code text,operation_code text,status text,write_allowed boolean);
INSERT INTO public.lf_router_action_registry VALUES(
 'REPOSITORY_ARTIFACT','CODE_DEVELOPMENT','DESARROLLO_CODIGO_AGENTE_LF',
 'CANDIDATO_READ_ONLY',false);
GRANT USAGE ON SCHEMA private,extensions TO service_role,supabase_read_only_user;
GRANT SELECT ON public.lf_operation_execution,public.lf_router_action_registry
 TO service_role,supabase_read_only_user;
TRUNCATE src_lines;
\\copy src_lines(line) FROM 'supabase/migrations/""" + GATE + """' WITH (FORMAT csv, DELIMITER E'\\x01', QUOTE E'\\x02', ESCAPE E'\\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\\n' ORDER BY n),E'BEGIN;\\n',''),E'\\nCOMMIT;','') FROM src_lines
\\gexec
"""
    return_test = git_bytes(repo_root, BOUNDARY + "test_programming_analysis_return_to_development_v1.sql", RETURN_REF).decode()
    start = return_test.index("-- Test-only stub: the terminal authority receipt")
    end = return_test.index("CREATE TEMP TABLE test_results")
    return_setup = return_test[start:end].replace(
        "CREATE TEMP TABLE src_lines(n bigint GENERATED ALWAYS AS IDENTITY, line text);",
        "TRUNCATE src_lines;")
    # The terminal-authority receipt is an explicitly synthetic fixture, not attestation.
    for name in RETURN_FILES:
        artifacts["supabase/migrations/" + name] = git_bytes(repo_root, "supabase/migrations/" + name, RETURN_REF)
    artifacts["composition.sql"] = (prefix + load_gate + return_setup + extra + "\nROLLBACK;\n").encode()
    manifest = {
        "schema_version": "PG01_LOCAL_COMPOSITION_SOURCES_V1",
        "writer_source_ref": WRITER_REF,
        "return_source_ref": RETURN_REF,
        "terminal_authority_receipt": "EXPLICIT_TEST_STUB_NOT_OPERATIONAL",
        "gate_sha256": GATE_SHA256,
        "evidence_tier": "LOCAL_REAL_SQL_SYNTHETIC_CATALOG_PROFILE_JUDGE",
        "hosted_database_touched": False,
        "operational_admission": False,
        "files": {path: hashlib.sha256(data).hexdigest() for path, data in artifacts.items()},
    }
    output.mkdir(parents=True, exist_ok=False)
    for path, data in artifacts.items():
        target = output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    (output / "sources.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo-root", type=Path, required=True)
    p.add_argument("--gate-root", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    print(json.dumps(build(a.repo_root, a.gate_root, a.output), indent=2))
