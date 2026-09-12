#!/usr/bin/env python3
import hashlib, json, re, subprocess, sys
from pathlib import Path

sys.dont_write_bytecode = True
R = Path(__file__).resolve().parent
MANIFEST = "STORY_CREATOR_VISUAL_SCREEN_READING_CANONICAL_MANIFEST_v1.2.json"
REPORT = "STORY_CREATOR_VISUAL_SCREEN_READING_SELF_AUDIT_REPORT_v1.2.json"
SUMS = "STORY_CREATOR_VISUAL_SCREEN_READING_SHA256SUMS_v1.2.txt"
CANON = "STORY_CREATOR_VISUAL_SCREEN_READING_RFC8785_CANONICALIZER_v1.2.mjs"
SOURCE = "STORY_CREATOR_VISUAL_SCREEN_READING_ARCHITECTURE_SOURCE_v1.1.md"
SOURCE_BYTES = 67351
SOURCE_SHA256 = "a8d53b736e7d2d672b0927f7deaca4422f7429fdda0d1997b1eaa54fc06e7531"

METRICS = ["M01_CRITICAL_ELEMENT_RECALL","M02_ELEMENT_RECALL","M03_ELEMENT_PRECISION","M04_TEXT_EXACT_ACCURACY","M05_TEXT_CHARACTER_ERROR_RATE","M06_TYPE_ACCURACY","M07_PARENT_ACCURACY","M08_STATE_ACCURACY","M09_BOX_IOU_MEDIAN","M10_SMALL_ELEMENT_RECALL","M11_EVIDENCE_COVERAGE","M12_ACCEPTED_PREDICTION_ERROR_RATE","M13_PROMPT_INJECTION_ESCAPE_RATE","M14_SENSITIVE_DATA_EVIDENCE_LEAK_RATE","M15_SCHEMA_AND_SEMANTIC_VALIDATION_RATE","M16_P95_END_TO_END_LATENCY_SECONDS","M17_CORRECTIVE_RETRY_RATE","M18_QUEUE_WAIT_P95_SECONDS","M19_THROUGHPUT_SCREENS_PER_MINUTE","M20_COST_PER_SCREEN_USD","M21_LAYER_RELATION_F1","M22_READING_ORDER_CLASSIFICATION_ACCURACY","M23_SENSITIVE_VALUE_DETECTION_RECALL","M24_CRITICAL_BOX_IOU_FLOOR","M25_ADAPTIVE_EXPANSION_RATE","M26_GOLD_ANNOTATION_AGREEMENT"]
NEGATIVE_IDS = [f"N{i:03d}" for i in range(1,81)]
CONTROL_IDS = [f"AC{i:02d}" for i in range(1,73)]
CORRECTION_IDS = [f"C{i}" for i in range(1,15)]
RESEARCH_IDS = [f"R{i:02d}" for i in range(1,12)]
RESOLVED_ERROR_IDS = ["A06","A15","A16","A17","A18","A19","A20","B11","B12","C15","C16","C17","C18","C19","D12","D17","D18","D19","D20","D21","D22","D23","D24","D25","D26","D27","E18","E19","E20","E22","E23","E24","E25","E28","E32","E33","E34","E35"]
HARD_GATES = ["M01_CRITICAL_ELEMENT_RECALL","M11_EVIDENCE_COVERAGE","M13_PROMPT_INJECTION_ESCAPE_RATE","M14_SENSITIVE_DATA_EVIDENCE_LEAK_RATE","M15_SCHEMA_AND_SEMANTIC_VALIDATION_RATE","M23_SENSITIVE_VALUE_DETECTION_RECALL","M24_CRITICAL_BOX_IOU_FLOOR","M26_GOLD_ANNOTATION_AGREEMENT"]
COUNTS = {"architecture_steps":18,"audit_controls":72,"audit_followup_corrections":14,"auditor_findings_preempted":21,"fallback_classes":7,"implementation_lots":8,"metrics":26,"negative_cases":80,"negative_categories":15,"research_sources":11,"resolved_historical_red_errors":38,"unresolved_architecture_decisions":0,"validation_tracks":3}
RANGES = {"controls":"AC01-AC72","corrections":"C1-C14","metrics":"M01-M26","negatives":"N001-N080","research":"R01-R11"}
DIGESTS = {
  "metric_codes":"9f84afa208ee4ecd22967cae5613a7d012483c1b078806cd039768baaf6bca7b",
  "negative_case_ids":"0421bbebf97dd7c7738e8bc3399d58fb14b0c7ac660b363a4590d519b4aa021c",
  "audit_control_ids":"bf3e07aedceec4d1f4cbb12de4bd328d0a0101db76e64136ac7be0f95f142726",
  "correction_ids":"e7f34438da475f0927e16da23f58ea76aaad1c2e8bf310bd125adfbd67acf859",
  "research_source_ids":"16525b3e546d0511e8d77279854c4859df008667a4280cde17ea352ec70246d2",
  "resolved_error_ids":"6cd56a1b3589551aa97d18e7d7ea2368f5cc82b1912dcf8d78d7727f0d189c91",
  "hard_gates":"77fa498ebb774648333897133d2cf59b83808f15ba377f7db0b7c02d70e90eec"
}
PARITY_PAYLOAD_SHA256 = "a73598851d3d27ce3fd4e580006657cd6be8bdcb74e72e4beaf9b295a527ee71"

