"""A3 projection of existing GitHub AS-IS and Supabase authority readbacks.

Pure, source-only adapter. The existing authorized host fetches these facts;
this code neither resolves sources nor attests authority or currentness.
"""
from __future__ import annotations

from copy import deepcopy
import re
from typing import Any

SHA = re.compile(r"^[0-9a-f]{40}$")
PATH = re.compile(r"^[a-zA-Z0-9_./()@-]+$")


def project(readback: Any, target_ref: str) -> dict:
    def rejected(code: str) -> dict:
        return {"status": "BLOCKED", "blocking_code": code}

    if not isinstance(readback, dict) or readback.get("target_ref") != target_ref:
        return rejected("A3_AS_IS_TARGET_BINDING_MISSING")
    github, authority = readback.get("github"), readback.get("authority")
    if not isinstance(github, dict) or not isinstance(authority, dict):
        return rejected("A3_AS_IS_AND_AUTHORITY_BOTH_REQUIRED")
    if (github.get("repository") != "cristhianlujan/libertad-financiera"
            or not isinstance(github.get("commit_sha"), str)
            or not SHA.fullmatch(github["commit_sha"])
            or github.get("source_attested") is not False
            or github.get("currentness_attested") is not False
            or github.get("runtime_authorized") is not False):
        return rejected("A3_GITHUB_AS_IS_SOURCE_UNQUALIFIED")
    if (authority.get("source_ref")
            != "contract://programacion.contratos/B2B_AUTH_LOGIN_LOGICAL_BOUNDARY_CONTRACT#45"
            or authority.get("status") != "defined"
            or authority.get("version_id") != 19
            or authority.get("logical_only") is not True
            or authority.get("runtime_activation") is not False
            or authority.get("currentness_attested") is not False):
        return rejected("A3_LOGICAL_AUTHORITY_SOURCE_UNQUALIFIED")
    binding = authority.get("physical_binding")
    if (not isinstance(binding, dict)
            or binding.get("endpoint") != "UNBOUND"
            or binding.get("http_method") != "UNBOUND"
            or binding.get("oidc_grant") != "UNBOUND"):
        return rejected("A3_LOGICAL_AUTHORITY_BINDING_DRIFT")
    components = github.get("observed_components")
    if not isinstance(components, list) or not components:
        return rejected("A3_AS_IS_COMPONENT_SOURCE_MISSING")
    refs, seen, typed = [], set(), []
    for row in components:
        if not isinstance(row, dict):
            return rejected("A3_AS_IS_COMPONENT_INVALID")
        path, sha, scope = row.get("path"), row.get("blob_sha1"), row.get("scope")
        if (not isinstance(path, str) or not PATH.fullmatch(path)
                or path.startswith("/") or ".." in path.split("/")
                or not isinstance(sha, str) or not SHA.fullmatch(sha)
                or scope not in ("B2B_SHELL", "B2B_SESSION_CONTEXT", "B2B_PORTAL_LAYOUT", "B2B_SHELL_UI")
                or path in seen):
            return rejected("A3_AS_IS_COMPONENT_REF_INVALID")
        seen.add(path)
        ref = "github://"+github["repository"]+"@"+github["commit_sha"]+"/"+path+"#blob="+sha
        refs.append(ref)
        typed.append({"component_scope": scope, "path": path,
                      "source_ref": ref, "observation": "CODE_EXISTS_IN_REPO",
                      "business": "LF", "target_login_implemented": "UNKNOWN",
                      "source_attested": False})
    gaps = [
        "LOGIN_TARGET_IMPLEMENTATION_NOT_CONFIRMED",
        "LOGIN_LOGICAL_CONTRACT_PHYSICAL_BINDING_UNBOUND",
        "GITHUB_SOURCE_CURRENTNESS_NOT_ATTESTED",
        "LOGICAL_AUTHORITY_NOT_RELEASED",
    ]
    return {
        "status": "RELATED_AS_IS_FOUND_TARGET_LOGIN_UNKNOWN",
        "business": "LF", "target_ref": target_ref,
        "related_components": typed,
        "source_refs": refs+[authority["source_ref"]],
        "authority_candidate": {
            "source_ref": authority["source_ref"], "status": authority["status"],
            "version_id": authority["version_id"],
            "physical_binding": deepcopy(binding),
            "currentness": "UNKNOWN",
        },
        "authority_state": "UNKNOWN", "implementation_state": "UNKNOWN",
        "material_gaps": gaps,
        "currentness_refs": [],
        "source_attested": False, "a4_allowed": False,
    }
