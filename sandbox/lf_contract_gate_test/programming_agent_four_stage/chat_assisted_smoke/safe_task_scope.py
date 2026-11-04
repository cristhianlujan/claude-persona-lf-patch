"""Offline task-scope check used only to exercise ChatGPT-driven GitHub workflow.

No Supabase authority, DB reads or Worker dispatch.
"""
from pathlib import PurePosixPath

class ScopeError(ValueError):
    pass

def validate_allowed_change(path: str, *, allowed_prefix: str, protected: tuple[str, ...]) -> str:
    if not isinstance(path, str) or not path or "\\" in path:
        raise ScopeError("INVALID_PATH")
    parts = PurePosixPath(path).parts
    if path.startswith("/") or ".." in parts or "." in parts:
        raise ScopeError("INVALID_PATH")
    if not allowed_prefix.endswith("/") or not path.startswith(allowed_prefix):
        raise ScopeError("OUTSIDE_ALLOWED_SCOPE")
    if path in protected:
        raise ScopeError("PROTECTED_PATH")
    return path
