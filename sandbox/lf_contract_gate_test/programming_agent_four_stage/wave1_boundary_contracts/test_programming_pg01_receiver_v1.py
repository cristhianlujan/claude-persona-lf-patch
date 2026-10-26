"""Emitter integration cases; invoked inside the local SQL foundation runner.

Uses real candidate SQL guard/resolve/validation and canonical currentness
evaluation. Currentness provider/catalog are synthetic, not operational proofs.
"""
from copy import deepcopy
from dataclasses import replace
from datetime import datetime, timedelta
import json
import subprocess

from programming_pg01_receiver_v1 import (
    CanonicalCurrentnessPort, ExpectedHandoff, ReadOnlyReceiver, SqlReadPort,
)
from lf_currentness_authority_v1 import compatibility_proof_sha256
from lf_material_currentness_v1 import canonical_sha256


def exercise_receiver(*, context, sql, query, check, repo, router_v2_exercise=None):
    calls = []
    counter = 0
    rev = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()

    def lit(value):
        return "'" + json.dumps(value).replace("'", "''") + "'::jsonb"

    def read_query(statement, params):
        # This test adapter escapes parameters for psql; production adapters must
        # bind them through their driver. It always runs under READ ONLY.
        calls.append((statement, params))
        for value in params:
            statement = statement.replace("%s", "'" + value.replace("'", "''") + "'", 1)
        return json.loads(sql("BEGIN READ ONLY;\n" + statement + ";\nROLLBACK;"))

    def persisted(candidate, case):
        nonlocal counter
        counter += 1
        candidate = deepcopy(candidate)
        candidate["decision_ref"] = "fixture://receiver/decision/" + str(counter)
        candidate["subject"]["ref"] = "fixture://receiver/subject/" + str(counter)
        # Generic canonical record allows pre-validation historical shapes. This
        # is solely a local fixture for legacy invalid recorded snapshots.
        got = query("public.fn_lf_decision_context_asof_record_v1(" + lit(candidate) + ",'LOCAL-EMITTER-TEST')")
        check(case + "_fixture_recorded", got.get("state"), "RECORDED")
        snap = candidate["extensions"]["programming_context_snapshot"]
        expected = ExpectedHandoff(got["context_id"], got["context_sha256"], snap.get("snapshot_schema_digest_sha256", "0"*64), candidate["consumer_code"], candidate["subject"]["ref"], "2026-10-02T00:00:00Z")
        return candidate, expected

    def receiver(candidate, *, change=None, classification=None, packet_mutate=None, read=read_query):
        snap = candidate["extensions"]["programming_context_snapshot"]

        def provider(expected, scope_id):
            fps = {"context": expected.context_sha256, "snapshot_schema": expected.snapshot_schema_digest_sha256,
                   "snapshot_authority": snap["authority_fingerprint_sha256"], "snapshot_source": snap["source_snapshot_sha256"]}
            materials = [{"material_id": name, "kind": "DIGEST", "bound_digest": fp,
                          "current_digest": ("0"*64 if name == change else fp), "depends_on": []} for name, fp in fps.items()]
            binding = {"schema_version":"LF_MATERIAL_CURRENTNESS_BINDING_V1", "authority":{"ref":"fixture://main","bound_revision":rev,"current_revision":rev},
                       "evidence_revision":rev,"dependency_completeness":"COMPLETE","require_ancestor":True,
                       "contract_identity":"PROGRAMMING_CONTEXT_SNAPSHOT_V1:" + expected.snapshot_schema_digest_sha256,
                       "implementation_binding":"PG-01:" + scope_id,"materials":materials,"root_material_ids":list(fps),"compatibility_contract":{"assessments":[]}}
            if change and classification:
                binding["compatibility_contract"]["assessments"] = [{"material_id":change,"change_class":classification,"proof_sha256":compatibility_proof_sha256(material_id=change,change_class=classification,bound_fingerprint=fps[change],current_fingerprint="0"*64,contract_identity=binding["contract_identity"],implementation_binding=binding["implementation_binding"])}]
            packet = {"context_id":expected.context_id,"context_sha256":expected.context_sha256,"scope_id":scope_id,"binding":binding}
            if packet_mutate:
                packet_mutate(packet)
            return packet
        return ReadOnlyReceiver(SqlReadPort(read), CanonicalCurrentnessPort(repo, provider))

    good, handoff = persisted(context, "positive")
    subject = receiver(good)
    accepted = subject.consume(handoff, "S1")
    check("emitter_positive_boundary", accepted["state"], "ACCEPT")
    check("emitter_never_execution_permission", accepted["execution_allowed"], False)
    check("emitter_remaining_gates_explicit", accepted["pending_gates"], ["PG-01_C4","PG-01_C7","PG-01_C6_PERSISTENCE"])
    check("emitter_admitted_exact_scope", accepted["admitted_scope_ids"], ["S1"])
    required = {"context_id","context_sha256","snapshot_schema_digest_sha256","receiver_schema_digest_sha256","material_projection_sha256","validated_material_paths","verdict"}
    check("emitter_exact_seven_business_fields", sorted(set(accepted["receipt"]) - {"schema_version"}), sorted(required))
    check("emitter_projection_digest_recomputed", accepted["receipt"]["material_projection_sha256"], canonical_sha256(accepted["material_projection"]))
    check("emitter_producer_receiver_parity", accepted["receipt"]["receiver_schema_digest_sha256"], handoff.snapshot_schema_digest_sha256)
    check("emitter_repeat_entire_result_identical", subject.consume(handoff,"S1"), accepted)
    check("emitter_accepts_identical_proposed_projection", subject.consume(handoff,"S1",proposed_projection=deepcopy(accepted["material_projection"]))["state"], "ACCEPT")

    # N1 and N2 are synthetic counterparts; no historical provenance claimed.
    bad = deepcopy(context)
    for field in ("material_front_coverage","implementability_schema","decision_context","analysis_stop_rule","scope_front_matrix","source_refs"):
        bad["extensions"]["programming_context_snapshot"].pop(field)
    bad, h = persisted(bad, "N1_six_missing")
    check("N1_synthetic_six_missing_BLOCK", receiver(bad).consume(h,"S1")["state"], "BLOCK")
    bad = deepcopy(context); bad["extensions"]["programming_context_snapshot"]["scope_front_matrix"] = []
    bad, h = persisted(bad,"N2_empty_matrix")
    check("N2_synthetic_empty_matrix_BLOCK", receiver(bad).consume(h,"S1")["state"], "BLOCK")

    bad = deepcopy(context); snap=bad["extensions"]["programming_context_snapshot"]
    snap["scope_readiness"][0]["status"]="NOT_APPLICABLE"; snap["package_readiness"]="NEED_MORE_EVIDENCE"
    bad,h=persisted(bad,"N3_zero_READY")
    blocked=receiver(bad).consume(h,"S1")
    check("N3_zero_READY_code", blocked["code"], "NO_READY_SCOPE")
    check("N3_identifiable_BLOCK_receipt", blocked["receipt"]["verdict"], "BLOCK")
    before=len(calls)
    check("N4_missing_handoff", subject.consume(None,"S1")["code"], "EXPECTED_HANDOFF_INVALID_OR_MISSING")
    check("N4_malformed_expected_hash", subject.consume(replace(handoff,context_sha256=""),"S1")["state"], "BLOCK")
    check("N4_no_query_without_expected_receipt", len(calls), before)

    blocked=receiver(good,change="snapshot_source",classification="BREAKING").consume(handoff,"S1")
    check("N5_stale_BLOCK", blocked["state"], "BLOCK")
    check("N5_canonical_engine_STALE", blocked["currentness"]["decision"], "STALE_AFFECTED")
    blocked=receiver(good,packet_mutate=lambda p:p["binding"].update(dependency_completeness="UNKNOWN")).consume(handoff,"S1")
    check("N5_unknown_fails_closed", blocked["currentness"]["decision"], "UNKNOWN_FAIL_CLOSED")
    blocked=receiver(good,change="snapshot_source").consume(handoff,"S1")
    check("N5_missing_compatibility_evidence", blocked["state"], "BLOCK")
    rebound_base=subprocess.check_output(["git","-C",str(repo),"rev-parse","HEAD^"],text=True).strip()
    def unrelated_main_change(packet):
        packet["binding"]["authority"]["bound_revision"]=rebound_base
        packet["binding"]["evidence_revision"]=rebound_base
    rebound=receiver(good,packet_mutate=unrelated_main_change).consume(handoff,"S1")
    check("unrelated_git_revision_drift_does_not_stale",rebound["state"],"ACCEPT")
    check("canonical_currentness_rebound",rebound["currentness"]["decision"],"CURRENT_REBOUND" if rebound_base!=rev else "CURRENT")
    bounded=receiver(good,change="snapshot_source",classification="CONTRACT_COMPATIBLE").consume(handoff,"S1")
    check("bounded_validation_not_silently_bypassed",bounded["code"],"BOUNDED_VALIDATION_REQUIRED")

    bad=deepcopy(context);bad["actor_authority"]["authority_sha256"]="b"*64
    bad,h=persisted(bad,"N6_authority_payload")
    check("N6_modified_context_vs_original_receipt", receiver(bad).consume(replace(h,context_sha256=handoff.context_sha256),"S1")["code"], "EXACT_RECEIPT_MISMATCH")
    blocked=receiver(good,change="snapshot_authority",classification="IMPLEMENTATION_ONLY_COMPATIBLE").consume(handoff,"S1")
    check("N6_authority_requires_rebuild_even_if_compatible", blocked["currentness"]["reason"], "SNAPSHOT_REBUILD_REQUIRED:snapshot_authority")
    check("N7_unknown_requested_scope", subject.consume(handoff,"OTHER")["code"], "REQUESTED_SCOPE_NOT_READY_OR_UNKNOWN")

    partial=deepcopy(context);snap=partial["extensions"]["programming_context_snapshot"];snap["package_readiness"]="PARTIAL_READY"
    s2=deepcopy(snap["scope_readiness"][0]);s2.update(scope_id="S2",status="BLOCKED",material_front_refs=["F2"],blockers=["OWNER_PENDING"]);snap["scope_readiness"].append(s2)
    f2=deepcopy(snap["material_front_coverage"]["material_fronts"][0]);f2.update(front_id="F2",scope_refs=["S2"],closure="BLOCKED",evidence_refs=[],blockers=[{"blocker_code":"OWNER_PENDING","blocker_class":"OWNER_DECISION_REQUIRED","reason":"fixture","evidence_refs":[]}]);snap["material_front_coverage"]["material_fronts"].append(f2)
    snap["material_front_coverage"]["front_candidate_refs"].append("F2")
    m2=deepcopy(snap["scope_front_matrix"][0]);m2.update(scope_id="S2",front_id="F2",front_closure="BLOCKED",effect_on_scope="BLOCKS");snap["scope_front_matrix"].append(m2)
    partial,h=persisted(partial,"partial")
    check("partial_READY_accepts_S1_only",receiver(partial).consume(h,"S1")["admitted_scope_ids"],["S1"])
    check("N7_partial_READY_never_substitutes_blocked_S2",receiver(partial).consume(h,"S2")["code"],"REQUESTED_SCOPE_NOT_READY_OR_UNKNOWN")

    lossy=deepcopy(accepted["material_projection"]);lossy["snapshot"].pop("requirements")
    blocked=subject.consume(handoff,"S1",proposed_projection=lossy)
    check("N8_lossy_projection_BLOCK",blocked["code"],"MATERIAL_PROJECTION_LOSS_OR_MISMATCH")
    check("N8_BLOCK_receipt_hashes_retained_full_projection",blocked["receipt"]["material_projection_sha256"],canonical_sha256(blocked["material_projection"]))
    check("N8_expected_id_mismatch",subject.consume(replace(handoff,context_id="00000000-0000-0000-0000-000000000000"),"S1")["code"],"EXACT_RECEIPT_MISMATCH")
    check("schema_digest_mismatch",subject.consume(replace(handoff,snapshot_schema_digest_sha256="0"*64),"S1")["code"],"HANDOFF_SCHEMA_DIGEST_MISMATCH")
    bad=deepcopy(context);bad["extensions"]["programming_context_snapshot"]["snapshot_schema_digest_sha256"]="0"*64
    bad,h=persisted(bad,"schema_inner_drift")
    check("producer_schema_drift",receiver(bad).consume(replace(h,snapshot_schema_digest_sha256=handoff.snapshot_schema_digest_sha256),"S1")["code"],"PRODUCER_RECEIVER_SCHEMA_DIGEST_MISMATCH")
    bad=deepcopy(context);bad["extensions"]["programming_context_snapshot"]["unknown_material_obligation"]="must not drop"
    bad,h=persisted(bad,"unknown_material")
    check("unknown_material_field_BLOCK",receiver(bad).consume(h,"S1")["code"],"SNAPSHOT_MATERIAL_FIELDS_MISSING_OR_UNKNOWN")
    blocked=receiver(good,packet_mutate=lambda p:p.update(scope_id="OTHER")).consume(handoff,"S1")
    check("currentness_scope_replay_BLOCK",blocked["currentness"]["reason"],"CURRENTNESS_SUBJECT_MISMATCH")
    blocked=receiver(good,packet_mutate=lambda p:p["binding"].update(root_material_ids=["snapshot_source"])).consume(handoff,"S1")
    check("currentness_hiding_material_roots_BLOCK",blocked["currentness"]["reason"],"CURRENTNESS_ROOTS_INCOMPLETE")
    def unavailable(*args):
        raise RuntimeError("fixture only")
    blocked=receiver(good,read=unavailable).consume(handoff,"S1")
    check("read_port_unavailable_BLOCK",blocked["code"],"READ_PORT_UNAVAILABLE")
    check("early_failure_does_not_fabricate_receipt",blocked["receipt"],None)
    check("no_new_writes_from_repeat_consume",query("(SELECT count(*) FROM private.lf_decision_context_asof_v1 WHERE decision_ref='"+good["decision_ref"]+"')"),1)
    from test_programming_pg01_preplanning_receiver_v1 import exercise_preplanning
    preplanning_evidence = exercise_preplanning(context=context, persisted=persisted, boundary_factory=receiver, check=check)
    router_evidence = None
    if router_v2_exercise is not None:
        router_evidence = router_v2_exercise(context=context, sql=sql, query=query, check=check,
                                             repo=repo, persisted=persisted, receiver=receiver)
    return {"router_v2_compatibility": router_evidence, "eight_families":"SYNTHETIC_LOCAL_BOUNDARY_CASES_EXECUTED", "historical_snapshots_executed":False,
            "sample_accept_receipt":accepted["receipt"],"read_calls":len(calls),"source_preplanning":preplanning_evidence,"operational_currentness_provider_verified":False,
            "c4_implemented":False,"c7_implemented":False,"handoff_receipt_persisted":False}


