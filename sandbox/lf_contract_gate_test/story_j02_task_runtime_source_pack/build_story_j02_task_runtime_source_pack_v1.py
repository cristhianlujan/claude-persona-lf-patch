import argparse
import hashlib
import json
import re
from pathlib import Path, PurePosixPath
from typing import Any

import yaml


HERE = Path(__file__).resolve().parent
SPEC_PATH = HERE / "story_j02_task_runtime_source_pack_v1.json"
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load_authorities(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("AUTHORITY_SNAPSHOT_NOT_OBJECT")
    return payload


def validate_authority(name: str, value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        raise ValueError(f"AUTHORITY_{name.upper()}_MISSING")
    ref = value.get("ref")
    revision = value.get("revision")
    digest = value.get("digest")
    if not isinstance(ref, str) or not ref.strip():
        raise ValueError(f"AUTHORITY_{name.upper()}_REF_INVALID")
    if not isinstance(revision, str) or not revision.strip():
        raise ValueError(f"AUTHORITY_{name.upper()}_REVISION_INVALID")
    if not isinstance(digest, str) or not SHA64_RE.fullmatch(digest):
        raise ValueError(f"AUTHORITY_{name.upper()}_DIGEST_INVALID")
    return {"ref": ref, "revision": revision, "digest": digest}


def safe_path(repo_root: Path, ref: str, source_root: str) -> Path:
    pure = PurePosixPath(ref)
    if pure.is_absolute() or ".." in pure.parts or "." in pure.parts:
        raise ValueError(f"SOURCE_PATH_INVALID:{ref}")
    if not ref.startswith(source_root.rstrip("/") + "/"):
        raise ValueError(f"SOURCE_PATH_OUTSIDE_ROOT:{ref}")
    path = (repo_root / ref).resolve()
    root = (repo_root / source_root).resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"SOURCE_PATH_ESCAPE:{ref}") from exc
    if not path.is_file():
        raise ValueError(f"SOURCE_MISSING:{ref}")
    return path


def build(repo_root: Path, source_revision: str, authority_snapshot: dict[str, Any]) -> dict[str, Any]:
    if not SHA40_RE.fullmatch(source_revision):
        raise ValueError("SOURCE_REVISION_INVALID")
    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    source_root = spec["source_root"]
    rows: list[dict[str, str]] = []
    content_by_ref: dict[str, str] = {}
    seen: set[str] = set()

    for ref in spec["source_paths"]:
        if ref in seen:
            raise ValueError(f"SOURCE_DUPLICATE:{ref}")
        seen.add(ref)
        path = safe_path(repo_root, ref, source_root)
        raw = path.read_bytes()
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ValueError(f"SOURCE_NOT_UTF8:{ref}") from exc
        if not content:
            raise ValueError(f"SOURCE_EMPTY:{ref}")
        rows.append({"path": ref, "sha256": sha256_bytes(raw), "source_revision": source_revision})
        content_by_ref[ref] = content

    schema_ref = spec["runtime_schema"]["ref"]
    schema = json.loads(content_by_ref[schema_ref])
    if not isinstance(schema, dict):
        raise ValueError("RUNTIME_SCHEMA_ROOT_INVALID")

    judge_cfg = spec["judge_binding"]
    judge = yaml.safe_load(content_by_ref[judge_cfg["ref"]])
    if not isinstance(judge, dict):
        raise ValueError("J02_JUDGE_ROOT_INVALID")
    if judge.get("judge_code") != judge_cfg["judge_code"]:
        raise ValueError("J02_JUDGE_CODE_MISMATCH")
    if judge.get("version") != judge_cfg["judge_version"]:
        raise ValueError("J02_JUDGE_VERSION_MISMATCH")
    independence = judge.get("independence") or {}
    if not isinstance(independence, dict) or independence.get("worker_must_not_execute_own_judge") is not True:
        raise ValueError("J02_JUDGE_INDEPENDENCE_MISSING")
    validator_cfg = judge.get("validator") or {}
    if validator_cfg.get("entrypoint") != "scripts/validate_screen_decomposition_visual.py":
        raise ValueError("J02_JUDGE_VALIDATOR_MISMATCH")

    row_by_ref = {item["path"]: item for item in rows}
    context_chars = sum(len(content_by_ref[ref]) for ref in spec["model_context"]["source_refs"])
    if context_chars > spec["model_context"]["max_chars"]:
        raise ValueError(f"MODEL_CONTEXT_BUDGET_EXCEEDED:{context_chars}")

    authorities = [
        validate_authority(name, authority_snapshot.get(name))
        for name in spec["required_authority_refs"]
    ]

    return {
        "schema_version": "LF_PROFILE_TASK_AUTHORITY_SNAPSHOT_V1",
        "step_contract": {
            "step_id": spec["step_id"],
            "worker_role": spec["worker_role"],
            "judge_code": judge_cfg["judge_code"],
        },
        "profile_identity": {
            "profile_code": spec["profile_code"],
            "profile_slug": spec["profile_slug"],
        },
        "task_authority": {
            "source_mode": spec["source_mode"],
            "source_root": source_root,
            "source_refs": rows,
            "runtime_schema": {
                "ref": schema_ref,
                "sha256": row_by_ref[schema_ref]["sha256"],
                "selection_mode": "EXACT_REF",
            },
            "deterministic_validator": {
                "ref": spec["deterministic_validator"]["ref"],
                "sha256": row_by_ref[spec["deterministic_validator"]["ref"]]["sha256"],
                "invocation": "CLI",
            },
            "judge_binding": {
                "judge_code": judge_cfg["judge_code"],
                "ref": judge_cfg["ref"],
                "sha256": row_by_ref[judge_cfg["ref"]]["sha256"],
                "worker_must_not_execute_own_judge": True,
            },
            "model_context": {
                "source_refs": list(spec["model_context"]["source_refs"]),
                "max_chars": spec["model_context"]["max_chars"],
                "observed_chars": context_chars,
            },
            "authority_refs": authorities,
        },
        "source_revision": source_revision,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--authority-snapshot", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()

    result = build(
        Path(args.repo_root).resolve(),
        args.source_revision,
        load_authorities(Path(args.authority_snapshot)),
    )
    rendered = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
