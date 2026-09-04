from __future__ import annotations

import time
from typing import Any

from .cache import StructuralCache
from .hashing import canonical_json_sha256
from .llama import (
    LlamaHTTPClient,
    LlamaTransportError,
    PersistentLlamaServerAdapter,
    PersistentLlamaServerVerifier,
)
from .models import BatchRequest, ExecuteRequest, ProfileTask, QueueExecuteRequest
from .repository import RepositoryBindings
from .settings import Settings
from .structural import PreparedContext, StructuralContextPipeline
from .validation import OutputGates

RESULT_SCHEMA = "lf-profile-runtime-api-result/v1"


def _failure(exc: BaseException) -> tuple[str, str | None]:
    current: BaseException | None = exc
    seen: set[int] = set()
    fallback = type(exc).__name__.upper()
    selected: tuple[str, str | None] | None = None
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        code = getattr(current, "code", None)
        if isinstance(code, str) and code:
            detail = getattr(current, "detail", None)
            selected = (code, str(detail)[:500] if detail else None)
        current = current.__cause__ or current.__context__
    return selected or (fallback, None)


def _not_evaluated(code: str) -> dict[str, Any]:
    return {"status": "NOT_EVALUATED", "blocking_codes": [code], "downstream_authorized": False}


def _governed_context(task: ProfileTask, prepared_pack: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    cards = [item.model_dump(mode="python") for item in task.lf_card_sources]
    adapters = [item.model_dump(mode="python") for item in task.lf_adapter_sources]
    card_receipts = [
        {"card_ref": item["card_ref"], "card_version": item["card_version"], "source_ref": item["source_ref"],
         "content_sha256": item["content_sha256"], "selected_sections": item["selected_sections"],
         "budget_chars": item["budget_chars"], "request_id": task.request_id}
        for item in cards
    ]
    adapter_receipts = [
        {"adapter_code": item["adapter_code"], "adapter_version": item["adapter_version"],
         "target_ref": item["target_ref"], "binding_ref": item["binding_ref"],
         "assurance_revision": item["assurance_revision"], "request_id": task.request_id}
        for item in adapters
    ]
    pack = dict(prepared_pack)
    pack["lf_cards"] = [{k: v for k, v in item.items() if k != "content"} | {"content": item["content"]} for item in cards]
    pack["lf_card_receipts"] = card_receipts
    pack["lf_adapter_receipts"] = adapter_receipts
    receipt = {
        "schema": "lf-governed-context-receipt/v1",
        "request_id": task.request_id,
        "profile_code": task.profile_code,
        "card_receipts": card_receipts,
        "adapter_receipts": adapter_receipts,
    }
    receipt["context_fingerprint"] = canonical_json_sha256({"request_id": task.request_id, "cards": card_receipts, "adapters": adapter_receipts, "structural_pack_sha256": prepared_pack.get("pack_sha256")})
    return pack, receipt


class ProfileRuntimeEngine:
    def __init__(self, settings: Settings, *, llama_client: LlamaHTTPClient | None = None, cache: StructuralCache | None = None, structural_pipeline: StructuralContextPipeline | None = None) -> None:
        self.settings = settings
        self.repository = RepositoryBindings(settings.repo_root, max_prompt_chars=settings.max_prompt_chars)
        self.cache = cache or StructuralCache(settings.state_dir / "structural-cache", max_entries=settings.cache_max_entries)
        self.structural = structural_pipeline or StructuralContextPipeline(settings, self.cache)
        self.llama_client = llama_client or LlamaHTTPClient(settings)
        self.gates = OutputGates(self.repository)
        self.runner: Any = None

    def initialize(self) -> None:
        self.settings.validate(); self.repository.validate(); self.structural.validate(); self.cache.initialize(); self.runner = self.repository.load_runtime_runner()

    def run_execute(self, request: ExecuteRequest) -> dict[str, Any]:
        started = time.perf_counter()
        try:
            prepared = self.structural.prepare(request.artifact, request.input_governance)
        except Exception as exc:
            code, detail = _failure(exc); result = self._profile_failure(task=request.profile, code=code, detail=detail, stage="STRUCTURAL_CONTEXT", started=started)
        else:
            result = self._execute_profile(task=request.profile, artifact=request.artifact, prepared=prepared, context_reused_within_batch=False)
        return {"schema": RESULT_SCHEMA, "kind": "execute", "request_id": request.profile.request_id, "artifact_sha256": request.artifact.image_sha256, "result": result, "total_ms": round((time.perf_counter()-started)*1000,3), "downstream_authorized": False}

    def run_queue_execute(self, request: QueueExecuteRequest) -> dict[str, Any]:
        started=time.perf_counter(); task=request.profile
        context_pack={"schema":"lf-profile-runtime-queue-context/v1","source":"QUEUE_NATIVE_TEXT_PROFILE","screen_governance_applicable":False,"downstream_authorized":False}
        result=self._execute_queue_profile(task=task,context_pack=context_pack)
        return {"schema":RESULT_SCHEMA,"kind":"queue_execute","request_id":task.request_id,"artifact_sha256":None,"result":result,"total_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

    def run_batch(self, request: BatchRequest) -> dict[str, Any]:
        started=time.perf_counter()
        if len(request.profiles)>self.settings.max_batch_size:
            failures=[self._profile_failure(task=t,code="BATCH_SIZE_EXCEEDS_RUNTIME_LIMIT",detail=None,stage="INPUT_GOVERNANCE",started=started) for t in request.profiles]
            return self._batch_result(request,failures,started,context=None)
        try: prepared=self.structural.prepare(request.artifact,request.input_governance)
        except Exception as exc:
            code,detail=_failure(exc); failures=[self._profile_failure(task=t,code=code,detail=detail,stage="STRUCTURAL_CONTEXT",started=started) for t in request.profiles]; return self._batch_result(request,failures,started,context=None)
        results=[self._execute_profile(task=t,artifact=request.artifact,prepared=prepared,context_reused_within_batch=i>0) for i,t in enumerate(request.profiles)]
        return self._batch_result(request,results,started,context=prepared)

    def runtime_snapshot(self) -> dict[str, Any]:
        llama=self.llama_client.health(); return {"schema":"lf-profile-runtime-api-snapshot/v1","runtime_version":self.settings.runtime_version,"resolver_version":self.settings.resolver_version,"source_sha":self.settings.source_sha,"bind":{"host":self.settings.api_host,"port":self.settings.api_port},"llama_server":llama,"cache":self.cache.stats(),"max_workers":self.settings.max_workers,"max_batch_size":self.settings.max_batch_size,"full_image_model_enabled":self.settings.allow_model_image,"deployment_classification":"INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY","operational_ready":False,"downstream_authorized":False}

    def _execute_queue_profile(self, *, task: ProfileTask, context_pack: dict[str, Any]) -> dict[str, Any]:
        started=time.perf_counter(); context={"queue_native":True,"screen_governance_applicable":False,"cache_hit":False}
        try:
            if task.send_image_to_model: raise LlamaTransportError("QUEUE_NATIVE_IMAGE_REQUIRES_GOVERNED_ENVELOPE")
            sources=self.repository.profile_sources(task.profile_slug,task.profile_source_paths); schema=self.repository.runtime_schema(task.profile_slug)
            governed_pack, governed_receipt = _governed_context(task, context_pack)
            adapter=PersistentLlamaServerAdapter(settings=self.settings,client=self.llama_client,schema=schema,structural_context=governed_pack,image_bytes=None,image_media_type=None)
            verifier=PersistentLlamaServerVerifier(settings=self.settings,schema=schema,structural_context=governed_pack)
            runtime_package=self.runner.execute_profile_runtime(execution_id=f"EJECUCION_PERFIL_LF:{task.request_id}",profile_code=task.profile_code,profile_slug=task.profile_slug,profile_sources=sources,input_literal=task.input_literal,adapter=adapter,attestation_verifier=verifier,allow_test_doubles=False,lf_adapter_sources=[i.model_dump(mode="python") for i in task.lf_adapter_sources])
        except Exception as exc:
            code,detail=_failure(exc); return self._profile_failure(task=task,code=code,detail=detail,stage="RUNTIME_COMPLETION",started=started,context=context)
        contract,payload=self.gates.contract(profile_slug=task.profile_slug,raw_output=runtime_package.get("raw_output"),schema=schema); semantic=self.gates.semantic_utility(profile_slug=task.profile_slug,payload=payload,contract_gate=contract)
        completion={"status":"PASS","blocking_codes":[],"receipt":runtime_package.get("receipt"),"governed_context_receipt":governed_receipt,"attestation_verification":runtime_package.get("runtime_attestation_verification"),"llama_usage":adapter.last_completion.get("usage",{}),"llama_timings":adapter.last_completion.get("timings",{})}
        return {"request_id":task.request_id,"profile_code":task.profile_code,"profile_slug":task.profile_slug,"context":context,"runtime_completion":completion,"profile_contract_valid":contract,"semantic_utility":semantic,"raw_output":runtime_package.get("raw_output"),"elapsed_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

    def _execute_profile(self, *, task: ProfileTask, artifact: Any, prepared: PreparedContext, context_reused_within_batch: bool) -> dict[str, Any]:
        started=time.perf_counter(); context={"cache_key":prepared.cache_key,"cache_hit":prepared.cache_hit,"pack_sha256":prepared.pack.get("pack_sha256"),"prepare_ms":prepared.prepare_ms,"reused_within_batch":context_reused_within_batch}
        try:
            sources=self.repository.profile_sources(task.profile_slug,task.profile_source_paths); schema=self.repository.runtime_schema(task.profile_slug)
            if task.send_image_to_model and not self.settings.allow_model_image: raise LlamaTransportError("FULL_IMAGE_MODEL_PATH_DISABLED")
            image_bytes=artifact.image_bytes() if task.send_image_to_model else None
            governed_pack, governed_receipt = _governed_context(task, prepared.pack)
            adapter=PersistentLlamaServerAdapter(settings=self.settings,client=self.llama_client,schema=schema,structural_context=governed_pack,image_bytes=image_bytes,image_media_type=artifact.image_media_type if image_bytes is not None else None)
            verifier=PersistentLlamaServerVerifier(settings=self.settings,schema=schema,structural_context=governed_pack)
            runtime_package=self.runner.execute_profile_runtime(execution_id=f"EJECUCION_PERFIL_LF:{task.request_id}",profile_code=task.profile_code,profile_slug=task.profile_slug,profile_sources=sources,input_literal=task.input_literal,adapter=adapter,attestation_verifier=verifier,allow_test_doubles=False,lf_adapter_sources=[i.model_dump(mode="python") for i in task.lf_adapter_sources])
        except Exception as exc:
            code,detail=_failure(exc); return self._profile_failure(task=task,code=code,detail=detail,stage="RUNTIME_COMPLETION",started=started,context=context)
        contract,payload=self.gates.contract(profile_slug=task.profile_slug,raw_output=runtime_package.get("raw_output"),schema=schema); semantic=self.gates.semantic_utility(profile_slug=task.profile_slug,payload=payload,contract_gate=contract)
        completion={"status":"PASS","blocking_codes":[],"receipt":runtime_package.get("receipt"),"governed_context_receipt":governed_receipt,"attestation_verification":runtime_package.get("runtime_attestation_verification"),"llama_usage":adapter.last_completion.get("usage",{}),"llama_timings":adapter.last_completion.get("timings",{})}
        return {"request_id":task.request_id,"profile_code":task.profile_code,"profile_slug":task.profile_slug,"context":context,"runtime_completion":completion,"profile_contract_valid":contract,"semantic_utility":semantic,"raw_output":runtime_package.get("raw_output"),"elapsed_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

    @staticmethod
    def _profile_failure(*,task:ProfileTask,code:str,detail:str|None,stage:str,started:float,context:dict[str,Any]|None=None)->dict[str,Any]:
        completion={"status":"FAIL","blocking_codes":[code],"stage":stage};
        if detail: completion["detail"]=detail
        return {"request_id":task.request_id,"profile_code":task.profile_code,"profile_slug":task.profile_slug,"context":context,"runtime_completion":completion,"profile_contract_valid":_not_evaluated("RUNTIME_COMPLETION_FAILED"),"semantic_utility":_not_evaluated("RUNTIME_COMPLETION_FAILED"),"raw_output":None,"elapsed_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}

    @staticmethod
    def _batch_result(request:BatchRequest,profile_results:list[dict[str,Any]],started:float,*,context:PreparedContext|None)->dict[str,Any]:
        passed=sum(i.get("runtime_completion",{}).get("status")=="PASS" for i in profile_results); contract_passed=sum(i.get("profile_contract_valid",{}).get("status")=="PASS" for i in profile_results); utility_passed=sum(i.get("semantic_utility",{}).get("status")=="PASS" for i in profile_results)
        return {"schema":RESULT_SCHEMA,"kind":"batch","batch_id":request.batch_id,"artifact_sha256":request.artifact.image_sha256,"status":"COMPLETED","context":None if context is None else {"cache_key":context.cache_key,"cache_hit":context.cache_hit,"pack_sha256":context.pack.get("pack_sha256"),"prepare_ms":context.prepare_ms,"prepared_once":True,"reuse_count":max(0,len(profile_results)-1)},"summary":{"profiles_total":len(profile_results),"runtime_completion_pass":passed,"profile_contract_valid_pass":contract_passed,"semantic_utility_floor_pass":utility_passed},"profile_results":profile_results,"total_ms":round((time.perf_counter()-started)*1000,3),"downstream_authorized":False}
