#!/usr/bin/env python3
"""Identity-only CLIP microbenchmark over the same 18 governed icon regions.

Pre-registered purpose:
- measure visual identity family only;
- never infer click/function behavior from CLIP similarity;
- preserve the OmniParser 0/18 free-form caption baseline;
- no authentic human adjudication, P0-5 credit, real-corpus credit, or runtime promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import statistics
import time
from pathlib import Path

SOURCE_SHA = "e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7"
SOURCE_BYTES = 1_384_686
MODEL_REPO = "openai/clip-vit-base-patch32"
MODEL_REVISION = "c7244be81152024ce0e99ac8d2e373a8953d9f9a"
MODEL_WEIGHT = "model.safetensors"
MODEL_WEIGHT_SHA256 = "99d28a652e6ec46629ab7047a0ac82c69b1fe11e0ce672c43af65d3a9a3fc05d"
REFERENCE_CLASS = "TECHNICAL_OBSERVABLE_REFERENCE_NOT_HUMAN_ADJUDICATION"

# Fixed before inference. Prompt wording is deliberately generic and not tuned per target.
CLASS_PROMPTS = {
    "BRAND_MARK": "a brand logo icon",
    "SHIELD": "a shield security icon",
    "HELP_QUESTION": "a question mark help icon",
    "PERSON": "a person user profile icon",
    "IDENTITY_CARD": "an identity card ID icon",
    "LIGHTNING": "a lightning bolt icon",
    "LOCK": "a lock padlock icon",
    "ARROW_RIGHT": "a right arrow icon",
    "TEXT_FRAGMENT_NOT_ICON": "text letters or a word",
    "OTHER": "another simple interface symbol",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def self_test() -> None:
    required = {
        "BRAND_MARK", "SHIELD", "HELP_QUESTION", "PERSON", "IDENTITY_CARD",
        "LIGHTNING", "LOCK", "ARROW_RIGHT", "TEXT_FRAGMENT_NOT_ICON", "OTHER",
    }
    if set(CLASS_PROMPTS) != required or len(CLASS_PROMPTS) != 10:
        raise SystemExit("FAIL_CLIP_CLASS_REGISTRY")
    if len(set(CLASS_PROMPTS.values())) != 10:
        raise SystemExit("FAIL_CLIP_PROMPT_DUPLICATE")
    print(json.dumps({"gate": "PASS_CLIP_IDENTITY_SELF_TEST", "class_count": 10}, sort_keys=True))


def load_targets(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != "p0-icon-semantic-targets/v1":
        raise SystemExit("FAIL_CLIP_TARGET_SCHEMA")
    if data.get("source_sha256") != SOURCE_SHA or int(data.get("source_bytes", -1)) != SOURCE_BYTES:
        raise SystemExit("FAIL_CLIP_SOURCE_BINDING")
    targets = data.get("targets")
    if not isinstance(targets, list) or len(targets) != 18:
        raise SystemExit("FAIL_CLIP_TARGET_COUNT")
    for target in targets:
        expected = target.get("expected_identity")
        if expected not in CLASS_PROMPTS:
            raise SystemExit(f"FAIL_CLIP_UNREGISTERED_EXPECTED_CLASS:{expected}")
    if data.get("reference_class") != REFERENCE_CLASS:
        raise SystemExit("FAIL_CLIP_REFERENCE_CLASS")
    if data.get("real_corpus_credit") != 0 or data.get("p0_5_credit") != 0:
        raise SystemExit("FAIL_CLIP_CREDIT_BOUNDARY")
    return data


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=False)
    parser.add_argument(
        "--targets",
        default=str(Path(__file__).with_name("evidence") / "OMNIPARSER_ICON_TARGETS_20260814.json"),
    )
    parser.add_argument("--output", default=".audit-output/clip-icon-identity-microbenchmark.json")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        return 0
    if not args.source:
        raise SystemExit("FAIL_CLIP_SOURCE_REQUIRED")

    from huggingface_hub import snapshot_download
    from PIL import Image
    import torch
    from transformers import CLIPModel, CLIPProcessor

    torch.set_num_threads(max(1, min(4, os.cpu_count() or 1)))
    source_path = Path(args.source)
    source_bytes = source_path.read_bytes()
    if len(source_bytes) != SOURCE_BYTES or sha256_bytes(source_bytes) != SOURCE_SHA:
        raise SystemExit("FAIL_CLIP_LOCAL_SOURCE_BINDING")
    targets = load_targets(Path(args.targets))

    cache_root = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface"))
    snapshot = Path(snapshot_download(
        repo_id=MODEL_REPO,
        revision=MODEL_REVISION,
        allow_patterns=[
            MODEL_WEIGHT, "config.json", "preprocessor_config.json", "tokenizer.json",
            "tokenizer_config.json", "special_tokens_map.json", "vocab.json", "merges.txt",
        ],
        cache_dir=str(cache_root),
    ))
    weight = snapshot / MODEL_WEIGHT
    if not weight.is_file():
        raise SystemExit("FAIL_CLIP_WEIGHT_MISSING")
    observed_weight_sha = sha256_bytes(weight.read_bytes())
    if observed_weight_sha != MODEL_WEIGHT_SHA256:
        raise SystemExit(
            f"FAIL_CLIP_WEIGHT_SHA:expected={MODEL_WEIGHT_SHA256}:observed={observed_weight_sha}"
        )

    processor = CLIPProcessor.from_pretrained(str(snapshot), local_files_only=True)
    model = CLIPModel.from_pretrained(
        str(snapshot), local_files_only=True, use_safetensors=True, torch_dtype=torch.float32
    ).eval()

    source = Image.open(source_path).convert("RGB")
    if source.size != (1536, 1024):
        raise SystemExit(f"FAIL_CLIP_SOURCE_DIMENSIONS:{source.size}")

    labels = list(CLASS_PROMPTS)
    prompts = [CLASS_PROMPTS[x] for x in labels]
    text_inputs = processor(text=prompts, return_tensors="pt", padding=True)
    with torch.inference_mode():
        text_features = model.get_text_features(**text_inputs)
        text_features = text_features / text_features.norm(dim=-1, keepdim=True)

    rows = []
    top1_correct = 0
    top2_contains_expected = 0
    margins = []
    latencies = []
    crop_dir = Path(args.output).parent / "clip-icon-crops"
    crop_dir.mkdir(parents=True, exist_ok=True)

    for target in targets["targets"]:
        b = target["bbox"]
        x, y, w, h = (int(b[k]) for k in ("x", "y", "width", "height"))
        crop = source.crop((x, y, x + w, y + h))
        crop_path = crop_dir / f"{target['element_id']}.png"
        crop.save(crop_path)
        t0 = time.perf_counter()
        image_inputs = processor(images=crop, return_tensors="pt")
        with torch.inference_mode():
            image_features = model.get_image_features(**image_inputs)
            image_features = image_features / image_features.norm(dim=-1, keepdim=True)
            similarities = (image_features @ text_features.T)[0]
            ranked = torch.argsort(similarities, descending=True).tolist()
        latencies.append(time.perf_counter() - t0)
        top1 = labels[ranked[0]]
        top2 = [labels[i] for i in ranked[:2]]
        expected = target["expected_identity"]
        correct = top1 == expected
        contains = expected in top2
        top1_correct += int(correct)
        top2_contains_expected += int(contains)
        margin = float(similarities[ranked[0]] - similarities[ranked[1]])
        margins.append(margin)
        rows.append({
            "element_id": target["element_id"],
            "bbox": target["bbox"],
            "crop_sha256": sha256_bytes(crop_path.read_bytes()),
            "expected_identity": expected,
            "top1_identity": top1,
            "top1_correct": correct,
            "top2_identities": top2,
            "expected_in_top2": contains,
            "top1_margin_raw_cosine": margin,
            "top3": [
                {"identity": labels[i], "cosine_similarity": float(similarities[i])}
                for i in ranked[:3]
            ],
            "interaction_function_confirmed": False,
        })

    metrics = {
        "target_count": 18,
        "class_count": len(labels),
        "top1_identity_correct_count": top1_correct,
        "top1_identity_accuracy": top1_correct / 18,
        "expected_in_top2_count": top2_contains_expected,
        "expected_in_top2_rate": top2_contains_expected / 18,
        "median_top1_margin_raw_cosine": statistics.median(margins),
        "min_top1_margin_raw_cosine": min(margins),
        "max_top1_margin_raw_cosine": max(margins),
        "median_inference_seconds_per_crop": statistics.median(latencies),
        "interaction_functions_confirmed_from_clip": 0,
    }
    result = {
        "schema_version": "p0-icon-clip-identity-microbenchmark/v1",
        "reference_class": REFERENCE_CLASS,
        "source_sha256": SOURCE_SHA,
        "source_bytes": SOURCE_BYTES,
        "code_head_sha": os.environ.get("GITHUB_SHA", ""),
        "model": {
            "repo": MODEL_REPO,
            "revision": MODEL_REVISION,
            "weight_path": MODEL_WEIGHT,
            "weight_sha256": MODEL_WEIGHT_SHA256,
            "task": "identity_family_only_zero_shot",
            "prompts": CLASS_PROMPTS,
        },
        "metrics": metrics,
        "targets": rows,
        "decision_boundary": {
            "runtime_threshold_selected": False,
            "note": "No threshold is selected from this single-screen technical set. Similarity is diagnostic only.",
        },
        "real_corpus_credit": 0,
        "p0_5_credit": 0,
        "holdout_accessed": False,
        "runtime_promoted": False,
        "production_authorized": False,
    }
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({
        "gate": "PASS_P0_ICON_CLIP_IDENTITY_MICROBENCHMARK",
        "targets": 18,
        "top1_correct": top1_correct,
        "expected_in_top2": top2_contains_expected,
        "output_sha256": sha256_bytes(out.read_bytes()),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
