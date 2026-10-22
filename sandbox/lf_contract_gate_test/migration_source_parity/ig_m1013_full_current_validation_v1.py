#!/usr/bin/env python3
"""IG M10.13 only: full-current material proof over the canonical parity core.
Known historical exceptions are exact, frozen, independently verified identities.
No effect on PASE changeset-scoped checks; no SQL writes or schema migrations.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import migration_source_parity_core as core
import migration_transport_normalization as transport

REGISTRY_GIT_BLOB = "be3804d0c6b6b62f1c0f3924e08e9b07cc1c4f52"
DUPLICATES = {
 "20261011000425": ("20261011033000", "2fa9e47880eddd96"),
 "20261011000445": ("20261011034000", "f6034c24ddd47770"),
 "20261011000451": ("20261011035000", "fa746e2cb3793376"),
 "20261011075708": ("20261011052000", "3742dd2e1757b147"),
 "20261011081610": ("20261011081500", "38696672846f1bb1"),
 "20261011085515": ("20261011085000", "01713b51e968b5e5"),
 "20261011223638": ("20261011155000", "98e691a7c09d3017"),
 "20261011223646": ("20261011155001", "2a97e5e5b6db3e23"),
 "20261011223729": ("20261011155002", "c9083e20ea7f94f7"),
 "20261011233708": ("20261011194000", "4f56e1c4dc554b5b"),
 "20261011233711": ("20261011194100", "d3c1a924281a2d6f"),
 "20261011235413": ("20261011211000", "dc2d38030259fa3c"),
}
LOCAL_ONLY = {
 "20261006110403": ("engineering_unit_stop_scope_v1", "582cbcac07b623c4bf0687ff934b6972c393abf1"),
 "20261006152000": ("engineering_contract_corrections_privacy_m45", "62576939c13e951fbf11fda7b0bb05e587709836"),
 "20261012120000": ("ig_m100_ekb_signed_release_snapshot_learnings", "032468a44ed74dde4ef79a0b7edbbe3df4f0100d"),
}
POINTERS = {
 "20261009172500": "2d3aba11a1e85c50bef0c07354267dbf7f0d9a72",
 "20261009175500": "397ffd615b5c052c80bfda313b8fb4170ed39aec",
 "20261009183000": "e1533e0b47a81be2b3902c1f0f6069ab0bcac988",
 "20261011190000": "985cb6bf91b15f5522d218f4b94b0ef3fc3d0186",
}
POINTER_RE = re.compile(
 r"^github://cristhianlujan/claude-persona-lf-patch@([0-9a-f]{40})/"
 r"supabase/migrations/([0-9]{14}_[a-z0-9_]+\.sql)#blob=([0-9a-f]{40})$"
)

class FullParityError(ValueError):
    pass

def check(condition: bool, code: str, detail: str = "") -> None:
    if not condition:
        raise FullParityError(code + (":" + detail if detail else ""))

def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, text=True, capture_output=True,
                          check=True, timeout=120).stdout.strip()

def read_csv(path: Path, width: int) -> list[list[str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows=list(csv.reader(handle))
    check(all(len(row)==width for row in rows), "FAIL_IG_M1013_CSV_WIDTH")
    return rows

def check_inventory(local: dict, remote: dict, counts: dict, registry_text: str, registry_blob: str) -> None:
    check(registry_blob == REGISTRY_GIT_BLOB, "FAIL_IG_M1013_REGISTRY_BLOB")
    only_g=set(local)-set(remote); only_d=set(remote)-set(local)
    check(only_g==set(LOCAL_ONLY) and only_d==set(DUPLICATES),
          "FAIL_IG_M1013_UNREGISTERED_DRIFT",
          "git="+str(sorted(only_g))+" db="+str(sorted(only_d)))
    check(set(counts)==set(remote), "FAIL_IG_M1013_STATEMENT_COVERAGE")
    for version,(name,blob) in LOCAL_ONLY.items():
        check(local[version][0]==name and local[version][2]==blob,
              "FAIL_IG_M1013_GIT_ONLY_SOURCE",version)
        check(version+"_"+name in registry_text,
              "FAIL_IG_M1013_GIT_ONLY_UNDOCUMENTED",version)
    for duplicate,(original,sha16) in DUPLICATES.items():
        check(original in remote and original in local,
              "FAIL_IG_M1013_ORIGINAL_MISSING",duplicate)
        check(remote[duplicate][0]==original+"_"+remote[original][0],
              "FAIL_IG_M1013_DUPLICATE_NAME",duplicate)
        # Snapshot returns CANONICAL SQL hashes (comments stripped), while
        # sha16 from the immutable registry pins RAW stored SQL bytes. Do not
        # compare one representation against the other; raw is checked below.
        check(remote[duplicate][1]==remote[original][1] and
              re.fullmatch(r"sha256:[0-9a-f]{64}",remote[duplicate][1]) is not None and
              counts[duplicate]==counts[original],
              "FAIL_IG_M1013_DUPLICATE_SQL",duplicate)
        check(duplicate in registry_text, "FAIL_IG_M1013_DUPLICATE_UNDOCUMENTED",duplicate)

def check_raw_duplicates(raw: dict[str, tuple[str, int]]) -> None:
    """Prove exact raw stored statement bytes against the pinned ledger digest.

    The snapshot strips comment lines for transport matching. The known-drift
    registry records SHA-256 over original stored SQL; both are independently
    required before accepting any historical duplicate.
    """
    expected=set(DUPLICATES)|{original for original,_ in DUPLICATES.values()}
    check(set(raw)==expected,"FAIL_IG_M1013_DUPLICATE_RAW_COVERAGE")
    for duplicate,(original,sha16) in DUPLICATES.items():
        dupe_digest,dupe_count=raw[duplicate]
        orig_digest,orig_count=raw[original]
        check(re.fullmatch(r"[0-9a-f]{64}",dupe_digest) is not None and
              dupe_digest==orig_digest and dupe_digest.startswith(sha16) and
              dupe_count==orig_count and dupe_count>0,
              "FAIL_IG_M1013_DUPLICATE_RAW_SQL",duplicate)


def evaluate(*, data_root: Path, inputs: dict, full, pg_env: dict, psql, output_dir: Path) -> dict:
    registry_path=data_root/"docs/reconcile/KNOWN_DRIFT_REGISTRY.md"
    check(registry_path.is_file(),"FAIL_IG_M1013_REGISTRY_MISSING")
    registry=registry_path.read_text(encoding="utf-8")
    registry_blob=git(data_root,"hash-object",str(registry_path))
    local={}
    migrations=data_root/"supabase/migrations"
    adapter=full._load_parity_adapter()
    for file in sorted(migrations.glob("*.sql")):
        marker=adapter.FILENAME_RE.fullmatch(file.name)
        if marker is None or marker.group(1)<=full.CLASSIFICATION_BASELINE_END:
            continue
        version,name=marker.groups()
        check(version not in local,"FAIL_IG_M1013_GIT_DUPLICATE_VERSION",version)
        local[version]=(name,file,git(data_root,"hash-object",str(file)))
    remote={}
    for version,name,sha in read_csv(inputs["post_cutover"],3):
        check(re.fullmatch(r"[0-9]{14}",version) is not None and version not in remote,
              "FAIL_IG_M1013_LEDGER_INVALID",version)
        remote[version]=(name,sha)
    counts={}
    for version,count in read_csv(inputs["statement_counts"],2):
        check(version in remote and version not in counts and count.isdigit() and int(count)>0,
              "FAIL_IG_M1013_COUNT_INVALID",version)
        counts[version]=int(count)
    check_inventory(local,remote,counts,registry,registry_blob)

    # Independent raw-SQL attestation. The snapshot returns normalized hashes,
    # so recover EXACT historical raw stored bytes via a read-only SQL digest.
    duplicate_versions=sorted(set(DUPLICATES)|
                              {original for original,_ in DUPLICATES.values()})
    array_literal="{"+",".join(duplicate_versions)+"}"
    # Built-in pg_catalog.sha256 is accessible to lf_reconcile_readonly.
    # extensions.digest has EXECUTE privilege but schema extensions lacks USAGE.
    raw_sql=("select version,"
             "encode(pg_catalog.sha256(convert_to("
             "coalesce(array_to_string(statements,chr(10)),''),'UTF8')),"
             "'hex'),"
             "coalesce(cardinality(statements),0)::text "
             "from supabase_migrations.schema_migrations "
             "where version=any('"+array_literal+"'::text[]) order by version")
    raw={}
    for version,digest,count in read_csv_stream(psql(raw_sql,env=pg_env),3):
        check(version in duplicate_versions and version not in raw and
              count.isdigit(),"FAIL_IG_M1013_DUPLICATE_RAW_ROW",version)
        raw[version]=(digest,int(count))
    check_raw_duplicates(raw)
    for version,(_digest,statement_count) in raw.items():
        check(statement_count==counts[version],
              "FAIL_IG_M1013_DUPLICATE_RAW_CARDINALITY",version)

    # Four historical representation pointers must bind to current Git blob
    # AND the source blob at the immutable historical commit recorded by the ledger.
    pointer_versions=sorted(POINTERS)
    array_literal="{"+",".join(pointer_versions)+"}"
    sql=("select version,name,cardinality(statements)::text,"
         "coalesce(array_to_string(statements,chr(10)),'') "
         "from supabase_migrations.schema_migrations "
         "where version=any('"+array_literal+"'::text[]) order by version")
    live_pointers=read_csv_stream(psql(sql,env=pg_env),4)
    check(len(live_pointers)==len(POINTERS),"FAIL_IG_M1013_POINTER_COUNT")
    observed={}
    for version,name,num,pointer in live_pointers:
        check(version in POINTERS and version not in observed,"FAIL_IG_M1013_POINTER_UNEXPECTED",version)
        observed[version]=1
        check(version in local and version in remote and
              name==local[version][0] and name==remote[version][0] and num=="1" and counts[version]==1,
              "FAIL_IG_M1013_POINTER_IDENTITY",version)
        match=POINTER_RE.fullmatch(pointer)
        check(match is not None,"FAIL_IG_M1013_POINTER_FORMAT",version)
        commit,path,blob=match.groups()
        check(path==version+"_"+name+".sql" and blob==POINTERS[version] and
              local[version][2]==blob and
              git(data_root,"rev-parse",commit+":supabase/migrations/"+path)==blob,
              "FAIL_IG_M1013_POINTER_BLOB",version)
        check(version+"_"+name in registry,"FAIL_IG_M1013_POINTER_UNDOCUMENTED",version)
    check(set(observed)==set(POINTERS),"FAIL_IG_M1013_POINTER_MISSING")

    # Exact version, name, SQL and statement count for every other shared migration.
    shared=sorted((set(local)&set(remote))-set(POINTERS))
    locals_for_core={}
    for version in shared:
        sql_text=local[version][1].read_text(encoding="utf-8")
        locals_for_core[version]=(local[version][0],
                    hashlib.sha256(transport.canonical(sql_text)).hexdigest(),sql_text)
    remotes_for_core={v:(remote[v][0],adapter.remote_content_sha256(remote[v][1],v)) for v in shared}
    verdict=core.evaluate_exact_parity(locals_for_core,remotes_for_core,
                                      {v:counts[v] for v in shared})
    check(verdict.status=="PASS" and verdict.version_count==len(shared),
          "FAIL_IG_M1013_CORE_INCOMPLETE")

    # Canonical frozen baselines, not redefined by the IG-specific exception list.
    grandfather=read_csv(inputs["grandfathered"],2)
    legacy=read_csv(inputs["legacy"],2)
    check(len(grandfather)==1 and
          grandfather[0]==[full.GRANDFATHERED_COUNT,full.GRANDFATHERED_SHA256],
          "FAIL_IG_M1013_GRANDFATHERED_ATTESTATION")
    markers=[]
    for file in migrations.glob("*.sql"):
        with file.open(encoding="utf-8") as handle:
            mark=adapter.MARKER_RE.fullmatch(handle.readline().rstrip("\r\n"))
        if mark: markers.append(mark.groups())
    check(len(markers)==1 and markers[0][0]==full.CUTOVER and
          legacy==[[markers[0][3],markers[0][4]]],
          "FAIL_IG_M1013_LEGACY_ATTESTATION")
    proof={"schema_version":"ig-m1013-full-current-proof/v1",
           "status":"PASS","scope":"FULL_CURRENT_STATE",
           "source_versions":len(local),"ledger_versions":len(remote),
           "shared_versions":len(set(local)&set(remote)),
           "canonical_compared":verdict.version_count,
           "pointer_matches":len(POINTERS),
           "documented_exceptions":len(DUPLICATES)+len(LOCAL_ONLY),
           "ledger_duplicates_hash_and_count_equal":len(DUPLICATES),
           "raw_ledger_duplicates_verified":len(DUPLICATES),
           "raw_vs_snapshot_hash_representation":"INDEPENDENT",
           "registry_blob":registry_blob,
           "unregistered_drift_count":0,
           "grandfathered":"MATCH","legacy":"MATCH",
           "production_activated":False}
    (output_dir/"full-current-proof.json").write_text(
        json.dumps(proof,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    return proof

def read_csv_stream(payload: str, width: int) -> list[list[str]]:
    rows=list(csv.reader(io.StringIO(payload)))
    check(all(len(r)==width for r in rows),"FAIL_IG_M1013_POINTER_CSV_WIDTH")
    return rows
