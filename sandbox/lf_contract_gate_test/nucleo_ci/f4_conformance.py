"""F4 conformance of declared implementation versions, exact Git HEAD + disposable PG17.
No declaration is manufactured for LF/SALY; no source code execution or runtime write.
"""
import hashlib
import json
import pathlib
import re
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = "sdk/lf_nucleo_implementation_claims.v1.json"
SCHEMA = "LF_NUCLEO_IMPLEMENTATION_CLAIMS_V1"
HASH = re.compile(r"[0-9a-f]{64}")
FIELDS = {"instancia", "nodo", "regla", "version", "version_hash", "source_path", "source_sha256"}
ALLOW = {"AL_DIA", "EN_PLAZO", "AL_DIA_SIN_IMPACTO"}

def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("F4_DUPLICATE_JSON_KEY")
        result[key] = value
    return result

def claims(raw):
    obj = json.loads(raw, object_pairs_hook=no_duplicate_keys)
    if not isinstance(obj, dict) or set(obj) != {"schema_version", "claims"} or obj["schema_version"] != SCHEMA or not isinstance(obj["claims"], list):
        raise ValueError("F4_MANIFEST_INVALID")
    seen = set()
    for c in obj["claims"]:
        if not isinstance(c, dict) or set(c) != FIELDS:
            raise ValueError("F4_CLAIM_INVALID")
        if c["instancia"] not in ("lf_ops", "saly") or type(c["version"]) is not int or not 0 < c["version"] <= 2147483647:
            raise ValueError("F4_IDENTITY_INVALID")
        for key in ("nodo", "regla", "source_path"):
            if not isinstance(c[key], str) or not c[key].strip():
                raise ValueError("F4_IDENTITY_INVALID")
        for key in ("version_hash", "source_sha256"):
            if not isinstance(c[key], str) or not HASH.fullmatch(c[key]):
                raise ValueError("F4_HASH_INVALID")
        path = pathlib.PurePosixPath(c["source_path"])
        if (path.is_absolute() or str(path) != c["source_path"] or ".." in path.parts or "\\" in str(path)
                or path.parts[0] in ("sandbox", "docs", ".github") or path.suffix not in (".ts",".tsx",".js",".mjs",".py",".sql",".go",".rs",".java",".kt",".swift",".cs",".rb",".php")):
            raise ValueError("F4_SOURCE_PATH_INVALID")
        key = (c["instancia"], c["nodo"], c["regla"], c["source_path"])
        if key in seen:
            raise ValueError("F4_DUPLICATE_CLAIM")
        seen.add(key)
    return obj["claims"]

def git_blob(root, commit, path):
    spec = commit + ":" + path
    # Do not follow symlinks, submodules, or checkout changes. Only a Git blob in exact commit.
    meta = subprocess.check_output(["git","ls-tree",commit,"--",path],cwd=root,text=True).strip()
    if not meta.startswith(("100644 blob ", "100755 blob ")) or meta.split("\t",1)[-1] != path:
        raise ValueError("F4_SOURCE_NOT_TRACKED_REGULAR_FILE: " + path)
    return subprocess.check_output(["git","show",spec],cwd=root)

def verify_bytes(items, read):
    for c in items:
        if hashlib.sha256(read(c["source_path"])).hexdigest() != c["source_sha256"]:
            raise ValueError("F4_SOURCE_HASH_DRIFT: " + c["source_path"])

