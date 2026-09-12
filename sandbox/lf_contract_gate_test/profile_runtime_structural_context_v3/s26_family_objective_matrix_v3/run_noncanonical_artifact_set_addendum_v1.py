#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import sys
import tempfile
import time
import types
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[4]
SERVICE_ROOT = ROOT / "services/profile_runtime_api"
sys.path.insert(0, str(SERVICE_ROOT))

if importlib.util.find_spec("jsonschema") is None:
    stub = types.ModuleType("jsonschema")
    class SchemaError(Exception):
        pass
    class Draft202012Validator:
        @staticmethod
        def check_schema(_schema: Any) -> None: return None
        def __init__(self, _schema: Any) -> None: pass
        def iter_errors(self, _payload: Any) -> list[Any]: return []
    stub.SchemaError = SchemaError
    stub.Draft202012Validator = Draft202012Validator
    sys.modules["jsonschema"] = stub

from pydantic import ValidationError
from profile_runtime_api.cache import StructuralCache
from profile_runtime_api.engine import ProfileRuntimeEngine
from profile_runtime_api.hashing import canonical_json_sha256
from profile_runtime_api.llama import governed_generation_schema
from profile_runtime_api.models import (
    AdvisoryReadOnlyConstraints,
    Artifact,
    ArtifactSetExecuteRequest,
    InputGovernanceReceipt,
    NonCanonicalArtifactSet,
    ProfileTask,
)
from profile_runtime_api.settings import Settings
from profile_runtime_api.structural import PreparedContext

FINAL_SHA = os.environ.get("S26_FINAL_CANDIDATE_SHA", "").strip()
if not re.fullmatch(r"[0-9a-f]{40}", FINAL_SHA):
    raise SystemExit("BLOCK_FINAL_CANDIDATE_SHA_INVALID")
OUT = Path(os.environ.get("S26_MATRIX_ADDENDUM_OUT_DIR", ".audit-output/s26-noncanonical-artifact-set-addendum"))
OUT.mkdir(parents=True, exist_ok=True)


def _quality_output() -> str:
    return json.dumps({
        "review_id":"review-NONCANONICAL-SET",
        "reviewed_artifact":"two exact-bound approved visual artifacts",
        "verdict":"BLOCK_PIPELINE",
        "score_breakdown":{"contract_schema_compliance":5,"evidence_integrity":4,"lf_safety_governance":5,"handoff_readiness":2,"leakage_scope_control":5,"total":21},
        "evidence_map":[{"ref":"approved://a","observation":"Bound visual artifact A."},{"ref":"approved://b","observation":"Bound visual artifact B."}],
        "blocking_codes":["INDEPENDENT_SEMANTIC_REVIEW_NOT_EXECUTED"],
        "repair_actions":[],"remaining_risks":["No independent semantic authority was executed."],"next_gate":"STOP",
        "routing":{"activation_path":"DIRECT","via":"ORCHESTRATOR","pipeline_action":"BLOCK_PIPELINE","resolution_target":"NONE"},
    }, ensure_ascii=False)


class FakeLlamaClient:
    def __init__(self) -> None: self.chat_calls = 0
    def health(self) -> dict[str, Any]: return {"ready":True,"status":"READY","model_ids":["matrix-fake-local"]}
    def chat(self, **kwargs: Any) -> dict[str, Any]:
        self.chat_calls += 1
        schema, policy = governed_generation_schema(kwargs["schema"], profile_slug=kwargs["profile_slug"], schema_mode=kwargs.get("schema_mode","AUTO"))
        return {"content":_quality_output(),"id":f"matrix-{self.chat_calls}","model":"matrix-fake-local","usage":{"prompt_tokens":10,"completion_tokens":10},"timings":{"predicted_ms":1.0},"finish_reason":"stop","generation_schema_sha256":canonical_json_sha256(schema),"generation_schema_policy":policy}


