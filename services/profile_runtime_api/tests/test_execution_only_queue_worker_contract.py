import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ACTIVE = ROOT / "services/profile_runtime_api/scripts/hetzner_execution_only_queue_worker.py"
LEGACY = ROOT / "services/profile_runtime_api/scripts/hetzner_queue_worker.py"
MATERIALIZER = ROOT / "services/profile_runtime_api/scripts/runtime_envelope_materializer.py"
SERVICE = ROOT / "services/profile_runtime_api/deploy/lf-profile-runtime-queue-worker.service"

FORBIDDEN_RUNTIME_AUTHORITY_TOKENS = (
    "lf_router_resolve_v1",
    "v_lf_router_adapter_bindings",
    "from public.lf_activos",
    "metadata->'semantic_judge_binding'",
)
FORBIDDEN_LEGACY_CONTROL_FLOW = {
    "_adapter_sources",
    "_claim",
    "_begin_governed_pre_model",
    "run_once",
    "main",
}


def _legacy_called_helpers(active_tree: ast.AST) -> set[str]:
    names: set[str] = set()
    for node in ast.walk(active_tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        if (
            isinstance(fn, ast.Attribute)
            and isinstance(fn.value, ast.Name)
            and fn.value.id == "legacy"
        ):
            names.add(fn.attr)
    return names


def _function_map(tree: ast.AST) -> dict[str, ast.FunctionDef | ast.AsyncFunctionDef]:
    return {
        node.name: node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }


def _local_calls(node: ast.AST, known: set[str]) -> set[str]:
    calls: set[str] = set()
    for child in ast.walk(node):
        if isinstance(child, ast.Call) and isinstance(child.func, ast.Name):
            if child.func.id in known:
                calls.add(child.func.id)
    return calls


def test_active_service_uses_execution_only_worker() -> None:
    service = SERVICE.read_text(encoding="utf-8")
    assert "hetzner_execution_only_queue_worker.py --daemon" in service
    assert "hetzner_queue_worker.py --daemon" not in service


def test_active_worker_does_not_resolve_router_or_discover_assets() -> None:
    source = ACTIVE.read_text(encoding="utf-8")
    for token in FORBIDDEN_RUNTIME_AUTHORITY_TOKENS:
        assert token not in source
    assert "LF_ROUTER_EXECUTION_ENVELOPE_V1" in source
    assert "router_execution_envelope_sha256" in source
    assert "_materialize_resolved_adapter_sources" in source


def test_active_worker_owns_control_flow_without_monkeypatching_legacy() -> None:
    source = ACTIVE.read_text(encoding="utf-8")
    tree = ast.parse(source)
    assert "legacy.main(" not in source
    assert "legacy.run_once(" not in source
    assert "legacy._claim =" not in source
    assert "legacy._begin_governed_pre_model =" not in source
    functions = _function_map(tree)
    assert "run_once" in functions
    assert "main" in functions


def test_active_legacy_helper_closure_cannot_reach_discovery_authority() -> None:
    active_source = ACTIVE.read_text(encoding="utf-8")
    active_tree = ast.parse(active_source)
    roots = _legacy_called_helpers(active_tree)
    assert roots
    assert roots.isdisjoint(FORBIDDEN_LEGACY_CONTROL_FLOW)

    legacy_source = LEGACY.read_text(encoding="utf-8")
    legacy_tree = ast.parse(legacy_source)
    functions = _function_map(legacy_tree)
    known = set(functions)

    missing = sorted(name for name in roots if name not in functions)
    assert not missing, f"legacy helper roots missing: {missing}"

    closure = set(roots)
    pending = list(roots)
    while pending:
        name = pending.pop()
        for callee in _local_calls(functions[name], known):
            if callee not in closure:
                closure.add(callee)
                pending.append(callee)

    reached_forbidden = sorted(closure & FORBIDDEN_LEGACY_CONTROL_FLOW)
    assert not reached_forbidden, f"active runtime reaches forbidden legacy flow: {reached_forbidden}"

    closure_source = "\n".join(
        ast.get_source_segment(legacy_source, functions[name]) or ""
        for name in sorted(closure)
    )
    for token in FORBIDDEN_RUNTIME_AUTHORITY_TOKENS:
        assert token not in closure_source, f"reachable legacy helper contains forbidden authority token: {token}"


def test_router_advisory_materializer_is_pure_no_discovery() -> None:
    source = MATERIALIZER.read_text(encoding="utf-8")
    for token in FORBIDDEN_RUNTIME_AUTHORITY_TOKENS:
        assert token not in source
    assert "psycopg" not in source
    assert "urllib" not in source
    assert "materialize_router_advisory_envelope" in source


def test_runtime_only_reads_exact_router_resolved_capsule_refs() -> None:
    source = ACTIVE.read_text(encoding="utf-8")
    assert 'item.get("ref")' in source
    assert 'item.get("activation_source") != "ROUTER"' in source
    assert "HETZNER_RESOLVED_ADAPTER_CAPSULE_PATH_ESCAPE" in source
    assert "HETZNER_ROUTER_EXECUTION_PROFILE_CODE_MISMATCH" in source
    assert "HETZNER_ROUTER_EXECUTION_ENVELOPE_DIGEST_MISMATCH" in source
