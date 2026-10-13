"""Evidence-bound path discontinuity detection; not a do-calculus causal claim.

Consumer-facing analysis of edge observations. CAUSAL_EFFECT_LINEAGE remains the
canonical authority for producer->receiver effect verification and receipts.
"""
from __future__ import annotations


def assess_paths(nodes: list[str], edges: list[dict], start: str, end: str, *, max_paths: int = 128) -> dict:
    def blocked(reason): return {"status": "BLOCK", "reason": reason, "cutover_eligible": False}
    if (not isinstance(nodes, list) or not nodes or len(nodes) > 200
            or any(not isinstance(n, str) or not n for n in nodes)
            or len(set(nodes)) != len(nodes)):
        return blocked("GRAPH_NODES_INVALID")
    if start not in nodes or end not in nodes or start == end:
        return blocked("ENDPOINT_INVALID")
    if not isinstance(edges, list) or not edges or len(edges) > 800:
        return blocked("GRAPH_EDGES_INVALID")
    if type(max_paths) is not int or not 1 <= max_paths <= 1000:
        return blocked("PATH_BUDGET_INVALID")
    adj = {node: [] for node in nodes}
    identifiers = set()
    for edge in edges:
        if not isinstance(edge, dict): return blocked("EDGE_INVALID")
        src, dst = edge.get("source"), edge.get("target")
        if src not in adj or dst not in adj or src == dst:
            return blocked("EDGE_ENDPOINT_INVALID")
        if edge.get("state") not in ("VERIFIED", "BROKEN", "UNKNOWN"):
            return blocked("EDGE_STATE_INVALID")
        if (not isinstance(edge.get("evidence_ref"), str) or not edge["evidence_ref"].strip()
                or not isinstance(edge.get("edge_id"), str) or not edge["edge_id"].strip()):
            return blocked("EDGE_PROVENANCE_MISSING")
        if edge["edge_id"] in identifiers: return blocked("EDGE_ID_DUPLICATE")
        identifiers.add(edge["edge_id"])
        adj[src].append(edge)
    color = {n: 0 for n in nodes}
    def dfs_cycle(node):
        color[node] = 1
        for e in adj[node]:
            nxt = e["target"]
            if color[nxt] == 1 or (color[nxt] == 0 and dfs_cycle(nxt)):
                return True
        color[node] = 2
        return False
    if any(color[n] == 0 and dfs_cycle(n) for n in nodes):
        return blocked("CYCLIC_GRAPH_UNSUPPORTED")
    routes = []
    overflow = False
    def walk(node, path):
        nonlocal overflow
        if overflow: return
        if node == end:
            if len(routes) >= max_paths:
                overflow = True
            else:
                routes.append(path)
            return
        for edge in adj[node]:
            walk(edge["target"], path + [edge])
            if overflow: return
    walk(start, [])
    if overflow: return blocked("PATH_BUDGET_EXHAUSTED")
    if not routes:
        return {"status": "NO_OBSERVED_TOPOLOGICAL_PATH", "cutover_eligible": False, "causal_proof": False}
    good = sum(all(edge["state"] == "VERIFIED" for edge in p) for p in routes)
    first_breaks = {next(edge["edge_id"] for edge in p if edge["state"] != "VERIFIED")
                    for p in routes if any(edge["state"] != "VERIFIED" for edge in p)}
    broken = {x for x in first_breaks if next(e["state"] for e in edges if e["edge_id"] == x) == "BROKEN"}
    unknown = first_breaks - broken
    status = ("ALTERNATE_VERIFIED_PATH_PRESENT" if good and first_breaks else
              "ALL_PATHS_OBSERVED_VERIFIED" if good else "OBSERVED_BOUNDARY_GAPS")
    return {"status": status, "paths": len(routes), "verified_paths": good,
            "first_broken_edges": sorted(broken), "first_unknown_edges": sorted(unknown),
            "causal_proof": False, "root_cause_certified": False,
            "external_effect_readback_required": True, "cutover_eligible": False}