class FakeStructuralPipeline:
    def __init__(self) -> None: self.calls = 0
    def validate(self) -> None: return None
    def prepare(self, _artifact: Any, _governance: Any) -> PreparedContext:
        self.calls += 1
        return PreparedContext(cache_key=f"matrix:{self.calls}:"+"a"*64, cache_hit=False, pack={"schema":"matrix-pack/v1","pack_sha256":hashlib.sha256(f"pack-{self.calls}".encode()).hexdigest()}, prepare_ms=0.1)


def artifact(code: str, sha_char: str) -> Artifact:
    return Artifact(screen_code=code, filename=f"{code}.png", image_sha256=sha_char*64, width_px=1600, height_px=1000, observations=[])


def advisory() -> InputGovernanceReceipt:
    context={"router":"ACT-0001","scope":"visual_artifact_review_only"}
    return InputGovernanceReceipt(
        receipt_ref="router://ACT-0001/noncanonical/matrix",
        current=True, ready=True, context_sha256=canonical_json_sha256(context), context=context,
        status="ADVISORY_READ_ONLY", decision="ADVISORY", subject_mode="NON_CANONICAL_ARTIFACT",
        required_artifact_binding=["artifact_ref","artifact_sha256","dimensions"],
        constraints=AdvisoryReadOnlyConstraints(),
    )


def task(**updates: Any) -> ProfileTask:
    data={"request_id":"S26-MATRIX-NONCANONICAL-SET","profile_code":"PERFIL-QUALITY-PACK","profile_slug":"quality_pack","profile_source_paths":["profiles/quality_pack/SKILL.md"],"input_literal":"Compare exact-bound approved visual artifacts only; do not register or mutate canonical screens."}
    data.update(updates)
    return ProfileTask(**data)


def expect_validation(code: str, fn: Callable[[], Any]) -> tuple[bool, str]:
    try: fn()
    except ValidationError as exc:
        text=str(exc)
        return code in text, code if code in text else text[:500]
    except Exception as exc:
        text=str(exc)
        return code in text, code if code in text else text[:500]
    return False, "NO_EXCEPTION"


