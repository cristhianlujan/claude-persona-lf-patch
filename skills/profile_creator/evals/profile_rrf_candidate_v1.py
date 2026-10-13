"""Read-only Reciprocal Rank Fusion over independently sourced evidence rankings.

Never substitutes TARGETED_EVIDENCE_ACQUISITION or proves an item correct.
"""
from __future__ import annotations


def reciprocal_rank_fusion(sources: list[dict], k: int = 60) -> dict:
    def blocked(reason):
        return {"status": "BLOCK", "reason": reason, "cutover_eligible": False}
    if not isinstance(sources, list) or len(sources) < 2:
        return {"status": "NOT_APPLICABLE", "reason": "TWO_INDEPENDENT_SOURCES_REQUIRED", "cutover_eligible": False}
    if type(k) is not int or not 1 <= k <= 1000:
        return blocked("RRF_K_INVALID")
    origins, ids, subjects = set(), set(), set()
    scores: dict[str, float] = {}
    support: dict[str, list[str]] = {}
    for source in sources:
        if not isinstance(source, dict):
            return blocked("SOURCE_INVALID")
        for key in ("source_id", "origin_id", "subject_sha256", "receipt_ref", "source_revision"):
            if not isinstance(source.get(key), str) or not source[key].strip():
                return blocked("BOUND_SOURCE_IDENTITY_REQUIRED")
        if source.get("independently_observed") is not True:
            return blocked("SOURCE_OBSERVATION_NOT_VERIFIED")
        origin, sid = source["origin_id"], source["source_id"]
        if origin in origins or sid in ids:
            return blocked("SOURCE_REUSE_OR_DOUBLE_COUNT")
        origins.add(origin); ids.add(sid); subjects.add(source["subject_sha256"])
        ranks = source.get("ranked_items")
        if (not isinstance(ranks, list) or not ranks or len(ranks) > 500
                or any(not isinstance(x, str) or not x.strip() for x in ranks)
                or len(set(ranks)) != len(ranks)):
            return blocked("RANKED_SOURCE_ITEMS_INVALID")
        for rank, item in enumerate(ranks, start=1):
            scores[item] = scores.get(item, 0.0) + 1 / (k + rank)
            support.setdefault(item, []).append(sid)
    if len(subjects) != 1:
        return blocked("SUBJECT_CURRENTNESS_MISMATCH")
    items = sorted(scores, key=lambda x: (-scores[x], x))
    return {"status": "FUSED_RANKING_NOT_ADMISSION", "ranking": [
        {"item": x, "score": round(scores[x], 12), "supporting_sources": sorted(support[x])}
        for x in items], "k": k, "sources": len(sources),
        "external_source_readback_required": True, "expertise_certified": False, "cutover_eligible": False}
