#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from s26_bundle_certification import BundleError, build_bundle, certify_zip, dump_json, sha256_file, validate_bundle

RUN = "S26-RUN-CERT-001"


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def fixture(
    root: Path,
    validator_body: str | None = None,
    wrong_receipt: bool = False,
    omit: str | None = None,
    validator_argv: list[str] | None = None,
):
    repo = root / "repo"
    artifact = repo / "producer/artifact.json"
    dump_json(artifact, {"screen": "Historial de lotes", "rows": 2})
    artifact_sha = sha256_file(artifact)
    write(repo / "producer/input.txt", "source input\n")
    dump_json(repo / "governance/authority.json", {"schema": "AUTH", "run_id": RUN})
    dump_json(repo / "governance/card_context.json", {"resolution": "GENERIC_SAFE", "run_id": RUN})
    dump_json(repo / "producer/receipt.json", {"schema": "PRODUCER", "artifact_sha256": "0" * 64 if wrong_receipt else artifact_sha})
    dump_json(repo / "producer/evidence.json", {"artifact_ref": "bundle://artifact/artifact.json", "input_ref": f"run://{RUN}/inputs/input.txt"})
    body = validator_body or """#!/usr/bin/env python3
import json,sys
from pathlib import Path
a=json.load(open(sys.argv[1],encoding='utf-8'))
assert a['screen']=='Historial de lotes'
assert Path(sys.argv[2]).read_text(encoding='utf-8').strip()=='source input'
print('VALIDATOR_PASS')
"""
    write(repo / "validators/check.py", body)
    write(repo / "validators/noop.py", "print('NOOP')\n")
    items = [
        {"category": "input", "source": "producer/input.txt", "bundle_path": "inputs/input.txt"},
        {"category": "authority", "source": "governance/authority.json", "bundle_path": "authorities/authority.json"},
        {"category": "cards_context", "source": "governance/card_context.json", "bundle_path": "context/card_context.json"},
        {"category": "evidence", "source": "producer/evidence.json", "bundle_path": "evidence/evidence.json"},
    ]
    if omit:
        items = [x for x in items if x["category"] != omit]
    validators = [] if omit == "validator" else [{
        "source": "validators/check.py",
        "bundle_path": "validators/check.py",
        "argv": validator_argv or ["python3", "validators/check.py", "artifact/artifact.json", "inputs/input.txt"],
    }]
    receipts = [] if omit == "receipt" else [{
        "source": "producer/receipt.json",
        "bundle_path": "receipts/producer.json",
        "artifact_sha256_field": "artifact_sha256",
    }]
    spec = {
        "schema": "S26_REVIEW_BUNDLE_SPEC_V1",
        "run_id": RUN,
        "run_metadata": {"run_id": RUN, "base_sha": "a" * 40, "branch": "lf/s26-c-cert", "head_sha": "b" * 40},
        "artifact": {"source": "producer/artifact.json", "bundle_path": "artifact/artifact.json"},
        "items": items,
        "receipts": receipts,
        "validators": validators,
    }
    dump_json(repo / "bundle_spec.json", spec)
    return repo, repo / "bundle_spec.json"


def rehash_manifest(bundle: Path):
    man = json.loads((bundle / "bundle_manifest.json").read_text(encoding="utf-8"))
    for item in man["files"]:
        p = bundle / item["path"]
        if p.is_file():
            item["bytes"] = p.stat().st_size
            item["sha256"] = sha256_file(p)
    dump_json(bundle / "bundle_manifest.json", man)


def expect_error(name: str, fn, prefix: str):
    try:
        result = fn()
    except BundleError as exc:
        errors = [str(exc)]
    else:
        errors = result if isinstance(result, list) else result.get("errors", [])
    assert any(e.startswith(prefix) for e in errors), (name, prefix, errors)
    print("PASS", name, prefix)