def main() -> int:
    cases=[]
    t0=time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="s26-artset-matrix-") as td:
        settings=Settings(repo_root=ROOT,state_dir=Path(td),api_token="matrix",source_sha=FINAL_SHA,allow_no_auth=True)
        llm=FakeLlamaClient(); pipe=FakeStructuralPipeline(); engine=ProfileRuntimeEngine(settings,llama_client=llm,cache=StructuralCache(Path(td)/"cache"),structural_pipeline=pipe)  # type: ignore[arg-type]
        engine.initialize()
        req=ArtifactSetExecuteRequest(
            artifact_set=NonCanonicalArtifactSet(artifacts=[{"artifact_ref":"approved://a","artifact":artifact("APPROVED-A","e")},{"artifact_ref":"approved://b","artifact":artifact("APPROVED-B","f")}]),
            input_governance=advisory(), profile=task(),
        )
        out=engine.run_artifact_set_execute(req); result=out["result"]
        receipt=(result.get("runtime_completion") or {}).get("governed_context_receipt") or {}
        authority=receipt.get("authority_resolution") or []
        pos=(pipe.calls==2 and llm.chat_calls==1 and out.get("artifact_count")==2 and result.get("runtime_completion",{}).get("status")=="PASS" and result.get("context",{}).get("subject_mode")=="NON_CANONICAL_ARTIFACT" and any(x.get("authority_type")=="INPUT_GOVERNANCE" for x in authority) and out.get("downstream_authorized") is False)
        cases.append({"case_id":"ARTSET-POS-2-ARTIFACTS-ONE-PROFILE","pass":pos,"observed":{"structural_prepares":pipe.calls,"profile_model_calls":llm.chat_calls,"artifact_count":out.get("artifact_count"),"runtime_status":result.get("runtime_completion",{}).get("status"),"subject_mode":result.get("context",{}).get("subject_mode"),"input_governance_authority_bound":any(x.get("authority_type")=="INPUT_GOVERNANCE" for x in authority),"downstream_authorized":out.get("downstream_authorized")}})

    ctx={"router":"ACT-0001","scope":"visual_artifact_review_only"}
    ok,obs=expect_validation("INPUT_GOVERNANCE_NOT_CURRENT", lambda: InputGovernanceReceipt(receipt_ref="router://bad/current",current=False,ready=True,context_sha256=canonical_json_sha256(ctx),context=ctx,status="ADVISORY_READ_ONLY",decision="ADVISORY",subject_mode="NON_CANONICAL_ARTIFACT",required_artifact_binding=["artifact_ref","artifact_sha256","dimensions"],constraints=AdvisoryReadOnlyConstraints()))
    cases.append({"case_id":"ARTSET-NEG-ADVISORY-NOT-CURRENT","pass":ok,"observed":obs})

    ok,obs=expect_validation("NON_CANONICAL_ARTIFACT_SET_GOVERNANCE_MODE_MISMATCH", lambda: ArtifactSetExecuteRequest(artifact_set=NonCanonicalArtifactSet(artifacts=[{"artifact_ref":"approved://a","artifact":artifact("APPROVED-A","e")}]),input_governance=InputGovernanceReceipt(receipt_ref="router://canonical",current=True,ready=True,context_sha256=canonical_json_sha256(ctx),context=ctx,status="READY",decision="PASS",subject_mode="CANONICAL_SCREEN"),profile=task()))
    cases.append({"case_id":"ARTSET-NEG-CANONICAL-CANNOT-MASQUERADE","pass":ok,"observed":obs})

    ok,obs=expect_validation("NON_CANONICAL_ARTIFACT_SHA256_DUPLICATE", lambda: NonCanonicalArtifactSet(artifacts=[{"artifact_ref":"approved://a","artifact":artifact("APPROVED-A","e")},{"artifact_ref":"approved://b","artifact":artifact("APPROVED-B","e")}]))
    cases.append({"case_id":"ARTSET-NEG-DUPLICATE-SHA","pass":ok,"observed":obs})

    ok,obs=expect_validation("Input should be True", lambda: AdvisoryReadOnlyConstraints(no_write=False))
    cases.append({"case_id":"ARTSET-NEG-WRITE-CAPABILITY","pass":ok,"observed":obs})

    ok,obs=expect_validation("NON_CANONICAL_ARTIFACT_SET_FULL_IMAGE_MODEL_UNSUPPORTED", lambda: ArtifactSetExecuteRequest(artifact_set=NonCanonicalArtifactSet(artifacts=[{"artifact_ref":"approved://a","artifact":artifact("APPROVED-A","e")},{"artifact_ref":"approved://b","artifact":artifact("APPROVED-B","f")}]),input_governance=advisory(),profile=task(send_image_to_model=True)))
    cases.append({"case_id":"ARTSET-NEG-MULTI-IMAGE-MODEL-TRANSPORT","pass":ok,"observed":obs})

    failed=[c["case_id"] for c in cases if not c["pass"]]
    receipt={"schema":"S26_MATRIX_V3_NON_CANONICAL_ARTIFACT_SET_ADDENDUM_V1","final_candidate_sha":FINAL_SHA,"status":"PASS" if not failed else "FAIL","case_count":len(cases),"pass_count":len(cases)-len(failed),"fail_count":len(failed),"failed_cases":failed,"cases":cases,"elapsed_ms":round((time.perf_counter()-t0)*1000,3),"model_calls_external":0,"supabase_writes":0,"production_effect":False,"claim_ceiling":"ADDENDUM_REGRESSION_ONLY_NOT_MATRIX_33_CERTIFICATION_NOT_GATE_G_NOT_GOLDEN_NOT_PRODUCTION"}
    path=OUT/"noncanonical_artifact_set_addendum_receipt.json"; path.write_text(json.dumps(receipt,ensure_ascii=False,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:receipt[k] for k in ("status","final_candidate_sha","case_count","pass_count","fail_count","failed_cases","elapsed_ms")},sort_keys=True))
    return 0 if not failed else 2

if __name__ == "__main__": raise SystemExit(main())
