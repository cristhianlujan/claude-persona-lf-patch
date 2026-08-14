#!/usr/bin/env python3
"""Source-bound OmniParser icon caption microbenchmark.

This benchmark intentionally bypasses OmniParser's detector because the governed
LF reader already produced the 18 exact ICON_FUNCTION_NOT_OBSERVABLE regions.
It measures the independent icon-caption model on those fixed crops.

This is technical evidence only:
- no authentic human adjudication;
- no P0-5 or real-corpus credit;
- no production authorization;
- no interaction behavior is promoted from pixels alone.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

SOURCE_SHA = "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"
SOURCE_BYTES = 1_384_686
SOURCE_EVIDENCE_OBJECT_ID = "be7fcf20-5f83-46d4-be0e-c80dc3ceed7c"
MODEL_REPO = "microsoft/OmniParser-v2.0"
MODEL_REVISION = "f69bfad5de1394935f036d4e435cf7a2b80e8c4b"
MODEL_WEIGHT_PATH = "icon_caption/model.safetensors"
MODEL_WEIGHT_SHA256 = "01b934b0fe2d07b181e2d07752f16ae27c9d0ea88ddffe13a9a003aa9680f233"
OMNIPARSER_REPO_COMMIT = "b0d5c9f5701f7e2be4771872e6e928da77759df3"
PROCESSOR_REPO = "microsoft/Florence-2-base"
PROCESSOR_REVISION = "386f84a8872b44814ea429c0187e0b7406260d94"
FLORENCE_CODE_REPO = "microsoft/Florence-2-base-ft"
FLORENCE_CODE_REVISION = "0d9634b5410c7947cf54ca344be5ad328240721f"
REFERENCE_CLASS = "TECHNICAL_OBSERVABLE_REFERENCE_NOT_HUMAN_ADJUDICATION"


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_targets(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != "p0-icon-semantic-targets/v1":
        raise SystemExit("FAIL_ICON_TARGET_SCHEMA")
    if payload.get("source_sha256") != SOURCE_SHA or int(payload.get("source_bytes", -1)) != SOURCE_BYTES:
        raise SystemExit("FAIL_ICON_TARGET_SOURCE_BINDING")
    targets = payload.get("targets")
    if not isinstance(targets, list) or len(targets) != 18:
        raise SystemExit(f"FAIL_ICON_TARGET_COUNT:{len(targets) if isinstance(targets, list) else 'invalid'}")
    ids = [t.get("element_id") for t in targets]
    if len(set(ids)) != 18:
        raise SystemExit("FAIL_ICON_TARGET_DUPLICATE_ID")
    if payload.get("reference_class") != REFERENCE_CLASS:
        raise SystemExit("FAIL_ICON_TARGET_REFERENCE_CLASS")
    if payload.get("real_corpus_credit") != 0 or payload.get("p0_5_credit") != 0:
        raise SystemExit("FAIL_ICON_TARGET_CREDIT_BOUNDARY")
    if payload.get("production_authorized") is not False:
        raise SystemExit("FAIL_ICON_TARGET_PRODUCTION_BOUNDARY")
    return payload


def fetch_source_from_broker() -> bytes:
    import p0_exact_head_real_source_ci_v1 as legacy
    import p0_exact_head_real_source_ci_v2 as v2

    config = v2.load_config()
    legacy.BROKER_URL = config["broker_url"]
    token = legacy.require_env("GITHUB_TOKEN")
    identity = {
        "repository": legacy.require_env("GITHUB_REPOSITORY"),
        "ref": legacy.require_env("GITHUB_REF"),
        "github_sha": legacy.require_env("GITHUB_SHA"),
        "run_id": int(legacy.require_env("GITHUB_RUN_ID")),
        "run_attempt": int(legacy.require_env("GITHUB_RUN_ATTEMPT")),
        "event_name": legacy.require_env("GITHUB_EVENT_NAME"),
    }
    delivered = legacy.broker(token, {**identity, "action": "get_source"})
    if delivered.get("outcome") != "SOURCE_DELIVERED_TO_EXACT_GITHUB_RUN":
        raise SystemExit(f"FAIL_ICON_SOURCE_DELIVERY_OUTCOME:{delivered.get('outcome')}")
    info = delivered.get("source")
    if not isinstance(info, dict):
        raise SystemExit("FAIL_ICON_SOURCE_DELIVERY_SHAPE")
    if info.get("evidence_object_id") != SOURCE_EVIDENCE_OBJECT_ID:
        raise SystemExit("FAIL_ICON_SOURCE_EVIDENCE_ID")
    if info.get("content_sha256") != SOURCE_SHA or int(info.get("content_bytes", -1)) != SOURCE_BYTES:
        raise SystemExit("FAIL_ICON_SOURCE_METADATA")
    source = base64.b64decode(info["content_base64"], validate=False)
    if len(source) != SOURCE_BYTES or sha256_bytes(source) != SOURCE_SHA:
        raise SystemExit("FAIL_ICON_SOURCE_CRYPTOGRAPHIC_INTEGRITY")
    return source


def normalize(text: str) -> str:
    return " ".join("".join(ch.lower() if ch.isalnum() else " " for ch in text).split())


def matches_alias(caption: str, aliases: list[str]) -> bool:
    norm = normalize(caption)
    for alias in aliases:
        a = normalize(alias)
        if a and a in norm:
            return True
    return False


def _self_test() -> None:
    checks = {
        "shield": matches_alias("a shield with a check mark", ["shield", "security"]),
        "lock": matches_alias("padlock icon", ["lock", "padlock"]),
        "person_negative": not matches_alias("green lightning bolt", ["person", "user"]),
        "text_fragment": matches_alias("the word registro", ["text", "registro"]),
    }
    if not all(checks.values()):
        raise SystemExit(f"FAIL_ICON_MICROBENCH_SELF_TEST:{checks}")
    print(json.dumps({"gate": "PASS_ICON_MICROBENCH_SELF_TEST", "checks": checks}, sort_keys=True))


def run_model(source_path: Path, targets_payload: dict, output_path: Path) -> dict:
    import cv2
    import torch
    from huggingface_hub import snapshot_download
    from PIL import Image
    from transformers import AutoModelForCausalLM, AutoProcessor

    torch.set_num_threads(max(1, min(4, os.cpu_count() or 1)))
    cache_root = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface"))
    snapshot = Path(snapshot_download(
        repo_id=MODEL_REPO,
        revision=MODEL_REVISION,
        allow_patterns=["icon_caption/*"],
        cache_dir=str(cache_root),
    ))
    weight = snapshot / MODEL_WEIGHT_PATH
    if not weight.is_file():
        raise SystemExit("FAIL_ICON_MODEL_WEIGHT_MISSING")
    observed_weight_sha = sha256_bytes(weight.read_bytes())
    if observed_weight_sha != MODEL_WEIGHT_SHA256:
        raise SystemExit(
            f"FAIL_ICON_MODEL_WEIGHT_SHA:expected={MODEL_WEIGHT_SHA256}:observed={observed_weight_sha}"
        )

    processor = AutoProcessor.from_pretrained(
        PROCESSOR_REPO,
        revision=PROCESSOR_REVISION,
        trust_remote_code=True,
        code_revision=PROCESSOR_REVISION,
    )
    model_dir = snapshot / "icon_caption"
    model = AutoModelForCausalLM.from_pretrained(
        str(model_dir),
        torch_dtype=torch.float32,
        trust_remote_code=True,
        code_revision=FLORENCE_CODE_REVISION,
    )
    model.eval()

    image_bgr = cv2.imread(str(source_path))
    if image_bgr is None:
        raise SystemExit("FAIL_ICON_SOURCE_DECODE")
    h, w = image_bgr.shape[:2]
    if (w, h) != (1536, 1024):
        raise SystemExit(f"FAIL_ICON_SOURCE_DIMENSIONS:{w}x{h}")

    crops = []
    metadata = []
    crop_dir = output_path.parent / "icon-crops"
    crop_dir.mkdir(parents=True, exist_ok=True)
    for target in targets_payload["targets"]:
        b = target["bbox"]
        x, y, bw, bh = (int(b[k]) for k in ("x", "y", "width", "height"))
        if not (0 <= x < w and 0 <= y < h and bw > 0 and bh > 0 and x + bw <= w and y + bh <= h):
            raise SystemExit(f"FAIL_ICON_BBOX:{target['element_id']}")
        crop = image_bgr[y:y+bh, x:x+bw]
        crop64 = cv2.resize(crop, (64, 64), interpolation=cv2.INTER_LINEAR)
        rgb = cv2.cvtColor(crop64, cv2.COLOR_BGR2RGB)
        pil = Image.fromarray(rgb)
        crop_path = crop_dir / f"{target['element_id']}.png"
        pil.save(crop_path)
        crops.append(pil)
        metadata.append({
            **target,
            "crop_sha256": sha256_bytes(crop_path.read_bytes()),
            "crop_resize": "64x64_INTER_LINEAR_OFFICIAL_OMNIPARSER_METHOD",
        })

    prompt = "<CAPTION>"
    captions: list[str] = []
    latencies: list[float] = []
    batch_size = 2
    with torch.inference_mode():
        for start in range(0, len(crops), batch_size):
            batch = crops[start:start+batch_size]
            t0 = time.perf_counter()
            inputs = processor(images=batch, text=[prompt] * len(batch), return_tensors="pt")
            generated = model.generate(
                input_ids=inputs["input_ids"],
                pixel_values=inputs["pixel_values"],
                max_new_tokens=20,
                num_beams=1,
                do_sample=False,
            )
            texts = [x.strip() for x in processor.batch_decode(generated, skip_special_tokens=True)]
            latencies.append(time.perf_counter() - t0)
            captions.extend(texts)

    if len(captions) != 18:
        raise SystemExit(f"FAIL_ICON_CAPTION_COUNT:{len(captions)}")

    rows = []
    identity_match_count = 0
    safely_resolvable = 0
    for target, caption in zip(metadata, captions):
        match = matches_alias(caption, list(target["aliases"]))
        identity_match_count += int(match)
        policy_safe = bool(target["policy_resolvable"]) and match
        safely_resolvable += int(policy_safe)
        rows.append({
            "element_id": target["element_id"],
            "bbox": target["bbox"],
            "crop_sha256": target["crop_sha256"],
            "expected_identity": target["expected_identity"],
            "observed_caption": caption,
            "identity_family_match": match,
            "material_role": target["material_role"],
            "resolution_policy": target["resolution_policy"],
            "policy_resolvable_if_identity_matches": bool(target["policy_resolvable"]),
            "safe_policy_resolution_supported": policy_safe,
            "interaction_function_confirmed": False,
        })

    metrics = {
        "target_count": 18,
        "caption_nonempty_count": sum(bool(x.strip()) for x in captions),
        "identity_family_match_count": identity_match_count,
        "identity_family_match_rate": identity_match_count / 18,
        "safe_policy_resolution_supported_count": safely_resolvable,
        "safe_policy_resolution_supported_rate": safely_resolvable / 18,
        "icon_observations_remaining_if_policy_adopted": 18 - safely_resolvable,
        "interaction_functions_confirmed_from_pixels": 0,
        "batch_count": len(latencies),
        "batch_latency_seconds": latencies,
        "total_generation_seconds": sum(latencies),
    }
    result = {
        "schema_version": "p0-icon-omniparser-microbenchmark/v1",
        "reference_class": REFERENCE_CLASS,
        "source_sha256": SOURCE_SHA,
        "source_bytes": SOURCE_BYTES,
        "source_evidence_object_id": SOURCE_EVIDENCE_OBJECT_ID,
        "code_head_sha": os.environ.get("GITHUB_SHA", ""),
        "omniparser": {
            "repository": "microsoft/OmniParser",
            "release": "v.2.0.1",
            "repository_commit": OMNIPARSER_REPO_COMMIT,
            "caption_model_repo": MODEL_REPO,
            "caption_model_revision": MODEL_REVISION,
            "caption_weight_sha256": MODEL_WEIGHT_SHA256,
            "processor_repo": PROCESSOR_REPO,
            "processor_revision": PROCESSOR_REVISION,
            "florence_code_repo": FLORENCE_CODE_REPO,
            "florence_code_revision": FLORENCE_CODE_REVISION,
            "method": "fixed governed bbox -> exact crop -> cv2 INTER_LINEAR 64x64 -> Florence2 <CAPTION>",
            "detector_used": False,
            "detector_reason": "LF already has 18 governed icon regions; benchmark isolates semantic captioning."
        },
        "metrics": metrics,
        "targets": rows,
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "holdout_accessed": False,
        "runtime_promoted": False,
        "production_authorized": False,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({
        "gate": "PASS_P0_ICON_OMNIPARSER_MICROBENCHMARK",
        "target_count": 18,
        "identity_matches": identity_match_count,
        "safe_policy_resolutions": safely_resolvable,
        "icon_observations_remaining": 18 - safely_resolvable,
        "output_sha256": sha256_bytes(output_path.read_bytes()),
    }, sort_keys=True))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--targets", required=False, default=str(Path(__file__).with_name("evidence") / "OMNIPARSER_ICON_TARGETS_20260814.json"))
    parser.add_argument("--output", required=False, default=".audit-output/omniparser-icon-microbenchmark.json")
    parser.add_argument("--source", required=False)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    _self_test()
    if args.self_test:
        return 0

    targets = load_targets(Path(args.targets))
    output = Path(args.output)
    if args.source:
        source_path = Path(args.source)
        source = source_path.read_bytes()
        if len(source) != SOURCE_BYTES or sha256_bytes(source) != SOURCE_SHA:
            raise SystemExit("FAIL_ICON_LOCAL_SOURCE_BINDING")
    else:
        source = fetch_source_from_broker()
        source_path = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "lf-p0-icon-source.png"
        source_path.write_bytes(source)

    try:
        run_model(source_path, targets, output)
    finally:
        if not args.source:
            source_path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