with tempfile.TemporaryDirectory(prefix="s26_bundle_tests_") as td:
    root = Path(td)

    repo, spec = fixture(root / "positive")
    out = root / "positive/bundle"; zip_path = root / "positive/bundle.zip"
    build_bundle(spec, repo, out, zip_path)
    receipt = certify_zip(zip_path)
    assert receipt["status"] == "PASS", receipt
    assert receipt["manifest_reconciled"] and receipt["hashes_verified"] and receipt["fresh_unpack_pass"] and receipt["replay_pass"]
    print("PASS positive_fresh_unpack_replay")

    repo, spec = fixture(root / "missing")
    (repo / "producer/input.txt").unlink()
    expect_error("input_missing_at_build", lambda: build_bundle(spec, repo, root / "missing/bundle"), "SOURCE_MISSING")

    repo, spec = fixture(root / "authority", omit="authority")
    expect_error("authority_required", lambda: build_bundle(spec, repo, root / "authority/bundle"), "REQUIRED_CATEGORY_MISSING:authority")

    repo, spec = fixture(root / "validator", omit="validator")
    expect_error("validator_required", lambda: build_bundle(spec, repo, root / "validator/bundle"), "REQUIRED_CATEGORY_MISSING")

    repo, spec = fixture(root / "receiptbad", wrong_receipt=True)
    expect_error("receipt_same_artifact", lambda: build_bundle(spec, repo, root / "receiptbad/bundle"), "RECEIPT_ARTIFACT_MISMATCH")

    repo, spec = fixture(root / "argv_mismatch", validator_argv=["python3", "validators/noop.py"])
    expect_error("validator_argv_binding", lambda: build_bundle(spec, repo, root / "argv_mismatch/bundle"), "VALIDATOR_ARGV_MISMATCH")

    repo, spec = fixture(root / "tamper")
    out = root / "tamper/bundle"; build_bundle(spec, repo, out)
    write(out / "inputs/input.txt", "tampered\n")
    expect_error("sha_tamper", lambda: validate_bundle(out), "MANIFEST_SHA_MISMATCH")

    repo, spec = fixture(root / "extra")
    out = root / "extra/bundle"; build_bundle(spec, repo, out)
    write(out / "extra.txt", "x")
    expect_error("unlisted_file", lambda: validate_bundle(out), "MANIFEST_SET_MISMATCH")

    repo, spec = fixture(root / "absent")
    out = root / "absent/bundle"; build_bundle(spec, repo, out)
    (out / "inputs/input.txt").unlink()
    expect_error("listed_file_absent", lambda: validate_bundle(out), "MANIFEST_FILE_MISSING")

    repo, spec = fixture(root / "crossrun")
    out = root / "crossrun/bundle"; build_bundle(spec, repo, out)
    dump_json(out / "evidence/evidence.json", {"bad": "run://S26-RUN-OTHER/inputs/input.txt"})
    rehash_manifest(out)
    expect_error("cross_run_reference", lambda: validate_bundle(out), "CROSS_RUN_REF")

    repo, spec = fixture(root / "external")
    out = root / "external/bundle"; build_bundle(spec, repo, out)
    dump_json(out / "evidence/evidence.json", {"bad": "github://example/repo@" + "c"*40 + "/missing.json"})
    rehash_manifest(out)
    expect_error("external_reference_unmapped", lambda: validate_bundle(out), "EXTERNAL_REF_UNMAPPED")

    repo, spec = fixture(root / "manifestgap")
    out = root / "manifestgap/bundle"; build_bundle(spec, repo, out)
    man = json.loads((out / "bundle_manifest.json").read_text(encoding="utf-8"))
    man["files"] = [x for x in man["files"] if x["path"] != "evidence/evidence.json"]
    man["file_count"] = len(man["files"])
    dump_json(out / "bundle_manifest.json", man)
    expect_error("manifest_incomplete", lambda: validate_bundle(out), "MANIFEST_SET_MISMATCH")

    bad_validator = """#!/usr/bin/env python3
from pathlib import Path
assert Path('../producer/secret.txt').read_text() == 'secret'
"""
    repo, spec = fixture(root / "localdep", validator_body=bad_validator)
    write(repo.parent / "producer/secret.txt", "secret")
    out = root / "localdep/bundle"; zip_path = root / "localdep/bundle.zip"
    build_bundle(spec, repo, out, zip_path)
    receipt = certify_zip(zip_path)
    assert receipt["fresh_unpack_pass"] is True, receipt
    assert receipt["replay_pass"] is False, receipt
    assert any(e.startswith("REPLAY_FAILED") for e in receipt["errors"]), receipt
    print("PASS local_working_tree_dependency_blocked")

print("S26_BUNDLE_CERTIFICATION_TESTS_PASS=12_NEGATIVE_PLUS_1_POSITIVE")