def needed(root, base, head, paths):
    # Future claims/changes to any declared source activate the existing PG17 PASE step.
    # Removing a previous claim is not silently certified by an empty manifest.
    if MANIFEST in paths:
        return True
    for sha in (base, head):
        try:
            raw = subprocess.check_output(["git","show",sha+":"+MANIFEST],cwd=root,stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            continue
        if any(c["source_path"] in paths for c in claims(raw)):
            return True
    return False

def read_claims(root, base, head):
    current = claims(git_blob(root, head, MANIFEST))
    try:
        old_raw = subprocess.check_output(["git","show",base+":"+MANIFEST],cwd=root,stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        old = []
    else:
        old = claims(old_raw)
    key = lambda c: (c["instancia"],c["nodo"],c["regla"],c["source_path"])
    if {key(x) for x in old} - {key(x) for x in current}:
        raise ValueError("F4_CLAIM_REMOVAL_REQUIRES_SEPARATE_AUTHORITY")
    verify_bytes(current, lambda p: git_blob(root,head,p))
    return current

def literal(data):
    return "'" + data.replace("'","''") + "'"

def evaluate(rows):
    if not isinstance(rows,list):
        raise ValueError("F4_RESULT_INVALID")
    errors = [r for r in rows if r.get("estado") not in ALLOW]
    if errors:
        raise ValueError("F4_CONFORMIDAD_REJECTED "+json.dumps(errors,ensure_ascii=False,sort_keys=True))
    return rows

def source_selftest():
    raw = b"export const fixture = 1;\n"
    c = dict(instancia="lf_ops",nodo="ZZT-MOD-1",regla="ZZT-F4-CONFORM",version=1,version_hash="a"*64,
             source_path="services/test-only-fixture.ts",source_sha256=hashlib.sha256(raw).hexdigest())
    parse = lambda rows: claims(json.dumps({"schema_version":SCHEMA,"claims":rows}))
    verify_bytes(parse([c]),lambda p:raw)
    for fn, expected in [
        (lambda:verify_bytes([c],lambda p:raw+b"mutation"),"F4_SOURCE_HASH_DRIFT"),
        (lambda:parse([c,c]),"F4_DUPLICATE_CLAIM"),
        (lambda:parse([dict(c,source_path="../outside.ts")]),"F4_SOURCE_PATH_INVALID"),
        (lambda:parse([dict(c,version=True)]),"F4_IDENTITY_INVALID"),
        (lambda:evaluate([{"estado":"DESFASADO"}]),"F4_CONFORMIDAD_REJECTED"),
        (lambda:evaluate([{"estado":"VERSION_NO_PUBLICADA"}]),"F4_CONFORMIDAD_REJECTED"),
    ]:
        try:
            fn()
        except ValueError as err:
            if expected not in str(err):
                raise
        else:
            raise RuntimeError("F4_NEGATIVE_NOT_DETECTED "+expected)
    evaluate([{"estado":"AL_DIA"},{"estado":"EN_PLAZO"},{"estado":"AL_DIA_SIN_IMPACTO"}])
    print("F4_SOURCE_SELFTEST_PASS 8/8",flush=True)

def run(container,root,base,head,psql):
    source_selftest()
    ddl = (HERE/"f4_conformance_pg17.sql").read_text()
    fixture = (HERE/"f4_conformance_cases_pg17.sql").read_text()
    for schema, other in (("lf_ops","saly"),("saly","lf_ops")):
        sql = "BEGIN;\n"+ddl+"\n"+fixture.replace("@SCHEMA@",schema).replace("@OTHER@",other)+"\nROLLBACK;\n"
        r = psql(container,sql,check=False)
        print(r.stdout+r.stderr,flush=True)
        if r.returncode or r.stderr.count("F4_CONFORM_PASS "+schema+" ")!=10:
            raise RuntimeError("F4_PG17_CONFORMANCE_TEST_FAILED "+schema)
        restored = psql(container,"SELECT count(*) FROM "+schema+".nucleo_reglas WHERE codigo='ZZT-F4-CONFORM';").stdout.strip()
        if restored!="0":
            raise RuntimeError("F4_FIXTURE_ROLLBACK_FAILED "+schema)
        print("F4_CONFORM_ROLLBACK_PASS "+schema+" 10/10",flush=True)
    items = read_claims(root,base,head)
    payload = literal(json.dumps(items,ensure_ascii=False))
    r = psql(container,"BEGIN;\n"+ddl+"\nSELECT pg_temp.f4_conformance_v1("+payload+"::jsonb,now());\nROLLBACK;")
    rows = [line for line in r.stdout.splitlines() if line.strip().startswith("[")]
    if len(rows)!=1:
        raise RuntimeError("F4_RESULT_MISSING")
    observed=json.loads(rows[0])
    if len(observed)!=len(items) or [r.get("idx") for r in observed]!=list(range(1,len(items)+1)):
        raise RuntimeError("F4_RESULT_CARDINALITY")
    evaluate(observed)
    if not items:
        print("F4_CLAIMS_NOT_APPLICABLE_EMPTY (no runtime conformance certified)",flush=True)
    else:
        print("F4_CLAIMS_VERIFIED "+json.dumps(observed,ensure_ascii=False,sort_keys=True),flush=True)
    print("F4_CONFORMANCE_CI_PASS 20/20 PG17 plus 8/8 source checks",flush=True)
