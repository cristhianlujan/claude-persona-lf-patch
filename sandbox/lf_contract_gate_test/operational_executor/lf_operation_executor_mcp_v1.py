#!/usr/bin/env python3
"""MCP STDIO adapter. Not a hosted connection, not active by simply merging."""
from __future__ import annotations

import os
import sys

from handler_registry_v1 import HANDLERS
from lf_operation_executor_v1 import Request, runtime_dispatch


def serve() -> None:
    try:
        from mcp.server.fastmcp import FastMCP
    except ImportError as exc:
        raise SystemExit("The approved runtime must install FastMCP separately") from exc

    server = FastMCP("LF_OPERATION_EXECUTOR_V1")

    @server.tool()
    def execute_operational_action(
        operation_code: str,
        execution_id: str,
        handler_code: str,
        payload: dict,
        effect_scope: str,
        dispatch_key: str,
        dry_run: bool = True,
    ) -> dict:
        """Execute ONLY an admitted Router operation through a registered handler."""
        actor = os.environ.get("LF_OPERATION_EXECUTOR_ACTOR", "")
        req = Request(operation_code, execution_id, handler_code, payload,
                      effect_scope, dispatch_key, actor)
        return runtime_dispatch(req, HANDLERS, dry_run=dry_run)

    server.run(transport="stdio")


if __name__ == "__main__":
    if len(sys.argv) != 1:
        raise SystemExit("No raw-SQL, migration or apply_migration commands")
    serve()