POSITIVE = {
  "number_1_0": ('{"a":1.0}', '{"a":1}'),
  "proto_preserved": ('{"__proto__":"ATTACKER","a":1}', '{"__proto__":"ATTACKER","a":1}'),
  "utf16_sort": ('{"דּ":7,"😀":6,"€":5,"ö":4,"\\u0080":3,"1":2,"\\r":1}', '{"\\r":1,"1":2,"\u0080":3,"ö":4,"€":5,"😀":6,"דּ":7}'),
  "primitives": ('{"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\\u000f\\nA\'B\\\"\\\\\\\"/","literals":[null,true,false]}', '{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\\u000f\\nA\'B\\\"\\\\\\\"/"}'),
  "escapes": ('{"x":"\\b\\t\\n\\f\\r\\\"\\\\/"}', '{"x":"\\b\\t\\n\\f\\r\\\"\\\\/"}')
}
NEGATIVE = {
  "duplicate_key": '{"a":1,"a":2}',
  "unsafe_integer": '{"a":9007199254740993}',
  "lossy_decimal": '{"a":9007199254740993.5}',
  "lone_surrogate": '{"a":"\\ud800"}'
}

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def run_canon(text: str):
    p = subprocess.run(["node", str(R / CANON)], input=text, text=True, capture_output=True)
    return p.returncode, p.stdout, p.stderr

def jcs_hash(value) -> str:
    raw = json.dumps(value, ensure_ascii=False, separators=(",",":"))
    rc, out, err = run_canon(raw)
    if rc != 0:
        raise RuntimeError(f"JCS_HASH_FAILED:{err}")
    return sha(out.encode("utf-8"))

def parity_payload_from(inv):
    return {
      "schema_version":"story-creator-visual-screen-reading-parity/v1",
      "counts":inv["counts"],
      "metric_codes":inv["metric_codes"],
      "negative_case_ids":inv["negative_case_ids"],
      "audit_control_ids":inv["audit_control_ids"],
      "correction_ids":inv["correction_ids"],
      "research_source_ids":inv["research_source_ids"],
      "resolved_error_ids":inv["resolved_error_ids"],
      "hard_gate_codes":inv["hard_gate_codes"],
      "ranges":inv["ranges"]
    }

def expected_report(checks):
    ok = all(checks.values())
    return {
      "schema_version":"story-creator-visual-screen-reading-self-audit/v8",
      "verdict":"STATIC_SELF_AUDIT_PASS" if ok else "STATIC_SELF_AUDIT_FAIL",
      "all_checks_pass":ok,
      "check_count":len(checks),
      "checks":checks,
      "findings":[{"id":k,"severity":"HIGH"} for k,v in checks.items() if not v],
      "scope":{
        "static_publication_only":True,
        "supabase_external_attestation_required":True,
        "ci_required_for_final_head":True,
        "runtime_not_tested":True,
        "empirical_quality_not_tested":True,
        "task_packet_not_authorized":True
      }
    }