def exercise_historical(*, rows, sql, query, check, repo):
    """Replay exact RO-exported historical inputs only inside disposable PG.

    The export is external to git; only ids/hashes/results enter evidence.
    No rewriting, sanitization or historical admission claim is performed.
    """
    results=[]
    for row in rows:
        context=row["context_payload"]
        lit=lambda value: "'"+json.dumps(value).replace("'","''")+"'::jsonb"
        txt=lambda value: "'"+value.replace("'","''")+"'"
        digest=query("encode(extensions.digest(convert_to(("+lit(context)+")::text,'UTF8'),'sha256'),'hex')")
        check("historical_hash_"+row["context_id"],digest,row["context_sha256"])
        sql("INSERT INTO private.lf_decision_context_asof_v1(context_id,decision_ref,consumer_code,subject_ref,subject_version,decided_at,effective_at,context_payload,context_sha256,created_by_execution_id) VALUES ("+
            ",".join([txt(row["context_id"]),txt(context["decision_ref"]),txt(context["consumer_code"]),txt(context["subject"]["ref"]),txt(context["subject"]["version"]),txt(context["times"]["decided_at"]),txt(context["times"]["effective_at"]),lit(context),txt(digest),txt("LOCAL-HISTORICAL-NEGATIVE-REPLAY")])+");")
        def read(statement,params):
            for value in params: statement=statement.replace("%s",txt(value),1)
            return json.loads(sql("BEGIN READ ONLY;\n"+statement+";\nROLLBACK;"))
        def no_currentness(*args):
            raise AssertionError("Historical invalid payload must stop before currentness")
        receiver=ReadOnlyReceiver(SqlReadPort(read),CanonicalCurrentnessPort(repo,no_currentness))
        decided_at=row["decided_at"]+(":00" if row["decided_at"].endswith("+00") else "")
        expected=ExpectedHandoff(row["context_id"],digest,receiver.contract_digest,context["consumer_code"],context["subject"]["ref"],(datetime.fromisoformat(decided_at)+timedelta(seconds=1)).isoformat())
        scopes=context["extensions"]["programming_context_snapshot"].get("scope_readiness") or []
        scope=next((s.get("scope_id") for s in scopes if isinstance(s,dict) and s.get("scope_id")),"HISTORICAL_REQUESTED_SCOPE")
        validation=query("programacion.fn_programming_context_snapshot_validate_v1("+lit(context)+")")
        got=receiver.consume(expected,scope)
        check("historical_rejected_"+row["context_id"],got["state"],"BLOCK")
        check("historical_invalid_snapshot_"+row["context_id"],validation["state"],"BLOCKED")
        results.append({"context_id":row["context_id"],"context_sha256":digest,"decided_at":row["decided_at"],"validation_code":validation.get("code"),"receiver_code":got["code"],"verdict":got["state"],"evidence_tier":"EXACT_HISTORICAL_INPUT_REPLAY_IN_LOCAL_PG"})
    return results