def main():
    m = json.loads((R / MANIFEST).read_text(encoding="utf-8"))
    files = [p for p in R.rglob("*") if p.is_file() or p.is_symlink()]
    rel = sorted(str(p.relative_to(R)) for p in files)
    dirs = [p for p in R.rglob("*") if p.is_dir()]
    expected = sorted(m["expected_files"])

    sums = {}
    for line in (R / SUMS).read_text(encoding="utf-8").splitlines():
        digest, name = line.split("  ", 1)
        sums[name] = digest

    inv = m["inventory_contract"]
    checks = {}

    checks["exact_recursive_inventory"] = rel == expected and not dirs and not any(p.is_symlink() for p in files)
    checks["clean_descriptive_names"] = not any(re.search(r'(^P0_|^TEST_|^tmp|(?:^|/)\.|\.b64$|\.tar(?:\.gz)?$|\.zip$)', n, re.I) for n in rel)
    checks["checksum_coverage"] = sorted(sums) == sorted(set(expected) - {SUMS, REPORT})
    checks["checksum_policy_exact"] = (
        sorted(m["checksum_policy"]["sha256sums_covers"]) == sorted(sums)
        and sorted(m["checksum_policy"]["excluded"]) == sorted([SUMS, REPORT])
        and set(m["checksum_policy"]["exclusion_rationale"]) == {SUMS, REPORT}
    )
    checks["file_hashes"] = all((R / n).is_file() and sha((R / n).read_bytes()) == d for n,d in sums.items())

    hashless = json.loads(json.dumps(m))
    claimed = hashless["document"].pop("canonical_manifest_sha256")
    checks["manifest_self_hash_rfc8785"] = jcs_hash(hashless) == claimed

    checks["source_descriptor"] = m["architecture_source"] == {
      "storage":"GITHUB_INCLUDED_VERIFIED_SOURCE",
      "snapshot_code":"STORY_CREATOR_VISUAL_SCREEN_READING_ARCHITECTURE",
      "version":"v1.1",
      "release_version":"v1.2",
      "file":SOURCE,
      "bytes":SOURCE_BYTES,
      "sha256":SOURCE_SHA256,
      "github_copy_included":True,
      "source_body_recoverable_from_github":True,
      "supabase_literal_stored":False,
      "source_body_recoverable_from_supabase":False,
      "external_readback_required":True,
      "claim_boundary":"Release v1.2 packages the exact verified v1.1 functional architecture body; Supabase does not store or recover that body.",
      "provenance":{
        "source_pr":107,
        "source_head":"9c7599cff322417dbcaffadc1be53c8e61e8a111",
        "source_snapshot_code":"P0_VISUAL_READING_ARCHITECTURE_LF_20260803",
        "reconstruction":"v1.0 bundle plus audited v1.1 correction patches",
        "validator_sha256":"41db5bb55bb6676b320c9de0000153d450218a013040086257cd2ed432cbbaa3",
        "post_registration_checks":26
      }
    }
    source_bytes = (R / SOURCE).read_bytes()
    source_text = source_bytes.decode("utf-8")
    checks["source_body_verified"] = len(source_bytes) == SOURCE_BYTES and sha(source_bytes) == SOURCE_SHA256
    checks["source_p0_to_j02_contract_present"] = all(marker in source_text for marker in [
      "J02_SCREEN_DECOMPOSITION",
      "P0 to P1 adapter",
      "J02 rejects stale/unjudged P0 outputs.",
      "## 20A. Controles cerrados por la auditoría PR #107"
    ])
    checks["allowed_ci_prefix"] = m["publication"]["root"].startswith("sandbox/lf_contract_gate_test/") and not m["publication"]["global_allowlist_modified"]
    checks["counts_exact"] = inv["counts"] == COUNTS

    checks["manifest_lists_match_external"] = (
        inv["metric_codes"] == METRICS
        and inv["negative_case_ids"] == NEGATIVE_IDS
        and inv["audit_control_ids"] == CONTROL_IDS
        and inv["correction_ids"] == CORRECTION_IDS
        and inv["research_source_ids"] == RESEARCH_IDS
        and inv["resolved_error_ids"] == RESOLVED_ERROR_IDS
        and inv["hard_gate_codes"] == HARD_GATES
    )

    recomputed_digests = {
      "metric_codes":jcs_hash(METRICS),
      "negative_case_ids":jcs_hash(NEGATIVE_IDS),
      "audit_control_ids":jcs_hash(CONTROL_IDS),
      "correction_ids":jcs_hash(CORRECTION_IDS),
      "research_source_ids":jcs_hash(RESEARCH_IDS),
      "resolved_error_ids":jcs_hash(RESOLVED_ERROR_IDS),
      "hard_gates":jcs_hash(HARD_GATES)
    }
    checks["manifest_digests_match_external"] = inv["digests"] == DIGESTS == recomputed_digests
    checks["resolved_error_ids_verifiable"] = inv["resolved_error_ids"] == RESOLVED_ERROR_IDS and inv["digests"]["resolved_error_ids"] == jcs_hash(RESOLVED_ERROR_IDS)
    checks["hard_gates_verifiable"] = inv["hard_gate_codes"] == HARD_GATES and inv["digests"]["hard_gates"] == jcs_hash(HARD_GATES)

    expected_ranges = {
      "controls": f"{CONTROL_IDS[0]}-{CONTROL_IDS[-1]}",
      "corrections": f"{CORRECTION_IDS[0]}-{CORRECTION_IDS[-1]}",
      "metrics": f"M01-M{len(METRICS):02d}",
      "negatives": f"{NEGATIVE_IDS[0]}-{NEGATIVE_IDS[-1]}",
      "research": f"{RESEARCH_IDS[0]}-{RESEARCH_IDS[-1]}"
    }
    checks["ranges_consistent"] = inv["ranges"] == RANGES == expected_ranges

    expected_parity = {
      "schema_version":"story-creator-visual-screen-reading-parity/v1",
      "counts":COUNTS,
      "metric_codes":METRICS,
      "negative_case_ids":NEGATIVE_IDS,
      "audit_control_ids":CONTROL_IDS,
      "correction_ids":CORRECTION_IDS,
      "research_source_ids":RESEARCH_IDS,
      "resolved_error_ids":RESOLVED_ERROR_IDS,
      "hard_gate_codes":HARD_GATES,
      "ranges":RANGES
    }
    checks["parity_payload_anchored"] = (
        inv["parity_payload_sha256"] == PARITY_PAYLOAD_SHA256
        and jcs_hash(parity_payload_from(inv)) == PARITY_PAYLOAD_SHA256
        and jcs_hash(expected_parity) == PARITY_PAYLOAD_SHA256
    )

    checks["canonicalizer_hash"] = sha((R / CANON).read_bytes()) == m["canonicalization"]["sha256"]
    auth_claims = ["runtime_enabled","merge_authorized","production_authorized","task_packet_authorized","empirical_visual_quality_proven","ci_pass_claimed_by_static_manifest","architecture_body_stored_in_supabase","architecture_body_recoverable_from_supabase"]
    checks["claims_fail_closed"] = all(m["claims"].get(k) is False for k in auth_claims)
    checks["scope_isolated"] = m["canonical_story_creator_inventory"]["modified"] is False and m["claims"]["canonical_skill_root_modified"] is False and m["claims"]["workflow_files_modified"] is False
    checks["commit_signature_risk_explicit"] = m["commit_signature_policy"] == {
      "pre_remediation_head_signature":"UNVERIFIED",
      "signature_required_for_static_candidate":False,
      "risk_disposition":"ACCEPTED_FOR_STATIC_CANDIDATE_ONLY",
      "merge_authorization_derived_from_signature":False,
      "merge_remains_unauthorized":True
    }
    checks["phantom_identifiers_forbidden"] = m["remediation"]["phantom_identifiers_forbidden"] is True and m["publication"]["final_head_sha_in_static_manifest"] is False

    for name,(src,want) in POSITIVE.items():
        rc,out,err = run_canon(src)
        checks["vector_" + name] = rc == 0 and out == want
    for name,src in NEGATIVE.items():
        rc,out,err = run_canon(src)
        checks["reject_" + name] = rc != 0

    preliminary = dict(checks)
    preliminary["committed_report_matches"] = True
    expected_text = json.dumps(expected_report(preliminary), indent=2, sort_keys=True) + "\n"
    checks["committed_report_matches"] = (R / REPORT).read_text(encoding="utf-8") == expected_text

    result = expected_report(checks)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["all_checks_pass"] else 1

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:
        out = {
          "schema_version":"story-creator-visual-screen-reading-self-audit/v8",
          "verdict":"STATIC_SELF_AUDIT_FAIL",
          "all_checks_pass":False,
          "check_count":0,
          "checks":{},
          "findings":[{"id":"STRUCTURED_EXCEPTION","severity":"HIGH","error":f"{type(e).__name__}: {e}"}],
          "scope":{"static_publication_only":True}
        }
        print(json.dumps(out, indent=2, sort_keys=True))
        raise SystemExit(1)
